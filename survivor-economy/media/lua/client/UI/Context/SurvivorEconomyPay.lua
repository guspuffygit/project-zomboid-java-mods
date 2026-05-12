if isServer() then
    return
end

local MODULE = "SurvivorEconomy"

local function readMaxDistance()
    if
        SandboxVars
        and SandboxVars.SurvivorEconomy
        and SandboxVars.SurvivorEconomy.PlayerTransferMaxDistance
    then
        return SandboxVars.SurvivorEconomy.PlayerTransferMaxDistance
    end
    return 4
end

local function readAllowTransfers()
    if
        SandboxVars
        and SandboxVars.SurvivorEconomy
        and SandboxVars.SurvivorEconomy.AllowPlayerTransfers ~= nil
    then
        return SandboxVars.SurvivorEconomy.AllowPlayerTransfers
    end
    return true
end

local function findClickedPlayer(localPlayer, worldobjects)
    if worldobjects == nil then
        return nil
    end
    for i = 1, #worldobjects do
        local obj = worldobjects[i]
        if instanceof(obj, "IsoPlayer") and obj ~= localPlayer then
            return obj
        end
        if obj and obj.getSquare then
            local square = obj:getSquare()
            if square then
                local movingObjects = square:getMovingObjects()
                if movingObjects then
                    for j = 0, movingObjects:size() - 1 do
                        local moving = movingObjects:get(j)
                        if instanceof(moving, "IsoPlayer") and moving ~= localPlayer then
                            return moving
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function formatBalance(amount)
    return tostring(math.floor((amount or 0) + 0.5))
end

local function sendTransferRequest(targetPlayer, currency, amount)
    local sender = getSpecificPlayer(0)
    if sender == nil or targetPlayer == nil then
        return
    end
    sendClientCommand(sender, MODULE, "transferToPlayer", {
        targetUsername = targetPlayer:getUsername(),
        targetSteamId = tostring(targetPlayer:getSteamID()),
        currency = currency,
        amount = amount,
    })
end

local function promptForAmount(targetPlayer, currency, balance)
    local displayName = targetPlayer:getDisplayName() or targetPlayer:getUsername()
    local title =
        getText("IGUI_SurvivorEconomy_ContextTransferAmount", displayName, formatBalance(balance))
    local modal = ISTextBox:new(0, 0, 280, 120, title, "", nil, function(target, button)
        if button.internal ~= "OK" then
            return
        end
        local entered = tonumber(button.parent.entry:getText())
        if entered == nil or entered <= 0 then
            return
        end
        if entered > balance then
            entered = balance
        end
        sendTransferRequest(targetPlayer, currency, entered)
    end, nil, getSpecificPlayer(0))
    modal.onlyNumbers = true
    modal:initialise()
    modal:addToUIManager()
end

local function buildSubMenu(contextMenu, targetPlayer, displayName)
    local subMenuLabel = getText("IGUI_SurvivorEconomy_ContextTransfer", displayName)
    local parentOption = contextMenu:addOption(subMenuLabel, nil, nil)
    local subMenu = ISContextMenu:getNew(contextMenu)
    contextMenu:addSubMenu(parentOption, subMenu)

    local balances = SurvivorEconomy and SurvivorEconomy.balances or {}
    local entries = {}
    for currency, balance in pairs(balances) do
        if balance and balance > 0 then
            entries[#entries + 1] = { currency = currency, balance = balance }
        end
    end
    table.sort(entries, function(a, b)
        return tostring(a.currency) < tostring(b.currency)
    end)

    if #entries == 0 then
        local noFunds = subMenu:addOption(getText("IGUI_SurvivorEconomy_ContextNoFunds"), nil, nil)
        noFunds.notAvailable = true
        return parentOption
    end

    for _, entry in ipairs(entries) do
        local label = entry.currency .. " ($" .. formatBalance(entry.balance) .. ")"
        subMenu:addOption(label, nil, function()
            promptForAmount(targetPlayer, entry.currency, entry.balance)
        end)
    end
    return parentOption
end

local function onFillContext(playerNum, contextMenu, worldobjects, test)
    if test then
        return
    end
    local localPlayer = getSpecificPlayer(playerNum)
    if localPlayer == nil then
        return
    end
    if not readAllowTransfers() then
        return
    end

    local target = findClickedPlayer(localPlayer, worldobjects)
    if target == nil then
        return
    end

    local displayName = target:getDisplayName() or target:getUsername() or "?"
    local maxDistance = readMaxDistance()
    local distSq = localPlayer:DistToSquared(target)

    if distSq > (maxDistance * maxDistance) then
        local option = contextMenu:addOption(
            getText("IGUI_SurvivorEconomy_ContextTransfer", displayName),
            nil,
            nil
        )
        option.notAvailable = true
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip.description = getText("IGUI_SurvivorEconomy_ContextOutOfRange")
        option.toolTip = tooltip
        return
    end

    buildSubMenu(contextMenu, target, displayName)
end

Events.OnFillWorldObjectContextMenu.Add(onFillContext)
