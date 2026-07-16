package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** All SQL for the Survivor Skill Obelisk mod. Holds no business logic. */
public class SurvivorSkillObeliskRepository {

    /** A row of the {@code deaths} table flattened for the client-side death-picker UI. */
    public record DeathSummary(
            long id,
            long ts,
            String username,
            String forename,
            String surname,
            double hoursSurvived,
            int zombieKills) {}

    /** Owner identity for a {@code deaths} row — used to validate recovery requests. */
    public record DeathOwner(long steamId, String username) {}

    public record SkillRow(String perk, int level, float xp) {}

    public record WatchedMediaRow(
            String mediaId,
            int mediaIndex,
            int mediaType,
            int linesWatched,
            int lineCount,
            boolean fullyWatched) {}

    /**
     * {@code level}/{@code length}/{@code isaddon} mirror the numeric fields of Lifestyles' track
     * records; nullable because rows written before those columns existed only carry name + sound.
     */
    public record LearnedSongRow(
            String instrument,
            String songName,
            String sound,
            Double level,
            Double length,
            Double isaddon) {}

    /**
     * A Lifestyles hidden-skill row ({@code Yoga}, {@code Inventing}) — mirrors one entry of the
     * player's {@code LSHiddenSkills} mod-data table: {@code {level, xp, xpForNextLevel}}.
     */
    public record HiddenSkillRow(String skill, int level, double xp, double xpForNextLevel) {}

    public record ObeliskTypeRow(int x, int y, int z, String type) {}

    public record AmbitionRow(
            String name,
            String category,
            boolean completed,
            boolean isActive,
            boolean isPassive,
            String[] goals,
            String[] goalProgress) {}

    private static final String LIST_DEATHS_BY_OWNER =
            """
            SELECT id, ts, username, forename, surname, hours_survived, zombie_kills
            FROM deaths
            WHERE steam_id = ? AND username = ?
            ORDER BY ts DESC
            LIMIT ?""";

    private static final String FIND_DEATH_OWNER =
            "SELECT steam_id, username FROM deaths WHERE id = ?";

    private static final String LIST_SKILLS_BY_DEATH =
            "SELECT perk, level, xp FROM death_skills WHERE death_id = ?";

    private static final String LIST_RECIPES_BY_DEATH =
            "SELECT recipe_name FROM death_recipes WHERE death_id = ?";

    private static final String LIST_READ_LITERATURE_BY_DEATH =
            "SELECT literature_title FROM death_read_literature WHERE death_id = ?";

    private static final String LIST_READ_PRINT_MEDIA_BY_DEATH =
            "SELECT media_id FROM death_read_print_media WHERE death_id = ?";

    private static final String LIST_WATCHED_MEDIA_BY_DEATH =
            """
            SELECT media_id, media_index, media_type, lines_watched, line_count, fully_watched
            FROM death_watched_media WHERE death_id = ?""";

    private static final String LIST_LEARNED_SONGS_BY_DEATH =
            """
            SELECT instrument, song_name, sound, level, length, isaddon
            FROM death_learned_songs WHERE death_id = ?""";

    private static final String LIST_HIDDEN_SKILLS_BY_DEATH =
            """
            SELECT skill, level, xp, xp_for_next_level
            FROM death_hidden_skills WHERE death_id = ?""";

    private static final String LIST_AMBITIONS_BY_DEATH =
            """
            SELECT name, category, completed, is_active, is_passive,
                   goal1, goal2, goal3, goal4, goal5, goal6,
                   goal1_progress, goal2_progress, goal3_progress,
                   goal4_progress, goal5_progress, goal6_progress
            FROM death_ambitions WHERE death_id = ?""";

    private static final String INSERT_DEATH =
            """
            INSERT INTO deaths
                (ts, username, steam_id, forename, surname, hours_survived, zombie_kills, x, y, z)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""";

    private static final String INSERT_SKILL =
            "INSERT INTO death_skills (death_id, perk, level, xp) VALUES (?, ?, ?, ?)";

    private static final String INSERT_RECIPE =
            "INSERT INTO death_recipes (death_id, recipe_name) VALUES (?, ?)";

    private static final String INSERT_READ_LITERATURE =
            "INSERT INTO death_read_literature (death_id, literature_title) VALUES (?, ?)";

    private static final String INSERT_READ_PRINT_MEDIA =
            "INSERT INTO death_read_print_media (death_id, media_id) VALUES (?, ?)";

    private static final String INSERT_WATCHED_MEDIA =
            """
            INSERT INTO death_watched_media
                (death_id, media_id, media_index, category, media_type, title,
                 lines_watched, line_count, fully_watched)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""";

    private static final String INSERT_LEARNED_SONG =
            """
            INSERT INTO death_learned_songs
                (death_id, instrument, song_name, sound, level, length, isaddon)
            VALUES (?, ?, ?, ?, ?, ?, ?)""";

    private static final String INSERT_HIDDEN_SKILL =
            """
            INSERT INTO death_hidden_skills (death_id, skill, level, xp, xp_for_next_level)
            VALUES (?, ?, ?, ?, ?)""";

    private static final String FIND_RECOVERY_GRANTS =
            "SELECT perk, xp FROM recovery_skills WHERE steam_id = ? AND username = ?";

    private static final String DELETE_RECOVERY =
            "DELETE FROM recoveries WHERE steam_id = ? AND username = ?";

    private static final String DELETE_RECOVERY_SKILLS =
            "DELETE FROM recovery_skills WHERE steam_id = ? AND username = ?";

    private static final String INSERT_RECOVERY =
            "INSERT INTO recoveries (steam_id, username, death_id, ts) VALUES (?, ?, ?, ?)";

    private static final String INSERT_RECOVERY_SKILL =
            "INSERT INTO recovery_skills (steam_id, username, perk, xp) VALUES (?, ?, ?, ?)";

    private static final String FIND_OBELISK_TYPE =
            "SELECT type FROM obelisk_types WHERE x = ? AND y = ? AND z = ?";

    private static final String LIST_ALL_OBELISK_TYPES = "SELECT x, y, z, type FROM obelisk_types";

    private static final String UPSERT_OBELISK_TYPE =
            """
            INSERT INTO obelisk_types (x, y, z, type, set_by_username, set_by_steam_id, set_ts)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(x, y, z) DO UPDATE SET
                type = excluded.type,
                set_by_username = excluded.set_by_username,
                set_by_steam_id = excluded.set_by_steam_id,
                set_ts = excluded.set_ts""";

    private static final String MARK_OBELISK_NONE =
            """
            INSERT INTO obelisk_types (x, y, z, type, set_by_username, set_by_steam_id, set_ts)
            VALUES (?, ?, ?, 'None', NULL, 0, ?)
            ON CONFLICT(x, y, z) DO UPDATE SET
                type = 'None',
                set_by_username = NULL,
                set_by_steam_id = 0,
                set_ts = excluded.set_ts""";

    private static final String DELETE_OBELISK_TYPE =
            "DELETE FROM obelisk_types WHERE x = ? AND y = ? AND z = ?";

    private static final String INSERT_AMBITION =
            """
            INSERT INTO death_ambitions
                (death_id, name, category, completed, is_active, is_passive,
                 goal1, goal2, goal3, goal4, goal5, goal6,
                 goal1_progress, goal2_progress, goal3_progress,
                 goal4_progress, goal5_progress, goal6_progress)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""";

    private final Connection connection;

    public SurvivorSkillObeliskRepository(Connection connection) {
        this.connection = connection;
    }

    /** Insert a death row and return its generated id. */
    public long insertDeath(
            long ts,
            String username,
            long steamId,
            String forename,
            String surname,
            double hoursSurvived,
            int zombieKills,
            float x,
            float y,
            float z)
            throws SQLException {
        try (PreparedStatement stmt =
                connection.prepareStatement(INSERT_DEATH, Statement.RETURN_GENERATED_KEYS)) {
            stmt.setLong(1, ts);
            stmt.setString(2, username);
            stmt.setLong(3, steamId);
            stmt.setString(4, forename);
            stmt.setString(5, surname);
            stmt.setDouble(6, hoursSurvived);
            stmt.setInt(7, zombieKills);
            stmt.setFloat(8, x);
            stmt.setFloat(9, y);
            stmt.setFloat(10, z);
            stmt.executeUpdate();
            try (ResultSet keys = stmt.getGeneratedKeys()) {
                if (keys.next()) {
                    return keys.getLong(1);
                }
            }
        }
        throw new SQLException("Insert into deaths returned no generated key");
    }

    public void insertSkill(long deathId, String perk, int level, float xp) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_SKILL)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, perk);
            stmt.setInt(3, level);
            stmt.setFloat(4, xp);
            stmt.executeUpdate();
        }
    }

    public void insertRecipe(long deathId, String recipeName) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_RECIPE)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, recipeName);
            stmt.executeUpdate();
        }
    }

    public void insertReadLiterature(long deathId, String literatureTitle) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_READ_LITERATURE)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, literatureTitle);
            stmt.executeUpdate();
        }
    }

    public void insertReadPrintMedia(long deathId, String mediaId) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_READ_PRINT_MEDIA)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, mediaId);
            stmt.executeUpdate();
        }
    }

    public void insertWatchedMedia(
            long deathId,
            String mediaId,
            int mediaIndex,
            String category,
            int mediaType,
            String title,
            int linesWatched,
            int lineCount,
            boolean fullyWatched)
            throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_WATCHED_MEDIA)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, mediaId);
            stmt.setInt(3, mediaIndex);
            stmt.setString(4, category);
            stmt.setInt(5, mediaType);
            stmt.setString(6, title);
            stmt.setInt(7, linesWatched);
            stmt.setInt(8, lineCount);
            stmt.setInt(9, fullyWatched ? 1 : 0);
            stmt.executeUpdate();
        }
    }

    public void insertLearnedSong(
            long deathId,
            String instrument,
            String songName,
            String sound,
            Double level,
            Double length,
            Double isaddon)
            throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_LEARNED_SONG)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, instrument);
            stmt.setString(3, songName);
            stmt.setString(4, sound);
            stmt.setObject(5, level);
            stmt.setObject(6, length);
            stmt.setObject(7, isaddon);
            stmt.executeUpdate();
        }
    }

    public void insertHiddenSkill(
            long deathId, String skill, int level, double xp, double xpForNextLevel)
            throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_HIDDEN_SKILL)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, skill);
            stmt.setInt(3, level);
            stmt.setDouble(4, xp);
            stmt.setDouble(5, xpForNextLevel);
            stmt.executeUpdate();
        }
    }

    /**
     * Lifestyles ambitions have heterogeneous goal types — a slot can be a number target (e.g.
     * 5000), a string flag ("pain"), or unused. {@code goals} / {@code goalProgress} are each
     * length 6; entries map slot index 0→goal1, 1→goal2, ... 5→goal6. Nulls store as SQL NULL.
     */
    public void insertAmbition(
            long deathId,
            String name,
            String category,
            boolean completed,
            boolean isActive,
            boolean isPassive,
            String[] goals,
            String[] goalProgress)
            throws SQLException {
        if (goals.length != 6 || goalProgress.length != 6) {
            throw new IllegalArgumentException("goals/goalProgress must be length 6");
        }
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_AMBITION)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, name);
            stmt.setString(3, category);
            stmt.setInt(4, completed ? 1 : 0);
            stmt.setInt(5, isActive ? 1 : 0);
            stmt.setInt(6, isPassive ? 1 : 0);
            for (int i = 0; i < 6; i++) {
                stmt.setString(7 + i, goals[i]);
            }
            for (int i = 0; i < 6; i++) {
                stmt.setString(13 + i, goalProgress[i]);
            }
            stmt.executeUpdate();
        }
    }

    /**
     * Most recent first. Filter on both {@code steam_id} and {@code username} so an account that
     * was used by multiple PZ characters only sees rows for the one currently in play.
     */
    public List<DeathSummary> listDeathsByOwner(long steamId, String username, int limit)
            throws SQLException {
        List<DeathSummary> rows = new ArrayList<>();
        try (PreparedStatement stmt = connection.prepareStatement(LIST_DEATHS_BY_OWNER)) {
            stmt.setLong(1, steamId);
            stmt.setString(2, username);
            stmt.setInt(3, limit);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    rows.add(
                            new DeathSummary(
                                    rs.getLong("id"),
                                    rs.getLong("ts"),
                                    rs.getString("username"),
                                    rs.getString("forename"),
                                    rs.getString("surname"),
                                    rs.getDouble("hours_survived"),
                                    rs.getInt("zombie_kills")));
                }
            }
        }
        return rows;
    }

    public DeathOwner findDeathOwner(long deathId) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(FIND_DEATH_OWNER)) {
            stmt.setLong(1, deathId);
            try (ResultSet rs = stmt.executeQuery()) {
                if (rs.next()) {
                    return new DeathOwner(rs.getLong("steam_id"), rs.getString("username"));
                }
            }
        }
        return null;
    }

    public List<SkillRow> listSkillsByDeath(long deathId) throws SQLException {
        List<SkillRow> rows = new ArrayList<>();
        try (PreparedStatement stmt = connection.prepareStatement(LIST_SKILLS_BY_DEATH)) {
            stmt.setLong(1, deathId);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    rows.add(
                            new SkillRow(
                                    rs.getString("perk"), rs.getInt("level"), rs.getFloat("xp")));
                }
            }
        }
        return rows;
    }

    public List<String> listRecipesByDeath(long deathId) throws SQLException {
        return listStringColumn(LIST_RECIPES_BY_DEATH, "recipe_name", deathId);
    }

    public List<String> listReadLiteratureByDeath(long deathId) throws SQLException {
        return listStringColumn(LIST_READ_LITERATURE_BY_DEATH, "literature_title", deathId);
    }

    public List<String> listReadPrintMediaByDeath(long deathId) throws SQLException {
        return listStringColumn(LIST_READ_PRINT_MEDIA_BY_DEATH, "media_id", deathId);
    }

    public List<WatchedMediaRow> listWatchedMediaByDeath(long deathId) throws SQLException {
        List<WatchedMediaRow> rows = new ArrayList<>();
        try (PreparedStatement stmt = connection.prepareStatement(LIST_WATCHED_MEDIA_BY_DEATH)) {
            stmt.setLong(1, deathId);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    rows.add(
                            new WatchedMediaRow(
                                    rs.getString("media_id"),
                                    rs.getInt("media_index"),
                                    rs.getInt("media_type"),
                                    rs.getInt("lines_watched"),
                                    rs.getInt("line_count"),
                                    rs.getInt("fully_watched") != 0));
                }
            }
        }
        return rows;
    }

    public List<LearnedSongRow> listLearnedSongsByDeath(long deathId) throws SQLException {
        List<LearnedSongRow> rows = new ArrayList<>();
        try (PreparedStatement stmt = connection.prepareStatement(LIST_LEARNED_SONGS_BY_DEATH)) {
            stmt.setLong(1, deathId);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    rows.add(
                            new LearnedSongRow(
                                    rs.getString("instrument"),
                                    rs.getString("song_name"),
                                    rs.getString("sound"),
                                    getNullableDouble(rs, "level"),
                                    getNullableDouble(rs, "length"),
                                    getNullableDouble(rs, "isaddon")));
                }
            }
        }
        return rows;
    }

    public List<HiddenSkillRow> listHiddenSkillsByDeath(long deathId) throws SQLException {
        List<HiddenSkillRow> rows = new ArrayList<>();
        try (PreparedStatement stmt = connection.prepareStatement(LIST_HIDDEN_SKILLS_BY_DEATH)) {
            stmt.setLong(1, deathId);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    rows.add(
                            new HiddenSkillRow(
                                    rs.getString("skill"),
                                    rs.getInt("level"),
                                    rs.getDouble("xp"),
                                    rs.getDouble("xp_for_next_level")));
                }
            }
        }
        return rows;
    }

    public List<AmbitionRow> listAmbitionsByDeath(long deathId) throws SQLException {
        List<AmbitionRow> rows = new ArrayList<>();
        try (PreparedStatement stmt = connection.prepareStatement(LIST_AMBITIONS_BY_DEATH)) {
            stmt.setLong(1, deathId);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    String[] goals = new String[6];
                    String[] progress = new String[6];
                    for (int i = 0; i < 6; i++) {
                        goals[i] = rs.getString("goal" + (i + 1));
                        progress[i] = rs.getString("goal" + (i + 1) + "_progress");
                    }
                    rows.add(
                            new AmbitionRow(
                                    rs.getString("name"),
                                    rs.getString("category"),
                                    rs.getInt("completed") != 0,
                                    rs.getInt("is_active") != 0,
                                    rs.getInt("is_passive") != 0,
                                    goals,
                                    progress));
                }
            }
        }
        return rows;
    }

    /**
     * The XP amounts (per perk) actually granted to this player by their most recent obelisk
     * recovery. Empty map when the player has never recovered, or has died since — recovery-granted
     * XP is subtracted before the next grant is applied, so this ledger is what makes recovery
     * additive-but-not-stackable.
     */
    public Map<String, Float> findRecoveryGrants(long steamId, String username)
            throws SQLException {
        Map<String, Float> grants = new HashMap<>();
        try (PreparedStatement stmt = connection.prepareStatement(FIND_RECOVERY_GRANTS)) {
            stmt.setLong(1, steamId);
            stmt.setString(2, username);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    grants.put(rs.getString("perk"), rs.getFloat("xp"));
                }
            }
        }
        return grants;
    }

    /**
     * Replace the player's recovery ledger with the given per-perk granted amounts. Caller is
     * responsible for wrapping in a transaction — the delete + inserts must land atomically or a
     * crash mid-write would let the player re-recover without the old grant being subtracted.
     */
    public void replaceRecovery(
            long steamId, String username, long deathId, long ts, Map<String, Float> grants)
            throws SQLException {
        deleteRecovery(steamId, username);
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_RECOVERY)) {
            stmt.setLong(1, steamId);
            stmt.setString(2, username);
            stmt.setLong(3, deathId);
            stmt.setLong(4, ts);
            stmt.executeUpdate();
        }
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_RECOVERY_SKILL)) {
            for (Map.Entry<String, Float> grant : grants.entrySet()) {
                stmt.setLong(1, steamId);
                stmt.setString(2, username);
                stmt.setString(3, grant.getKey());
                stmt.setFloat(4, grant.getValue());
                stmt.executeUpdate();
            }
        }
    }

    /** No-op when the player has no recovery record — safe to call on every death. */
    public void deleteRecovery(long steamId, String username) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(DELETE_RECOVERY)) {
            stmt.setLong(1, steamId);
            stmt.setString(2, username);
            stmt.executeUpdate();
        }
        try (PreparedStatement stmt = connection.prepareStatement(DELETE_RECOVERY_SKILLS)) {
            stmt.setLong(1, steamId);
            stmt.setString(2, username);
            stmt.executeUpdate();
        }
    }

    /** Returns {@code null} when no row exists for the coordinates — caller defaults to "None". */
    public String findObeliskType(int x, int y, int z) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(FIND_OBELISK_TYPE)) {
            stmt.setInt(1, x);
            stmt.setInt(2, y);
            stmt.setInt(3, z);
            try (ResultSet rs = stmt.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("type");
                }
            }
        }
        return null;
    }

    public void upsertObeliskType(
            int x, int y, int z, String type, String setByUsername, long setBySteamId, long setTs)
            throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(UPSERT_OBELISK_TYPE)) {
            stmt.setInt(1, x);
            stmt.setInt(2, y);
            stmt.setInt(3, z);
            stmt.setString(4, type);
            stmt.setString(5, setByUsername);
            stmt.setLong(6, setBySteamId);
            stmt.setLong(7, setTs);
            stmt.executeUpdate();
        }
    }

    public List<ObeliskTypeRow> listAllObeliskTypes() throws SQLException {
        List<ObeliskTypeRow> rows = new ArrayList<>();
        try (PreparedStatement stmt = connection.prepareStatement(LIST_ALL_OBELISK_TYPES);
                ResultSet rs = stmt.executeQuery()) {
            while (rs.next()) {
                rows.add(
                        new ObeliskTypeRow(
                                rs.getInt("x"),
                                rs.getInt("y"),
                                rs.getInt("z"),
                                rs.getString("type")));
            }
        }
        return rows;
    }

    /**
     * Idempotently records that an obelisk exists at the given square with no configured type.
     * Resets {@code type} to {@code "None"} and clears setter attribution on conflict — every fresh
     * placement (pickup + drop, admin re-spawn) starts unconfigured.
     */
    public void markObeliskNone(int x, int y, int z, long setTs) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(MARK_OBELISK_NONE)) {
            stmt.setInt(1, x);
            stmt.setInt(2, y);
            stmt.setInt(3, z);
            stmt.setLong(4, setTs);
            stmt.executeUpdate();
        }
    }

    /** No-op when no row matches — safe to call from redundant removal-event handlers. */
    public void deleteObeliskType(int x, int y, int z) throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(DELETE_OBELISK_TYPE)) {
            stmt.setInt(1, x);
            stmt.setInt(2, y);
            stmt.setInt(3, z);
            stmt.executeUpdate();
        }
    }

    private static Double getNullableDouble(ResultSet rs, String column) throws SQLException {
        double value = rs.getDouble(column);
        return rs.wasNull() ? null : value;
    }

    private List<String> listStringColumn(String sql, String column, long deathId)
            throws SQLException {
        List<String> rows = new ArrayList<>();
        try (PreparedStatement stmt = connection.prepareStatement(sql)) {
            stmt.setLong(1, deathId);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    rows.add(rs.getString(column));
                }
            }
        }
        return rows;
    }
}
