package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.event.packet.*;
import zombie.iso.areas.SafeHouse;
import zombie.network.fields.Square;

public class SafehouseEventHandler {

    private static final org.slf4j.Logger logger = ExtraLoggerFactory.createLogger("safehouses");

    public static void onSafehouseClaim(SafehouseClaimPacketEvent event) {
        try {
            Square square = (Square) event.getField("square");
            logger.info(
                    "SafehouseClaim: steamId={}, user={}, player={}, square=(x{},y{},z{}), title={}",
                    event.steamId,
                    event.username,
                    event.getPacket().getUsername(),
                    square.getX(),
                    square.getY(),
                    square.getZ(),
                    event.getPacket().getTitle());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseClaim", e);
        }
    }

    public static void onSafehouseRelease(SafehouseReleasePacketEvent event) {
        try {
            SafeHouse safehouse = event.getPacket().getSafehouse();
            logger.info(
                    "SafehouseRelease: steamId={}, user={}, owner={}, zone=({},{},{},{}), title={}, created={}, members=[{}]",
                    event.steamId,
                    event.username,
                    safehouse.getOwner(),
                    safehouse.getX(),
                    safehouse.getY(),
                    safehouse.getX2(),
                    safehouse.getY2(),
                    safehouse.getTitle(),
                    safehouse.getDatetimeCreatedStr(),
                    safehouse.getPlayers());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseRelease", e);
        }
    }

    public static void onSafehouseChangeOwner(SafehouseChangeOwnerPacketEvent event) {
        try {
            SafeHouse safehouse = event.getPacket().getSafehouse();
            logger.info(
                    "SafehouseChangeOwner: steamId={}, user={}, previousOwner={}, newOwner={}, zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    event.getPreviousOwner(),
                    safehouse.getOwner(),
                    safehouse.getX(),
                    safehouse.getY(),
                    safehouse.getX2(),
                    safehouse.getY2(),
                    safehouse.getTitle(),
                    safehouse.getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseChangeOwner", e);
        }
    }

    public static void onSafehouseChangeMember(SafehouseChangeMemberPacketEvent event) {
        try {
            SafeHouse safehouse = event.getPacket().getSafehouse();
            logger.info(
                    "SafehouseChangeMember: steamId={}, user={}, owner={}, removedPlayer={}, wasMember={} zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    safehouse.getOwner(),
                    event.getPacket().getUsername(),
                    event.wasMember(),
                    safehouse.getX(),
                    safehouse.getY(),
                    safehouse.getX2(),
                    safehouse.getY2(),
                    safehouse.getTitle(),
                    safehouse.getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseChangeMember", e);
        }
    }

    public static void onSafehouseInvite(SafehouseInvitePacketEvent event) {
        try {
            SafeHouse safehouse = event.getPacket().getSafehouse();
            logger.info(
                    "SafehouseInvite: steamId={}, user={}, owner={}, invitedPlayer={}, zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    safehouse.getOwner(),
                    event.getPacket().getUsername(),
                    safehouse.getX(),
                    safehouse.getY(),
                    safehouse.getX2(),
                    safehouse.getY2(),
                    safehouse.getTitle(),
                    safehouse.getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseInvite", e);
        }
    }

    public static void onSafehouseAccept(SafehouseAcceptPacketEvent event) {
        try {
            SafeHouse safehouse = event.getPacket().getSafehouse();
            logger.info(
                    "SafehouseAccept: steamId={}, user={}, owner={}, invitedPlayer={} accepted={}, zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    safehouse.getOwner(),
                    event.getPacket().getUsername(),
                    event.getField("isAccepted"),
                    safehouse.getX(),
                    safehouse.getY(),
                    safehouse.getX2(),
                    safehouse.getY2(),
                    safehouse.getTitle(),
                    safehouse.getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseAccept", e);
        }
    }

    public static void onSafehouseChangeRespawn(SafehouseChangeRespawnPacketEvent event) {
        try {
            SafeHouse safehouse = event.getPacket().getSafehouse();
            logger.info(
                    "SafehouseChangeRespawn: steamId={}, user={}, owner={}, player={}, addingRespawn={}, wasRespawning={}, zone=({},{},{},{}), title={}, created={}",
                    event.steamId,
                    event.username,
                    safehouse.getOwner(),
                    event.getPacket().getUsername(),
                    Boolean.TRUE.equals(event.getField("doRemove")),
                    event.wasRespawning(),
                    safehouse.getX(),
                    safehouse.getY(),
                    safehouse.getX2(),
                    safehouse.getY2(),
                    safehouse.getTitle(),
                    safehouse.getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseChangeRespawn", e);
        }
    }

    public static void onSafehouseChangeTitle(SafehouseChangeTitlePacketEvent event) {
        try {
            SafeHouse safehouse = event.getPacket().getSafehouse();
            logger.info(
                    "SafehouseChangeTitle: steamId={}, user={}, owner={}, previousTitle={}, newTitle={}, zone=({},{},{},{}), created={}",
                    event.steamId,
                    event.username,
                    safehouse.getOwner(),
                    event.getPreviousTitle(),
                    event.getField("title"),
                    safehouse.getX(),
                    safehouse.getY(),
                    safehouse.getX2(),
                    safehouse.getY2(),
                    safehouse.getDatetimeCreatedStr());
        } catch (Exception e) {
            logger.error("Failed to log SafehouseChangeTitle", e);
        }
    }

    public static void onSafezoneClaim(SafezoneClaimPacketEvent event) {
        try {
            logger.info(
                    "SafezoneClaim: steamId={}, user={}, player={}, square=(x{},y{}), title={}",
                    event.steamId,
                    event.username,
                    event.getPacket().getUsername(),
                    intField(event, "x"),
                    intField(event, "y"),
                    event.getPacket().getTitle());
        } catch (Exception e) {
            logger.error("Failed to log SafezoneClaim", e);
        }
    }

    private static int intField(PacketEvent event, String name) {
        Integer value = (Integer) event.getField(name);
        return value != null ? value : 0;
    }
}
