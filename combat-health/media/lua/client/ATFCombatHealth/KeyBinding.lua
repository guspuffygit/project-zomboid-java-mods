require("keyBinding")
require("OptionScreens/MainOptions")

ATFCombatHealthBindings = ATFCombatHealthBindings or {}
local B = ATFCombatHealthBindings
function B.register()
    local heading = false
    for _, entry in ipairs(keyBinding) do
        if entry.value == "ATFCombatHealthToggle" then
            return
        end
        heading = heading or entry.value == "[ATFCombatHealth]"
    end
    if not heading then
        table.insert(keyBinding, { value = "[ATFCombatHealth]" })
    end
    table.insert(keyBinding, { value = "ATFCombatHealthToggle", key = 0 })
end
B.register()
if not B.installed then
    B.installed = true
    local loadKeys = MainOptions.loadKeys
    function MainOptions.loadKeys(...)
        B.register()
        return loadKeys(...)
    end
    Events.OnGameBoot.Add(B.register)
end
return B
