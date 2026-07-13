--
-- SurvivorSkillObeliskLighting.lua
-- Per-color radial glow for the survivor-skill obelisks. Each colored variant
-- gets its own UnpoweredGlow registration matching both the small and large
-- sheets. RGB values were sampled from the artist's `_on` overlay pixels so
-- the tile-radius halo matches the crisp outline that
-- SurvivorSkillObeliskOverlay draws on top of the base sprite.
--
-- Silver (index 1) intentionally has no entry: its overlay is a black rim
-- (a "cold" obelisk), and IsoLightSource only adds light — no way to render
-- an anti-glow with a radial source. It still gets the overlay outline.
--

require("UnpoweredGlow")

-- { color-name, sprite-index, r, g, b, radius }
local CONFIGS = {
    { "Onyx", 0, 0.80, 0.80, 0.80, 3 },
    { "Ruby", 2, 0.80, 0.10, 0.10, 3 },
    { "Magenta", 3, 0.75, 0.10, 0.60, 3 },
    { "Amethyst", 4, 0.60, 0.10, 0.75, 3 },
    { "Sapphire", 5, 0.30, 0.10, 0.75, 3 },
    { "Cobalt", 6, 0.10, 0.40, 0.75, 3 },
    { "Turquoise", 7, 0.10, 0.75, 0.75, 3 },
    { "Aqua", 8, 0.10, 0.75, 0.60, 3 },
    { "Emerald", 9, 0.10, 0.75, 0.30, 3 },
    { "Peridot", 10, 0.40, 0.75, 0.10, 3 },
    { "Topaz", 11, 0.75, 0.75, 0.10, 3 },
    { "Citrine", 12, 0.75, 0.60, 0.10, 3 },
    { "Amber", 13, 0.75, 0.35, 0.10, 3 },
}

-- Sheet is 8 columns wide, row-major, and horizontally flipped for E: row 0
-- (idx 0-7) maps to 7-idx, row 1 (idx 8-13) maps to 23-idx. No sm_01 mirror
-- sheet exists yet, so only the lg mirror name is added here.
local function largeMirrorIndex(idx)
    if idx < 8 then
        return 7 - idx
    end
    return 23 - idx
end

-- Exact `sprites` lists (not a `match` closure) so UnpoweredGlow can serve all
-- 13 registrations from one hash lookup per streamed object — LoadGridsquare
-- fires per streamed square, and 13 closures × 3 compares each was measurably
-- hot in dense areas.
local function spritesFor(idx)
    return {
        "atf_obelisks_sm_01_" .. idx,
        "atf_obelisks_lg_01_" .. idx,
        "atf_obelisks_lg_01_mirror_" .. largeMirrorIndex(idx),
    }
end

for i = 1, #CONFIGS do
    local cfg = CONFIGS[i]
    local color, idx, r, g, b, radius = cfg[1], cfg[2], cfg[3], cfg[4], cfg[5], cfg[6]
    UnpoweredGlow.register({
        name = "survivor_skill_obelisk_" .. color,
        sprites = spritesFor(idx),
        r = r,
        g = g,
        b = b,
        radius = radius,
    })
end
