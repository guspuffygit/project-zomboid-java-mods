package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import net.bytebuddy.pool.TypePool;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import zombie.iso.areas.SafeHouse;

class RespawnTest {
    @TempDir Path directory;

    private Connection database(String name) throws Exception {
        Connection db = DriverManager.getConnection("jdbc:sqlite:" + directory.resolve(name));
        db.setAutoCommit(false);
        try (var q = db.createStatement()) {
            q.executeUpdate(
                    "CREATE TABLE IF NOT EXISTS networkPlayers (id INTEGER PRIMARY KEY,world TEXT,username TEXT,steamid TEXT,playerIndex INTEGER,x REAL,y REAL,z REAL,worldversion INTEGER,isDead INTEGER,name TEXT,splitUsername TEXT,data BLOB)");
        }
        db.commit();
        return db;
    }

    private static AdminCoreRespawnStore.Account account(String name) {
        return new AdminCoreRespawnStore.Account(name, "world", 0, false);
    }

    private static void insert(Connection db, String user, boolean dead, byte[] data)
            throws Exception {
        try (var q =
                db.prepareStatement(
                        "INSERT INTO networkPlayers(world,username,steamid,playerIndex,x,y,z,worldversion,isDead,name,splitUsername,data) VALUES('world',?,'7656119',0,100,100,0,241,?,'Character',?,?)")) {
            q.setString(1, user);
            q.setBoolean(2, dead);
            q.setString(3, user);
            q.setBytes(4, data);
            q.executeUpdate();
        }
        db.commit();
    }

    private static void replace(Connection db, int id, byte[] data) throws Exception {
        try (var q = db.prepareStatement("UPDATE networkPlayers SET isDead=0,data=? WHERE id=?")) {
            q.setBytes(1, data);
            q.setInt(2, id);
            q.executeUpdate();
        }
        db.commit();
    }

    private static AdminCoreRespawnStore.Pending pending(AdminCoreRespawnStore.Profile previous) {
        return new AdminCoreRespawnStore.Pending(
                "ticket", "100:100:20:20:123", "Alice", Long.MAX_VALUE, previous);
    }

    @Test
    void journalRestoresOnlyExactDeadProfileAcrossRestart() throws Exception {
        var account = account("Alice");
        try (var db = database("restart.db")) {
            insert(db, "Alice", true, new byte[] {1, 2, 3});
            insert(db, "Bob", false, new byte[] {9});
            var old = AdminCoreRespawnStore.read(db, account);
            AdminCoreRespawnStore.begin(db, account, pending(old));
            replace(db, old.id(), new byte[] {4, 5, 6});
        }
        try (var db = database("restart.db")) {
            var attempt = AdminCoreRespawnStore.pending(db, account);
            assertTrue(
                    AdminCoreRespawnStore.rollback(
                            db, account, attempt, AdminCoreRespawnStore.read(db, account)));
            assertArrayEquals(new byte[] {1, 2, 3}, AdminCoreRespawnStore.read(db, account).data());
            assertTrue(AdminCoreRespawnStore.read(db, account).dead());
            assertArrayEquals(
                    new byte[] {9}, AdminCoreRespawnStore.read(db, account("Bob")).data());
            assertNull(AdminCoreRespawnStore.pending(db, account));
        }
    }

    @Test
    void newCharacterRollbackDeletesOnlyItsExactRowAndRefusesChangedData() throws Exception {
        try (var db = database("new.db")) {
            var account = account("Alice");
            AdminCoreRespawnStore.begin(db, account, pending(null));
            insert(db, "Alice", false, new byte[] {1});
            insert(db, "Bob", false, new byte[] {7});
            var saved = AdminCoreRespawnStore.read(db, account);
            replace(db, saved.id(), new byte[] {2});
            assertFalse(AdminCoreRespawnStore.rollback(db, account, pending(null), saved));
            assertNotNull(AdminCoreRespawnStore.pending(db, account));
            assertTrue(
                    AdminCoreRespawnStore.rollback(
                            db, account, pending(null), AdminCoreRespawnStore.read(db, account)));
            assertNull(AdminCoreRespawnStore.read(db, account));
            assertArrayEquals(
                    new byte[] {7}, AdminCoreRespawnStore.read(db, account("Bob")).data());
        }
    }

    @Test
    void finalCommitAndJournalCompletionAreOneDurableTransaction() throws Exception {
        var account = account("Alice");
        try (var db = database("commit.db")) {
            insert(db, "Alice", true, new byte[] {1});
            var old = AdminCoreRespawnStore.read(db, account);
            AdminCoreRespawnStore.begin(db, account, pending(old));
            replace(db, old.id(), new byte[] {2});
            assertTrue(
                    AdminCoreRespawnStore.commit(
                            db, account, AdminCoreRespawnStore.read(db, account), new byte[] {3}));
        }
        try (var db = database("commit.db")) {
            assertArrayEquals(new byte[] {3}, AdminCoreRespawnStore.read(db, account).data());
            assertNull(AdminCoreRespawnStore.pending(db, account));
        }
    }

    @Test
    void failedConstructionRecoversOnlyUnchangedPreviousProfile() throws Exception {
        try (var db = database("failed.db")) {
            var account = account("Alice");
            insert(db, "Alice", true, new byte[] {1});
            var old = AdminCoreRespawnStore.read(db, account);
            AdminCoreRespawnStore.begin(db, account, pending(old));
            AdminCoreRespawnStore.recoverUnwritten(db, account);
            assertNull(AdminCoreRespawnStore.pending(db, account));
            AdminCoreRespawnStore.begin(db, account, pending(old));
            replace(db, old.id(), new byte[] {2});
            AdminCoreRespawnStore.recoverUnwritten(db, account);
            assertNotNull(AdminCoreRespawnStore.pending(db, account));
            assertThrows(
                    java.sql.SQLException.class,
                    () -> AdminCoreRespawnStore.begin(db, account, pending(old)));
        }
    }

    @Test
    void livingProfileCannotBeJournaledAndSteamCoopUsesDifferentIdentityColumn() throws Exception {
        try (var db = database("identity.db")) {
            var account = account("Alice");
            insert(db, "Alice", false, new byte[] {1});
            assertThrows(
                    java.sql.SQLException.class,
                    () ->
                            AdminCoreRespawnStore.begin(
                                    db, account, pending(AdminCoreRespawnStore.read(db, account))));
            assertNull(AdminCoreRespawnStore.read(db, account("7656119")));
            assertNotNull(
                    AdminCoreRespawnStore.read(
                            db, new AdminCoreRespawnStore.Account("7656119", "world", 0, true)));
            assertNull(
                    AdminCoreRespawnStore.read(
                            db, new AdminCoreRespawnStore.Account("Alice", "world", 1, false)));
        }
    }

    @Test
    void membershipUsesOwnerOrActualMemberNeverPersistentRespawnFlag() {
        SafeHouse house = new SafeHouse(100, 100, 20, 10, "Alice");
        house.getPlayers().add("Bob");
        house.getPlayersRespawn().add("Mallory");
        assertTrue(AdminCoreRespawnServer.member(house, "Alice"));
        assertTrue(AdminCoreRespawnServer.member(house, "Bob"));
        assertFalse(AdminCoreRespawnServer.member(house, "Mallory"));
        house.getPlayers().remove("Bob");
        assertFalse(AdminCoreRespawnServer.member(house, "Bob"));
        assertEquals(java.util.List.of("Mallory"), house.getPlayersRespawn());
    }

    @Test
    void patchesWeaveActualNativeMethodsAndKeepLegacyPreferencesReadOnly() throws Exception {
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        for (String name :
                java.util.List.of(
                        "zombie.network.GameServer",
                        "zombie.network.packets.character.CreatePlayerPacket",
                        "zombie.network.PacketTypes$PacketType",
                        "zombie.network.GameClient",
                        "zombie.iso.IsoWorld")) {
            byte[] bytes =
                    new AdminCoreRespawnPatch(name)
                            .dynamicType(
                                    locator,
                                    pool,
                                    new ByteBuddy()
                                            .redefine(pool.describe(name).resolve(), locator))
                            .make()
                            .getBytes();
            assertTrue(bytes.length > 0);
            java.util.Set<String> hooks = new java.util.HashSet<>();
            new ClassReader(bytes)
                    .accept(
                            new ClassVisitor(Opcodes.ASM9) {
                                @Override
                                public MethodVisitor visitMethod(
                                        int access,
                                        String method,
                                        String descriptor,
                                        String signature,
                                        String[] exceptions) {
                                    return new MethodVisitor(Opcodes.ASM9) {
                                        @Override
                                        public void visitMethodInsn(
                                                int opcode,
                                                String owner,
                                                String called,
                                                String desc,
                                                boolean itf) {
                                            if (owner.contains("AdminCoreRespawn"))
                                                hooks.add(called);
                                        }
                                    };
                                }
                            },
                            0);
            assertFalse(hooks.isEmpty(), name);
            if (name.endsWith("CreatePlayerPacket"))
                assertTrue(
                        hooks.containsAll(
                                java.util.List.of(
                                        "coordinate", "position", "mark", "begin", "end")));
            if (name.endsWith("GameServer")) assertTrue(hooks.contains("acceptLoaded"));
        }
    }

    @Test
    void missingOrChangedNativeMethodsRejectTransformationInsteadOfSkippingProtection() {
        var system = ClassFileLocator.ForClassLoader.ofSystemLoader();
        for (String name :
                java.util.List.of(
                        "zombie.network.GameServer",
                        "zombie.network.packets.character.CreatePlayerPacket",
                        "zombie.network.PacketTypes$PacketType",
                        "zombie.network.GameClient",
                        "zombie.iso.IsoWorld")) {
            var replacement = new ByteBuddy().subclass(Object.class).name(name).make();
            var locator =
                    new ClassFileLocator.Compound(
                            new ClassFileLocator.Simple(
                                    java.util.Map.of(name, replacement.getBytes())),
                            system);
            var pool = TypePool.Default.of(locator);
            assertThrows(
                    IllegalStateException.class,
                    () ->
                            new AdminCoreRespawnPatch(name)
                                    .dynamicType(
                                            locator,
                                            pool,
                                            new ByteBuddy()
                                                    .redefine(
                                                            pool.describe(name).resolve(),
                                                            locator)));
        }
    }

    @Test
    void realStormConnectionAdviceThenRespawnPatchPassJvmVerificationTogether() throws Exception {
        String name = "zombie.network.GameServer";
        var locator = ClassFileLocator.ForClassLoader.ofSystemLoader();
        var pool = TypePool.Default.of(locator);
        var storm =
                (io.pzstorm.storm.core.StormClassTransformer)
                        Class.forName(
                                        "io.pzstorm.storm.patch.networking.GameServerPlayerConnectionEventsPatch")
                                .getDeclaredConstructor()
                                .newInstance();
        byte[] stormBytes =
                storm.dynamicType(
                                locator,
                                pool,
                                new ByteBuddy().redefine(pool.describe(name).resolve(), locator))
                        .make()
                        .getBytes();
        var composedLocator =
                new ClassFileLocator.Compound(
                        new ClassFileLocator.Simple(java.util.Map.of(name, stormBytes)), locator);
        var composedPool = TypePool.Default.of(composedLocator);
        byte[] combined =
                new AdminCoreRespawnPatch(name)
                        .dynamicType(
                                composedLocator,
                                composedPool,
                                new ByteBuddy()
                                        .redefine(
                                                composedPool.describe(name).resolve(),
                                                composedLocator))
                        .make()
                        .getBytes();
        var calls = new java.util.HashMap<String, Integer>();
        new ClassReader(combined)
                .accept(
                        new ClassVisitor(Opcodes.ASM9) {
                            @Override
                            public MethodVisitor visitMethod(
                                    int access,
                                    String method,
                                    String descriptor,
                                    String signature,
                                    String[] exceptions) {
                                if (!method.equals("receivePlayerConnect")) return null;
                                return new MethodVisitor(Opcodes.ASM9) {
                                    @Override
                                    public void visitMethodInsn(
                                            int opcode,
                                            String owner,
                                            String method,
                                            String descriptor,
                                            boolean itf) {
                                        if (owner.contains("AdminCoreRespawn")
                                                || owner.endsWith("PlayerConnectionEvents"))
                                            calls.merge(method, 1, Integer::sum);
                                    }
                                };
                            }
                        },
                        0);
        assertEquals(2, calls.get("captureLoad"));
        assertEquals(2, calls.get("acceptLoaded"));
        assertEquals(2, calls.get("clearConnect"));
        assertTrue(calls.containsKey("enterConnect"));
        assertTrue(calls.containsKey("exitConnect"));
        assertTrue(calls.containsKey("snapshotPlayers"));
        assertTrue(calls.containsKey("afterPlayerConnect"));
        // Defining and reflecting methods forces real JVM verification without initializing a
        // second game server. ByteBuddy.make()/ASM inspection alone missed the remapped-slot bug.
        Class<?> verified = new NativeVerifier().define(name, combined);
        assertDoesNotThrow(verified::getDeclaredMethods);
    }

    private static final class NativeVerifier extends ClassLoader {
        NativeVerifier() {
            super(RespawnTest.class.getClassLoader());
        }

        Class<?> define(String name, byte[] bytes) {
            return defineClass(name, bytes, 0, bytes.length);
        }
    }
}
