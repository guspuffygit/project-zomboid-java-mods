local checks = 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
require = function() end
local callbacks = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local event = {
            Add = function(callback)
                callbacks[name] = callbacks[name] or {}
                table.insert(callbacks[name], callback)
            end,
        }
        rawset(t, name, event)
        return event
    end,
})
local native, external, labels = 0, 0, 0
ISWorldMap = {
    render = function()
        native = native + 1
    end,
}
WorldMapOptions = {
    getVisibleOptions = function()
        return {}
    end,
    synchUI = function() end,
}
local otherOption = {
    getName = function()
        return "Other mod"
    end,
}
WorldMapOptions_visibleOptionsHooks = {
    function(result)
        table.insert(result, otherOption)
    end,
}
UIFont = { Small = 1 }
PZMath = { floor = math.floor }
getTimestampMs = function()
    return 0
end
Translator = {
    getLanguage = function()
        return "EN"
    end,
}
getText = function(value)
    return value
end
getTextManager = function()
    return {
        getFontHeight = function()
            return 12
        end,
        MeasureStringX = function()
            return 60
        end,
    }
end
local player = {
    getUsername = function()
        return "owner"
    end,
}
getPlayer = function()
    return player
end
AVCS = {
    cacheRevision = 1,
    dbByPlayerID = { owner = { [1] = true } },
    dbByVehicleSQLID = { [1] = { CarModel = "Base.Car", LastLocationX = 50, LastLocationY = 50 } },
}
local map = {
    getWidth = function()
        return 100
    end,
    getHeight = function()
        return 100
    end,
    javaObject = {
        DrawTextureScaledColor = function() end,
        DrawTextCentre = function()
            labels = labels + 1
        end,
    },
    mapAPI = {
        worldToUIX = function(_, x)
            return x
        end,
        worldToUIY = function(_, x, y)
            return y
        end,
    },
}
local path = "another-vehicle-claim-system/media/lua/client/AVCSMapRenderer.lua"
dofile(path)
local options = WorldMapOptions:getVisibleOptions()
check(#options == 2 and options[1] == otherOption, "Other map hooks coexist with AVCS")
local filter = options[2]
filter:setValue(false)
local original = ISWorldMap.render
ISWorldMap.render = function(self)
    external = external + 1
    original(self)
end
local externalWrapper = ISWorldMap.render
dofile(path)
check(ISWorldMap.render == externalWrapper, "Reload retains later wrappers from other mods")
check(
    #WorldMapOptions_visibleOptionsHooks == 2 and #WorldMapOptions:getVisibleOptions() == 2,
    "Reload adds no duplicate option"
)
check(
    #callbacks.OnSafehousesChanged == 1 and #callbacks.SyncFaction == 1,
    "Reload adds no duplicate event callback"
)
check(
    not filter:getValue() and WorldMapOptions:getVisibleOptions()[2] == filter,
    "Reload preserves the player's filter and option identity"
)
ISWorldMap.render(map)
check(native == 1 and external == 1 and labels == 0, "Disabled filter stays disabled after reload")
filter:setValue(true)
ISWorldMap.render(map)
check(
    native == 2 and external == 2 and labels == 1,
    "One base render and one marker render after two loads"
)
AVCS.dbByVehicleSQLID[1].LastLocationX = 1000
ISWorldMap.render(map)
check(labels == 2, "Stable player keeps the current renderer cache before invalidation")
callbacks.SyncFaction[1]()
ISWorldMap.render(map)
check(labels == 2, "Persistent callback invalidates the current cache after reload")
print("PASS: " .. checks .. " map reload checks")
