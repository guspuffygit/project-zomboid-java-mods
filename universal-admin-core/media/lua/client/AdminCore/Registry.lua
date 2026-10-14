require("AdminCore/WindowSizing")
local C = AdminCore
C.actions = C.actions or {}
C.registryVersion = C.registryVersion or 0
C.sections = { "Dashboard", "World", "Zones", "Server" }
-- Retain the extension contract used by separately installed mods. A section
-- removed from navigation is still a valid registered category and search alias.
C.categoryAliases = {
    Vehicles = "Server",
    Events = "World",
    Security = "Server",
    Logs = "Server",
    Mods = "Server",
    Settings = "Server",
}
C.aliasGroups = {
    Vehicles = "Vehicles",
    Security = "Security",
    Logs = "Logs",
    Mods = "Mod tools",
    Settings = "Settings",
}
C.nativeSections = {
    CHECKSTATS = "Dashboard",
    ADMINPOWER = "Dashboard",
    ITEMLIST = "Dashboard",
    SEEOPTIONS = "Dashboard",
    NONPVPZONE = "Zones",
    SEEFACTIONS = "Zones",
    SEEROLES = "Server",
    SEEUSERS = "Server",
    SEESAFEHOUSES = "Zones",
    SAFEZONE = "Dashboard",
    SEETICKETS = "Server",
    MINISCOREBOARD = "Dashboard",
    SANDBOX = "Dashboard",
    CLIMATE = "World",
    STATISTICS = "Server",
    PVPLOGTOOL = "Server",
    DEATHMATCH = "Server",
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
    PVPLOGTOOL = "pvp log combat player kills deaths",
    ITEMLIST = "items list viewer item spawn inventory",
    SEEFACTIONS = "factions list owner members tag search",
    SEESAFEHOUSES = "safehouses list house owner property members search",
}
C.nativeGroups = {}
C.quickAccess = {}
C.defaultToolLayout = {
    ["native.ADMINPOWER"] = { sortOrder = 10 },
    ["native.CHECKSTATS"] = { sortOrder = 20 },
    ["native.MINISCOREBOARD"] = { sortOrder = 30 },
    ["native.ITEMLIST"] = { sortOrder = 40 },
    ["native.SAFEZONE"] = { sortOrder = 50, displayName = "Add Safehouse..." },
    ["core.vehicle"] = { sortOrder = 60 },
    ["native.SANDBOX"] = { sortOrder = 70 },
    ["native.SEEOPTIONS"] = { sortOrder = 80 },
    ["native.SEETICKETS"] = { visibleInNavigation = false, searchable = false, hidden = true },
    ["native.PVPLOGTOOL"] = { visibleInNavigation = false },
}

function C.sectionForCategory(category)
    for _, section in ipairs(C.sections) do
        if section == category then
            return section
        end
    end
    return C.categoryAliases[category]
end

-- Presentation metadata does not grant permissions or replace an action's
-- original category. Server-wide editing and personal pins are separate scope.
function C.actionPresentation(id, category, groups, options)
    local defaults = C.defaultToolLayout[id] or {}
    options = options or {}
    local result = {
        category = C.sectionForCategory(category) or "Server",
        sourceCategory = category,
        groups = {},
        visibleInNavigation = true,
        searchable = true,
        hidden = false,
        sortOrder = 1000,
    }
    for _, key in ipairs({
        "visibleInNavigation",
        "searchable",
        "hidden",
        "sortOrder",
        "displayName",
    }) do
        if defaults[key] ~= nil then
            result[key] = defaults[key]
        end
        if options[key] ~= nil then
            result[key] = options[key]
        end
    end
    for _, label in ipairs(groups or {}) do
        result.groups[#result.groups + 1] = label
    end
    if #result.groups == 0 and C.aliasGroups[category] then
        result.groups[1] = C.aliasGroups[category]
    end
    return result
end

function C.actionLess(a, b)
    local ao, bo = tonumber(a.sortOrder) or 1000, tonumber(b.sortOrder) or 1000
    if ao ~= bo then
        return ao < bo
    end
    local at, bt = a.title:lower(), b.title:lower()
    if at ~= bt then
        return at < bt
    end
    return tostring(a.id or a.category) < tostring(b.id or b.category)
end

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
    assert(C.sectionForCategory(action.category), "Unknown control-center category")
    if action.group then
        assert(type(action.group) == "table", "Action group must be a path of labels")
        for _, label in ipairs(action.group) do
            assert(type(label) == "string" and label ~= "", "Group labels must not be empty")
        end
    end
    C.actions[action.id] = action
    C.registryVersion = C.registryVersion + 1
end

function C.canRun(action)
    if action.disabled == true then
        return false
    end
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
function C.pageGeometry(
    width,
    height,
    fontHeight,
    count,
    page,
    hierarchical,
    footerHeight,
    titleHeight
)
    local rowHeight = math.max(32, fontHeight + 12)
    local searchHeight = math.max(28, fontHeight + 6)
    titleHeight = titleHeight or fontHeight
    local searchY = math.max(42, 10 + titleHeight + 12)
    local summaryY = math.max(78, searchY + searchHeight + 8)
    local top = math.max(108, summaryY + fontHeight + 8)
    footerHeight = math.max(30, fontHeight + 6, footerHeight or 0)
    local footerY = height - 32 - footerHeight
    local contentHeight = footerY - 8 - top
    local rows = math.max(1, math.floor((contentHeight + 8) / (rowHeight + 8)))
    -- A collapsed group is a tool row too. Its presence must not force an
    -- otherwise wide window into a different, one-column layout.
    local columns = width >= 900 and 2 or 1
    local pageSize = rows * columns
    local pages = math.max(1, math.ceil(count / pageSize))
    return {
        rowHeight = rowHeight,
        searchHeight = searchHeight,
        searchY = searchY,
        summaryY = summaryY,
        top = top,
        footerY = footerY,
        footerHeight = footerHeight,
        width = width,
        height = height,
        fontHeight = fontHeight,
        titleHeight = titleHeight,
        rows = rows,
        columns = columns,
        pageSize = pageSize,
        pages = pages,
        page = math.max(1, math.min(page or 1, pages)),
    }
end
