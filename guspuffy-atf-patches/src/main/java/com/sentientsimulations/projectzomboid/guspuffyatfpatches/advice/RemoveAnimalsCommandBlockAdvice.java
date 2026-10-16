package com.sentientsimulations.projectzomboid.guspuffyatfpatches.advice;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import net.bytebuddy.asm.Advice;
import zombie.core.raknet.UdpConnection;

public class RemoveAnimalsCommandBlockAdvice {

    @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
    public static boolean onEnter(
            @Advice.Argument(0) UdpConnection connection, @Advice.Argument(1) String subsystem) {
        if (!"animals".equalsIgnoreCase(subsystem)) {
            return false;
        }
        LOGGER.warn(
                "RemoveAnimalsCommandBlockPatch: blocked /remove animals from {}",
                connection == null ? "console" : connection.usernames[0]);
        return true;
    }

    @Advice.OnMethodExit
    public static void onExit(
            @Advice.Enter boolean blocked, @Advice.Return(readOnly = false) String result) {
        if (blocked) {
            result = "Removing all animals is disabled on this server";
        }
    }
}
