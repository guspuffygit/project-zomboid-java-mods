package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
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
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id         INTEGER NOT NULL,
                literature_title TEXT NOT NULL,
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

    private static final String CREATE_DEATH_LEARNED_SONGS =
            """
            CREATE TABLE IF NOT EXISTS death_learned_songs (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id   INTEGER NOT NULL,
                instrument TEXT NOT NULL,
                song_name  TEXT NOT NULL,
                sound      TEXT,
                level      REAL,
                length     REAL,
                isaddon    REAL,
                FOREIGN KEY (death_id) REFERENCES deaths(id)
            )""";

    private static final String CREATE_DEATH_LEARNED_SONGS_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_death_learned_songs_death "
                    + "ON death_learned_songs(death_id)";

    private static final String CREATE_DEATH_AMBITIONS =
            """
            CREATE TABLE IF NOT EXISTS death_ambitions (
                id             INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id       INTEGER NOT NULL,
                name           TEXT NOT NULL,
                category       TEXT,
                completed      INTEGER NOT NULL,
                is_active      INTEGER NOT NULL,
                is_passive     INTEGER NOT NULL,
                goal1          TEXT,
                goal2          TEXT,
                goal3          TEXT,
                goal4          TEXT,
                goal5          TEXT,
                goal6          TEXT,
                goal1_progress TEXT,
                goal2_progress TEXT,
                goal3_progress TEXT,
                goal4_progress TEXT,
                goal5_progress TEXT,
                goal6_progress TEXT,
                FOREIGN KEY (death_id) REFERENCES deaths(id)
            )""";

    private static final String CREATE_DEATH_AMBITIONS_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_death_ambitions_death "
                    + "ON death_ambitions(death_id)";

    private static final String CREATE_DEATH_HIDDEN_SKILLS =
            """
            CREATE TABLE IF NOT EXISTS death_hidden_skills (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                death_id          INTEGER NOT NULL,
                skill             TEXT NOT NULL,
                level             INTEGER NOT NULL,
                xp                REAL NOT NULL,
                xp_for_next_level REAL NOT NULL,
                FOREIGN KEY (death_id) REFERENCES deaths(id)
            )""";

    private static final String CREATE_DEATH_HIDDEN_SKILLS_INDEX =
            "CREATE INDEX IF NOT EXISTS idx_death_hidden_skills_death "
                    + "ON death_hidden_skills(death_id)";

    private static final String CREATE_RECOVERIES =
            """
            CREATE TABLE IF NOT EXISTS recoveries (
                steam_id INTEGER NOT NULL,
                username TEXT NOT NULL,
                death_id INTEGER NOT NULL,
                ts       INTEGER NOT NULL,
                PRIMARY KEY (steam_id, username)
            )""";

    private static final String CREATE_RECOVERY_SKILLS =
            """
            CREATE TABLE IF NOT EXISTS recovery_skills (
                steam_id INTEGER NOT NULL,
                username TEXT NOT NULL,
                perk     TEXT NOT NULL,
                xp       REAL NOT NULL,
                PRIMARY KEY (steam_id, username, perk)
            )""";

    private static final String CREATE_OBELISK_TYPES =
            """
            CREATE TABLE IF NOT EXISTS obelisk_types (
                x                 INTEGER NOT NULL,
                y                 INTEGER NOT NULL,
                z                 INTEGER NOT NULL,
                type              TEXT NOT NULL,
                set_by_username   TEXT,
                set_by_steam_id   INTEGER,
                set_ts            INTEGER NOT NULL,
                PRIMARY KEY (x, y, z)
            )""";

    private final Connection connection;

    public SurvivorSkillObeliskDatabase(String dbPath) throws SQLException {
        this.connection = DriverManager.getConnection("jdbc:sqlite:" + dbPath);
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("PRAGMA journal_mode=WAL");
            stmt.execute("PRAGMA synchronous=NORMAL");
            stmt.execute("PRAGMA foreign_keys=ON");
        }
        createTables();
        migrate();
    }

    /**
     * In-place upgrades for DBs created by earlier releases. {@code CREATE TABLE IF NOT EXISTS}
     * never touches an existing table, so columns added to the schema constants above must also be
     * ALTERed in here for saves that already have the old shape.
     */
    private void migrate() throws SQLException {
        addColumnIfMissing("death_learned_songs", "level", "REAL");
        addColumnIfMissing("death_learned_songs", "length", "REAL");
        addColumnIfMissing("death_learned_songs", "isaddon", "REAL");
    }

    private void addColumnIfMissing(String table, String column, String type) throws SQLException {
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery("PRAGMA table_info(" + table + ")")) {
            while (rs.next()) {
                if (column.equalsIgnoreCase(rs.getString("name"))) {
                    return;
                }
            }
        }
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("ALTER TABLE " + table + " ADD COLUMN " + column + " " + type);
        }
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
            stmt.execute(CREATE_DEATH_LEARNED_SONGS);
            stmt.execute(CREATE_DEATH_LEARNED_SONGS_INDEX);
            stmt.execute(CREATE_DEATH_AMBITIONS);
            stmt.execute(CREATE_DEATH_AMBITIONS_INDEX);
            stmt.execute(CREATE_DEATH_HIDDEN_SKILLS);
            stmt.execute(CREATE_DEATH_HIDDEN_SKILLS_INDEX);
            stmt.execute(CREATE_RECOVERIES);
            stmt.execute(CREATE_RECOVERY_SKILLS);
            stmt.execute(CREATE_OBELISK_TYPES);
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
