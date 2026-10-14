package com.sentientsimulations.projectzomboid.admincore;

import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import zombie.core.PerformanceSettings;
import zombie.core.opengl.RenderSettings;
import zombie.core.textures.ColorInfo;
import zombie.iso.IsoCamera;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;

/** Temporary render answers only. Never writes LOS, room exploration, or player/chunk ownership. */
public final class AdminCoreObserveRender {
    private static final Logger LOGGER = LoggerFactory.getLogger(AdminCoreObserveRender.class);
    static final int CHUNK_RADIUS = 3;
    private static final ThreadLocal<Region> RENDER = new ThreadLocal<>();
    private static final ThreadLocal<SceneLight> SCENE_LIGHT = new ThreadLocal<>();
    private static final Set<IsoChunk> cachedChunks = new HashSet<>();
    private static final Map<IsoChunk, ColorInfo[]> colors = new IdentityHashMap<>();
    private static final Map<IsoChunk, boolean[]> lightingFlags = new IdentityHashMap<>();
    private static final Map<IsoChunk, ColorInfo[][]> colorViews = new IdentityHashMap<>();
    private static final Map<IsoChunk, Boolean> nativeReadiness = new IdentityHashMap<>();
    private static final Set<IsoChunk> fallbackChunks = new HashSet<>();
    private static Region cachedRegion;
    private static SceneLight cachedLight;
    private static long nextLightRefresh;

    private AdminCoreObserveRender() {}

    record SceneLight(float r, float g, float b) {
        static SceneLight from(RenderSettings.PlayerRenderSettings settings) {
            float ambient = settings.getAmbient();
            // Match GameTime's packed outdoor skylight and JNI's 8-bit color conversion.
            // GameTime packs B in the low byte; JNILighting reads that byte into ColorInfo.r.
            // Ambient alone is only half the native sky brightness below saturation.
            return new SceneLight(
                    skyChannel(settings.getBmod(), ambient),
                    skyChannel(settings.getGmod(), ambient),
                    skyChannel(settings.getRmod(), ambient));
        }

        private static float skyChannel(float tint, float ambient) {
            return (int) (unit((tint * 2f) * ambient) * 255f) / 255f;
        }

        private static float unit(float value) {
            return Float.isFinite(value) ? Math.max(0f, Math.min(1f, value)) : 0f;
        }

        boolean differs(SceneLight previous) {
            return previous == null
                    || Math.abs(r - previous.r) > 1f / 255f
                    || Math.abs(g - previous.g) > 1f / 255f
                    || Math.abs(b - previous.b) > 1f / 255f;
        }
    }

    record Region(int playerIndex, int chunkX, int chunkY, int z, int radius) {
        Region(int playerIndex, int chunkX, int chunkY, int z) {
            this(playerIndex, chunkX, chunkY, z, CHUNK_RADIUS);
        }

        boolean contains(int player, int x, int y, int squareZ) {
            return player == playerIndex
                    && Math.abs((long) Math.floorDiv(x, 8) - chunkX) <= radius
                    && Math.abs((long) Math.floorDiv(y, 8) - chunkY) <= radius
                    && squareZ >= z - 2
                    && squareZ <= z;
        }
    }

    public static boolean begin() {
        // Nested render calls reuse the outer scope; only its finally may restore the map.
        if (RENDER.get() != null) return false;
        return AdminCoreObserveCamera.selectSafely(
                false,
                () -> {
                    var frame = IsoCamera.frameState;
                    if (!AdminCoreObserveCamera.renderAllowed(frame.playerIndex)
                            || frame.camCharacterSquare == null) {
                        if (cachedRegion == null || cachedRegion.playerIndex == frame.playerIndex)
                            clear();
                        return false;
                    }
                    var interest = AdminCoreObserveStreaming.renderInterest();
                    var region =
                            new Region(
                                    frame.playerIndex,
                                    interest == null
                                            ? Math.floorDiv(
                                                    (int) Math.floor(frame.camCharacterX), 8)
                                            : interest.x(),
                                    interest == null
                                            ? Math.floorDiv(
                                                    (int) Math.floor(frame.camCharacterY), 8)
                                            : interest.y(),
                                    (int) Math.floor(frame.camCharacterZ),
                                    interest == null ? CHUNK_RADIUS : interest.radius());
                    if (cachedRegion != null
                            && (cachedRegion.playerIndex != region.playerIndex
                                    || cachedRegion.z != region.z)) {
                        clear();
                    }
                    cachedRegion = region;
                    AdminCoreObserveStreaming.beginRender(frame.playerIndex);
                    // At most 361 existing chunks. No requests, stream movement, or scans of the
                    // world.
                    var cell = IsoWorld.instance.getCell();
                    var iterator = cachedChunks.iterator();
                    while (iterator.hasNext()) {
                        IsoChunk previous = iterator.next();
                        if (Math.abs((long) previous.wx - region.chunkX) > region.radius
                                || Math.abs((long) previous.wy - region.chunkY) > region.radius
                                || cell.getChunkForGridSquare(
                                                previous.wx * 8, previous.wy * 8, region.z)
                                        != previous) {
                            iterator.remove();
                            colors.remove(previous);
                            lightingFlags.remove(previous);
                            colorViews.remove(previous);
                            nativeReadiness.remove(previous);
                            fallbackChunks.remove(previous);
                            invalidate(previous, region);
                        }
                    }
                    for (int x = region.chunkX - region.radius;
                            x <= region.chunkX + region.radius;
                            x++) {
                        for (int y = region.chunkY - region.radius;
                                y <= region.chunkY + region.radius;
                                y++) {
                            IsoChunk chunk = cell.getChunkForGridSquare(x * 8, y * 8, region.z);
                            if (chunk != null && chunk.loaded) {
                                boolean entered = cachedChunks.add(chunk);
                                boolean ready = nativeLightReady(chunk, frame.playerIndex);
                                Boolean previous = nativeReadiness.put(chunk, ready);
                                if (entered || (previous != null && previous != ready))
                                    invalidate(chunk, region);
                            }
                        }
                    }
                    var light =
                            SceneLight.from(
                                    RenderSettings.getInstance()
                                            .getPlayerSettings(frame.playerIndex));
                    long now = System.currentTimeMillis();
                    // Native JNI dirtiness cannot update absent remote lighting. Only a material
                    // climate change refreshes these fallback FBOs, at most four times a second.
                    if (cachedLight == null) cachedLight = light;
                    else if (light.differs(cachedLight) && now >= nextLightRefresh) {
                        for (IsoChunk chunk : fallbackChunks) invalidate(chunk, region);
                        cachedLight = light;
                        nextLightRefresh = now + 250;
                    }
                    SCENE_LIGHT.set(cachedLight == null ? light : cachedLight);
                    RENDER.set(region);
                    return true;
                });
    }

    public static void end(boolean entered) {
        if (entered) {
            RENDER.remove();
            SCENE_LIGHT.remove();
            AdminCoreObserveStreaming.endRender();
        }
    }

    public static boolean suppressVisibilityMask(int playerIndex) {
        Region region = RENDER.get();
        return region != null
                && region.playerIndex == playerIndex
                && AdminCoreObserveCamera.selectSafely(
                        false, () -> AdminCoreObserveCamera.renderAllowed(playerIndex));
    }

    public static boolean visible(IsoGridSquare square, int playerIndex) {
        Region region = RENDER.get();
        return region != null
                && square != null
                && square.getChunk() != null
                && region.contains(playerIndex, square.x, square.y, square.z);
    }

    public static ColorInfo color(IsoGridSquare square, int playerIndex, ColorInfo original) {
        if (!visible(square, playerIndex)) return original;
        if (original != null && nativeSceneReady(square, playerIndex)) return original;
        // Independent per-square render color, never the native lighting object's mutable value.
        IsoChunk chunk = square.getChunk();
        // Exactly 192 color slots per chunk; replaced square instances retain no references.
        // A chunk loaded during rendering can wait until next frame before receiving a cache.
        if (colors.size() >= AdminCoreObserveStreaming.MAX_CHUNKS && !colors.containsKey(chunk))
            return original;
        ColorInfo[] cache = colors.computeIfAbsent(chunk, ignored -> new ColorInfo[64 * 3]);
        int position = (square.z - RENDER.get().z + 2) * 64 + (square.y & 7) * 8 + (square.x & 7);
        ColorInfo result = cache[position];
        if (result == null) cache[position] = result = new ColorInfo();
        fallbackChunks.add(chunk);
        SceneLight light = SCENE_LIGHT.get();
        result.set(
                light == null ? 1f : light.r,
                light == null ? 1f : light.g,
                light == null ? 1f : light.b,
                original == null ? 1f : original.a);
        return result;
    }

    static boolean nativeLightReady(IsoChunk chunk, int playerIndex) {
        return chunk != null
                && playerIndex >= 0
                && playerIndex < chunk.lightingNeverDone.length
                && !chunk.lightingNeverDone[playerIndex];
    }

    static boolean nativeSceneReady(IsoGridSquare square, int playerIndex) {
        return square != null
                && nativeLightReady(square.getChunk(), playerIndex)
                && playerIndex < square.lighting.length
                && square.lighting[playerIndex] instanceof AdminCoreNativeLighting nativeLighting
                && (nativeLighting.uacObserverVisibilityFlags() & 2) != 0;
    }

    public static int vertex(IsoGridSquare square, int vertex, int playerIndex, int original) {
        if (!visible(square, playerIndex) || nativeSceneReady(square, playerIndex)) return original;
        ColorInfo color = color(square, playerIndex, null);
        if (color == null) return original;
        int difference = square.z - RENDER.get().z;
        // Match native JNILighting's shading of lower floors without changing its cache.
        float scale = difference < -1 || (difference == -1 && vertex < 4) ? .85f : 1f;
        return 0xFF000000
                | (int) (color.r * scale * 255f)
                | (int) (color.g * scale * 255f) << 8
                | (int) (color.b * scale * 255f) << 16;
    }

    public static float level(IsoGridSquare square, int playerIndex, float original) {
        if (!visible(square, playerIndex) || nativeSceneReady(square, playerIndex)) return original;
        ColorInfo color = color(square, playerIndex, null);
        return color == null ? original : Math.max(color.r, Math.max(color.g, color.b));
    }

    /** Remote chunks have no physical-player lighting pass; do not change its pending flags. */
    public static boolean[] lightingPending(IsoChunk chunk, boolean[] original) {
        Region region = RENDER.get();
        if (region == null
                || chunk == null
                || !chunk.loaded
                || original == null
                || region.playerIndex < 0
                || region.playerIndex >= original.length
                || Math.abs((long) chunk.wx - region.chunkX) > region.radius
                || Math.abs((long) chunk.wy - region.chunkY) > region.radius
                || (lightingFlags.size() >= AdminCoreObserveStreaming.MAX_CHUNKS
                        && !lightingFlags.containsKey(chunk))) return original;
        boolean[] view =
                lightingFlags.computeIfAbsent(chunk, ignored -> new boolean[original.length]);
        System.arraycopy(original, 0, view, 0, original.length);
        view[region.playerIndex] = false;
        return view;
    }

    /** The older renderer reads this array directly instead of calling getLightInfo(). */
    public static ColorInfo[] lightInfo(IsoGridSquare square, ColorInfo[] original) {
        Region region = RENDER.get();
        if (region == null
                || original == null
                || !visible(square, region.playerIndex)
                || region.playerIndex < 0
                || region.playerIndex >= original.length) return original;
        IsoChunk chunk = square.getChunk();
        if (nativeSceneReady(square, region.playerIndex)) return original;
        if (colorViews.size() >= AdminCoreObserveStreaming.MAX_CHUNKS
                && !colorViews.containsKey(chunk)) return original;
        ColorInfo[][] cache = colorViews.computeIfAbsent(chunk, ignored -> new ColorInfo[64 * 3][]);
        int position = (square.z - region.z + 2) * 64 + (square.y & 7) * 8 + (square.x & 7);
        ColorInfo[] view = cache[position];
        if (view == null) cache[position] = view = new ColorInfo[original.length];
        System.arraycopy(original, 0, view, 0, original.length);
        view[region.playerIndex] = color(square, region.playerIndex, original[region.playerIndex]);
        return view;
    }

    public static void clear() {
        RENDER.remove();
        SCENE_LIGHT.remove();
        AdminCoreObserveStreaming.endRender();
        Region previous = cachedRegion;
        cachedRegion = null;
        cachedLight = null;
        nextLightRefresh = 0;
        colors.clear();
        lightingFlags.clear();
        colorViews.clear();
        nativeReadiness.clear();
        fallbackChunks.clear();
        Throwable first = null;
        if (previous != null)
            for (IsoChunk chunk : cachedChunks) {
                try {
                    invalidate(chunk, previous);
                } catch (RuntimeException | LinkageError failure) {
                    if (first == null) first = failure;
                }
            }
        cachedChunks.clear();
        if (first != null)
            LOGGER.warn("Could not invalidate an unloaded observer render cache", first);
    }

    private static void invalidate(IsoChunk chunk, Region region) {
        if (!PerformanceSettings.fboRenderChunk) return;
        for (int z = Math.max(-32, region.z - 2); z <= Math.min(31, region.z); z++) {
            chunk.getRenderLevels(region.playerIndex).invalidateLevel(z, 32L);
        }
    }
}
