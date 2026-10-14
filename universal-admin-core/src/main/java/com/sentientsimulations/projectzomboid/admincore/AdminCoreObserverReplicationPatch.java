package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import java.lang.reflect.Modifier;
import java.util.List;
import net.bytebuddy.asm.AsmVisitorWrapper;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/** Adds the same bounded read interest to Storm's outgoing object replication helpers. */
public final class AdminCoreObserverReplicationPatch extends StormClassTransformer {
    static final String MARKER = "uacObserverReplicationV1";
    static final List<String> TARGETS =
            List.of(
                    "io.pzstorm.storm.connection.StormGameEntityBroadcastGate",
                    "io.pzstorm.storm.connection.StormSyncIsoObjectGate");
    private final String target;

    public AdminCoreObserverReplicationPatch(String target) {
        super(target);
        this.target = target;
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
        if (target.equals(TARGETS.getFirst()))
            return calls(
                    builder,
                    pool,
                    "run",
                    "(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;Z)Z",
                    1);
        builder =
                calls(
                        builder,
                        pool,
                        "isRelevant",
                        "(Lzombie/core/raknet/UdpConnection;Lzombie/iso/IsoObject;)Z",
                        1);
        return calls(builder, pool, "runLightSwitch", "(Ljava/lang/Object;Ljava/lang/Object;)Z", 0);
    }

    private DynamicType.Builder<Object> calls(
            DynamicType.Builder<Object> builder,
            TypePool pool,
            String name,
            String descriptor,
            int entityArgument) {
        var matcher = ElementMatchers.named(name).and(ElementMatchers.hasDescriptor(descriptor));
        if (pool.describe(target).resolve().getDeclaredMethods().filter(matcher).size() != 1)
            throw new IllegalStateException(
                    "Unsupported observer replication signature "
                            + target
                            + "."
                            + name
                            + descriptor);
        return builder.visit(
                new AsmVisitorWrapper.ForDeclaredMethods()
                        .writerFlags(ClassWriter.COMPUTE_MAXS)
                        .method(
                                matcher,
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
                                                        && called.equals("isRelevantTo")
                                                        && desc.equals("(FF)Z")) {
                                                    // The helper already checks full connection and
                                                    // source exclusion.
                                                    // Its original entity argument supplies the
                                                    // authoritative floor.
                                                    super.visitVarInsn(
                                                            Opcodes.ALOAD, entityArgument);
                                                    super.visitMethodInsn(
                                                            Opcodes.INVOKESTATIC,
                                                            "com/sentientsimulations/projectzomboid/admincore/AdminCoreObserverInterest",
                                                            "replicationRelevant",
                                                            "(Lzombie/core/raknet/UdpConnection;FFLjava/lang/Object;)Z",
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
                                                            "Observer replication call count: "
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
