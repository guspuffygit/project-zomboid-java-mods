require("AdminCore/Registry")
local C = AdminCore

-- Build only when the registry changes. Expanding/searching never reads world objects.
function C.buildActionTree(entries)
    local roots, groups = {}, {}
    for _, entry in ipairs(entries) do
        local children, path = roots, entry.category
        entry.title = entry.title or tostring(entry.button.title)
        entry.groups = entry.groups or (entry.action and entry.action.group) or {}
        entry.path = table.concat(entry.groups, " / ")
        entry.depth = #entry.groups
        for depth, label in ipairs(entry.groups) do
            path = path .. "\31" .. label
            if not groups[path] then
                local group = {
                    id = path,
                    title = label,
                    category = entry.category,
                    depth = depth - 1,
                    children = {},
                    isGroup = true,
                    sortOrder = entry.sortOrder,
                }
                groups[path] = group
                children[#children + 1] = group
            end
            groups[path].sortOrder = math.min(
                tonumber(groups[path].sortOrder) or 1000,
                tonumber(entry.sortOrder) or 1000
            )
            children = groups[path].children
        end
        children[#children + 1] = entry
    end
    local function sort(nodes)
        table.sort(nodes, C.actionLess)
        for _, node in ipairs(nodes) do
            if node.isGroup then
                sort(node.children)
            end
        end
    end
    sort(roots)
    return roots, groups
end

function C.actionRows(tree, entries, section, query, expanded)
    local rows = {}
    query = (query or ""):match("^%s*(.-)%s*$")
    local function eligible(entry)
        return not entry.hidden
            and (not entry.action or not entry.action.hideUnavailable or entry.enabled)
    end
    if query ~= "" then
        for _, entry in ipairs(entries) do
            if
                eligible(entry)
                and entry.searchable ~= false
                and C.matchesAction(
                    entry.title,
                    entry.category,
                    (entry.keywords or "")
                        .. " "
                        .. entry.path
                        .. " "
                        .. (entry.sourceCategory or ""),
                    section,
                    query,
                    entry.quick
                )
            then
                rows[#rows + 1] = entry
            end
        end
        return rows, false
    end
    local hierarchical = false
    local function visit(nodes, emit)
        local count = 0
        for _, entry in ipairs(nodes) do
            if entry.isGroup then
                local children = {}
                local childCount = visit(entry.children, children)
                if childCount > 0 then
                    hierarchical = true
                    entry.count = childCount
                    emit[#emit + 1] = entry
                    if expanded[entry.id] then
                        for _, child in ipairs(children) do
                            emit[#emit + 1] = child
                        end
                    end
                    count = count + childCount
                end
            elseif
                eligible(entry)
                and entry.visibleInNavigation ~= false
                and C.matchesAction(
                    entry.title,
                    entry.category,
                    entry.keywords,
                    section,
                    "",
                    entry.quick
                )
            then
                emit[#emit + 1] = entry
                count = count + 1
            end
        end
        return count
    end
    visit(tree, rows)
    return rows, hierarchical
end
