package com.sentientsimulations.projectzomboid.avcsmapview;

import lombok.Getter;

public enum VehicleType {
    PERSONAL("personal"),
    FACTION("faction"),
    SAFEHOUSE("safehouse");

    @Getter private final String value;

    VehicleType(String value) {
        this.value = value;
    }

    public static VehicleType fromString(String text) {
        for (VehicleType type : VehicleType.values()) {
            if (type.value.equalsIgnoreCase(text)) {
                return type;
            }
        }
        throw new IllegalArgumentException("No enum constant found for string: " + text);
    }
}
