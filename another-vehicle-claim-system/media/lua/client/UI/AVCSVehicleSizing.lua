require("UI/AVCSWindowSizing")
local T = AVCS.WindowSizing

local function adminLayout(panel)
    local buttons = {
        panel.btnViewSafehouse,
        panel.btnViewFaction,
        panel.btnModifyPermissions,
        panel.btnDelete,
        panel.btnTeleport,
        panel.btnUntow,
    }
    if buttons[1] then
        local top = buttons[1].y
        local bh = math.min(buttons[1].height, math.floor((panel.height - top - 24 - 10) / 6))
        for i, button in ipairs(buttons) do
            button:setY(top + (i - 1) * (bh + 2))
            button:setHeight(bh)
        end
    end
    local list = panel.listData
    local fontHeight = getTextManager():getFontHeight(UIFont.NewSmall)
    local footer = fontHeight * 3 + 45
    list:setWidth(panel.width - list.x - 12)
    list:setHeight(math.max(100, panel.height - list.y - footer))
    local ratios = { 0, 0.18, 0.29, 0.60, 0.74, 0.84 }
    for i, column in ipairs(list.columns) do
        column.size = math.floor(list.width * ratios[i])
    end
    panel.lblFilter:setY(list:getBottom() + 4)
    panel.listFilterHeader:setY(panel.lblFilter:getBottom() + fontHeight + 4)
    panel.listFilterHeader:setWidth(math.min(600, list.width))
    panel.listFilterHeader.columns[2].size = math.floor(panel.listFilterHeader.width * 0.4)
    panel.textFilterUsername:setX(panel.listFilterHeader.x)
    panel.textFilterUsername:setY(panel.listFilterHeader.y)
    panel.textFilterUsername:setWidth(math.floor(panel.listFilterHeader.width * 0.4) - 5)
    panel.textFilterVehicleName:setX(
        panel.listFilterHeader.x + math.floor(panel.listFilterHeader.width * 0.4)
    )
    panel.textFilterVehicleName:setY(panel.listFilterHeader.y)
    panel.textFilterVehicleName:setWidth(math.floor(panel.listFilterHeader.width * 0.6))
end

local function userLayout(panel)
    local fontHeight = getTextManager():getFontHeight(UIFont.NewSmall)
    local top = math.max(28, fontHeight + 8)
    local grip = 24
    local bottom = panel.height - grip - 4
    -- Keep an immutable baseline so shrinking and growing restores the same layout.
    panel.avcsClaimListWidth = panel.avcsClaimListWidth or panel.listVehicles.width
    panel.avcsClaimButtonSize = panel.avcsClaimButtonSize or panel.tabBtnSize or 30
    local buttons = {}
    for _, button in ipairs(panel.tabButtons or {}) do
        buttons[#buttons + 1] = button
    end
    for _, name in ipairs({ "btnModify", "btnUnclaim", "btnTeleport" }) do
        if panel[name] then
            buttons[#buttons + 1] = panel[name]
        end
    end
    local buttonSize = math.min(
        panel.avcsClaimButtonSize,
        math.floor((bottom - top - 8 - math.max(0, #buttons - 1) * 5) / math.max(1, #buttons))
    )
    local toolbarWidth = buttonSize + 16
    -- Native tabs stretch vertically, and the preview is bottom-anchored. Turn
    -- those off: this layout owns their geometry, including deferred Java resizes.
    local function place(widget, x, y, width, height)
        widget:setAnchorTop(true)
        widget:setAnchorBottom(false)
        widget:setAnchorLeft(true)
        widget:setAnchorRight(false)
        widget:setX(x)
        widget:setY(y)
        if width then
            widget:setWidth(width)
        end
        if height then
            widget:setHeight(height)
        end
    end
    for i, button in ipairs(buttons) do
        place(button, 8, top + 4 + (i - 1) * (buttonSize + 5), buttonSize, buttonSize)
    end
    place(panel.leftPaneHolder, 0, top, toolbarWidth, bottom - top)
    local left = toolbarWidth + 1
    local listWidth = math.min(panel.avcsClaimListWidth, math.floor(panel.width * 0.30))
    place(panel.listVehicles, left, top, listWidth, bottom - top)
    local rightX = left + listWidth + 8
    local compact = panel.width - rightX - 8 < 480
    local rows = compact and 8 or 4
    local previewTop = top + rows * (fontHeight + 1) + 8
    place(panel.vehiclePreview, rightX, previewTop, panel.width - rightX - 8, bottom - previewTop)
    local secondX = compact and rightX + 3 or rightX + math.floor((panel.width - rightX) * 0.50)
    for i, name in ipairs({
        "lblVehicleOwner",
        "lblVehicleOwnerInfo",
        "lblVehicleExpire",
        "lblVehicleExpireInfo",
    }) do
        place(panel[name], rightX + 3, top + (i - 1) * (fontHeight + 1))
    end
    for i, name in ipairs({
        "lblVehicleLocation",
        "lblVehicleLocationInfo",
        "lblVehicleLastLocationUpdate",
        "lblVehicleLastLocationUpdateInfo",
    }) do
        place(panel[name], secondX, top + ((compact and 4 or 0) + i - 1) * (fontHeight + 1))
    end
    -- AVCS adds interactive children after the native grips. Keep a generous
    -- bottom strip clear and the actual mouse controls above all content.
    if panel.resizeWidget then
        place(panel.resizeWidget, panel.width - grip, panel.height - grip, grip, grip)
        panel.resizeWidget:setVisible(true)
        panel.resizeWidget:bringToTop()
    end
    if panel.resizeWidget2 then
        place(panel.resizeWidget2, 0, panel.height - grip, panel.width - grip, grip)
        panel.resizeWidget2:setVisible(true)
        panel.resizeWidget2:bringToTop()
    end
    if panel.avcsSizeButton then
        panel.avcsSizeButton:bringToTop()
    end
end

local function permissionLayout(panel)
    local fontHeight = getTextManager():getFontHeight(UIFont.NewSmall)
    panel.lblPublicPermissions:setY(32)
    panel.lblPublicPermissions:setX(12)
    for i, label in ipairs(panel.lblSet) do
        local y = 38 + i * (fontHeight + 5)
        label:setY(y)
        panel.chkBox[i]:setY(y)
        panel.chkBox[i]:setX(panel.width - fontHeight - 24)
    end
    panel.btnCancel:setX(15)
    panel.btnConfirm:setX(panel.width - panel.btnConfirm.width - 24)
    panel.btnCancel:setY(panel.height - panel.btnCancel.height - 22)
    panel.btnConfirm:setY(panel.height - panel.btnConfirm.height - 22)
end

local function install()
    if not AVCS or not AVCS.UI or T.vehicleInstalled then
        return
    end
    if
        not AVCS.UI.AdminManagerMain
        or not AVCS.UI.UserManagerMain
        or not AVCS.UI.UserPermissionPanel
    then
        return
    end
    T.vehicleInstalled = true
    local originalScale = AVCS.getUIFontScale
    AVCS.getUIFontScale = function()
        return math.min(
            originalScale(),
            math.max(0.75, (getCore():getScreenWidth() - 24) / 955),
            math.max(0.75, (getCore():getScreenHeight() - 24) / 540)
        )
    end
    local definitions = {
        { AVCS.UI.AdminManagerMain, "VehicleAdmin", 950, 460, adminLayout },
        { AVCS.UI.UserManagerMain, "VehicleClaims", 620, 360, userLayout },
        { AVCS.UI.UserPermissionPanel, "VehiclePermissions", 650, 500, permissionLayout },
    }
    for _, definition in ipairs(definitions) do
        local class, key, minW, minH, layout = unpack(definition)
        local original = class.createChildren
        class.createChildren = function(self)
            T.fit(self, self.width, self.height)
            original(self)
            if key == "VehiclePermissions" then
                minH = 100 + 11 * (getTextManager():getFontHeight(UIFont.NewSmall) + 5)
            elseif key == "VehicleClaims" then
                local fontHeight = getTextManager():getFontHeight(UIFont.NewSmall)
                minH = math.max(360, math.max(28, fontHeight + 8) + 8 * (fontHeight + 1) + 100)
            end
            T.resizable(self, key, minW, minH, layout)
        end
    end
    print("[AVCS] AVCS screen fitting and resize controls installed.")
end

Events.OnGameStart.Add(install)
