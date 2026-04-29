require "CSR_FeatureFlags"
require "Items/ProceduralDistributions"

local function injectFireworkDistribution()
    if not CSR_FeatureFlags.isFireworkEnabled() then return end

    local dist = ProceduralDistributions and ProceduralDistributions.list or nil
    if not dist then
        print("[CSR] WARNING: ProceduralDistributions.list not available for firework injection")
        return
    end

    local targets = {
        { table = "GasStoreSpecial",       weight = 6  },
        { table = "CarnivalPrizes",        weight = 4  },
        { table = "StoreCounterTobacco",   weight = 2  },
        { table = "BedroomDresserChild",   weight = 0.5 },
        { table = "GunStoreCounter",       weight = 2  },
        { table = "GigamartSchool",        weight = 1  },
        { table = "ArmyStorageAmmunition", weight = 4  },
        { table = "CrateSurvivalGear",     weight = 3  },
        { table = "SecurityLockers",       weight = 2  },
        { table = "GunStoreDisplayCase",   weight = 3  },
        { table = "ArmySurplusStore",      weight = 4  },
        { table = "GarageTools",           weight = 1  },
        { table = "CampingStoreGear",      weight = 3  },
    }

    local injected = 0
    for _, entry in ipairs(targets) do
        local tbl = dist[entry.table]
        if tbl and tbl.items then
            table.insert(tbl.items, "CommonSenseReborn.Firework")
            table.insert(tbl.items, entry.weight)
            injected = injected + 1
        end
    end
    print("[CSR] Firework distribution injected into " .. injected .. " / " .. #targets .. " loot tables")
end

-- Try all known distribution events in priority order
if Events and Events.OnPreDistributionMerge then
    Events.OnPreDistributionMerge.Add(injectFireworkDistribution)
elseif Events and Events.OnPostDistributionMerge then
    Events.OnPostDistributionMerge.Add(injectFireworkDistribution)
elseif Events and Events.OnInitWorld then
    Events.OnInitWorld.Add(injectFireworkDistribution)
end

-- Also try on game start as a safety net (distributions may already be merged)
if Events and Events.OnGameStart then
    local _fireworkGameStartDone = false
    Events.OnGameStart.Add(function()
        if _fireworkGameStartDone then return end
        _fireworkGameStartDone = true
        injectFireworkDistribution()
    end)
end
