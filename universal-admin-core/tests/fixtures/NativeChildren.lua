-- Shared Java UI child ownership and deferred anchor movement for native Lua tests.
return function(J)
    function J:RemoveChild(child)
        for i, entry in ipairs(self.children) do
            if entry == child then
                table.remove(self.children, i)
                break
            end
        end
        child.parent = nil
    end
    function J:onResize()
        local dw, dh = self.width - self.lastWidth, self.height - self.lastHeight
        for _, child in ipairs(self.children) do
            if child.AnchorBottom and not child.AnchorTop then
                child.y = child.y + dh
            end
            if child.AnchorRight and not child.AnchorLeft then
                child.x = child.x + dw
            end
        end
        self.lastWidth, self.lastHeight = self.width, self.height
    end
end
