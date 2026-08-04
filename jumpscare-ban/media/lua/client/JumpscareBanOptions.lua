-- Client mod option for Jumpscare Ban (Options > Mods > Jumpscare Ban).
-- Only the admin sound commands (/kachow, /fart, /cry) honor this option;
-- the ban jumpscare and the send-off broadcast after a real ban always play.

JumpscareBanOptions = JumpscareBanOptions or {}

-- Guard against re-registration: PZAPI.ModOptions:create() inserts a fresh page
-- into PZAPI.ModOptions.Data every call, so an unguarded re-run of this file
-- (Lua hot-reload) duplicates the whole section in the options screen.
if not JumpscareBanOptions.adminSounds then
    local options = PZAPI.ModOptions:create("JumpscareBan", "UI_optionscreen_binding_JumpscareBan")

    JumpscareBanOptions.adminSounds = options:addTickBox(
        "JumpscareBan_adminSounds",
        "UI_optionscreen_binding_JumpscareBan_adminSounds",
        true,
        "UI_optionscreen_binding_JumpscareBan_adminSounds_tooltip"
    )
end

function JumpscareBanOptions.isAdminSoundsEnabled()
    return JumpscareBanOptions.adminSounds:getValue()
end
