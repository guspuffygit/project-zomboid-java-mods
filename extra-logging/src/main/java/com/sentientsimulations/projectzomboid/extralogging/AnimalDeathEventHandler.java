package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sentientsimulations.projectzomboid.extralogging.models.AnimalDeathLog;
import java.util.ArrayList;
import java.util.StringJoiner;
import zombie.GameTime;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.characters.animals.IsoAnimal;
import zombie.characters.animals.datas.AnimalBreed;
import zombie.characters.animals.datas.AnimalData;
import zombie.iso.IsoGridSquare;
import zombie.iso.areas.DesignationZoneAnimal;
import zombie.iso.objects.IsoHutch;

/**
 * Logs {@code OnAnimalDeath}. Animals never reach {@link DeathEventHandler}: {@code IsoAnimal}
 * extends {@code IsoPlayer}, but Storm's death trigger tests for animals before players, so they
 * arrive as their own event with a player-shaped payload that does not apply (no username, traits
 * or perks) and livestock-specific state that does.
 */
public class AnimalDeathEventHandler {

    private static final String SEPARATOR =
            "================================================================================";
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    /** Hunger/thirst above this drains health in {@code AnimalData.updateHealth}. */
    private static final float NEGLECT_THRESHOLD = 0.8F;

    private static final long GAME_MILLIS_PER_HOUR = 3600000L;

    private static final org.slf4j.Logger logger = ExtraLoggerFactory.createLogger("animal-deaths");
    private static final org.slf4j.Logger jsonLogger =
            ExtraLoggerFactory.createLogger("animal-deaths", "json");

    public static void onAnimalDeath(IsoAnimal animal) {
        try {
            AnimalDeathLog log = buildLog(animal);
            writeDeathEntry(log);
            jsonLogger.info(OBJECT_MAPPER.writeValueAsString(log));
            LOGGER.debug(
                    "Logged death of animal: {} ({})", log.getAnimalType(), log.getDeathCause());
        } catch (Exception e) {
            LOGGER.error("Failed to log death for animal: {}", describe(animal), e);
        }
    }

    private static AnimalDeathLog buildLog(IsoAnimal animal) {
        AnimalDeathLog log = new AnimalDeathLog();

        AnimalData data = animal.getData();

        log.setAnimalId(animal.getAnimalID());
        log.setAnimalType(animal.getAnimalType());
        log.setBreed(breedName(data));
        log.setCustomName(animal.getCustomName());
        log.setFemale(animal.isFemale());
        log.setWild(animal.isWild());
        log.setBaby(animal.isBaby());
        log.setGeriatric(animal.isGeriatric());
        if (data != null) {
            log.setAge(data.getAge());
            log.setWeight(data.getWeight());
        }
        log.setMeatRatio(animal.getMeatRatio());

        appendDeathCause(log, animal);

        log.setX(animal.getX());
        log.setY(animal.getY());
        log.setZ(animal.getZ());

        log.setHealth(animal.getHealth());
        log.setHunger(animal.getHunger());
        log.setThirst(animal.getThirst());
        log.setStress(animal.getStress());
        log.setHoursSurvived(animal.getHoursSurvived());

        log.setRoadKill(animal.isRoadKill());
        log.setOnFire(animal.isOnFire());
        log.setOnHook(animal.isOnHook());

        IsoHutch hutch = animal.getHutch();
        if (hutch != null) {
            IsoGridSquare square = hutch.getSquare();
            if (square != null) {
                log.setHutchX(square.getX());
                log.setHutchY(square.getY());
                log.setHutchZ(square.getZ());
            }
            log.setNestBoxIndex(animal.getNestBoxIndex());
        }

        DesignationZoneAnimal zone = animal.getDZone();
        if (zone != null) {
            log.setZoneName(zone.getName());
            log.setZoneId(zone.getId());
        }

        if (!animal.geneticDisorder.isEmpty()) {
            log.setGeneticDisorders(new ArrayList<>(animal.geneticDisorder));
        }

        return log;
    }

    private static void appendDeathCause(AnimalDeathLog log, IsoAnimal animal) {
        IsoGameCharacter attacker = animal.getAttackedBy();
        if (attacker != null) {
            log.setGameHoursSinceLastAttack(gameHoursSinceLastAttack(animal));
        }

        // IsoAnimal extends IsoPlayer, so animals must be tested before players.
        if (attacker instanceof IsoAnimal killerAnimal) {
            log.setDeathCause("Animal");
            log.setKillerType("Animal");
            log.setKillerAnimalType(killerAnimal.getAnimalType());
        } else if (attacker instanceof IsoZombie) {
            log.setDeathCause("Zombie");
            log.setKillerType("Zombie");
        } else if (attacker instanceof IsoPlayer killerPlayer) {
            log.setDeathCause("Player");
            log.setKillerType("Player");
            log.setKillerUsername(killerPlayer.getUsername());
            log.setKillerSteamId(killerPlayer.getSteamID());
        } else if (animal.isRoadKill()) {
            log.setDeathCause("Vehicle");
        } else if (animal.isOnFire()) {
            log.setDeathCause("Fire");
        } else if (attacker != null) {
            log.setDeathCause(attacker.getClass().getSimpleName());
            log.setKillerType(attacker.getClass().getSimpleName());
        } else if (animal.getHutch() != null && animal.getHealth() > 0.0F) {
            // Storm's IsoHutch.killAnimal seam fires before setHealth(0), so a hutched animal
            // arriving with health > 0 can only be a meta-predator kill; in-hutch health-drain
            // deaths arrive at <= 0.
            log.setDeathCause("MetaPredator");
            log.setKillerType("MetaPredator");
        } else if (animal.getHunger() > NEGLECT_THRESHOLD) {
            log.setDeathCause("Starvation");
        } else if (animal.getThirst() > NEGLECT_THRESHOLD) {
            log.setDeathCause("Dehydration");
        } else if (animal.isGeriatric()) {
            log.setDeathCause("OldAge");
        } else if (animal.getHutch() != null) {
            // Health drained inside the hutch without hunger/thirst/age standing out — dirt decay.
            log.setDeathCause("HutchNeglect");
        } else {
            log.setDeathCause("Unknown");
        }
    }

    private static Double gameHoursSinceLastAttack(IsoAnimal animal) {
        if (animal.attackedTimer <= 0L) {
            return null;
        }
        long now = GameTime.getInstance().getCalender().getTimeInMillis();
        return (now - animal.attackedTimer) / (double) GAME_MILLIS_PER_HOUR;
    }

    private static String breedName(AnimalData data) {
        if (data == null) {
            return null;
        }
        AnimalBreed breed = data.getBreed();
        return breed == null ? null : breed.getName();
    }

    private static void writeDeathEntry(AnimalDeathLog log) {
        logger.info("{}\n{}\n{}\n{}", SEPARATOR, formatHeader(log), SEPARATOR, formatBody(log));
    }

    private static String formatHeader(AnimalDeathLog log) {
        String name = log.getCustomName();
        String descriptor =
                log.getBreed() == null
                        ? log.getAnimalType()
                        : log.getBreed() + " " + log.getAnimalType();
        return String.format(
                "Death of %s (id %s)",
                name == null || name.isEmpty() ? descriptor : name + " the " + descriptor,
                log.getAnimalId());
    }

    private static String formatBody(AnimalDeathLog log) {
        StringBuilder sb = new StringBuilder();

        field(sb, "Type", log.getAnimalType());
        field(sb, "Breed", log.getBreed());
        field(sb, "Custom Name", log.getCustomName());
        field(sb, "Sex", Boolean.TRUE.equals(log.getFemale()) ? "Female" : "Male");
        field(sb, "Wild", String.valueOf(log.getWild()));
        field(sb, "Age", String.format("%s days%s", log.getAge(), lifeStage(log)));
        field(sb, "Weight", format(log.getWeight()));

        field(sb, "Death Cause", formatKiller(log));
        field(
                sb,
                "Position",
                String.format("(%.1f, %.1f, %.1f)", log.getX(), log.getY(), log.getZ()));

        sb.append("\n--- Condition ---\n");
        field(sb, "Health", format(log.getHealth()));
        field(sb, "Hunger", format(log.getHunger()));
        field(sb, "Thirst", format(log.getThirst()));
        field(sb, "Stress", format(log.getStress()));
        field(sb, "Hours Survived", String.format("%.1f", log.getHoursSurvived()));

        sb.append("\n--- Home ---\n");
        if (log.getHutchX() != null) {
            field(
                    sb,
                    "Hutch",
                    String.format(
                            "(%d, %d, %d) nest box %d",
                            log.getHutchX(),
                            log.getHutchY(),
                            log.getHutchZ(),
                            log.getNestBoxIndex()));
        } else {
            field(sb, "Hutch", "none");
        }
        field(sb, "Zone", log.getZoneName() == null ? "none" : log.getZoneName());

        if (log.getGeneticDisorders() != null) {
            StringJoiner joiner = new StringJoiner(", ");
            for (String disorder : log.getGeneticDisorders()) {
                joiner.add(disorder);
            }
            sb.append("\n--- Genetic Disorders ---\n");
            sb.append("{ ").append(joiner).append(" }\n");
        }

        return sb.toString();
    }

    private static String formatKiller(AnimalDeathLog log) {
        if (log.getKillerUsername() != null) {
            return "Killed by player: " + log.getKillerUsername();
        }
        if (log.getKillerAnimalType() != null) {
            return "Killed by animal: " + log.getKillerAnimalType();
        }
        return log.getDeathCause();
    }

    private static String lifeStage(AnimalDeathLog log) {
        if (Boolean.TRUE.equals(log.getBaby())) {
            return " (baby)";
        }
        if (Boolean.TRUE.equals(log.getGeriatric())) {
            return " (geriatric)";
        }
        return "";
    }

    private static String describe(IsoAnimal animal) {
        try {
            return animal.getAnimalType() + "#" + animal.getAnimalID();
        } catch (Exception e) {
            return String.valueOf(animal);
        }
    }

    private static String format(Float value) {
        return value == null ? "n/a" : String.format("%.2f", value);
    }

    private static void field(StringBuilder sb, String label, String value) {
        sb.append(String.format("%-16s%s%n", label + ":", value));
    }
}
