-- A read-only view of the current local survivor's normal Health UI state.
-- Treatment stays in ISHealthPanel, including inventory checks and timed actions.
require("ATFCombatHealth/SmartTreatmentResolver")
ATFCombatHealthModel = ATFCombatHealthModel or {}
local Model = ATFCombatHealthModel
local referenceSlots, nextReference = {}, 0

function Model.clear(playerNum)
    if playerNum == nil then
        referenceSlots = {}
    else
        referenceSlots[playerNum] = nil
    end
end

local function referenceState(player, count)
    local slot = player:getPlayerNum()
    local state = referenceSlots[slot]
    if not state or state.player ~= player then
        -- Keep only the current survivor's references in each local slot.
        state = { player = player, parts = {} }
        referenceSlots[slot] = state
    end
    for ordinal in pairs(state.parts) do
        if ordinal >= count then
            state.parts[ordinal] = nil
        end
    end
    return state
end

local function referenceId(state, ordinal, bodyPart)
    local entry = state.parts[ordinal]
    if not entry or entry.bodyPart ~= bodyPart then
        nextReference = nextReference + 1
        entry = { bodyPart = bodyPart, id = nextReference }
        state.parts[ordinal] = entry
    end
    -- Kahlua's tostring(table) can change when that table's contents change.
    -- Assign identity from reference equality instead of its displayed hash.
    return entry.id
end

local function text(key, fallback)
    return getTextOrNull(key) or fallback
end

local function currentLocalPlayer(player)
    return player
        and player:isLocalPlayer()
        and getSpecificPlayer(player:getPlayerNum()) == player
        and not player:isDead()
end

local function ownHealthPanel(player)
    local info = getPlayerInfoPanel and getPlayerInfoPanel(player:getPlayerNum())
    local panel = info and info.healthView
    if panel and panel.character == player and not panel.otherPlayer then
        return panel
    end
end

local function field(value)
    value = tostring(value)
    return tostring(#value) .. ":" .. value
end

local function appendSuffix(label, key)
    return label .. " (" .. getText(key) .. ")"
end

-- These labels and skill gates match the non-cheat branch of the installed
-- ISHealthBodyPartListBox:doDrawItem. Do not expose its debug wound timers,
-- zombie infection state, or information covered by a bandage. Native muscle
-- stiffness is summarized separately because it has no medical action.
local injurySignals = {
    IGUI_health_Scratched = { "scratch", 1 },
    IGUI_health_Cut = { "cut", 1 },
    IGUI_health_DeepWound = { "deepWound", 1 },
    IGUI_health_Bitten = { "bite", 1 },
    IGUI_health_Pain = { "pain", 1 },
    IGUI_health_HeavyPain = { "pain", 2 },
    IGUI_health_Bleeding = { "bleeding", 1 },
    IGUI_health_Fracture = { "fracture", 1 },
    IGUI_health_DirtyBandage = { "dirtyBandage", 1 },
    IGUI_health_Infected = { "infection", 1 },
    IGUI_health_LodgedBullet = { "bullet", 1 },
    IGUI_health_Burned = { "burn", 1 },
    IGUI_health_LodgedGlassShards = { "glass", 1 },
}
local function visibleLabels(bodyPart, doctorLevel)
    local labels, emphasis, signals = {}, 0, {}
    local function add(key, color, suffix)
        local label = getText(key)
        if suffix then
            label = appendSuffix(label, suffix)
        end
        labels[#labels + 1] = label
        local signal = injurySignals[key]
        if signal then
            signals[signal[1]] = signal[2]
        end
        emphasis = math.max(emphasis, color or 0)
    end
    local function woundSuffix(getter, gate, severe, moderate)
        if doctorLevel <= gate then
            return nil
        end
        local time = bodyPart[getter](bodyPart)
        if time > severe then
            return "IGUI_health_Severe"
        elseif time > moderate then
            return "IGUI_health_Moderate"
        end
    end

    if bodyPart:getPlantainFactor() > 0 then
        add("ContextMenu_PlantainCataplasm")
    end
    if bodyPart:getComfreyFactor() > 0 then
        add("ContextMenu_ComfreyCataplasm")
    end
    if bodyPart:getGarlicFactor() > 0 then
        add("ContextMenu_GarlicCataplasm")
    end
    if bodyPart:scratched() then
        add("IGUI_health_Scratched", 1, woundSuffix("getScratchTime", 2, 17, 14))
    end
    if bodyPart:isCut() then
        add("IGUI_health_Cut", 1, woundSuffix("getCutTime", 2, 17, 14))
    end
    if bodyPart:deepWounded() then
        add("IGUI_health_DeepWound", 1, woundSuffix("getDeepWoundTime", 4, 10, 8))
    end
    if bodyPart:bitten() then
        add("IGUI_health_Bitten", 1)
    end
    local pain = bodyPart:getAdditionalPain()
    if pain > 10 then
        add(pain > 50 and "IGUI_health_HeavyPain" or "IGUI_health_Pain", 1)
    end
    if bodyPart:bleeding() then
        -- Emphasis is a presentation hint, not a calculated wound severity.
        add("IGUI_health_Bleeding", 2)
    end
    local fracture, splint = bodyPart:getFractureTime(), bodyPart:getSplintFactor()
    if fracture > 0 and splint == 0 then
        add("IGUI_health_Fracture", 1, woundSuffix("getFractureTime", 6, 50, 20))
    end
    if splint > 0 then
        local suffix
        if doctorLevel > 4 then
            if splint > 4 then
                suffix = "IGUI_health_Good"
            elseif fracture > 2 then
                suffix = "IGUI_health_Moderate"
            end
        end
        add("IGUI_health_Splinted", 0, suffix)
    end
    local bandaged = bodyPart:bandaged()
    if bandaged then
        local clean = bodyPart:getBandageLife() > 0
        add(clean and "IGUI_health_Bandaged" or "IGUI_health_DirtyBandage", clean and 0 or 1)
    end
    if not bandaged then
        if
            bodyPart:isInfectedWound()
            and (doctorLevel > 8 or bodyPart:getWoundInfectionLevel() * 10 >= 2.5 - doctorLevel)
        then
            add("IGUI_health_Infected", 1)
        end
        if bodyPart:haveBullet() then
            add("IGUI_health_LodgedBullet", 1)
        end
        if bodyPart:getBurnTime() > 0 then
            local suffix = doctorLevel > 4
                and bodyPart:isNeedBurnWash()
                and "IGUI_health_NeedCleaning"
            add("IGUI_health_Burned", 1, suffix)
        end
    end
    if bodyPart:stitched() then
        local suffix
        if doctorLevel > 6 then
            suffix = bodyPart:getStitchTime() > 40 and "IGUI_health_Good" or "IGUI_health_NeedTime"
        end
        add("IGUI_health_Stitched", 0, suffix)
    end
    if not bandaged and bodyPart:haveGlass() then
        add("IGUI_health_LodgedGlassShards", 1)
    end
    return labels, emphasis, signals
end

function Model.snapshot(player)
    if not currentLocalPlayer(player) then
        return nil
    end
    local damage = player:getBodyDamage()
    local parts = damage:getBodyParts()
    local references = referenceState(player, parts:size())
    local doctorLevel = player:getPerkLevel(Perks.Doctor)
    local rows, allRows, bleeding, strainCount, strainGrade = {}, {}, 0, 0, 0
    for ordinal = 0, parts:size() - 1 do
        local bodyPart = parts:get(ordinal)
        if bodyPart:bleeding() then
            bleeding = bleeding + 1
        end
        local labels, emphasis, signals = {}, 0, {}
        local stiffness = bodyPart:getStiffness()
        if
            bodyPart:HasInjury()
            or bodyPart:bandaged()
            or bodyPart:stitched()
            or bodyPart:getSplintFactor() > 0
            or bodyPart:getAdditionalPain() > 10
            or stiffness > 5
        then
            labels, emphasis, signals = visibleLabels(bodyPart, doctorLevel)
            -- Native getDamagedParts requires >5 for a strain-only part;
            -- its renderer also shows exactly 5 on otherwise visible parts.
            -- Keep that visibility while presenting strain outside treatment.
            if stiffness >= 5 then
                strainCount = strainCount + 1
                strainGrade = math.max(strainGrade, stiffness < 20 and 1 or 2)
            end
        end
        local visibleInjury = #labels > 0
        if not visibleInjury then
            -- This does not diagnose a concealed wound: allRows uses the same
            -- placeholder for an undetectable condition and an uninjured part.
            labels = { text("UI_ATFCombatHealth_NoInjury", "No visible injury") }
        end
        local name = BodyPartType.getDisplayName(bodyPart:getType())
        local fingerprint = {
            field(ordinal),
            field(referenceId(references, ordinal, bodyPart)),
            field(name),
            field(emphasis),
        }
        for _, label in ipairs(labels) do
            fingerprint[#fingerprint + 1] = field(label)
        end
        local row = {
            id = ordinal,
            bodyPart = bodyPart,
            name = name,
            labels = labels,
            signals = signals,
            summary = table.concat(labels, ", "),
            severity = emphasis,
            fingerprint = table.concat(fingerprint),
        }
        allRows[#allRows + 1] = row
        if visibleInjury then
            rows[#rows + 1] = row
        end
    end

    local rawHealth = damage:getHealth()
    local health = math.floor(rawHealth * 10 + 0.5) / 10
    local panel = ownHealthPanel(player)
    local nativeStatus = panel and panel.healthPanel and panel.healthPanel.javaObject
    local status = nativeStatus and nativeStatus:getDamageStatusString()
        or (getText("IGUI_health_Overall_Body_Status") .. ": " .. tostring(health))
    local moodles = player:getMoodles()
    local pain = moodles:getMoodleLevel(MoodleType.PAIN)
    local bleedingLevel = moodles:getMoodleLevel(MoodleType.BLEEDING)
    local painText = pain > 0 and getText("Moodles_Pain_lvl" .. pain)
        or text("UI_ATFCombatHealth_NoPain", "No pain")
    -- PZ exposes active bleeding, not a surviving blood-volume measurement.
    local blood = bleeding > 0 and getText("IGUI_health_Bleeding")
        or text("UI_ATFCombatHealth_NoActiveBleeding", "No active bleeding")
    local critical = bleedingLevel >= 3 or pain >= 3
    local strain = strainCount > 0
            and {
                count = strainCount,
                text = getText(
                    strainGrade == 1 and "IGUI_health_MinorStiffness" or "IGUI_health_Stiffness"
                ),
            }
        or nil
    local signature = {
        field(health),
        field(status),
        field(pain),
        field(painText),
        field(bleeding),
        field(blood),
        field(critical),
        field(strainCount),
        field(strain and strain.text or ""),
    }
    for _, row in ipairs(allRows) do
        signature[#signature + 1] = field(row.fingerprint)
    end
    return {
        rows = rows,
        allRows = allRows,
        health = health,
        rawHealth = rawHealth,
        status = status,
        pain = pain,
        painText = painText,
        bleeding = bleeding,
        blood = blood,
        critical = critical,
        strain = strain,
        signature = table.concat(signature),
    }
end

function Model.openTreatment(player, bodyPart, x, y, preference)
    if not currentLocalPlayer(player) or not bodyPart then
        return false
    end
    -- A cached row may outlive a reconnect or a replacement BodyDamage object.
    local parts = player:getBodyDamage():getBodyParts()
    local current = false
    for ordinal = 0, parts:size() - 1 do
        if parts:get(ordinal) == bodyPart then
            current = true
            break
        end
    end
    local panel = ownHealthPanel(player)
    if not current or not panel or not panel.doBodyPartContextMenu then
        return false
    end
    local doctorLevel = player:getPerkLevel(Perks.Doctor)
    local labels = visibleLabels(bodyPart, doctorLevel)
    if #labels == 0 then
        -- A stale row may now contain only passive strain or have healed.
        return false
    end
    panel.doctorLevel = doctorLevel
    return ATFSmartTreatmentResolver.open(player, bodyPart, x, y, preference)
end

return Model
