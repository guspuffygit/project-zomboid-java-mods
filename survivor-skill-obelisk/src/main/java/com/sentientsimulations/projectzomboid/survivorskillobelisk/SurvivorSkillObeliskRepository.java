package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

/** All SQL for the Survivor Skill Obelisk mod. Holds no business logic. */
public class SurvivorSkillObeliskRepository {

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
            INSERT INTO death_learned_songs (death_id, instrument, song_name, sound)
            VALUES (?, ?, ?, ?)""";

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

    public void insertLearnedSong(long deathId, String instrument, String songName, String sound)
            throws SQLException {
        try (PreparedStatement stmt = connection.prepareStatement(INSERT_LEARNED_SONG)) {
            stmt.setLong(1, deathId);
            stmt.setString(2, instrument);
            stmt.setString(3, songName);
            stmt.setString(4, sound);
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
}
