require("AdminCore/OverlayManager")
local C, M = AdminCore, AdminOverlayManager
if C.observerOverlaysInstalled then
    return
end
C.observerOverlaysInstalled = true
M.registerOverlay("observer.facing", {
    permission = "ADMIN_SPECTATOR",
    refreshMs = 100,
    maxRows = 1,
    active = function()
        return C.observer.id ~= nil
    end,
    collect = function()
        local target = C.observedPlayer()
        if not target then
            return {}
        end
        -- This is the replicated forward vector, not an exact weapon/ballistics ray.
        local dx, dy = target:getForwardDirectionX(), target:getForwardDirectionY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.001 then
            return {}
        end
        return {
            {
                x = target:getX(),
                y = target:getY(),
                z = target:getZ(),
                dx = dx / length,
                dy = dy / length,
            },
        }
    end,
    renderWorld = function(ui, rows)
        for _, row in ipairs(rows) do
            M.drawLine(
                ui,
                row.x,
                row.y,
                row.x + row.dx * 4,
                row.y + row.dy * 4,
                row.z,
                { r = 0.3, g = 0.95, b = 1 },
                "Facing"
            )
        end
    end,
})

-- Town/property overlays use the same cache and render loop; they never fetch
-- data or bypass Community Manager's separate authorization.
for _, kind in ipairs({ "towns", "properties" }) do
    local category = kind
    M.registerOverlay("observer." .. category, {
        permission = "ADMIN_RENDER_DEBUG",
        refreshMs = 2000,
        maxRows = 128,
        active = function()
            return C.observer.id ~= nil
        end,
        collect = function()
            local community, target = ATFCommunity, C.observedPlayer()
            if
                not target
                or not community
                or not community.canManage
                or not community.canManage()
                or not community.state
                or not community.bounds
            then
                return {}
            end
            local rows = {}
            for _, record in ipairs(community.state[category] or {}) do
                local b = community.bounds(record)
                if
                    b
                    and b.x1 < target:getX() + 80
                    and b.x2 > target:getX() - 80
                    and b.y1 < target:getY() + 80
                    and b.y2 > target:getY() - 80
                then
                    rows[#rows + 1] = {
                        x1 = b.x1,
                        y1 = b.y1,
                        x2 = b.x2,
                        y2 = b.y2,
                        z = b.z or math.floor(target:getZ()),
                        label = record.name or record.title or category,
                    }
                    if #rows >= 128 then
                        break
                    end
                end
            end
            return rows
        end,
        renderWorld = function(ui, rows)
            for _, row in ipairs(rows) do
                M.drawRect(ui, row, { r = 0.85, g = 0.6, b = 0.95 }, row.label)
            end
        end,
    })
end

M.registerOverlay("observer.safehouses", {
    permission = "ADMIN_RENDER_DEBUG",
    refreshMs = 2000,
    maxRows = 128,
    active = function()
        return C.observer.id ~= nil
    end,
    collect = function()
        local target = C.observedPlayer()
        if not target then
            return {}
        end
        local rows, houses = {}, SafeHouse.getSafehouseList()
        for i = 0, houses:size() - 1 do
            local house = houses:get(i)
            local x, y, w, h = house:getX(), house:getY(), house:getW(), house:getH()
            if
                x < target:getX() + 80
                and x + w > target:getX() - 80
                and y < target:getY() + 80
                and y + h > target:getY() - 80
            then
                rows[#rows + 1] = {
                    x = x,
                    y = y,
                    w = w,
                    h = h,
                    z = math.floor(target:getZ()),
                    label = house:getTitle(),
                }
                if #rows >= 128 then
                    break
                end
            end
        end
        return rows
    end,
    renderWorld = function(ui, rows)
        for _, row in ipairs(rows) do
            M.drawRect(ui, row, { r = 0.8, g = 0.75, b = 0.3 }, row.label)
        end
    end,
})
M.registerOverlay("observer.community", {
    permission = "ADMIN_RENDER_DEBUG",
    refreshMs = 2000,
    maxRows = 128,
    active = function()
        return C.observer.id ~= nil
    end,
    collect = function()
        -- Optional integration reads only Community's independently authorized state.
        local community = ATFCommunity
        if
            not community
            or not community.canManage
            or not community.canManage()
            or not community.state
        then
            return {}
        end
        local rows = {}
        for _, zone in ipairs(community.state.zones or {}) do
            local b = community.bounds and community.bounds(zone) or zone
            if b and b.x1 and b.y1 and b.x2 and b.y2 then
                rows[#rows + 1] = {
                    x1 = b.x1,
                    y1 = b.y1,
                    x2 = b.x2,
                    y2 = b.y2,
                    z = b.z or 0,
                    label = zone.name or "Community zone",
                }
                if #rows >= 128 then
                    break
                end
            end
        end
        return rows
    end,
    renderWorld = function(ui, rows)
        for _, row in ipairs(rows) do
            M.drawRect(ui, row, { r = 0.3, g = 1, b = 0.5 }, row.label)
        end
    end,
})
