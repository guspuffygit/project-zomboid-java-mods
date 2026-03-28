--
-- Copyright (c) 2024 outdead.
-- Use of this source code is governed by the Apache 2.0 license.
--
-- ItemsClientLogger adds logr for actions with items to the Logs directory
-- the Project Zomboid game.
--

local ItemsClientLogger = {}

-- DumpAdminItem writes admin actions with items.
function ItemsClientLogger.DumpAdminItem(player, action, itemName, count, target)
    if player == nil then
        return nil;
    end

    local message = player:getUsername() .. " " .. action

    message = message .. " " .. count .. " " .. itemName
    message = message .. " in " .. target:getUsername() .. "'s"
    message = message .. " inventory"

    logutils.WriteLog(logutils.filemask.admin, message);
end

-- OnAddItemsFromTable overrides original ISItemsListTable.onOptionMouseDown and
-- ISItemsListTable.onAddItem and adds logs for additem actions.
ItemsClientLogger.OnAddItemsFromTable = function()
    local originalOnOptionMouseDown = ISItemsListTable.onOptionMouseDown;
    local originalOnAddItem = ISItemsListTable.onAddItem;
    local originalCreateChildren = ISItemsListTable.createChildren;

    ISItemsListTable.onOptionMouseDown = function(self, button, x, y)
        originalOnOptionMouseDown(self, button, x, y);

        if button.internal == "ADDITEM" then
            return
        end

        local character = getSpecificPlayer(self.viewer.playerSelect.selected - 1)
        if not character or character:isDead() then return end

        local item = button.parent.datas.items[button.parent.datas.selected].item;
        local count = 0;

        if button.internal == "ADDITEM1" then
            count = 1
        end

        if button.internal == "ADDITEM2" then
            count = 2
        end

        if button.internal == "ADDITEM5" then
            count = 5
        end

        ItemsClientLogger.DumpAdminItem(getPlayer(), "added", item:getFullName(), count, character)
    end

    ISItemsListTable.onAddItem = function(self, button, item)
        originalOnAddItem(self, button, item)

        local character = getSpecificPlayer(self.viewer.playerSelect.selected - 1)
        if not character or character:isDead() then return end

        local count = tonumber(button.parent.entry:getText())

        ItemsClientLogger.DumpAdminItem(getPlayer(), "added", item:getFullName(), count, character)
    end

    local addItem = function(self, item)
        ISItemsListTable.addItem(self, item)

        local character = getSpecificPlayer(self.viewer.playerSelect.selected - 1)
        if not character or character:isDead() then return end

        ItemsClientLogger.DumpAdminItem(getPlayer(), "added", item:getFullName(), 1, character)
    end

    ISItemsListTable.createChildren = function(self)
        originalCreateChildren(self)

        self.datas:setOnMouseDoubleClick(self, addItem)
    end
end

-- OnChangeItemsFromManageInventory overrides original ISPlayerStatsManageInvUI:onClick
-- for adding logs for remove and get items actions.
ItemsClientLogger.OnChangeItemsFromManageInventory = function()
    local originalOnClick = ISPlayerStatsManageInvUI.onClick;

    ISPlayerStatsManageInvUI.onClick = function(self, button)
        originalOnClick(self, button);

        if self.selectedItem then
            if button.internal == "REMOVE" then
                ItemsClientLogger.DumpAdminItem(getPlayer(), "removed", self.selectedItem.item.fullType, 1, self.player);
            end

            if button.internal == "GETITEM" then
                ItemsClientLogger.DumpAdminItem(getPlayer(), "removed", self.selectedItem.item.fullType, 1, self.player);
                ItemsClientLogger.DumpAdminItem(getPlayer(), "added", self.selectedItem.item.fullType, 1, getPlayer());
            end
        end
    end
end

-- OnGameStart adds callback for OnGameStart global event.
ItemsClientLogger.OnGameStart = function()
    if SandboxVars.LogExtender.AdminManageItem then
        ItemsClientLogger.OnAddItemsFromTable()
        ItemsClientLogger.OnChangeItemsFromManageInventory()
    end
end

Events.OnGameStart.Add(ItemsClientLogger.OnGameStart)
