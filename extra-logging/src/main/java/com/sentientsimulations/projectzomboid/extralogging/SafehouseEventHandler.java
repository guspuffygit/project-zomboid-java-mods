package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.SafehouseClaimedEvent;
import io.pzstorm.storm.event.zomboid.SafehouseInviteRespondedEvent;
import io.pzstorm.storm.event.zomboid.SafehouseInviteSentEvent;
import io.pzstorm.storm.event.zomboid.SafehouseMemberRemovedEvent;
import io.pzstorm.storm.event.zomboid.SafehouseOwnerChangedEvent;
import io.pzstorm.storm.event.zomboid.SafehouseReleasedEvent;
import io.pzstorm.storm.event.zomboid.SafezoneClaimedEvent;
import java.time.Instant;

public class SafehouseEventHandler {

    @SubscribeEvent
    public static void onSafehouseClaimed(SafehouseClaimedEvent event) {
        try {
            String header = formatHeader("take safehouse");
            StringBuilder sb = new StringBuilder();
            field(sb, "Username", event.username);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Zone", formatZone(event.x, event.y, event.w, event.h));
            field(sb, "Title", event.title);
            SafehouseLogWriter.writeEntry(header, sb.toString());
            LOGGER.info("Logged safehouse claim by: {}", event.username);
        } catch (Exception e) {
            LOGGER.error("Failed to log safehouse claim for: {}", event.username, e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseReleased(SafehouseReleasedEvent event) {
        try {
            String header = formatHeader("release safehouse");
            StringBuilder sb = new StringBuilder();
            field(sb, "Owner", event.owner);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Zone", formatZone(event.x, event.y, event.w, event.h));
            field(sb, "Title", event.title);
            field(sb, "Members", "[" + event.members + "]");
            SafehouseLogWriter.writeEntry(header, sb.toString());
            LOGGER.info("Logged safehouse release by: {}", event.owner);
        } catch (Exception e) {
            LOGGER.error("Failed to log safehouse release for: {}", event.owner, e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseOwnerChanged(SafehouseOwnerChangedEvent event) {
        try {
            String header = formatHeader("change safehouse owner");
            StringBuilder sb = new StringBuilder();
            field(sb, "Previous Owner", event.previousOwner);
            field(sb, "New Owner", event.newOwner);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Zone", formatZone(event.x, event.y, event.w, event.h));
            field(sb, "Title", event.title);
            SafehouseLogWriter.writeEntry(header, sb.toString());
            LOGGER.info(
                    "Logged safehouse owner change: {} -> {}", event.previousOwner, event.newOwner);
        } catch (Exception e) {
            LOGGER.error("Failed to log safehouse owner change", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseMemberRemoved(SafehouseMemberRemovedEvent event) {
        try {
            String header = formatHeader("remove player from safehouse");
            StringBuilder sb = new StringBuilder();
            field(sb, "Removed", event.removedPlayer);
            field(sb, "Owner", event.owner);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Zone", formatZone(event.x, event.y, event.w, event.h));
            field(sb, "Title", event.title);
            SafehouseLogWriter.writeEntry(header, sb.toString());
            LOGGER.info("Logged safehouse member removal: {}", event.removedPlayer);
        } catch (Exception e) {
            LOGGER.error("Failed to log safehouse member removal for: {}", event.removedPlayer, e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseInviteSent(SafehouseInviteSentEvent event) {
        try {
            String header = formatHeader("send safehouse invite");
            StringBuilder sb = new StringBuilder();
            field(sb, "Owner", event.owner);
            field(sb, "Invited", event.invited);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Zone", formatZone(event.x, event.y, event.w, event.h));
            field(sb, "Title", event.title);
            SafehouseLogWriter.writeEntry(header, sb.toString());
            LOGGER.info("Logged safehouse invite: {} -> {}", event.owner, event.invited);
        } catch (Exception e) {
            LOGGER.error("Failed to log safehouse invite", e);
        }
    }

    @SubscribeEvent
    public static void onSafehouseInviteResponded(SafehouseInviteRespondedEvent event) {
        try {
            String action = event.accepted ? "accept safehouse invite" : "decline safehouse invite";
            String header = formatHeader(action);
            StringBuilder sb = new StringBuilder();
            field(sb, "Player", event.invitedPlayer);
            field(sb, "Owner", event.owner);
            field(sb, "Accepted", String.valueOf(event.accepted));
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Zone", formatZone(event.x, event.y, event.w, event.h));
            field(sb, "Title", event.title);
            SafehouseLogWriter.writeEntry(header, sb.toString());
            LOGGER.info(
                    "Logged safehouse invite response: {} {} invite from {}",
                    event.invitedPlayer,
                    event.accepted ? "accepted" : "declined",
                    event.owner);
        } catch (Exception e) {
            LOGGER.error("Failed to log safehouse invite response", e);
        }
    }

    @SubscribeEvent
    public static void onSafezoneClaimed(SafezoneClaimedEvent event) {
        try {
            String header = formatHeader("create safezone");
            StringBuilder sb = new StringBuilder();
            field(sb, "Username", event.username);
            field(sb, "Steam ID", String.valueOf(event.steamId));
            field(sb, "Zone", formatZone(event.x, event.y, event.w, event.h));
            field(sb, "Title", event.title);
            SafehouseLogWriter.writeEntry(header, sb.toString());
            LOGGER.info("Logged safezone creation by: {}", event.username);
        } catch (Exception e) {
            LOGGER.error("Failed to log safezone creation for: {}", event.username, e);
        }
    }

    private static String formatHeader(String action) {
        return String.format("[%s] %s", Instant.now(), action);
    }

    private static String formatZone(int x, int y, int w, int h) {
        return String.format("%d,%d,%d,%d", x, y, w, h);
    }

    private static void field(StringBuilder sb, String label, String value) {
        sb.append(String.format("%-16s%s%n", label + ":", value));
    }
}
