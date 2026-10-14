package com.sentientsimulations.projectzomboid.admincore;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.iso.IsoWorld;
import zombie.iso.areas.SafeHouse;
import zombie.network.GameServer;

/** Mutates only the existing claim rectangle; membership and chat identity are never recreated. */
public final class SafehouseBoundaryBridge {
    private SafehouseBoundaryBridge() {}

    private static boolean allowed(IsoPlayer actor) {
        return GameServer.server
                && actor != null
                && GameServer.isPlayerConnected(actor)
                && actor.getRole() != null
                && actor.getRole().hasCapability(Capability.CanSetupSafehouses);
    }

    @LuaMethod
    public static SafeHouse find(IsoPlayer actor, double x, double y, double w, double h) {
        if (!allowed(actor) || !rectangle(x, y, w, h)) return null;
        return SafeHouse.getSafeHouse((int) x, (int) y, (int) w, (int) h);
    }

    @LuaMethod
    public static String fingerprint(IsoPlayer actor, SafeHouse house) {
        if (!allowed(actor) || !SafeHouse.getSafehouseList().contains(house)) return "";
        return fingerprint(house);
    }

    static String fingerprint(SafeHouse h) {
        // Length-prefix strings and include all authority/identity fields, not the ticking
        // online count/last-visited fields which would invalidate a preview every update.
        var value = new StringBuilder();
        for (Object part :
                new Object[] {
                    h.getId(),
                    h.getX(),
                    h.getY(),
                    h.getW(),
                    h.getH(),
                    h.getOwner(),
                    h.getTitle(),
                    h.getDatetimeCreated(),
                    h.getLocation()
                }) {
            String text = String.valueOf(part);
            value.append(text.length()).append(':').append(text);
        }
        for (var list : java.util.List.of(h.getPlayers(), h.getPlayersRespawn())) {
            value.append('|').append(list.size()).append(':');
            for (String text : list) value.append(text.length()).append(':').append(text);
        }
        try {
            return HexFormat.of()
                    .formatHex(
                            MessageDigest.getInstance("SHA-256")
                                    .digest(value.toString().getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    static boolean rectangle(double x, double y, double w, double h) {
        return Double.isFinite(x + y + w + h)
                && x == Math.floor(x)
                && y == Math.floor(y)
                && w == Math.floor(w)
                && h == Math.floor(h)
                && w >= 2
                && h >= 2
                && w <= 200
                && h <= 200
                && Math.abs(x) <= 1_000_000
                && Math.abs(y) <= 1_000_000;
    }

    static String validate(
            SafeHouse house,
            String expected,
            double x,
            double y,
            double w,
            double h,
            boolean expand) {
        if (house == null || !SafeHouse.getSafehouseList().contains(house))
            return "Safehouse no longer exists. Reopen the editor.";
        if (!fingerprint(house).equals(expected))
            return "Safehouse changed while editing. Reopen the editor.";
        if (!rectangle(x, y, w, h)) return "Select 2-200 whole tiles per side.";
        if (expand
                && (x > house.getX()
                        || y > house.getY()
                        || x + w < house.getX2()
                        || y + h < house.getY2()))
            return "Expand must contain the entire existing safehouse.";
        if (x == house.getX() && y == house.getY() && w == house.getW() && h == house.getH())
            return "The boundary has not changed.";
        if (SafeHouse.getSafehouseOverlapping((int) x, (int) y, (int) (x + w), (int) (y + h), house)
                != null) return "Selection overlaps another safehouse.";
        int onlineId = SafeHouse.getOnlineID((int) x, (int) y);
        for (SafeHouse other : SafeHouse.getSafehouseList())
            if (other != house && other.getOnlineID() == onlineId)
                return "Native safehouse network identity collision. Choose a different boundary.";
        return "OK";
    }

    @LuaMethod
    public static String apply(
            IsoPlayer actor,
            SafeHouse house,
            String expected,
            double x,
            double y,
            double w,
            double h,
            boolean expand) {
        if (!allowed(actor)) return "Permission denied.";
        String error = validate(house, expected, x, y, w, h, expand);
        if (!"OK".equals(error)) return error;
        var grid = IsoWorld.instance == null ? null : IsoWorld.instance.getMetaGrid();
        if (grid == null
                || !grid.isValidSquare((int) x, (int) y)
                || !grid.isValidSquare((int) (x + w - 1), (int) y)
                || !grid.isValidSquare((int) x, (int) (y + h - 1))
                || !grid.isValidSquare((int) (x + w - 1), (int) (y + h - 1)))
            return "Boundary is outside the available world map.";
        applyRectangle(house, (int) x, (int) y, (int) w, (int) h);
        return "OK";
    }

    static void applyRectangle(SafeHouse house, int x, int y, int w, int h) {
        house.setX(x);
        house.setY(y);
        house.setW(w);
        house.setH(h);
        // B42 addresses later membership packets by coordinate-derived onlineId. Update it
        // on both peers, as constructors do after reconnect/load; the final getId stays intact.
        house.setOnlineID(SafeHouse.getOnlineID(x, y));
    }
}
