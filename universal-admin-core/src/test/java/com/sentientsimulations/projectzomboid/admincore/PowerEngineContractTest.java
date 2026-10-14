package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.ui.UITextBox2;
import zombie.vehicles.BaseVehicle;

class PowerEngineContractTest {
    @Test
    void powersSearchUsesAvailableNativeTextEntryMethods() throws Exception {
        assertEquals(
                void.class,
                UITextBox2.class.getMethod("setPlaceholderText", String.class).getReturnType());
        assertEquals(
                String.class, UITextBox2.class.getMethod("getPlaceholderText").getReturnType());
        assertEquals(
                void.class, UITextBox2.class.getMethod("SetText", String.class).getReturnType());
        assertEquals(String.class, UITextBox2.class.getMethod("getText").getReturnType());
        assertEquals(void.class, UITextBox2.class.getMethod("focus").getReturnType());
        assertEquals(void.class, UITextBox2.class.getMethod("unfocus").getReturnType());
        assertEquals(boolean.class, UITextBox2.class.getMethod("isFocused").getReturnType());
    }

    @Test
    void everyWhitelistedPowerUsesExistingBooleanNativeMethods() throws Exception {
        Path path = Path.of("media/lua/shared/AdminCore/PowerDefinitions.lua");
        if (!Files.exists(path)) {
            path = Path.of("universal-admin-core").resolve(path);
        }
        String lua = Files.readString(path);
        var row =
                Pattern.compile(
                                "\\{\\s*\"([^\"]+)\",\\s*\"[^\"]+\",\\s*\"[^\"]+\","
                                        + "\\s*\"ADMIN_[^\"]+\",\\s*\"([^\"]+)\","
                                        + "\\s*\"([^\"]+)\",\\s*\"([^\"]+)\"\\s*,?\\s*}")
                        .matcher(lua);
        int count = 0;
        while (row.find()) {
            assertEquals(Capability.class, Capability.class.getField(row.group(2)).getType());
            assertEquals(
                    boolean.class,
                    IsoPlayer.class.getMethod(row.group(3)).getReturnType(),
                    row.group(1));
            assertEquals(
                    void.class,
                    IsoPlayer.class.getMethod(row.group(4), boolean.class).getReturnType(),
                    row.group(1));
            count++;
        }
        assertEquals(
                24, count, "Every supported power must be checked against the installed build");
    }

    @Test
    void safeVehicleToolsUseAvailableNativeInspectionAndReplication() throws Exception {
        assertEquals(short.class, BaseVehicle.class.getMethod("getId").getReturnType());
        assertEquals(int.class, BaseVehicle.class.getMethod("getSkinCount").getReturnType());
        assertEquals(int.class, BaseVehicle.class.getMethod("getSkinIndex").getReturnType());
        assertEquals(int.class, BaseVehicle.class.getMethod("getPartCount").getReturnType());
        assertEquals(
                void.class, BaseVehicle.class.getMethod("setSkinIndex", int.class).getReturnType());
        assertEquals(void.class, BaseVehicle.class.getMethod("transmitSkinIndex").getReturnType());
        assertTrue(
                BaseVehicle.class.getMethod("getScript").getReturnType().getMethod("getFullName")
                        != null);
    }
}
