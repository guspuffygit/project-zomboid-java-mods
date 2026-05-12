if isServer() then
    return
end

local MODULE = "SurvivorEconomy"

local HALO_DURATION = 300

SurvivorEconomy = SurvivorEconomy or {}
SurvivorEconomy.balances = SurvivorEconomy.balances or {}

---Returns the cached balance for the given currency, or 0 if unknown. The cache is populated
---by the first {@code balanceUpdated} push from the server (in response to the
---{@code requestBalance} sent on the first tick) and refreshed on every subsequent transaction
---that touches this player.
---@param currency string
---@return number
function SurvivorEconomy.getBalance(currency)
    return SurvivorEconomy.balances[currency] or 0
end

---@param amount number
---@param translationKey string
---@param r number
---@param g number
---@param b number
local function showAmountHalo(amount, translationKey, r, g, b)
    local player = getSpecificPlayer(0)

    if player == nil then
        return
    end

    local rendered = math.floor(amount + 0.5)
    local message = getText(translationKey, tostring(rendered))

    player:setHaloNote(message, r, g, b, HALO_DURATION)
end

---@param module string
---@param command string
---@param args? table
local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end

    if command == "zombieBountyPaid" then
        if args == nil then
            return
        end

        local amount = args.amount

        if amount == nil then
            return
        end

        showAmountHalo(amount, "UI_SurvivorEconomy_ZombieBountyPaid", 80, 220, 80)
    elseif command == "paycheckPaid" then
        if args == nil then
            return
        end

        local amount = args.amount

        if amount == nil then
            return
        end

        showAmountHalo(amount, "UI_SurvivorEconomy_PaycheckPaid", 80, 160, 255)
    elseif command == "balanceUpdated" then
        if args == nil then
            return
        end

        SurvivorEconomy.balances = {}

        if args.balances ~= nil then
            for currency, balance in pairs(args.balances) do
                SurvivorEconomy.balances[currency] = balance
            end
        end
    elseif command == "transferSent" then
        if args == nil then
            return
        end
        local amount = args.amount
        local other = args.otherDisplayName or args.otherUsername or "?"
        if amount == nil then
            return
        end
        local rendered = math.floor(amount + 0.5)
        local message =
            getText("UI_SurvivorEconomy_TransferSent", tostring(rendered), tostring(other))
        local p = getSpecificPlayer(0)
        if p ~= nil then
            p:setHaloNote(message, 80, 160, 255, HALO_DURATION)
        end
    elseif command == "transferReceived" then
        if args == nil then
            return
        end
        local amount = args.amount
        local other = args.otherDisplayName or args.otherUsername or "?"
        if amount == nil then
            return
        end
        local rendered = math.floor(amount + 0.5)
        local message =
            getText("UI_SurvivorEconomy_TransferReceived", tostring(rendered), tostring(other))
        local p = getSpecificPlayer(0)
        if p ~= nil then
            p:setHaloNote(message, 80, 220, 80, HALO_DURATION)
        end
    elseif command == "transferFailed" then
        if args == nil then
            return
        end
        local reason = args.reason or "INVALID_AMOUNT"
        local key = "UI_SurvivorEconomy_TransferFailed_" .. tostring(reason)
        local message = getText(key)
        local p = getSpecificPlayer(0)
        if p ~= nil then
            p:setHaloNote(message, 220, 80, 80, HALO_DURATION)
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

---On the first tick where {@code getSpecificPlayer(0)} is available, ask the server for the
---player's current balances. Self-removes after the request is sent so we only fire once per
---session. The server replies with a {@code balanceUpdated} command that populates
---{@code SurvivorEconomy.balances}.
local function requestInitialBalance()
    local player = getSpecificPlayer(0)

    if player == nil then
        return
    end

    Events.OnTick.Remove(requestInitialBalance)
    sendClientCommand(player, MODULE, "requestBalance", {})
end

Events.OnTick.Add(requestInitialBalance)
