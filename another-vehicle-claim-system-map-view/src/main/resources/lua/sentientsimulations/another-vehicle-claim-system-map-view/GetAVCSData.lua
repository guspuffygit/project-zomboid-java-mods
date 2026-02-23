if AVCS then
    function AVCS.getDetailedVehicleList()
        local response = {}

        if AVCS == nil or AVCS.dbByPlayerID == nil or AVCS.dbByVehicleSQLID == nil then
            return response
        end

        local function getVehicleDisplayName(name)
            local cleanName = string.gsub(name, "^Base%.", "")

            local translationKey = "IGUI_VehicleName" .. cleanName

            local displayName = getText(translationKey)

            if displayName == translationKey then
                return name
            end

            return displayName
        end

        local function addVehiclesForPlayer(playerID, carType)
            local playerVehicles = AVCS.dbByPlayerID[playerID]

            if playerVehicles then
                for vehicleID, _ in pairs(playerVehicles) do
                    if vehicleID ~= "LastKnownLogonTime" then
                        local vehicleData = AVCS.dbByVehicleSQLID[vehicleID]

                        if vehicleData then
                            local vehicleEntry = {
                                vehicleID = vehicleID,
                                ownerPlayerId = vehicleData.OwnerPlayerID,
                                claimDateTime = vehicleData.ClaimDateTime,
                                carModel = vehicleData.CarModel,
                                displayName = getVehicleDisplayName(vehicleData.CarModel),
                                lastLocationX = vehicleData.LastLocationX,
                                lastLocationY = vehicleData.LastLocationY,
                                lastLocationUpdateTime = vehicleData.LastLocationUpdateDateTime,
                                carType = carType,
                            }

                            table.insert(response, vehicleEntry)
                        end
                    end
                end
            end
        end

        local currentPlayer = getPlayer():getUsername()

        addVehiclesForPlayer(currentPlayer, "personal")

        if SafeHouse then
            local safehouseObj = SafeHouse.hasSafehouse(getPlayer())

            if safehouseObj then
                local members = safehouseObj:getPlayers()
                for i = 0, members:size() - 1 do
                    local memberID = members:get(i)

                    if memberID ~= currentPlayer then
                        addVehiclesForPlayer(memberID, "safehouse")
                    end
                end
            end
        end

        if Faction then
            local factionObj = Faction.getPlayerFaction(getPlayer())

            if factionObj then
                local ownerID = factionObj:getOwner()

                if ownerID ~= currentPlayer then
                    addVehiclesForPlayer(ownerID, "faction")
                end

                local members = factionObj:getPlayers()
                for i = 0, members:size() - 1 do
                    local memberID = members:get(i)

                    if memberID ~= currentPlayer and memberID ~= ownerID then
                        addVehiclesForPlayer(memberID, "faction")
                    end
                end
            end
        end

        return response
    end
end