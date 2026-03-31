package com.sentientsimulations.projectzomboid.extralogging;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.SafehouseClaimedEvent;
import io.pzstorm.storm.event.zomboid.SafehouseInviteRespondedEvent;
import io.pzstorm.storm.event.zomboid.SafehouseInviteSentEvent;
import io.pzstorm.storm.event.zomboid.SafehouseMemberRemovedEvent;
import io.pzstorm.storm.event.zomboid.SafehouseOwnerChangedEvent;
import io.pzstorm.storm.event.zomboid.SafehouseReleasedEvent;
import io.pzstorm.storm.event.zomboid.SafezoneClaimedEvent;

public class SafehouseEventHandler {

    private static final ch.qos.logback.classic.Logger logger =
            ExtraLoggerFactory.createLogger("safehouses");

    @SubscribeEvent
    public static void onSafehouseClaimed(SafehouseClaimedEvent event) {
        try {
            logger.info(
                    "SafehouseClaimed: steamId={}, user={}, zone=({},{},{},{}), title={}",
                    event.steamId,
                    event.username,
                    event.x,
                    event.y,
                    event.w,
                    event.h,
                    event.title);
        } catch (Exception e) {
            logger.error("Failed to log onSafehouseClaimed", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseReleased(SafehouseReleasedEvent event) {
        try {
            logger.info(
                    "SafehouseReleased: steamId={}, owner={}, zone=({},{},{},{}), title={}, members=[{}]",
                    event.steamId,
                    event.owner,
                    event.x,
                    event.y,
                    event.w,
                    event.h,
                    event.title,
                    event.members);
        } catch (Exception e) {
            logger.error("Failed to log onSafehouseReleased", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseOwnerChanged(SafehouseOwnerChangedEvent event) {
        try {
            logger.info(
                    "SafehouseOwnerChanged: steamId={}, previousOwner={}, newOwner={}, zone=({},{},{},{}), title={}",
                    event.steamId,
                    event.previousOwner,
                    event.newOwner,
                    event.x,
                    event.y,
                    event.w,
                    event.h,
                    event.title);
        } catch (Exception e) {
            logger.error("Failed to log onSafehouseOwnerChanged", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseMemberRemoved(SafehouseMemberRemovedEvent event) {
        try {
            logger.info(
                    "SafehouseMemberRemoved: steamId={}, owner={}, removed={}, zone=({},{},{},{}), title={}",
                    event.steamId,
                    event.owner,
                    event.removedPlayer,
                    event.x,
                    event.y,
                    event.w,
                    event.h,
                    event.title);
        } catch (Exception e) {
            logger.error("Failed to log onSafehouseMemberRemoved", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseInviteSent(SafehouseInviteSentEvent event) {
        try {
            logger.info(
                    "SafehouseInviteSent: steamId={}, owner={}, invited={}, zone=({},{},{},{}), title={}",
                    event.steamId,
                    event.owner,
                    event.invited,
                    event.x,
                    event.y,
                    event.w,
                    event.h,
                    event.title);
        } catch (Exception e) {
            logger.error("Failed to log onSafehouseInviteSent", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseInviteResponded(SafehouseInviteRespondedEvent event) {
        try {
            logger.info(
                    "SafehouseInviteResponded: steamId={}, player={}, owner={}, accepted={}, zone=({},{},{},{}), title={}",
                    event.steamId,
                    event.invitedPlayer,
                    event.owner,
                    event.accepted,
                    event.x,
                    event.y,
                    event.w,
                    event.h,
                    event.title);
        } catch (Exception e) {
            logger.error("Failed to log onSafehouseInviteResponded", e);
        }
    }

    @SubscribeEvent
    public static void onSafezoneClaimed(SafezoneClaimedEvent event) {
        try {
            logger.info(
                    "SafezoneClaimed: steamId={}, user={}, zone=({},{},{},{}), title={}",
                    event.steamId,
                    event.username,
                    event.x,
                    event.y,
                    event.w,
                    event.h,
                    event.title);
        } catch (Exception e) {
            logger.error("Failed to log onSafezoneClaimed", e);
        }
    }
}
