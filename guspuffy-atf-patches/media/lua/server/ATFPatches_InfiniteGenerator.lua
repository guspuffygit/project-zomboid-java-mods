--[[
Generator - Infinite: an admin-placed, silent, indestructible generator that
never degrades and never runs out of fuel.

Placement: /additem Base.generator_infinite, then place with the moveable
cursor (or brush-tool the atf_generators_01_0 tile). placeMoveable only
special-cases the four vanilla appliances_misc_01 sprite names, so a custom
generator sprite lands as a plain IsoThumpable/IsoObject — the OnObjectAdded
hook below (fired by both placeMoveable and AddItemToMapPacket, on the server
main thread) swaps it for a real IsoGenerator. Converted squares are
remembered in global ModData so the top-up loop survives restarts; on reload
the map save restores the object as an IsoGenerator directly.

Brush tool (MP, 42.21+): the brush sends AddObjectToMapPacket, which builds a
plain tile object and fires no server event. The client wrapper in
ATFPatches_InfiniteGeneratorBrush sends the "brushPlace" command instead. A
MapObjects load hook converts any plain atf_generators tile when its chunk
loads, and registers any infinite IsoGenerator the registry missed.

Adoption: dropping the item from hands (ISDropWorldItemAction,
ISDropVehicleItemAction, ISTransferAction to the floor) goes through
IsoGridSquare.AddWorldInventoryItem, which builds the IsoGenerator directly
and never fires OnObjectAdded — the generator lands unregistered and burns
its carried tank. Those three server-side completes are wrapped below to
register whatever infinite generator they leave on the drop square.

Silence: the tile's GeneratorSound = ATFSilentGenerator prefix makes every
client-side Loop/Starting/Stopping/Backfire play a no-op (unknown sound), and
the item's SoundRadius/SoundVolume = 1 shrinks the server's repeating
WorldSound (zombie attraction) to a single tile.

Protection is the Survivor Skill Obelisk guard (SurvivorSkillObeliskDestroyGuard)
ported for this sprite: sledgehammer destroy, furniture pickup/disassemble,
the vanilla "Take generator" context action and unplugging are synced timed
actions whose complete() runs on the SERVER in B42, removing the object with
direct Java calls — no removal packet, so overriding complete() here is the
gate. Only a role with the brush-tool capability may remove or unplug one. A non-admin who tries to destroy it is killed SERVER-side: B42
player health is server-authoritative, a client-side Kill only plays the
death screen and leaves the server character alive (see the obelisk's
ObeliskCurseHandler for the full history).
]]

if not isServer() then
    return
end

local SPRITE_PREFIX = "atf_generators_"
local ITEM_FULL_TYPE = "Base.generator_infinite"
local MODDATA_KEY = "ATFPatches_InfiniteGenerators"
local MAX_FUEL = 10 -- IsoGenerator fuel runs 0..10; 10 is 100%
local MAX_CONDITION = 100

ATFPatches_InfiniteGenerator = ATFPatches_InfiniteGenerator or {}
local Gen = ATFPatches_InfiniteGenerator

local function isInfiniteGenSprite(obj)
    if not obj or not obj.getSprite then
        return false
    end
    local sprite = obj:getSprite()
    local name = sprite and sprite:getName() or nil
    return name ~= nil and string.sub(name, 1, #SPRITE_PREFIX) == SPRITE_PREFIX
end

local function registry()
    return ModData.getOrCreate(MODDATA_KEY)
end

local function squareKey(square)
    return square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
end

-- Same policy as the obelisk guard: only a role that can use the brush tool
-- may remove one. Fails closed if the capability lookup errors.
local function isRemovalAllowed(character)
    if not character then
        return false
    end
    local ok, allowed = pcall(function()
        local role = character:getRole()
        return role ~= nil and role:hasCapability(Capability.UseBrushToolManager)
    end)
    return ok and allowed == true
end

local function smite(character)
    if not character or character:isDead() then
        return
    end
    local ok, err = pcall(function()
        character:Kill(character)
        character:die()
    end)
    if not ok then
        print("[ATFPatches] Infinite generator smite failed: " .. tostring(err))
    end
end

local function topUp(gen)
    if not gen:isConnected() then
        gen:setConnected(true)
    end
    if gen:getCondition() < MAX_CONDITION then
        gen:setCondition(MAX_CONDITION)
    end
    if gen:getFuel() < MAX_FUEL then
        gen:setFuel(MAX_FUEL)
    end
    if not gen:isActivated() then
        gen:setActivated(true)
    end
end

function Gen.adoptOnSquare(square)
    if not square then
        return
    end
    local gen = square:getGenerator()
    if not gen or not isInfiniteGenSprite(gen) then
        return
    end
    local key = squareKey(square)
    if registry()[key] then
        return
    end
    registry()[key] = true
    topUp(gen)
    print("[ATFPatches] Infinite generator adopted at " .. key)
end

-- Replaces the plain tile object (if any) with a real IsoGenerator.
local function convertOnSquare(square, tileObj, how)
    -- The chunk generator registry is position-keyed; a second generator on
    -- the same tile kills the live one's power. Leave the tile decorative.
    if square:getGenerator() then
        print(
            "[ATFPatches] Infinite generator NOT converted at "
                .. squareKey(square)
                .. ": square already has a generator"
        )
        return
    end
    if tileObj then
        square:transmitRemoveItemFromSquareOnClients(tileObj)
        square:RemoveTileObject(tileObj)
    end
    -- Constructor adds itself to the square and transmits to clients; the
    -- setters below each self-sync on the server.
    local gen = IsoGenerator.new(instanceItem(ITEM_FULL_TYPE), getCell(), square)
    gen:setConnected(true)
    gen:setCondition(MAX_CONDITION)
    gen:setFuel(MAX_FUEL)
    gen:setActivated(true)
    registry()[squareKey(square)] = true
    print("[ATFPatches] Infinite generator " .. how .. " at " .. squareKey(square))
end

local function findPlainTile(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if not instanceof(obj, "IsoGenerator") and isInfiniteGenSprite(obj) then
            return obj
        end
    end
    return nil
end

function Gen.onObjectAdded(obj)
    if instanceof(obj, "IsoGenerator") then
        if isInfiniteGenSprite(obj) and obj:getSquare() then
            registry()[squareKey(obj:getSquare())] = true
        end
        return
    end
    if not isInfiniteGenSprite(obj) or not obj:getSquare() then
        return
    end
    convertOnSquare(obj:getSquare(), obj, "placed")
end

function Gen.onLoadWithSprite(obj)
    local square = obj:getSquare()
    if not square then
        return
    end
    if instanceof(obj, "IsoGenerator") then
        local key = squareKey(square)
        if not registry()[key] then
            registry()[key] = true
            print("[ATFPatches] Infinite generator registered on load at " .. key)
        end
        return
    end
    convertOnSquare(square, obj, "converted on load")
end

function Gen.onClientCommand(module, command, player, args)
    if module ~= "ATFPatches_InfiniteGenerator" or command ~= "brushPlace" then
        return
    end
    if not isRemovalAllowed(player) then
        print(
            "[ATFPatches] Infinite generator brushPlace rejected for "
                .. tostring(player and player:getUsername())
        )
        return
    end
    local square = args and getCell():getGridSquare(args.x, args.y, args.z) or nil
    if not square then
        return
    end
    convertOnSquare(square, findPlainTile(square), "brush-placed")
end

-- Fuel/condition only drain while the chunk is loaded (IsoGenerator.update),
-- so topping up loaded squares is enough. Unloaded squares are skipped and
-- squares whose generator an admin brush-tooled away are forgotten.
function Gen.everyTenMinutes()
    local reg = registry()
    local dead = nil
    for k, _ in pairs(reg) do
        local x, y, z = string.match(k, "^(-?%d+):(-?%d+):(-?%d+)$")
        local square = x and getSquare(tonumber(x), tonumber(y), tonumber(z)) or nil
        if square then
            local gen = square:getGenerator()
            if gen and isInfiniteGenSprite(gen) then
                topUp(gen)
            else
                dead = dead or {}
                table.insert(dead, k)
            end
        end
    end
    if dead then
        for _, k in ipairs(dead) do
            reg[k] = nil
        end
    end
end

-- Vanilla re-marks the whole building toxic (generator fumes) every in-game
-- hour while a generator runs indoors. Clear it so an infinite generator can
-- live inside a base without gassing it. Caveat: this also un-gasses a real
-- generator running in the SAME building.
function Gen.everyOneMinute()
    for k, _ in pairs(registry()) do
        local x, y, z = string.match(k, "^(-?%d+):(-?%d+):(-?%d+)$")
        local square = x and getSquare(tonumber(x), tonumber(y), tonumber(z)) or nil
        local building = square and square:getBuilding() or nil
        if building and building:isToxic() then
            building:setToxic(false)
        end
    end
end

Gen.origDestroyComplete = Gen.origDestroyComplete or ISDestroyStuffAction.complete
function ISDestroyStuffAction:complete()
    if not isInfiniteGenSprite(self.item) or isRemovalAllowed(self.character) then
        return Gen.origDestroyComplete(self)
    end
    smite(self.character)
    return true
end

Gen.origMoveComplete = Gen.origMoveComplete or ISMoveablesAction.complete
function ISMoveablesAction:complete()
    if self.mode == "pickup" or self.mode == "scrap" then
        local target = self.moveProps and self.moveProps.object or nil
        if isInfiniteGenSprite(target) and not isRemovalAllowed(self.character) then
            return true
        end
    end
    return Gen.origMoveComplete(self)
end

Gen.origTakeComplete = Gen.origTakeComplete or ISTakeGenerator.complete
function ISTakeGenerator:complete()
    if isInfiniteGenSprite(self.generator) and not isRemovalAllowed(self.character) then
        return true
    end
    return Gen.origTakeComplete(self)
end

Gen.origPlugComplete = Gen.origPlugComplete or ISPlugGenerator.complete
function ISPlugGenerator:complete()
    if isInfiniteGenSprite(self.generator) and not isRemovalAllowed(self.character) then
        return true
    end
    return Gen.origPlugComplete(self)
end

local function isInfiniteGenItem(item)
    return item ~= nil and item:getFullType() == ITEM_FULL_TYPE
end

Gen.origDropWorldComplete = Gen.origDropWorldComplete or ISDropWorldItemAction.complete
function ISDropWorldItemAction:complete()
    local adopt = isInfiniteGenItem(self.item)
    local result = Gen.origDropWorldComplete(self)
    if adopt then
        Gen.adoptOnSquare(self.sq)
    end
    return result
end

Gen.origDropVehicleComplete = Gen.origDropVehicleComplete or ISDropVehicleItemAction.complete
function ISDropVehicleItemAction:complete()
    local adopt = isInfiniteGenItem(self.item)
    local result = Gen.origDropVehicleComplete(self)
    if adopt then
        Gen.adoptOnSquare(self.dropSquare)
    end
    return result
end

Gen.origTransferItem = Gen.origTransferItem or ISTransferAction.transferItem
function ISTransferAction:transferItem(character, item, srcContainer, destContainer, dropSquare)
    local adopt = isInfiniteGenItem(item) and dropSquare ~= nil
    local result =
        Gen.origTransferItem(self, character, item, srcContainer, destContainer, dropSquare)
    if adopt then
        Gen.adoptOnSquare(dropSquare)
    end
    return result
end

-- Trampoline pattern: register once, dispatch through the global table so a
-- hot reload replaces the handlers without double-registering.
if not Gen.__eventsRegistered then
    Gen.__eventsRegistered = true
    Events.OnObjectAdded.Add(function(obj)
        ATFPatches_InfiniteGenerator.onObjectAdded(obj)
    end)
    Events.EveryTenMinutes.Add(function()
        ATFPatches_InfiniteGenerator.everyTenMinutes()
    end)
    Events.EveryOneMinute.Add(function()
        ATFPatches_InfiniteGenerator.everyOneMinute()
    end)
    Events.OnClientCommand.Add(function(module, command, player, args)
        ATFPatches_InfiniteGenerator.onClientCommand(module, command, player, args)
    end)
    MapObjects.OnLoadWithSprite("atf_generators_01_0", function(obj)
        ATFPatches_InfiniteGenerator.onLoadWithSprite(obj)
    end, 5)
end
