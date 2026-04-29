CSR_TrashSpriteWhitelist = CSR_TrashSpriteWhitelist or {}

-- Vanilla trash_01 floor sprites (confirmed via forageSystem.lua, camping_fuel.lua, ISDestroyCursor.lua)
-- Decor d_trash_1 sprites (confirmed via newtiledefinitions.tiles.txt, ISDestroyCursor.lua d_ prefix)
-- Community: report missing sprites so they can be added here
local trashSprites = {
    "trash_01_0",  "trash_01_1",  "trash_01_2",  "trash_01_3",
    "trash_01_4",  "trash_01_5",  "trash_01_6",  "trash_01_7",
    "trash_01_8",  "trash_01_9",  "trash_01_10", "trash_01_11",
    "trash_01_12",
    "trash_01_16", "trash_01_17", "trash_01_18", "trash_01_19",
    "trash_01_20", "trash_01_21", "trash_01_22", "trash_01_23",
    "trash_01_24", "trash_01_25", "trash_01_26", "trash_01_27",
    "trash_01_28", "trash_01_29", "trash_01_30", "trash_01_31",
    "trash_01_32", "trash_01_33", "trash_01_34", "trash_01_35",
    "trash_01_36", "trash_01_37", "trash_01_38", "trash_01_39",
    "trash_01_40", "trash_01_41", "trash_01_42", "trash_01_43",
    "trash_01_44", "trash_01_45", "trash_01_46", "trash_01_47",
    "trash_01_48", "trash_01_49", "trash_01_50", "trash_01_51",
    "trash_01_52", "trash_01_53",
    -- Decor trash (paper, plastic bags, wood scraps)
    "d_trash_1_0",  "d_trash_1_1",  "d_trash_1_2",  "d_trash_1_3",
    "d_trash_1_4",  "d_trash_1_5",  "d_trash_1_6",  "d_trash_1_7",
    "d_trash_1_8",  "d_trash_1_9",  "d_trash_1_10", "d_trash_1_11",
    "d_trash_1_12", "d_trash_1_13", "d_trash_1_14", "d_trash_1_15",
    "d_trash_1_16", "d_trash_1_17", "d_trash_1_18", "d_trash_1_19",
    "d_trash_1_20", "d_trash_1_21", "d_trash_1_22", "d_trash_1_23",
    "d_trash_1_24", "d_trash_1_25",
}

-- Build fast lookup table
local lookup = {}
for _, name in ipairs(trashSprites) do
    lookup[name] = true
end

function CSR_TrashSpriteWhitelist.isTrash(spriteName)
    return lookup[spriteName] == true
end

function CSR_TrashSpriteWhitelist.findTrashOnSquare(square)
    if not square then return nil end
    local objects = square:getObjects()
    if not objects then return nil end
    local found = {}
    for i = objects:size() - 1, 0, -1 do
        local obj = objects:get(i)
        if obj and not instanceof(obj, "IsoWorldInventoryObject") then
            local sprite = obj:getSprite()
            if sprite then
                local name = sprite:getName()
                if name and lookup[name] then
                    table.insert(found, obj)
                end
            end
        end
    end
    return #found > 0 and found or nil
end
