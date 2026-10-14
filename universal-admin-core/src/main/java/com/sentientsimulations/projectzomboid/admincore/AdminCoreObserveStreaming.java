package com.sentientsimulations.projectzomboid.admincore;

import java.util.ArrayList;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.iso.ChunkSaveWorker;
import zombie.iso.IsoCamera;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.LightingJNI;
import zombie.iso.PlayerCamera;
import zombie.iso.WorldStreamer;
import zombie.network.GameClient;

/** A bounded second terrain owner. The physical player's map is never scrolled or unloaded. */
public final class AdminCoreObserveStreaming {
    private static final Logger LOGGER = LoggerFactory.getLogger(AdminCoreObserveStreaming.class);
    static final int RADIUS = 3;
    static final int MAX_RADIUS = 9;
    static final int MAX_CHUNKS = (MAX_RADIUS * 2 + 1) * (MAX_RADIUS * 2 + 1);
    static final int REQUESTS_PER_TICK = 8;
    static final String MARKER = "uacObserverTerrainReady";
    private static volatile boolean markersReady;
    private static volatile IsoCell cell;
    private static volatile IsoChunkMap map;
    private static IsoPlayer actor;
    private static final Map<Integer, IsoChunk> owned = new ConcurrentHashMap<>();
    private static volatile Interest interest;
    private static int pendingRadius = RADIUS;
    private static IsoChunkMap renderOrigin;
    private static int renderSlot = -1;
    private static boolean accepting;
    private static long nextRequestAt;

    private AdminCoreObserveStreaming() {}

    record Interest(int x, int y, long expires, int radius) {
        Interest {
            if (radius < RADIUS || radius > MAX_RADIUS)
                throw new IllegalArgumentException("Observer radius");
        }

        Interest(int x, int y, long expires) {
            this(x, y, expires, RADIUS);
        }

        boolean contains(int chunkX, int chunkY, long now) {
            return now < expires
                    && Math.abs((long) chunkX - x) <= radius
                    && Math.abs((long) chunkY - y) <= radius;
        }
    }

    public static boolean grantRadius(int radius) {
        if (radius < RADIUS || radius > Math.min(MAX_RADIUS, IsoChunkMap.chunkGridWidth / 2))
            return false;
        pendingRadius = radius;
        return true;
    }

    public static int radius() {
        Interest current = interest;
        return current == null ? RADIUS : current.radius;
    }

    static Interest renderInterest() {
        Interest current = interest;
        return current != null && System.currentTimeMillis() < current.expires ? current : null;
    }

    static int viewportRadius(int width, int height, int tileScale, int nativeGridWidth) {
        if (width <= 0 || height <= 0 || tileScale <= 0) return RADIUS;
        // Invert native isometric projection. Native FBO dimensions already include zoom.
        // Six tiles cover the two lower rendered floors; one chunk ring preloads movement.
        double extent = width / (128d * tileScale) + height / (64d * tileScale) + 6d;
        int requested = (int) Math.ceil(extent / 8d) + 1;
        return Math.max(RADIUS, Math.min(requested, Math.min(MAX_RADIUS, nativeGridWidth / 2)));
    }

    public static int requestedRadius() {
        IsoPlayer player = IsoPlayer.getInstance();
        int index = player == null ? 0 : player.getPlayerNum();
        if (index < 0 || index >= IsoCamera.cameras.length) return RADIUS;
        return viewportRadius(
                IsoCamera.getOffscreenWidth(index),
                IsoCamera.getOffscreenHeight(index),
                Core.tileScale,
                IsoChunkMap.chunkGridWidth);
    }

    static int key(int x, int y) {
        return (x << 16) + y;
    }

    static boolean contains(int x, int y) {
        Interest current = interest;
        return current != null && current.contains(x, y, System.currentTimeMillis());
    }

    static boolean capacitySupported() {
        if (IsoChunkMap.chunkGridWidth < RADIUS * 2 + 1) return false;
        if (markersReady) return true;
        try {
            if (!AdminCoreNativeLighting.class.isAssignableFrom(LightingJNI.JNILighting.class))
                return false;
            for (var type : new Class<?>[] {IsoChunkMap.class, WorldStreamer.class, IsoCell.class})
                if (!type.getField(MARKER).getBoolean(null)) return false;
            for (String name : AdminCoreObserveTerrainPatch.TARGETS)
                if (!Class.forName(name)
                        .getField(AdminCoreObserveTerrainPatch.MARKER)
                        .getBoolean(null)) return false;
            if (!PlayerCamera.class
                    .getField(AdminCoreObserveProjectionPatch.MARKER)
                    .getBoolean(null)) return false;
            if (!Class.forName("zombie.vispoly.VisibilityPolygon2")
                    .getField(AdminCoreObserveVisibilityPatch.MARKER)
                    .getBoolean(null)) return false;
            markersReady = true;
            return true;
        } catch (ReflectiveOperationException | RuntimeException | LinkageError failure) {
            return false;
        }
    }

    static void update(IsoPlayer owner, float x, float y, long expires) {
        if (!GameClient.client || IsoWorld.instance == null || IsoWorld.instance.getCell() == null)
            return;
        var currentCell = IsoWorld.instance.getCell();
        int cx = Math.floorDiv((int) Math.floor(x), 8);
        int cy = Math.floorDiv((int) Math.floor(y), 8);
        if (currentCell != cell || owner != actor) clear();
        cell = currentCell;
        actor = owner;
        Interest previous = interest;
        interest = new Interest(cx, cy, expires, pendingRadius);
        IsoChunkMap.bSettingChunk.lock();
        try {
            if (map == null
                    || previous == null
                    || previous.x != cx
                    || previous.y != cy
                    || previous.radius != interest.radius) {
                IsoChunkMap old = map;
                map = new IsoChunkMap(cell);
                map.playerId = owner.getPlayerNum();
                map.worldX = cx;
                map.worldY = cy;
                // Transfer retained ownership before releasing outgoing chunks.
                var iterator = owned.entrySet().iterator();
                while (iterator.hasNext()) {
                    IsoChunk chunk = iterator.next().getValue();
                    if (contains(chunk.wx, chunk.wy)) {
                        if (!chunk.refs.contains(map)) chunk.refs.add(map);
                        if (old != null) chunk.refs.remove(old);
                        if (chunk.loaded) map.setChunkDirect(chunk, false);
                    } else {
                        release(chunk, old);
                        iterator.remove();
                    }
                }
            }
            long now = System.currentTimeMillis();
            int budget = now >= nextRequestAt ? REQUESTS_PER_TICK : 0;
            if (budget > 0) nextRequestAt = now + 100;
            // Load the center first, then progressively request rings. Never full scan the world.
            for (int radius = 0; radius <= interest.radius && budget > 0; radius++) {
                for (int dy = -radius; dy <= radius && budget > 0; dy++) {
                    for (int dx = -radius; dx <= radius && budget > 0; dx++) {
                        if (Math.max(Math.abs(dx), Math.abs(dy)) != radius) continue;
                        int wx = cx + dx, wy = cy + dy;
                        if (owned.containsKey(key(wx, wy))) continue;
                        var chunk =
                                map.LoadChunkForLater(
                                        wx, wy, wx - map.getWorldXMin(), wy - map.getWorldYMin());
                        if (chunk != null) {
                            owned.put(key(wx, wy), chunk);
                            if (chunk.loaded) accept(chunk);
                            budget--;
                        }
                    }
                }
            }
        } finally {
            IsoChunkMap.bSettingChunk.unlock();
        }
    }

    /** Native queue dispatch only knows local maps; extend dispatch without consuming the queue. */
    public static boolean accept(IsoChunk chunk) {
        if (accepting
                || map == null
                || chunk == null
                || !contains(chunk.wx, chunk.wy)
                || owned.get(key(chunk.wx, chunk.wy)) != chunk
                || !chunk.refs.contains(map)) return false;
        accepting = true;
        try {
            boolean accepted = map.setChunkDirect(chunk, false);
            if (accepted) {
                map.minHeight = Math.min(map.minHeight, chunk.minLevel);
                map.maxHeight = Math.max(map.maxHeight, chunk.maxLevel);
            }
            return accepted;
        } finally {
            accepting = false;
        }
    }

    /** Background download thread reads only this immutable volatile grant snapshot. */
    public static boolean shouldRequest(IsoChunk chunk) {
        return chunk != null && contains(chunk.wx, chunk.wy);
    }

    public static IsoGameCharacter physicalCharacter(
            IsoChunkMap nativeMap, IsoGameCharacter original) {
        return actor != null
                        && map != nativeMap
                        && cell != null
                        && actor.getPlayerNum() >= 0
                        && actor.getPlayerNum() < cell.chunkMap.length
                        && nativeMap == cell.chunkMap[actor.getPlayerNum()]
                        && AdminCoreObserveCamera.active()
                ? actor
                : original;
    }

    public static IsoChunk chunk(IsoCell requestedCell, int x, int y) {
        if (requestedCell != cell || !contains(x, y)) return null;
        var found = owned.get(key(x, y));
        return found != null && found.loaded ? found : null;
    }

    public static IsoGridSquare square(IsoCell requestedCell, int x, int y, int z) {
        if (z < -32 || z > 31) return null;
        var found = chunk(requestedCell, Math.floorDiv(x, 8), Math.floorDiv(y, 8));
        return found == null
                ? null
                : found.getGridSquare(Math.floorMod(x, 8), Math.floorMod(y, 8), z);
    }

    /** Native renderers read the viewing slot's map. Swap only for the render call's lifetime. */
    static boolean beginRender(int playerIndex) {
        if (map == null
                || cell == null
                || actor == null
                || renderOrigin != null
                || playerIndex != actor.getPlayerNum()
                || !AdminCoreObserveCamera.renderAllowed(playerIndex)) return false;
        renderSlot = playerIndex;
        renderOrigin = cell.chunkMap[playerIndex];
        cell.chunkMap[playerIndex] = map;
        return true;
    }

    static void endRender() {
        if (renderOrigin != null
                && cell != null
                && renderSlot >= 0
                && cell.chunkMap[renderSlot] == map) cell.chunkMap[renderSlot] = renderOrigin;
        renderOrigin = null;
        renderSlot = -1;
    }

    static void clear() {
        interest = null;
        endRender();
        IsoChunkMap.bSettingChunk.lock();
        try {
            for (IsoChunk chunk : new ArrayList<>(owned.values())) {
                try {
                    release(chunk, map);
                } catch (RuntimeException | LinkageError failure) {
                    LOGGER.warn("Could not release an observer terrain reference", failure);
                }
            }
            owned.clear();
            map = null;
            cell = null;
            actor = null;
            nextRequestAt = 0;
        } finally {
            IsoChunkMap.bSettingChunk.unlock();
        }
    }

    private static void release(IsoChunk chunk, IsoChunkMap owner) {
        if (owner == null || !chunk.refs.remove(owner) || !chunk.refs.isEmpty()) return;
        IsoChunkMap.SharedChunks.remove(key(chunk.wx, chunk.wy), chunk);
        if (chunk.loaded) {
            chunk.removeFromWorld();
            ChunkSaveWorker.instance.Add(chunk);
        }
        // Pending chunks with no references are cancelled/reused by native WorldStreamer.
    }
}
