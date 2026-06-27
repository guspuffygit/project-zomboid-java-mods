--
-- SurvivorSkillObeliskLighting.lua
-- Glow config for the survivor-skill obelisks. The actual light-source
-- bookkeeping lives in UnpoweredGlow.lua.
--

require "UnpoweredGlow"

-- Warm gold glow, ~6 tile radius. Floats are 0..1.
UnpoweredGlow.register({
    spritePrefix = "survivor_skill_obelisk_",
    r = 1.00,
    g = 0.75,
    b = 0.35,
    radius = 6,
})
