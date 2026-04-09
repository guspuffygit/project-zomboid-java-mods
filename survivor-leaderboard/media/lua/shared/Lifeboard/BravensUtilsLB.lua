BravensUtilsLB = {}

BravensUtilsLB.DelayFunction = function(func, delay)
    delay = delay or 1
    local ticks = 0
    local canceled = false

    local function onTick()
        if not canceled and ticks < delay then
            ticks = ticks + 1
            return
        end

        Events.OnTick.Remove(onTick)
        if not canceled then func() end
    end

    Events.OnTick.Add(onTick)
    return function()
        canceled = true
    end
end
