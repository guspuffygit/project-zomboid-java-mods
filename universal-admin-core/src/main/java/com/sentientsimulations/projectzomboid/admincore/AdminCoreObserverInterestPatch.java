package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import java.lang.reflect.Modifier;
import java.util.List;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.asm.AsmVisitorWrapper;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Only outgoing replication and chunk reads gain interest; combat/transaction relevance is
 * untouched.
 */
public final class AdminCoreObserverInterestPatch extends StormClassTransformer {
    static final String MARKER = "uacObserverInterestV1";
    static final List<String> TARGETS =
            List.of(
                    "zombie.network.PlayerDownloadServer",
                    "zombie.network.ServerMap",
                    "zombie.network.packets.character.PlayerPacket",
                    "zombie.network.packets.INetworkPacket",
                    "zombie.vehicles.VehicleManager",
                    "zombie.popman.NetworkZombiePacker",
                    "zombie.popman.animal.AnimalSynchronizationManager");
    private static final String BASE = "com.sentientsimulations.projectzomboid.admincore.";
    private final String target;

    public AdminCoreObserverInterestPatch(String target) {
        super(target);
        this.target = target;
    }

    private void require(TypePool pool, String name, String descriptor) {
        if (pool.describe(target)
                        .resolve()
                        .getDeclaredMethods()
                        .filter(
                                ElementMatchers.named(name)
                                        .and(ElementMatchers.hasDescriptor(descriptor)))
                        .size()
                != 1)
            throw new IllegalStateException(
                    "Unsupported observer native signature " + target + "." + name + descriptor);
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        if (!TARGETS.contains(target)) throw new IllegalArgumentException(target);
        builder =
                builder.defineField(
                                MARKER,
                                boolean.class,
                                Modifier.PUBLIC | Modifier.STATIC | Modifier.FINAL)
                        .value(true);
        if (target.equals("zombie.network.PlayerDownloadServer")) {
            require(pool, "isRequestInRange", "(II)Z");
            return advice(builder, locator, pool, "Chunk", "isRequestInRange");
        }
        if (target.equals("zombie.network.ServerMap")) {
            require(pool, "preupdate", "()V");
            require(pool, "outsidePlayerInfluence", "(Lzombie/network/ServerMap$ServerCell;)Z");
            return advice(
                    advice(builder, locator, pool, "Retain", "preupdate"),
                    locator,
                    pool,
                    "Outside",
                    "outsidePlayerInfluence");
        }
        if (target.equals("zombie.network.packets.character.PlayerPacket"))
            return calls(
                    builder,
                    pool,
                    "processServer",
                    "(Lzombie/network/PacketTypes$PacketType;Lzombie/core/raknet/UdpConnection;)V",
                    false);
        if (target.equals("zombie.vehicles.VehicleManager"))
            return calls(
                    builder, pool, "sendVehicles", "(Lzombie/core/raknet/UdpConnection;)V", false);
        if (target.equals("zombie.popman.NetworkZombiePacker"))
            return calls(
                    builder,
                    pool,
                    "getZombieData",
                    "(Lzombie/core/raknet/UdpConnection;Lzombie/network/packets/character/ZombieSynchronizationPacket;)I",
                    true);
        if (target.equals("zombie.popman.animal.AnimalSynchronizationManager"))
            return calls(
                    builder,
                    pool,
                    "sendUpdateToClient",
                    "(Lzombie/core/raknet/UdpConnection;ZLjava/util/HashSet;)V",
                    true);
        builder =
                calls(
                        builder,
                        pool,
                        "sendToRelativeClients",
                        "(Lzombie/network/PacketTypes$PacketType;Lzombie/core/raknet/UdpConnection;FF)V",
                        false);
        return calls(
                builder,
                pool,
                "sendToRelative",
                "(Lzombie/network/PacketTypes$PacketType;Lzombie/network/IConnection;FF[Ljava/lang/Object;)V",
                false);
    }

    private static DynamicType.Builder<Object> advice(
            DynamicType.Builder<Object> builder,
            ClassFileLocator locator,
            TypePool pool,
            String nested,
            String name) {
        return builder.visit(
                Advice.to(
                                pool.describe(BASE + "AdminCoreObserverInterestAdvice$" + nested)
                                        .resolve(),
                                locator)
                        .on(ElementMatchers.named(name)));
    }

    private DynamicType.Builder<Object> calls(
            DynamicType.Builder<Object> builder,
            TypePool pool,
            String name,
            String descriptor,
            boolean distance) {
        require(pool, name, descriptor);
        return builder.visit(
                new AsmVisitorWrapper.ForDeclaredMethods()
                        .method(
                                ElementMatchers.named(name)
                                        .and(ElementMatchers.hasDescriptor(descriptor)),
                                (type,
                                        method,
                                        delegate,
                                        context,
                                        types,
                                        writerFlags,
                                        readerFlags) ->
                                        new MethodVisitor(Opcodes.ASM9, delegate) {
                                            private int count;

                                            @Override
                                            public void visitMethodInsn(
                                                    int opcode,
                                                    String owner,
                                                    String called,
                                                    String desc,
                                                    boolean itf) {
                                                if (opcode == Opcodes.INVOKEVIRTUAL
                                                        && owner.equals(
                                                                "zombie/core/raknet/UdpConnection")
                                                        && called.equals(
                                                                distance
                                                                        ? "RelevantTo"
                                                                        : "isRelevantTo")
                                                        && desc.equals(
                                                                distance ? "(FFF)Z" : "(FF)Z")) {
                                                    super.visitMethodInsn(
                                                            Opcodes.INVOKESTATIC,
                                                            BASE.replace('.', '/')
                                                                    + "AdminCoreObserverInterest",
                                                            distance
                                                                    ? "relevantWithin"
                                                                    : "relevant",
                                                            "(Lzombie/core/raknet/UdpConnection;"
                                                                    + (distance ? "FFF)Z" : "FF)Z"),
                                                            false);
                                                    count++;
                                                } else
                                                    super.visitMethodInsn(
                                                            opcode, owner, called, desc, itf);
                                            }

                                            @Override
                                            public void visitEnd() {
                                                if (count != 1)
                                                    throw new IllegalStateException(
                                                            "Observer outgoing relevance call count: "
                                                                    + target
                                                                    + "."
                                                                    + name
                                                                    + "="
                                                                    + count);
                                                super.visitEnd();
                                            }
                                        }));
    }
}
