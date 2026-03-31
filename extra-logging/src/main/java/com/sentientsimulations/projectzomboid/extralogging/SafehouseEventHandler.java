package com.sentientsimulations.projectzomboid.extralogging;

import com.sentientsimulations.projectzomboid.extralogging.events.*;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.packet.*;

public class SafehouseEventHandler {

    private static final ch.qos.logback.classic.Logger logger =
            ExtraLoggerFactory.createLogger("safehouses");

    @SubscribeEvent
    public static void onSafehouseClaim(SafehouseClaimPacketEvent event) {
        try {
            logger.info(
                    "SafehouseClaim: steamId={}, user={}, player={}, square=(x{},y{},z{}), title={}",
                    event.steamId,
                    event.username,
                    event.getPlayer().getUsername(),
                    event.getSquare().getX(),
                    event.getSquare().getY(),
                    event.getSquare().getZ(),
                    event.getTitle());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseClaim", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseRelease(SafehouseReleasePacketEvent event) {
        try {
            logger.info(
                    "SafehouseRelease: steamId={}, user={}, owner={}, zone=({},{},{},{}), title={}, created={}, members=[{}]",
                    event.steamId,
                    event.username,
                    event.getSafehouse().getOwner(),
                    event.getSafehouse().getX(),
                    event.getSafehouse().getY(),
                    event.getSafehouse().getX2(),
                    event.getSafehouse().getY2(),
                    event.getSafehouse().getTitle(),
                    event.getSafehouse().getDatetimeCreatedStr(),
                    event.getSafehouse().getPlayers());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseRelease", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseChangeOwner(SafehouseChangeOwnerPacketEvent event) {
        try {
            logger.info(
                    "SafehouseChangeOwner: steamId={}, user={}, previousOwner={}, newOwner={}, zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    event.getPreviousOwner(),
                    event.getSafehouse().getOwner(),
                    event.getSafehouse().getX(),
                    event.getSafehouse().getY(),
                    event.getSafehouse().getX2(),
                    event.getSafehouse().getY2(),
                    event.getSafehouse().getTitle(),
                    event.getSafehouse().getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseChangeOwner", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseChangeMember(SafehouseChangeMemberPacketEvent event) {
        try {
            logger.info(
                    "SafehouseChangeMember: steamId={}, user={}, owner={}, removedPlayer={}, wasMember={} zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    event.getSafehouse().getOwner(),
                    event.getPlayer(),
                    event.wasMember(),
                    event.getSafehouse().getX(),
                    event.getSafehouse().getY(),
                    event.getSafehouse().getX2(),
                    event.getSafehouse().getY2(),
                    event.getSafehouse().getTitle(),
                    event.getSafehouse().getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseChangeMember", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseInvite(SafehouseInvitePacketEvent event) {
        try {
            logger.info(
                    "SafehouseInvite: steamId={}, user={}, owner={}, invitedPlayer={}, zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    event.getSafehouse().getOwner(),
                    event.getInvited(),
                    event.getSafehouse().getX(),
                    event.getSafehouse().getY(),
                    event.getSafehouse().getX2(),
                    event.getSafehouse().getY2(),
                    event.getSafehouse().getTitle(),
                    event.getSafehouse().getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseInvite", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseAccept(SafehouseAcceptPacketEvent event) {
        try {
            logger.info(
                    "SafehouseAccept: steamId={}, user={}, owner={}, invitedPlayer={} accepted={}, zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    event.getSafehouse().getOwner(),
                    event.getInvited(),
                    event.isAccepted(),
                    event.getSafehouse().getX(),
                    event.getSafehouse().getY(),
                    event.getSafehouse().getX2(),
                    event.getSafehouse().getY2(),
                    event.getSafehouse().getTitle(),
                    event.getSafehouse().getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseAccept", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseChangeRespawn(SafehouseChangeRespawnPacketEvent event) {
        try {
            logger.info(
                    "SafehouseChangeRespawn: steamId={}, user={}, owner={}, player={}, addingRespawn={}, wasRespawning={}, zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    event.getSafehouse().getOwner(),
                    event.getPlayer(),
                    event.isAddingRespawn(),
                    event.wasRespawning(),
                    event.getSafehouse().getX(),
                    event.getSafehouse().getY(),
                    event.getSafehouse().getX2(),
                    event.getSafehouse().getY2(),
                    event.getSafehouse().getTitle(),
                    event.getSafehouse().getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseChangeRespawn", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseChangeTitle(SafehouseChangeTitlePacketEvent event) {
        try {
            logger.info(
                    "SafehouseChangeTitle: steamId={}, user={}, owner={}, previousTitle={}, newTitle={}, zone=({},{},{},{}), created={}",
                    event.steamId,
                    event.username,
                    event.getSafehouse().getOwner(),
                    event.getPreviousTitle(),
                    event.getTitle(),
                    event.getSafehouse().getX(),
                    event.getSafehouse().getY(),
                    event.getSafehouse().getX2(),
                    event.getSafehouse().getY2(),
                    event.getSafehouse().getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseChangeTitle", e);
        }
    }

    @SubscribeEvent
    public static void onSafezoneClaim(SafezoneClaimPacketEvent event) {
        try {
            logger.info(
                    "SafezoneClaim: steamId={}, user={}, player={}, square=(x{},y{}), title={}",
                    event.steamId,
                    event.username,
                    event.getPlayer().getUsername(),
                    event.getX(),
                    event.getY(),
                    event.getTitle());
        } catch (Exception e) {
            logger.error("Failed to log SafezoneClaim", e);
        }
    }
}
