package com.sentientsimulations.projectzomboid.avcsmapview;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.IsoPlayer;
import zombie.core.znet.SteamUtils;

/**
 * Server-Lua-callable helper for reading a lossless SteamID string off an {@link IsoPlayer}.
 *
 * <p>Kahlua numbers are double-backed (52-bit mantissa) so a 64-bit SteamID (~2^56) loses its low
 * bits the moment {@code player.getSteamID()} crosses into Lua — {@code tostring(sid)} returns
 * scientific notation, {@code string.format("%d", sid)} returns the already-lossy integer. Callers
 * that need to compare SteamIDs on the server must do it in Java where the {@code long} is intact.
 * This wrapper is that Java hop: {@code AvcsSteamIdApi.getSteamIDString(player)} returns the exact
 * decimal string.
 *
 * <p>Exposed by {@link AvcsSteamIdApiLuaExposerHandler} on the server JVM only.
 */
public final class AvcsSteamIdApi {

    private AvcsSteamIdApi() {}

    @LuaMethod(name = "getSteamIDString")
    public static String getSteamIDString(IsoPlayer player) {
        if (player == null) {
            return "";
        }
        return SteamUtils.convertSteamIDToString(player.getSteamID());
    }
}
