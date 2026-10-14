package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.asm.AsmVisitorWrapper;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.Label;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/** Narrow B42.21 call-site patches; original native creation/connection methods remain intact. */
public final class AdminCoreRespawnPatch extends StormClassTransformer {
    private static final String BASE = "com/sentientsimulations/projectzomboid/admincore/";
    private final String target;

    public AdminCoreRespawnPatch(String target) {
        super(target);
        this.target = target;
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        if (target.equals("zombie.network.GameServer")) {
            require(
                    pool,
                    "receiveClientCommand",
                    "(Lzombie/core/network/ByteBufferReader;Lzombie/core/raknet/UdpConnection;S)V",
                    true);
            require(
                    pool,
                    "receivePlayerConnect",
                    "(Lzombie/core/network/ByteBufferReader;Lzombie/network/IConnection;Ljava/lang/String;)V",
                    true);
            return advice(
                            advice(builder, locator, pool, "Command", "receiveClientCommand"),
                            locator,
                            pool,
                            "Connect",
                            "receivePlayerConnect")
                    .visit(visitor("receivePlayerConnect", Mode.CONNECT));
        }
        if (target.equals("zombie.network.packets.character.CreatePlayerPacket")) {
            require(
                    pool,
                    "processServer",
                    "(Lzombie/network/PacketTypes$PacketType;Lzombie/core/raknet/UdpConnection;)V",
                    false);
            return advice(builder, locator, pool, "Create", "processServer")
                    .visit(visitor("processServer", Mode.CREATE));
        }
        if (target.equals("zombie.network.PacketTypes$PacketType")) {
            require(
                    pool,
                    "onClientLoadingPacket",
                    "(Lzombie/core/network/ByteBufferReader;)Z",
                    false);
            return advice(builder, locator, pool, "Loading", "onClientLoadingPacket");
        }
        if (target.equals("zombie.network.GameClient")) {
            require(
                    pool,
                    "receiveClientCommand",
                    "(Lzombie/core/network/ByteBufferReader;S)V",
                    true);
            return advice(builder, locator, pool, "Response", "receiveClientCommand");
        }
        if (target.equals("zombie.iso.IsoWorld")) {
            require(pool, "init", "()V", false);
            return builder.visit(visitor("init", Mode.WORLD));
        }
        throw new IllegalArgumentException(target);
    }

    private void require(TypePool pool, String method, String descriptor, boolean isStatic) {
        var methods =
                pool.describe(target)
                        .resolve()
                        .getDeclaredMethods()
                        .filter(
                                ElementMatchers.named(method)
                                        .and(ElementMatchers.hasDescriptor(descriptor)));
        if (methods.size() != 1 || methods.getOnly().isStatic() != isStatic)
            throw new IllegalStateException(
                    "Unsupported native respawn signature: " + target + "." + method + descriptor);
    }

    private static DynamicType.Builder<Object> advice(
            DynamicType.Builder<Object> builder,
            ClassFileLocator locator,
            TypePool pool,
            String nested,
            String method) {
        return builder.visit(
                Advice.to(
                                pool.describe(
                                                BASE.replace('/', '.')
                                                        + "AdminCoreRespawnAdvice$"
                                                        + nested)
                                        .resolve(),
                                locator)
                        .on(ElementMatchers.named(method)));
    }

    private enum Mode {
        CREATE,
        CONNECT,
        WORLD
    }

    private static AsmVisitorWrapper visitor(String method, Mode mode) {
        return new AsmVisitorWrapper.ForDeclaredMethods()
                .method(
                        ElementMatchers.named(method),
                        (type, description, delegate, context, pool, writerFlags, readerFlags) ->
                                new Calls(delegate, mode))
                .writerFlags(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
    }

    private static final class Calls extends MethodVisitor {
        private final Mode mode;
        private int coordinates;
        private int playerPositions;
        private int marks;
        private int acceptance;
        private int optionReads;
        private int legacyReads;

        Calls(MethodVisitor delegate, Mode mode) {
            super(Opcodes.ASM9, delegate);
            this.mode = mode;
        }

        @Override
        public void visitFieldInsn(int opcode, String owner, String name, String descriptor) {
            if (mode == Mode.CREATE
                    && opcode == Opcodes.PUTSTATIC
                    && owner.equals("zombie/iso/IsoChunkMap")
                    && name.matches("world[XYZ]a")) {
                super.visitInsn(
                        name.equals("worldXa")
                                ? Opcodes.ICONST_0
                                : name.equals("worldYa") ? Opcodes.ICONST_1 : Opcodes.ICONST_2);
                invoke("AdminCoreRespawnServer", "coordinate", "(II)I");
                coordinates++;
            }
            super.visitFieldInsn(opcode, owner, name, descriptor);
        }

        @Override
        public void visitMethodInsn(
                int opcode, String owner, String name, String descriptor, boolean isInterface) {
            boolean connectionLoad =
                    mode == Mode.CONNECT
                            && !isInterface
                            && (opcode == Opcodes.INVOKEVIRTUAL
                                            && owner.equals("zombie/savefile/ServerPlayerDB")
                                            && name.equals("serverLoadNetworkCharacter")
                                            && descriptor.equals(
                                                    "(ILjava/lang/String;)Lzombie/characters/IsoPlayer;")
                                    || opcode == Opcodes.INVOKESTATIC
                                            && owner.equals(
                                                    "com/sentientsimulations/projectzomboid/securitypatches/patch/PienZInvisibilityProbePatch")
                                            && name.equals("loadAndProbe")
                                            && descriptor.equals(
                                                    "(Lzombie/savefile/ServerPlayerDB;ILjava/lang/String;)Lzombie/characters/IsoPlayer;"));
            if (connectionLoad) {
                // Copy the actual int/String call arguments. Other Storm advice can move native
                // local variables, so no local slot number is read by this guard. The anti-cheat
                // wrapper keeps the same receiver/int/String stack, regardless of patch order.
                super.visitInsn(Opcodes.DUP2);
                invoke("AdminCoreRespawnServer", "captureLoad", "(ILjava/lang/String;)V");
            }
            boolean option =
                    mode == Mode.WORLD
                            && name.equals("getValue")
                            && descriptor.equals("()Ljava/lang/String;")
                            && owner.equals("zombie/network/ServerOptions$StringServerOption");
            if (option) super.visitInsn(Opcodes.DUP);
            if (mode == Mode.CREATE
                    && owner.equals("zombie/characters/IsoPlayer")
                    && descriptor.equals("(F)F")
                    && (name.equals("setX") || name.equals("setY") || name.equals("setZ"))) {
                super.visitInsn(
                        name.equals("setX")
                                ? Opcodes.ICONST_0
                                : name.equals("setY") ? Opcodes.ICONST_1 : Opcodes.ICONST_2);
                invoke("AdminCoreRespawnServer", "position", "(FI)F");
                playerPositions++;
            }
            if (mode == Mode.CREATE
                    && owner.equals("zombie/Lua/LuaEventManager")
                    && name.equals("triggerEvent")) {
                super.visitVarInsn(Opcodes.ALOAD, 0);
                super.visitFieldInsn(
                        Opcodes.GETFIELD,
                        "zombie/network/packets/character/CreatePlayerPacket",
                        "player",
                        "Lzombie/characters/IsoPlayer;");
                invoke("AdminCoreRespawnServer", "mark", "(Lzombie/characters/IsoPlayer;)V");
                marks++;
            }
            super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
            if ((mode == Mode.CREATE || mode == Mode.WORLD)
                    && owner.equals("zombie/iso/areas/SafeHouse")
                    && name.equals("isRespawnInSafehouse")
                    && descriptor.equals("(Ljava/lang/String;)Z")) {
                invoke(
                        mode == Mode.CREATE ? "AdminCoreRespawnServer" : "AdminCoreRespawnBridge",
                        "legacyPreference",
                        "(Z)Z");
                legacyReads++;
            }
            if (option) {
                invoke(
                        "AdminCoreRespawnBridge",
                        "spawnPointOption",
                        "(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/String;");
                optionReads++;
            }
            if (connectionLoad) {
                super.visitInsn(Opcodes.DUP);
                invoke(
                        "AdminCoreRespawnServer",
                        "acceptLoaded",
                        "(Lzombie/characters/IsoPlayer;)Z");
                Label valid = new Label();
                super.visitJumpInsn(Opcodes.IFNE, valid);
                super.visitInsn(Opcodes.POP);
                // Explicit early-return cleanup also works if an outer transformer does not
                // route this injected return through Advice.OnMethodExit. Cleanup is idempotent.
                invoke("AdminCoreRespawnServer", "clearConnect", "()V");
                super.visitInsn(Opcodes.RETURN);
                super.visitLabel(valid);
                acceptance++;
            }
        }

        private void invoke(String type, String method, String descriptor) {
            super.visitMethodInsn(Opcodes.INVOKESTATIC, BASE + type, method, descriptor, false);
        }

        @Override
        public void visitEnd() {
            if (mode == Mode.CREATE
                            && (coordinates != 3
                                    || playerPositions != 3
                                    || marks != 1
                                    || legacyReads != 1)
                    || mode == Mode.CONNECT && acceptance != 2
                    || mode == Mode.WORLD && (optionReads < 2 || legacyReads != 2))
                throw new IllegalStateException(
                        "Unsupported native respawn method layout: "
                                + mode
                                + "/"
                                + coordinates
                                + "/"
                                + playerPositions
                                + "/"
                                + marks
                                + "/"
                                + acceptance
                                + "/"
                                + optionReads
                                + "/"
                                + legacyReads);
            super.visitEnd();
        }
    }
}
