package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import java.lang.reflect.Modifier;
import net.bytebuddy.asm.AsmVisitorWrapper;
import net.bytebuddy.description.method.MethodDescription;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.implementation.Implementation;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/** Keep the native matrix calculation, substituting only its viewer coordinates. */
public final class AdminCoreObserveProjectionPatch extends StormClassTransformer {
    static final String MARKER = "uacObserverProjectionV1";

    public AdminCoreObserveProjectionPatch() {
        super("zombie.iso.PlayerCamera");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        return builder.defineField(
                        MARKER, boolean.class, Modifier.PUBLIC | Modifier.STATIC | Modifier.FINAL)
                .value(true)
                .visit(
                        new AsmVisitorWrapper.ForDeclaredMethods()
                                .writerFlags(ClassWriter.COMPUTE_MAXS)
                                .method(
                                        ElementMatchers.namedOneOf(
                                                "calculateModelViewProjection",
                                                "calculateFixForJigglyModels"),
                                        new Coordinates()));
    }

    private static final class Coordinates
            implements AsmVisitorWrapper.ForDeclaredMethods.MethodVisitorWrapper {
        @Override
        public MethodVisitor wrap(
                TypeDescription type,
                MethodDescription method,
                MethodVisitor visitor,
                Implementation.Context context,
                TypePool pool,
                int writerFlags,
                int readerFlags) {
            return new MethodVisitor(Opcodes.ASM9, visitor) {
                @Override
                public void visitMethodInsn(
                        int opcode, String owner, String name, String descriptor, boolean itf) {
                    super.visitMethodInsn(opcode, owner, name, descriptor, itf);
                    int axis =
                            owner.equals("zombie/characters/IsoGameCharacter")
                                            && descriptor.equals("()F")
                                    ? switch (name) {
                                        case "getX" -> 0;
                                        case "getY" -> 1;
                                        default -> -1;
                                    }
                                    : owner.equals("zombie/iso/IsoCamera$FrameState")
                                                    && name.equals("calculateCameraZ")
                                                    && descriptor.equals(
                                                            "(Lzombie/characters/IsoGameCharacter;)F")
                                            ? 2
                                            : -1;
                    if (axis < 0) return;
                    super.visitVarInsn(Opcodes.ALOAD, 0);
                    super.visitFieldInsn(
                            Opcodes.GETFIELD, "zombie/iso/PlayerCamera", "playerIndex", "I");
                    super.visitInsn(Opcodes.ICONST_0 + axis);
                    super.visitMethodInsn(
                            Opcodes.INVOKESTATIC,
                            "com/sentientsimulations/projectzomboid/admincore/AdminCoreObserveCamera",
                            "projectionCoordinate",
                            "(FII)F",
                            false);
                }
            };
        }
    }
}
