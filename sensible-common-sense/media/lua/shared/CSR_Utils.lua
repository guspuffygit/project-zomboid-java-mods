CSR_Utils = {}

local OPEN_CAN_RESULTS = {
    ["Base.CannedBeans"] = "Base.OpenBeans",
    ["Base.TinnedBeans"] = "Base.OpenBeans",
    ["Base.CannedBolognese"] = "Base.CannedBologneseOpen",
    ["Base.CannedBellPepper"] = "Base.CannedBellPepper_Open",
    ["Base.CannedBroccoli"] = "Base.CannedBroccoli_Open",
    ["Base.CannedCabbage"] = "Base.CannedCabbage_Open",
    ["Base.CannedCarrots2"] = "Base.CannedCarrotsOpen",
    ["Base.CannedChili"] = "Base.CannedChiliOpen",
    ["Base.CannedCorn"] = "Base.CannedCornOpen",
    ["Base.CannedCornedBeef"] = "Base.CannedCornedBeefOpen",
    ["Base.CannedEggplant"] = "Base.CannedEggplant_Open",
    ["Base.CannedFruitCocktail"] = "Base.CannedFruitCocktailOpen",
    ["Base.CannedLeek"] = "Base.CannedLeek_Open",
    ["Base.CannedMilk"] = "Base.CannedMilkOpen",
    ["Base.CannedMushroomSoup"] = "Base.CannedMushroomSoupOpen",
    ["Base.CannedPeaches"] = "Base.CannedPeachesOpen",
    ["Base.CannedPeas"] = "Base.CannedPeasOpen",
    ["Base.CannedPineapple"] = "Base.CannedPineappleOpen",
    ["Base.CannedPotato2"] = "Base.CannedPotatoOpen",
    ["Base.CannedRedRadish"] = "Base.CannedRedRadish_Open",
    ["Base.CannedSardines"] = "Base.CannedSardinesOpen",
    ["Base.CannedTomato2"] = "Base.CannedTomatoOpen",
    ["Base.Dogfood"] = "Base.DogfoodOpen",
    ["Base.TinnedSoup"] = "Base.TinnedSoupOpen",
    ["Base.TunaTin"] = "Base.TunaTinOpen"
}
local REINFORCED_DOOR_SPRITES = {
    fixtures_doors_01_32 = true,
    fixtures_doors_01_33 = true,
    -- location_community_police_01_4/5 (police station security doors) were
    -- previously here but are intentionally excluded: these are standard
    -- setIsLocked doors and should be pryable without EnableSafeDoorPry.
    -- The v1.5.4 fix chain specifically targets making them openable after pry.
}

local function sandbox()
    return SandboxVars and SandboxVars.CommonSenseReborn or {}
end

local function inventoryContainsAny(inv, types)
    for _, itemType in ipairs(types) do
        local item = inv:FindAndReturn(itemType)
        if item then
            return item
        end
    end
    return nil
end

local function hasAnyTag(item, tags)
    if not item or not item.hasTag then
        return false
    end

    for _, tag in ipairs(tags) do
        local itemTag = ItemTag and ItemTag.get and ResourceLocation and ResourceLocation.of and ItemTag.get(ResourceLocation.of(tag)) or nil
        if itemTag and item:hasTag(itemTag) then
            return true
        end
    end

    return false
end

local function spriteNameOf(obj)
    local sprite = obj and obj.getSprite and obj:getSprite() or nil
    if sprite and sprite.getName then
        return sprite:getName()
    end
    return nil
end

local function getObjectDistanceSq(player, obj)
    local square = obj and obj.getSquare and obj:getSquare() or nil
    if not player or not square then
        return math.huge
    end

    return IsoUtils.DistanceToSquared(player:getX(), player:getY(), square:getX() + 0.5, square:getY() + 0.5)
end

local function getScriptItem(item)
    if not item then
        return nil
    end

    if item.getScriptItem then
        local scriptItem = item:getScriptItem()
        if scriptItem then
            return scriptItem
        end
    end

    if ScriptManager and ScriptManager.instance and item.getFullType then
        return ScriptManager.instance:FindItem(item:getFullType())
    end

    return nil
end

local function safeCall(obj, fnName, ...)
    if not obj or type(obj[fnName]) ~= "function" then
        return nil
    end
    return obj[fnName](obj, ...)
end

CSR_Utils.safeCall = safeCall

local function scriptHasAnyTag(item, tags)
    if not item or not item.hasTag then
        return false
    end

    for _, tag in ipairs(tags) do
        local itemTag = ItemTag and ItemTag.get and ResourceLocation and ResourceLocation.of and ItemTag.get(ResourceLocation.of(tag)) or nil
        if itemTag and item:hasTag(itemTag) then
            return true
        end
    end

    return false
end

local function looksLikeClosedCan(item)
    if not item or not item.getFullType then
        return false
    end

    local fullType = item:getFullType()
    if fullType:find("Open", 1, true) then
        return false
    end

    local lower = string.lower(fullType)
    return lower:find("canned", 1, true) ~= nil
        or lower:find("tinned", 1, true) ~= nil
        or lower:find("tin", 1, true) ~= nil
        or lower:find("dogfood", 1, true) ~= nil
end

local function resolveReplaceOnUseFullType(item)
    if not item then
        return nil
    end

    if item.getReplaceOnUseFullType then
        local fullType = item:getReplaceOnUseFullType()
        if fullType and fullType ~= "" and fullType ~= item:getFullType() then
            return fullType
        end
    end

    local scriptItem = getScriptItem(item)
    if not scriptItem then
        return nil
    end

    local replaceOnUse = scriptItem.getReplaceOnUse and scriptItem:getReplaceOnUse() or nil
    if not replaceOnUse or replaceOnUse == "" then
        return nil
    end

    if replaceOnUse:find("%.") then
        return replaceOnUse
    end

    local module = item.getModule and item:getModule() or "Base"
    return module .. "." .. replaceOnUse
end
local function resolveOpenedFoodVariant(item)
    if not item or not item.getFullType or not item.getType then
        return nil
    end

    local scriptItem = getScriptItem(item)
    if not scriptItem or scriptItem.CannedFood ~= true then
        return nil
    end

    local fullType = item:getFullType()
    if fullType:find("Open", 1, true) or fullType:find("_Open", 1, true) then
        return nil
    end

    if scriptItem.getReplaceOnUse and scriptItem:getReplaceOnUse() then
        return nil
    end

    local module = item.getModule and item:getModule() or "Base"
    local itemType = item:getType()
    local candidates = {
        module .. "." .. itemType .. "Open",
        module .. "." .. itemType .. "_Open"
    }

    if not ScriptManager or not ScriptManager.instance then
        return nil
    end

    for _, candidate in ipairs(candidates) do
        if candidate ~= fullType and ScriptManager.instance:FindItem(candidate) then
            return candidate
        end
    end

    return nil
end

local function replaceTypeMatchesEmptyJar(fullType)
    return fullType == "Base.EmptyJar" or fullType == "EmptyJar"
end

local function getOpenedJarReplacementType(openedFullType)
    if not openedFullType or not ScriptManager or not ScriptManager.instance then
        return nil
    end

    local openedScript = ScriptManager.instance:FindItem(openedFullType)
    if not openedScript then
        return nil
    end

    local replaceOnUse = openedScript.getReplaceOnUse and openedScript:getReplaceOnUse() or nil
    if replaceOnUse and replaceOnUse ~= "" then
        if replaceOnUse:find("%.") then
            if replaceTypeMatchesEmptyJar(replaceOnUse) then
                return replaceOnUse
            end
        else
            local module = openedScript.getModuleName and openedScript:getModuleName() or "Base"
            local fullType = module .. "." .. replaceOnUse
            if replaceTypeMatchesEmptyJar(fullType) or replaceTypeMatchesEmptyJar(replaceOnUse) then
                return fullType
            end
        end
    end

    return nil
end

local function itemUsesBattery(item)
    if not item then
        return false
    end

    if hasAnyTag(item, { "usesbattery", "UsesBattery" }) or scriptHasAnyTag(item, { "usesbattery", "UsesBattery" }) then
        return true
    end

    local scriptItem = getScriptItem(item)
    if scriptItem and scriptItem.getUsesBattery and scriptItem:getUsesBattery() then
        return true
    end

    return false
end

function CSR_Utils.calculatePrySuccess(player, tool)
    local strength = player:getPerkLevel(Perks.Strength)
    local fitness = player:getPerkLevel(Perks.Fitness)
    local toolCondition = tool:getCondition() / math.max(1, tool:getConditionMax())
    local multiplier = (SandboxVars and SandboxVars.CommonSenseReborn and SandboxVars.CommonSenseReborn.PrySuccessMultiplier) or 1.0
    local baseChance = 0.25 + (strength * 0.04) + (fitness * 0.02) + (toolCondition * 0.2)
    return math.min(0.95, math.max(0.05, baseChance * multiplier))
end

function CSR_Utils.calculateLockpickSuccess(player, tool, target)
    local nimble = player:getPerkLevel(Perks.Nimble)
    local mechanics = player.getPerkLevel and player:getPerkLevel(Perks.Mechanics) or 0
    local fitness = player:getPerkLevel(Perks.Fitness)
    local toolCondition = tool:getCondition() / math.max(1, tool:getConditionMax())
    local professionBonus = 0
    local descriptor = player.getDescriptor and player:getDescriptor() or nil
    local profession = descriptor and descriptor.getProfession and descriptor:getProfession() or nil
    if profession == "burglar" then
        professionBonus = 0.08
    end

    local targetPenalty = 0
    if target and target.getDoor and target:getDoor() then
        targetPenalty = 0.04
    end
    if target and target.getId then
        local partId = string.lower(target:getId() or "")
        if partId:find("trunk", 1, true) or partId:find("rear", 1, true) then
            targetPenalty = targetPenalty + 0.02
        end
    end

    local csrSandbox = SandboxVars and SandboxVars.CommonSenseReborn or nil
    local multiplier = (csrSandbox and csrSandbox.LockpickSuccessMultiplier) or 1.0
    local baseChance = 0.16
        + (nimble * 0.045)
        + (mechanics * 0.015)
        + (fitness * 0.01)
        + (toolCondition * 0.18)
        + professionBonus
        - targetPenalty

    if CSR_Utils.isPaperclip(tool) then
        baseChance = baseChance * 0.45
    end

    return math.min(0.9, math.max(0.04, baseChance * multiplier))
end

function CSR_Utils.hasCrowbar(player)
    local inv = player:getInventory()
    local item = inv:FindAndReturn("Crowbar")
    if item then
        return item
    end
    if ItemTag and ItemTag.CROWBAR and inv.getFirstTagRecurse then
        return inv:getFirstTagRecurse(ItemTag.CROWBAR)
    end
    if ItemTag and ItemTag.PRY_BAR and inv.getFirstTagRecurse then
        return inv:getFirstTagRecurse(ItemTag.PRY_BAR)
    end
    return nil
end

function CSR_Utils.hasBoltCutters(player)
    local inv = player:getInventory()
    local item = inv:FindAndReturn("BoltCutters")
    if item then
        return item
    end
    if inv.getFirstTagRecurse then
        local tag = ItemTag and ItemTag.get and ResourceLocation and ResourceLocation.of
            and ItemTag.get(ResourceLocation.of("base:boltcutters")) or nil
        if tag then
            return inv:getFirstTagRecurse(tag)
        end
    end
    return nil
end

function CSR_Utils.findSaw(player)
    local inv = player:getInventory()
    local item = inv:FindAndReturn("Saw")
    if item then
        return item
    end
    if inv.getFirstTagRecurse then
        local tag = ItemTag and ItemTag.get and ResourceLocation and ResourceLocation.of
            and ItemTag.get(ResourceLocation.of("base:saw")) or nil
        if tag then
            return inv:getFirstTagRecurse(tag)
        end
    end
    return nil
end

function CSR_Utils.hasKnife(player)
    return inventoryContainsAny(player:getInventory(), { "KitchenKnife", "HuntingKnife", "BreadKnife", "Knife" })
end

function CSR_Utils.hasScissors(player)
    return inventoryContainsAny(player:getInventory(), { "Scissors", "ScissorsForged" })
end

local SCREWDRIVER_TYPES = { "Screwdriver", "Screwdriver_Old", "Screwdriver_Improvised" }

function CSR_Utils.isScrewdriver(item)
    if not item or not item.getType then return false end
    local t = item:getType()
    for i = 1, #SCREWDRIVER_TYPES do
        if t == SCREWDRIVER_TYPES[i] then return true end
    end
    return false
end

function CSR_Utils.hasScrewdriver(player)
    return CSR_Utils.findPreferredInventoryItemByTypes(player, SCREWDRIVER_TYPES)
end

function CSR_Utils.findPaperclip(player)
    return CSR_Utils.findPreferredInventoryItemByTypes(player, { "Paperclip" })
end

function CSR_Utils.isPaperclip(item)
    return item and item.getType and item:getType() == "Paperclip"
end

function CSR_Utils.hasPliers(player)
    return player and player:getInventory() and player:getInventory():FindAndReturn("Pliers") or nil
end

function CSR_Utils.hasBattery(player)
    return player and player:getInventory() and player:getInventory():FindAndReturn("Battery") or nil
end

function CSR_Utils.findPreferredIgnitionSource(player)
    return CSR_Utils.findPreferredInventoryItem(player, function(item)
        if not item or not item.getType then
            return false
        end

        local itemType = item:getType()
        if itemType == "Matches" or itemType == "Lighter" or itemType == "LighterDisposable" or itemType == "LighterBBQ" or itemType == "Lighter_Battery" then
            return true
        end

        return hasAnyTag(item, { "startfire", "START_FIRE" }) or scriptHasAnyTag(item, { "startfire", "START_FIRE" })
    end)
end

function CSR_Utils.hasIgnitionSource(player)
    return CSR_Utils.findPreferredIgnitionSource(player)
end

function CSR_Utils.findPreferredThread(player)
    return CSR_Utils.findPreferredInventoryItem(player, function(item)
        if not item then
            return false
        end

        if item.getType and (item:getType() == "Thread" or item:getType() == "Thread_Aramid" or item:getType() == "Thread_Sinew") then
            return true
        end

        return hasAnyTag(item, { "thread", "Thread" }) or scriptHasAnyTag(item, { "thread", "Thread" })
    end)
end

function CSR_Utils.findPreferredNeedle(player)
    return CSR_Utils.findPreferredInventoryItem(player, function(item)
        if not item then
            return false
        end

        if item.getType then
            local itemType = item:getType()
            if itemType == "Needle" or itemType == "Needle_Bone" or itemType == "Needle_Brass" or itemType == "Needle_Forged" then
                return true
            end
        end

        return hasAnyTag(item, { "SewingNeedle", "sewingneedle" }) or scriptHasAnyTag(item, { "SewingNeedle", "sewingneedle" })
    end)
end

function CSR_Utils.findPreferredPlank(player)
    return CSR_Utils.findPreferredInventoryItemByTypes(player, { "Plank" })
end

function CSR_Utils.hasPlank(player)
    return CSR_Utils.findPreferredPlank(player)
end

function CSR_Utils.hasLighterFluid(player)
    return CSR_Utils.findPreferredLighterFluid(player)
end

function CSR_Utils.canPourCanContents(item)
    if not item or not item.getCategory or item:getCategory() ~= "Food" then
        return false
    end

    local replaceOnUse = item.getReplaceOnUse and item:getReplaceOnUse() or nil
    if replaceOnUse == "TinCanEmpty" or replaceOnUse == "Base.TinCanEmpty" then
        return true
    end

    return resolveReplaceOnUseFullType(item) == "Base.TinCanEmpty"
end

function CSR_Utils.isKnifeItem(item)
    if not item or not item.getType then
        return false
    end

    local itemType = item:getType()
    return itemType == "KitchenKnife" or itemType == "HuntingKnife" or itemType == "BreadKnife" or itemType == "Knife"
end

function CSR_Utils.isScissorsItem(item)
    if not item or not item.getType then
        return false
    end

    local itemType = item:getType()
    return itemType == "Scissors" or itemType == "ScissorsForged"
end

function CSR_Utils.isClothCuttingTool(item)
    return CSR_Utils.isKnifeItem(item) or CSR_Utils.isScissorsItem(item)
end

function CSR_Utils.isCanOpeningTool(item)
    if not item or not item.getType then
        return false
    end

    return CSR_Utils.isKnifeItem(item) or CSR_Utils.isScrewdriver(item)
end

function CSR_Utils.isSupportedCan(item)
    if not item or not item.getFullType then
        return false
    end

    if OPEN_CAN_RESULTS[item:getFullType()] ~= nil then
        return true
    end

    if not looksLikeClosedCan(item) then
        return false
    end

    local replaceOnUseType = resolveReplaceOnUseFullType(item)
    if replaceOnUseType then
        return true
    end

    local openedVariant = resolveOpenedFoodVariant(item)
    return openedVariant ~= nil and getOpenedJarReplacementType(openedVariant) == nil
end

function CSR_Utils.getOpenJarResult(item)
    if not item or not item.getFullType then
        return nil
    end

    local openedType = resolveOpenedFoodVariant(item)
    if not openedType then
        return nil
    end

    if getOpenedJarReplacementType(openedType) then
        return openedType
    end

    return nil
end

function CSR_Utils.isSupportedJarFood(item)
    return CSR_Utils.getOpenJarResult(item) ~= nil
end

function CSR_Utils.getOpenedJarEmptyContainer(item)
    local openedType = CSR_Utils.getOpenJarResult(item)
    if not openedType then
        return nil
    end

    local replacement = getOpenedJarReplacementType(openedType)
    if not replacement then
        return nil
    end

    if replacement == "EmptyJar" then
        return "Base.EmptyJar"
    end

    return replacement
end

function CSR_Utils.getJarLidType()
    if ScriptManager and ScriptManager.instance and ScriptManager.instance:FindItem("Base.JarLid") then
        return "Base.JarLid"
    end
    return nil
end

function CSR_Utils.isCannedFood(item)
    return CSR_Utils.isSupportedCan(item)
end

function CSR_Utils.isRepairableItem(item)
    return item and item.getConditionMax and item:getConditionMax() > 0 and item:getCondition() < item:getConditionMax()
end

local explicitTearFabric = {
    ["Bra_Straps_FrillyRed"] = "Cotton",
    ["Bra_Straps_Black"] = "Cotton",
    ["Bra_Straps_FrillyPink"] = "Cotton",
    ["Bra_Straps_AnimalPrint"] = "Cotton",
    ["Bra_Straps_FrillyBlack"] = "Cotton",
    ["Bra_Straps_White"] = "Cotton",
    ["Bra_Strapless_AnimalPrint"] = "Cotton",
    ["Bra_Strapless_White"] = "Cotton",
    ["Bra_Strapless_Black"] = "Cotton",
    ["Bra_Strapless_FrillyBlack"] = "Cotton",
    ["Bra_Strapless_FrillyPink"] = "Cotton",
    ["Bra_Strapless_FrillyRed"] = "Cotton",
    ["Bra_Strapless_RedSpots"] = "Cotton",
    ["Underpants_Black"] = "Cotton",
    ["Underpants_RedSpots"] = "Cotton",
    ["Underpants_White"] = "Cotton",
    ["Underpants_AnimalPrint"] = "Cotton",
    ["FrillyUnderpants_Black"] = "Cotton",
    ["FrillyUnderpants_Red"] = "Cotton",
    ["FrillyUnderpants_Pink"] = "Cotton",
    ["Boxers_RedStripes"] = "Cotton",
    ["Boxers_Silk_Red"] = "Cotton",
    ["Boxers_Silk_Black"] = "Cotton",
    ["Boxers_Hearts"] = "Cotton",
    ["Boxers_White"] = "Cotton",
    ["Briefs_White"] = "Cotton",
    ["Briefs_AnimalPrints"] = "Cotton",
    ["Briefs_Garbage"] = "Cotton",
    ["Briefs_Rag"] = "Cotton",
    ["Briefs_Tarp"] = "Denim",
    ["Briefs_SmallTrunks_Black"] = "Cotton",
    ["Briefs_SmallTrunks_Red"] = "Cotton",
    ["Briefs_SmallTrunks_WhiteTINT"] = "Cotton",
    ["Briefs_SmallTrunks_Blue"] = "Cotton",
    ["Briefs_Denim"] = "Denim",
    ["Socks_LegWarmers"] = "Cotton",
    ["Socks_Ankle_Black"] = "Cotton",
    ["Socks_Ankle_White"] = "Cotton",
    ["Socks_Ankle"] = "Cotton",
    ["Socks_Heavy"] = "Cotton",
    ["Socks_Long_Black"] = "Cotton",
    ["Socks_Long_White"] = "Cotton",
    ["Socks_Long"] = "Cotton",
    ["StockingsBlack"] = "Cotton",
    ["StockingsBlackSemiTrans"] = "Cotton",
    ["StockingsBlackTrans"] = "Cotton",
    ["StockingsWhite"] = "Cotton",
    ["TightsBlack"] = "Cotton",
    ["TightsFishnets"] = "Cotton",
    ["TightsBlackSemiTrans"] = "Cotton",
    ["TightsBlackTrans"] = "Cotton",
    ["Gloves_WhiteTINT"] = "Cotton",
    ["Gloves_FingerlessGloves"] = "Cotton",
    ["Gloves_HuntingCamo"] = "Cotton",
    ["Gloves_LongWomenGloves"] = "Cotton",
    ["Gloves_RagWrap"] = "Cotton",
    ["Gloves_DenimWrap"] = "Denim",
    ["Gloves_FingerlessLeatherGloves_Black"] = "Leather",
    ["Gloves_FingerlessLeatherGloves"] = "Leather",
    ["Gloves_FingerlessLeatherGloves_Brown"] = "Leather",
    ["Gloves_LeatherGlovesBlack"] = "Leather",
    ["Gloves_LeatherGloves"] = "Leather",
    ["Gloves_LeatherGlovesBrown"] = "Leather",
    ["Gloves_LeatherWrap"] = "Leather",
}

local function getClothFabricType(item)
    if not item then
        return nil
    end

    if item.getFabricType then
        local fabricType = item:getFabricType()
        if fabricType and fabricType ~= "" then
            return fabricType
        end
    end

    local itemType = item.getType and item:getType() or ""
    if explicitTearFabric[itemType] then
        return explicitTearFabric[itemType]
    end

    local fullType = item.getFullType and string.lower(item:getFullType() or "") or ""
    if fullType:find("leather", 1, true) or fullType:find("hide", 1, true) then
        return "Leather"
    end
    if fullType:find("denim", 1, true) or fullType:find("tarp", 1, true) then
        return "Denim"
    end
    if fullType:find("bra_", 1, true) or fullType:find("underpants", 1, true) or fullType:find("boxers", 1, true) or fullType:find("briefs", 1, true) or fullType:find("socks_", 1, true) or fullType:find("stockings", 1, true) or fullType:find("tights", 1, true) or fullType:find("gloves_", 1, true) then
        return "Cotton"
    end

    return nil
end

local function getCoveredPartCountSafe(item)
    if not item or not item.getCoveredParts then
        return 0
    end

    local coveredParts = item:getCoveredParts()
    if not coveredParts or not coveredParts.size then
        return 0
    end

    return coveredParts:size()
end

function CSR_Utils.getTearClothInfo(item)
    if not item or not item.getType then
        return nil
    end

    local itemType = item:getType()
    if itemType == "Sheet" or itemType == "SheetDirty" then
        return {
            outputType = "Base.RippedSheets",
            quantity = 3,
            requiresTool = false,
            fabricType = "Cotton",
        }
    end
    if itemType == "RippedSheetsDirty" then
        return {
            outputType = "Base.RippedSheetsDirty",
            quantity = 1,
            requiresTool = false,
            fabricType = "Cotton",
        }
    end

    if not item.IsClothing or not item:IsClothing() then
        return nil
    end

    local fabricType = getClothFabricType(item)
    if not fabricType then
        return nil
    end

    local outputType = "Base.RippedSheets"
    local requiresTool = false
    if fabricType == "Denim" then
        outputType = "Base.DenimStrips"
        requiresTool = true
    elseif fabricType == "Leather" then
        outputType = "Base.LeatherStrips"
        requiresTool = true
    end

    local coveredCount = getCoveredPartCountSafe(item)
    local quantity = 1
    if coveredCount >= 2 then
        quantity = 2
    end
    if coveredCount >= 4 then
        quantity = 3
    end

    if itemType:find("Stockings", 1, true) or itemType:find("Tights", 1, true) then
        quantity = math.max(quantity, 2)
    end

    return {
        outputType = outputType,
        quantity = quantity,
        requiresTool = requiresTool,
        fabricType = fabricType,
    }
end

function CSR_Utils.canTearCloth(item, player)
    local info = CSR_Utils.getTearClothInfo(item)
    if not info then
        return false
    end

    if item and item.isFavorite and item:isFavorite() then
        return false
    end

    if player and player.isEquippedClothing and player:isEquippedClothing(item) then
        return false
    end

    if info.requiresTool and player then
        return CSR_Utils.hasScissors(player) or CSR_Utils.hasKnife(player)
    end

    return true
end

function CSR_Utils.findClothCuttingTool(player)
    return CSR_Utils.hasScissors(player) or CSR_Utils.hasKnife(player)
end

function CSR_Utils.isCloth(item)
    return CSR_Utils.getTearClothInfo(item) ~= nil
end

function CSR_Utils.canTailorClothing(item)
    if not item or not item.IsClothing or not item:IsClothing() then
        return false
    end

    if not item.getCoveredParts or not item.getFabricType then
        return false
    end

    local coveredParts = item:getCoveredParts()
    if not coveredParts or coveredParts:size() <= 0 then
        return false
    end

    local fabricType = item:getFabricType()
    return fabricType ~= nil and fabricType ~= ""
end

function CSR_Utils.isBandageMaterial(item)
    if not item or not item.getFullType then
        return false
    end

    local fullType = item:getFullType()
    return fullType == "Base.RippedSheets"
        or fullType == "Base.RippedSheetsDirty"
        or fullType == "Base.DenimStrips"
        or fullType == "Base.DenimStripsDirty"
        or fullType == "Base.LeatherStrips"
        or fullType == "Base.LeatherStripsDirty"
end

function CSR_Utils.canMakeBandage(item, player)
    if not CSR_Utils.isBandageMaterial(item) then
        return false
    end

    if not player then
        return true
    end

    return CSR_Utils.findPreferredThread(player) ~= nil and CSR_Utils.findPreferredNeedle(player) ~= nil
end

function CSR_Utils.isStapler(item)
    if not item or not item.getFullType then return false end
    return item:getFullType() == "Base.Stapler"
end

function CSR_Utils.findStapler(player)
    if not player then return nil end
    local inv = player:getInventory()
    return inv and inv:FindAndReturn("Stapler") or nil
end

function CSR_Utils.findStaples(player)
    if not player then return nil end
    local inv = player:getInventory()
    if not inv then return nil end
    local staples = inv:FindAndReturn("Staples")
    if staples then
        local remaining = (staples.getCurrentUsesFloat and staples:getCurrentUsesFloat()) or (staples.getDelta and staples:getDelta()) or 0
        if remaining > 0 then
            return staples
        end
    end
    return nil
end

function CSR_Utils.canStapleWound(bodyPart)
    if not bodyPart then return false end
    if bodyPart:bandaged() or bodyPart:stitched() then return false end
    if bodyPart:haveGlass() or bodyPart:haveBullet() then return false end
    return bodyPart:scratched() or bodyPart:isCut() or bodyPart:isDeepWounded()
end

function CSR_Utils.isFlashlight(item)
    if not item or not item.IsDrainable or not item:IsDrainable() then
        return false
    end

    if hasAnyTag(item, { "flashlight", "Flashlight", "flashlightpillar", "FlashlightPillar" }) then
        return true
    end

    if scriptHasAnyTag(item, { "flashlight", "Flashlight", "flashlightpillar", "FlashlightPillar" }) then
        return true
    end

    if item.getLightDistance and item:getLightDistance() and item:getLightDistance() > 0 then
        return true
    end

    return false
end

function CSR_Utils.isBatteryPoweredFlashlight(item)
    if not CSR_Utils.isFlashlight(item) then
        return false
    end

    if itemUsesBattery(item) then
        return true
    end

    if not item or not item.getFullType then
        return false
    end

    local fullType = item:getFullType()
    return fullType == "Base.Torch"
        or fullType == "Base.HandTorch"
        or fullType == "Base.FlashLight_AngleHead"
        or fullType == "Base.FlashLight_AngleHead_Army"
        or fullType == "Base.PenLight"
        or fullType == "Base.Flashlight_Crafted"
end

function CSR_Utils.isRefillableLighter(item)
    if not item or not item.IsDrainable or not item:IsDrainable() then
        return false
    end

    return hasAnyTag(item, { "refillablelighter", "RefillableLighter", "lighter", "Lighter" })
end

function CSR_Utils.canRechargeFlashlight(item)
    return CSR_Utils.isBatteryPoweredFlashlight(item) and item.getDelta and item:getDelta() < 1.0
end

function CSR_Utils.isFlashlightActive(item)
    if not CSR_Utils.isFlashlight(item) then
        return false
    end

    if safeCall(item, "canBeActivated") ~= true then
        return false
    end

    return safeCall(item, "isActivated") == true
end

function CSR_Utils.canRefillLighter(item)
    return CSR_Utils.isRefillableLighter(item) and item.getDelta and item:getDelta() < 1.0
end

function CSR_Utils.findRepairTool(player, excludeItem)
    local inv = player:getInventory()
    local tools = {
        "Hammer", "Screwdriver", "Screwdriver_Old", "Screwdriver_Improvised",
        "Pliers", "Wrench", "Saw", "Crowbar", "PipeWrench", "Axe"
    }
    for _, t in ipairs(tools) do
        local found = inv:FindAndReturn(t)
        if found and found ~= excludeItem and found.getCondition and found:getCondition() > 0 then
            return found
        end
    end
    return nil
end

function CSR_Utils.isBarricadedForPlayer(target, character)
    if not target or not character or not target.getBarricadeForCharacter then
        return false
    end

    return target:getBarricadeForCharacter(character) ~= nil
end

function CSR_Utils.isReinforcedDoor(target)
    local spriteName = spriteNameOf(target)
    return spriteName and REINFORCED_DOOR_SPRITES[spriteName] == true or false
end

function CSR_Utils.isGarageDoor(target)
    if not target then
        return false
    end

    -- Check via native IsoDoor garage door traversal (map-placed doors)
    if instanceof(target, "IsoDoor") and IsoDoor then
        if IsoDoor.getGarageDoorFirst then
            local first = IsoDoor.getGarageDoorFirst(target)
            if first then return true end
        end
    end

    -- Check via square's getGarageDoor (catches most garage door types)
    local sq = target.getSquare and target:getSquare() or nil
    if sq and sq.getGarageDoor then
        if sq:getGarageDoor(true) or sq:getGarageDoor(false) then
            return true
        end
    end

    -- Check sprite name for "garage" or "industry_truck"
    local sprite = target.getSprite and target:getSprite() or nil
    if sprite and sprite.getName then
        local name = sprite:getName() or ""
        if string.find(name, "garage", 1, true) or string.find(name, "industry_truck", 1, true) then
            return true
        end
    end

    -- Fallback: buildUtil for player-built garage doors
    if buildUtil and buildUtil.getGarageDoorObjects then
        local objects = buildUtil.getGarageDoorObjects(target)
        if objects and #objects > 0 then return true end
    end

    return false
end

function CSR_Utils.canPryWorldTarget(target, player)
    if not CSR_Utils.isPryTarget(target) then
        return false, "Not a pry target"
    end

    if CSR_Utils.isBarricadedForPlayer(target, player) then
        return false, "Target is barricaded"
    end

    if instanceof(target, "IsoWindow") then
        return true
    end

    if CSR_Utils.isGarageDoor(target) and sandbox().EnableGarageDoorPry == false then
        return false, "Garage door prying disabled"
    end

    if CSR_Utils.isReinforcedDoor(target) then
        if sandbox().EnableSafeDoorPry ~= true then
            return false, "Reinforced doors disabled"
        end

        local minStrength = sandbox().ReinforcedDoorLevel or 8
        if player and player.getPerkLevel and player:getPerkLevel(Perks.Strength) < minStrength then
            return false, "Need more strength"
        end
    end

    return true
end

function CSR_Utils.canLockpickWorldTarget(target, player)
    if not target then
        return false, "Not a lockpick target"
    end

    if CSR_Utils.isBarricadedForPlayer(target, player) then
        return false, "Target is barricaded"
    end

    if instanceof(target, "IsoDoor") then
        if target:IsOpen() then
            return false, "Door already open"
        end
        return (target.isLocked and target:isLocked()) or (target.isLockedByKey and target:isLockedByKey()) or false
    end

    if instanceof(target, "IsoThumpable") and target.isDoor and target:isDoor() then
        if target:IsOpen() then
            return false, "Door already open"
        end
        return (target.isLocked and target:isLocked()) or (target.isLockedByKey and target:isLockedByKey()) or false
    end

    return false, "Not a door"
end

function CSR_Utils.isBoltCutterTarget(target)
    if not target then
        return false
    end

    -- Bolt cutters work on any locked door or gate

    if instanceof(target, "IsoDoor") then
        if target:IsOpen() then
            return false
        end
        return (target.isLocked and target:isLocked()) or (target.isLockedByKey and target:isLockedByKey())
    end

    if instanceof(target, "IsoThumpable") and target.isDoor and target:isDoor() then
        if target:IsOpen() then
            return false
        end
        return (target.isLocked and target:isLocked()) or (target.isLockedByKey and target:isLockedByKey())
    end

    return false
end

function CSR_Utils.canBoltCutWorldTarget(target, player)
    if not CSR_Utils.isBoltCutterTarget(target) then
        return false, "Not a bolt cutter target"
    end

    if CSR_Utils.isBarricadedForPlayer(target, player) then
        return false, "Target is barricaded"
    end

    return true
end

function CSR_Utils.calculateBoltCutSuccess(player, tool)
    local strength = player:getPerkLevel(Perks.Strength)
    local fitness = player:getPerkLevel(Perks.Fitness)
    local toolCondition = tool:getCondition() / math.max(1, tool:getConditionMax())
    local csrSandbox = SandboxVars and SandboxVars.CommonSenseReborn or nil
    local multiplier = (csrSandbox and csrSandbox.BoltCutSuccessMultiplier) or 1.0
    -- Bolt cutters are more reliable than prying (mechanical advantage)
    local baseChance = 0.35 + (strength * 0.04) + (fitness * 0.02) + (toolCondition * 0.25)
    return math.min(0.95, math.max(0.08, baseChance * multiplier))
end

function CSR_Utils.getNearbyPryVehiclePart(player)
    if not player then
        return nil, nil
    end

    local vehicle = player.getNearVehicle and player:getNearVehicle() or nil
    if not vehicle then
        return nil, nil
    end

    local part = vehicle.getUseablePart and vehicle:getUseablePart(player) or nil
    if not part or not part.getDoor or not part:getDoor() then
        return nil, nil
    end

    if not CSR_Utils.canPryVehiclePart(part) then
        return nil, nil
    end

    return vehicle, part
end

function CSR_Utils.getNearbyLockpickVehiclePart(player)
    if not player then
        return nil, nil
    end

    local vehicle = player.getNearVehicle and player:getNearVehicle() or nil
    if not vehicle then
        return nil, nil
    end

    local part = vehicle.getUseablePart and vehicle:getUseablePart(player) or nil
    if not part or not part.getDoor or not part:getDoor() then
        return nil, nil
    end

    if not CSR_Utils.canLockpickVehiclePart(part) then
        return nil, nil
    end

    return vehicle, part
end

function CSR_Utils.canPryVehiclePart(part)
    if not part or not part.getDoor or not part:getDoor() then
        return false
    end

    local partId = part.getId and string.lower(part:getId() or "") or ""
    if partId == "" or partId == "enginedoor" then
        return false
    end
    return part:getDoor():isLocked()
end

function CSR_Utils.canLockpickVehiclePart(part)
    if not part or not part.getDoor or not part:getDoor() then
        return false
    end

    local partId = part.getId and string.lower(part:getId() or "") or ""
    if partId == "" or partId == "enginedoor" then
        return false
    end

    return part:getDoor():isLocked()
end

function CSR_Utils.unlockVehicleDoorPart(vehicle, part, character, openDoor, breakLock)
    if not vehicle or not part or not part.getDoor or not part:getDoor() then
        print("[CSR] unlockVehicleDoorPart: invalid vehicle/part/door")
        return false
    end

    local door = part:getDoor()
    local partId = part.getId and part:getId() or "?"
    print("[CSR] unlockVehicleDoorPart: part=" .. tostring(partId)
        .. " locked=" .. tostring(door:isLocked())
        .. " open=" .. tostring(door:isOpen())
        .. " lockBroken=" .. tostring(door:isLockBroken())
        .. " openDoor=" .. tostring(openDoor)
        .. " breakLock=" .. tostring(breakLock))

    -- Force-unlock the door directly. Do NOT use toggleLockedDoor — it requires
    -- the player to have the vehicle key and silently fails without one.
    door:setLocked(false)

    if breakLock and door.setLockBroken then
        door:setLockBroken(true)
    end

    if openDoor then
        door:setOpen(true)
        -- Play the door open animation so the physics model moves the door
        -- out of the way. Without this, the door state says "open" but the
        -- collision geometry may still block entry.
        if vehicle.playPartAnim then
            vehicle:playPartAnim(part, "Open")
        end
        if character and vehicle.playPartSound then
            vehicle:playPartSound(part, character, "Open")
        end
    end

    if vehicle.transmitPartDoor then
        vehicle:transmitPartDoor(part)
    end

    if isServer() and vehicle.sendVars then
        vehicle:sendVars()
    end

    print("[CSR] unlockVehicleDoorPart AFTER: locked=" .. tostring(door:isLocked())
        .. " open=" .. tostring(door:isOpen())
        .. " lockBroken=" .. tostring(door:isLockBroken()))

    return not door:isLocked()
end

function CSR_Utils.hasVanillaHotwireAccess(player)
    if not player then
        return false
    end

    return (player:getPerkLevel(Perks.Electricity) >= 1 and player:getPerkLevel(Perks.Mechanics) >= 2)
        or player:hasTrait(CharacterTrait.BURGLAR)
end

function CSR_Utils.canAttemptImprovisedHotwire(player, vehicle)
    if not player or not vehicle or not vehicle.isDriver or not vehicle:isDriver(player) then
        return false
    end

    -- VehicleEasyUse sandbox var no longer blocks CSR hotwire

    if vehicle:isHotwired() or vehicle:isEngineRunning() then
        return false
    end

    if vehicle:isKeysInIgnition() or player:getInventory():haveThisKeyId(vehicle:getKeyId()) then
        return false
    end

    if CSR_Utils.hasVanillaHotwireAccess(player) then
        return false
    end

    return CSR_Utils.hasScrewdriver(player) ~= nil
end

function CSR_Utils.isPryTarget(target)
    if not target then
        return false
    end

    if instanceof(target, "IsoDoor") then
        return not target:IsOpen() and ((target.isLocked and target:isLocked()) or (target.isLockedByKey and target:isLockedByKey()))
    end

    if instanceof(target, "IsoThumpable") and target.isDoor and target:isDoor() then
        return not target:IsOpen() and ((target.isLocked and target:isLocked()) or (target.isLockedByKey and target:isLockedByKey()))
    end

    if instanceof(target, "IsoWindow") then
        if target:IsOpen() or (target.isSmashed and target:isSmashed()) then
            return false
        end
        if target.isPermaLocked and target:isPermaLocked() then
            return false
        end
        return (target.isLocked and target:isLocked()) or false
    end

    return false
end

function CSR_Utils.findWorldTarget(worldobjects, player, predicate)
    if not predicate then
        return nil
    end

    local best = nil
    local bestDist = math.huge

    local function considerObject(obj)
        if obj and predicate(obj) then
            local dist = getObjectDistanceSq(player, obj)
            if dist < bestDist then
                best = obj
                bestDist = dist
            end
        end
    end

    for _, obj in ipairs(worldobjects or {}) do
        considerObject(obj)
    end

    if best then
        return best
    end

    local fetch = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars or nil
    local clickedSquare = fetch and fetch.clickedSquare or nil
    if not clickedSquare or not getCell then
        return nil
    end

    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = getCell():getGridSquare(clickedSquare:getX() + dx, clickedSquare:getY() + dy, clickedSquare:getZ())
            if square then
                local objects = square:getObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        considerObject(objects:get(i))
                    end
                end
            end
        end
    end

    return best
end

function CSR_Utils.unlockTarget(target, character, skipOpen)
    if not target then
        return false
    end

    if instanceof(target, "IsoDoor") or (instanceof(target, "IsoThumpable") and target.isDoor and target:isDoor()) then
        local linkedDoors = {}
        local seen = {}

        local function addLinkedDoor(obj)
            if obj and not seen[obj] then
                seen[obj] = true
                table.insert(linkedDoors, obj)
            end
        end

        addLinkedDoor(target)

        -- For map-placed IsoDoor, use native Java static methods
        if instanceof(target, "IsoDoor") and IsoDoor then
            -- Double doors / fence gates via IsoDoor.getDoubleDoorObject
            if IsoDoor.getDoubleDoorObject then
                for i = 1, 4 do
                    local linked = IsoDoor.getDoubleDoorObject(target, i)
                    if linked then
                        addLinkedDoor(linked)
                    else
                        break
                    end
                end
            end

            -- Garage doors via IsoDoor.getGarageDoorFirst/Next
            if IsoDoor.getGarageDoorFirst then
                local garageDoor = IsoDoor.getGarageDoorFirst(target)
                while garageDoor do
                    addLinkedDoor(garageDoor)
                    if IsoDoor.getGarageDoorNext then
                        garageDoor = IsoDoor.getGarageDoorNext(garageDoor)
                    else
                        break
                    end
                end
            end
        end

        -- For player-built IsoThumpable doors, use buildUtil
        if instanceof(target, "IsoThumpable") and buildUtil then
            if buildUtil.getDoubleDoorObjects then
                local doubleDoors = buildUtil.getDoubleDoorObjects(target)
                if doubleDoors then
                    for i = 1, #doubleDoors do
                        addLinkedDoor(doubleDoors[i])
                    end
                end
            end

            if buildUtil.getGarageDoorObjects then
                local garageDoors = buildUtil.getGarageDoorObjects(target)
                if garageDoors then
                    for i = 1, #garageDoors do
                        addLinkedDoor(garageDoors[i])
                    end
                end
            end
        end

        for _, doorObj in ipairs(linkedDoors) do
            if doorObj.setLocked then
                doorObj:setLocked(false)
            end
            if doorObj.setLockedByKey then
                doorObj:setLockedByKey(false)
            end
            if doorObj.setIsLocked then
                doorObj:setIsLocked(false)
            end
            if doorObj.setPermaLocked then
                doorObj:setPermaLocked(false)
            end
            -- Mark this door as CSR-pryed in modData so OnObjectAdded can
            -- re-clear any lock the forceLocked tile property restores on
            -- chunk (re)load or after a close sync.
            if doorObj.getModData then
                local md = doorObj:getModData()
                if md then
                    md.csrPryed = true
                end
            end
            -- B42: syncIsoObject broadcasts world object state to all clients.
            -- sync() does not exist on IsoDoor/IsoThumpable in B42.
            if doorObj.syncIsoObject then
                doorObj:syncIsoObject(false, 0, nil, nil)
            end
            if doorObj.transmitModData then
                doorObj:transmitModData()
            end
        end

        if not skipOpen and character and target.ToggleDoor and not target:IsOpen() then
            -- Check if the door tile has the forceLocked property.
            -- When present, Java's ToggleDoor requires the character to hold
            -- a key with a matching keyId (e.g. vault/security doors).
            local hasForceLocked = false
            local spriteObj = target.getSprite and target:getSprite() or nil
            if spriteObj and spriteObj.getProperties then
                local props = spriteObj:getProperties()
                hasForceLocked = props and props.has and props:has("forceLocked") or false
            end

            if hasForceLocked then
                -- Get the door's assigned keyId so we can create a matching key.
                local keyId = -1
                if target.getKeyId then
                    keyId = target:getKeyId()
                end
                -- If no key is assigned yet, generate one and assign it to the door.
                if not keyId or keyId < 0 then
                    keyId = ZombRand(65534) + 1
                    if target.setKeyId then
                        target:setKeyId(keyId)
                        if target.syncIsoObject then
                            target:syncIsoObject(false, 0, nil, nil)
                        end
                    end
                end
                -- Create a temporary key with the matching keyId so that Java's
                -- ToggleDoor allows the toggle despite the forceLocked tile property.
                local inv = character:getInventory()
                local tempKey = instanceItem("Base.Key1")
                if tempKey and tempKey.setKeyId then
                    tempKey:setKeyId(keyId)
                end
                if tempKey then
                    inv:AddItem(tempKey)
                end
                target:ToggleDoor(character)
                if tempKey then
                    inv:Remove(tempKey)
                end
                -- Also leave a permanent Security Key so the player can re-open
                -- with E after closing. forceLocked restores isLocked=true in
                -- Java on every close; the matching key lets vanilla's key-check
                -- pass indefinitely without needing to pry again.
                local permKey = instanceItem("Base.Key1")
                if permKey then
                    permKey:setKeyId(keyId)
                    if permKey.setName then
                        permKey:setName("Security Key")
                    end
                    if permKey.setCustomName then
                        permKey:setCustomName(true)
                    end
                    local keyring = (inv and inv.FindAndReturn and inv:FindAndReturn("KeyRing"))
                                 or (inv and inv.getFirstTypeRecurse and inv:getFirstTypeRecurse("KeyRing"))
                    if keyring and keyring.getInventory then
                        keyring:getInventory():AddItem(permKey)
                    else
                        inv:AddItem(permKey)
                    end
                end
            else
                target:ToggleDoor(character)
            end

            if target.syncIsoObject then
                target:syncIsoObject(false, 0, nil, nil)
            end
        end
        return true
    end

    if instanceof(target, "IsoWindow") then
        if target.setPermaLocked then
            target:setPermaLocked(false)
        end
        if target.setIsLocked then
            target:setIsLocked(false)
        end
        if target.syncIsoObject then
            target:syncIsoObject(false, 0, nil, nil)
        end
        if not skipOpen and character and target.ToggleWindow and not target:IsOpen() then
            target:ToggleWindow(character)
            if target.syncIsoObject then
                target:syncIsoObject(false, 0, nil, nil)
            end
        end
        return true
    end

    return false
end

function CSR_Utils.hasDuctTape(player)
    return CSR_Utils.findPreferredDuctTape(player)
end

function CSR_Utils.hasGlue(player)
    return CSR_Utils.findPreferredGlue(player)
end

function CSR_Utils.hasTape(player)
    return CSR_Utils.findPreferredTape(player)
end

function CSR_Utils.getOpenCanResult(item)
    if not item or not item.getFullType then
        return nil
    end

    local explicit = OPEN_CAN_RESULTS[item:getFullType()]
    if explicit then
        return explicit
    end

    if not looksLikeClosedCan(item) then
        return nil
    end

    local replaceOnUseType = resolveReplaceOnUseFullType(item)
    if replaceOnUseType then
        return replaceOnUseType
    end

    return resolveOpenedFoodVariant(item)
end

function CSR_Utils.resolveInventorySelection(items)
    local resolved = {}
    local seenRefs = {}
    local seenIds = {}
    if not items then
        return resolved
    end

    local function addResolved(item)
        if not item then
            return
        end
        local itemId = item.getID and item:getID() or nil
        if itemId ~= nil then
            local key = tostring(itemId)
            if seenIds[key] then
                return
            end
            seenIds[key] = true
        elseif seenRefs[item] then
            return
        end
        seenRefs[item] = true
        table.insert(resolved, item)
    end

    for _, entry in ipairs(items) do
        if entry and entry.items then
            for i = 1, #entry.items do
                addResolved(entry.items[i])
            end
        else
            addResolved(entry)
        end
    end

    return resolved
end

function CSR_Utils.getRemainingConsumableAmount(item)
    if not item then
        return nil
    end

    if item.IsDrainable and item:IsDrainable() then
        if item.getCurrentUsesFloat and item.getUseDelta and item:getUseDelta() > 0 then
            return item:getCurrentUsesFloat()
        end
        if item.getDelta then
            return item:getDelta()
        end
    end

    if instanceof and instanceof(item, "Food") and item.getHungerChange then
        return math.abs(item:getHungerChange() * 100)
    end

    if item.getUsedDelta and item:getUsedDelta() > 0 then
        return item:getUsedDelta()
    end

    return nil
end

function CSR_Utils.getConditionPercent(item)
    if not item or not item.getCondition or not item.getConditionMax or item:getConditionMax() <= 0 then
        return nil
    end
    return math.floor((item:getCondition() / item:getConditionMax()) * 100)
end

function CSR_Utils.findBetterDuplicate(player, item)
    if not player or not item or not item.getFullType then
        return nil
    end

    local inventory = player:getInventory()
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if not items then
        return nil
    end

    local fullType = item:getFullType()
    local currentCondition = CSR_Utils.getConditionPercent(item) or -1
    local best = nil
    local bestCondition = currentCondition

    for i = 0, items:size() - 1 do
        local other = items:get(i)
        if other and other ~= item and other.getFullType and other:getFullType() == fullType then
            local otherCondition = CSR_Utils.getConditionPercent(other) or -1
            if otherCondition > bestCondition then
                best = other
                bestCondition = otherCondition
            end
        end
    end

    return best, bestCondition
end

function CSR_Utils.getItemFreshnessInsight(item)
    if not item or not instanceof or not instanceof(item, "Food") then
        return nil
    end

    local freezingTime = safeCall(item, "getFreezingTime")
    if type(freezingTime) == "number" and freezingTime > 0 then
        if safeCall(item, "isFrozen") then
            return "Frozen"
        end
        return "Freezing: " .. math.floor(freezingTime) .. "%"
    end

    -- B42.17: freshness windows live on the ScriptItem, not the InventoryItem.
    -- (item:getOffAge / item:getOffAgeMax return per-instance/runtime values
    -- that don't reliably reflect the item's spoilage curve.) Match the
    -- pattern used by eris_food_expiry, which works on B42.17 in production:
    --   age              = item:getAge()                        -- days
    --   daysFresh        = scriptItem:getDaysFresh()            -- days
    --   daysTotallyRot   = scriptItem:getDaysTotallyRotten()    -- days
    local age = safeCall(item, "getAge") or 0
    local script = safeCall(item, "getScriptItem")
    if not script then return nil end
    local daysFresh = safeCall(script, "getDaysFresh") or 0
    local daysRotten = safeCall(script, "getDaysTotallyRotten") or 0

    -- Sentinel: > ~10 years => never perishes (canned, jarred, sealed).
    if daysFresh > 3650 or daysRotten > 3650 or daysRotten <= 0 then
        return "Sealed"
    end

    if age >= daysRotten then
        return "Rotten"
    elseif daysFresh > 0 and age >= daysFresh then
        return "Going stale"
    end

    return "Fresh"
end

function CSR_Utils.getDrainableInsight(item)
    if not item then
        return nil
    end

    local fluidContainer = safeCall(item, "getFluidContainer")
    if fluidContainer then
        local amount = safeCall(fluidContainer, "getAmount")
        local capacity = safeCall(fluidContainer, "getCapacity")
        if type(amount) == "number" and type(capacity) == "number" and capacity > 0 then
            return math.max(0, math.floor((amount / capacity) * 100))
        end
    end

    if (item.IsDrainable and item:IsDrainable()) or (instanceof and instanceof(item, "DrainableComboItem")) then
        local uses = safeCall(item, "getCurrentUsesFloat")
        if type(uses) == "number" then
            return math.max(0, math.floor(uses * 100))
        end
    end

    return nil
end

function CSR_Utils.findSoonStaleFood(player)
    if not player then
        return nil
    end

    local inventory = player:getInventory()
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if not items then
        return nil
    end

    local best = nil
    local bestAge = nil
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and instanceof and instanceof(item, "Food") then
            local insight = CSR_Utils.getItemFreshnessInsight(item)
            if insight == "Going stale" then
                local age = safeCall(item, "getAge") or 0
                if not bestAge or age > bestAge then
                    best = item
                    bestAge = age
                end
            end
        end
    end

    return best
end

local function formatNutritionNumber(value)
    local numeric = tonumber(value)
    if not numeric then
        return "0"
    end
    if math.abs(numeric - math.floor(numeric + 0.5)) < 0.05 then
        return tostring(math.floor(numeric + 0.5))
    end
    return string.format("%.1f", numeric)
end

function CSR_Utils.getFoodNutritionValues(item)
    if not item or not instanceof or not instanceof(item, "Food") then
        return nil
    end

    local calories = tonumber(safeCall(item, "getCalories") or 0) or 0
    local carbs = tonumber(safeCall(item, "getCarbohydrates") or 0) or 0
    local fats = tonumber(safeCall(item, "getLipids") or 0) or 0
    local proteins = tonumber(safeCall(item, "getProteins") or 0) or 0

    if calories <= 0 and carbs <= 0 and fats <= 0 and proteins <= 0 then
        return nil
    end

    return {
        calories = calories,
        carbs = carbs,
        fats = fats,
        proteins = proteins,
    }
end

function CSR_Utils.getFoodNutritionSummary(item)
    local values = CSR_Utils.getFoodNutritionValues(item)
    if not values then
        return nil
    end

    return string.format(
        "%s kcal | P %sg | C %sg | F %sg",
        formatNutritionNumber(values.calories),
        formatNutritionNumber(values.proteins),
        formatNutritionNumber(values.carbs),
        formatNutritionNumber(values.fats)
    )
end

function CSR_Utils.getCharacterNutritionSummary(character)
    if not character or not character.getNutrition then
        return nil
    end

    local nutrition = character:getNutrition()
    if not nutrition then
        return nil
    end

    local weight = tonumber(safeCall(nutrition, "getWeight") or 0) or 0
    local calories = tonumber(safeCall(nutrition, "getCalories") or 0) or 0
    local proteins = tonumber(safeCall(nutrition, "getProteins") or 0) or 0
    local carbs = tonumber(safeCall(nutrition, "getCarbohydrates") or 0) or 0
    local fats = tonumber(safeCall(nutrition, "getLipids") or 0) or 0

    local trend = "Stable"
    if safeCall(nutrition, "isIncWeightLot") == true then
        trend = "Gaining fast"
    elseif safeCall(nutrition, "isIncWeight") == true then
        trend = "Gaining"
    elseif safeCall(nutrition, "isDecWeight") == true then
        trend = "Losing"
    end

    return {
        weight = weight,
        weightText = string.format("%s kg", formatNutritionNumber(weight)),
        trend = trend,
        calories = calories,
        caloriesText = formatNutritionNumber(calories) .. " kcal",
        proteins = proteins,
        proteinsText = formatNutritionNumber(proteins) .. " g",
        carbs = carbs,
        carbsText = formatNutritionNumber(carbs) .. " g",
        fats = fats,
        fatsText = formatNutritionNumber(fats) .. " g",
    }
end

function CSR_Utils.compareConsumablePriority(a, b)
    local aRemaining = CSR_Utils.getRemainingConsumableAmount(a)
    local bRemaining = CSR_Utils.getRemainingConsumableAmount(b)

    if aRemaining and bRemaining and aRemaining ~= bRemaining then
        return aRemaining < bRemaining
    end

    if aRemaining and not bRemaining then
        return true
    end

    if bRemaining and not aRemaining then
        return false
    end

    local aCondition = a and a.getCondition and a:getCondition() or nil
    local bCondition = b and b.getCondition and b:getCondition() or nil
    if aCondition and bCondition and aCondition ~= bCondition then
        return aCondition < bCondition
    end

    local aId = a and a.getID and a:getID() or 0
    local bId = b and b.getID and b:getID() or 0
    return aId < bId
end

function CSR_Utils.findPreferredInventoryItem(player, matcher)
    if not player or not matcher then
        return nil
    end

    local inventory = player:getInventory()
    if not inventory then
        return nil
    end

    local best = nil

    -- B42: use getAllEvalRecurse to search all containers including bags
    if inventory.getAllEvalRecurse then
        local results = inventory:getAllEvalRecurse(matcher)
        if results then
            for i = 0, results:size() - 1 do
                local item = results:get(i)
                if item and (not best or CSR_Utils.compareConsumablePriority(item, best)) then
                    best = item
                end
            end
        end
        return best
    end

    -- Fallback: manual iteration
    local function searchContainer(container)
        local items = container and container.getItems and container:getItems() or nil
        if not items then return end
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and matcher(item) and (not best or CSR_Utils.compareConsumablePriority(item, best)) then
                best = item
            end
        end
    end

    searchContainer(inventory)
    return best
end

function CSR_Utils.findInventoryItemById(player, itemId, expectedType)
    if not player or not itemId then
        return nil
    end

    local inventory = player:getInventory()
    if not inventory then
        return nil
    end

    local function searchContainer(container)
        local items = container and container.getItems and container:getItems() or nil
        if not items then return nil end
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and item.getID and item:getID() == itemId then
                if not expectedType or (item.getFullType and item:getFullType() == expectedType) then
                    return item
                end
            end
        end
        return nil
    end

    -- Search main inventory
    local found = searchContainer(inventory)
    if found then return found end

    -- Search sub-containers (bags, backpacks attached to player)
    local items = inventory.getItems and inventory:getItems() or nil
    if items then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and instanceof(item, "InventoryContainer") then
                local subInv = item.getInventory and item:getInventory() or nil
                if subInv then
                    found = searchContainer(subInv)
                    if found then return found end
                end
            end
        end
    end

    return nil
end

function CSR_Utils.findPreferredInventoryItemByTypes(player, types)
    return CSR_Utils.findPreferredInventoryItem(player, function(item)
        if not item or not item.getType then
            return false
        end

        local itemType = item:getType()
        for i = 1, #types do
            if itemType == types[i] then
                return true
            end
        end

        return false
    end)
end

function CSR_Utils.findPreferredDuctTape(player)
    return CSR_Utils.findPreferredInventoryItemByTypes(player, { "DuctTape" })
end

function CSR_Utils.findPreferredGlue(player)
    return CSR_Utils.findPreferredInventoryItemByTypes(player, { "Glue", "SuperGlue" })
end

function CSR_Utils.findPreferredTape(player)
    return CSR_Utils.findPreferredInventoryItemByTypes(player, { "Scotchtape", "Tape" })
end

function CSR_Utils.findPreferredLighterFluid(player)
    return CSR_Utils.findPreferredInventoryItemByTypes(player, { "LighterFluid" })
end

function CSR_Utils.findPreferredFabricMaterial(player)
    return CSR_Utils.findPreferredInventoryItemByTypes(player, { "RippedSheets", "DenimStrips", "LeatherStrips", "Sheet", "RippedSheetsDirty" })
end

function CSR_Utils.isClothingItem(item)
    return item and item.IsClothing and item:IsClothing()
end

function CSR_Utils.canPatchClothing(item, player)
    if not CSR_Utils.isClothingItem(item) then return false end
    if not CSR_Utils.isRepairableItem(item) then return false end
    if not player then return true end
    return CSR_Utils.findPreferredThread(player) ~= nil
        and CSR_Utils.findPreferredNeedle(player) ~= nil
        and CSR_Utils.findPreferredFabricMaterial(player) ~= nil
end

-- Returns a flat array of damaged worn clothing items (condition < max).
-- Used by Repair All Clothing.
function CSR_Utils.getDamagedWornClothing(player)
    local out = {}
    if not player or not player.getWornItems then return out end
    local worn = player:getWornItems()
    if not worn or not worn.size then return out end
    for i = 0, worn:size() - 1 do
        local entry = worn:get(i)
        local item = entry and entry.getItem and entry:getItem() or nil
        if item and CSR_Utils.isClothingItem(item) and CSR_Utils.isRepairableItem(item) then
            local cond = item.getCondition and item:getCondition() or 0
            local condMax = item.getConditionMax and item:getConditionMax() or 0
            local hasPatches = item.getPatchesNumber and (item:getPatchesNumber() or 0) > 0
            if cond < condMax or hasPatches then
                out[#out + 1] = item
            end
        end
    end
    return out
end

-- Counts the number of fabric strips currently in the player's main inventory
-- across the same accepted types as findPreferredFabricMaterial.
function CSR_Utils.countFabricMaterials(player)
    if not player or not player.getInventory then return 0 end
    local inv = player:getInventory()
    if not inv then return 0 end
    local total = 0
    local types = { "RippedSheets", "DenimStrips", "LeatherStrips", "Sheet", "RippedSheetsDirty" }
    for i = 1, #types do
        if inv.getNumberOfItem then
            total = total + (inv:getNumberOfItem(types[i], false, true) or 0)
        end
    end
    return total
end

-- Gate for the Repair All Clothing context entry. Requires at least one damaged
-- worn garment and the basic tailoring kit (thread + needle + 1 fabric).
function CSR_Utils.canRepairAllClothing(player)
    if not player then return false end
    if CSR_Utils.findPreferredThread(player) == nil then return false end
    if CSR_Utils.findPreferredNeedle(player) == nil then return false end
    if CSR_Utils.findPreferredFabricMaterial(player) == nil then return false end
    local list = CSR_Utils.getDamagedWornClothing(player)
    return #list > 0
end

function CSR_Utils.isClipboard(item)
    return item and item.getFullType and item:getFullType() == "Base.Clipboard"
end

function CSR_Utils.getClipboardData(item)
    if not CSR_Utils.isClipboard(item) then
        return nil
    end

    local modData = item:getModData()
    modData.CSRClipboard = modData.CSRClipboard or {
        version = 1,
        title = "Clipboard",
        paperAmount = 0,
        entries = {},
    }

    local data = modData.CSRClipboard
    data.version = data.version or 1
    data.title = data.title or "Clipboard"
    data.paperAmount = math.max(0, math.min(5, tonumber(data.paperAmount) or 0))
    data.entries = data.entries or {}

    local maxEntries = data.paperAmount * 6
    if maxEntries <= 0 then
        data.entries = {}
    elseif #data.entries > maxEntries then
        for i = #data.entries, maxEntries + 1, -1 do
            data.entries[i] = nil
        end
    end

    return data
end

function CSR_Utils.getClipboardEntryCapacity(item)
    local data = CSR_Utils.getClipboardData(item)
    if not data then
        return 0
    end
    return data.paperAmount * 6
end

function CSR_Utils.canOpenClipboard(item)
    return CSR_Utils.getClipboardEntryCapacity(item) > 0
end

function CSR_Utils.getClipboardSummary(item)
    local data = CSR_Utils.getClipboardData(item)
    if not data then
        return nil
    end

    local checked = 0
    local total = 0
    for i = 1, #data.entries do
        local entry = data.entries[i]
        if entry and type(entry.text) == "string" and entry.text:gsub("%s+", "") ~= "" then
            total = total + 1
            if entry.checked then
                checked = checked + 1
            end
        end
    end

    return {
        title = data.title or "Clipboard",
        paperAmount = data.paperAmount or 0,
        totalEntries = total,
        checkedEntries = checked,
    }
end

function CSR_Utils.getClipboardItemNames(player)
    if not player then
        return {}
    end

    local names = {}
    local inv = player.getInventory and player:getInventory() or nil
    if not inv then
        return names
    end

    local items = inv:getItems()
    if not items then
        return names
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and CSR_Utils.isClipboard(item) then
            local data = CSR_Utils.getClipboardData(item)
            if data and data.entries then
                for _, entry in ipairs(data.entries) do
                    if entry and type(entry.text) == "string" then
                        local clean = entry.text:match("^(.-)%s*x%d+$") or entry.text
                        clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
                        if clean ~= "" then
                            names[clean] = true
                        end
                    end
                end
            end
        end
    end

    return names
end

function CSR_Utils.makeRequestId(player, actionName)
    local onlineId = player and player.getOnlineID and player:getOnlineID() or 0
    local username = player and player.getUsername and player:getUsername() or "player"
    local stamp = getTimestampMs and getTimestampMs() or os.time() * 1000
    return table.concat({
        tostring(actionName or "CSR"),
        tostring(onlineId),
        tostring(username),
        tostring(stamp),
        tostring(ZombRand(1000000)),
    }, ":")
end

CSR_Utils._ammoBoxMap = nil

local function buildAmmoBoxMap()
    local map = {
        ["Base.Bullets9mmBox"]    = { round = "Base.Bullets9mm",    count = 50 },
        ["Base.Bullets45Box"]     = { round = "Base.Bullets45",     count = 50 },
        ["Base.Bullets38Box"]     = { round = "Base.Bullets38",     count = 50 },
        ["Base.Bullets357Box"]    = { round = "Base.Bullets357",    count = 50 },
        ["Base.Bullets44Box"]     = { round = "Base.Bullets44",     count = 20 },
        ["Base.308Box"]           = { round = "Base.308Bullets",    count = 20 },
        ["Base.556Box"]           = { round = "Base.556Bullets",    count = 20 },
        ["Base.3030Box"]          = { round = "Base.3030Bullets",   count = 20 },
        ["Base.ShotgunShellsBox"] = { round = "Base.ShotgunShells", count = 25 },
    }

    local sm = getScriptManager and getScriptManager() or nil
    if sm and sm.getItem and sm:getItem("Base.9x39Box") then
        map["Base.Bullets357Box"].count = 30
        map["Base.556Box"].count = 60
        map["Base.9x39Box"]            = { round = "Base.9x39Bullets",    count = 30 }
        map["Base.Bullets22LRBox"]     = { round = "Base.Bullets22LR",    count = 60 }
        map["Base.Bullets32Box"]       = { round = "Base.Bullets32",      count = 50 }
        map["Base.Bullets50Box"]       = { round = "Base.Bullets50",      count = 20 }
        map["Base.Bullets50MagnumBox"] = { round = "Base.Bullets50Magnum", count = 30 }
        map["Base.545x39Box"]         = { round = "Base.545x39Bullets",   count = 30 }
        map["Base.30_06Box"]          = { round = "Base.30_06Bullets",    count = 20 }
        map["Base.303Box"]            = { round = "Base.303Bullets",      count = 20 }
        map["Base.762x39Box"]         = { round = "Base.762x39Bullets",   count = 30 }
        map["Base.762x54rBox"]        = { round = "Base.762x54rBullets",  count = 20 }
        map["Base.792x57Box"]         = { round = "Base.792x57Bullets",   count = 20 }
    end

    -- Dynamic scan: detect modded ammo boxes/cartons from ScriptManager
    if sm and sm.getAllItems then
        local ok, allItems = pcall(function() return sm:getAllItems() end)
        if ok and allItems then
            -- Index all items by full type for lookup
            local itemIndex = {}
            for i = 0, allItems:size() - 1 do
                local script = allItems:get(i)
                if script and script.getFullType then
                    itemIndex[script:getFullType()] = script
                end
            end

            -- Find items ending in "Box", "Carton", or "CartonBig"
            local suffixes = { "CartonBig", "Carton", "Box" }
            for fullType, script in pairs(itemIndex) do
                if not map[fullType] then
                    for _, suffix in ipairs(suffixes) do
                        local base = string.match(fullType, "^(.+)" .. suffix .. "$")
                        if base then
                            -- Try matching round item directly
                            local roundType = nil
                            if itemIndex[base] then
                                roundType = base
                            elseif itemIndex[base .. "Bullets"] then
                                roundType = base .. "Bullets"
                            end

                            if roundType then
                                local roundScript = itemIndex[roundType]
                                -- Verify the round has Ammo tag or DisplayCategory
                                local isAmmo = false
                                if roundScript then
                                    local ok2, tags = pcall(function() return roundScript:getTags() end)
                                    if ok2 and tags then
                                        local tagStr = tostring(tags)
                                        if string.find(tagStr, "Ammo") then
                                            isAmmo = true
                                        end
                                    end
                                    if not isAmmo then
                                        local ok3, cat = pcall(function() return roundScript:getDisplayCategory() end)
                                        if ok3 and cat and tostring(cat) == "Ammo" then
                                            isAmmo = true
                                        end
                                    end
                                end

                                if isAmmo then
                                    -- Calculate count from weight ratio (box / round weight)
                                    local count = 20
                                    local ok4, boxWeight = pcall(function() return script:getActualWeight() end)
                                    local ok5, roundWeight = pcall(function() return roundScript:getActualWeight() end)
                                    if ok4 and ok5 and boxWeight and roundWeight and roundWeight > 0 then
                                        local calc = math.floor(boxWeight / roundWeight)
                                        if calc >= 1 and calc <= 500 then
                                            count = calc
                                        end
                                    end
                                    map[fullType] = { round = roundType, count = count }
                                    print("[CSR] AmmoBoxMap: detected modded ammo " .. tostring(fullType) .. " -> " .. tostring(roundType) .. " x" .. tostring(count))
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    return map
end

function CSR_Utils.getAmmoBoxMap()
    if not CSR_Utils._ammoBoxMap then
        CSR_Utils._ammoBoxMap = buildAmmoBoxMap()
    end
    return CSR_Utils._ammoBoxMap
end

function CSR_Utils.isAmmoBox(item)
    if not item or not item.getFullType then return false end
    return CSR_Utils.getAmmoBoxMap()[item:getFullType()] ~= nil
end

function CSR_Utils.getAmmoBoxInfo(item)
    if not item or not item.getFullType then return nil end
    return CSR_Utils.getAmmoBoxMap()[item:getFullType()]
end

function CSR_Utils.getReverseAmmoBoxMap()
    if not CSR_Utils._reverseAmmoBoxMap then
        local map = CSR_Utils.getAmmoBoxMap()
        local rev = {}
        for boxType, info in pairs(map) do
            rev[info.round] = { box = boxType, count = info.count }
        end
        CSR_Utils._reverseAmmoBoxMap = rev
    end
    return CSR_Utils._reverseAmmoBoxMap
end

function CSR_Utils.isAmmoRound(item)
    if not item or not item.getFullType then return false end
    return CSR_Utils.getReverseAmmoBoxMap()[item:getFullType()] ~= nil
end

function CSR_Utils.getAmmoRoundInfo(item)
    if not item or not item.getFullType then return nil end
    return CSR_Utils.getReverseAmmoBoxMap()[item:getFullType()]
end

function CSR_Utils.countAmmoRoundsOfType(player, roundType)
    if not player or not roundType then return 0 end
    local count = 0
    local function searchContainer(container)
        local items = container and container.getItems and container:getItems() or nil
        if not items then return end
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and item.getFullType and item:getFullType() == roundType then
                count = count + 1
            end
        end
    end
    local mainInv = player:getInventory()
    searchContainer(mainInv)
    local mainItems = mainInv and mainInv.getItems and mainInv:getItems() or nil
    if mainItems then
        for i = 0, mainItems:size() - 1 do
            local item = mainItems:get(i)
            if item and instanceof(item, "InventoryContainer") then
                local subInv = item.getInventory and item:getInventory() or nil
                if subInv then searchContainer(subInv) end
            end
        end
    end
    return count
end

function CSR_Utils.collectAmmoRounds(player, roundType, maxCount)
    if not player or not roundType then return {} end
    local collected = {}
    local function searchContainer(container)
        if maxCount and #collected >= maxCount then return end
        local items = container and container.getItems and container:getItems() or nil
        if not items then return end
        for i = 0, items:size() - 1 do
            if maxCount and #collected >= maxCount then break end
            local item = items:get(i)
            if item and item.getFullType and item:getFullType() == roundType then
                collected[#collected + 1] = item
            end
        end
    end
    local mainInv = player:getInventory()
    searchContainer(mainInv)
    local mainItems = mainInv and mainInv.getItems and mainInv:getItems() or nil
    if mainItems then
        for i = 0, mainItems:size() - 1 do
            if maxCount and #collected >= maxCount then break end
            local item = mainItems:get(i)
            if item and instanceof(item, "InventoryContainer") then
                local subInv = item.getInventory and item:getInventory() or nil
                if subInv then searchContainer(subInv) end
            end
        end
    end
    return collected
end

function CSR_Utils.isModLoaded(modId)
    if getActivatedMods and getActivatedMods().contains then
        return getActivatedMods():contains(modId)
    end
    return false
end

-- OnObjectAdded: re-clear lock state for any door/window that was previously
-- pried by CSR. forceLocked tile properties can restore isLocked=true when the
-- world chunk is (re)loaded or when the door object is re-synced after close.
-- We detect this by checking modData.csrPryed and calling setLocked(false) again.
local function onCSRObjectAdded(obj)
    if not obj then return end
    local md = obj.getModData and obj:getModData() or nil
    if not md or not md.csrPryed then return end
    if obj.setLocked then obj:setLocked(false) end
    if obj.setLockedByKey then obj:setLockedByKey(false) end
    if obj.setIsLocked then obj:setIsLocked(false) end
    if obj.setPermaLocked then obj:setPermaLocked(false) end
    if obj.syncIsoObject then
        obj:syncIsoObject(false, 0, nil, nil)
    end
end

if Events and Events.OnObjectAdded then
    Events.OnObjectAdded.Add(onCSRObjectAdded)
end

return CSR_Utils


