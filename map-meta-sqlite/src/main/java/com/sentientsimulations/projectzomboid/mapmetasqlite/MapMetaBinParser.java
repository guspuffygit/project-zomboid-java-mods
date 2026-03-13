package com.sentientsimulations.projectzomboid.mapmetasqlite;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.BufferUnderflowException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

public class MapMetaBinParser {

    private static final int MAX_SANE_COUNT = 100_000;
    private static final int CURRENT_WORLD_VERSION = 244;

    // ===== Data Records =====

    public record Header(
            String magic, int worldVersion, int minX, int minY, int maxX, int maxY) {
        public int gridWidth() {
            return maxX - minX + 1;
        }

        public int gridHeight() {
            return maxY - minY + 1;
        }

        public int totalCells() {
            return gridWidth() * gridHeight();
        }
    }

    public record RoomData(
            long metaId, boolean explored, boolean lightsActive, boolean doneSpawn,
            boolean roofFixed) {}

    public record BuildingData(
            long metaId, boolean alarmed, int keyId, boolean seen, boolean hasBeenVisited,
            int lootRespawnHour, int alarmDecay) {}

    public record CellData(int x, int y, List<RoomData> rooms, List<BuildingData> buildings) {}

    public record SafeHouseData(
            int x, int y, int w, int h, String owner, int hitPoints, List<String> players,
            long lastVisited, String title, long datetimeCreated, String location,
            List<String> playersRespawn) {}

    public record NonPvpZoneData(int x, int y, int x2, int y2, int size, String title) {}

    public record FactionData(
            String name, String owner, List<String> players, boolean hasTag, String tag,
            float tagR, float tagG, float tagB) {}

    public record DesignationZoneData(
            double id, int x, int y, int z, int h, int w, String type, String name,
            int hourLastSeen) {}

    public record StashBuildingData(String stashName, int buildingX, int buildingY) {}

    public record StashSystemData(
            List<StashBuildingData> possibleStashes, List<StashBuildingData> buildingsToDo,
            List<String> alreadyReadMap) {}

    public record ParseError(String section, int offset, String message) {}

    public record ParseResult(
            String file,
            long fileSize,
            Header header,
            List<CellData> cells,
            int expectedCells,
            List<SafeHouseData> safehouses,
            List<NonPvpZoneData> nonPvpZones,
            List<FactionData> factions,
            List<DesignationZoneData> designationZones,
            StashSystemData stashSystem,
            List<String> uniqueRdsSpawned,
            List<ParseError> errors) {}

    // ===== String I/O =====

    static String readString(ByteBuffer buf) {
        int numBytes = buf.getShort() & 0xFFFF;
        if (numBytes == 0) return "";
        if (numBytes > buf.remaining()) {
            throw new BufferUnderflowException();
        }
        byte[] bytes = new byte[numBytes];
        buf.get(bytes);
        return new String(bytes, StandardCharsets.UTF_8);
    }

    static void writeString(ByteBuffer buf, String str) {
        if (str == null || str.isEmpty()) {
            buf.putShort((short) 0);
        } else {
            byte[] bytes = str.getBytes(StandardCharsets.UTF_8);
            buf.putShort((short) bytes.length);
            buf.put(bytes);
        }
    }

    // ===== Sanity Checking =====

    private static void checkCount(int count, String context) {
        if (count < 0 || count > MAX_SANE_COUNT) {
            throw new IllegalStateException(
                    "Insane count " + count + " for " + context + " (likely corruption)");
        }
    }

    // ===== Parse Methods =====

    static Header parseHeader(ByteBuffer buf) {
        byte b1 = buf.get();
        byte b2 = buf.get();
        byte b3 = buf.get();
        byte b4 = buf.get();
        String magic = "" + (char) b1 + (char) b2 + (char) b3 + (char) b4;
        int worldVersion = buf.getInt();
        int minX = buf.getInt();
        int minY = buf.getInt();
        int maxX = buf.getInt();
        int maxY = buf.getInt();
        return new Header(magic, worldVersion, minX, minY, maxX, maxY);
    }

    static List<CellData> parseCells(
            ByteBuffer buf, int worldVersion, int minX, int minY, int maxX, int maxY) {
        List<CellData> cells = new ArrayList<>();
        for (int x = minX; x <= maxX; x++) {
            for (int y = minY; y <= maxY; y++) {
                int numRooms = buf.getInt();
                checkCount(numRooms, "rooms in cell " + x + "," + y);

                List<RoomData> rooms = new ArrayList<>(numRooms);
                for (int i = 0; i < numRooms; i++) {
                    long metaId = buf.getLong();
                    short flags = buf.getShort();
                    rooms.add(
                            new RoomData(
                                    metaId,
                                    (flags & 1) != 0,
                                    (flags & 2) != 0,
                                    (flags & 4) != 0,
                                    (flags & 8) != 0));
                }

                int numBuildings = buf.getInt();
                checkCount(numBuildings, "buildings in cell " + x + "," + y);

                List<BuildingData> buildings = new ArrayList<>(numBuildings);
                for (int i = 0; i < numBuildings; i++) {
                    long metaId = buf.getLong();
                    boolean alarmed = buf.get() != 0;
                    int keyId = buf.getInt();
                    boolean seen = buf.get() != 0;
                    boolean hasBeenVisited = buf.get() != 0;
                    int lootRespawnHour = buf.getInt();
                    int alarmDecay = worldVersion >= 201 ? buf.getInt() : 0;
                    buildings.add(
                            new BuildingData(
                                    metaId, alarmed, keyId, seen, hasBeenVisited, lootRespawnHour,
                                    alarmDecay));
                }

                cells.add(new CellData(x, y, rooms, buildings));
            }
        }
        return cells;
    }

    static SafeHouseData parseSafeHouse(ByteBuffer buf, int worldVersion) {
        int x = buf.getInt();
        int y = buf.getInt();
        int w = buf.getInt();
        int h = buf.getInt();
        String owner = readString(buf);
        int hitPoints = worldVersion >= 216 ? buf.getInt() : 0;
        int playerCount = buf.getInt();
        checkCount(playerCount, "safehouse players");
        List<String> players = new ArrayList<>(playerCount);
        for (int i = 0; i < playerCount; i++) {
            players.add(readString(buf));
        }
        long lastVisited = buf.getLong();
        String title = readString(buf);
        long datetimeCreated = worldVersion >= 223 ? buf.getLong() : 0;
        String location = worldVersion >= 223 ? readString(buf) : null;
        int respawnCount = buf.getInt();
        checkCount(respawnCount, "safehouse respawns");
        List<String> playersRespawn = new ArrayList<>(respawnCount);
        for (int i = 0; i < respawnCount; i++) {
            playersRespawn.add(readString(buf));
        }
        return new SafeHouseData(
                x, y, w, h, owner, hitPoints, players, lastVisited, title, datetimeCreated,
                location, playersRespawn);
    }

    static NonPvpZoneData parseNonPvpZone(ByteBuffer buf) {
        return new NonPvpZoneData(
                buf.getInt(), buf.getInt(), buf.getInt(), buf.getInt(), buf.getInt(),
                readString(buf));
    }

    static FactionData parseFaction(ByteBuffer buf) {
        String name = readString(buf);
        String owner = readString(buf);
        int playerSize = buf.getInt();
        checkCount(playerSize, "faction players");
        boolean hasTag = buf.get() != 0;
        String tag = null;
        float r = 0, g = 0, b = 0;
        if (hasTag) {
            tag = readString(buf);
            r = buf.getFloat();
            g = buf.getFloat();
            b = buf.getFloat();
        }
        List<String> players = new ArrayList<>(playerSize);
        for (int i = 0; i < playerSize; i++) {
            players.add(readString(buf));
        }
        return new FactionData(name, owner, players, hasTag, tag, r, g, b);
    }

    static DesignationZoneData parseDesignationZone(ByteBuffer buf) {
        return new DesignationZoneData(
                buf.getDouble(),
                buf.getInt(),
                buf.getInt(),
                buf.getInt(),
                buf.getInt(),
                buf.getInt(),
                readString(buf),
                readString(buf),
                buf.getInt());
    }

    static StashSystemData parseStashSystem(ByteBuffer buf) {
        int nPossible = buf.getInt();
        checkCount(nPossible, "possible stashes");
        List<StashBuildingData> possibleStashes = new ArrayList<>(nPossible);
        for (int i = 0; i < nPossible; i++) {
            possibleStashes.add(new StashBuildingData(readString(buf), buf.getInt(), buf.getInt()));
        }

        int nToDo = buf.getInt();
        checkCount(nToDo, "buildings to do");
        List<StashBuildingData> buildingsToDo = new ArrayList<>(nToDo);
        for (int i = 0; i < nToDo; i++) {
            buildingsToDo.add(new StashBuildingData(readString(buf), buf.getInt(), buf.getInt()));
        }

        int nRead = buf.getInt();
        checkCount(nRead, "already read maps");
        List<String> alreadyReadMap = new ArrayList<>(nRead);
        for (int i = 0; i < nRead; i++) {
            alreadyReadMap.add(readString(buf));
        }

        return new StashSystemData(possibleStashes, buildingsToDo, alreadyReadMap);
    }

    // ===== Top-level Parse =====

    public static ParseResult parse(ByteBuffer buf, String fileName) {
        long fileSize = buf.remaining();
        List<ParseError> errors = new ArrayList<>();

        // Header (required)
        Header header;
        try {
            header = parseHeader(buf);
        } catch (Exception e) {
            errors.add(new ParseError("header", buf.position(), e.getMessage()));
            return new ParseResult(
                    fileName, fileSize, null, List.of(), 0, List.of(), List.of(), List.of(),
                    List.of(), null, List.of(), errors);
        }

        if (!"META".equals(header.magic())) {
            errors.add(new ParseError("header", 0, "Invalid magic: " + header.magic()));
            return new ParseResult(
                    fileName, fileSize, header, List.of(), 0, List.of(), List.of(), List.of(),
                    List.of(), null, List.of(), errors);
        }

        int expectedCells = header.totalCells();
        int worldVersion = header.worldVersion();

        // Cells
        List<CellData> cells = List.of();
        try {
            cells =
                    parseCells(
                            buf, worldVersion, header.minX(), header.minY(), header.maxX(),
                            header.maxY());
        } catch (Exception e) {
            errors.add(new ParseError("cells", buf.position(), e.getMessage()));
        }

        // SafeHouses
        List<SafeHouseData> safehouses = List.of();
        if (errors.isEmpty()) {
            try {
                int count = buf.getInt();
                checkCount(count, "safehouses");
                safehouses = new ArrayList<>(count);
                for (int i = 0; i < count; i++) {
                    safehouses.add(parseSafeHouse(buf, worldVersion));
                }
            } catch (Exception e) {
                errors.add(new ParseError("safehouses", buf.position(), e.getMessage()));
            }
        }

        // NonPvpZones
        List<NonPvpZoneData> nonPvpZones = List.of();
        if (errors.isEmpty()) {
            try {
                int count = buf.getInt();
                checkCount(count, "nonPvpZones");
                nonPvpZones = new ArrayList<>(count);
                for (int i = 0; i < count; i++) {
                    nonPvpZones.add(parseNonPvpZone(buf));
                }
            } catch (Exception e) {
                errors.add(new ParseError("nonPvpZones", buf.position(), e.getMessage()));
            }
        }

        // Factions
        List<FactionData> factions = List.of();
        if (errors.isEmpty()) {
            try {
                int count = buf.getInt();
                checkCount(count, "factions");
                factions = new ArrayList<>(count);
                for (int i = 0; i < count; i++) {
                    factions.add(parseFaction(buf));
                }
            } catch (Exception e) {
                errors.add(new ParseError("factions", buf.position(), e.getMessage()));
            }
        }

        // DesignationZones
        List<DesignationZoneData> designationZones = List.of();
        if (errors.isEmpty()) {
            try {
                int count = buf.getInt();
                checkCount(count, "designationZones");
                designationZones = new ArrayList<>(count);
                for (int i = 0; i < count; i++) {
                    designationZones.add(parseDesignationZone(buf));
                }
            } catch (Exception e) {
                errors.add(new ParseError("designationZones", buf.position(), e.getMessage()));
            }
        }

        // StashSystem — try SP format first (no skip pointer), fall back to server format
        StashSystemData stashSystem = null;
        if (errors.isEmpty() && buf.hasRemaining()) {
            int savedPos = buf.position();
            try {
                // Try SP format (stash data directly)
                stashSystem = parseStashSystem(buf);
            } catch (Exception e1) {
                // Try server format (skip pointer + stash data)
                buf.position(savedPos);
                try {
                    int skipPosition = buf.getInt(); // skip pointer
                    stashSystem = parseStashSystem(buf);
                } catch (Exception e2) {
                    errors.add(
                            new ParseError(
                                    "stashSystem", savedPos,
                                    "SP parse: " + e1.getMessage() + "; Server parse: "
                                            + e2.getMessage()));
                }
            }
        }

        // UniqueRDSSpawned
        List<String> uniqueRdsSpawned = List.of();
        if (errors.isEmpty() && buf.hasRemaining()) {
            try {
                int count = buf.getInt();
                checkCount(count, "uniqueRdsSpawned");
                uniqueRdsSpawned = new ArrayList<>(count);
                for (int i = 0; i < count; i++) {
                    uniqueRdsSpawned.add(readString(buf));
                }
            } catch (Exception e) {
                errors.add(new ParseError("uniqueRdsSpawned", buf.position(), e.getMessage()));
            }
        }

        return new ParseResult(
                fileName, fileSize, header, cells, expectedCells, safehouses, nonPvpZones, factions,
                designationZones, stashSystem, uniqueRdsSpawned, errors);
    }

    // ===== Write/Repair Methods =====

    static void writeHeader(ByteBuffer buf, Header header) {
        buf.put((byte) 'M');
        buf.put((byte) 'E');
        buf.put((byte) 'T');
        buf.put((byte) 'A');
        buf.putInt(CURRENT_WORLD_VERSION);
        buf.putInt(header.minX());
        buf.putInt(header.minY());
        buf.putInt(header.maxX());
        buf.putInt(header.maxY());
    }

    static void writeCells(ByteBuffer buf, List<CellData> cells, Header header) {
        int cellIndex = 0;
        for (int x = header.minX(); x <= header.maxX(); x++) {
            for (int y = header.minY(); y <= header.maxY(); y++) {
                CellData cell = cellIndex < cells.size() ? cells.get(cellIndex) : null;
                cellIndex++;

                if (cell != null && cell.x() == x && cell.y() == y) {
                    // Write recovered rooms
                    buf.putInt(cell.rooms().size());
                    for (RoomData room : cell.rooms()) {
                        buf.putLong(room.metaId());
                        short flags = 0;
                        if (room.explored()) flags |= 1;
                        if (room.lightsActive()) flags |= 2;
                        if (room.doneSpawn()) flags |= 4;
                        if (room.roofFixed()) flags |= 8;
                        buf.putShort(flags);
                    }
                    // Write recovered buildings
                    buf.putInt(cell.buildings().size());
                    for (BuildingData bld : cell.buildings()) {
                        buf.putLong(bld.metaId());
                        buf.put((byte) (bld.alarmed() ? 1 : 0));
                        buf.putInt(bld.keyId());
                        buf.put((byte) (bld.seen() ? 1 : 0));
                        buf.put((byte) (bld.hasBeenVisited() ? 1 : 0));
                        buf.putInt(bld.lootRespawnHour());
                        buf.putInt(bld.alarmDecay());
                    }
                } else {
                    // Empty cell (unrecovered)
                    buf.putInt(0); // 0 rooms
                    buf.putInt(0); // 0 buildings
                    if (cell != null) cellIndex--; // didn't consume this cell
                }
            }
        }
    }

    static void writeSafeHouse(ByteBuffer buf, SafeHouseData sh) {
        buf.putInt(sh.x());
        buf.putInt(sh.y());
        buf.putInt(sh.w());
        buf.putInt(sh.h());
        writeString(buf, sh.owner());
        buf.putInt(sh.hitPoints());
        buf.putInt(sh.players().size());
        for (String player : sh.players()) {
            writeString(buf, player);
        }
        buf.putLong(sh.lastVisited());
        writeString(buf, sh.title());
        buf.putLong(sh.datetimeCreated());
        writeString(buf, sh.location());
        buf.putInt(sh.playersRespawn().size());
        for (String player : sh.playersRespawn()) {
            writeString(buf, player);
        }
    }

    static void writeNonPvpZone(ByteBuffer buf, NonPvpZoneData zone) {
        buf.putInt(zone.x());
        buf.putInt(zone.y());
        buf.putInt(zone.x2());
        buf.putInt(zone.y2());
        buf.putInt(zone.size());
        writeString(buf, zone.title());
    }

    static void writeFaction(ByteBuffer buf, FactionData faction) {
        writeString(buf, faction.name());
        writeString(buf, faction.owner());
        buf.putInt(faction.players().size());
        if (faction.hasTag()) {
            buf.put((byte) 1);
            writeString(buf, faction.tag());
            buf.putFloat(faction.tagR());
            buf.putFloat(faction.tagG());
            buf.putFloat(faction.tagB());
        } else {
            buf.put((byte) 0);
        }
        for (String player : faction.players()) {
            writeString(buf, player);
        }
    }

    static void writeDesignationZone(ByteBuffer buf, DesignationZoneData zone) {
        buf.putDouble(zone.id());
        buf.putInt(zone.x());
        buf.putInt(zone.y());
        buf.putInt(zone.z());
        buf.putInt(zone.h());
        buf.putInt(zone.w());
        writeString(buf, zone.type());
        writeString(buf, zone.name());
        buf.putInt(zone.hourLastSeen());
    }

    static void writeStashSystem(ByteBuffer buf, StashSystemData stash) {
        if (stash == null) {
            buf.putInt(0); // possibleStashes
            buf.putInt(0); // buildingsToDo
            buf.putInt(0); // alreadyReadMap
            return;
        }
        buf.putInt(stash.possibleStashes().size());
        for (StashBuildingData sb : stash.possibleStashes()) {
            writeString(buf, sb.stashName());
            buf.putInt(sb.buildingX());
            buf.putInt(sb.buildingY());
        }
        buf.putInt(stash.buildingsToDo().size());
        for (StashBuildingData sb : stash.buildingsToDo()) {
            writeString(buf, sb.stashName());
            buf.putInt(sb.buildingX());
            buf.putInt(sb.buildingY());
        }
        buf.putInt(stash.alreadyReadMap().size());
        for (String s : stash.alreadyReadMap()) {
            writeString(buf, s);
        }
    }

    public static ByteBuffer repair(ParseResult result) {
        if (result.header() == null) {
            throw new IllegalStateException("Cannot repair: header is missing");
        }

        // Allocate generously
        ByteBuffer buf = ByteBuffer.allocate((int) Math.max(result.fileSize() * 2, 65536));
        Header header = result.header();

        writeHeader(buf, header);
        writeCells(buf, result.cells(), header);

        // SafeHouses
        buf.putInt(result.safehouses().size());
        for (SafeHouseData sh : result.safehouses()) {
            writeSafeHouse(buf, sh);
        }

        // NonPvpZones
        buf.putInt(result.nonPvpZones().size());
        for (NonPvpZoneData zone : result.nonPvpZones()) {
            writeNonPvpZone(buf, zone);
        }

        // Factions
        buf.putInt(result.factions().size());
        for (FactionData faction : result.factions()) {
            writeFaction(buf, faction);
        }

        // DesignationZones
        buf.putInt(result.designationZones().size());
        for (DesignationZoneData zone : result.designationZones()) {
            writeDesignationZone(buf, zone);
        }

        // StashSystem (write SP format — no skip pointer)
        writeStashSystem(buf, result.stashSystem());

        // UniqueRDSSpawned
        buf.putInt(result.uniqueRdsSpawned().size());
        for (String s : result.uniqueRdsSpawned()) {
            writeString(buf, s);
        }

        buf.flip();
        return buf;
    }

    // ===== JSON Output =====

    public static String toJson(ParseResult result) {
        StringBuilder sb = new StringBuilder();
        sb.append("{\n");
        jsonField(sb, 1, "file", result.file());
        sb.append(",\n");
        jsonField(sb, 1, "fileSize", result.fileSize());
        sb.append(",\n");

        // Header
        indent(sb, 1);
        sb.append("\"header\": ");
        if (result.header() != null) {
            Header h = result.header();
            sb.append("{ \"magic\": \"").append(jsonEscape(h.magic())).append("\"");
            sb.append(", \"worldVersion\": ").append(h.worldVersion());
            sb.append(", \"minX\": ").append(h.minX());
            sb.append(", \"minY\": ").append(h.minY());
            sb.append(", \"maxX\": ").append(h.maxX());
            sb.append(", \"maxY\": ").append(h.maxY());
            sb.append(" }");
        } else {
            sb.append("null");
        }
        sb.append(",\n");

        // Cells summary
        int totalRooms = result.cells().stream().mapToInt(c -> c.rooms().size()).sum();
        int totalBuildings = result.cells().stream().mapToInt(c -> c.buildings().size()).sum();
        indent(sb, 1);
        sb.append("\"cells\": { \"expected\": ").append(result.expectedCells());
        sb.append(", \"parsed\": ").append(result.cells().size());
        sb.append(", \"totalRooms\": ").append(totalRooms);
        sb.append(", \"totalBuildings\": ").append(totalBuildings);
        sb.append(" },\n");

        // SafeHouses
        indent(sb, 1);
        sb.append("\"safehouses\": ");
        jsonArraySafehouses(sb, result.safehouses());
        sb.append(",\n");

        // NonPvpZones
        indent(sb, 1);
        sb.append("\"nonPvpZones\": ");
        jsonArrayNonPvpZones(sb, result.nonPvpZones());
        sb.append(",\n");

        // Factions
        indent(sb, 1);
        sb.append("\"factions\": ");
        jsonArrayFactions(sb, result.factions());
        sb.append(",\n");

        // DesignationZones
        indent(sb, 1);
        sb.append("\"designationZones\": ");
        jsonArrayDesignationZones(sb, result.designationZones());
        sb.append(",\n");

        // StashSystem
        indent(sb, 1);
        sb.append("\"stashSystem\": ");
        if (result.stashSystem() != null) {
            jsonStashSystem(sb, result.stashSystem());
        } else {
            sb.append("null");
        }
        sb.append(",\n");

        // UniqueRDSSpawned
        indent(sb, 1);
        sb.append("\"uniqueRdsSpawned\": ");
        jsonStringArray(sb, result.uniqueRdsSpawned());
        sb.append(",\n");

        // Errors
        indent(sb, 1);
        sb.append("\"errors\": ");
        jsonArrayErrors(sb, result.errors());
        sb.append("\n}\n");

        return sb.toString();
    }

    private static void jsonField(StringBuilder sb, int depth, String key, String value) {
        indent(sb, depth);
        sb.append("\"").append(key).append("\": \"").append(jsonEscape(value)).append("\"");
    }

    private static void jsonField(StringBuilder sb, int depth, String key, long value) {
        indent(sb, depth);
        sb.append("\"").append(key).append("\": ").append(value);
    }

    private static void indent(StringBuilder sb, int depth) {
        for (int i = 0; i < depth; i++) sb.append("  ");
    }

    private static String jsonEscape(String s) {
        if (s == null) return "null";
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }

    private static void jsonStringArray(StringBuilder sb, List<String> items) {
        sb.append("[");
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) sb.append(", ");
            sb.append("\"").append(jsonEscape(items.get(i))).append("\"");
        }
        sb.append("]");
    }

    private static void jsonArraySafehouses(StringBuilder sb, List<SafeHouseData> items) {
        if (items.isEmpty()) {
            sb.append("[]");
            return;
        }
        sb.append("[\n");
        for (int i = 0; i < items.size(); i++) {
            SafeHouseData sh = items.get(i);
            indent(sb, 2);
            sb.append("{ \"x\": ").append(sh.x());
            sb.append(", \"y\": ").append(sh.y());
            sb.append(", \"w\": ").append(sh.w());
            sb.append(", \"h\": ").append(sh.h());
            sb.append(", \"owner\": \"").append(jsonEscape(sh.owner())).append("\"");
            sb.append(", \"hitPoints\": ").append(sh.hitPoints());
            sb.append(", \"players\": ");
            jsonStringArray(sb, sh.players());
            sb.append(", \"lastVisited\": ").append(sh.lastVisited());
            sb.append(", \"title\": \"").append(jsonEscape(sh.title())).append("\"");
            sb.append(", \"datetimeCreated\": ").append(sh.datetimeCreated());
            sb.append(", \"location\": ");
            if (sh.location() != null)
                sb.append("\"").append(jsonEscape(sh.location())).append("\"");
            else sb.append("null");
            sb.append(", \"playersRespawn\": ");
            jsonStringArray(sb, sh.playersRespawn());
            sb.append(" }");
            if (i < items.size() - 1) sb.append(",");
            sb.append("\n");
        }
        indent(sb, 1);
        sb.append("]");
    }

    private static void jsonArrayNonPvpZones(StringBuilder sb, List<NonPvpZoneData> items) {
        if (items.isEmpty()) {
            sb.append("[]");
            return;
        }
        sb.append("[\n");
        for (int i = 0; i < items.size(); i++) {
            NonPvpZoneData z = items.get(i);
            indent(sb, 2);
            sb.append("{ \"x\": ").append(z.x());
            sb.append(", \"y\": ").append(z.y());
            sb.append(", \"x2\": ").append(z.x2());
            sb.append(", \"y2\": ").append(z.y2());
            sb.append(", \"size\": ").append(z.size());
            sb.append(", \"title\": \"").append(jsonEscape(z.title())).append("\" }");
            if (i < items.size() - 1) sb.append(",");
            sb.append("\n");
        }
        indent(sb, 1);
        sb.append("]");
    }

    private static void jsonArrayFactions(StringBuilder sb, List<FactionData> items) {
        if (items.isEmpty()) {
            sb.append("[]");
            return;
        }
        sb.append("[\n");
        for (int i = 0; i < items.size(); i++) {
            FactionData f = items.get(i);
            indent(sb, 2);
            sb.append("{ \"name\": \"").append(jsonEscape(f.name())).append("\"");
            sb.append(", \"owner\": \"").append(jsonEscape(f.owner())).append("\"");
            sb.append(", \"players\": ");
            jsonStringArray(sb, f.players());
            if (f.hasTag()) {
                sb.append(", \"tag\": \"").append(jsonEscape(f.tag())).append("\"");
                sb.append(", \"tagColor\": [")
                        .append(f.tagR())
                        .append(", ")
                        .append(f.tagG())
                        .append(", ")
                        .append(f.tagB())
                        .append("]");
            }
            sb.append(" }");
            if (i < items.size() - 1) sb.append(",");
            sb.append("\n");
        }
        indent(sb, 1);
        sb.append("]");
    }

    private static void jsonArrayDesignationZones(
            StringBuilder sb, List<DesignationZoneData> items) {
        if (items.isEmpty()) {
            sb.append("[]");
            return;
        }
        sb.append("[\n");
        for (int i = 0; i < items.size(); i++) {
            DesignationZoneData z = items.get(i);
            indent(sb, 2);
            sb.append("{ \"id\": ").append(z.id());
            sb.append(", \"x\": ").append(z.x());
            sb.append(", \"y\": ").append(z.y());
            sb.append(", \"z\": ").append(z.z());
            sb.append(", \"h\": ").append(z.h());
            sb.append(", \"w\": ").append(z.w());
            sb.append(", \"type\": \"").append(jsonEscape(z.type())).append("\"");
            sb.append(", \"name\": \"").append(jsonEscape(z.name())).append("\"");
            sb.append(", \"hourLastSeen\": ").append(z.hourLastSeen());
            sb.append(" }");
            if (i < items.size() - 1) sb.append(",");
            sb.append("\n");
        }
        indent(sb, 1);
        sb.append("]");
    }

    private static void jsonStashSystem(StringBuilder sb, StashSystemData stash) {
        sb.append("{\n");
        indent(sb, 2);
        sb.append("\"possibleStashes\": [");
        for (int i = 0; i < stash.possibleStashes().size(); i++) {
            StashBuildingData s = stash.possibleStashes().get(i);
            if (i > 0) sb.append(", ");
            sb.append("{ \"name\": \"")
                    .append(jsonEscape(s.stashName()))
                    .append("\", \"x\": ")
                    .append(s.buildingX())
                    .append(", \"y\": ")
                    .append(s.buildingY())
                    .append(" }");
        }
        sb.append("],\n");
        indent(sb, 2);
        sb.append("\"buildingsToDo\": [");
        for (int i = 0; i < stash.buildingsToDo().size(); i++) {
            StashBuildingData s = stash.buildingsToDo().get(i);
            if (i > 0) sb.append(", ");
            sb.append("{ \"name\": \"")
                    .append(jsonEscape(s.stashName()))
                    .append("\", \"x\": ")
                    .append(s.buildingX())
                    .append(", \"y\": ")
                    .append(s.buildingY())
                    .append(" }");
        }
        sb.append("],\n");
        indent(sb, 2);
        sb.append("\"alreadyReadMap\": ");
        jsonStringArray(sb, stash.alreadyReadMap());
        sb.append("\n");
        indent(sb, 1);
        sb.append("}");
    }

    private static void jsonArrayErrors(StringBuilder sb, List<ParseError> errors) {
        if (errors.isEmpty()) {
            sb.append("[]");
            return;
        }
        sb.append("[\n");
        for (int i = 0; i < errors.size(); i++) {
            ParseError e = errors.get(i);
            indent(sb, 2);
            sb.append("{ \"section\": \"").append(jsonEscape(e.section())).append("\"");
            sb.append(", \"offset\": ").append(e.offset());
            sb.append(", \"message\": \"").append(jsonEscape(e.message())).append("\" }");
            if (i < errors.size() - 1) sb.append(",");
            sb.append("\n");
        }
        indent(sb, 1);
        sb.append("]");
    }

    // ===== Main =====

    public static void main(String[] args) throws IOException {
        if (args.length < 1) {
            System.err.println("Usage: MapMetaBinParser <path/to/map_meta.bin>");
            System.exit(1);
        }

        File inputFile = new File(args[0]);
        if (!inputFile.exists()) {
            System.err.println("File not found: " + inputFile.getAbsolutePath());
            System.exit(1);
        }

        // Read input file
        byte[] fileBytes;
        try (FileInputStream fis = new FileInputStream(inputFile);
                BufferedInputStream bis = new BufferedInputStream(fis)) {
            fileBytes = bis.readAllBytes();
        }

        ByteBuffer buf = ByteBuffer.wrap(fileBytes);

        // Parse
        ParseResult result = parse(buf, inputFile.getAbsolutePath());

        // JSON report
        String json = toJson(result);
        System.out.println(json);

        // Repair
        if (result.header() == null) {
            System.err.println("Cannot repair: header is unreadable.");
            System.exit(2);
        }

        ByteBuffer repaired = repair(result);
        String repairedName = inputFile.getName().replace(".bin", "_repaired.bin");
        File repairedFile = new File(inputFile.getParentFile(), repairedName);

        try (FileOutputStream fos = new FileOutputStream(repairedFile);
                BufferedOutputStream bos = new BufferedOutputStream(fos)) {
            bos.write(repaired.array(), 0, repaired.limit());
        }

        System.err.println("Repaired file written to: " + repairedFile.getAbsolutePath());
        System.err.println(
                "Recovered: "
                        + result.cells().size()
                        + "/"
                        + result.expectedCells()
                        + " cells, "
                        + result.safehouses().size()
                        + " safehouses, "
                        + result.nonPvpZones().size()
                        + " zones, "
                        + result.factions().size()
                        + " factions, "
                        + result.designationZones().size()
                        + " designation zones"
                        + (result.errors().isEmpty() ? "" : " (" + result.errors().size() + " errors)"));
    }
}
