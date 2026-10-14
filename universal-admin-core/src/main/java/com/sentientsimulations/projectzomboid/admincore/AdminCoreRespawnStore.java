package com.sentientsimulations.projectzomboid.admincore;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Collections;
import java.util.Set;
import java.util.WeakHashMap;

/** One-attempt journal in the native players database. Never modifies another account/slot. */
final class AdminCoreRespawnStore {
    private static final Set<Connection> INITIALIZED =
            Collections.newSetFromMap(new WeakHashMap<>());

    record Account(String key, String world, int slot, boolean steam) {}

    record Profile(
            int id,
            float x,
            float y,
            float z,
            int version,
            boolean dead,
            String name,
            String splitUsername,
            byte[] data) {}

    record Pending(String token, String house, String username, long expires, Profile previous) {}

    private AdminCoreRespawnStore() {}

    static Profile read(Connection db, Account account) throws SQLException {
        String column = account.steam() ? "steamid" : "username";
        try (PreparedStatement q =
                db.prepareStatement(
                        "SELECT id,x,y,z,worldversion,isDead,name,splitUsername,data FROM networkPlayers WHERE "
                                + column
                                + "=? AND world=? AND playerIndex=?")) {
            q.setString(1, account.key());
            q.setString(2, account.world());
            q.setInt(3, account.slot());
            try (ResultSet r = q.executeQuery()) {
                return r.next() ? profile(r, "") : null;
            }
        }
    }

    private static Profile profile(ResultSet r, String prefix) throws SQLException {
        return new Profile(
                r.getInt(prefix + "id"),
                r.getFloat(prefix + "x"),
                r.getFloat(prefix + "y"),
                r.getFloat(prefix + "z"),
                r.getInt(prefix + "worldversion"),
                r.getBoolean(prefix + "isDead"),
                r.getString(prefix + "name"),
                r.getString(prefix + "splitUsername"),
                r.getBytes(prefix + "data"));
    }

    static void schema(Connection db) throws SQLException {
        if (INITIALIZED.contains(db)) return;
        try (var statement = db.createStatement()) {
            statement.executeUpdate(
                    "CREATE TABLE IF NOT EXISTS uac_respawn_pending (account TEXT NOT NULL,world TEXT NOT NULL,slot INTEGER NOT NULL,steam INTEGER NOT NULL,token TEXT NOT NULL,house TEXT NOT NULL,username TEXT NOT NULL,expires INTEGER NOT NULL,old_id INTEGER,old_x REAL,old_y REAL,old_z REAL,old_worldversion INTEGER,old_isDead INTEGER,old_name TEXT,old_splitUsername TEXT,old_data BLOB,PRIMARY KEY(account,world,slot,steam))");
        }
        db.commit();
        INITIALIZED.add(db);
    }

    static Pending pending(Connection db, Account account) throws SQLException {
        schema(db);
        try (var q =
                db.prepareStatement(
                        "SELECT * FROM uac_respawn_pending WHERE account=? AND world=? AND slot=? AND steam=?")) {
            bind(q, account);
            try (var r = q.executeQuery()) {
                if (!r.next()) return null;
                Profile previous = r.getObject("old_id") == null ? null : profile(r, "old_");
                return new Pending(
                        r.getString("token"),
                        r.getString("house"),
                        r.getString("username"),
                        r.getLong("expires"),
                        previous);
            }
        }
    }

    static void begin(Connection db, Account account, Pending pending) throws SQLException {
        schema(db);
        recoverUnwritten(db, account);
        if (pending(db, account) != null)
            throw new SQLException("An earlier respawn needs recovery.");
        Profile previous = pending.previous();
        if (previous != null && !previous.dead())
            throw new SQLException("Existing character is alive.");
        try (var q =
                db.prepareStatement(
                        "INSERT INTO uac_respawn_pending VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")) {
            bind(q, account);
            q.setString(5, pending.token());
            q.setString(6, pending.house());
            q.setString(7, pending.username());
            q.setLong(8, pending.expires());
            if (previous == null) {
                for (int i = 9; i <= 17; i++) q.setObject(i, null);
            } else {
                q.setInt(9, previous.id());
                q.setFloat(10, previous.x());
                q.setFloat(11, previous.y());
                q.setFloat(12, previous.z());
                q.setInt(13, previous.version());
                q.setBoolean(14, previous.dead());
                q.setString(15, previous.name());
                q.setString(16, previous.splitUsername());
                q.setBytes(17, previous.data());
            }
            q.executeUpdate();
        }
        db.commit();
    }

    static void clear(Connection db, Account account) throws SQLException {
        deletePending(db, account);
        db.commit();
    }

    private static void deletePending(Connection db, Account account) throws SQLException {
        try (var q =
                db.prepareStatement(
                        "DELETE FROM uac_respawn_pending WHERE account=? AND world=? AND slot=? AND steam=?")) {
            bind(q, account);
            q.executeUpdate();
        }
    }

    static boolean same(Profile one, Profile two) {
        return one == null
                ? two == null
                : two != null
                        && one.id() == two.id()
                        && one.dead() == two.dead()
                        && java.util.Arrays.equals(one.data(), two.data());
    }

    static void recoverUnwritten(Connection db, Account account) throws SQLException {
        Pending pending = pending(db, account);
        if (pending != null && same(pending.previous(), read(db, account))) clear(db, account);
    }

    /** Marker removal and journal completion share one SQLite commit, including across restart. */
    static boolean commit(Connection db, Account account, Profile current, byte[] cleanData)
            throws SQLException {
        try (var q =
                db.prepareStatement("UPDATE networkPlayers SET data=? WHERE id=? AND data=?")) {
            q.setBytes(1, cleanData);
            q.setInt(2, current.id());
            q.setBytes(3, current.data());
            if (q.executeUpdate() != 1) {
                db.rollback();
                return false;
            }
            deletePending(db, account);
            db.commit();
            return true;
        } catch (SQLException failure) {
            db.rollback();
            throw failure;
        }
    }

    /** Caller must verify the loaded native character's attempt token before calling this. */
    static boolean rollback(Connection db, Account account, Pending attempt, Profile current)
            throws SQLException {
        if (current == null) {
            clear(db, account);
            return true;
        }
        Profile previous = attempt.previous();
        String sql =
                previous == null
                        ? "DELETE FROM networkPlayers WHERE id=? AND data=?"
                        : "UPDATE networkPlayers SET x=?,y=?,z=?,worldversion=?,isDead=?,name=?,splitUsername=?,data=? WHERE id=? AND data=?";
        try (var q = db.prepareStatement(sql)) {
            int index = 1;
            if (previous != null) {
                if (current.id() != previous.id()) return false;
                q.setFloat(index++, previous.x());
                q.setFloat(index++, previous.y());
                q.setFloat(index++, previous.z());
                q.setInt(index++, previous.version());
                q.setBoolean(index++, previous.dead());
                q.setString(index++, previous.name());
                q.setString(index++, previous.splitUsername());
                q.setBytes(index++, previous.data());
            }
            q.setInt(index++, current.id());
            q.setBytes(index, current.data());
            if (q.executeUpdate() != 1) {
                db.rollback();
                return false;
            }
            // The rollback and journal removal commit together.
            clear(db, account);
            return true;
        } catch (SQLException failure) {
            db.rollback();
            throw failure;
        }
    }

    private static void bind(PreparedStatement q, Account a) throws SQLException {
        q.setString(1, a.key());
        q.setString(2, a.world());
        q.setInt(3, a.slot());
        q.setBoolean(4, a.steam());
    }
}
