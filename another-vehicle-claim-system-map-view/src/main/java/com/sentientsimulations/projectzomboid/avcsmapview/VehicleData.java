package com.sentientsimulations.projectzomboid.avcsmapview;

import io.pzstorm.storm.lua.StormKahluaTable;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class VehicleData {
    private Double vehicleID;
    private String ownerPlayerId;
    private Double claimDateTime;
    private String carModel;
    private String displayName;
    private Double lastLocationX;
    private Double lastLocationY;
    private Double lastLocationUpdateTime;
    private VehicleType carType;

    public VehicleData(StormKahluaTable table) {
        vehicleID = table.getDouble("vehicleID");
        ownerPlayerId = table.getString("ownerPlayerId");
        claimDateTime = table.getDouble("claimDateTime");
        carModel = table.getString("carModel");
        displayName = table.getString("displayName");
        lastLocationX = table.getDouble("lastLocationX");
        lastLocationY = table.getDouble("lastLocationY");
        lastLocationUpdateTime = table.getDouble("lastLocationUpdateTime");
        carType = VehicleType.fromString(table.getString("carType"));
    }
}
