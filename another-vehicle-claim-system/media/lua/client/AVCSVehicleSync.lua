-- Preserve the existing server-approved AVCS relocation protocol independently of admin UI.
local warps = {}
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AVCS" or command ~= "vehicleWarp" or type(args) ~= "table" then
        return
    end
    if
        type(args.vehicle) == "number"
        and type(args.claim) == "number"
        and type(args.x) == "number"
        and type(args.y) == "number"
        and type(args.physicsY) == "number"
    then
        args.expires = getTimestampMs() + 5000
        warps[args.vehicle] = args
    end
end)
Events.OnTick.Add(function()
    local now = getTimestampMs()
    for id, warp in pairs(warps) do
        if
            now > warp.expires
            or (
                AvcsVehicleSync
                and AvcsVehicleSync.apply(id, warp.claim, warp.x, warp.y, warp.physicsY)
            )
        then
            warps[id] = nil
        end
    end
end)
Events.OnDisconnect.Add(function()
    warps = {}
end)
