-- Separate compatibility extension; does not redistribute Chunk List source.
-- Export retains every selected chunk. Only nearby boundary previews are retained.
ATFChunkListBudget = ATFChunkListBudget or {}
local B = ATFChunkListBudget

function B.install()
    local list = _G.ChunkList
    if not list or list.__atfBudget then
        return
    end
    list.__atfBudget = true
    local originalDump = list.dumpSelection

    function list:stopSelection()
        if self.highlightTask then
            Events.OnPlayerUpdate.Remove(self.highlightTask)
        end
        self.highlightTask = nil
        self.highlightCoords = {}
        self.selectionActive = false
        -- dumpSelection is called AFTER stopSelection by the native Export action.
        if self.__atfClear then
            Events.OnTick.Remove(self.__atfClear)
        end
        self.__atfClear = function()
            Events.OnTick.Remove(self.__atfClear)
            self.__atfClear = nil
            if not self.selectionActive then
                self.dumpList = {}
            end
        end
        Events.OnTick.Add(self.__atfClear)
    end

    function list:dumpSelection(name)
        originalDump(self, name)
        self.dumpList = {}
    end

    function list:startSelection(name)
        self:stopSelection()
        self.selectionActive, self.dumpList = name, {}
        local previousX, previousY, previousZ
        self.highlightTask = function(player)
            if player ~= getPlayer() then
                return
            end
            if not player or player:isDead() or not self:playerIsAdmin() then
                self:stopSelection()
                self.dumpList = {}
                return
            end
            local size = self.chunkSize
            local x, y, z =
                math.floor(player:getX() / size),
                math.floor(player:getY() / size),
                math.floor(player:getZ())
            self.dumpList[x .. "_" .. y] = true
            if x ~= previousX or y ~= previousY or z ~= previousZ then
                previousX, previousY, previousZ = x, y, z
                local coords, keys = {}, {}
                -- Fixed nine-chunk window: total work cannot grow with the journey.
                for cx = x - 1, x + 1 do
                    for cy = y - 1, y + 1 do
                        if self.dumpList[cx .. "_" .. cy] then
                            for _, coord in ipairs(self:getBoundarySquares(cx, cy)) do
                                local key = coord[1] .. ":" .. coord[2]
                                if not keys[key] then
                                    keys[key] = true
                                    coords[#coords + 1] = coord
                                end
                            end
                        end
                    end
                end
                self.highlightCoords = coords
            end
            self:highlightSquares(self.highlightCoords)
        end
        Events.OnPlayerUpdate.Add(self.highlightTask)
    end
end

if B.startHook then
    Events.OnGameStart.Remove(B.startHook)
end
B.startHook = B.install
Events.OnGameStart.Add(B.startHook)
B.install()
