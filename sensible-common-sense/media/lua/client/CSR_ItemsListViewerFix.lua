--[[
    CSR_ItemsListViewerFix.lua
    -------------------------------------------------------------------------
    Vanilla ISItemsListTable:initList (B42.17 admin Item Viewer) calls
    v:getItemType():toString() on every registered item. If ANY mod has an
    item with a null Type field, getItemType() returns null and the
    :toString() call throws "attempted index: toString of non-table: null",
    which then crashes the entire Item Viewer for admins.

    Crash signature observed in the wild:
        Lua(Vanilla).initList(ISItemsListTable.lua:290)
        attempted index: toString of non-table: null

    Root cause is NOT CSR -- our scripts have valid Type fields. But because
    the crash takes down the admin tool entirely, we monkey-patch initList
    to skip any item whose getItemType() / getDisplayCategory() / getLootType()
    returns null. The skipped items log once each so admins know which mod is
    misbehaving.
--]]

if not ISItemsListTable or not ISItemsListTable.initList then return end
if ISItemsListTable._csrInitListPatched then return end
ISItemsListTable._csrInitListPatched = true

local _origInitList = ISItemsListTable.initList

local function safeStr(jstr)
    if jstr == nil then return nil end
    local ok, s = pcall(function() return jstr:toString() end)
    if not ok then return nil end
    return s
end

function ISItemsListTable:initList(module)
    -- Filter the module list in-place to drop scripts with nil Type before
    -- vanilla iterates them. The rebuilt array preserves ipairs ordering.
    local cleaned = {}
    local skipped = {}
    if module then
        for x = 1, #module do
            local v = module[x]
            local keep = true
            if not v then
                keep = false
            else
                local okType, itemType = pcall(function() return v:getItemType() end)
                if not okType or itemType == nil then
                    keep = false
                end
                if keep then
                    local okDC, dc = pcall(function() return v:getDisplayCategory() end)
                    if not okDC or dc == nil then keep = false end
                end
                if keep then
                    local okLT, lt = pcall(function() return v:getLootType() end)
                    if not okLT or lt == nil then keep = false end
                end
            end
            if keep then
                cleaned[#cleaned + 1] = v
            else
                local name = "<unknown>"
                if v and v.getFullName then
                    local ok, n = pcall(function() return v:getFullName() end)
                    if ok and n then name = tostring(n) end
                end
                skipped[#skipped + 1] = name
            end
        end
    end
    if #skipped > 0 then
        print("[CSR] Item Viewer: skipped " .. #skipped .. " malformed item script(s) to prevent admin-panel crash:")
        for i = 1, math.min(#skipped, 25) do
            print("  - " .. skipped[i])
        end
        if #skipped > 25 then
            print("  ... (" .. (#skipped - 25) .. " more)")
        end
    end
    return _origInitList(self, cleaned)
end
