package com.sentientsimulations.projectzomboid.admincore;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.Lua.LuaManager;
import zombie.characters.Capability;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;

public final class AdminCoreObserveCamera {
    private static String username;
    private static long expires;

    @LuaMethod
    public static void follow(String name) {
        username = name;
        expires = System.currentTimeMillis() + 5000;
    }

    @LuaMethod
    public static void stop() {
        username = null;
        expires = 0;
    }

    public static IsoGameCharacter select(IsoGameCharacter original) {
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
