package com.sentientsimulations.projectzomboid.admincore;

import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.Lua.LuaManager;
import zombie.characters.Capability;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.iso.IsoCamera;
import zombie.iso.IsoUtils;
import zombie.iso.IsoWorld;
import zombie.iso.PlayerCamera;

/** A short-lived server grant controls a camera, never the character's position. */
public final class AdminCoreObserveCamera {
    private static final Logger LOGGER = LoggerFactory.getLogger(AdminCoreObserveCamera.class);
    private static String username;
    private static String mode = "FOLLOW";
    private static long expires, retryAfter, resolveAfter;
    private static IsoPlayer actor, target;
    private static boolean originalBlock, renderGranted, hideWeather;
    private static float panX, panY, freeX, freeY, freeAnchorX, freeAnchorY, freeZ;
    private static float grantedX, grantedY, grantedZ;
    private static float followOffsetX, followOffsetY;
    private static boolean followOffsetKnown;
    private static boolean streamGranted, hasPosition;

    private AdminCoreObserveCamera() {}

    @LuaMethod
    public static boolean grant(String name, boolean allowRender) {
        if (System.currentTimeMillis() < retryAfter || name == null || name.length() > 128)
            return false;
        IsoPlayer current = IsoPlayer.getInstance();
        if (!authorized(current) || current.isDead() || current.getVehicle() != null) {
            stop();
            return false;
        }
        if (actor != current) {
            stop();
            actor = current;
            originalBlock = current.isBlockMovement();
            current.setBlockMovement(true);
        }
        if (!name.equals(username)) {
            AdminCoreObserveStreaming.clear();
            streamGranted = hasPosition = false;
            target = null;
            resolveAfter = 0;
            panX = panY = 0;
            followOffsetKnown = false;
            mode = "FOLLOW";
        }
        username = name;
        expires = System.currentTimeMillis() + 6000;
        renderGranted = allowRender;
        if (!allowRender) hideWeather = false;
        return true;
    }

    /** Coordinates and TTL come from the independently authorized server interest response. */
    @LuaMethod
    public static boolean grantAt(
            String name,
            boolean allowRender,
            double x,
            double y,
            double z,
            double ttlSeconds,
            boolean stream) {
        if (!AdminCoreObserverBridge.validPosition(x, y, z)
                || z >= 32
                || !Double.isFinite(ttlSeconds)
                || ttlSeconds <= 0
                || ttlSeconds > 6
                || !grant(name, allowRender)) return false;
        grantedX = (float) x;
        grantedY = (float) y;
        grantedZ = (float) z;
        hasPosition = true;
        expires = System.currentTimeMillis() + (long) (ttlSeconds * 1000);
        streamGranted = stream && allowRender;
        if (streamGranted && !AdminCoreObserveStreaming.capacitySupported()) {
            stop();
            return false;
        }
        panX = panY = 0;
        followOffsetKnown = false;
        if ("FREE".equals(mode)) {
            freeX = freeAnchorX = grantedX;
            freeY = freeAnchorY = grantedY;
            freeZ = grantedZ;
        }
        return selectSafely(
                false,
                () -> {
                    if (streamGranted)
                        AdminCoreObserveStreaming.update(actor, grantedX, grantedY, expires);
                    else AdminCoreObserveStreaming.clear();
                    return true;
                });
    }

    @LuaMethod
    public static boolean streaming() {
        return active() && streamGranted && hasPosition;
    }

    @LuaMethod
    public static float getViewX() {
        if ("FREE".equals(mode)) return freeX;
        var selected = followTarget();
        return (selected == null ? grantedX : selected.getX() + followX()) + panX;
    }

    @LuaMethod
    public static float getViewY() {
        if ("FREE".equals(mode)) return freeY;
        var selected = followTarget();
        return (selected == null ? grantedY : selected.getY() + followY()) + panY;
    }

    @LuaMethod
    public static float getViewZ() {
        if ("FREE".equals(mode)) return freeZ;
        var selected = followTarget();
        return selected == null ? grantedZ : selected.getZ();
    }

    private static float followX() {
        return "SOFT".equals(mode) && followOffsetKnown ? followOffsetX : 0;
    }

    private static float followY() {
        return "SOFT".equals(mode) && followOffsetKnown ? followOffsetY : 0;
    }

    // Player positions already receive native interpolation. Grant replies authorize
    // terrain at four Hz; using those same snapshots for rendering adds visible delay.
    private static IsoPlayer followTarget() {
        IsoPlayer selected = resolve();
        if (selected == null) return null;
        if (!streamGranted) return selected;
        if ("SOFT".equals(mode) && !followOffsetKnown) return null;
        float x = selected.getX() + followX() + panX;
        float y = selected.getY() + followY() + panY;
        float z = selected.getZ();
        int radius = AdminCoreObserveStreaming.radius();
        return Float.isFinite(x)
                        && Float.isFinite(y)
                        && Float.isFinite(z)
                        && Math.floor(z) == Math.floor(grantedZ)
                        && Math.abs(Math.floor(x / 8) - Math.floor(grantedX / 8)) <= radius
                        && Math.abs(Math.floor(y / 8) - Math.floor(grantedY / 8)) <= radius
                ? selected
                : null;
    }

    @LuaMethod
    public static boolean setFollowOffset(double x, double y) {
        if (!active()
                || !Double.isFinite(x)
                || !Double.isFinite(y)
                || Math.abs(x) > 8
                || Math.abs(y) > 8) return false;
        followOffsetX = (float) x;
        followOffsetY = (float) y;
        followOffsetKnown = true;
        return true;
    }

    @LuaMethod
    public static int requestedRadius() {
        return AdminCoreObserveStreaming.requestedRadius();
    }

    @LuaMethod
    public static boolean grantRadius(double radius) {
        return Double.isFinite(radius)
                && radius == Math.rint(radius)
                && AdminCoreObserveStreaming.grantRadius((int) radius);
    }

    @LuaMethod
    public static float getFollowOffsetX() {
        return followX() + panX;
    }

    @LuaMethod
    public static float getFollowOffsetY() {
        return followY() + panY;
    }

    @LuaMethod
    public static boolean ready() {
        return active()
                && IsoWorld.instance != null
                && IsoWorld.instance.getCell() != null
                && IsoWorld.instance
                                .getCell()
                                .getGridSquare(
                                        (int) Math.floor(getViewX()),
                                        (int) Math.floor(getViewY()),
                                        (int) Math.floor(getViewZ()))
                        != null;
    }

    private static boolean authorized(IsoPlayer player) {
        return player != null
                && player.getRole() != null
                && player.getRole().hasAdminPower()
                && player.getRole().hasCapability(Capability.TeleportToPlayer)
                && player.getRole().hasCapability(Capability.SeePlayersConnected);
    }

    @LuaMethod
    public static void stop() {
        AdminCoreObserveRender.clear();
        AdminCoreObserveStreaming.clear();
        IsoPlayer previous = actor;
        username = null;
        expires = 0;
        target = actor = null;
        renderGranted = hideWeather = false;
        streamGranted = hasPosition = false;
        followOffsetKnown = false;
        followOffsetX = followOffsetY = 0;
        mode = "FOLLOW";
        panX = panY = 0;
        if (previous != null) {
            previous.setBlockMovement(originalBlock);
            IsoCamera.setCameraCharacter(previous);
        }
    }

    @LuaMethod
    public static boolean active() {
        if (username == null) return false;
        if (System.currentTimeMillis() >= expires
                || actor == null
                || actor.getPlayerNum() < 0
                || actor.getPlayerNum() >= IsoPlayer.players.length
                || actor != IsoPlayer.players[actor.getPlayerNum()]
                || !authorized(actor)
                || actor.isDead()
                || actor.getVehicle() != null) {
            stop();
            return false;
        }
        return true;
    }

    private static IsoPlayer resolve() {
        long now = System.currentTimeMillis();
        if (now >= resolveAfter) {
            target = LuaManager.GlobalObject.getPlayerFromUsername(username);
            resolveAfter = now + 250;
        }
        if (target == null || target.isDead() || target.getCurrentSquare() == null) return null;
        return target;
    }

    @LuaMethod
    public static boolean setMode(String value) {
        if (!active() || !("FOLLOW".equals(value) || "SOFT".equals(value) || "FREE".equals(value)))
            return false;
        if (value.equals(mode)) return true;
        IsoPlayer selected = resolve();
        if (selected == null && !streaming()) return false;
        if ("FREE".equals(value) && !"FREE".equals(mode)) {
            freeX = streamGranted || selected == null ? grantedX : selected.getX() + panX;
            freeY = streamGranted || selected == null ? grantedY : selected.getY() + panY;
            freeAnchorX = freeX;
            freeAnchorY = freeY;
            freeZ = streamGranted || selected == null ? grantedZ : selected.getZ();
        }
        mode = value;
        panX = panY = 0;
        return true;
    }

    @LuaMethod
    public static boolean pan(double dx, double dy) {
        if (!active() || "FOLLOW".equals(mode) || !Double.isFinite(dx) || !Double.isFinite(dy))
            return false;
        return applyPrediction(Math.clamp(dx, -2, 2), Math.clamp(dy, -2, 2));
    }

    /** Reapply only movement made after an acknowledged request, without moving its stream area. */
    @LuaMethod
    public static boolean restorePrediction(double dx, double dy) {
        if (!streaming() || "FOLLOW".equals(mode) || !Double.isFinite(dx) || !Double.isFinite(dy))
            return false;
        return applyPrediction(dx, dy);
    }

    private static boolean applyPrediction(double dx, double dy) {
        IsoPlayer selected = resolve();
        if (selected == null && !streaming()) return false;
        if ("SOFT".equals(mode) && followOffsetKnown) {
            double nextX = followOffsetX + panX + dx, nextY = followOffsetY + panY + dy;
            if (Math.abs(nextX) > 8 || Math.abs(nextY) > 8) return false;
            panX += (float) dx;
            panY += (float) dy;
            return true;
        }
        float targetX = streamGranted || selected == null ? grantedX : selected.getX();
        float targetY = streamGranted || selected == null ? grantedY : selected.getY();
        float nx = (float) ("FREE".equals(mode) ? freeX + dx : targetX + panX + dx);
        float ny = (float) ("FREE".equals(mode) ? freeY + dy : targetY + panY + dy);
        float limit = "SOFT".equals(mode) ? 8 : 24;
        // The acknowledged SOFT center already includes the server-approved offset.
        // Bounds remain relative to the target, not to that offset center.
        float anchorX =
                "SOFT".equals(mode) ? selected == null ? targetX : selected.getX() : freeAnchorX;
        float anchorY =
                "SOFT".equals(mode) ? selected == null ? targetY : selected.getY() : freeAnchorY;
        if (!insidePanRange(nx, ny, anchorX, anchorY, limit)
                || IsoWorld.instance == null
                || IsoWorld.instance.getCell() == null
                || (!streamGranted
                        && IsoWorld.instance
                                        .getCell()
                                        .getGridSquare(
                                                (int) Math.floor(nx),
                                                (int) Math.floor(ny),
                                                (int) getViewZ())
                                == null)) return false;
        if ("FREE".equals(mode)) {
            freeX = nx;
            freeY = ny;
        } else {
            panX = nx - targetX;
            panY = ny - targetY;
        }
        return true;
    }

    @LuaMethod
    public static void setHideWeather(boolean value) {
        hideWeather = value && active() && renderGranted;
    }

    public static boolean hideWeather() {
        return hideWeather
                && active()
                && IsoCamera.frameState.playerIndex == actor.getPlayerNum()
                && renderGranted
                && actor.getRole().hasCapability(Capability.UseDebugContextMenu);
    }

    public static IsoGameCharacter select(IsoGameCharacter original) {
        if (username == null) return original;
        return selectSafely(
                original,
                () -> {
                    if (!active()) return original;
                    // Other local players keep their own split-screen camera.
                    if (!ownsCamera(original, actor, target)) return original;
                    IsoPlayer selected = resolve();
                    if (selected == null) {
                        if (streaming()) return actor;
                        stop();
                        return original;
                    }
                    return selected;
                });
    }

    public static void center(PlayerCamera camera) {
        if (username == null) return;
        selectSafely(
                false,
                () -> {
                    if (!active() || camera.playerIndex != actor.getPlayerNum()) return false;
                    IsoPlayer selected = resolve();
                    if (selected == null) {
                        if (!streaming()) {
                            stop();
                            return false;
                        }
                        selected = actor;
                    }
                    if (!streamGranted
                            && "FREE".equals(mode)
                            && (int) selected.getZ() != (int) freeZ) {
                        stop();
                        return false;
                    }
                    if (streamGranted)
                        AdminCoreObserveStreaming.update(actor, grantedX, grantedY, expires);
                    float x = getViewX();
                    float y = getViewY();
                    float z =
                            streamGranted
                                    ? getViewZ()
                                    : IsoCamera.frameState.calculateCameraZ(selected);
                    camera.offX =
                            IsoUtils.XToScreen(x, y, z, 0)
                                    - IsoCamera.getOffscreenWidth(camera.playerIndex) / 2f
                                    + IsoCamera.playerOffsetX;
                    camera.offY =
                            IsoUtils.YToScreen(x, y, z, 0)
                                    - IsoCamera.getOffscreenHeight(camera.playerIndex) / 2f
                                    - selected.getOffsetY() * 1.5f
                                    + IsoCamera.playerOffsetY;
                    camera.rightClickX =
                            camera.rightClickY =
                                    camera.rightClickTargetX = camera.rightClickTargetY = 0;
                    return true;
                });
    }

    /** The render frame has a separate viewer from the camera offset in B42. */
    public static void frame(IsoCamera.FrameState frame) {
        if (username == null) return;
        selectSafely(
                false,
                () -> {
                    if (!active() || frame.playerIndex != actor.getPlayerNum()) return false;
                    IsoPlayer selected = resolve();
                    if (selected == null) {
                        if (!streaming()) {
                            stop();
                            return false;
                        }
                        selected = actor;
                    }
                    float x = getViewX();
                    float y = getViewY();
                    float z =
                            streamGranted
                                    ? getViewZ()
                                    : IsoCamera.frameState.calculateCameraZ(selected);
                    var square =
                            IsoWorld.instance
                                    .getCell()
                                    .getGridSquare(
                                            (int) Math.floor(x),
                                            (int) Math.floor(y),
                                            (int) Math.floor(z));
                    var room = square == null ? null : square.getRoom();
                    frame.camCharacter = selected;
                    frame.camCharacterX = x;
                    frame.camCharacterY = y;
                    frame.camCharacterZ = z;
                    frame.camCharacterSquare = square;
                    frame.camCharacterRoom = room;
                    PlayerCamera camera = IsoCamera.cameras[frame.playerIndex];
                    frame.offX = camera.getOffX();
                    frame.offY = camera.getOffY();
                    return true;
                });
    }

    static boolean renderAllowed(int playerIndex) {
        return active()
                && renderGranted
                && playerIndex == actor.getPlayerNum()
                && actor.getRole().hasCapability(Capability.UseDebugContextMenu);
    }

    /** B42's 3D projection reads the avatar position independently of sprite offsets. */
    public static float projectionCoordinate(float original, int playerIndex, int axis) {
        if (username == null) return original;
        return selectSafely(
                original,
                () -> {
                    if (!active() || playerIndex != actor.getPlayerNum()) return original;
                    return switch (axis) {
                        case 0 -> getViewX();
                        case 1 -> getViewY();
                        case 2 -> getViewZ();
                        default -> original;
                    };
                });
    }

    /** The native player-render gate otherwise measures LOS from the stationary observer. */
    @SuppressWarnings("PMD.CompareObjectsWithEquals")
    public static boolean showsPlayer(IsoPlayer viewer, IsoPlayer remote) {
        if (viewer == null || remote == null || viewer != actor || viewer == remote) return false;
        return selectSafely(
                false,
                () ->
                        viewer.isLocalPlayer()
                                && renderAllowed(viewer.getPlayerNum())
                                && AdminCoreObserveRender.visible(
                                        remote.getCurrentSquare(), viewer.getPlayerNum())
                                && (!remote.isInvisible()
                                        || viewer.getRole()
                                                .hasCapability(Capability.SeesInvisiblePlayers)));
    }

    static boolean insidePanRange(float x, float y, float anchorX, float anchorY, float limit) {
        return Float.isFinite(x)
                && Float.isFinite(y)
                && Math.abs(x - anchorX) <= limit
                && Math.abs(y - anchorY) <= limit;
    }

    // Character identity is intentional: equal account data must not redirect
    // another local player's camera or a replacement character instance.
    @SuppressWarnings("PMD.CompareObjectsWithEquals")
    static boolean ownsCamera(Object original, Object actor, Object target) {
        return original == actor || original == target;
    }

    static <T> T selectSafely(T original, Supplier<T> selection) {
        try {
            return selection.get();
        } catch (RuntimeException | LinkageError error) {
            stop();
            retryAfter = System.currentTimeMillis() + 30000;
            LOGGER.warn(
                    "Observe camera disabled after a client error; restoring normal camera", error);
            return original;
        }
    }
}
