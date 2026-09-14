local pad = 10
local nextRequest = 0
local pendingPanels = {}

AVCS.UI.UserPermissionPanel = ISPanel:derive("AVCS.UI.UserPermissionPanel")

function AVCS.UI.UserPermissionPanel:initialise()
    ISPanel.initialise(self)
end

function AVCS.UI.UserPermissionPanel:close()
    if self.requestId then
        pendingPanels[self.requestId] = nil
    end
    ISPanel.close(self)
end

function AVCS.UI.UserPermissionPanel:prerender()
    ISPanel.prerender(self)
    if self.requestId and getTimestampMs() - self.requestTime >= 10000 then
        pendingPanels[self.requestId] = nil
        self.requestId = nil
        self.btnConfirm:setEnable(true)
        self.btnConfirm:setTitle("Retry")
        self.btnConfirm.tooltip = "No server confirmation received. Retry or reopen to check."
        for _, box in ipairs(self.chkBox) do
            box.enable = true
        end
    end
end

function AVCS.UI.UserPermissionPanel:btnCancel_onClick(btn)
    self.close(self)
end

function AVCS.UI.UserPermissionPanel:btnConfirm_onClick(btn)
    if self.requestId or not getPlayer() then
        return
    end
    if AVCS.Sync and not AVCS.Sync.ready() then
        self.btnConfirm.tooltip = "Claim data is synchronizing. Try again shortly."
        return
    end
    -- Send the complete desired state. Comparing to an old cache loses rapid
    -- off/on/off edits while a previous request is still travelling to the server.
    nextRequest = nextRequest + 1
    self.requestId, self.requestTime = nextRequest, getTimestampMs()
    pendingPanels[nextRequest] = self
    local temp = { VehicleID = self.vehicleID, requestId = nextRequest }
    for _, box in ipairs(self.chkBox) do
        temp[box.internal] = box:isSelected(1)
        box.enable = false
    end
    self.btnConfirm:setEnable(false)
    self.btnConfirm:setTitle("Saving")
    sendClientCommand(getPlayer(), "AVCS", "updateSpecifyVehicleUserPermission", temp)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AVCS" or command ~= "permissionResult" or not args then
        return
    end
    local panel = pendingPanels[args.requestId]
    if not panel or panel.vehicleID ~= args.VehicleID then
        return
    end
    pendingPanels[args.requestId] = nil
    panel.requestId = nil
    if args.ok then
        panel:close()
    else
        panel.btnConfirm:setEnable(true)
        panel.btnConfirm:setTitle("Retry")
        panel.btnConfirm.tooltip =
            "Server rejected the change. Check ownership and reopen this panel."
        for _, box in ipairs(panel.chkBox) do
            box.enable = true
        end
    end
end)

function AVCS.UI.UserPermissionPanel:addSets(text, name)
    local lblpadleft = pad + 10
    local i = #self.lblSet + 1

    self.lblSet[i] = ISLabel:new(
        lblpadleft,
        12 + ((getTextManager():getFontHeight(UIFont.NewSmall) + 5) * i),
        getTextManager():getFontHeight(UIFont.NewSmall),
        text,
        1,
        1,
        1,
        1,
        UIFont.NewSmall,
        true
    )
    self.lblSet[i]:initialise()
    self.lblSet[i]:instantiate()
    self:addChild(self.lblSet[i])

    self.chkBox[i] = ISTickBox:new(
        self.width - getTextManager():getFontHeight(UIFont.NewSmall) - 20,
        12 + ((getTextManager():getFontHeight(UIFont.NewSmall) + 5) * i),
        getTextManager():getFontHeight(UIFont.NewSmall),
        getTextManager():getFontHeight(UIFont.NewSmall),
        "",
        nil,
        nil
    )
    self.chkBox[i].internal = name
    self.chkBox[i]:initialise()
    self.chkBox[i]:instantiate()
    self.chkBox[i]:addOption("")
    self:addChild(self.chkBox[i])

    if AVCS.dbByVehicleSQLID[self.vehicleID][name] then
        self.chkBox[i]:setSelected(1, true)
    end
end

function AVCS.UI.UserPermissionPanel:createChildren()
    local btnWidth = 50 * AVCS.getUIFontScale()
    local bthHeight = 30 * AVCS.getUIFontScale()

    self.btnCancel = ISButton:new(
        self.width / 2 - btnWidth - 15,
        self.height - bthHeight - pad,
        btnWidth,
        bthHeight,
        "Cancel",
        self,
        AVCS.UI.UserPermissionPanel.btnCancel_onClick
    )
    self.btnCancel.internal = "btnCancel"
    self.btnCancel.borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 }
    self.btnCancel.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
    self.btnCancel:initialise()
    self.btnCancel:instantiate()
    self.btnCancel:setEnable(true)
    self:addChild(self.btnCancel)

    self.btnConfirm = ISButton:new(
        self.width / 2 + 15,
        self.height - bthHeight - pad,
        btnWidth,
        bthHeight,
        "OK",
        self,
        AVCS.UI.UserPermissionPanel.btnConfirm_onClick
    )
    self.btnConfirm.internal = "btnConfirm"
    self.btnConfirm.borderColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 }
    self.btnConfirm.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
    self.btnConfirm:initialise()
    self.btnConfirm:instantiate()
    self.btnConfirm:setEnable(true)
    self:addChild(self.btnConfirm)

    local lblwidth = getTextManager():MeasureStringX(
        UIFont.NewSmall,
        getText("IGUI_AVCS_User_Permissions_lblPublicPermissions")
    )
    self.lblPublicPermissions = ISLabel:new(
        (self.width / 2) - (lblwidth / 2),
        pad,
        getTextManager():getFontHeight(UIFont.NewSmall),
        getText("IGUI_AVCS_User_Permissions_lblPublicPermissions"),
        1,
        1,
        1,
        1,
        UIFont.NewSmall,
        true
    )
    self.lblPublicPermissions:initialise()
    self.lblPublicPermissions:instantiate()
    self:addChild(self.lblPublicPermissions)

    self:addSets(getText("IGUI_AVCS_User_Permissions_lblAllowDrive"), "AllowDrive")
    self:addSets(getText("IGUI_AVCS_User_Permissions_lblAllowPassenger"), "AllowPassenger")
    self:addSets(getText("IGUI_AVCS_User_Permissions_lblAllowSiphonFuel"), "AllowSiphonFuel")
    self:addSets(
        getText("IGUI_AVCS_User_Permissions_lblAllowUninstallParts"),
        "AllowUninstallParts"
    )
    self:addSets(getText("IGUI_AVCS_User_Permissions_lblAllowAttachVehicle"), "AllowAttachVehicle")
    self:addSets(getText("IGUI_AVCS_User_Permissions_lblAllowDetechVehicle"), "AllowDetechVehicle")
    self:addSets(
        getText("IGUI_AVCS_User_Permissions_lblAllowTakeEngineParts"),
        "AllowTakeEngineParts"
    )
    self:addSets(getText("IGUI_AVCS_User_Permissions_lblAllowOpeningTrunk"), "AllowOpeningTrunk")
    self:addSets(getText("IGUI_AVCS_User_Permissions_lblAllowInflatTires"), "AllowInflatTires")
    self:addSets(getText("IGUI_AVCS_User_Permissions_lblAllowDeflatTires"), "AllowDeflatTires")
end

function AVCS.UI.UserPermissionPanel:new(x, y, width, height, vehicleID)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.x = x
    o.y = y
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    o.width = width
    o.height = height
    o.moveWithMouse = false
    o.vehicleID = vehicleID
    o.lblSet = {}
    o.chkBox = {}
    return o
end
