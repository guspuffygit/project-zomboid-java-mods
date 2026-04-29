require "CSR_FeatureFlags"

--[[
    CSR_Guide.lua
    In-game guide window accessible from the Utility HUD.
    Uses ISCollapsableWindow + ISRichTextPanel to display feature documentation.
]]

CSR_Guide = {}

local guideWindow = nil

local GUIDE_SECTIONS = {
    {
        title = "Getting Started",
        text = "<SIZE:medium> <RGB:0.6,0.9,1.0> Common Sense Reborn <RGB:1,1,1> <SIZE:small> <LINE>"
            .. " <LINE> CSR adds practical quality-of-life features to Project Zomboid."
            .. " <LINE> <LINE> <RGB:1,0.8,0.3> Toggling Features On/Off <RGB:1,1,1>"
            .. " <LINE> Every feature can be toggled in <RGB:0.7,1,0.7> Sandbox Settings > Common Sense Reborn <RGB:1,1,1>."
            .. " <LINE> Access this from the main menu before starting, or from the admin"
            .. " <LINE> panel in multiplayer. Changes take effect immediately."
            .. " <LINE> <LINE> <RGB:1,0.8,0.3> Hiding UI Panels <RGB:1,1,1>"
            .. " <LINE> All CSR panels can be toggled with hotkeys (see Controls below)."
            .. " <LINE> Press the same hotkey again to hide any panel."
            .. " <LINE> The Utility HUD's Lock button prevents accidental dragging."
            .. " <LINE> Close this guide with the X button or the ? button on the HUD.",
    },
    {
        title = "Controls & Hotkeys",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> Controls & Hotkeys <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> All hotkeys are rebindable via Mod Options (main menu or in-game)."
            .. " <LINE> <LINE> <RGB:0.6,0.9,1.0> HUD & Overlays <RGB:1,1,1>"
            .. " <LINE> <RGB:0.7,1,0.7> Numpad /    <RGB:1,1,1> Toggle Utility HUD"
            .. " <LINE> <RGB:0.7,1,0.7> Numpad *    <RGB:1,1,1> Toggle Zombie Density Overlay"
            .. " <LINE> <RGB:0.7,1,0.7> Numpad 3    <RGB:1,1,1> Toggle Vehicle Dashboard"
            .. " <LINE> <LINE> <RGB:0.6,0.9,1.0> Inventory <RGB:1,1,1>"
            .. " <LINE> <RGB:0.7,1,0.7> \\           <RGB:1,1,1> Toggle Loot Filter Panel"
            .. " <LINE> <RGB:0.7,1,0.7> .           <RGB:1,1,1> Toggle Hide Equipped Items"
            .. " <LINE> <RGB:0.7,1,0.7> Tab         <RGB:1,1,1> Toggle Proximity Loot Panel"
            .. " <LINE> <RGB:0.7,1,0.7> Numpad 6    <RGB:1,1,1> Toggle Nested Containers"
            .. " <LINE> <LINE> <RGB:0.6,0.9,1.0> Actions <RGB:1,1,1>"
            .. " <LINE> <RGB:0.7,1,0.7> Numpad +    <RGB:1,1,1> Toggle Seatbelt"
            .. " <LINE> <RGB:0.7,1,0.7> Numpad -    <RGB:1,1,1> Quick Sit / Stand"
            .. " <LINE> <LINE> <RGB:0.6,0.9,1.0> Utility HUD Buttons <RGB:1,1,1>"
            .. " <LINE> <RGB:0.7,1,0.7> ? button    <RGB:1,1,1> Open/close this guide"
            .. " <LINE> <RGB:0.7,1,0.7> Lock/Unlock <RGB:1,1,1> Prevent accidental panel dragging"
            .. " <LINE> <RGB:0.7,1,0.7> P / Z / O   <RGB:1,1,1> Filter sound cues (Players/Zombies/Other)"
            .. " <LINE> <RGB:0.7,1,0.7> DW button   <RGB:1,1,1> Toggle Dual Wield on/off"
            .. " <LINE> <LINE> <RGB:0.6,0.9,1.0> Admin Control <RGB:1,1,1>"
            .. " <LINE> When Admin Authoritative Control is enabled in sandbox, per-player"
            .. " <LINE> toggles (DW, Nested Containers) are locked to the server values."
            .. " <LINE> Locked buttons show a lock indicator. Players cannot override.",
    },
    {
        title = "Pry System",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> Pry System <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> Right-click doors, safes, and vehicle doors with a crowbar or pry tool to force them open."
            .. " <LINE> <RGB:0.7,1,0.7> Garage doors, safe doors, and vehicle doors <RGB:1,1,1> each have separate toggles."
            .. " <LINE> <RGB:0.7,1,0.7> Bolt cutters <RGB:1,1,1> can cut padlocks and chain-link fences."
            .. " <LINE> Tool condition matters -- damaged tools may break during use.",
    },
    {
        title = "Lockpicking",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> Lockpicking <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> Use a screwdriver on locked doors to attempt picking the lock."
            .. " <LINE> Success depends on skill and luck. Higher Electrical skill helps.",
    },
    {
        title = "Vehicle Features",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> Vehicle Features <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> <RGB:0.7,1,0.7> Mechanics QoL: <RGB:1,1,1> Batch uninstall parts, improved part inspection."
            .. " <LINE> <RGB:0.7,1,0.7> Vehicle Salvage: <RGB:1,1,1> Salvage wrecked vehicles for Mechanics and Metalworking XP."
            .. " <LINE> <RGB:0.7,1,0.7> Seatbelt: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> Numpad + <RGB:1,1,1>. Reduces crash injury."
            .. " <LINE> <RGB:0.7,1,0.7> Dashboard: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> Numpad 3 <RGB:1,1,1>. Color-coded gauges, clock, radio."
            .. " <LINE> <RGB:0.7,1,0.7> Smart Key Labels: <RGB:1,1,1> Keys show which vehicle they belong to."
            .. " <LINE> <RGB:0.7,1,0.7> Vehicle HVAC: <RGB:1,1,1> Vehicle heating/cooling affects player temperature."
            .. " <LINE> <RGB:0.7,1,0.7> Hotwire: <RGB:1,1,1> Improvised hotwiring with Electrical skill."
            .. " <LINE> <RGB:0.7,1,0.7> Remove Hotwire: <RGB:1,1,1> Seated as driver of a hotwired vehicle with the engine off and a screwdriver in inventory, the V radial menu shows a 'Remove Hotwire' slice."
            .. " <LINE>   Duration scales with Electricity and Mechanics. Costs 1 condition on the screwdriver. SP + MP. Toggle in sandbox: EnableUnHotwire.",
    },
    {
        title = "Combat & Survival",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> Combat & Survival <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> <RGB:0.7,1,0.7> Point Blank: <RGB:1,1,1> Bonus damage at extremely close range."
            .. " <LINE> <RGB:0.7,1,0.7> Bullet Penetration: <RGB:1,1,1> Bullets can pass through killed zombies."
            .. " <LINE> <RGB:0.7,1,0.7> Dual Wield: <RGB:1,1,1> Hold a weapon in each hand. Toggle via HUD DW button."
            .. " <LINE>   Disabled by default -- enable in sandbox settings first."
            .. " <LINE>   If Admin Authoritative Control is on, the DW toggle is locked."
            .. " <LINE> <RGB:0.7,1,0.7> Back 2 Slot: <RGB:1,1,1> Carry two large weapons on your back."
            .. " <LINE> <RGB:0.7,1,0.7> Stop, Drop & Roll: <RGB:1,1,1> When on fire, right-click to drop and roll."
            .. " <LINE>   Lucky trait extinguishes faster. May damage outer clothing."
            .. " <LINE> <RGB:0.7,1,0.7> Corpse Ignite: <RGB:1,1,1> Burn zombie corpses with lighter + fuel."
            .. " <LINE> <RGB:0.7,1,0.7> Hide in Furniture: <RGB:1,1,1> Hide in closets, beds, dumpsters, fridges, couches, tables, crates, barrels."
            .. " <LINE>   Become invisible to zombies. Boredom increases. ESC or move to stop."
            .. " <LINE>   Survives logout/reconnect. Container must not be too full."
            .. " <LINE> <RGB:0.7,1,0.7> Vision Cone Outline: <RGB:1,1,1> Zombies in your view cone glow with an outline."
            .. " <LINE>   Only while aiming (RMB). Requires melee outline in game settings."
            .. " <LINE> <RGB:0.7,1,0.7> Infection Resilience: <RGB:1,1,1> Small chance to survive a zombie infection."
            .. " <LINE>   When infection reaches a random threshold, the game rolls for survival."
            .. " <LINE>   Success converts the infection to a recoverable fever."
            .. " <LINE>   Multiple bites reduce your odds. All values configurable in sandbox."
            .. " <LINE> <RGB:0.7,1,0.7> Field Filters: <RGB:1,1,1> Craft makeshift respirator and gas mask filters."
            .. " <LINE>   Uses common materials (charcoal, ripped sheets, cans, tape)."
            .. " <LINE>   Filter lifespan multiplier adjustable in sandbox settings.",
    },
    {
        title = "Inventory & Items",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> Inventory & Items <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> <RGB:0.7,1,0.7> Alternate Can Opening: <RGB:1,1,1> Open cans with knives, axes, etc."
            .. " <LINE> <RGB:0.7,1,0.7> Eat All Stack: <RGB:1,1,1> Eat or drink an entire stack at once."
            .. " <LINE> <RGB:0.7,1,0.7> Magazine Batch: <RGB:1,1,1> Load/unload all magazines at once."
            .. " <LINE> <RGB:0.7,1,0.7> Equipment QoL: <RGB:1,1,1> Quick equip improvements."
            .. " <LINE> <RGB:0.7,1,0.7> Loot Filter: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> \\ <RGB:1,1,1>. Filter container contents by type."
            .. " <LINE> <RGB:0.7,1,0.7> Clipboard Filter: <RGB:1,1,1> Toggle in Loot Filter panel. Hides items already on your clipboard checklists."
            .. " <LINE> <RGB:0.7,1,0.7> Proximity Loot: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> Tab <RGB:1,1,1>. Highlights nearby loot."
            .. " <LINE> <RGB:0.7,1,0.7> Hide Equipped: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> . <RGB:1,1,1>. Hide equipped items in list."
            .. " <LINE> <RGB:0.7,1,0.7> Nested Containers: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> Numpad 6 <RGB:1,1,1>. Bags show as buttons."
            .. " <LINE> <RGB:0.7,1,0.7> Item Insight Tooltips: <RGB:1,1,1> Extended item info on hover."
            .. " <LINE> <RGB:0.7,1,0.7> Item Rename: <RGB:1,1,1> Rename items with custom labels."
            .. " <LINE> <RGB:0.7,1,0.7> Tool Set: <RGB:1,1,1> Craft combined tool items (tool roll, toolbox)."
            .. " <LINE> <RGB:0.7,1,0.7> Bag Bottom Attach: <RGB:1,1,1> Attach weapons to the bottom of backpacks."
            .. " <LINE> <RGB:0.7,1,0.7> Dismantle All Watches: <RGB:1,1,1> Batch dismantle watches for parts."
            .. " <LINE> <RGB:0.7,1,0.7> Gear Sling: <RGB:1,1,1> Adds a dedicated csr:gearsling equip slot for shoulder bags, satchels, chest rigs, duffels, and other crossbody carriers."
            .. " <LINE>   Note: when EnableGearSling is on, the curated bag list is *moved* from its vanilla slot (back / fanny / webbing / satchel) into csr:gearsling -- this frees the vanilla slot for a primary backpack."
            .. " <LINE>   Disable EnableGearSling in sandbox to restore vanilla slot routing. The toggle requires a save reload to take effect because B42 CanBeEquipped is rewritten at startup.",
    },
    {
        title = "Actions & Comfort",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> Actions & Comfort <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> <RGB:0.7,1,0.7> Walking Actions: <RGB:1,1,1> Perform some actions while walking."
            .. " <LINE> <RGB:0.7,1,0.7> Quick Sit: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> Numpad - <RGB:1,1,1>. Sit on the ground anywhere."
            .. " <LINE> <RGB:0.7,1,0.7> Warm Up: <RGB:1,1,1> Rub hands together when cold (right-click menu)."
            .. " <LINE>   Blocked by hand injuries. Unequips held items. You can walk while warming."
            .. " <LINE> <RGB:0.7,1,0.7> Sleep Anywhere: <RGB:1,1,1> Sleep on the ground without a bed."
            .. " <LINE> <RGB:0.7,1,0.7> Sleep Benefits: <RGB:1,1,1> Sleeping reduces boredom and unhappiness."
            .. " <LINE> <RGB:0.7,1,0.7> Massage: <RGB:1,1,1> Massage another player to reduce pain."
            .. " <LINE> <RGB:0.7,1,0.7> Towel Drying: <RGB:1,1,1> Use a towel to dry off faster."
            .. " <LINE> <RGB:0.7,1,0.7> Exercise With Gear: <RGB:1,1,1> Keep bags and clothing on during exercise.",
    },
    {
        title = "HUD & Overlays",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> HUD & Overlays <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> <RGB:0.7,1,0.7> Utility HUD: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> Numpad / <RGB:1,1,1>. Draggable status panel."
            .. " <LINE>   Shows food freshness, repair hints, zombie density."
            .. " <LINE>   Lock button prevents dragging. ? button opens this guide."
            .. " <LINE> <RGB:0.7,1,0.7> Weapon HUD Overlay: <RGB:1,1,1> Weapon condition display near hotbar."
            .. " <LINE> <RGB:0.7,1,0.7> Visual Sound Cues: <RGB:1,1,1> On-screen indicators for sounds."
            .. " <LINE>   Filter with HUD buttons: P=players, Z=zombies, O=other."
            .. " <LINE> <RGB:0.7,1,0.7> Zombie Density: <RGB:1,1,1> Toggle with <RGB:0.7,1,0.7> Numpad * <RGB:1,1,1>. Heatmap overlay."
            .. " <LINE>   Minimap variant also available."
            .. " <LINE> <RGB:0.7,1,0.7> Player Map Tracking: <RGB:1,1,1> See other players on the map (MP)."
            .. " <LINE> <RGB:0.7,1,0.7> Hotbar Flashlight: <RGB:1,1,1> Flashlight indicator on the hotbar."
            .. " <LINE> <RGB:0.7,1,0.7> ADS Ammo Counter: <RGB:1,1,1> Floating ammo pill near your cursor when aiming any firearm."
            .. " <LINE>   Independent from the hotbar pill strip and weapon HUD counter. Toggle in sandbox."
            .. " <LINE> <RGB:0.7,1,0.7> Survivor's Ledger: <RGB:1,1,1> Draggable HUD strip showing days survived, kills, distance, weight, session kills, and avg K/D."
            .. " <LINE>   Stats persist across saves. Drag to reposition. Default OFF; enable under Interface settings."
            .. " <LINE> <RGB:0.7,1,0.7> Passive Generator Overlay: <RGB:1,1,1> Open any Generator Info window and click the 'Overlay: ON / OFF' button next to Range."
            .. " <LINE>   Draws a dim purple ring around every activated generator on your floor so you can see power coverage without opening each gen."
            .. " <LINE>   The single-gen Range button and carry preview continue to work independently. Per-character preference persists.",
    },
    {
        title = "Utility",
        text = "<SIZE:medium> <RGB:1,0.7,0.3> Utility <SIZE:small> <RGB:1,1,1> <LINE>"
            .. " <LINE> <RGB:0.7,1,0.7> Useful Barrels: <RGB:1,1,1> Uncap vanilla barrels with a pipe wrench."
            .. " <LINE>   Once uncapped, barrels store fluids and collect rain when outdoors."
            .. " <LINE>   Capacity configurable in sandbox. Uses vanilla fluid system."
            .. " <LINE> <RGB:0.7,1,0.7> Wash Menu Split: <RGB:1,1,1> Separate wash and drink options."
            .. " <LINE> <RGB:0.7,1,0.7> Sweep Trash: <RGB:1,1,1> Clean up floor debris."
            .. " <LINE> <RGB:0.7,1,0.7> Clipboard QoL: <RGB:1,1,1> Clipboard interaction improvements."
            .. " <LINE> <RGB:0.7,1,0.7> Room Scanner: <RGB:1,1,1> Scan Room button on clipboard. Detects enclosed room and lists all items."
            .. "   Requires paper + pen. Auto-names from room type. Rescan to update."
            .. " <LINE> <RGB:0.7,1,0.7> Notice Board: <RGB:1,1,1> Right-click paper notice tiles or whiteboards to read or write messages."
            .. "   Writing requires a pen, pencil, or marker. Whiteboards hold up to 6 lines."
            .. " <LINE> <RGB:0.7,1,0.7> Video Insert/Eject: <RGB:1,1,1> Right-click a TV or VCR to insert or eject a VHS tape or DVD."
            .. " <LINE> <RGB:0.7,1,0.7> Quick Device Toggle: <RGB:1,1,1> Quickly toggle flashlights and radios."
            .. " <LINE> <RGB:0.7,1,0.7> Saw All Drop: <RGB:1,1,1> Sawing logs drops planks to the ground."
            .. " <LINE> <RGB:0.7,1,0.7> Firework: <RGB:1,1,1> Light fireworks to distract zombies."
            .. " <LINE> <RGB:0.7,1,0.7> Repair Extensions: <RGB:1,1,1> Expanded repair options for more items."
            .. " <LINE> <RGB:0.7,1,0.7> Advanced Sound Options: <RGB:1,1,1> Fine-tune sound settings."
            .. " <LINE> <RGB:0.7,1,0.7> Character Info: <RGB:1,1,1> Enhanced character info panel."
            .. " <LINE> <RGB:0.7,1,0.7> Hide Watermark: <RGB:1,1,1> Remove the version watermark from screen."
            .. " <LINE> <RGB:0.7,1,0.7> Climb With Bags: <RGB:1,1,1> Keep bags in your hands when climbing windows and fences."
            .. " <LINE>   Heavier bags slow you down. Works with all bag types."
            .. " <LINE> <RGB:0.7,1,0.7> Climb With Generator: <RGB:1,1,1> Carry generators through windows and over fences."
            .. "   Heavier time penalty than bags (0.25/kg). Visible generator model."
            .. " <LINE> <RGB:0.7,1,0.7> Wearable Slot Fix: <RGB:1,1,1> Ear muffs and protectors use Ears slot instead of Hat."
            .. "   Wear ear protection and a hat at the same time."
            .. " <LINE> <RGB:0.7,1,0.7> Tow Assist: <RGB:1,1,1> Vehicles get a forward boost while towing."
            .. " <LINE>   Force scales with both vehicle masses. Per-type factors in sandbox.",
    },
}

local function buildFullText()
    local parts = {}
    for i, section in ipairs(GUIDE_SECTIONS) do
        if i > 1 then
            table.insert(parts, " <LINE> <LINE> ")
        end
        table.insert(parts, section.text)
    end
    return table.concat(parts)
end

function CSR_Guide.toggle()
    if guideWindow and guideWindow:isVisible() then
        guideWindow:setVisible(false)
        guideWindow:removeFromUIManager()
        guideWindow = nil
        return
    end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local w = math.min(520, screenW - 40)
    local h = math.min(560, screenH - 40)
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    guideWindow = ISCollapsableWindow:new(x, y, w, h)
    guideWindow:initialise()
    guideWindow:setTitle(getText("IGUI_CSR_Guide_Title"))
    guideWindow.resizable = true
    guideWindow.drawFrame = true

    local titleBarHeight = guideWindow:titleBarHeight()

    local richText = ISRichTextPanel:new(0, titleBarHeight, w, h - titleBarHeight)
    richText:initialise()
    richText.autosetheight = false
    richText.background = true
    richText.backgroundColor = { r = 0, g = 0, b = 0, a = 0.85 }
    richText.borderColor = { r = 0.3, g = 0.3, b = 0.3, a = 0.6 }
    richText.marginLeft = 12
    richText.marginTop = 8
    richText.marginRight = 12
    richText.marginBottom = 8
    richText.anchorLeft = true
    richText.anchorRight = true
    richText.anchorTop = true
    richText.anchorBottom = true
    richText:setText(buildFullText())
    richText:paginate()

    guideWindow:addChild(richText)
    guideWindow:addToUIManager()
    guideWindow:setVisible(true)
    guideWindow:bringToTop()
end
