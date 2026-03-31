package com.sentientsimulations.projectzomboid.extralogging.patch;

import com.sentientsimulations.projectzomboid.extralogging.events.PlayerDiedEvent;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.iso.objects.IsoDeadBody;

/** Patches {@link zombie.characters.IsoPlayer} to dispatch an event when a player dies. */
public class IsoPlayerPatch extends StormClassTransformer {

    public IsoPlayerPatch() {
        super("zombie.characters.IsoPlayer");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(Advice.to(OnDiedAdvice.class).on(ElementMatchers.named("onDied")));
    }

    public static class OnDiedAdvice {

        @Advice.OnMethodEnter(suppress = Throwable.class)
        public static void beforeOnDied(
                @Advice.This IsoPlayer player,
                @Advice.Argument(0) IsoGameCharacter sender,
                @Advice.Argument(1) IsoDeadBody body) {

            PlayerDiedEvent event = new PlayerDiedEvent(player, body);
            StormEventDispatcher.dispatchEvent(event);
        }
    }
}
