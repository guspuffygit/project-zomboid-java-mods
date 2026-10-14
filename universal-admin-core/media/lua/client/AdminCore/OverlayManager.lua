require("ISUI/ISUIElement")
require("AdminCore/OperationsClient")
AdminOverlayManager = AdminOverlayManager or {}
local M, C = AdminOverlayManager, AdminCore
if M.installed then
    return
end
M.installed, M.entries, M.maxProviders = true, {}, 32
function M.registerOverlay(id, provider)
    assert(
        type(id) == "string"
            and #id <= 100
            and type(provider) == "table"
            and type(provider.permission) == "string"
            and type(provider.renderWorld) == "function",
        "Overlay needs a stable id, permission and renderer"
    )
    local count = 0
    for _ in pairs(M.entries) do
        count = count + 1
    end
    assert(M.entries[id] or count < M.maxProviders, "Overlay provider limit reached")
    M.entries[id] = {
        provider = provider,
        enabled = false,
        rows = {},
        nextUpdate = 0,
        maxRows = math.min(256, math.max(1, provider.maxRows or 128)),
        refreshMs = math.max(100, provider.refreshMs or 1000),
    }
end
function M.enableOverlay(id, enabled)
    local entry = M.entries[id]
    if not entry then
        return false
    end
    entry.enabled = enabled == true
    entry.nextUpdate = 0
    if not entry.enabled then
        entry.rows = {}
    end
    C.operationsKeepAlive("overlay:" .. id, entry.enabled)
    return true
end
function M.invalidate(id)
    if M.entries[id] then
        M.entries[id].nextUpdate = 0
    end
end
function M.unregisterOverlay(id)
    M.enableOverlay(id, false)
    M.entries[id] = nil
end
local function authorized(entry)
    if not entry.enabled or not C.operationsAllowed(entry.provider.permission) then
        return false
    end
    if not entry.provider.active then
        return true
    end
    local ok, result = pcall(entry.provider.active)
    return ok and result == true
end
function M.worldPoint(x, y, z)
    local player = getPlayer()
    if not player then
        return 0, 0
    end
    local index = player:getPlayerNum()
    local zoom = getCore():getZoom(index)
    return getPlayerScreenLeft(index)
        + (IsoUtils.XToScreen(x, y, z, 0) - IsoCamera.getOffX(index)) / zoom,
        getPlayerScreenTop(index)
            + (IsoUtils.YToScreen(x, y, z, 0) - IsoCamera.getOffY(index)) / zoom
end
function M.drawLine(ui, x1, y1, x2, y2, z, color, label)
    color = color or { r = 0.3, g = 0.9, b = 1, a = 0.9 }
    local ax, ay = M.worldPoint(x1, y1, z)
    local bx, by = M.worldPoint(x2, y2, z)
    ui:drawLine2(ax, ay, bx, by, color.a or 0.9, color.r or 1, color.g or 1, color.b or 1)
    if label then
        ui:drawText(
            tostring(label):sub(1, 120),
            bx + 4,
            by - 12,
            color.r or 1,
            color.g or 1,
            color.b or 1,
            1,
            UIFont.Small
        )
    end
end
function M.drawRect(ui, b, color, label)
    local x, y, w, h, z = b.x or b.x1, b.y or b.y1, b.w, b.h, b.z or 0
    w = w or (b.x2 - x)
    h = h or (b.y2 - y)
    M.drawLine(ui, x, y, x + w, y, z, color)
    M.drawLine(ui, x + w, y, x + w, y + h, z, color)
    M.drawLine(ui, x + w, y + h, x, y + h, z, color)
    M.drawLine(ui, x, y + h, x, y, z, color, label)
end
function M.renderWorld(ui)
    local player = getPlayer()
    if not player then
        return
    end
    local n = player:getPlayerNum()
    ui:setStencilRect(
        getPlayerScreenLeft(n),
        getPlayerScreenTop(n),
        getPlayerScreenWidth(n),
        getPlayerScreenHeight(n)
    )
    for id, entry in pairs(M.entries) do
        if authorized(entry) then
            local ok, err = pcall(entry.provider.renderWorld, ui, entry.rows, M)
            if not ok then
                M.enableOverlay(id, false)
                print("[Universal Admin Core] Overlay disabled: " .. id .. " | " .. tostring(err))
            end
        end
    end
    ui:clearStencilRect()
end
-- Map consumers can reuse the same bounded cache. No second world render loop.
function M.renderMap(ui, api)
    for _, entry in pairs(M.entries) do
        if authorized(entry) and entry.provider.renderMap then
            pcall(entry.provider.renderMap, ui, entry.rows, api, M)
        end
    end
end
local Layer = ISUIElement:derive("AdminOperationsOverlayLayer")
function Layer:render()
    M.renderWorld(self)
end
function M.tick()
    local now, any = getTimestampMs(), false
    for id, entry in pairs(M.entries) do
        local ok, active = pcall(authorized, entry)
        if ok and active then
            any = true
            if now >= entry.nextUpdate then
                entry.nextUpdate = now + entry.refreshMs
                local success, rows = pcall(entry.provider.collect or function()
                    return {}
                end)
                entry.rows = {}
                if success and type(rows) == "table" then
                    for i = 1, math.min(#rows, entry.maxRows) do
                        entry.rows[i] = rows[i]
                    end
                else
                    M.enableOverlay(id, false)
                    print("[Universal Admin Core] Overlay provider failed: " .. id)
                end
            end
        else
            entry.rows = {}
        end
    end
    if any and not M.ui then
        local ui = Layer:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
        ui:initialise()
        ui:instantiate()
        ui:setWantMouseEvents(false)
        ui:backMost()
        ui:addToUIManager()
        M.ui = ui
    elseif not any and M.ui then
        M.ui:removeFromUIManager()
        M.ui = nil
    end
    if M.ui then
        M.ui:setWidth(getCore():getScreenWidth())
        M.ui:setHeight(getCore():getScreenHeight())
    end
end
function M.clear()
    for id in pairs(M.entries) do
        M.enableOverlay(id, false)
    end
    if M.ui then
        M.ui:removeFromUIManager()
        M.ui = nil
    end
end
Events.OnTick.Add(M.tick)
Events.OnDisconnect.Add(M.clear)
Events.OnMainMenuEnter.Add(M.clear)
