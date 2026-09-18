require("AdminCore/WindowSizing")
local C = AdminCore
C.actions = C.actions or {}
C.registryVersion = C.registryVersion or 0
C.sections = {
    "Dashboard",
    "World",
    "Zones",
    "Vehicles",
    "Events",
    "Server",
    "Security",
    "Logs",
    "Mods",
    "Settings",
}
C.nativeSections = {
    CHECKSTATS = "Dashboard",
    ADMINPOWER = "Dashboard",
    ITEMLIST = "World",
    SEEOPTIONS = "Server",
    NONPVPZONE = "Zones",
    SEEFACTIONS = "Zones",
    SEEROLES = "Security",
    SEEUSERS = "Dashboard",
    SEESAFEHOUSES = "Zones",
    SAFEZONE = "Zones",
    SEETICKETS = "Logs",
    MINISCOREBOARD = "Dashboard",
    SANDBOX = "Settings",
    CLIMATE = "World",
    STATISTICS = "Dashboard",
    PVPLOGTOOL = "Logs",
    ZONE_EDITOR = "Zones",
}
C.nativeKeywords = {
    ADMINPOWER = "invisible god ghost noclip powers",
    CHECKSTATS = "self health traits skills xp",
    SEEUSERS = "players accounts user list moderation teleport inventory",
    SEEOPTIONS = "server settings password whitelist max players pvp",
    SANDBOX = "sandbox electricity water loot population settings",
    CLIMATE = "weather temperature rain wind climate",
    STATISTICS = "performance fps tick memory network",
    SAFEZONE = "create safehouse safezone drag rectangle",
    NONPVPZONE = "no pvp zones",
    SEEROLES = "roles permissions access level",
    SEETICKETS = "tickets reports",
}
C.quickAccess = {
    SEEUSERS = true,
    ADMINPOWER = true,
    STATISTICS = true,
    SEEOPTIONS = true,
    SEESAFEHOUSES = true,
}

-- Extensions supply their own server-authorized implementation. No arbitrary command RPC.
function C.registerAction(action)
    assert(
        type(action) == "table" and type(action.id) == "string" and action.id ~= "",
        "Action needs a stable id"
    )
    assert(
        type(action.title) == "string" and type(action.run) == "function",
        "Action needs title and run"
    )
    assert(
        action.capability or type(action.allowed) == "function",
        "Action needs an explicit permission gate"
    )
    local valid = false
    for _, section in ipairs(C.sections) do
        if section == action.category then
            valid = true
        end
    end
    assert(valid, "Unknown control-center category")
    C.actions[action.id] = action
    C.registryVersion = C.registryVersion + 1
end

function C.canRun(action)
    if action.capability and not C.allowed(action.capability) then
        return false
    end
    if action.allowed and not action.allowed() then
        return false
    end
    if action.available and not action.available() then
        return false
    end
    return true
end

function C.runAction(action)
    -- Recheck after the menu was opened: roles and optional modules can change.
    if not C.canRun(action) then
        return C.message("This action is no longer available for your role.")
    end
    local ok, err = pcall(action.run)
    if not ok then
        print("[Universal Admin Core] Action " .. action.id .. " failed: " .. tostring(err))
        C.message("The action could not be completed. Check the client log for details.")
    end
end

function C.matchesAction(title, category, keywords, section, query, quick)
    query = (query or ""):lower():match("^%s*(.-)%s*$")
    if query ~= "" then
        return (title .. " " .. category .. " " .. (keywords or "")):lower():find(query, 1, true)
            ~= nil
    end
    return category == section or (section == "Dashboard" and quick == true)
end

-- Pagination keeps every action reachable at small resolutions and large fonts.
function C.pageGeometry(width, height, fontHeight, count, page)
    local rowHeight = math.max(32, fontHeight + 12)
    local rows = math.max(1, math.floor((height - 166) / (rowHeight + 8)))
    local columns = width >= 900 and 2 or 1
    local pageSize = rows * columns
    local pages = math.max(1, math.ceil(count / pageSize))
    return {
        rowHeight = rowHeight,
        rows = rows,
        columns = columns,
        pageSize = pageSize,
        pages = pages,
        page = math.max(1, math.min(page or 1, pages)),
    }
end
