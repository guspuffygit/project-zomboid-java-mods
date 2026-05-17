package com.sentientsimulations.projectzomboid.avcsmapview;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Intercepts the 5-arg {@code LuaEventManager.triggerEvent(String, Object, Object, Object, Object)}
 * on the dedicated server and skips the dispatch when the event is an AVCS-blocked {@code
 * vehicle.remove} {@code OnClientCommand}.
 *
 * <p>The advice fires for the gated wrapper that Storm's {@code
 * GameServerReceiveClientCommandPatch} substitutes into {@code GameServer.receiveClientCommand}, as
 * well as any other caller of the same overload. {@link VehicleRemoveSecurity#shouldBlock} filters
 * on event/module/command, so non-vehicle-remove dispatches pass through untouched.
 */
public class LuaEventManagerVehicleRemovePatch extends StormClassTransformer {

    public LuaEventManagerVehicleRemovePatch() {
        super("zombie.Lua.LuaEventManager");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        return builder.visit(
                Advice.to(VehicleRemoveAdvice.class)
                        .on(
                                ElementMatchers.named("triggerEvent")
                                        .and(ElementMatchers.takesArguments(5))));
    }

    public static class VehicleRemoveAdvice {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean before(
                @Advice.Argument(0) String event,
                @Advice.Argument(1) Object module,
                @Advice.Argument(2) Object command,
                @Advice.Argument(3) Object player,
                @Advice.Argument(4) Object args) {
            return VehicleRemoveSecurity.shouldBlock(event, module, command, player, args);
        }
    }
}
