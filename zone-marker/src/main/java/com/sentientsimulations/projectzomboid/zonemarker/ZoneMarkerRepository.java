package com.sentientsimulations.projectzomboid.zonemarker;

import com.sentientsimulations.projectzomboid.zonemarker.records.ZoneCategoryRecord;
import com.sentientsimulations.projectzomboid.zonemarker.records.ZoneRecord;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

public class ZoneMarkerRepository {

    private static final String INSERT_CATEGORY =
            "INSERT INTO categories (name, r, g, b, a) VALUES (?, ?, ?, ?, ?)";

    private static final String DELETE_CATEGORY_BY_NAME = "DELETE FROM categories WHERE name = ?";

    private static final String SELECT_CATEGORY_EXISTS = "SELECT 1 FROM categories WHERE name = ?";

    private static final String SELECT_ALL_CATEGORIES =
            "SELECT id, name, r, g, b, a FROM categories ORDER BY id";

    private static final String INSERT_ZONE =
            """
            INSERT INTO zones (category_id, x_start, y_start, x_end, y_end, region)
            SELECT id, ?, ?, ?, ?, ? FROM categories WHERE name = ?""";

    private static final String DELETE_ZONES_BY_REGION =
            """
            DELETE FROM zones
            WHERE category_id = (SELECT id FROM categories WHERE name = ?)
              AND region = ?""";

    private static final String SELECT_ZONES_BY_CATEGORY =
            """
            SELECT z.id, z.category_id, z.x_start, z.y_start, z.x_end, z.y_end, z.region
            FROM zones z
            JOIN categories c ON z.category_id = c.id
            WHERE c.name = ?
            ORDER BY z.id""";

    private final Connection connection;

    public ZoneMarkerRepository(Connection connection) {
        this.connection = connection;
    }

    /**
     * @return the generated category id, or -1 if the name already exists
     */
    public long insertCategory(String name, double r, double g, double b, double a)
            throws SQLException {
        try (PreparedStatement ps =
                connection.prepareStatement(INSERT_CATEGORY, new String[] {"id"})) {
            ps.setString(1, name);
            ps.setDouble(2, r);
            ps.setDouble(3, g);
            ps.setDouble(4, b);
            ps.setDouble(5, a);
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) {
                    return keys.getLong(1);
                }
            }
        }
        return -1;
    }

    /**
     * @return true if a category was deleted
     */
    public boolean deleteCategoryByName(String name) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DELETE_CATEGORY_BY_NAME)) {
            ps.setString(1, name);
            return ps.executeUpdate() > 0;
        }
    }

    public boolean categoryExists(String name) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(SELECT_CATEGORY_EXISTS)) {
            ps.setString(1, name);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    public List<ZoneCategoryRecord> loadAllCategories() throws SQLException {
        List<ZoneCategoryRecord> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_ALL_CATEGORIES);
                ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                results.add(
                        new ZoneCategoryRecord(
                                rs.getLong("id"),
                                rs.getString("name"),
                                rs.getDouble("r"),
                                rs.getDouble("g"),
                                rs.getDouble("b"),
                                rs.getDouble("a")));
            }
        }
        return results;
    }

    public void insertZone(
            String categoryName,
            double xStart,
            double yStart,
            double xEnd,
            double yEnd,
            String region)
            throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(INSERT_ZONE)) {
            ps.setDouble(1, xStart);
            ps.setDouble(2, yStart);
            ps.setDouble(3, xEnd);
            ps.setDouble(4, yEnd);
            ps.setString(5, region);
            ps.setString(6, categoryName);
            ps.executeUpdate();
        }
    }

    /**
     * @return number of zones removed
     */
    public int deleteZonesByRegion(String categoryName, String region) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DELETE_ZONES_BY_REGION)) {
            ps.setString(1, categoryName);
            ps.setString(2, region);
            return ps.executeUpdate();
        }
    }

    public List<ZoneRecord> loadZonesByCategoryName(String categoryName) throws SQLException {
        List<ZoneRecord> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_ZONES_BY_CATEGORY)) {
            ps.setString(1, categoryName);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    results.add(
                            new ZoneRecord(
                                    rs.getLong("id"),
                                    rs.getLong("category_id"),
                                    rs.getDouble("x_start"),
                                    rs.getDouble("y_start"),
                                    rs.getDouble("x_end"),
                                    rs.getDouble("y_end"),
                                    rs.getString("region")));
                }
            }
        }
        return results;
    }
}
