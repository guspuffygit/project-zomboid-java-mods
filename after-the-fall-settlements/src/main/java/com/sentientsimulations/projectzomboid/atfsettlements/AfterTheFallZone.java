package com.sentientsimulations.projectzomboid.atfsettlements;

import lombok.AllArgsConstructor;
import lombok.Getter;

@AllArgsConstructor
@Getter
public class AfterTheFallZone {
    private Double xStart;
    private Double xEnd;
    private Double yStart;
    private Double yEnd;
    private String region;
    private String type;
    private String mayor;
    private Boolean admin;
}
