CSR_Theme = CSR_Theme or {}

CSR_Theme.colors = {
    panelBg = { a = 0.82, r = 0.07, g = 0.08, b = 0.10 },
    panelHeader = { a = 0.94, r = 0.12, g = 0.14, b = 0.18 },
    panelBorder = { a = 0.95, r = 0.29, g = 0.35, b = 0.42 },
    text = { a = 1.0, r = 0.94, g = 0.96, b = 0.98 },
    textMuted = { a = 1.0, r = 0.67, g = 0.73, b = 0.80 },
    accentBlue = { a = 1.0, r = 0.34, g = 0.66, b = 0.96 },
    accentGreen = { a = 1.0, r = 0.38, g = 0.78, b = 0.58 },
    accentAmber = { a = 1.0, r = 0.92, g = 0.70, b = 0.30 },
    accentRed = { a = 1.0, r = 0.86, g = 0.36, b = 0.36 },
    accentViolet = { a = 1.0, r = 0.72, g = 0.58, b = 0.94 },
    accentSlate = { a = 1.0, r = 0.30, g = 0.36, b = 0.44 },
}

local function c(name)
    return CSR_Theme.colors[name]
end

function CSR_Theme.getColor(name)
    return c(name)
end

function CSR_Theme.withAlpha(color, alpha)
    if not color then
        return nil
    end

    return {
        a = alpha ~= nil and alpha or color.a or 1.0,
        r = color.r or 1.0,
        g = color.g or 1.0,
        b = color.b or 1.0,
    }
end

function CSR_Theme.statusColor(text)
    local t = string.lower(text or "")
    if t:find("off", 1, true) or t:find("missing", 1, true) or t:find("none", 1, true) or t:find("failed", 1, true) then
        return c("accentRed")
    end
    if t:find("high", 1, true) or t:find("warning", 1, true) or t:find("stale", 1, true) or t:find("dup", 1, true) then
        return c("accentAmber")
    end
    if t:find("on", 1, true) or t:find("ready", 1, true) or t:find("nearby", 1, true) then
        return c("accentGreen")
    end
    return c("text")
end

function CSR_Theme.drawPanelChrome(panel, title, headerHeight)
    local bg = c("panelBg")
    local header = c("panelHeader")
    local border = c("panelBorder")
    local text = c("text")
    local muted = c("textMuted")

    panel:drawRect(0, 0, panel.width, panel.height, bg.a, bg.r, bg.g, bg.b)
    panel:drawRect(0, 0, panel.width, headerHeight, header.a, header.r, header.g, header.b)
    panel:drawRectBorder(0, 0, panel.width, panel.height, border.a, border.r, border.g, border.b)
    panel:drawText(title, 10, math.max(3, math.floor((headerHeight - 16) / 2)), text.r, text.g, text.b, 0.97, UIFont.Small)
    panel:drawText("CSR", panel.width - 34, math.max(3, math.floor((headerHeight - 16) / 2)), muted.r, muted.g, muted.b, 0.70, UIFont.Small)
end

function CSR_Theme.applyButtonStyle(button, accentName, active)
    if not button then
        return
    end

    local accent = c(accentName or "accentBlue") or c("accentBlue")
    local bg = active and {
        r = math.min(1, accent.r * 0.55),
        g = math.min(1, accent.g * 0.55),
        b = math.min(1, accent.b * 0.55),
        a = 1.0,
    } or {
        r = 0.18,
        g = 0.20,
        b = 0.24,
        a = 1.0,
    }

    button.backgroundColor = bg
    button.backgroundColorMouseOver = {
        r = math.min(1, bg.r + 0.08),
        g = math.min(1, bg.g + 0.08),
        b = math.min(1, bg.b + 0.08),
        a = 1.0,
    }
    button.borderColor = {
        r = active and accent.r or 0.36,
        g = active and accent.g or 0.40,
        b = active and accent.b or 0.46,
        a = 1.0,
    }
end

return CSR_Theme
