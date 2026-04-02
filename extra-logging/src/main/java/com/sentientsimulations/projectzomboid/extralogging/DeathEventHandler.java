package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sentientsimulations.projectzomboid.extralogging.models.DeathLog;
import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.characters.CharacterStat;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.characters.Stats;
import zombie.characters.skills.PerkFactory;
import zombie.characters.traits.CharacterTraits;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.scripting.objects.CharacterTrait;

public class DeathEventHandler {

    private static final String SEPARATOR =
            "================================================================================";
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private static final ch.qos.logback.classic.Logger logger =
            ExtraLoggerFactory.createLogger("deaths");
    private static final ch.qos.logback.classic.Logger jsonLogger =
            ExtraLoggerFactory.createLogger("deaths", "json");

    private static void writeDeathEntry(String header, String body) {
        logger.info("{}\n{}\n{}\n{}", SEPARATOR, header, SEPARATOR, body);
    }

    private static void writeDeathEntryJson(OnCharacterDeathEvent event) {
        try {
            IsoPlayer player = (IsoPlayer) event.character;
            DeathLog log = new DeathLog();

            // Identity
            log.setUsername(player.getUsername());
            log.setSteamId(player.getSteamID());
            log.setForename(player.getDescriptor().getForename());
            log.setSurname(player.getDescriptor().getSurname());
            log.setInfected(player.getBodyDamage().isInfected());

            // Death cause
            IsoGameCharacter attacker = player.getAttackedBy();
            if (attacker instanceof IsoPlayer killerPlayer) {
                log.setDeathCause("PVP");
                log.setKillerUsername(killerPlayer.getUsername());
            } else if (attacker instanceof IsoZombie) {
                log.setDeathCause("Zombie");
            } else if (player.isOnFire()) {
                log.setDeathCause("Fire");
            } else if (attacker != null) {
                log.setDeathCause(attacker.getClass().getSimpleName());
            } else {
                log.setDeathCause("Unknown");
            }

            log.setX(player.getX());
            log.setY(player.getY());
            log.setZ(player.getZ());

            log.setZombieKills(player.getZombieKills());
            log.setHoursSurvived(player.getHoursSurvived());

            BodyDamage bd = player.getBodyDamage();
            log.setPartsBleeding(bd.getNumPartsBleeding());
            log.setPartsBitten(bd.getNumPartsBitten());
            log.setPartsScratched(bd.getNumPartsScratched());

            Stats stats = player.getStats();
            Map<String, Float> statsMap = new LinkedHashMap<>();
            for (CharacterStat stat : CharacterStat.REGISTRY.values()) {
                statsMap.put(stat.getId(), stats.get(stat));
            }
            log.setStats(statsMap);

            CharacterTraits characterTraits = player.getCharacterTraits();
            Map<CharacterTrait, Boolean> traitsMap = characterTraits.getTraits();
            List<String> traitNames = new ArrayList<>();
            for (Map.Entry<CharacterTrait, Boolean> entry : traitsMap.entrySet()) {
                if (Boolean.TRUE.equals(entry.getValue())) {
                    traitNames.add(entry.getKey().getName());
                }
            }
            log.setTraits(traitNames);

            Map<String, Integer> skillsMap = new LinkedHashMap<>();
            for (PerkFactory.Perk perk : PerkFactory.PerkList) {
                int level = player.getPerkLevel(perk);
                if (level > 0) {
                    skillsMap.put(perk.getName(), level);
                }
            }
            log.setSkills(skillsMap);

            Map<String, Float> skillXpMap = new LinkedHashMap<>();
            for (PerkFactory.Perk perk : PerkFactory.PerkList) {
                float xp = player.getXp().getXP(perk);
                if (xp > 0) {
                    skillXpMap.put(perk.getName(), xp);
                }
            }
            log.setSkillXp(skillXpMap);

            Map<String, Integer> itemCounts = new LinkedHashMap<>();
            countItems(player.getInventory(), itemCounts);
            log.setInventory(itemCounts);

            jsonLogger.info(OBJECT_MAPPER.writeValueAsString(log));
        } catch (Exception e) {
            LOGGER.error("Unable to write death entry json", e);
        }
    }

    public static void onCharacterDeath(OnCharacterDeathEvent event) {
        if (!(event.character instanceof IsoPlayer player)) {
            return;
        }
        try {
            String header = formatHeader(player);
            String body = formatBody(player);
            writeDeathEntry(header, body);
            writeDeathEntryJson(event);
            LOGGER.info("Logged death of player: {}", player.getUsername());
        } catch (Exception e) {
            LOGGER.error("Failed to log death for player: {}", player.getUsername(), e);
        }
    }

    private static String formatHeader(IsoPlayer player) {
        String forename = player.getDescriptor().getForename();
        String surname = player.getDescriptor().getSurname();
        return String.format("Death of %s %s", forename, surname);
    }

    private static String formatBody(IsoPlayer player) {
        StringBuilder sb = new StringBuilder();

        appendIdentity(sb, player);
        appendDeathCause(sb, player);
        appendPosition(sb, player);
        appendCombat(sb, player);
        appendBodyDamage(sb, player);
        appendStats(sb, player);
        appendTraits(sb, player);
        appendSkills(sb, player);
        appendInventory(sb, player);

        return sb.toString();
    }

    private static void appendIdentity(StringBuilder sb, IsoPlayer player) {
        String forename = player.getDescriptor().getForename();
        String surname = player.getDescriptor().getSurname();

        field(sb, "Username", player.getUsername());
        field(sb, "Steam ID", String.valueOf(player.getSteamID()));
        field(sb, "Character", surname + ", " + forename);
        field(sb, "Infected", String.valueOf(player.getBodyDamage().isInfected()));
    }

    private static void appendDeathCause(StringBuilder sb, IsoPlayer player) {
        IsoGameCharacter attacker = player.getAttackedBy();
        String cause;
        if (attacker instanceof IsoPlayer killerPlayer) {
            cause = "Killed by player: " + killerPlayer.getUsername();
        } else if (attacker instanceof IsoZombie) {
            cause = "Killed by zombie";
        } else if (player.isOnFire()) {
            cause = "Killed by fire";
        } else if (attacker != null) {
            cause = "Killed by: " + attacker.getClass().getSimpleName();
        } else {
            cause = "Unknown";
        }
        field(sb, "Death Cause", cause);
    }

    private static void appendPosition(StringBuilder sb, IsoPlayer player) {
        field(
                sb,
                "Position",
                String.format("(%.1f, %.1f, %.1f)", player.getX(), player.getY(), player.getZ()));
    }

    private static void appendCombat(StringBuilder sb, IsoPlayer player) {
        field(sb, "Zombie Kills", String.valueOf(player.getZombieKills()));
        field(sb, "Hours Survived", String.format("%.1f", player.getHoursSurvived()));
    }

    private static void appendBodyDamage(StringBuilder sb, IsoPlayer player) {
        BodyDamage bd = player.getBodyDamage();
        sb.append("\n--- Body Damage ---\n");
        field(sb, "Bleeding", String.valueOf(bd.getNumPartsBleeding()));
        field(sb, "Bitten", String.valueOf(bd.getNumPartsBitten()));
        field(sb, "Scratched", String.valueOf(bd.getNumPartsScratched()));
    }

    private static void appendStats(StringBuilder sb, IsoPlayer player) {
        Stats stats = player.getStats();
        sb.append("\n--- Stats ---\n");
        for (CharacterStat stat :
                new CharacterStat[] {
                    CharacterStat.HUNGER,
                    CharacterStat.THIRST,
                    CharacterStat.PAIN,
                    CharacterStat.FATIGUE,
                    CharacterStat.STRESS,
                    CharacterStat.SICKNESS,
                    CharacterStat.SANITY,
                    CharacterStat.ENDURANCE,
                    CharacterStat.MORALE,
                    CharacterStat.INTOXICATION,
                    CharacterStat.TEMPERATURE,
                    CharacterStat.UNHAPPINESS,
                    CharacterStat.ZOMBIE_INFECTION,
                    CharacterStat.ZOMBIE_FEVER
                }) {
            field(sb, stat.getId(), String.format("%.2f", stats.get(stat)));
        }
    }

    private static void appendTraits(StringBuilder sb, IsoPlayer player) {
        CharacterTraits characterTraits = player.getCharacterTraits();
        Map<CharacterTrait, Boolean> traitsMap = characterTraits.getTraits();
        StringJoiner joiner = new StringJoiner(", ");
        for (Map.Entry<CharacterTrait, Boolean> entry : traitsMap.entrySet()) {
            if (Boolean.TRUE.equals(entry.getValue())) {
                joiner.add(entry.getKey().getName());
            }
        }
        sb.append("\n--- Traits ---\n");
        sb.append("{ ").append(joiner).append(" }\n");
    }

    private static void appendSkills(StringBuilder sb, IsoPlayer player) {
        ArrayList<PerkFactory.Perk> perks = PerkFactory.PerkList;
        StringJoiner joiner = new StringJoiner(", ");
        for (PerkFactory.Perk perk : perks) {
            int level = player.getPerkLevel(perk);
            if (level > 0) {
                joiner.add(perk.getName() + "=" + level);
            }
        }
        sb.append("\n--- Skills ---\n");
        sb.append("{ ").append(joiner).append(" }\n");
    }

    private static void appendInventory(StringBuilder sb, IsoPlayer player) {
        Map<String, Integer> itemCounts = new LinkedHashMap<>();
        countItems(player.getInventory(), itemCounts);
        StringJoiner joiner = new StringJoiner(", ");
        for (Map.Entry<String, Integer> entry : itemCounts.entrySet()) {
            joiner.add(entry.getKey() + " x" + entry.getValue());
        }
        sb.append("\n--- Inventory ---\n");
        sb.append("{ ").append(joiner).append(" }\n");
    }

    private static void countItems(ItemContainer container, Map<String, Integer> itemCounts) {
        for (InventoryItem item : container.getItems()) {
            itemCounts.merge(item.getFullType(), 1, Integer::sum);
            if (item instanceof InventoryContainer inventoryContainer) {
                countItems(inventoryContainer.getInventory(), itemCounts);
            }
        }
    }

    private static void field(StringBuilder sb, String label, String value) {
        sb.append(String.format("%-16s%s%n", label + ":", value));
    }
}
