require "CSR_FeatureFlags"

--[[
    CSR_NestedContainers.lua
    Adds sidebar buttons for containers found inside other containers.

    Uses the vanilla event OnRefreshInventoryWindowContainers("buttonsAdded")
    which fires AFTER refreshBackpacks has created all standard buttons.
    We simply call addContainerButton() and let vanilla handle positioning,
    selection, click handling, and scroll height — zero manual layout.

    Toggle on/off with Numpad 6 (rebindable via Mod Options).
]]

-- Max recursion depth when scanning containers for sidebar buttons.
-- Each level adds one tab on the inventory sidebar. 4 covers realistic
-- worst case (backpack -> small bag -> fanny pack -> wallet) so users can
-- always click through to and TAKE items from the deepest container.
-- Previously 2, which made depth-3+ items visible inside the depth-2 tab
-- but provided no tab to drag/right-click them out from.
local NESTED_MAX_DEPTH = 4
local DEFAULT_KEY = Keyboard and Keyboard.KEY_NUMPAD6 or 77

-- Runtime toggle (persisted in player modData)
local nestedEnabled = true

local options = nil
local nestedKeyBind = nil
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    options = PZAPI.ModOptions:create("CommonSenseRebornNestedContainers", "Common Sense Reborn - Nested Containers")
    if options and options.addKeyBind then
        nestedKeyBind = options:addKeyBind("toggleNestedContainers", "Toggle Nested Containers", DEFAULT_KEY)
    end
end

local function getBoundKey()
    if nestedKeyBind and nestedKeyBind.getValue then
        return nestedKeyBind:getValue()
    end
    return DEFAULT_KEY
end

local function loadToggleState()
    local player = getPlayer and getPlayer() or nil
    if not player then return end
    local modData = player:getModData()
    if modData.CSR_NestedEnabled ~= nil then
        nestedEnabled = modData.CSR_NestedEnabled
    end
end

local function saveToggleState()
    local player = getPlayer and getPlayer() or nil
    if not player then return end
    local modData = player:getModData()
    modData.CSR_NestedEnabled = nestedEnabled
end

local function removeNestedButtons(inventoryPage)
    if not inventoryPage or not inventoryPage.backpacks then return end
    local i = #inventoryPage.backpacks
    while i >= 1 do
        local btn = inventoryPage.backpacks[i]
        if btn and btn._csr_nested then
            inventoryPage:removeChild(btn)
            table.remove(inventoryPage.backpacks, i)
        end
        i = i - 1
    end
end

-- Removes vanilla-created nested container buttons from the loot panel.
-- In B42, vanilla adds buttons for sub-containers inside the container being
-- looted (before our event fires). These are not tagged _csr_nested, so
-- removeNestedButtons() doesn't catch them. We identify them by checking
-- whether the button's inventory belongs to a container item (getContainingItem
-- returns non-nil) -- world-root containers have no containing item.
local function pruneVanillaNestedButtons(inventoryPage)
    if not inventoryPage or not inventoryPage.backpacks then return end
    local i = #inventoryPage.backpacks
    while i >= 1 do
        local btn = inventoryPage.backpacks[i]
        if btn and btn.inventory then
            local containing = btn.inventory.getContainingItem and btn.inventory:getContainingItem()
            if containing then
                inventoryPage:removeChild(btn)
                table.remove(inventoryPage.backpacks, i)
            end
        end
        i = i - 1
    end
end

-- After pruning buttons the scroll height was already fixed at the pre-prune size.
-- Walk the remaining buttons to find the lowest bottom edge and shrink the panel.
local function resizePanelAfterPrune(inventoryPage)
    if not inventoryPage or not inventoryPage.backpacks then return end
    local maxBottom = 0
    for _, btn in ipairs(inventoryPage.backpacks) do
        if btn and btn.y ~= nil and btn.height ~= nil then
            local bottom = btn.y + btn.height
            if bottom > maxBottom then maxBottom = bottom end
        end
    end
    if inventoryPage.setScrollHeight then
        inventoryPage:setScrollHeight(maxBottom + 2)
    end
end

local function toggleNested()
    if CSR_FeatureFlags.isAdminAuthoritative() then return end
    nestedEnabled = not nestedEnabled
    saveToggleState()

    -- Refresh inventory to add/remove nested buttons
    local pInv = getPlayerInventory(0)
    local pLoot = getPlayerLoot(0)
    if pInv then removeNestedButtons(pInv) end
    if pLoot then removeNestedButtons(pLoot) end
    if pInv then pInv:refreshBackpacks() end
    if pLoot then pLoot:refreshBackpacks() end
end

local function onKeyPressed(key)
    if key == getBoundKey() then
        toggleNested()
    end
end

local function onGameStart()
    loadToggleState()
end

local function isContainer(item)
    return item and item:getCategory() == "Container"
end

local function addNestedButtons(inventoryPage, inventory, parentItem, depth)
    if depth > NESTED_MAX_DEPTH then return end
    if not inventory or not inventory.getItems then return end

    local items = inventory:getItems()
    if not items then return end

    local playerObj = getPlayer()

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        repeat
            if not isContainer(item) then break end

            -- Skip items that already have their own vanilla button (player side only)
            if playerObj and inventoryPage.onCharacter then
                if playerObj:isEquipped(item) then break end
                if item:getType() == "KeyRing" then break end
            end

            local nestedInv = item:getInventory()
            if not nestedInv then break end

            -- Skip if a button for this inventory already exists (avoids duplicates
            -- for bags on the floor that vanilla already creates buttons for)
            local alreadyExists = false
            for _, existingBtn in ipairs(inventoryPage.backpacks) do
                if existingBtn.inventory == nestedInv then
                    alreadyExists = true
                    break
                end
            end
            if alreadyExists then break end

            local btn = inventoryPage:addContainerButton(
                nestedInv, item:getTex(), item:getName(), item:getName()
            )

            if not btn then break end
            btn._csr_nested = true

            -- Clothing tint
            if item.getVisual and item:getVisual() and item.getClothingItem and item:getClothingItem() then
                pcall(function()
                    local tint = item:getVisual():getTint(item:getClothingItem())
                    if tint then
                        btn:setTextureRGBA(tint:getRedFloat(), tint:getGreenFloat(), tint:getBlueFloat(), 1.0)
                    end
                end)
            end

            -- Parent icon overlay
            if parentItem then
                local parentTex = parentItem:getTex()
                if parentTex then
                    if not btn._csrOrigRender then
                        btn._csrOrigRender = btn.render
                    end
                    btn.render = function(self)
                        if btn._csrOrigRender then btn._csrOrigRender(self) end
                        local margin = 4
                        local iconSize = self.height / 2.5
                        self:drawTextureScaled(parentTex, self.width - iconSize - margin,
                            self.height - iconSize - margin, iconSize, iconSize, 1)
                    end
                end
            end

            -- Recurse into this nested container for deeper nesting
            addNestedButtons(inventoryPage, nestedInv, item, depth + 1)
        until true
    end
end

local function onRefreshContainers(inventoryPage, stage)
    if stage ~= "buttonsAdded" then return end
    local adminAuth = CSR_FeatureFlags.isAdminAuthoritative()
    local playerDisabled = not adminAuth and not nestedEnabled
    local featureDisabled = not (CSR_FeatureFlags.isNestedContainersEnabled and CSR_FeatureFlags.isNestedContainersEnabled())

    if playerDisabled or featureDisabled then
        -- Feature is off — do nothing. Let vanilla render its own sub-container
        -- buttons exactly as it would without this mod. Pruning them caused blank
        -- squares because the layout wasn't reflowed after removal.
        return
    end

    -- Snapshot existing buttons so we only scan vanilla-created containers
    local existingButtons = {}
    for _, btn in ipairs(inventoryPage.backpacks) do
        table.insert(existingButtons, btn)
    end

    for _, btn in ipairs(existingButtons) do
        local inventory = btn.inventory
        if inventory then
            local parentItem = inventory:getContainingItem()
            addNestedButtons(inventoryPage, inventory, parentItem, 1)
        end
    end
end

if Events then
    if Events.OnRefreshInventoryWindowContainers then
        Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)
    end
    if Events.OnKeyPressed then
        Events.OnKeyPressed.Add(onKeyPressed)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(onGameStart)
    end
end
