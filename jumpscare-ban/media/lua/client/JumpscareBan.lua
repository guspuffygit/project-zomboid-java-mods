-- Plays the Foxy jumpscare on the local client when the server tells us we're being banned.
-- Triggered by a server command from the JumpscareBan Storm patch on BanSystem.KickUser;
-- the server delays the actual disconnect ~3s so this animation can finish rendering.

local jumpscareActive = false
local jumpscareTimer = 0
local jumpscareUI = nil
local currentFrame = 0

local maxFrames = 14
local animationSpeed = 10
local totalDuration = maxFrames * animationSpeed

local frames = {}
for i = 0, maxFrames - 1 do
    if i < 10 then
        frames[i] = getTexture("media/textures/foxy_jumpscares/frame_0" .. i .. "_delay-0.06s.png")
    else
        frames[i] = getTexture("media/textures/foxy_jumpscares/frame_" .. i .. "_delay-0.06s.png")
    end
end

local function doFoxyJumpscare()
    if jumpscareActive then return end

    print("[JumpscareBan] BAN JUMPSCARE TRIGGERED!")

    local player = getSpecificPlayer(0)
    if player and player:getSquare() then
        player:getSquare():playSound("JumpscareBanFoxyScream")
    else
        getSoundManager():PlayWorldSoundWav("media/sound/fnaf-foxy-scream.ogg", false, 0, 0, 0, 1.0, true)
    end

    if not jumpscareUI then
        jumpscareUI = ISUIElement:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
        jumpscareUI:addToUIManager()

        jumpscareUI.render = function(self)
            local tex = frames[currentFrame]
            if tex then
                self:drawTextureScaled(tex, 0, 0, self.width, self.height, 1, 1, 1, 1)
            end
        end
    end

    currentFrame = 0
    jumpscareActive = true
    jumpscareTimer = totalDuration
end

local function tickJumpscare()
    if not jumpscareActive then return end

    jumpscareTimer = jumpscareTimer - 1

    if (jumpscareTimer % animationSpeed == 0) then
        currentFrame = currentFrame + 1
        if currentFrame >= maxFrames then
            currentFrame = maxFrames - 1
        end
    end

    if jumpscareTimer <= 0 then
        if jumpscareUI then
            jumpscareUI:removeFromUIManager()
            jumpscareUI = nil
        end
        jumpscareActive = false
    end
end

local function onServerCommand(module, command, args)
    if module == "JumpscareBan" and command == "trigger" then
        doFoxyJumpscare()
    end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(tickJumpscare)
