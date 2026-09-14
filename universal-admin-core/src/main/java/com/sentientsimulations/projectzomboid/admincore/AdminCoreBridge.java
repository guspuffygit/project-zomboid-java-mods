package com.sentientsimulations.projectzomboid.admincore;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.WeakHashMap;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.Capability;
import zombie.characters.Faction;
import zombie.characters.IsoPlayer;
import zombie.characters.NetworkUser;
import zombie.characters.NetworkUsers;
import zombie.iso.areas.SafeHouse;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.ServerWorldDatabase;
import zombie.network.chat.ChatServer;
import zombie.network.packets.INetworkPacket;

/** Server-only adapter. Authorization is repeated here, not delegated to UI visibility. */
public final class AdminCoreBridge {
    private static final Map<IsoPlayer, ObserveMove> observeMoves = new WeakHashMap<>();

    private AdminCoreBridge() {}

    private static boolean allowed(IsoPlayer actor, Capability cap) {
        return GameServer.server
                && actor != null
                && GameServer.isPlayerConnected(actor)
                && actor.getRole() != null
                && actor.getRole().hasCapability(cap);
    }

    private static boolean known(String name) {
        return name != null
                && !name.isBlank()
                && name.length() <= 128
                && ServerWorldDatabase.instance.containsUser(name);
    }

    static SafeHouse safehouseByKey(String id) {
        if (id == null || id.isBlank()) return null;
        // B42's string lookup matches titles. getId() also contains a local creation
        // timestamp that isn't synchronized. Match the bounds used by SafehouseSync.
        for (SafeHouse house : SafeHouse.getSafehouseList()) {
            String key =
                    house.getX() + "," + house.getY() + "," + house.getW() + "," + house.getH();
            if (id.equals(key)) return house;
        }
        return null;
    }

    private static void sync(SafeHouse house) {
        ChatServer.getInstance().createSafehouseChat(house.getId());
        INetworkPacket.sendToAll(PacketTypes.PacketType.SafehouseSync, house);
        ChatServer.getInstance()
                .syncSafehouseChatMembers(house.getId(), house.getOwner(), house.getPlayers());
    }

    private static void sync(Faction faction) {
        ChatServer.getInstance().createFactionChat(faction.getName());
        INetworkPacket.sendToAll(PacketTypes.PacketType.FactionSync, faction);
        ChatServer.getInstance()
                .syncFactionChatMembers(
                        faction.getName(), faction.getOwner(), faction.getPlayers());
    }

    @LuaMethod
    public static boolean knownUser(IsoPlayer actor, String name) {
        return (allowed(actor, Capability.CanSetupSafehouses)
                        || allowed(actor, Capability.FactionCheat)
                        || allowed(actor, Capability.ReadUserLog))
                && known(name);
    }

    @LuaMethod
    public static double lastSeen(IsoPlayer actor, String username) {
        if (!(allowed(actor, Capability.CanSetupSafehouses)
                || allowed(actor, Capability.FactionCheat)
                || allowed(actor, Capability.ReadUserLog))) return -1;
        NetworkUser user = NetworkUsers.instance.getUser(username);
        if (user == null || user.getLastConnection() == null) return -1;
        try {
            return LocalDateTime.parse(
                            user.getLastConnection(),
                            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))
                    .atZone(ZoneId.systemDefault())
                    .toEpochSecond();
        } catch (RuntimeException ex) {
            return -1;
        }
    }

    @LuaMethod
    public static String addMember(IsoPlayer actor, String kind, String id, String username) {
        if (!known(username)) return "Account not found on this server.";
        if ("safehouse".equals(kind)) {
            if (!allowed(actor, Capability.CanSetupSafehouses)) return "Permission denied.";
            SafeHouse house = safehouseByKey(id);
            if (house == null) return "Safehouse no longer exists.";
            SafeHouse other = SafeHouse.hasSafehouse(username);
            if (other != null && other != house)
                return "Player already belongs to another safehouse.";
            house.addPlayer(username);
            sync(house);
        } else if ("faction".equals(kind)) {
            if (!allowed(actor, Capability.FactionCheat)) return "Permission denied.";
            Faction faction = Faction.getFaction(id);
            if (faction == null) return "Faction no longer exists.";
            Faction other = Faction.getPlayerFaction(username);
            if (other != null && other != faction)
                return "Player already belongs to another faction.";
            faction.addPlayer(username);
            sync(faction);
        } else return "Unknown membership type.";
        System.out.println(
                "[Universal Admin Core] "
                        + actor.getUsername()
                        + " added "
                        + username
                        + " to "
                        + kind
                        + " "
                        + id);
        return "OK";
    }

    @LuaMethod
    public static String transferAndRemove(
            IsoPlayer actor, String kind, String id, String oldOwner, String replacement) {
        return transfer(actor, kind, id, oldOwner, replacement, true);
    }

    @LuaMethod
    public static String transferOnly(
            IsoPlayer actor, String kind, String id, String oldOwner, String replacement) {
        return transfer(actor, kind, id, oldOwner, replacement, false);
    }

    private static String transfer(
            IsoPlayer actor,
            String kind,
            String id,
            String oldOwner,
            String replacement,
            boolean removeOld) {
        if (!known(replacement) || replacement.equals(oldOwner))
            return "Select a different existing account.";
        if ("safehouse".equals(kind)) {
            if (!allowed(actor, Capability.CanSetupSafehouses)) return "Permission denied.";
            SafeHouse house = safehouseByKey(id);
            if (house == null || !house.getOwner().equals(oldOwner))
                return "Safehouse ownership changed. Refresh first.";
            SafeHouse other = SafeHouse.hasSafehouse(replacement);
            if (other != null && other != house) return "Replacement belongs to another safehouse.";
            house.setOwner(replacement);
            if (removeOld) SafeHouse.kickUserFromSafehouse(house, oldOwner);
            else house.addPlayer(oldOwner);
            sync(house);
        } else if ("faction".equals(kind)) {
            if (!allowed(actor, Capability.FactionCheat)) return "Permission denied.";
            Faction faction = Faction.getFaction(id);
            if (faction == null || !faction.getOwner().equals(oldOwner))
                return "Faction ownership changed. Refresh first.";
            Faction other = Faction.getPlayerFaction(replacement);
            if (other != null && other != faction) return "Replacement belongs to another faction.";
            faction.setOwner(replacement);
            if (removeOld) faction.removePlayer(oldOwner);
            else faction.addPlayer(oldOwner);
            sync(faction);
        } else return "Unknown membership type.";
        System.out.println(
                "[Universal Admin Core] "
                        + actor.getUsername()
                        + " transferred "
                        + kind
                        + " "
                        + id
                        + " to "
                        + replacement
                        + "; remove old owner="
                        + removeOld);
        return "OK";
    }

    @LuaMethod
    public static String createSafehouse(
            IsoPlayer actor, String owner, String title, double x, double y, double w, double h) {
        if (!allowed(actor, Capability.CanSetupSafehouses)) return "Permission denied.";
        if (!known(owner)) return "Owner account not found.";
        if (title == null || title.isBlank() || title.length() > 128)
            return "Enter a title of 1-128 characters.";
        if (!Double.isFinite(x + y + w + h)
                || x != Math.floor(x)
                || y != Math.floor(y)
                || w != Math.floor(w)
                || h != Math.floor(h)
                || w < 2
                || h < 2
                || w > 200
                || h > 200
                || Math.abs(x) > 1000000
                || Math.abs(y) > 1000000)
            return "Select a rectangle between 2 and 200 tiles per side.";
        if (SafeHouse.hasSafehouse(owner) != null) return "Owner already belongs to a safehouse.";
        for (SafeHouse existing : SafeHouse.getSafehouseList()) {
            if (x < existing.getX() + existing.getW()
                    && x + w > existing.getX()
                    && y < existing.getY() + existing.getH()
                    && y + h > existing.getY()) return "Selection overlaps an existing safehouse.";
        }
        SafeHouse house = SafeHouse.addSafeHouse((int) x, (int) y, (int) w, (int) h, owner);
        if (house == null) return "The server could not create this safehouse.";
        house.setTitle(title);
        sync(house);
        System.out.println(
                "[Universal Admin Core] "
                        + actor.getUsername()
                        + " created safehouse "
                        + house.getId()
                        + " for "
                        + owner);
        return "OK";
    }

    @LuaMethod
    public static boolean canObserve(IsoPlayer actor) {
        return allowed(actor, Capability.TeleportToCoordinates)
                && allowed(actor, Capability.TeleportToPlayer)
                && allowed(actor, Capability.ToggleInvisibleHimself)
                && allowed(actor, Capability.ToggleGodModHimself)
                && actor.isInvisible()
                && actor.isGodMod()
                && actor.isNoClip()
                && actor.getVehicle() == null;
    }

    @LuaMethod
    public static boolean follow(IsoPlayer actor, String username) {
        if (!canObserve(actor)) {
            observeMoves.remove(actor);
            return false;
        }
        IsoPlayer target = GameServer.getPlayerByUserName(username);
        if (target == null
                || target == actor
                || !GameServer.isPlayerConnected(target)
                || target.isDead()) {
            observeMoves.remove(actor);
            return false;
        }
        long now = System.nanoTime();
        ObserveMove previous = observeMoves.get(actor);
        if (previous != null && previous.waiting(actor.getX(), actor.getY(), actor.getZ(), now))
            return true;
        observeMoves.remove(actor);
        double dx = target.getX() - actor.getX(), dy = target.getY() - actor.getY();
        if (dx * dx + dy * dy > 64 || (int) actor.getZ() != (int) target.getZ()) {
            GameServer.sendTeleport(actor, target.getX() + 2, target.getY() + 2, target.getZ());
            observeMoves.put(
                    actor,
                    new ObserveMove(target.getX() + 2, target.getY() + 2, target.getZ(), now));
        }
        return true;
    }

    @LuaMethod
    public static void returnFromObserve(IsoPlayer actor, double x, double y, double z) {
        observeMoves.remove(actor);
        // Coordinates originate exclusively from the server's observation-session record.
        if (GameServer.server
                && actor != null
                && GameServer.isPlayerConnected(actor)
                && Double.isFinite(x)
                && Double.isFinite(y)
                && Double.isFinite(z))
            GameServer.sendTeleport(actor, (float) x, (float) y, (float) z);
    }
}
