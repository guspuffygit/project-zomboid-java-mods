package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * Owns the SQLite connection and schema for the Survivor Skill Obelisk mod. A new instance is
 * opened per logical operation (mirrors the survivor-leaderboard pattern) so game-thread and
 * worker-thread paths never contend on a shared connection.
 *
 * <p>Schema today captures player identity + perk levels/XP recorded at death. Journals read and
 * VHS watched are intended to live in their own tables once the source data is investigated.
 */
public class SurvivorSkillObeliskDatabase implements AutoCloseable {

    private static final String CREATE_DEATHS =
            """
            CREATE TABLE IF NOT EXISTS deaths (
                id             INTEGER PRIMARY KEY AUTOINCREMENT,
                ts             INTEGER NOT NULL,
                username       TEXT,
                steam_id       INTEGER,
                forename       TEXT,
                surname        TEXT,
                hours_survived REAL,
                zombie_kills   INTEGER,
                x              REAL,
                y              REAL,
                z              REAL
            )""";

    private static final String CREATE_DEATH_SKILLS =
            """
            CREATE TABLE IF NOT EXISTS death_skills (
                id       INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id INTEGER NOT NULL,
                perk     TEXT NOT NULL,
                level    INTEGER NOT NULL,
                xp       REAL NOT NULL,
                FOREIGN KEY (death_id) REFERENCES deaths(id)
            )""";

    private static final String CREATE_DEATH_SKILLS_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_death_skills_death ON death_skills(death_id)";

    private static final String CREATE_DEATH_RECIPES =
            """
            CREATE TABLE IF NOT EXISTS death_recipes (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id    INTEGER NOT NULL,
                recipe_name TEXT NOT NULL,
                FOREIGN KEY (death_id) REFERENCES deaths(id)
            )""";

    private static final String CREATE_DEATH_RECIPES_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_death_recipes_death ON death_recipes(death_id)";

    private static final String CREATE_DEATH_READ_LITERATURE =
            """
            CREATE TABLE IF NOT EXISTS death_read_literature (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id   INTEGER NOT NULL,
                full_type  TEXT NOT NULL,
                pages_read INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (death_id) REFERENCES deaths(id)
            )""";

    private static final String CREATE_DEATH_READ_LITERATURE_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_death_read_literature_death "
                    + "ON death_read_literature(death_id)";

    private static final String CREATE_DEATH_READ_PRINT_MEDIA =
            """
            CREATE TABLE IF NOT EXISTS death_read_print_media (
                id       INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id INTEGER NOT NULL,
                media_id TEXT NOT NULL,
                FOREIGN KEY (death_id) REFERENCES deaths(id)
            )""";

    private static final String CREATE_DEATH_READ_PRINT_MEDIA_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_death_read_print_media_death "
                    + "ON death_read_print_media(death_id)";

    private static final String CREATE_DEATH_WATCHED_MEDIA =
            """
            CREATE TABLE IF NOT EXISTS death_watched_media (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id      INTEGER NOT NULL,
                media_id      TEXT NOT NULL,
                media_index   INTEGER,
                category      TEXT,
                media_type    INTEGER,
                title         TEXT,
                lines_watched INTEGER NOT NULL,
                line_count    INTEGER NOT NULL,
                fully_watched INTEGER NOT NULL,
                FOREIGN KEY (death_id) REFERENCES deaths(id)
            )""";

    private static final String CREATE_DEATH_WATCHED_MEDIA_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_death_watched_media_death "
                    + "ON death_watched_media(death_id)";

    private final Connection connection;

    public SurvivorSkillObeliskDatabase(String dbPath) throws SQLException {
        this.connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA synchronous=NORMAL");
            stmt.execute("PRAGMA foreign_keys=ON");
        }
        createTables();
    }

    private void createTables() throws SQLException {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute(CREATE_DEATHS);
            stmt.execute(CREATE_DEATH_SKILLS);
            stmt.execute(CREATE_DEATH_SKILLS_INDEX);
            stmt.execute(CREATE_DEATH_RECIPES);
            stmt.execute(CREATE_DEATH_RECIPES_INDEX);
            stmt.execute(CREATE_DEATH_READ_LITERATURE);
            stmt.execute(CREATE_DEATH_READ_LITERATURE_INDEX);
            stmt.execute(CREATE_DEATH_READ_PRINT_MEDIA);
            stmt.execute(CREATE_DEATH_READ_PRINT_MEDIA_INDEX);
            stmt.execute(CREATE_DEATH_WATCHED_MEDIA);
            stmt.execute(CREATE_DEATH_WATCHED_MEDIA_INDEX);
        }
    }

    public Connection getConnection() {
        return connection;
    }

    @Override
    public void close() throws SQLException {
        if (connection != null && !connection.isClosed()) {
            connection.close();
        }
    }
}
