--[[
    CSR_HotbarPersistence.lua
    Robust supplementary hotbar persistence layer.

    Vanilla saves slot *types* (modData["hotbar"]) and relies on Java
    item fields (attachedSlot / attachedSlotType / attachedToModel)
    for item assignments.  Both can silently fail to round-trip in
    edge cases (mod load order, item-ID reassignment, clothing not
    worn at loadPosition time, unexpected game exit).

    This module backs up the full hotbar state (slot layout + item
    identity per slot) alongside vanilla, and restores anything the
    vanilla path lost on reload.

    Compatible with any mod that adds hotbar slots via
    ISHotbarAttachDefinition.
]]

local PERSIST_KEY = "CSR_hotbar_persist"
local SAVE_INTERVAL_TICKS = 600  -- autosave every ~10 seconds

------------------------------------------------------------------------
-- Snapshot helper — captures full hotbar state
------------------------------------------------------------------------
local function buildSnapshot(hotbar)
    if not hotbar or not hotbar.availableSlot then return nil end
    local snap = {}
    -- Use sorted integer keys for deterministic order
    local keys = {}
    for k, _ in pairs(hotbar.availableSlot) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, i in ipairs(keys) do
        local slot = hotbar.availableSlot[i]
        local entry = { s = slot.slotType }
        local item = hotbar.attachedItems and hotbar.attachedItems[i]
        if item then
            entry.t = item:getFullType()
            entry.n = item:getName()
        end
        snap[tostring(i)] = entry
    end
    return snap
end

------------------------------------------------------------------------
-- POST-LOAD: restore item assignments that reloadIcons missed
------------------------------------------------------------------------
local restoreItems  -- forward declaration

------------------------------------------------------------------------
-- Deferred ISHotbar patching — avoids load-order race
------------------------------------------------------------------------
local _patchApplied = false

local function applyPatches()
    if _patchApplied then return end
    if not ISHotbar then return end
    _patchApplied = true

    -- Guard: don't double-patch
    if ISHotbar.__csr_persistence then return end
    ISHotbar.__csr_persistence = true

    -- SAVE: augment vanilla savePosition with item-level backup
    local _origSave = ISHotbar.savePosition

    function ISHotbar:savePosition()
        if _origSave then _origSave(self) end
        if not self.chr then return end
        local snap = buildSnapshot(self)
        if not snap then return end

        -- Check if new snapshot has any items
        local newHasItems = false
        for _, entry in pairs(snap) do
            if entry.t then newHasItems = true; break end
        end

        -- Never overwrite a snapshot that has items with one that has none
        -- (vanilla calls savePosition mid-refresh before items are re-attached)
        if not newHasItems then
            local existing = self.chr:getModData()[PERSIST_KEY]
            if existing then
                for _, entry in pairs(existing) do
                    if entry.t then return end  -- keep the old snapshot
                end
            end
        end

        self.chr:getModData()[PERSIST_KEY] = snap
    end

    -- REFRESH: one-shot restore after clothing slots are discovered
    local _origRefresh = ISHotbar.refresh

    function ISHotbar:refresh()
        if _origRefresh then _origRefresh(self) end
        if self.__csr_pendingRestore then
            self.__csr_pendingRestore = false
            restoreItems(self.playerNum)
        end
    end

    -- LOAD: restore slot layout from backup when vanilla data is missing
    local _origLoad = ISHotbar.loadPosition

    function ISHotbar:loadPosition()
        if _origLoad then _origLoad(self) end
        if not self.chr then return end

        local modData = self.chr:getModData()
        local snap = modData[PERSIST_KEY]
        if not snap then return end

        -- Count what vanilla loaded vs what our backup holds
        local vanillaCount = 0
        if self.availableSlot then
            for _ in pairs(self.availableSlot) do
                vanillaCount = vanillaCount + 1
            end
        end

        local backupCount = 0
        for _ in pairs(snap) do
            backupCount = backupCount + 1
        end

        -- If backup has more slot entries, fill in any missing ones
        if backupCount > vanillaCount then
            for k, entry in pairs(snap) do
                local idx = tonumber(k)
                if idx and entry.s then
                    if not self.availableSlot[idx] then
                        local ok, slotDef = pcall(function()
                            if self.getSlotDef then
                                return self:getSlotDef(entry.s)
                            end
                            return nil
                        end)
                        if ok and slotDef then
                            self.availableSlot[idx] = {
                                slotType = slotDef.type,
                                name     = slotDef.name,
                                def      = slotDef,
                            }
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- POST-LOAD: restore item assignments that reloadIcons missed
-- (assigned to forward-declared local above applyPatches)
------------------------------------------------------------------------
restoreItems = function(playerNum)
    local hotbar = getPlayerHotbar(playerNum)
    if not hotbar or not hotbar.availableSlot then return end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end

    local modData = playerObj:getModData()
    local snap = modData[PERSIST_KEY]
    if not snap then return end

    local inv = playerObj:getInventory()
    if not inv then return end
    local items = inv:getItems()
    if not items then return end
    local size = items:size()

    -- Build a map of slot type → index in current hotbar (handles renumbering)
    local slotTypeToIdx = {}
    for idx, slot in pairs(hotbar.availableSlot) do
        if slot.slotType and not slotTypeToIdx[slot.slotType] then
            slotTypeToIdx[slot.slotType] = idx
        end
    end

    -- Sort snapshot keys for deterministic restoration
    local snapKeys = {}
    for k, _ in pairs(snap) do
        snapKeys[#snapKeys + 1] = k
    end
    table.sort(snapKeys, function(a, b) return tonumber(a) < tonumber(b) end)

    for _, k in ipairs(snapKeys) do
        local entry = snap[k]
        local snapIdx = tonumber(k)
        if snapIdx and entry.t then
            -- Try matching by index first, fall back to slot type
            local idx = snapIdx
            local slot = hotbar.availableSlot[idx]
            if not slot and entry.s then
                idx = slotTypeToIdx[entry.s]
                slot = idx and hotbar.availableSlot[idx] or nil
            end

            if slot and slot.def and not hotbar.attachedItems[idx] then
                -- Find item by fullType match (IDs change between sessions)
                -- Prefer unattached items to avoid stealing from other slots
                local found = nil
                for i = 0, size - 1 do
                    local item = items:get(i)
                    if item and item:getFullType() == entry.t and item:getAttachedSlot() < 0 then
                        found = item
                        break
                    end
                end

                if found and found:getAttachmentType() then
                    local attachments = slot.def.attachments
                    if attachments then
                        local model = attachments[found:getAttachmentType()]
                        if model then
                            hotbar:attachItem(found, model, idx, slot.def, false)
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Periodic autosave — fires every SAVE_INTERVAL_TICKS
------------------------------------------------------------------------
local _tickCounter = 0

local function onPlayerUpdate(player)
    _tickCounter = _tickCounter + 1
    if _tickCounter < SAVE_INTERVAL_TICKS then return end
    _tickCounter = 0

    applyPatches()
    local playerNum = player:getPlayerNum()
    local hotbar = getPlayerHotbar(playerNum)
    if hotbar and hotbar.savePosition then
        hotbar:savePosition()
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

-- Apply patches and restore items on game start
Events.OnGameStart.Add(function()
    applyPatches()
    local n = getNumActivePlayers()
    for i = 0, n - 1 do
        restoreItems(i)
        local hotbar = getPlayerHotbar(i)
        if hotbar then
            hotbar.__csr_pendingRestore = true
        end
    end
end)

-- Also restore on player creation (covers MP reconnects)
Events.OnCreatePlayer.Add(function(playerNum)
    applyPatches()
    restoreItems(playerNum)
    local hotbar = getPlayerHotbar(playerNum)
    if hotbar then
        hotbar.__csr_pendingRestore = true
    end
end)

-- Periodic autosave via player update tick
Events.OnPlayerUpdate.Add(onPlayerUpdate)
