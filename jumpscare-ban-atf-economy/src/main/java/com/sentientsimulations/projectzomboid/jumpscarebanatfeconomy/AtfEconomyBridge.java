package com.sentientsimulations.projectzomboid.jumpscarebanatfeconomy;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoPlayer;

/**
 * Reflective bridge to the ATF Economy mod's {@code ATFEconomyApi.deduct} and {@code
 * GrantBridge.processGrant}. The economy jar is not published to any Maven repository, so this mod
 * cannot compile against it; at runtime all Storm mod jars share one class loader, so the classes
 * resolve whenever the economy mod is installed. The deduct is server-authoritative and atomic —
 * the balance check and the ledger insert happen in one SQLite transaction, and insufficient funds
 * comes back as {@code ok=false, reason=INSUFFICIENT_BALANCE} rather than an exception. Grants go
 * through {@code GrantBridge} rather than the Lua-facing {@code ATFEconomyApi.grant} because the
 * bridge takes a bare username + steamId, so the recipient does not need to be online.
 */
final class AtfEconomyBridge {

    static final String ECONOMY_UNAVAILABLE = "ECONOMY_UNAVAILABLE";
    static final String ECONOMY_ERROR = "ECONOMY_ERROR";

    private static final String API_CLASS =
            "com.afterthefallpz.projectzomboid.economy.lua.ATFEconomyApi";
    private static final String GRANT_BRIDGE_CLASS =
            "com.afterthefallpz.projectzomboid.economy.bridge.GrantBridge";
    private static final String GRANT_REQUEST_CLASS =
            "com.afterthefallpz.projectzomboid.economy.model.request.GrantRequest";

    private static volatile @Nullable Method deductMethod;
    private static volatile @Nullable Method processGrantMethod;
    private static volatile @Nullable Constructor<?> grantRequestConstructor;

    private AtfEconomyBridge() {}

    record DeductResult(boolean ok, @Nullable String reason) {}

    record GrantResult(boolean ok, @Nullable String reason) {}

    static DeductResult deduct(IsoPlayer player, String currency, double amount, String reason) {
        Method method = resolveDeduct();
        if (method == null) {
            return new DeductResult(false, ECONOMY_UNAVAILABLE);
        }
        try {
            KahluaTable result =
                    (KahluaTable) method.invoke(null, player, currency, amount, reason);
            if (result == null) {
                return new DeductResult(false, ECONOMY_ERROR);
            }
            boolean ok = Boolean.TRUE.equals(result.rawget("ok"));
            Object failureReason = result.rawget("reason");
            return new DeductResult(ok, failureReason == null ? null : failureReason.toString());
        } catch (Throwable t) {
            LOGGER.error("[JumpscareBanEconomy] ATFEconomyApi.deduct call failed", t);
            return new DeductResult(false, ECONOMY_ERROR);
        }
    }

    static GrantResult grant(
            String username, long steamId, String currency, double amount, String reason) {
        if (!resolveGrant()) {
            return new GrantResult(false, ECONOMY_UNAVAILABLE);
        }
        try {
            Object request =
                    grantRequestConstructor.newInstance(
                            username, steamId, currency, amount, reason);
            Object response = processGrantMethod.invoke(null, request);
            if (response == null) {
                return new GrantResult(false, ECONOMY_ERROR);
            }
            boolean ok = Boolean.TRUE.equals(response.getClass().getMethod("ok").invoke(response));
            Object failureReason = response.getClass().getMethod("reason").invoke(response);
            return new GrantResult(ok, failureReason == null ? null : failureReason.toString());
        } catch (Throwable t) {
            LOGGER.error("[JumpscareBanEconomy] GrantBridge.processGrant call failed", t);
            return new GrantResult(false, ECONOMY_ERROR);
        }
    }

    private static boolean resolveGrant() {
        if (processGrantMethod != null && grantRequestConstructor != null) {
            return true;
        }
        try {
            ClassLoader loader = AtfEconomyBridge.class.getClassLoader();
            Class<?> requestClass = Class.forName(GRANT_REQUEST_CLASS, true, loader);
            Class<?> bridgeClass = Class.forName(GRANT_BRIDGE_CLASS, true, loader);
            grantRequestConstructor =
                    requestClass.getConstructor(
                            String.class, long.class, String.class, double.class, String.class);
            processGrantMethod = bridgeClass.getMethod("processGrant", requestClass);
            return true;
        } catch (ClassNotFoundException | NoSuchMethodException e) {
            LOGGER.warn(
                    "[JumpscareBanEconomy] ATF Economy grant API not available: {}", e.toString());
            return false;
        }
    }

    private static @Nullable Method resolveDeduct() {
        Method method = deductMethod;
        if (method != null) {
            return method;
        }
        try {
            Class<?> api = Class.forName(API_CLASS, true, AtfEconomyBridge.class.getClassLoader());
            method =
                    api.getMethod(
                            "deduct", IsoPlayer.class, String.class, double.class, String.class);
            deductMethod = method;
            return method;
        } catch (ClassNotFoundException | NoSuchMethodException e) {
            LOGGER.warn("[JumpscareBanEconomy] ATF Economy API not available: {}", e.toString());
            return null;
        }
    }
}
