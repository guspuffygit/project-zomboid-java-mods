require("AdminDiagnostics/Recorder")
require("ISUI/ISModalDialog")
require("ISUI/ISButton")
require("ISUI/AdminPanel/ISAdminPanelUI")
local D = AdminDiagnostics
if D.controlsInstalled then
    return
end
D.controlsInstalled = true
local function notice(text)
    local p = getPlayer()
    if p then
        p:setHaloNote(text, 220, 240, 255, 300)
    end
end
function D.toggle()
    if D.enabled then
        D.stop()
        notice("Admin diagnostics stopped.")
    elseif D.start() then
        notice("Admin diagnostics recording. Ctrl+Shift+F11 marks an incident.")
    end
end
function D.manualMark()
    if not D.allowed() then
        return
    end
    if not D.enabled then
        notice("Start diagnostics first: Ctrl+Shift+F10.")
        return
    end
    D.mark()
    notice("Diagnostic incident marked; recording the next 20 seconds.")
end
function D.showStatus()
    if not D.allowed() then
        return
    end
    local text = "Admin diagnostics: "
        .. (D.enabled and "RECORDING" or "OFF")
        .. "\nCtrl+Shift+F10: start / stop. Ctrl+Shift+F11: mark a visible failure."
        .. "\nLocal logs: Zomboid/Lua/admin-diag-1.log through admin-diag-4.log."
        .. "\nJVM helper: "
        .. (AdminDiagnosticsProbe and "available" or "unavailable; use Windows memory monitor")
        .. "\nTwo-second samples; 60 seconds of history; 20 seconds after incidents."
        .. "\nLoaded counts are not proof of rendering. Manual marking is useful when the UI disappears."
    local panel = ISModalDialog:new(0, 0, 620, 250, text, false, nil, nil)
    panel:initialise()
    panel:addToUIManager()
end
Events.OnKeyPressed.Add(function(key)
    if key ~= Keyboard.KEY_F10 and key ~= Keyboard.KEY_F11 then
        return
    end
    if not isCtrlKeyDown() or not isShiftKeyDown() or not D.allowed() then
        return
    end
    if key == Keyboard.KEY_F10 then
        D.toggle()
    else
        D.manualMark()
    end
end)
Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context)
    if not D.allowed() or not getPlayer() or playerIndex ~= getPlayer():getPlayerNum() then
        return
    end
    context:addOption(
        D.enabled and "Stop admin diagnostics" or "Start admin diagnostics",
        nil,
        D.toggle
    )
    if D.enabled then
        context:addOption("Mark diagnostic incident", nil, D.manualMark)
    end
    context:addOption("Admin diagnostics status / help", nil, D.showStatus)
end)
Events.OnGameStart.Add(function()
    if AdminCore and AdminCore.registerAction then
        for _, item in ipairs({
            { "diagnostics.toggle", "Start / stop admin diagnostics", D.toggle },
            { "diagnostics.mark", "Mark diagnostic incident", D.manualMark },
            { "diagnostics.status", "Admin diagnostics status / help", D.showStatus },
        }) do
            AdminCore.registerAction({
                id = item[1],
                title = item[2],
                category = "Logs",
                allowed = D.allowed,
                keywords = "debug performance memory fps visibility freeze",
                run = item[3],
            })
        end
    elseif not D.nativeHooked then
        D.nativeHooked = true
        local create = ISAdminPanelUI.create
        function ISAdminPanelUI:create()
            create(self)
            if not D.allowed() or not self.cancel then
                return
            end
            local y, h = self.cancel.y, self.cancel.height
            local b = ISButton:new(
                self.cancel.x,
                y,
                self.cancel.width,
                h,
                "Diagnostics start / stop",
                nil,
                D.toggle
            )
            b.internal = "ADMIN_DIAGNOSTICS"
            b:initialise()
            b:instantiate()
            self:addChild(b)
            self.cancel:setY(y + h + 10)
            self:setHeight(self.height + h + 10)
        end
    end
end)
