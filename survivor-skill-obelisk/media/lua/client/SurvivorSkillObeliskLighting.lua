--
-- SurvivorSkillObeliskLighting.lua
-- Glow config for the survivor-skill obelisks. The actual light-source
-- bookkeeping lives in UnpoweredGlow.lua.
--

require("UnpoweredGlow")

-- Cool blue glow, ~3 tile radius. Floats are 0..1.
UnpoweredGlow.register({
    spritePrefix = "survivor_skill_obelisk_",
    r = 0.15,
    g = 0.35,
    b = 1.00,
    radius = 3,
})
