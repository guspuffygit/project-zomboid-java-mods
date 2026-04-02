package com.sentientsimulations.projectzomboid.extralogging.models;

import java.util.List;
import java.util.Map;
import lombok.Data;

@Data
public class DeathLog {

    private String username;
    private Long steamId;
    private String forename;
    private String surname;
    private Boolean infected;

    private String deathCause;
    private String killerUsername;

    private Float x;
    private Float y;
    private Float z;

    private Integer zombieKills;
    private Double hoursSurvived;

    private Integer partsBleeding;
    private Integer partsBitten;
    private Integer partsScratched;

    private Map<String, Float> stats;
    private List<String> traits;
    private Map<String, Integer> skills;
    private Map<String, Float> skillXp;
    private Map<String, Integer> inventory;
}
