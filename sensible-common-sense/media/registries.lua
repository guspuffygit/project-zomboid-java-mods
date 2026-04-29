CSR_DualWield = CSR_DualWield or {}

CSR_DualWield.COMMANDMODULE = "CommonSenseReborn"
CSR_DualWield.Commands = {}
CSR_DualWield.Commands.TRIGGERLEFTHANDATTACK = "DW_LeftAttack"
CSR_DualWield.Commands.TRIGGERLEFTHANDHIT = "DW_LeftHit"
CSR_DualWield.Commands.UNARMEDRIGHTHANDATTACK = "DW_UnarmedRightHit"

CSR_DualWield.LEFT_ATTACK_TIME = 20
CSR_DualWield.LEFT_ATTACK_XP = 1.5
CSR_DualWield.LEFT_ATTACK_MAINTENANCE_XP = 1

-- Unarmed mode: everyone punches instead of shoving
CSR_DualWield.UnarmedMode = {
    SCRIPTITEMNAME = "Base.CSR_BarePunching",
    UNARMEDPUNCHINGVALUE = true,
    TRIGGERLEFTHANDATTACK = true,
    MAXHITS_BASE = 1,
    SPEED_BASE = 0.9,
}

-- Shove mode: vanilla-style shove with knockdown, used when player is shoving
CSR_DualWield.ShoveMode = {
    SCRIPTITEMNAME = "Base.CSR_BareShove",
    UNARMEDPUNCHINGVALUE = false,
    TRIGGERLEFTHANDATTACK = false,
    MAXHITS_BASE = 1,
    SPEED_BASE = 1.0,
    ALLOWATTACKFLOOR = false,
}

-- Armed mode: everyone can follow up with left-hand weapon attacks
CSR_DualWield.ArmedMode = {
    TRIGGERLEFTHANDATTACK = true,
    MAXHITS_BASE = 2,
    MAXHITS_PERKBONUS = 0.4,
    SPEED_BASE = 1,
    CONDITIONLOWER_BASE = 1.3,
    MAYDAMAGEWEAPON = true,
}

-- Custom body locations for animated duffel bags / ALICE rigs (LowerBack + chest rig slot).
-- Shared global keyed by location URI so re-registration is safe if another mod (e.g. Skully's Duffels And Rigs) uses the same names.
CustomBodyLocation = CustomBodyLocation or {}
CustomBodyLocation.ItemBodyLocation = CustomBodyLocation.ItemBodyLocation or {}
if not CustomBodyLocation.ItemBodyLocation.LowerBack then
    CustomBodyLocation.ItemBodyLocation.LowerBack = ItemBodyLocation.register("custombodylocation:LowerBack")
end
if not CustomBodyLocation.ItemBodyLocation.NewRigLocation then
    CustomBodyLocation.ItemBodyLocation.NewRigLocation = ItemBodyLocation.register("custombodylocation:NewRigLocation")
end
