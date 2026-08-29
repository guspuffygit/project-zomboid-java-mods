package com.sentientsimulations.projectzomboid.extralogging.models;

import java.util.List;
import lombok.Data;

@Data
public class AnimalDeathLog {

    private Integer animalId;
    private String animalType;
    private String breed;
    private String customName;
    private Boolean female;
    private Boolean wild;
    private Boolean baby;
    private Boolean geriatric;
    private Integer age;
    private Float weight;
    private Float meatRatio;

    private String deathCause;
    private String killerType;
    private String killerUsername;
    private Long killerSteamId;
    private String killerAnimalType;
    private Double gameHoursSinceLastAttack;

    private Float x;
    private Float y;
    private Float z;

    private Float health;
    private Float hunger;
    private Float thirst;
    private Float stress;
    private Double hoursSurvived;

    private Boolean roadKill;
    private Boolean onFire;
    private Boolean onHook;

    private Integer hutchX;
    private Integer hutchY;
    private Integer hutchZ;
    private Integer nestBoxIndex;

    private String zoneName;
    private Double zoneId;

    private List<String> geneticDisorders;
}
