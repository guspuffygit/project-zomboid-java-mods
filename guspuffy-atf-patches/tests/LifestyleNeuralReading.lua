-- Optional arg2 is the read-only Lifestyle media/lua folder. It proves the
-- current schema through the actual invention writer and Neural Hat reader.
local root = (arg[1] or "guspuffy-atf-patches/build/vendor-fixtures") .. "/"
local checks, durationCalls, hatData, state = 0, 0, {}, 1
local function check(ok, why)
    assert(ok, why)
    checks = checks + 1
end
local function noop() end
require = function()
    return nil
end
ItemBodyLocation = { HAT = "Hat" }
ISReadABook = {
    getDuration = function()
        durationCalls = durationCalls + 1
        return 300
    end,
}
local hat = {
    getType = function()
        return "NeuralHat"
    end,
    getVisual = function()
        return {
            getTextureChoice = function()
                return state
            end,
        }
    end,
    getModData = function()
        return hatData
    end,
}
local reader = {
    getWornItems = function()
        return {
            getItem = function()
                return hat
            end,
        }
    end,
    getModData = function()
        return {}
    end,
}
local current
if arg[2] then
    Events = { OnGameStart = { Add = noop } }
    LSUtil = {}
    LSUtil.deepCopy = function(value)
        if type(value) ~= "table" then
            return value
        end
        local copy = {}
        for k, v in pairs(value) do
            copy[k] = LSUtil.deepCopy(v)
        end
        return copy
    end
    LSInv = { doDataTransmit = noop, updateInventionScripts = noop }
    dofile(arg[2] .. "/shared/Inventions/inventions_defs.lua")
    dofile(arg[2] .. "/client/Inventions/InventionsMenu.lua")
    dofile(arg[2] .. "/client/Inventions/NeuralHat.lua")
    local created = InventionsMenu.updateInvData(hat, "NeuralHat")
    check(created == hatData.movableData, "Actual invention writer creates movableData")
    check(
        type(created.inventionData) == "table" and hatData.invData == nil,
        "Actual writer uses inventionData with no top-level invData"
    )
    current = created.inventionData
    check(
        LS_NeuralHat.getCompleteInfo(reader).data == current,
        "Actual Neural Hat reader uses that same current data"
    )
else
    current = { efficiencyMult = { 0.1, 0.2, 0.05 }, fastRead = false }
    hatData = { movableData = { inventionData = current } }
end
dofile(root .. "mod-LifestyleHobbies/common/media/lua/shared/TimedActions/hooks/Read.lua")
check(
    ISReadABook.getDuration({ character = reader }) == 300,
    "Default current-schema efficiency preserves the multiplier clamp"
)
current.efficiencyMult[2] = 2
current.fastRead = true
for _, case in ipairs({ { 1, 67.5 }, { 3, 105 }, { 4, 75 }, { 5, 45 } }) do
    state = case[1]
    local before = durationCalls
    check(
        ISReadABook.getDuration({ character = reader }) == case[2],
        "Current schema applies supported state " .. state
    )
    check(durationCalls == before + 1, "Native duration called once for current schema")
end
state = 1
hatData.invData = { efficiencyMult = { 1, 100 }, fastRead = true }
check(
    ISReadABook.getDuration({ character = reader }) == 67.5,
    "Current item schema takes priority over conflicting legacy data"
)
hatData.movableData.inventionData = false
check(
    ISReadABook.getDuration({ character = reader }) == 300,
    "Malformed current data cannot take a conflicting legacy bonus"
)
hatData.movableData.inventionData = nil
check(
    ISReadABook.getDuration({ character = reader }) == 15,
    "Legacy-only item remains supported when current data is absent"
)
hatData = { invData = { efficiencyMult = { 1, 2 }, fastRead = true } }
check(
    ISReadABook.getDuration({ character = reader }) == 67.5,
    "Older top-level invData retains its reading bonus"
)
for _, value in ipairs({
    false,
    "invalid",
    {},
    { efficiencyMult = true },
    { efficiencyMult = { 1, 0 } },
    { efficiencyMult = { 1, -1 } },
    { efficiencyMult = { 1, "bad" } },
    { efficiencyMult = { 1, math.huge } },
    { efficiencyMult = { 1, 0 / 0 } },
}) do
    hatData = { movableData = { inventionData = value } }
    check(
        ISReadABook.getDuration({ character = reader }) == 300,
        "Malformed current schema keeps the native duration"
    )
end
print("PASS: " .. checks .. " Neural Hat current/legacy schema checks")
