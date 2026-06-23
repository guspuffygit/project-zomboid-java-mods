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
            float hoursSurvived,
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
            stmt.setFloat(6, hoursSurvived);
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
}
