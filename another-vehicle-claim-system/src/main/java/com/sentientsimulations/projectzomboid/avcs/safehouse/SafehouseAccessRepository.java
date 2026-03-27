package com.sentientsimulations.projectzomboid.avcs.safehouse;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class SafehouseAccessRepository {

    private static final String INSERT_ACCESS =
            "INSERT OR IGNORE INTO safehouse_access (owner_username, allowed_username) VALUES (?, ?)";

    private static final String DELETE_ACCESS =
            "DELETE FROM safehouse_access WHERE owner_username = ? AND allowed_username = ?";

    private static final String SELECT_BY_OWNER =
            "SELECT allowed_username FROM safehouse_access WHERE owner_username = ? ORDER BY allowed_username";

    private static final String SELECT_ALL =
            "SELECT owner_username, allowed_username FROM safehouse_access ORDER BY owner_username, allowed_username";

    private final Connection connection;

    public SafehouseAccessRepository(Connection connection) {
        this.connection = connection;
    }

    /**
     * @return true if a row was inserted, false if it already existed
     */
    public boolean insertAccess(String ownerUsername, String allowedUsername) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(INSERT_ACCESS)) {
            ps.setString(1, ownerUsername);
            ps.setString(2, allowedUsername);
            return ps.executeUpdate() > 0;
        }
    }

    /**
     * @return true if a row was deleted
     */
    public boolean deleteAccess(String ownerUsername, String allowedUsername) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(DELETE_ACCESS)) {
            ps.setString(1, ownerUsername);
            ps.setString(2, allowedUsername);
            return ps.executeUpdate() > 0;
        }
    }

    public List<String> loadAllowedByOwner(String ownerUsername) throws SQLException {
        List<String> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_BY_OWNER)) {
            ps.setString(1, ownerUsername);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    results.add(rs.getString("allowed_username"));
                }
            }
        }
        return results;
    }

    /**
     * @return map of owner -> list of allowed usernames
     */
    public Map<String, List<String>> loadAll() throws SQLException {
        Map<String, List<String>> results = new HashMap<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_ALL);
                ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String owner = rs.getString("owner_username");
                String allowed = rs.getString("allowed_username");
                results.computeIfAbsent(owner, k -> new ArrayList<>()).add(allowed);
            }
        }
        return results;
    }
}
