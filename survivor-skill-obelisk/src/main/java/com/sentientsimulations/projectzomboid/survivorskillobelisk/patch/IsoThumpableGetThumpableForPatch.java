package com.sentientsimulations.projectzomboid.survivorskillobelisk.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.implementation.bytecode.assign.Assigner;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Forces {@code IsoThumpable.getThumpableFor(IsoGameCharacter)} to return null for obelisks.
 * Brush-tool placement runs the tiles through {@code ISMoveableSpriteProps:placeMoveableInternal},
 * and the obelisk sprites carry the {@code solid} flag, so they land in the world as {@code
 * IsoThumpable} with {@code isThumpable=true} — zombie thump damage ({@code Thump}) and player
 * melee damage ({@code WeaponHit}) both gate on this method server-side, so a null return makes
 * zombies path around obelisks and turns weapon hits into no-ops. The two-argument overload
 * delegates here for anything that is not a window.
 */
public class IsoThumpableGetThumpableForPatch extends StormClassTransformer {

    public IsoThumpableGetThumpableForPatch() {
        super("zombie.iso.objects.IsoThumpable");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(GetThumpableForAdvice.class)
                        .on(
                                ElementMatchers.named("getThumpableFor")
                                        .and(ElementMatchers.takesArguments(1))));
    }

    public static class GetThumpableForAdvice {

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void onExit(
                @Advice.This Object self,
                @Advice.Return(readOnly = false, typing = Assigner.Typing.DYNAMIC) Object result) {
            if (result != null && ObeliskProtection.isProtectedObject(self)) {
                result = null;
            }
        }
    }
}
