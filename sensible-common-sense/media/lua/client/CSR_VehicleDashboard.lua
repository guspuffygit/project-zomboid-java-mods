require "CSR_FeatureFlags"
require "CSR_Theme"

-- Compatibility: Project Summer Car (3564950449) replaces the vanilla
-- ISVehicleDashboard with its own VehicleDashboardReplacer panel and adds
-- its own clock/temperature gauges. Our floating clock/HVAC/radio overlays
-- and gauge tinting all anchor to the vanilla dashboard, so when PSC is
-- active we step aside entirely and let PSC own the dashboard surface.
local PSC_ACTIVE = getActivatedMods and getActivatedMods():contains("ProjectSummerCar")

-- Keybind: toggle dashboard overlay visibility (default Numpad 3)
local DASH_TOGGLE_DEFAULT_KEY = Keyboard and Keyboard.KEY_NUMPAD3 or 81
local dashToggleKeyBind = nil
if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    local opts = PZAPI.ModOptions:create("CommonSenseRebornDashboard", "Common Sense Reborn - Dashboard")
    if opts and opts.addKeyBind then
        dashToggleKeyBind = opts:addKeyBind("toggleDashboardOverlay", "Toggle Dashboard Overlay", DASH_TOGGLE_DEFAULT_KEY)
    end
end

local function getDashToggleKey()
    if dashToggleKeyBind and dashToggleKeyBind.getValue then
        return dashToggleKeyBind:getValue()
    end
    return DASH_TOGGLE_DEFAULT_KEY
end

-- Persistent hidden state (survives entering/leaving vehicles within a session)
local _dashboardHidden = false

local function dynamicColor(amount, alpha)
    local accent
    if amount > 0.75 then
        accent = CSR_Theme.getColor("accentGreen")
    elseif amount > 0.50 then
        accent = CSR_Theme.getColor("accentAmber")
    elseif amount > 0.25 then
        accent = CSR_Theme.getColor("accentRed")
    elseif amount > 0.10 then
        accent = CSR_Theme.getColor("accentViolet")
    else
        accent = CSR_Theme.getColor("accentSlate")
    end
    return { r = accent.r, g = accent.g, b = accent.b, a = alpha }
end

local function patchVehicleDashboard()
    if PSC_ACTIVE then return end
    if not ISVehicleDashboard or ISVehicleDashboard.__csr_dashboard_patched then
        return
    end

    ISVehicleDashboard.__csr_dashboard_patched = true

    -- Track the active dashboard instance for clock positioning
    local activeDashboard = nil

    -- prerender: tint gauge background colors (modifies child properties before children draw)
    local originalPreRender = ISVehicleDashboard.prerender
    function ISVehicleDashboard:prerender(...)
        originalPreRender(self, ...)
        activeDashboard = self

        if CSR_FeatureFlags.isDashboardHighlightsEnabled()
            and self.vehicle
            and (self.vehicle:isKeysInIgnition() or self.vehicle:isHotwired())
            and self.vehicle:isEngineRunning() then

            local alpha = self:getAlphaFlick(0.65)
            self.batteryTex.backgroundColor = dynamicColor(self.vehicle:getBatteryCharge(), alpha)

            -- Perf: cache engine/heater VehiclePart refs per-vehicle to avoid
            -- two getPartById() Java calls every frame. Invalidate on vehicle swap.
            if self._csrPartVehicle ~= self.vehicle then
                self._csrPartVehicle = self.vehicle
                self._csrEnginePart = self.vehicle:getPartById("Engine")
                self._csrHeaterPart = self.vehicle:getPartById("Heater")
            end

            local engine = self._csrEnginePart
            if engine then
                self.engineTex.backgroundColor = dynamicColor(engine:getCondition() / 100, alpha)
            end

            local heater = self._csrHeaterPart
            if heater and heater:getModData().active then
                self.heaterTex.backgroundColor = dynamicColor(heater:getCondition() / 100, alpha)
            end
        end
    end

    -- ==========================================
    -- Standalone clock panel — floats above the dashboard
    -- ==========================================
    local clockModuleTex = getTexture("media/textures/CSR_ClockModule.png")
    local CLOCK_W = clockModuleTex and clockModuleTex:getWidth() or 120
    local CLOCK_H = clockModuleTex and clockModuleTex:getHeight() or 80

    -- LCD window bounds within the bezel (percentages of texture size)
    local LCD_LEFT   = 0.14
    local LCD_RIGHT  = 0.86
    local LCD_TOP    = 0.30
    local LCD_BOTTOM = 0.65

    local CSR_VehicleClock = ISPanel:derive("CSR_VehicleClock")

    function CSR_VehicleClock:createChildren()
        ISPanel.createChildren(self)
        self.background = false
        self.border = false
    end

    function CSR_VehicleClock:prerender()
        self.background = false
        self.border = false
        ISPanel.prerender(self)

        -- Anchor above the dashboard each frame
        local ui = activeDashboard
        if ui then
            local dx = ui:getAbsoluteX() + ui:getWidth() - CLOCK_W - 4
            local dy = ui:getAbsoluteY() - CLOCK_H - 4
            if math.abs(self:getAbsoluteX() - dx) > 1 or math.abs(self:getAbsoluteY() - dy) > 1 then
                self:setX(dx)
                self:setY(dy)
            end
        end
    end

    function CSR_VehicleClock:render()
        ISPanel.render(self)

        local player = getSpecificPlayer(0)
        if not player then return end
        local vehicle = player:getVehicle()
        if not vehicle then return end

        local running = vehicle:isEngineRunning()
        local a = running and 1.0 or 0.45

        -- Draw bezel texture
        if clockModuleTex then
            self:drawTexture(clockModuleTex, 0, 0, a, 1, 1, 1)
        end

        -- Build time string
        local tod = getGameTime():getTimeOfDay()
        local h = math.floor(tod) % 24
        local m = math.floor((tod - math.floor(tod)) * 60)
        local clockStr = string.format("%d:%02d", (h % 12 == 0) and 12 or (h % 12), m)
        local ampm = h < 12 and " AM" or " PM"
        local display = clockStr .. ampm

        -- Bright green LCD text, centered in the LCD window
        local cr, cg, cb = 0.4, 1.0, 0.4
        if running then
            cr, cg, cb = 0.5, 1.0, 0.5
        end

        local lcdX = CLOCK_W * LCD_LEFT
        local lcdW = CLOCK_W * (LCD_RIGHT - LCD_LEFT)
        local lcdY = CLOCK_H * LCD_TOP
        local lcdH = CLOCK_H * (LCD_BOTTOM - LCD_TOP)

        local textW = getTextManager():MeasureStringX(UIFont.Small, display)
        local textH = getTextManager():MeasureStringY(UIFont.Small, display)
        local cx = lcdX + (lcdW - textW) / 2
        local cy = lcdY + (lcdH - textH) / 2

        self:drawText(display, cx, cy, cr, cg, cb, a, UIFont.Small)
    end

    function CSR_VehicleClock:new()
        local o = ISPanel:new(0, 0, CLOCK_W, CLOCK_H)
        setmetatable(o, self)
        self.__index = self
        o.moveWithMouse = false
        o.background = false
        o.border = false
        o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        return o
    end

    -- ==========================================
    -- HVAC temperature gauge — floats below the clock
    -- ==========================================

    -- Forward-declare panel references (assigned later by show/hide functions)
    local csrClockPanel = nil
    local csrHVACPanel  = nil

    -- Independent drag offsets per panel (saved to player moddata)
    local _hvacOffsetX = 0
    local _hvacOffsetY = 0
    local _radioOffsetX = 0
    local _radioOffsetY = 0
    local _offsetsLoaded = false

    -- HVAC drag state
    local _hvacDragging = false
    local _hvacDragStartMX = 0
    local _hvacDragStartMY = 0
    local _hvacDragStartOX = 0
    local _hvacDragStartOY = 0

    local function savePanelOffsets()
        local player = getSpecificPlayer(0)
        if not player then return end
        local md = player:getModData()
        md.csrHvacOffsetX = _hvacOffsetX
        md.csrHvacOffsetY = _hvacOffsetY
        md.csrRadioOffsetX = _radioOffsetX
        md.csrRadioOffsetY = _radioOffsetY
    end

    local function loadPanelOffsets()
        local player = getSpecificPlayer(0)
        if not player then return end
        local md = player:getModData()
        if md.csrHvacOffsetX then
            _hvacOffsetX = md.csrHvacOffsetX
            _hvacOffsetY = md.csrHvacOffsetY
        end
        if md.csrRadioOffsetX then
            _radioOffsetX = md.csrRadioOffsetX
            _radioOffsetY = md.csrRadioOffsetY
        end
        _offsetsLoaded = true
    end

    local gaugeTex  = getTexture("media/textures/CSR_HVACGauge.png")
    local sliderTex = getTexture("media/textures/CSR_HVACSlider.png")
    local GAUGE_W  = gaugeTex  and gaugeTex:getWidth()  or 140
    local GAUGE_H  = gaugeTex  and gaugeTex:getHeight() or 18
    local SLIDER_W = sliderTex and sliderTex:getWidth()  or 14
    local SLIDER_H = sliderTex and sliderTex:getHeight() or 22

    local function getDefaultHVACPos()
        -- Use activeDashboard directly to avoid prerender-order jitter caused by
        -- reading csrClockPanel which may not have repositioned yet this frame.
        if activeDashboard then
            return activeDashboard:getAbsoluteX() + activeDashboard:getWidth() - CLOCK_W / 2 - 4,
                   activeDashboard:getAbsoluteY()
        elseif csrClockPanel then
            return csrClockPanel:getAbsoluteX() + csrClockPanel:getWidth() / 2,
                   csrClockPanel:getAbsoluteY() + CLOCK_H + 4
        end
        return getCore():getScreenWidth() / 2, getCore():getScreenHeight() / 2
    end

    -- Discrete temperature stops matching vanilla ISVehicleACUI knob values
    local TEMP_STOPS = { -25, -15, -8, 0, 8, 15, 25 }

    -- Slideable region within gauge (fraction of gauge width)
    local SLIDE_LEFT  = 0.13
    local SLIDE_RIGHT = 0.87

    local function tempToFraction(temp)
        -- Map temp from TEMP_STOPS range to 0..1
        for i, t in ipairs(TEMP_STOPS) do
            if temp <= t then
                if i == 1 then return 0 end
                local prev = TEMP_STOPS[i - 1]
                return (i - 2 + (temp - prev) / (t - prev)) / (#TEMP_STOPS - 1)
            end
        end
        return 1
    end

    local function fractionToTemp(frac)
        -- Snap to nearest discrete stop
        local idx = math.floor(frac * (#TEMP_STOPS - 1) + 0.5) + 1
        idx = math.max(1, math.min(#TEMP_STOPS, idx))
        return TEMP_STOPS[idx]
    end

    local CSR_VehicleHVAC = ISPanel:derive("CSR_VehicleHVAC")

    function CSR_VehicleHVAC:createChildren()
        ISPanel.createChildren(self)
        self.background = false
        self.border = false
    end

    function CSR_VehicleHVAC:prerender()
        self.background = false
        self.border = false
        ISPanel.prerender(self)

        if _hvacDragging then
            local mx = getMouseX()
            local my = getMouseY()
            _hvacOffsetX = _hvacDragStartOX + (mx - _hvacDragStartMX)
            _hvacOffsetY = _hvacDragStartOY + (my - _hvacDragStartMY)
        end

        local baseX, baseY = getDefaultHVACPos()
        local dx = baseX + _hvacOffsetX
        local dy = baseY + _hvacOffsetY
        if math.abs(self:getAbsoluteX() - dx) > 1 or math.abs(self:getAbsoluteY() - dy) > 1 then
            self:setX(dx)
            self:setY(dy)
        end
    end

    function CSR_VehicleHVAC:onRightMouseDown(x, y)
        _hvacDragging = true
        _hvacDragStartMX = self:getAbsoluteX() + x
        _hvacDragStartMY = self:getAbsoluteY() + y
        _hvacDragStartOX = _hvacOffsetX
        _hvacDragStartOY = _hvacOffsetY
        return true
    end

    function CSR_VehicleHVAC:onRightMouseUp(x, y)
        if _hvacDragging then
            _hvacDragging = false
            savePanelOffsets()
        end
        return true
    end

    function CSR_VehicleHVAC:onRightMouseUpOutside(x, y)
        if _hvacDragging then
            _hvacDragging = false
            savePanelOffsets()
        end
    end

    function CSR_VehicleHVAC:render()
        ISPanel.render(self)

        local player = getSpecificPlayer(0)
        if not player then return end
        local vehicle = player:getVehicle()
        if not vehicle then return end

        local heater = vehicle:getPartById("Heater")
        if not heater then return end

        local running = vehicle:isEngineRunning()
        local a = running and 1.0 or 0.35

        -- Draw gauge background
        if gaugeTex then
            self:drawTexture(gaugeTex, 0, (self.height - GAUGE_H) / 2, a, 1, 1, 1)
        end

        -- Get current temperature setting
        local md = heater:getModData()
        local temp = md.temperature or 0
        local active = md.active or false

        -- Calculate slider X position
        local frac = tempToFraction(temp)
        local slideW = GAUGE_W * (SLIDE_RIGHT - SLIDE_LEFT)
        local slideStartX = GAUGE_W * SLIDE_LEFT
        local sliderX = slideStartX + frac * slideW - SLIDER_W / 2
        local sliderY = (self.height - SLIDER_H) / 2

        -- Draw slider knob
        if sliderTex then
            local sa = a
            if active and running then sa = 1.0 end
            self:drawTexture(sliderTex, sliderX, sliderY, sa, 1, 1, 1)
        end

        -- Draw "OFF" text when heater is inactive and engine running
        if running and not active then
            local offStr = "OFF"
            local tw = getTextManager():MeasureStringX(UIFont.Small, offStr)
            self:drawText(offStr, (GAUGE_W - tw) / 2, GAUGE_H + 1, 0.6, 0.6, 0.6, 0.7, UIFont.Small)
        elseif running and active then
            local label
            if temp > 0 then
                label = "HEAT"
            elseif temp < 0 then
                label = "A/C"
            else
                label = "FAN"
            end
            local tw = getTextManager():MeasureStringX(UIFont.Small, label)
            local cr, cg, cb = 0.6, 0.6, 0.6
            if temp > 0 then cr, cg, cb = 1.0, 0.5, 0.3
            elseif temp < 0 then cr, cg, cb = 0.3, 0.7, 1.0
            end
            self:drawText(label, (GAUGE_W - tw) / 2, GAUGE_H + 1, cr, cg, cb, 0.8, UIFont.Small)
        end
    end

    function CSR_VehicleHVAC:getSliderFracFromMouse(x)
        local slideStartX = GAUGE_W * SLIDE_LEFT
        local slideW = GAUGE_W * (SLIDE_RIGHT - SLIDE_LEFT)
        local frac = (x - slideStartX) / slideW
        return math.max(0, math.min(1, frac))
    end

    function CSR_VehicleHVAC:applyTemp(frac)
        local player = getSpecificPlayer(0)
        if not player then return end
        local vehicle = player:getVehicle()
        if not vehicle then return end
        if not vehicle:isEngineRunning() and not vehicle:isKeysInIgnition() then return end

        local heater = vehicle:getPartById("Heater")
        if not heater then return end

        local temp = fractionToTemp(frac)
        local active = temp ~= 0

        getSoundManager():playUISound("VehicleACSetTemperature")
        sendClientCommand(player, 'vehicle', 'toggleHeater', { on = active, temp = temp })
    end

    function CSR_VehicleHVAC:onMouseDown(x, y)
        local player = getSpecificPlayer(0)
        if not player then return true end
        local vehicle = player:getVehicle()
        if not vehicle or (not vehicle:isEngineRunning() and not vehicle:isKeysInIgnition()) then return true end

        self.dragging = true
        local frac = self:getSliderFracFromMouse(x)
        self:applyTemp(frac)
        return true
    end

    function CSR_VehicleHVAC:onMouseMove(dx, dy)
        if self.dragging then
            local mx = self:getMouseX()
            local frac = self:getSliderFracFromMouse(mx)
            self:applyTemp(frac)
        end
    end

    function CSR_VehicleHVAC:onMouseMoveOutside(dx, dy)
        if self.dragging then
            local mx = self:getMouseX()
            local frac = self:getSliderFracFromMouse(mx)
            self:applyTemp(frac)
        end
    end

    function CSR_VehicleHVAC:onMouseUp(x, y)
        self.dragging = false
        return true
    end

    function CSR_VehicleHVAC:onMouseUpOutside(x, y)
        self.dragging = false
    end

    function CSR_VehicleHVAC:new()
        -- Height includes space for label text below gauge
        local panelH = SLIDER_H + 16
        local o = ISPanel:new(0, 0, GAUGE_W, panelH)
        setmetatable(o, self)
        self.__index = self
        o.moveWithMouse = false
        o.dragging = false
        o.background = false
        o.border = false
        o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        return o
    end

    local function hideHVACPanel()
        if csrHVACPanel then
            savePanelOffsets()  -- persist position before removing
            csrHVACPanel:removeFromUIManager()
            csrHVACPanel = nil
        end
    end

    local function showHVACPanel()
        if not CSR_FeatureFlags.isVehicleHVACEnabled() then return end
        if _dashboardHidden then return end
        if csrHVACPanel then return end
        local player = getSpecificPlayer(0)
        if not player then return end
        local vehicle = player:getVehicle()
        if not vehicle or not vehicle:getPartById("Heater") then return end
        if not _offsetsLoaded then loadPanelOffsets() end
        csrHVACPanel = CSR_VehicleHVAC:new()
        csrHVACPanel:addToUIManager()
        csrHVACPanel:setVisible(true)
    end

    -- Suppress vanilla heater popup when HVAC panel is active
    local _origOnClickHeater = ISVehicleDashboard.onClickHeater
    function ISVehicleDashboard:onClickHeater()
        if CSR_FeatureFlags.isVehicleHVACEnabled() and csrHVACPanel then
            -- Toggle heater on/off at current temperature instead of opening popup
            local player = self.character or getSpecificPlayer(0)
            if not player then return end
            local vehicle = player:getVehicle()
            if not vehicle then return end
            local heater = vehicle:getPartById("Heater")
            if not heater then return end
            if not vehicle:isEngineRunning() and not vehicle:isKeysInIgnition() then return end
            local md = heater:getModData()
            local temp = md.temperature or 0
            if temp == 0 then temp = 8 end  -- default to low heat when toggling on
            getSoundManager():playUISound("VehicleACButton")
            sendClientCommand(player, 'vehicle', 'toggleHeater', { on = not md.active, temp = temp })
            return
        end
        if _origOnClickHeater then _origOnClickHeater(self) end
    end

    local _origToggleHeater = ISVehicleMenu.onToggleHeater
    ISVehicleMenu.onToggleHeater = function(playerObj)
        if CSR_FeatureFlags.isVehicleHVACEnabled() then
            -- Toggle on/off without opening popup
            local vehicle = playerObj:getVehicle()
            if not vehicle then return end
            local heater = vehicle:getPartById("Heater")
            if not heater then return end
            if not vehicle:isEngineRunning() and not vehicle:isKeysInIgnition() then return end
            local md = heater:getModData()
            local temp = md.temperature or 0
            if temp == 0 then temp = 8 end
            playerObj:playSound("VehicleACButton")
            sendClientCommand(playerObj, 'vehicle', 'toggleHeater', { on = not md.active, temp = temp })
            return
        end
        if _origToggleHeater then _origToggleHeater(playerObj) end
    end

    -- Show/hide clock panel when entering/leaving vehicles

    -- ==========================================
    -- Radio panel — floats below the HVAC gauge
    -- ==========================================
    local csrRadioPanel = nil
    local radioBodyTex = getTexture("media/textures/CSR_RadioBody.png")
    local radioKnobTex = getTexture("media/textures/CSR_RadioKnob.png")

    -- Panel size matches texture (140x62, same width as HVAC gauge)
    local RADIO_W = radioBodyTex and radioBodyTex:getWidth() or 140
    local RADIO_H = radioBodyTex and radioBodyTex:getHeight() or 62
    local KNOB_SZ = radioKnobTex and radioKnobTex:getWidth() or 16

    -- Stretched draw dimensions (wider for LCD legibility, knobs bigger than holes)
    local RADIO_DRAW_W = 185
    local RADIO_DRAW_H = 72
    local KNOB_DRAW_SZ = 22

    -- Radio drag state (declared here so getDefaultRadioPos can use RADIO_DRAW_W)
    local _radioDragging = false
    local _radioDragStartMX = 0
    local _radioDragStartMY = 0
    local _radioDragStartOX = 0
    local _radioDragStartOY = 0

    local function getDefaultRadioPos()
        -- Use activeDashboard directly to avoid prerender-order jitter caused by
        -- reading csrClockPanel which may not have repositioned yet this frame.
        if activeDashboard then
            return activeDashboard:getAbsoluteX() + activeDashboard:getWidth() - CLOCK_W / 2 - 4 - RADIO_DRAW_W / 2,
                   activeDashboard:getAbsoluteY() + 24
        elseif csrClockPanel then
            local cx = csrClockPanel:getAbsoluteX() + csrClockPanel:getWidth() / 2
            return cx - RADIO_DRAW_W / 2,
                   csrClockPanel:getAbsoluteY() + CLOCK_H + 28
        end
        return getCore():getScreenWidth() / 2, getCore():getScreenHeight() / 2
    end

    -- Knob hole centers as fractions (from transparent-pixel analysis of 140x62 image)
    -- VOL knob: upper-left hole, center at pixel (16, 16)
    local VOL_KNOB_CX = 0.113
    local VOL_KNOB_CY = 0.258
    -- TUNE knob: upper-right hole, center at pixel (123, 16)
    local TUNE_KNOB_CX = 0.877
    local TUNE_KNOB_CY = 0.258

    -- LCD display area fractions (green screen: x=35-104, y=6-30 in 140x62 image)
    local LCD_RX1 = 0.250
    local LCD_RX2 = 0.743
    local LCD_RY1 = 0.097
    local LCD_RY2 = 0.484

    local CSR_VehicleRadio = ISPanel:derive("CSR_VehicleRadio")

    function CSR_VehicleRadio:createChildren()
        ISPanel.createChildren(self)
        self.background = false
        self.border = false
    end

    function CSR_VehicleRadio:prerender()
        self.background = false
        self.border = false
        ISPanel.prerender(self)

        if _radioDragging then
            local mx = getMouseX()
            local my = getMouseY()
            _radioOffsetX = _radioDragStartOX + (mx - _radioDragStartMX)
            _radioOffsetY = _radioDragStartOY + (my - _radioDragStartMY)
        end

        local baseX, baseY = getDefaultRadioPos()
        local dx = baseX + _radioOffsetX
        local dy = baseY + _radioOffsetY
        if math.abs(self:getAbsoluteX() - dx) > 1 or math.abs(self:getAbsoluteY() - dy) > 1 then
            self:setX(dx)
            self:setY(dy)
        end
    end

    local function getRadioDevice()
        local player = getSpecificPlayer(0)
        if not player then return nil, nil, nil end
        local vehicle = player:getVehicle()
        if not vehicle then return nil, nil, nil end
        local radio = vehicle:getPartById("Radio")
        if not radio or not radio:getInventoryItem() then return nil, nil, nil end
        local dd = radio:getDeviceData()
        if not dd then return nil, nil, nil end
        return player, radio, dd
    end

    function CSR_VehicleRadio:render()
        ISPanel.render(self)

        local player, radio, dd = getRadioDevice()
        if not radio then return end

        local isOn = dd:getIsTurnedOn()
        local a = isOn and 1.0 or 0.5

        -- Draw radio body
        if radioBodyTex then
            self:drawTextureScaled(radioBodyTex, 0, 0, RADIO_DRAW_W, RADIO_DRAW_H, a, 1, 1, 1)
        end

        -- Draw volume knob in left hole
        if radioKnobTex then
            local volKx = RADIO_DRAW_W * VOL_KNOB_CX - KNOB_DRAW_SZ / 2
            local volKy = RADIO_DRAW_H * VOL_KNOB_CY - KNOB_DRAW_SZ / 2
            self:drawTextureScaled(radioKnobTex, volKx, volKy, KNOB_DRAW_SZ, KNOB_DRAW_SZ, a, 1, 1, 1)

            -- Draw rotation indicator dot on vol knob
            if isOn then
                local vol = dd:getDeviceVolume()
                local angle = -2.4 + vol * 4.8
                local cx = RADIO_DRAW_W * VOL_KNOB_CX
                local cy = RADIO_DRAW_H * VOL_KNOB_CY
                local lineLen = KNOB_DRAW_SZ * 0.35
                local lx = cx + math.sin(angle) * lineLen
                local ly = cy - math.cos(angle) * lineLen
                self:drawRect(lx - 1, ly - 1, 3, 3, 0.9, 0.8, 0.8, 0.8)
            end

            -- Draw tuning knob in right hole
            local tuneKx = RADIO_DRAW_W * TUNE_KNOB_CX - KNOB_DRAW_SZ / 2
            local tuneKy = RADIO_DRAW_H * TUNE_KNOB_CY - KNOB_DRAW_SZ / 2
            self:drawTextureScaled(radioKnobTex, tuneKx, tuneKy, KNOB_DRAW_SZ, KNOB_DRAW_SZ, a, 1, 1, 1)

            -- Draw rotation indicator dot on tune knob
            if isOn then
                local minFreq = dd:getMinChannelRange()
                local maxFreq = dd:getMaxChannelRange()
                local curFreq = dd:getChannel()
                local tuneFrac = 0.5
                if maxFreq > minFreq then
                    tuneFrac = (curFreq - minFreq) / (maxFreq - minFreq)
                end
                local angle = -2.4 + tuneFrac * 4.8
                local cx = RADIO_DRAW_W * TUNE_KNOB_CX
                local cy = RADIO_DRAW_H * TUNE_KNOB_CY
                local lineLen = KNOB_DRAW_SZ * 0.35
                local lx = cx + math.sin(angle) * lineLen
                local ly = cy - math.cos(angle) * lineLen
                self:drawRect(lx - 1, ly - 1, 3, 3, 0.9, 0.8, 0.8, 0.8)
            end
        end

        -- Draw LCD display content on the green screen area
        if isOn then
            local lcdX = RADIO_DRAW_W * LCD_RX1
            local lcdW = RADIO_DRAW_W * (LCD_RX2 - LCD_RX1)
            local lcdY = RADIO_DRAW_H * LCD_RY1
            local lcdH = RADIO_DRAW_H * (LCD_RY2 - LCD_RY1)

            local freqStr = string.format("%.1f MHz", dd:getChannel() / 1000)

            -- Draw frequency centered in LCD
            local font = UIFont.NewSmall
            local freqW = getTextManager():MeasureStringX(font, freqStr)
            local freqH = getTextManager():MeasureStringY(font, freqStr)
            self:drawText(freqStr, lcdX + (lcdW - freqW) / 2, lcdY, 0.1, 0.4, 0.1, 0.9, font)

            -- Draw station name below freq if there's room
            local zomboidRadio = getZomboidRadio()
            local channelName = ""
            if zomboidRadio then
                channelName = zomboidRadio:getChannelName(dd:getChannel()) or ""
            end
            if channelName ~= "" then
                local displayName = channelName
                local nameW = getTextManager():MeasureStringX(font, displayName)
                if nameW > lcdW - 4 then
                    while #displayName > 1 and getTextManager():MeasureStringX(font, displayName .. "..") > lcdW - 4 do
                        displayName = displayName:sub(1, #displayName - 1)
                    end
                    displayName = displayName .. ".."
                    nameW = getTextManager():MeasureStringX(font, displayName)
                end
                self:drawText(displayName, lcdX + (lcdW - nameW) / 2, lcdY + freqH - 2, 0.1, 0.35, 0.1, 0.7, font)
            end
        end
    end

    -- Volume knob: drag to change volume, click (no drag) to toggle power
    function CSR_VehicleRadio:isInVolKnob(x, y)
        local cx = RADIO_DRAW_W * VOL_KNOB_CX
        local cy = RADIO_DRAW_H * VOL_KNOB_CY
        local dist = math.sqrt((x - cx)^2 + (y - cy)^2)
        return dist <= KNOB_DRAW_SZ * 0.6
    end

    -- Tune knob: drag to change frequency
    function CSR_VehicleRadio:isInTuneKnob(x, y)
        local cx = RADIO_DRAW_W * TUNE_KNOB_CX
        local cy = RADIO_DRAW_H * TUNE_KNOB_CY
        local dist = math.sqrt((x - cx)^2 + (y - cy)^2)
        return dist <= KNOB_DRAW_SZ * 0.6
    end

    function CSR_VehicleRadio:onRightMouseDown(x, y)
        _radioDragging = true
        _radioDragStartMX = self:getAbsoluteX() + x
        _radioDragStartMY = self:getAbsoluteY() + y
        _radioDragStartOX = _radioOffsetX
        _radioDragStartOY = _radioOffsetY
        return true
    end

    function CSR_VehicleRadio:onRightMouseUp(x, y)
        if _radioDragging then
            _radioDragging = false
            savePanelOffsets()
        end
        return true
    end

    function CSR_VehicleRadio:onRightMouseUpOutside(x, y)
        if _radioDragging then
            _radioDragging = false
            savePanelOffsets()
        end
    end

    function CSR_VehicleRadio:onMouseDown(x, y)
        local player, radio, dd = getRadioDevice()
        if not dd then return true end

        if self:isInVolKnob(x, y) then
            self.draggingVol = true
            self.dragStartY = y
            self.dragStartVal = dd:getDeviceVolume()
            self.dragMoved = false
            return true
        end

        if self:isInTuneKnob(x, y) then
            if not dd:getIsTurnedOn() then return true end
            self.draggingTune = true
            self.dragStartY = y
            self.dragStartFreq = dd:getChannel()
            return true
        end

        return true
    end

    function CSR_VehicleRadio:onMouseMove(dx, dy)
        local player, radio, dd = getRadioDevice()
        if not dd then return end

        if self.draggingVol then
            self.dragMoved = true
            if not dd:getIsTurnedOn() then return end
            local deltaY = self.dragStartY - self:getMouseY()
            local newVol = self.dragStartVal + deltaY / 60.0
            newVol = math.max(0, math.min(1, newVol))
            dd:setDeviceVolume(newVol)
        end

        if self.draggingTune then
            if not dd:getIsTurnedOn() then return end
            local deltaY = self.dragStartY - self:getMouseY()
            local minF = dd:getMinChannelRange()
            local maxF = dd:getMaxChannelRange()
            local range = maxF - minF
            local step = range / 100
            local newFreq = self.dragStartFreq + deltaY * step
            newFreq = math.max(minF, math.min(maxF, newFreq))
            -- Snap to nearest 200 (0.2 MHz steps like vanilla)
            newFreq = math.floor(newFreq / 200 + 0.5) * 200
            if newFreq ~= dd:getChannel() then
                dd:setChannel(newFreq)
                dd:playSoundSend("VehicleRadioTuneIn", false)
            end
        end
    end

    function CSR_VehicleRadio:onMouseMoveOutside(dx, dy)
        self:onMouseMove(dx, dy)
    end

    function CSR_VehicleRadio:onMouseUp(x, y)
        local player, radio, dd = getRadioDevice()

        if self.draggingVol then
            self.draggingVol = false
            -- If barely moved, toggle power
            if not self.dragMoved then
                if dd then
                    if dd:getIsTurnedOn() then
                        dd:setIsTurnedOn(false)
                        dd:playSoundSend("VehicleRadioButton", false)
                    else
                        local canPower = dd:getPower() > 0 or dd:canBePoweredHere()
                        if canPower then
                            dd:setIsTurnedOn(true)
                            dd:playSoundSend("VehicleRadioButton", false)
                        end
                    end
                end
            end
            self.dragMoved = false
            return true
        end

        if self.draggingTune then
            self.draggingTune = false
            return true
        end

        return true
    end

    function CSR_VehicleRadio:onMouseUpOutside(x, y)
        self.draggingVol = false
        self.draggingTune = false
        self.dragMoved = false
    end

    function CSR_VehicleRadio:onMouseWheel(del)
        local player, radio, dd = getRadioDevice()
        if not dd or not dd:getIsTurnedOn() then return true end

        local mx = self:getMouseX()
        local my = self:getMouseY()

        if self:isInVolKnob(mx, my) then
            local vol = dd:getDeviceVolume()
            vol = vol - del * 0.05
            vol = math.max(0, math.min(1, vol))
            dd:setDeviceVolume(vol)
            return true
        end

        if self:isInTuneKnob(mx, my) then
            local minF = dd:getMinChannelRange()
            local maxF = dd:getMaxChannelRange()
            local freq = dd:getChannel()
            freq = freq - del * 200  -- 0.2 MHz per notch
            freq = math.max(minF, math.min(maxF, freq))
            if freq ~= dd:getChannel() then
                dd:setChannel(freq)
                dd:playSoundSend("VehicleRadioTuneIn", false)
            end
            return true
        end

        return true
    end

    function CSR_VehicleRadio:new()
        local o = ISPanel:new(0, 0, RADIO_DRAW_W, RADIO_DRAW_H)
        setmetatable(o, self)
        self.__index = self
        o.moveWithMouse = false
        o.background = false
        o.border = false
        o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
        o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
        o.draggingVol = false
        o.draggingTune = false
        o.dragMoved = false
        return o
    end

    local function hideRadioPanel()
        if csrRadioPanel then
            savePanelOffsets()  -- persist position before removing
            csrRadioPanel:removeFromUIManager()
            csrRadioPanel = nil
        end
    end

    local function showRadioPanel()
        if not CSR_FeatureFlags.isVehicleRadioEnabled() then return end
        if _dashboardHidden then return end
        if csrRadioPanel then return end
        local player = getSpecificPlayer(0)
        if not player then return end
        local vehicle = player:getVehicle()
        if not vehicle then return end
        local radio = vehicle:getPartById("Radio")
        if not radio or not radio:getInventoryItem() then return end
        if not _offsetsLoaded then loadPanelOffsets() end
        csrRadioPanel = CSR_VehicleRadio:new()
        csrRadioPanel:addToUIManager()
        csrRadioPanel:setVisible(true)
    end

    -- Suppress vanilla radio popup when radio panel is active
    local _origOnClickRadio = ISVehicleDashboard.onClickRadio
    function ISVehicleDashboard:onClickRadio()
        if CSR_FeatureFlags.isVehicleRadioEnabled() and csrRadioPanel then
            -- Toggle power via dashboard icon click
            local player, radio, dd = getRadioDevice()
            if not dd then return end
            if dd:getIsTurnedOn() then
                dd:setIsTurnedOn(false)
                dd:playSoundSend("VehicleRadioButton", false)
            else
                local canPower = dd:getPower() > 0 or dd:canBePoweredHere()
                if canPower then
                    dd:setIsTurnedOn(true)
                    dd:playSoundSend("VehicleRadioButton", false)
                end
            end
            return
        end
        if _origOnClickRadio then _origOnClickRadio(self) end
    end

    local function showClockPanel()
        if not CSR_FeatureFlags.isVehicleClockEnabled() then return end
        if _dashboardHidden then return end
        if csrClockPanel then return end
        csrClockPanel = CSR_VehicleClock:new()
        csrClockPanel:addToUIManager()
        csrClockPanel:setVisible(true)
    end

    local function hideClockPanel()
        if csrClockPanel then
            csrClockPanel:removeFromUIManager()
            csrClockPanel = nil
        end
    end

    local function onPlayerUpdate(player)
        if player:getPlayerNum() ~= 0 then return end
        if player:getVehicle() then
            showClockPanel()
            showHVACPanel()
            showRadioPanel()
        else
            hideClockPanel()
            hideHVACPanel()
            hideRadioPanel()
        end
    end

    Events.OnPlayerUpdate.Add(onPlayerUpdate)

    local function onDashKeyPressed(key)
        if key ~= getDashToggleKey() then return end
        local player = getSpecificPlayer(0)
        if not player or not player:getVehicle() then return end
        _dashboardHidden = not _dashboardHidden
        if _dashboardHidden then
            hideClockPanel()
            hideHVACPanel()
            hideRadioPanel()
        else
            showClockPanel()
            showHVACPanel()
            showRadioPanel()
        end
    end

    Events.OnKeyPressed.Add(onDashKeyPressed)
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchVehicleDashboard)
end

return {}
