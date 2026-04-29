-- Temporary compatibility shield for mod packs that clobber core Lua globals.
-- Safe to remove once conflicting mods are fixed upstream.

local RAW_PCALL = pcall
local RAW_IPAIRS = ipairs
local RAW_PAIRS = pairs

local warnedOnce = false

local function fallbackIpairs(tbl)
    local i = 0
    return function()
        i = i + 1
        local v = tbl and tbl[i]
        if v ~= nil then
            return i, v
        end
    end
end

local function fallbackPairs(tbl)
    return next, tbl, nil
end

local function fallbackPcall(fn, ...)
    -- Last-resort fallback: preserves callability if global pcall was wiped.
    -- It does not trap errors like real pcall.
    return true, fn(...)
end

local function repairLuaGlobals()
    local repaired = false

    if type(_G.ipairs) ~= "function" then
        _G.ipairs = type(RAW_IPAIRS) == "function" and RAW_IPAIRS or fallbackIpairs
        repaired = true
    end

    if type(_G.pairs) ~= "function" then
        _G.pairs = type(RAW_PAIRS) == "function" and RAW_PAIRS or fallbackPairs
        repaired = true
    end

    if type(_G.pcall) ~= "function" then
        _G.pcall = type(RAW_PCALL) == "function" and RAW_PCALL or fallbackPcall
        repaired = true
    end

    if repaired and not warnedOnce then
        warnedOnce = true
        print("[CSR][Compat] Restored Lua globals (ipairs/pairs/pcall) after mod conflict")
    end
end

repairLuaGlobals()

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(repairLuaGlobals)
end
