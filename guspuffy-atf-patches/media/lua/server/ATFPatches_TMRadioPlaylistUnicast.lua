--[[
True Music Radio answers every client's playlist request with a broadcast.

On load each client sends eight {request = true} ClientCommands (six
terminal playlists, channels, blacklist). Each server handler
(TMRadioServer.UpdatePlaylistTerminalA..MTV / UpdateChannels /
UpdateBlacklist) rebuilds the answer and hands it to
TMRadioServer.SendServerCommandToClients, which is the 3-arg
sendServerCommand - a loop over every connected player. With 1,311-entry
playlists (~59 KB each) one player joining costs ~48 MB of outbound traffic
at 137 players; packet profile scan #9 (2026-09-02) measured it at
0.9-1.2 MB/s, 15-19% of everything the server sends.

The request path never changes shared state (it only re-reads ModData or
creates the default playlist once), so nobody but the requester needs the
reply. The edit path (a client submitting an edited playlist/blacklist
from the terminal UI) does change state and keeps its broadcast.

Implementation: each request-capable handler is wrapped; while it runs for
a {request = true} call, SendServerCommandToClients routes to the 4-arg
sendServerCommand(player, ...) which is a unicast to that player's
connection (GameServer.sendServerCommand(IsoPlayer, ...)). The handlers are
looked up on TMRadioServer by name at dispatch time
(TMRadioServer.OnClientCommand), so swapping the table fields is enough.
Lua handlers run on the server main thread one at a time, so the routing
flag cannot leak between calls; it is still reset on error via pcall.

Applied on the first server tick so TMRServer.lua is guaranteed loaded
regardless of mod order. No ClientCommand can arrive before then.
]]

if not isServer() then
    return
end

local REQUEST_HANDLERS = {
    "UpdatePlaylistTerminalA",
    "UpdatePlaylistTerminalB",
    "UpdatePlaylistTerminalC",
    "UpdatePlaylistTerminalD",
    "UpdatePlaylistTerminalE",
    "UpdatePlaylistTerminalMTV",
    "UpdateChannels",
    "UpdateBlacklist",
}

local function applyPatch()
    if
        type(TMRadioServer) ~= "table"
        or type(TMRadioServer.SendServerCommandToClients) ~= "function"
    then
        print("[ATFPatches] True Music Radio server not loaded; playlist unicast skipped.")
        return false
    end
    if TMRadioServer.__atfPlaylistUnicastApplied then
        return true
    end
    TMRadioServer.__atfPlaylistUnicastApplied = true

    local broadcast = TMRadioServer.SendServerCommandToClients
    local replyTo = nil

    TMRadioServer.SendServerCommandToClients = function(command, args)
        if replyTo then
            sendServerCommand(replyTo, "TMRadio", command, args)
        else
            broadcast(command, args)
        end
    end

    local wrapped = 0
    for _, name in ipairs(REQUEST_HANDLERS) do
        local original = TMRadioServer[name]
        if type(original) == "function" then
            TMRadioServer[name] = function(player, args)
                if not (player and args and args.request == true) then
                    return original(player, args)
                end
                replyTo = player
                local ok, err = pcall(original, player, args)
                replyTo = nil
                if not ok then
                    error(err)
                end
            end
            wrapped = wrapped + 1
        end
    end

    print(
        "[ATFPatches] True Music Radio playlist replies unicast to requester ("
            .. wrapped
            .. " handlers)."
    )
    return true
end

local function onFirstTick()
    Events.OnTick.Remove(onFirstTick)
    applyPatch()
end

Events.OnTick.Add(onFirstTick)
