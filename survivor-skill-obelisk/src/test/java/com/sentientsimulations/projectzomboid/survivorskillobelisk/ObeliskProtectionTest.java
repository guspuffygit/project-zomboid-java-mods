package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorskillobelisk.patch.ObeliskProtection;
import org.junit.jupiter.api.Test;

class ObeliskProtectionTest {

    @Test
    void protectsAllObeliskSprites() {
        assertTrue(ObeliskProtection.isProtectedSpriteName("atf_obelisks_lg_01_0"));
        assertTrue(ObeliskProtection.isProtectedSpriteName("atf_obelisks_sm_01_13"));
        assertTrue(ObeliskProtection.isProtectedSpriteName("atf_obelisks_lg_01_mirror_7"));
        assertTrue(ObeliskProtection.isProtectedSpriteName("atf_obelisks_lg_01_on_0"));
    }

    @Test
    void ignoresOtherSprites() {
        assertFalse(ObeliskProtection.isProtectedSpriteName(null));
        assertFalse(ObeliskProtection.isProtectedSpriteName(""));
        assertFalse(ObeliskProtection.isProtectedSpriteName("walls_exterior_house_01_0"));
        assertFalse(ObeliskProtection.isProtectedSpriteName("atf_other_thing_0"));
    }
}
