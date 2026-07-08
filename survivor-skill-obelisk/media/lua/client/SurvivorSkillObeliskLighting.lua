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

local function matcherFor(idx)
    local smallName = "atf_obelisks_sm_01_" .. idx
    local largeName = "atf_obelisks_lg_01_" .. idx
    return function(name)
        return name == smallName or name == largeName
    end
end

for i = 1, #CONFIGS do
    local cfg = CONFIGS[i]
    local color, idx, r, g, b, radius = cfg[1], cfg[2], cfg[3], cfg[4], cfg[5], cfg[6]
    UnpoweredGlow.register({
        name = "survivor_skill_obelisk_" .. color,
        match = matcherFor(idx),
        r = r,
        g = g,
        b = b,
        radius = radius,
    })
end
