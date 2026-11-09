package com.sentientsimulations.projectzomboid.survivorskillobelisk;

/**
 * Obelisk type ids that are not perk names. Everything else stored in {@code obelisk_types.type} is
 * one of these or a {@code PerkFactory.Perks} id.
 */
public final class ObeliskTypes {

    public static final String NONE = "None";

    /** Grants a timed all-skill XP bonus instead of skill recovery. */
    public static final String BLESSING = "Blessing";

    /**
     * Grants nothing here. A game-mode mod (pvp-raids) claims it to unlock its extraction points,
     * so the recover and blessing menus leave it alone.
     */
    public static final String EXTRACTION = "Extraction";

    private ObeliskTypes() {}
}
