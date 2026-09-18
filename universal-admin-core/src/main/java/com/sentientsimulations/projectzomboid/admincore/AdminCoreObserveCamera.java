package com.sentientsimulations.projectzomboid.admincore;

import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.Lua.LuaManager;
import zombie.characters.Capability;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;

public final class AdminCoreObserveCamera {
    private static final Logger LOGGER = LoggerFactory.getLogger(AdminCoreObserveCamera.class);
    private static String username;
    private static long expires;
    private static long retryAfter;

    @LuaMethod
    public static void follow(String name) {
        if (System.currentTimeMillis() < retryAfter) return;
        username = name;
        expires = System.currentTimeMillis() + 5000;
    }

    @LuaMethod
    public static void stop() {
        username = null;
        expires = 0;
    }

    public static IsoGameCharacter select(IsoGameCharacter original) {
        if (username == null) return original;
        return selectSafely(original, () -> selectActive(original));
    }

    static <T> T selectSafely(T original, Supplier<T> selection) {
        try {
            return selection.get();
        } catch (RuntimeException | LinkageError error) {
            stop();
            retryAfter = System.currentTimeMillis() + 30000;
            LOGGER.warn(
                    "Observe camera disabled after a client error; restoring normal camera", error);
            return original;
        }
    }

    private static IsoGameCharacter selectActive(IsoGameCharacter original) {
        if (username == null || System.currentTimeMillis() > expires) return original;
        IsoPlayer actor = IsoPlayer.getInstance();
        if (actor == null
                || actor.getRole() == null
                || !actor.getRole().hasCapability(Capability.TeleportToPlayer)
                || !actor.isInvisible()
                || !actor.isGodMod()
                || !actor.isNoClip()) return original;
        IsoPlayer target = LuaManager.GlobalObject.getPlayerFromUsername(username);
        if (target == null || target.isDead() || target.getCurrentSquare() == null) return original;
        return target;
    }
}
