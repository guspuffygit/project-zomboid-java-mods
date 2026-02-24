package com.sentientsimulations.projectzomboid.atfsettlements;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnGetWorldMapFilterOptions;
import io.pzstorm.storm.event.zomboid.OnWorldMapRenderEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.lua.LuaManagerUtils;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.wrappers.ui.PersistedBooleanConfigOption;
import zombie.config.BooleanConfigOption;
import zombie.core.math.PZMath;
import zombie.core.textures.Texture;

public class AfterTheFallSettlementsMod implements ZomboidMod {
    private final Zones zones = new Zones();

    private final BooleanConfigOption settlementsOption =
            new PersistedBooleanConfigOption("After The Fall Settlements", true);
    private final BooleanConfigOption smallAreasOption =
            new PersistedBooleanConfigOption("After The Fall Small Areas", false);
    private final BooleanConfigOption largeZonesOption =
            new PersistedBooleanConfigOption("After The Fall Large Zones", false);
    private final BooleanConfigOption moddedMapsOption =
            new PersistedBooleanConfigOption("After The Fall Modded Maps", false);
    private Boolean atfModLoaded = false;

    @Override
    public void registerEventHandlers() {
        LOGGER.debug(
                "Registering event handler for com.sentientsimulations.projectzomboid.atfsettlements.AfterTheFallSettlementsMod");
        StormEventDispatcher.registerEventHandler(this);
    }

    @SubscribeEvent
    public void onResetLuaEvent(OnZomboidGlobalsLoadEvent event) {
        Object atfFunction = LuaManagerUtils.getEnv().rawget("ATF_SetGlobalLighting");

        atfModLoaded = (atfFunction != null);
    }

    @SubscribeEvent
    public void onGetWorldMapFilterOptions(OnGetWorldMapFilterOptions event) {
        if (!atfModLoaded) {
            return;
        }

        LOGGER.debug("Adding option {}", event.getName());
        event.addOption(settlementsOption);
        event.addOption(smallAreasOption);
        event.addOption(largeZonesOption);
        event.addOption(moddedMapsOption);
    }

    @SubscribeEvent
    public void onGameMapRender(OnWorldMapRenderEvent event) {
        if (!atfModLoaded) {
            return;
        }

        if (settlementsOption.getValue()) {
            zones.settlements()
                    .values()
                    .forEach((zone) -> renderZone(event, zone, 0.635D, 0.286D, 0.639D, 1.0D));
        }

        if (smallAreasOption.getValue()) {
            zones.individualSmallAreas()
                    .values()
                    .forEach((zone) -> renderZone(event, zone, 0.812D, 0.765D, 0.161D, 1.0D));
        }

        if (largeZonesOption.getValue()) {
            zones.largeZones()
                    .values()
                    .forEach((zone) -> renderZone(event, zone, 0.0D, 0.341D, 1.0D, 0.341D));
        }

        if (moddedMapsOption.getValue()) {
            zones.moddedMaps()
                    .values()
                    .forEach((zone) -> renderZone(event, zone, 0.0D, 0.341D, 1.0D, 0.341D));
        }
    }

    public void renderZone(
            OnWorldMapRenderEvent event,
            AfterTheFallZone zone,
            double r,
            double g,
            double b,
            double a) {
        float zoom = event.getRenderer().getDisplayZoomF();
        float centerX = event.getRenderer().getCenterWorldX();
        float centerY = event.getRenderer().getCenterWorldY();

        float uiXStart =
                event.getRenderer()
                        .worldToUIX(
                                zone.getXStart().floatValue(),
                                zone.getYStart().floatValue(),
                                zoom,
                                centerX,
                                centerY,
                                event.getRenderer().getProjectionMatrix(),
                                event.getRenderer().getModelViewMatrix());

        float uiYStart =
                event.getRenderer()
                        .worldToUIY(
                                zone.getXStart().floatValue(),
                                zone.getYStart().floatValue(),
                                zoom,
                                centerX,
                                centerY,
                                event.getRenderer().getProjectionMatrix(),
                                event.getRenderer().getModelViewMatrix());

        float uiXEnd =
                event.getRenderer()
                        .worldToUIX(
                                zone.getXEnd().floatValue(),
                                zone.getYEnd().floatValue(),
                                zoom,
                                centerX,
                                centerY,
                                event.getRenderer().getProjectionMatrix(),
                                event.getRenderer().getModelViewMatrix());

        float uiYEnd =
                event.getRenderer()
                        .worldToUIY(
                                zone.getXEnd().floatValue(),
                                zone.getYEnd().floatValue(),
                                zoom,
                                centerX,
                                centerY,
                                event.getRenderer().getProjectionMatrix(),
                                event.getRenderer().getModelViewMatrix());

        double drawX = PZMath.floor(uiXStart);
        double drawY = PZMath.floor(uiYStart);

        double width = uiXEnd - uiXStart;
        double height = uiYEnd - uiYStart;

        event.getUiWorldMap()
                .DrawTextureScaledColor(
                        (Texture) null, drawX, drawY, width, height, r, g, b, a); // R, G, B, A

        float worldMidX = (zone.getXStart().floatValue() + zone.getXEnd().floatValue()) / 2.0f;
        float worldMidY = (zone.getYStart().floatValue() + zone.getYEnd().floatValue()) / 2.0f;
        event.renderName(worldMidX, worldMidY, zone.getRegion());
    }
}
