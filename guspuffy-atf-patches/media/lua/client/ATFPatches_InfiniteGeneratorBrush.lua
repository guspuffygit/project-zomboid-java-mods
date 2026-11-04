--[[
Routes brush-tool placement of the infinite generator to the server.

In multiplayer the brush tool calls sendAddObjectToMap, whose server handler
(AddObjectToMapPacket) builds a plain tile object and never fires
OnObjectAdded, so ATFPatches_InfiniteGenerator never sees it. For the
atf_generators sprites this sends the "brushPlace" command instead; the server
builds a real IsoGenerator and registers it for top-ups.
]]

if not isClient() then
    return
end

local SPRITE_PREFIX = "atf_generators_"

ATFPatches_InfiniteGeneratorBrush = ATFPatches_InfiniteGeneratorBrush or {}
local Brush = ATFPatches_InfiniteGeneratorBrush

Brush.origSendAddObjectToMap = Brush.origSendAddObjectToMap or sendAddObjectToMap

function sendAddObjectToMap(square, spriteName)
    if
        square
        and type(spriteName) == "string"
        and string.sub(spriteName, 1, #SPRITE_PREFIX) == SPRITE_PREFIX
    then
        sendClientCommand(getPlayer(), "ATFPatches_InfiniteGenerator", "brushPlace", {
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
        })
        return
    end
    return Brush.origSendAddObjectToMap(square, spriteName)
end
