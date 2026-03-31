package com.sentientsimulations.projectzomboid.extralogging;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import java.util.ArrayList;
import java.util.LinkedHashMap;
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
import zombie.scripting.objects.CharacterTrait;

public class DeathEventHandler {

    @SubscribeEvent
    public static void onCharacterDeath(OnCharacterDeathEvent event) {
        if (!(event.character instanceof IsoPlayer player)) {
            return;
        }
        try {
            String header = formatHeader(player);
            String body = formatBody(player);
            DeathLogWriter.writeDeathEntry(header, body);
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
        ItemContainer inventory = player.getInventory();
        ArrayList<InventoryItem> items = inventory.getItems();
        Map<String, Integer> itemCounts = new LinkedHashMap<>();
        for (InventoryItem item : items) {
            itemCounts.merge(item.getFullType(), 1, Integer::sum);
        }
        StringJoiner joiner = new StringJoiner(", ");
        for (Map.Entry<String, Integer> entry : itemCounts.entrySet()) {
            joiner.add(entry.getKey() + " x" + entry.getValue());
        }
        sb.append("\n--- Inventory ---\n");
        sb.append("{ ").append(joiner).append(" }\n");
    }

    private static void field(StringBuilder sb, String label, String value) {
        sb.append(String.format("%-16s%s%n", label + ":", value));
    }
}
