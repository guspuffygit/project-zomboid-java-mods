-- Reuse existing table on reload to preserve runtime state
local ProximityInventory = ProximityInventory or {}
ProximityInventory._reloaded = ProximityInventory._initialized or false

-- Options (only register on first load)
if not ProximityInventory._initialized then
  ProximityInventory.options = PZAPI.ModOptions:create("ProximityInventory", "Proximity Inventory")

  ProximityInventory.isEnabled = ProximityInventory.options:addTickBox(
    "ProximityInventory_isEnabled",
    getText("UI_optionscreen_binding_ProximityInventory_isEnabled"),
    true
  )

  ProximityInventory.toggleEnabledOption = ProximityInventory.options:addKeyBind(
    "ProximityInventory_toggleEnabled",
    getText("UI_optionscreen_binding_ProximityInventory_toggleEnabled"),
    Keyboard.KEY_NUMPAD1
  )

  ProximityInventory.toggleForceSelectedOption = ProximityInventory.options:addKeyBind(
    "ProximityInventory_ToggleForceSelected",
    getText("UI_optionscreen_binding_ProximityInventory_ToggleForceSelected"),
    Keyboard.KEY_NUMPAD0
  )

  ProximityInventory.isHighlightEnableOption = ProximityInventory.options:addTickBox(
    "ProximityInventory_isHighlightEnableOption",
    getText("UI_optionscreen_binding_ProximityInventory_isHighlightEnableOption"),
    true
  )
end

-- Consts (safe to re-register, textures are cached)
ProximityInventory.inventoryIcon = getTexture("media/ui/ProximityInventory.png")
ProximityInventory.forceSelectIcon = getTexture("media/ui/Panel_Icon_Pin.png")
ProximityInventory.highlightIcon = getTexture("media/textures/Item_LightBulb.png")

-- Runtime state (preserve across reloads)
---@type { [number]: ItemContainer? }
ProximityInventory.itemContainer = ProximityInventory.itemContainer or {}
---@type { [number]: ISButton? } -- Reference of the button in the UI for each player
ProximityInventory.inventoryButtonRef = ProximityInventory.inventoryButtonRef or {}
---@type { [number]: boolean? } -- Reference of the button in the UI for each player
ProximityInventory.isForceSelected = ProximityInventory.isForceSelected or {}

---@param container ItemContainer
---@param playerObj IsoPlayer
function ProximityInventory.CanBeAdded(container, playerObj)
  local object = container:getParent()

  if SandboxVars.ProximityInventory and SandboxVars.ProximityInventory.ZombieOnly then
    return container:getType() == "inventoryfemale" or container:getType() == "inventorymale"
  end

  -- Don't allow to see inside containers locked to you, for MP
  if object and instanceof(object, "IsoThumpable") then
    if object:isLockedToCharacter(playerObj) then
      return false
    end
  end

  return true
end

---@param playerNum number
function ProximityInventory.GetItemContainer(playerNum)
  if ProximityInventory.itemContainer[playerNum] then
    return ProximityInventory.itemContainer[playerNum]
  end

  ProximityInventory.itemContainer[playerNum] = ItemContainer.new("proxInv", nil, nil)
  ProximityInventory.itemContainer[playerNum]:setExplored(true)
  ProximityInventory.itemContainer[playerNum]:setOnlyAcceptCategory("none") -- Ensures you can't put stuff in it
  ProximityInventory.itemContainer[playerNum]:setCapacity(0)                -- Makes the UI Render the weight as XXX/0 instead of the default XXX/50

  return ProximityInventory.itemContainer[playerNum]
end

---@param invSelf ISInventoryPage
---@return ISButton
function ProximityInventory.AddProximityInventoryButton(invSelf)
  local itemContainer = ProximityInventory.GetItemContainer(invSelf.player)
  itemContainer:clear() -- We want to reset the proxinv between refreshes

  local title = getText("IGUI_ProxInv_InventoryName")

  if getSpecificPlayer(invSelf.player):getVehicle() then
    title = title .. " - " .. getText("GameSound_Category_Vehicle")
  end

  local proxInvButton = invSelf:addContainerButton(
    itemContainer,
    ProximityInventory.inventoryIcon,
    title
  )

  proxInvButton.textureOverride = ProximityInventory.isForceSelected[invSelf.player]
      and ProximityInventory.forceSelectIcon
      or nil

  return proxInvButton
end

---Adds the button at the top of the list of the containers, so that it always appears as first
---@param invSelf ISInventoryPage
function ProximityInventory.OnBeginRefresh(invSelf)
  local proxInvButton = ProximityInventory.AddProximityInventoryButton(invSelf)

  -- We will need this ref for after the button are added
  ProximityInventory.inventoryButtonRef[invSelf.player] = proxInvButton
end

---TODO Maybe Re-work this? We I could hook into ISInventoryPage:addContainerButton and insert the items from there, it could save us some performance
---@param invSelf ISInventoryPage
function ProximityInventory.OnButtonsAdded(invSelf)
  local proximityButtonRef = ProximityInventory.inventoryButtonRef[invSelf.player]
  if not proximityButtonRef then return end -- something must have gone wrong if this returns here

  local playerNum = invSelf.player --[[@as number]]
  local playerObj = getSpecificPlayer(invSelf.player)

  -- Handle force selected
  if ProximityInventory.isForceSelected[playerNum] then
    invSelf:setForceSelectedContainer(ProximityInventory.GetItemContainer(playerNum))
  end

  -- Add All backpacks content except proxInv (TODO: Ensure the 'except proxInv' part)
  for i = 1, #invSelf.backpacks do
    local invToAdd = invSelf.backpacks[i].inventory
    if ProximityInventory.CanBeAdded(invToAdd, playerObj) then
      local items = invToAdd:getItems()
      proximityButtonRef.inventory:getItems():addAll(items)

      invToAdd:setExplored(true)
      invToAdd:setHasBeenLooted(true)
    end
  end
end

function ProximityInventory.OnToggle()
  ProximityInventory.isEnabled:setValue(not ProximityInventory.isEnabled:getValue())
  PZAPI.ModOptions:save()

  ISInventoryPage.dirtyUI() -- Let's force a reset of the UI
end

function ProximityInventory.OnToggleForceSelected()
  local playerNum = 0
  local player = getSpecificPlayer(playerNum)

  ProximityInventory.isForceSelected[playerNum] = not ProximityInventory.isForceSelected[playerNum]

  local text = ProximityInventory.isForceSelected[playerNum]
      and getText("IGUI_ProxInv_Text_ForceSelectOn")
      or getText("IGUI_ProxInv_Text_ForceSelectOff")
      HaloTextHelper.addText(player, text, "", HaloTextHelper.getColorWhite())

  ISInventoryPage.dirtyUI() -- Let's force a reset of the UI
end

function ProximityInventory.OnToggleHighlight()
  ProximityInventory.isHighlightEnableOption:setValue(not ProximityInventory.isHighlightEnableOption:getValue())
  PZAPI.ModOptions:save()

  ISInventoryPage.dirtyUI()
end

function ProximityInventory.populateContextMenuOptions(context)
  local toggleText = ProximityInventory.isEnabled:getValue()
      and getText("IGUI_ProxInv_Context_ToggleOn")
      or getText("IGUI_ProxInv_Context_ToggleOff")
  local optToggle = context:addOption(toggleText, nil, ProximityInventory.OnToggle)
  optToggle.iconTexture = ProximityInventory.isEnabled:getValue() and ProximityInventory.inventoryIcon or nil

  local forceSelectedText = ProximityInventory.isForceSelected[0]
      and getText("IGUI_ProxInv_Context_ForceSelectOn")
      or getText("IGUI_ProxInv_Context_ForceSelectOff")
  local optForce = context:addOption(forceSelectedText, nil, ProximityInventory.OnToggleForceSelected)
  optForce.iconTexture = ProximityInventory.isForceSelected[0] and ProximityInventory.forceSelectIcon or nil

  local highlightText = ProximityInventory.isHighlightEnableOption:getValue()
      and getText("IGUI_ProxInv_Context_HighlightOn")
      or getText("IGUI_ProxInv_Context_HighlightOff")
  local optHighlight = context:addOption(highlightText, nil, ProximityInventory.OnToggleHighlight)
  optHighlight.iconTexture = ProximityInventory.isHighlightEnableOption:getValue() and ProximityInventory.highlightIcon or nil
end

-- Remove previous event listeners before re-adding (reload-safe)
if ProximityInventory._onKeyPressed then
  Events.OnKeyPressed.Remove(ProximityInventory._onKeyPressed)
end
if ProximityInventory._onRefreshInventory then
  Events.OnRefreshInventoryWindowContainers.Remove(ProximityInventory._onRefreshInventory)
end

ProximityInventory._onKeyPressed = function(key)
  if not getPlayer() then return end
  if key == ProximityInventory.toggleForceSelectedOption:getValue() then
    return ProximityInventory.OnToggleForceSelected()
  end
  if key == ProximityInventory.toggleEnabledOption:getValue() then
    return ProximityInventory.OnToggle()
  end
end
Events.OnKeyPressed.Add(ProximityInventory._onKeyPressed)

ProximityInventory._onRefreshInventory = function(invSelf, state)
  if not ProximityInventory.isEnabled:getValue() or invSelf.onCharacter then
    -- Ignore character containers, as usual, but I Wonder if instead it would be nice to have
    -- I did just enable proxinv for vehicles, so I'll need to wait for feedback
    return
  end

  if state == "begin" then
    return ProximityInventory.OnBeginRefresh(invSelf)
  end

  if state == "buttonsAdded" then
    return ProximityInventory.OnButtonsAdded(invSelf)
  end
end
Events.OnRefreshInventoryWindowContainers.Add(ProximityInventory._onRefreshInventory)

ProximityInventory._initialized = true

-- CraftingFix: Avoids duping in SP and MP
-- Store originals on first load only to prevent wrapping an already-wrapped function
-- Used by
-- - media\lua\client\ISUI\ISInventoryPaneContextMenu.lua
-- - media\lua\client\Entity\ISUI\CraftRecipe\ISHandCraftPanel.lua
ProximityInventory._orig_ISInventoryPaneContextMenu_getContainers = ProximityInventory._orig_ISInventoryPaneContextMenu_getContainers or ISInventoryPaneContextMenu.getContainers
ISInventoryPaneContextMenu.getContainers = function(character)
  local containerList = ProximityInventory._orig_ISInventoryPaneContextMenu_getContainers(character)
  if not containerList then return end

  local proxInvContainer = ProximityInventory.GetItemContainer(character:getPlayerNum())

  containerList:remove(proxInvContainer)

  return containerList;
end

-- ISInventoryPage: Context menu for proxInv, pass-through for everything else
ProximityInventory._orig_ISInventoryPage_onBackpackRightMouseDown = ProximityInventory._orig_ISInventoryPage_onBackpackRightMouseDown or ISInventoryPage.onBackpackRightMouseDown
function ISInventoryPage:onBackpackRightMouseDown(x, y)
  if self.inventory and self.inventory:getType() == "proxInv" then
    local page = self.parent.parent
    local context = ISContextMenu.get(page.player, getMouseX(), getMouseY())
    ProximityInventory.populateContextMenuOptions(context)
    return
  end
  return ProximityInventory._orig_ISInventoryPage_onBackpackRightMouseDown(self, x, y)
end

-- ISLootWindowContainerControls: Show "Move To Floor" over the proxInv container.
-- Vanilla arrange() has no branch for our custom container type (getDisplayedObject
-- returns nil because proxInv has no parent), so we let it run and append our button.
ProximityInventory._orig_ISLootWindowContainerControls_arrange = ProximityInventory._orig_ISLootWindowContainerControls_arrange or ISLootWindowContainerControls.arrange
function ISLootWindowContainerControls:arrange()
  ProximityInventory._orig_ISLootWindowContainerControls_arrange(self)

  local container = self.lootWindow.inventoryPane.inventory
  if not container or container:getType() ~= "proxInv" then return end

  local handler = self:checkHandler(ISLootWindowObjectControlHandler_MoveToFloor, nil, container)
  if not handler:shouldBeVisible() then return end

  local control = handler:getControl()
  control:setX(1)
  control:setY(1)
  control:setVisible(true)
  self:addChild(control)
  table.insert(self.controls, control)

  self:setHeight(control:getHeight() + 2)
  self:setX(0)
  self:setY(self.lootWindow.resizeWidget.y - self.height)
  self:setWidth(self.lootWindow:getWidth())
  self:setVisible(true)
  self:fixMouseOverButton()
end

-- proxInv holds items from many real source containers. Queuing every drop at
-- once creates one ISInventoryTransferAction per srcContainer (canMergeAction
-- groups by src+dst). On MP, if any later action's isValid returns false
-- (e.g. isItemTransactionConsistent race while earlier transfers are in
-- flight), ISBaseTimedAction.stop calls ISTimedActionQueue:resetQueue and
-- wipes every remaining batch — so one hiccup silently drops all containers
-- after it. Chain per-source batches across ticks: at most one container is
-- lost on failure, and the user's report of "only the first container gets
-- moved" no longer happens.
ProximityInventory._orig_MoveToFloor_perform = ProximityInventory._orig_MoveToFloor_perform or ISLootWindowObjectControlHandler_MoveToFloor.perform
function ISLootWindowObjectControlHandler_MoveToFloor:perform()
  if not self.container or self.container:getType() ~= "proxInv" then
    return ProximityInventory._orig_MoveToFloor_perform(self)
  end
  if isGamePaused() then return end

  local playerNum = self.playerNum
  local playerObj = getSpecificPlayer(playerNum)
  if not playerObj then return end
  local floor = ISInventoryPage.GetFloorContainer(playerNum)

  local order, groups = {}, {}
  local itemArrayList = self.container:getItems()
  for i = 1, itemArrayList:size() do
    local item = itemArrayList:get(i - 1)
    if item and not item:isFavorite() then
      local src = item:getContainer()
      if src and src ~= floor then
        if not groups[src] then
          groups[src] = {}
          table.insert(order, src)
        end
        table.insert(groups[src], item)
      end
    end
  end
  if #order == 0 then return end

  local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
  local idx = 1
  local waitTicks = 0
  local ticker
  ticker = function()
    if not playerObj:isAlive() then
      Events.OnTick.Remove(ticker)
      return
    end
    if #queue.queue > 0 then
      waitTicks = waitTicks + 1
      if waitTicks > 6000 then Events.OnTick.Remove(ticker) end
      return
    end
    waitTicks = 0
    if idx > #order then
      Events.OnTick.Remove(ticker)
      return
    end
    local batch = groups[order[idx]]
    idx = idx + 1
    local live = {}
    for _, it in ipairs(batch) do
      local src = it:getContainer()
      if src and src ~= floor and src:contains(it) and not it:isFavorite() then
        table.insert(live, it)
      end
    end
    if #live > 0 then
      ISInventoryPaneContextMenu.onDropItems(live, playerNum)
    end
  end
  Events.OnTick.Add(ticker)
end

-- ISInventoryPage: Highlight nearby containers
ProximityInventory._orig_ISInventoryPage_update = ProximityInventory._orig_ISInventoryPage_update or ISInventoryPage.update
function ISInventoryPage:update()
  ProximityInventory._orig_ISInventoryPage_update(self)

  if not ProximityInventory.isEnabled:getValue() or self.onCharacter then return end

  -- I know I kept some good separation between the mod code and the game code,
  -- but just injecting the table is is SOO much simpler, so I'll just inject it here
  self.coloredProxInventories = self.coloredProxInventories or {}

  for i=#self.coloredProxInventories, 1, -1 do
    local parent = self.coloredProxInventories[i]:getParent()
    if parent then
      parent:setHighlighted(self.player, false)
      parent:setOutlineHighlight(self.player, false);
      parent:setOutlineHlAttached(self.player, false);
    end
    self.coloredProxInventories[i]=nil
  end

  if not ProximityInventory.isHighlightEnableOption:getValue() or self.isCollapsed or self.inventory:getType() ~= "proxInv" then return end

  for i=1, #self.backpacks do
    local container = self.backpacks[i].inventory
    local parent = container:getParent()
    if parent and (instanceof(parent, "IsoObject") or instanceof(parent, "IsoDeadBody")) then
      parent:setHighlighted(self.player, true, false)
      parent:setHighlightColor(self.player, getCore():getObjectHighlitedColor())
      self.coloredProxInventories[#self.coloredProxInventories+1] = container
    end
  end
end
