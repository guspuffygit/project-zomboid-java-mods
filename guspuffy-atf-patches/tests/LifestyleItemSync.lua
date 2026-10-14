-- Execute the actual shared lookup and server dispatch against isolated inventory trees.
local root = (arg[1] or "guspuffy-atf-patches/build/vendor-fixtures") .. "/mod-LifestyleHobbies/common/media/lua/"
local sharedRoot = arg[2] or root
if sharedRoot:sub(-1) ~= "/" and sharedRoot:sub(-1) ~= "\\" then sharedRoot = sharedRoot .. "/" end
local checks, callback = 0, nil
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
Events = setmetatable({}, { __index = function(self, key)
    local event = { Add = function(fn)
        if key == "OnClientCommand" then callback = fn end
    end }
    rawset(self, key, event)
    return event
end })
isServer = function() return true end
isClient = function() return false end
require = function() return {} end
dofile(arg[4] or "guspuffy-atf-patches/media/lua/server/ATFPatches_LifestyleSyncPolicy.lua")
LSUtil = { debugPrint = function() end }
dofile(sharedRoot .. "shared/LSSync.lua")
local function container(items)
    local value = { items = items, lookups = 0 }
    function value:getFirstEvalRecurse(predicate)
        self.lookups = self.lookups + 1
        for _, item in ipairs(self.items) do
            if predicate(item) then return item end
            if item.getInventory then
                local result = item:getInventory():getFirstEvalRecurse(predicate)
                if result then return result end
            end
        end
        return nil
    end
    function value:getItems()
        return { size = function() return #items end, get = function(_, index) return items[index + 1] end }
    end
    return value
end
local function item(id)
    return { getID = function() return id end, getFullType = function() return "Moveables.Moveable" end }
end
local top, nested, deep, similar = item(1), item(2), item(3), item(4)
local inner = container({deep, similar})
local outer = container({nested, {getID=function() return 11 end, getInventory=function() return inner end}})
local inventory = container({top, {getID=function() return 10 end, getInventory=function() return outer end}})
local player = { getInventory = function() return inventory end }
local sent = {}
LSSync.transmitItemMovData = function(value, sender, obj, keys, data, stats)
    sent[#sent + 1] = {value=value, sender=sender, keys=keys, data=data, stats=stats}
end
dofile(root .. "server/LSservercommands.lua")
check(type(callback) == "function", "Actual server dispatcher registered")
for _, expected in ipairs({top,nested,deep,similar}) do
    local keys, data, stats = {customName="name"}, {value=7}, {value=8}
    local before = #sent
    callback("LS", "SyncItemData_FromPlayer", player, {expected:getID(),keys,data,stats})
    check(#sent == before + 1 and sent[#sent].value == expected, "Current exact identity resolves across nested bags")
    check(sent[#sent].sender == player and sent[#sent].keys == keys and sent[#sent].data == data and sent[#sent].stats == stats,
        "Sender and synchronization payload preserved")
end
table.remove(inner.items,1)
local before = #sent
callback("LS", "SyncItemData_FromPlayer", player, {3})
check(#sent == before, "Removed or transferred item does not synchronize from another inventory")
callback("LS", "SyncItemData_FromPlayer", player, {999})
check(#sent == before, "Unknown item does not transmit")
callback("LS", "SyncItemData_FromPlayer", player, {"3"})
check(#sent == before, "Different identity type does not match")
callback("LS", "SyncItemData_FromPlayer", player, {})
check(#sent == before, "Missing identity does not match")
callback("OTHER", "SyncItemData_FromPlayer", player, {1})
check(#sent == before, "Unrelated module is untouched")
-- Healthy native recursive lookup already works before the redundant fallback is removed.
check(LSSync.getItemServer(2,inventory) == nested and LSSync.getItemServer(4,inventory) == similar,
    "Actual shared helper recurses rather than the old audit's top-level-only stub")
if arg[3] ~= "baseline" then
    callback("LS", "SyncItemData_FromPlayer", player, nil)
    callback("LS", "SyncItemData_FromPlayer", nil, {1})
    local missing = {getInventory=function() return nil end}
    callback("LS", "SyncItemData_FromPlayer", missing, {1})
    check(#sent == before, "Missing sender, payload or inventory fails without transmitting")
    bad = true
    callback("LS", "SyncItemData_FromPlayer", player, {999})
    check(#sent == before, "Unrelated global cannot activate a broken bag-parent fallback")
end
print("PASS: " .. checks .. " Lifestyle item synchronization checks")
