local root = arg[1]
assert(root, "Supply the patched vendor fixture root")
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function hasEntries(values)
    for _ in pairs(values) do
        return true
    end
    return false
end
local function list(values)
    return {
        size = function()
            return #values
        end,
        get = function(_, i)
            return values[i + 1]
        end,
    }
end
local function event()
    local callbacks = {}
    return {
        callbacks = callbacks,
        Add = function(fn)
            callbacks[fn] = true
        end,
        Remove = function(fn)
            callbacks[fn] = nil
        end,
    }
end
Events = {
    OnClientCommand = event(),
    OnReceiveGlobalModData = event(),
    OnServerStarted = event(),
    OnPreFillWorldObjectContextMenu = event(),
    OnPlayerUpdate = event(),
    OnSafehousesChanged = event(),
    OnWeaponHitCharacter = event(),
}
local required = {}
require = function(name)
    assert(name ~= "ISUI/ISSafetyUI", "Removed native module must not be required")
    required[name] = true
end
Capability = { AddItem = {} }
SandboxVars = {
    AllowExteriorGenerator = true,
    ElecShutModifier = -1,
    TrueMusicRadio = { TMRTerminalEjectsMusic = true, TMRChannel1 = 100, TMRChannel2 = 200 },
}
GameTime = {
    getInstance = function()
        return {
            getNightsSurvived = function()
                return 5
            end,
        }
    end,
}
GlobalMusic = { CassetteTest = {} }
local tables, sent, grants, sound, requests = {}, 0, 0, 0, {}
local now = 0
getTimestampMs = function()
    return now
end
ModData = {
    getOrCreate = function(key)
        tables[key] = tables[key] or {}
        return tables[key]
    end,
}
local allowed, adjacent, blocked, window, dead, online, room, failItem, throwAfterAdd =
    true, true, false, false, false, true, true, false, false
local inventoryItems = {}
local inventory = {
    hasRoomFor = function()
        return room
    end,
    contains = function(_, item)
        return inventoryItems[item] == true
    end,
    AddItem = function(_, item)
        if failItem then
            return nil
        end
        inventoryItems[item] = true
        grants = grants + 1
        if throwAfterAdd then
            error("after inventory mutation")
        end
        return item
    end,
}
local square, playerSquare, terminal
playerSquare = {
    getZ = function()
        return 0
    end,
    isAdjacentTo = function()
        return adjacent
    end,
    isBlockedTo = function()
        return blocked
    end,
    isWindowTo = function()
        return window
    end,
}
local fields = { LoadedCapacity = 3, StationControl = 100 }
local sprite = {
    getName = function()
        return "terminal_sprite"
    end,
    getProperties = function()
        return {
            get = function(_, name)
                return name == "CustomName" and "Terminal" or "Security"
            end,
        }
    end,
}
terminal = {
    getSquare = function()
        return square
    end,
    getSprite = function()
        return sprite
    end,
    getContainer = function()
        return {
            getType = function()
                return "securityterminal"
            end,
        }
    end,
    getModData = function()
        return fields
    end,
    transmitModData = function()
        sent = sent + 1
    end,
    getObjectIndex = function()
        return 0
    end,
}
local powered = true
square = {
    getX = function()
        return 10
    end,
    getY = function()
        return 20
    end,
    getZ = function()
        return 0
    end,
    getObjects = function()
        return list({ terminal })
    end,
    haveElectricity = function()
        return powered
    end,
    isOutside = function()
        return true
    end,
    playSound = function()
        sound = sound + 1
    end,
}
local roleAllowed = false
local player = {
    isDead = function()
        return dead
    end,
    getCurrentSquare = function()
        return playerSquare
    end,
    getInventory = function()
        return inventory
    end,
    getRole = function()
        return {
            hasCapability = function(_, cap)
                return cap == Capability.AddItem and roleAllowed
            end,
        }
    end,
}
getOnlinePlayers = function()
    return list(online and { player } or {})
end
getCell = function()
    return {
        getGridSquare = function(_, x, y, z)
            if x == 10 and y == 20 and z == 0 then
                return square
            end
        end,
    }
end
SafeHouse = {
    isSafehouseAllowInteract = function()
        return allowed
    end,
}
instanceItem = function(name)
    return {
        getFullType = function()
            return name
        end,
    }
end
sendAddItemToContainer = function()
    sent = sent + 1
end
local serverFile = root
    .. "/mod-TrueMusicRadio42/42.20/media/lua/server/TrueMusicRadio/TMRServer.lua"
dofile(serverFile)
local function args()
    return {
        x = 10,
        y = 20,
        z = 0,
        index = 0,
        media = "Tsarcraft.CassetteTest",
        capacity = fields.LoadedCapacity,
        revision = fields.ATFEjectionRevision or 0,
    }
end
local rejected = {
    {
        "unknown media",
        function(a)
            a.media = "Base.Axe"
        end,
    },
    {
        "unsupported catalog",
        function(a)
            a.media = "Tsarcraft.Unknown"
        end,
    },
    {
        "missing coordinates",
        function(a)
            a.x = nil
        end,
    },
    {
        "fractional coordinates",
        function(a)
            a.y = 20.5
        end,
    },
    {
        "NaN",
        function(a)
            a.x = 0 / 0
        end,
    },
    {
        "unloaded square",
        function(a)
            a.x = 100
        end,
    },
    {
        "invalid object",
        function(a)
            a.index = 2
        end,
    },
    {
        "wrong floor",
        function(a)
            a.z = 1
        end,
    },
    {
        "claimed terminal",
        function()
            allowed = false
        end,
        function()
            allowed = true
        end,
    },
    {
        "remote terminal",
        function()
            adjacent = false
        end,
        function()
            adjacent = true
        end,
    },
    {
        "blocked terminal",
        function()
            blocked = true
        end,
        function()
            blocked = false
        end,
    },
    {
        "through window",
        function()
            window = true
        end,
        function()
            window = false
        end,
    },
    {
        "dead player",
        function()
            dead = true
        end,
        function()
            dead = false
        end,
    },
    {
        "disconnected player",
        function()
            online = false
        end,
        function()
            online = true
        end,
    },
    {
        "full inventory",
        function()
            room = false
        end,
        function()
            room = true
        end,
    },
    {
        "sandbox disabled",
        function()
            SandboxVars.TrueMusicRadio.TMRTerminalEjectsMusic = false
        end,
        function()
            SandboxVars.TrueMusicRadio.TMRTerminalEjectsMusic = true
        end,
    },
}
for _, scenario in ipairs(rejected) do
    local a = args()
    scenario[2](a)
    TMRadioServer.EjectMedia(player, a)
    check(grants == 0, scenario[1] .. " rejected before grant")
    if scenario[3] then
        scenario[3]()
    end
end
local first = args()
TMRadioServer.EjectMedia(player, first)
check(
    grants == 1 and fields.LoadedCapacity == 2 and fields.ATFEjectionRevision == 1,
    "Healthy additional-media ejection consumes exactly one stock"
)
TMRadioServer.EjectMedia(player, first)
check(grants == 1 and fields.LoadedCapacity == 2, "Identical request cannot replay")
fields.LoadedCapacity, fields.ATFEjectionRevision = 111, 0
TMRadioServer.EjectMedia(player, args())
check(
    grants == 1 and fields.LoadedCapacity == 2 and fields.ATFEjectionRevision == 1,
    "Client object modData cannot refill or rewind private ledger"
)
dofile(serverFile)
TMRadioServer.EjectMedia(player, first)
check(grants == 1, "Lua reload retains consumed revision in private persistence")
failItem = true
TMRadioServer.EjectMedia(player, args())
check(grants == 1 and fields.LoadedCapacity == 2, "Failed unmutated grant preserves stock")
failItem, throwAfterAdd = false, true
local ambiguous = args()
TMRadioServer.EjectMedia(player, ambiguous)
TMRadioServer.EjectMedia(player, ambiguous)
check(
    grants == 2 and fields.LoadedCapacity == 1,
    "Exception after grant does not enable duplicate retry"
)
throwAfterAdd = false
TMRadioServer.ResetEjectStock(player, { x = 10, y = 20, z = 0, index = 0, capacity = 111 })
check(fields.LoadedCapacity == 1, "Ordinary player cannot reset stock")
roleAllowed = true
TMRadioServer.ResetEjectStock(player, { x = 10, y = 20, z = 0, index = 0, capacity = 111 })
check(
    fields.LoadedCapacity == 111 and fields.ATFEjectionRevision == 3,
    "Capable staff reset stock and invalidate prior requests"
)
roleAllowed = false
TMRadioServer.ResetEjectStock(player, { x = 10, y = 20, z = 0, index = 0, capacity = 0 })
check(fields.LoadedCapacity == 111, "Immediate role loss denies reset")
roleAllowed = true
powered, fields.StationControl, SandboxVars.TrueMusicRadio.TMRTerminalEjectsMusic = false, 0, false
TMRadioServer.ResetEjectStock(player, { x = 10, y = 20, z = 0, index = 0, capacity = 0 })
check(fields.LoadedCapacity == 0, "Staff can empty an unpowered disconnected terminal")
TMRadioServer.ResetEjectStock(player, { x = 10, y = 20, z = 0, index = 0, capacity = 111 })
check(fields.LoadedCapacity == 111, "Staff can reload stock while station ejection is disabled")
TMRadioServer.EjectMedia(player, args())
check(
    grants == 2 and fields.LoadedCapacity == 111,
    "Staff reset does not permit ordinary off-station ejection"
)
powered, fields.StationControl, SandboxVars.TrueMusicRadio.TMRTerminalEjectsMusic = true, 100, true
TMRadioServer.ResetEjectStock(player, { x = 10, y = 20, z = 0, index = 0, capacity = 0 })
TMRadioServer.EjectMedia(player, args())
check(grants == 2 and fields.LoadedCapacity == 0, "Empty stock rejects ejection")
isClient = function()
    return true
end
sendClientCommand = function(actor, module, command, a)
    assert(actor == player, "Terminal request must use the explicit selected local actor")
    requests[#requests + 1] = { module, command, a, actor }
end
dofile(root .. "/mod-TrueMusicRadio42/42.20/media/lua/client/TrueMusicRadio/UseTerminalMenu.lua")
check(
    required["TrueMusicRadio/TMRadio"] and not required.TMRadio,
    "Clean client require names the actual module path"
)
UseTerminalMenu.walkToFront = function()
    return true
end
fields.LoadedCapacity, fields.ATFEjectionRevision = 5, 4
UseTerminalMenu.onUseTerminal({}, player, terminal, "Eject", "Tsarcraft.CassetteTest")
check(
    fields.LoadedCapacity == 5 and grants == 2,
    "Multiplayer click does not decrement locally or create inventory"
)
local request = requests[#requests]
check(
    request[2] == "EjectMedia"
        and request[4] == player
        and request[3].capacity == 5
        and request[3].revision == 4
        and request[3].index == 0,
    "Click binds the selected actor and sends bounded terminal identity and stock revision"
)
UseTerminalMenu.onUseTerminal({}, player, terminal, "ReloadCapacity", nil)
check(
    requests[#requests][2] == "ResetEjectStock" and fields.LoadedCapacity == 5,
    "Admin click delegates reset to server"
)
local beforeWalk = #requests
adjacent = false
UseTerminalMenu.onUseTerminal({}, player, terminal, "Eject", "Tsarcraft.CassetteTest")
check(
    #requests == beforeWalk and hasEntries(Events.OnPlayerUpdate.callbacks),
    "Distant click waits for the queued walk"
)
adjacent = true
for callback in pairs(Events.OnPlayerUpdate.callbacks) do
    callback(player)
end
check(
    #requests == beforeWalk + 1 and not hasEntries(Events.OnPlayerUpdate.callbacks),
    "Arrival sends one request and detaches callback"
)
adjacent = false
UseTerminalMenu.onUseTerminal({}, player, terminal, "Eject", "Tsarcraft.CassetteTest")
now = 10001
for callback in pairs(Events.OnPlayerUpdate.callbacks) do
    callback(player)
end
check(
    #requests == beforeWalk + 1 and not hasEntries(Events.OnPlayerUpdate.callbacks),
    "Cancelled walk expires without sending or retaining callback"
)
now = 20000
UseTerminalMenu.onUseTerminal({}, player, terminal, "Eject", "Tsarcraft.CassetteTest")
now = 30001
for callback in pairs(Events.OnPlayerUpdate.callbacks) do
    callback({})
end
check(
    not hasEntries(Events.OnPlayerUpdate.callbacks),
    "A replacement character update expires the previous character's pending request"
)
dofile(
    root
        .. "/mod-after_the_fall_core_b42/42.14/media/lua/client/ATF_SafetySystem/ATF_AutomaticSafehouseSafety.lua"
)
check(
    ATF.HUD and #ATF.HUD.providers == 1 and not required["ISUI/ISSafetyUI"],
    "ATF safety provider loads without removed unused native import"
)
tables = {}
adjacent = true
fields.LoadedCapacity, fields.ATFEjectionRevision = 112, nil
TMRadioServer.EjectMedia(player, args())
check(grants == 2, "Initial migration rejects stock above the native maximum")
roleAllowed = false
TMRadioServer.ResetEjectStock(player, { x = 10, y = 20, z = 0, index = 0, capacity = 111 })
check(
    fields.LoadedCapacity == 112,
    "Malformed historical stock does not authorize ordinary recovery"
)
roleAllowed = true
TMRadioServer.ResetEjectStock(player, { x = 10, y = 20, z = 0, index = 0, capacity = 111 })
check(
    fields.LoadedCapacity == 111 and fields.ATFEjectionRevision == 1,
    "Capable staff can replace malformed unseeded historical stock"
)
tables = {}
fields.ATFEjectionRevision = nil
fields.LoadedCapacity = 111
adjacent = true
TMRadioServer.EjectMedia(player, args())
check(
    grants == 3 and fields.LoadedCapacity == 110,
    "Initial migration accepts bounded native maximum once"
)
fields.LoadedCapacity, fields.ATFEjectionRevision = 111, 0
TMRadioServer.EjectMedia(player, args())
check(
    grants == 3 and fields.LoadedCapacity == 110 and fields.ATFEjectionRevision == 1,
    "Later maximum-stock rewrite cannot repeat initialization"
)
print("PASS: " .. checks .. " TrueMusicRadio authority/require checks")
