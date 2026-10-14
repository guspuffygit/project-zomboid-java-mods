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

/** Read-only lighting views at the native render gates; update/simulation paths are unchanged. */
public final class AdminCoreObserveTerrainPatch extends StormClassTransformer {
    static final String MARKER = "uacObserverTerrainRenderV1";
    static final List<String> TARGETS =
            List.of(
                    "zombie.iso.fboRenderChunk.FBORenderCell",
                    "zombie.iso.IsoCell",
                    "zombie.iso.IsoWater",
                    "zombie.iso.IsoGridSquare");
    private final String target;

    public AdminCoreObserveTerrainPatch(String target) {
        super(target);
        this.target = target;
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool pool, DynamicType.Builder<Object> builder) {
        if (!TARGETS.contains(target)) throw new IllegalArgumentException(target);
        boolean square = target.equals("zombie.iso.IsoGridSquare");
        String[] methods =
                square
                        ? new String[] {
                            "DoCutawayShader",
                            "performDrawWall",
                            "renderCharacters",
                            "renderDeferredCharacters",
                            "renderFloorInternal",
                            "renderMinusFloor"
                        }
                        : target.equals("zombie.iso.fboRenderChunk.FBORenderCell")
                                ? new String[] {
                                    "invalidateAll",
                                    "checkNewlyOnScreenChunks",
                                    "renderOneChunk",
                                    "renderOneChunk_TranslucentFloor",
                                    "renderOneChunk_Translucent"
                                }
                                : target.equals("zombie.iso.IsoWater")
                                        ? new String[] {"render", "renderShore"}
                                        : new String[] {"performRenderTiles"};
        for (String method : methods) {
            if (pool.describe(target)
                            .resolve()
                            .getDeclaredMethods()
                            .filter(ElementMatchers.named(method))
                            .size()
                    != 1)
                throw new IllegalStateException(
                        "Unsupported terrain render method " + target + "." + method);
        }
        return builder.defineField(
                        MARKER, boolean.class, Modifier.PUBLIC | Modifier.STATIC | Modifier.FINAL)
                .value(true)
                .visit(
                        new AsmVisitorWrapper.ForDeclaredMethods()
                                .writerFlags(ClassWriter.COMPUTE_MAXS)
                                .method(
                                        ElementMatchers.namedOneOf(methods),
                                        (type,
                                                method,
                                                delegate,
                                                context,
                                                types,
                                                writerFlags,
                                                readerFlags) ->
                                                new MethodVisitor(Opcodes.ASM9, delegate) {
                                                    private int reads;

                                                    @Override
                                                    public void visitFieldInsn(
                                                            int opcode,
                                                            String owner,
                                                            String name,
                                                            String descriptor) {
                                                        boolean match =
                                                                opcode == Opcodes.GETFIELD
                                                                        && owner.equals(
                                                                                square
                                                                                        ? "zombie/iso/IsoGridSquare"
                                                                                        : "zombie/iso/IsoChunk")
                                                                        && name.equals(
                                                                                square
                                                                                        ? "lightInfo"
                                                                                        : "lightingNeverDone")
                                                                        && descriptor.equals(
                                                                                square
                                                                                        ? "[Lzombie/core/textures/ColorInfo;"
                                                                                        : "[Z");
                                                        if (match) super.visitInsn(Opcodes.DUP);
                                                        super.visitFieldInsn(
                                                                opcode, owner, name, descriptor);
                                                        if (match) {
                                                            super.visitMethodInsn(
                                                                    Opcodes.INVOKESTATIC,
                                                                    "com/sentientsimulations/projectzomboid/admincore/AdminCoreObserveRender",
                                                                    square
                                                                            ? "lightInfo"
                                                                            : "lightingPending",
                                                                    "(L"
                                                                            + owner
                                                                            + ";"
                                                                            + descriptor
                                                                            + ")"
                                                                            + descriptor,
                                                                    false);
                                                            reads++;
                                                        }
                                                    }

                                                    @Override
                                                    public void visitEnd() {
                                                        if (reads != 1)
                                                            throw new IllegalStateException(
                                                                    "Terrain render read count "
                                                                            + target
                                                                            + "."
                                                                            + method.getName()
                                                                            + "="
                                                                            + reads);
                                                        super.visitEnd();
                                                    }
                                                }));
    }
}
