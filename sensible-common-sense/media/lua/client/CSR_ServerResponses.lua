CSR_ServerResponses = {}

require "CSR_PlayerMapTracker"
require "CSR_ZombieDensityOverlay"
require "CSR_Utils"

local function resolveLocalPlayer(args)
    local count = getNumActivePlayers and getNumActivePlayers() or 1

    if args and args.playerOnlineID ~= nil then
        for i = 0, count - 1 do
            local p = getSpecificPlayer(i)
            if p and p:getOnlineID() == args.playerOnlineID then
                return p
            end
        end
    end

    if args and args.playerIndex ~= nil then
        local p = getSpecificPlayer(tonumber(args.playerIndex) or 0)
        if p then
            return p
        end
    end

    return getPlayer()
end

local function spriteName(obj)
    local sprite = obj and obj.getSprite and obj:getSprite() or nil
    if sprite and sprite.getName then
        return sprite:getName()
    end
    return nil
end

local function onServerCommand(module, command, args)
    if module ~= "CommonSenseReborn" then
        return
    end

    local player = resolveLocalPlayer(args)
    if command == "ActionResult" then
        if player and args and args.text then
            player:Say(args.text)
            local text = args.text
            if text == "Got it open!" or text == "Unlocked it" or text == "Cut through!" then
                player:playSound("LockSuccess")
                player:setHaloNote(text, 0.5, 1.0, 0.5, 300)
            elseif text:find("failed") or text:find("Ouch") or text:find("broken") or text:find("bent") or text:find("snap") then
                player:setHaloNote(text, 1.0, 0.3, 0.3, 300)
            end
        end
    elseif command == "PlayerMarkers" then
        CSR_PlayerMapTracker.setPlayerData(args and args.players or {}, args and args.requestSeq or nil)
    elseif command == "ZombieDensityCells" then
        CSR_ZombieDensityOverlay.setCells(args and args.cells or {}, args and args.requestSeq or nil)
    elseif command == "DoClientOpenAnim" then
        local sq = args and getCell():getGridSquare(args.x, args.y, args.z) or nil
        if not sq or not player then
            return
        end

        local function tryOpen(obj)
            if not obj then
                return false
            end

            if instanceof(obj, "IsoWindow") then
                if not obj:IsOpen() then
                    obj:setIsLocked(false)
                    ISWorldObjectContextMenu:onOpenCloseWindow(obj, player:getPlayerNum())
                end
                return true
            end

            if instanceof(obj, "IsoDoor") or (instanceof(obj, "IsoThumpable") and obj.isDoor and obj:isDoor()) then
                if not obj:IsOpen() then
                    if obj.setLocked then obj:setLocked(false) end
                    if obj.setLockedByKey then obj:setLockedByKey(false) end
                    if obj.setIsLocked then obj:setIsLocked(false) end
                    if obj.setPermaLocked then obj:setPermaLocked(false) end
                    -- onOpenCloseDoor queues a walk-adj timed action. If the player
                    -- is not adjacent (e.g. door on the far side of a wall), the
                    -- walk-adj check inside vanilla onOpenCloseDoor fails silently
                    -- and the door never toggles. Fall back to ToggleDoor directly
                    -- since we already cleared all lock flags above.
                    ISWorldObjectContextMenu:onOpenCloseDoor(obj, player:getPlayerNum())
                    if not obj:IsOpen() and obj.ToggleDoor then
                        obj:ToggleDoor(player)
                    end
                end
                return true
            end

            return false
        end

        local objects = sq:getObjects()
        if args and args.objectIndex ~= nil and objects and args.objectIndex >= 0 and args.objectIndex < objects:size() then
            if tryOpen(objects:get(args.objectIndex)) then
                return
            end
        end

        if args and args.sprite and args.sprite ~= "" and objects then
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if spriteName(obj) == args.sprite and tryOpen(obj) then
                    return
                end
            end
        end

        if objects then
            for i = 0, objects:size() - 1 do
                if tryOpen(objects:get(i)) then
                    return
                end
            end
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

return CSR_ServerResponses
