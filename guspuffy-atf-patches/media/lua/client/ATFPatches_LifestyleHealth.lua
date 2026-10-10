-- Add Lifestyle's hidden Yoga skill to Skills and reuse its wellness callbacks.
-- Keep wellness out of FitnessExercises: Lifestyle's Zen bonus mutates every entry.
ATFPatches_LifestyleHealth = ATFPatches_LifestyleHealth or {}
local H = ATFPatches_LifestyleHealth
H.wrappers = H.wrappers or {}

local function text(key, fallback)
    return getTextOrNull(key) or fallback
end

function H.enabled()
    return SandboxVars
        and SandboxVars.Text
        and SandboxVars.Text.DividerMeditationNew
        and HiddenSkills
        and HiddenSkills.getSkill
        and Perks
        and Perks.Meditation
        and ZenWellnessContextMenu
        and ZenWellnessContextMenu.Options
        and ZenWellnessContextMenu.Options.Yoga
        and ZenWellnessContextMenu.Options.Meditation
end

function H.skillsEnabled()
    return SandboxVars
        and SandboxVars.Text
        and SandboxVars.Text.DividerMeditationNew
        and HiddenSkills
        and HiddenSkills.getSkill
        and Perks
        and Perks.Lifestyle
end

function H.yogaProgress(player)
    local values = HiddenSkills.getSkill(player, "Yoga")
    if not values then
        return
    end
    local level = math.max(0, math.min(10, math.floor(tonumber(values[1]) or 0)))
    local xp, target = math.max(0, tonumber(values[2]) or 0), tonumber(values[3]) or 0
    return {
        level = level,
        xp = xp,
        target = target,
        fraction = level == 10 and 1 or (target > 0 and math.min(1, xp / target) or 0),
    }
end

function H.makeYogaBar(panel, x, y)
    H.yogaBarClass = H.yogaBarClass or ISSkillProgressBar:derive("ATFPatches_YogaSkillBar")
    local class = H.yogaBarClass
    function class:renderPerkRect()
        local progress = H.yogaProgress(self.char)
        if progress.level > self.level then
            self.parent.lastLeveledUpPerk = self
            self.parent.lastLevelUpTime = 1
        end
        self.level, self.xp, self.xpForLvl = progress.level, progress.xp, progress.target
        local size = math.floor((getTextManager():getFontHeight(UIFont.Small) + 6) / 2)
        local spacing = getCore():getOptionFontSizeReal()
        -- Match ISSkillProgressBar: completed units are gold, only the current
        -- unit has a light gray outline/fill, and future units are dark outlines.
        local r, g, b = 1, 0.89, 0.38
        if self.parent.lastLeveledUpPerk == self then
            local time = self.parent.lastLevelUpTime
            local good = getCore():getGoodHighlitedColor()
            r = r * (1 - time) + good:getR() * time
            g = g * (1 - time) + good:getG() * time
            b = b * (1 - time) + good:getB() * time
        end
        for i = 0, 9 do
            local sx = i * (size + spacing)
            if i < progress.level then
                self:drawTextureScaled(self.SkillUnitFilled, sx, 0, size, size, 1, r, g, b)
                self:drawTextureScaled(self.SkillUnitBorder, sx, 0, size, size, 1, r, g, b)
            elseif i == progress.level then
                if progress.fraction == 1 then
                    self:drawTextureScaled(
                        self.SkillUnitFilled,
                        sx,
                        0,
                        size,
                        size,
                        1,
                        1,
                        0.89,
                        0.38
                    )
                    self:drawTextureScaled(self.SkillUnitBorder, sx, 0, size, size, 1, 1, 1, 1)
                else
                    self:drawTextureScaled(
                        self.SkillUnitBorder,
                        sx,
                        0,
                        size,
                        size,
                        1,
                        0.4,
                        0.4,
                        0.4
                    )
                    self:drawTextureScaled(
                        self.SkillUnitFilled,
                        sx,
                        0,
                        size * progress.fraction,
                        size,
                        1,
                        0.4,
                        0.4,
                        0.4
                    )
                end
            else
                self:drawTextureScaled(self.SkillUnitBorder, sx, 0, size, size, 1, 0.2, 0.2, 0.2)
            end
        end
    end
    function class:updateTooltip()
        local progress = H.yogaProgress(self.char)
        self.level = progress.level
        self.message = text("IGUI_perks_Yoga", "Yoga")
            .. " "
            .. text("IGUI_PlayerStats_Level", "Level")
            .. " "
            .. progress.level
            .. " <LINE> "
            .. (progress.level == 10 and text("IGUI_ATFPatches_Mastered", "Mastered") or string.format(
                "%g / %g %s",
                progress.xp,
                progress.target,
                text("IGUI_XP_xp", "XP")
            ))
            .. " <LINE><LINE> "
            .. text("IGUI_ATFPatches_YogaDescription", "Improves by completing Yoga sessions.")
    end
    function class:onMouseUp() end
    function class:activate() end
    local size = math.floor((getTextManager():getFontHeight(UIFont.Small) + 6) / 2)
    local bar = ISPanel.new(class, x, y, (size + getCore():getOptionFontSizeReal()) * 10, size)
    bar.char, bar.parent, bar.level = panel.char, panel, H.yogaProgress(panel.char).level
    bar:noBackground()
    bar.SkillUnitFilled = getTexture("media/ui/SkillPanel/SkillUnit_Fill.png")
    bar.SkillUnitBorder = getTexture("media/ui/SkillPanel/SkillUnit_Border.png")
    bar:initialise()
    return bar
end

function H.skillsChildren(original, panel, ...)
    if H.skillsEnabled() then
        panel.perks[Perks.Lifestyle] = panel.perks[Perks.Lifestyle] or {}
        panel.txtLen = math.max(
            panel.txtLen,
            getTextManager():MeasureStringX(UIFont.Small, text("IGUI_perks_Yoga", "Yoga"))
        )
    end
    return original(panel, ...)
end

function H.skillsRender(original, panel, ...)
    local font = getTextManager():getFontHeight(UIFont.Small)
    local row, y, count, insertY, insertIndex = font + 6, 10, 0
    if H.skillsEnabled() then
        for i, parent in ipairs(panel.sorted) do
            y = y + row
            if not panel.collapse[i] then
                y = y + 10
                local children = panel.perks[parent:getType()]
                y, count = y + #children * row, count + #children
                if parent:getType() == Perks.Lifestyle then
                    insertY, insertIndex = y, count + 1
                end
            end
            y = y + 10
        end
    end
    if
        panel.atfYogaBar and (not insertY or panel.reloadSkillBar or not panel.progressBarLoaded)
    then
        panel.atfYogaBar:removeTooltip()
        panel.atfYogaBar = nil
        panel.reloadSkillBar = true
    end
    if not insertY then
        return original(panel, ...)
    end
    -- Keep native perk XP APIs, boosts, ordering and render behavior. Reserve a
    -- display-only row after Lifestyle's real skills; no fake Java perk is added.
    local fields = { "drawText", "drawTexture", "setHeightAndParentHeight", "setScrollHeight" }
    local saved, methods = {}, {}
    for _, field in ipairs(fields) do
        saved[field], methods[field] = rawget(panel, field), panel[field]
    end
    panel.drawText = function(self, label, x, py, ...)
        return methods.drawText(self, label, x, py >= insertY and py + row or py, ...)
    end
    panel.drawTexture = function(self, texture, x, py, ...)
        return methods.drawTexture(self, texture, x, py >= insertY and py + row or py, ...)
    end
    panel.setHeightAndParentHeight = function(self, height)
        return methods.setHeightAndParentHeight(self, math.min(800, height + row))
    end
    panel.setScrollHeight = function(self, height)
        return methods.setScrollHeight(self, height + row)
    end
    local ok, result = pcall(original, panel, ...)
    for _, field in ipairs(fields) do
        panel[field] = saved[field]
    end
    if not ok then
        error(result)
    end
    for _, button in ipairs(panel.buttonList) do
        if button:getY() >= insertY then
            button:setY(button:getY() + row)
        end
    end
    for _, bar in ipairs(panel.progressBars) do
        if bar ~= panel.atfYogaBar then
            bar.atfNativeY = bar.atfNativeY or bar:getY()
            bar:setY(bar.atfNativeY >= insertY and bar.atfNativeY + row or bar.atfNativeY)
        end
    end
    local size = math.floor(row / 2)
    local x = 21 + row
    local barY = insertY + (row - size) / 2
    if not panel.atfYogaBar then
        panel.atfYogaBar = H.makeYogaBar(panel, x + 30 + panel.txtLen, barY)
        panel:addChild(panel.atfYogaBar)
        table.insert(panel.progressBars, insertIndex, panel.atfYogaBar)
    else
        panel.atfYogaBar:setY(barY)
    end
    panel:setStencilRect(0, 0, panel:getWidth(), panel:getHeight())
    -- Yoga has no native trait XP boost. Match ISCharacterInfo's unboosted
    -- skill-title tint; native titles retain that tint while the bar is hovered.
    panel:drawText(
        text("IGUI_perks_Yoga", "Yoga"),
        x + 20,
        insertY + 3,
        0.54,
        0.54,
        0.54,
        1,
        UIFont.Small
    )
    panel:clearStencilRect()
    return result
end

local function wellnessAction(player)
    local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
    for _, action in ipairs(queue) do
        if action.Type == "LSYogaAction" or action.Type == "LSMeditateAction" then
            return action
        end
    end
end

function H.canStart(ui, skill)
    if not H.enabled() then
        return false
    end
    local player = ui.player
    local option = ZenWellnessContextMenu.Options[skill]
    local data = player:getModData()
    if
        not data.LSMoodles
        or not data.LSMoodles.Embarrassed
        or not data.LSMoodles.Zen
        or not data.LSMoodles.WasTaughtSkill
        or not data.LSMoodles.MindfulState
        or player:isClimbing()
        or not ZenWellnessContextMenu.isValid(player)
    then
        return false, text("IGUI_ATFPatches_WellnessBusy", "Finish the current action first.")
    end
    if skill == "Yoga" and not option.isValid(player:isSitOnGround()) then
        return false, text("Tooltip_StandStillFitness", "Stand up first.")
    end
    local _, texture, tooltip = option.getOptionArgs()
    local unavailable, description = option.canPerform(player, tooltip, texture)
    return not unavailable, description
end

function H.dispatch(ui, skill)
    if not H.canStart(ui, skill) then
        return
    end
    local option = ZenWellnessContextMenu.Options[skill]
    if not option.isValid(ui.player:isSitOnGround()) then
        return
    end
    option.onAction({}, option, ui.player)
end

function H.clickWellness(ui, button)
    if ui.atfWellnessPending or not H.canStart(ui, button.atfSkill) then
        return
    end
    local player = ui.player
    if button.atfSkill == "Meditation" and not player:isSitOnGround() then
        ui.atfWellnessPending = {
            x = player:getX(),
            y = player:getY(),
            z = player:getZ(),
            deadline = getTimestampMs() + 8000,
        }
        player:reportEvent("EventSitOnGround")
    else
        H.dispatch(ui, button.atfSkill)
    end
end

function H.addControls(ui)
    if ui.atfYoga or not H.enabled() then
        return
    end
    -- Native initialise already resized this window. Java applies child anchors
    -- during onResize; a second setHeight before that overwrites the first delta.
    ui:recalcSize()
    local height = getTextManager():getFontHeight(UIFont.Small) + 6
    local y = ui.minusBtn:getBottom() + 10
    local x = ui.exercises.x
    local yogaTitle = text("IGUI_ATFPatches_DoYoga", "Do Yoga")
    local meditationTitle = text("ContextMenu_Meditate", "Meditate")
    local yogaWidth = math.max(100, getTextManager():MeasureStringX(UIFont.Small, yogaTitle) + 24)
    local meditationWidth =
        math.max(100, getTextManager():MeasureStringX(UIFont.Small, meditationTitle) + 24)
    local width = math.min(
        getCore():getScreenWidth() - 20,
        math.max(ui:getWidth(), x * 2 + yogaWidth + meditationWidth + 10)
    )
    ui:setWidth(width)
    ui:setX(math.max(0, math.min(ui:getX(), getCore():getScreenWidth() - width)))
    local available = width - x * 2
    local stacked = yogaWidth + meditationWidth + 10 > available
    local function add(skill, title)
        local buttonWidth = math.min(
            available,
            math.max(100, getTextManager():MeasureStringX(UIFont.Small, title) + 24)
        )
        local button = ISButton:new(x, y, buttonWidth, height, title, ui, function(target, clicked)
            ATFPatches_LifestyleHealth.clickWellness(target, clicked)
        end)
        button.atfSkill = skill
        button:initialise()
        button:instantiate()
        ui:addChild(button)
        x = x + buttonWidth + 10
        return button
    end
    ui.atfYoga = add("Yoga", yogaTitle)
    if stacked then
        x, y = ui.exercises.x, y + height + 10
    end
    ui.atfMeditate = add("Meditation", meditationTitle)
    ui:setHeight(ui:getHeight() + (height + 10) * (stacked and 2 or 1))
    ui:recalcSize()
    local footerY = ui:getHeight() - height - 11
    ui.ok:setY(footerY)
    ui.cancel:setY(footerY)
    ui.close:setY(footerY)
    ui.close:setX(ui:getWidth() - ui.close:getWidth() - 11)
    -- The new row precedes the native OK/Cancel/Close row for controller navigation.
    ui:insertNewLineOfButtons(ui.atfYoga, not stacked and ui.atfMeditate or nil)
    local rows = ui.joypadButtonsY
    local row = table.remove(rows)
    table.insert(rows, #rows, row)
    if stacked then
        ui:insertNewLineOfButtons(ui.atfMeditate)
        row = table.remove(rows)
        table.insert(rows, #rows, row)
    end
end

function H.fitnessInitialise(original, ui, ...)
    local result = original(ui, ...)
    H.addControls(ui)
    return result
end

function H.fitnessUpdate(original, ui, ...)
    local result = original(ui, ...)
    H.addControls(ui)
    local pending, player = ui.atfWellnessPending, ui.player
    if pending then
        if
            not ui:getIsVisible()
            or not H.enabled()
            or player:isDead()
            or player:isAiming()
            or player:isClimbing()
            or player:getVehicle()
            or player:isAsleep()
            or player:hasTimedActions()
            or getTimestampMs() > pending.deadline
            or math.abs(player:getX() - pending.x) > 0.1
            or math.abs(player:getY() - pending.y) > 0.1
            or player:getZ() ~= pending.z
        then
            ui.atfWellnessPending = nil
        elseif player:isSitOnGround() then
            ui.atfWellnessPending = nil
            H.dispatch(ui, "Meditation")
        end
    end
    return result
end

function H.fitnessButtons(original, ui, currentAction)
    local result = original(ui, currentAction)
    if ui.atfYoga then
        local enabled = H.enabled()
        ui.atfYoga:setVisible(not not enabled)
        ui.atfMeditate:setVisible(not not enabled)
        if enabled then
            for _, button in ipairs({ ui.atfYoga, ui.atfMeditate }) do
                local available, tooltip = H.canStart(ui, button.atfSkill)
                button:setEnable(available and not ui.atfWellnessPending)
                button.tooltip = (tooltip or "")
                    .. " <LINE> "
                    .. text("IGUI_ATFPatches_WellnessSession", "Uses Lifestyle's session length.")
            end
        end
    end
    if ui.atfWellnessPending or wellnessAction(ui.player) then
        ui.ok:setEnable(false)
        ui.cancel:setEnable(true)
    end
    return result
end

function H.fitnessClick(original, ui, button)
    if button.internal == "CLOSE" then
        ui.atfWellnessPending = nil
    end
    if button.internal == "CANCEL" and (ui.atfWellnessPending or wellnessAction(ui.player)) then
        ui.atfWellnessPending = nil
        -- clear stops the active action through its own stop() and removes any
        -- bag-removal preparation, preserving Lifestyle's XP penalty/hand cleanup.
        if wellnessAction(ui.player) then
            ISTimedActionQueue.clear(ui.player)
        end
        return
    end
    if button.internal == "OK" and (ui.atfWellnessPending or wellnessAction(ui.player)) then
        return
    end
    return original(ui, button)
end

function H.fitnessVisible(original, ui, visible)
    if not visible then
        ui.atfWellnessPending = nil
    end
    return original(ui, visible)
end

local function wrap(target, name, handler, key)
    local previous = H.wrappers[key]
    -- Another mod may wrap us after this file loads. Keep our existing layer in
    -- that chain; rewrapping at OnGameStart would add the Skills row twice.
    if previous and previous.target == target then
        return
    end
    local original = target[name]
    local wrapper = function(self, ...)
        return ATFPatches_LifestyleHealth[handler](original, self, ...)
    end
    H.wrappers[key] = { target = target, wrapper = wrapper }
    target[name] = wrapper
end

function H.install()
    if ISCharacterInfo and ISSkillProgressBar and ISPanel then
        wrap(ISCharacterInfo, "createChildren", "skillsChildren", "skillsChildren")
        wrap(ISCharacterInfo, "render", "skillsRender", "skillsRender")
    end
    if not ISFitnessUI then
        return
    end
    wrap(ISFitnessUI, "initialise", "fitnessInitialise", "fitnessInitialise")
    wrap(ISFitnessUI, "update", "fitnessUpdate", "fitnessUpdate")
    wrap(ISFitnessUI, "updateButtons", "fitnessButtons", "fitnessButtons")
    wrap(ISFitnessUI, "onClick", "fitnessClick", "fitnessClick")
    wrap(ISFitnessUI, "setVisible", "fitnessVisible", "fitnessVisible")
end

if not H.registered then
    H.registered = true
    Events.OnGameStart.Add(function()
        ATFPatches_LifestyleHealth.install()
    end)
end
H.install()
