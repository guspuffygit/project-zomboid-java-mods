--
-- LSDeathCompat.lua
-- Compat shim for the third-party Lifestyle mod's dead-player error spam.
--
-- PZ tears down the local player's inventory UI on death, so
-- getPlayerInventory(n) / getPlayerLoot(n) return nil until the player
-- respawns. Lifestyle indexes them unguarded from two places that keep
-- running while dead:
--   * CLSInv.UpdateInvScripts (CLSInv.lua) - called from LSAtEveryTick
--     (Events.OnTick), so ~60 "attempted index: inventoryPane of non-table:
--     null" errors per second on the death screen, and
--   * RefreshItemToolTip (local to LSPerMinute.lua) - called from
--     LSEveryMinute (Events.EveryOneMinute), once a minute.
--
-- CLSInv.UpdateInvScripts is a table field looked up at call time, so it's
-- wrapped in place. RefreshItemToolTip is a file-local, so LSEveryMinute is
-- re-registered with a guard; the whole per-minute pass is player-state
-- upkeep that has nothing to do while the inventory UI doesn't exist.
-- Idempotent: originals stashed as __lsdOrig*, flags as __lsd*Wrapped, so
-- hot-reload starts from originals. Inert if Lifestyle is absent.
--

LSDeathCompat = LSDeathCompat or {}

local function hasInventoryUi(playerNum)
    if playerNum == nil then
        return false
    end
    local inv = getPlayerInventory(playerNum)
    local loot = getPlayerLoot(playerNum)
    return inv ~= nil and inv.inventoryPane ~= nil and loot ~= nil and loot.inventoryPane ~= nil
end

local function wrapUpdateInvScripts()
    local cls = _G.CLSInv
    if cls == nil or type(cls.UpdateInvScripts) ~= "function" then
        return false
    end
    if cls.__lsdUpdateInvWrapped then
        return true
    end
    local orig = cls.__lsdOrigUpdateInvScripts or cls.UpdateInvScripts
    cls.__lsdOrigUpdateInvScripts = orig
    cls.__lsdUpdateInvWrapped = true
    cls.UpdateInvScripts = function(character)
        local playerNum = character and character:getPlayerNum()
        if not hasInventoryUi(playerNum) then
            return
        end
        return orig(character)
    end
    return true
end

local function wrapEveryMinute()
    local orig = _G.__lsdOrigLSEveryMinute or _G.LSEveryMinute
    if type(orig) ~= "function" then
        return false
    end
    if _G.__lsdEveryMinuteWrapped then
        return true
    end
    _G.__lsdOrigLSEveryMinute = orig
    _G.__lsdEveryMinuteWrapped = true
    local wrapped = function()
        local p = getPlayer()
        if p == nil or not hasInventoryUi(p:getPlayerNum()) then
            return
        end
        return orig()
    end
    Events.EveryOneMinute.Remove(orig)
    Events.EveryOneMinute.Add(wrapped)
    _G.LSEveryMinute = wrapped
    return true
end

local function uninstallHooks(state)
    if state == nil or state.hooks == nil then
        return
    end
    if state.hooks.tickSweep ~= nil then
        Events.OnTick.Remove(state.hooks.tickSweep)
    end
end

uninstallHooks(LSDeathCompat._state)

-- Lifestyle's globals may not be defined yet in every load order — poll for
-- a few ticks then stop.
local pendingTicks = 300
local function tickSweep()
    if pendingTicks == nil then
        return
    end
    local a = wrapUpdateInvScripts()
    local b = wrapEveryMinute()
    if a and b then
        pendingTicks = nil
        return
    end
    pendingTicks = pendingTicks - 1
    if pendingTicks <= 0 then
        pendingTicks = nil
    end
end

wrapUpdateInvScripts()
wrapEveryMinute()

local hooks = { tickSweep = tickSweep }
LSDeathCompat._state = { hooks = hooks }
Events.OnTick.Add(tickSweep)

return LSDeathCompat
