package com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch;

import io.pzstorm.storm.core.StormClassTransformer;
import net.bytebuddy.description.method.MethodDescription;
import net.bytebuddy.description.modifier.Visibility;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.implementation.MethodCall;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.pool.TypePool;

/**
 * Adds a no-arg {@code VehiclePart.doInventoryItemStats()} overload that forwards to the real
 * {@code doInventoryItemStats(getInventoryItem(), getMechanicSkillInstaller())} — the exact call
 * vanilla makes on its own repair path ({@code VehiclePart} full-repair, and null-item is the
 * documented reset case there).
 *
 * <p>Why: the 2026-08-26 Vehicle Repair Overhaul update calls {@code part:doInventoryItemStats()}
 * with no arguments from {@code VRO_VehicleCommands.lua}'s {@code _persistInstalledPart}. Kahlua
 * throws "expected 2 arguments, got 0", which aborts {@code doFix} before the part condition is
 * transmitted, before consumables are spent, and before {@code MECHANIC_ACTION_DONE} is sent — so
 * every VRO part repair silently does nothing for the player. With this overload the guarded call
 * {@code if part.doInventoryItemStats then part:doInventoryItemStats() end} resolves and does what
 * VRO intended (recompute condition-based container capacity after a repair).
 *
 * <p>Registered on both JVMs: the broken call site is server-side Lua in MP, but the same file runs
 * in the client JVM in singleplayer/host mode. Inert once VRO fixes its call — Kahlua then
 * dispatches to the 2-arg method by arity as before.
 */
public class VehiclePartStatsOverloadPatch extends StormClassTransformer {

    public VehiclePartStatsOverloadPatch() {
        super("zombie.vehicles.VehiclePart");
    }

    @Override
    public DynamicType.Builder<Object> dynamicType(
            ClassFileLocator locator, TypePool typePool, DynamicType.Builder<Object> builder) {
        TypeDescription part = typePool.describe("zombie.vehicles.VehiclePart").resolve();
        MethodDescription statsWithArgs =
                part.getDeclaredMethods()
                        .filter(
                                ElementMatchers.named("doInventoryItemStats")
                                        .and(ElementMatchers.takesArguments(2)))
                        .getOnly();
        MethodDescription getItem =
                part.getDeclaredMethods()
                        .filter(
                                ElementMatchers.named("getInventoryItem")
                                        .and(ElementMatchers.takesArguments(0)))
                        .getOnly();
        MethodDescription getSkill =
                part.getDeclaredMethods()
                        .filter(
                                ElementMatchers.named("getMechanicSkillInstaller")
                                        .and(ElementMatchers.takesArguments(0)))
                        .getOnly();
        return builder.defineMethod("doInventoryItemStats", void.class, Visibility.PUBLIC)
                .intercept(
                        MethodCall.invoke(statsWithArgs)
                                .withMethodCall(MethodCall.invoke(getItem))
                                .withMethodCall(MethodCall.invoke(getSkill)));
    }
}
