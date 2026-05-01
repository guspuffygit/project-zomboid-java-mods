package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import java.util.List;

public record SqlExecutionResponse(
        List<String> columns, List<List<Object>> rows, Integer updateCount, String error) {

    public static SqlExecutionResponse rows(List<String> columns, List<List<Object>> rows) {
        return new SqlExecutionResponse(columns, rows, null, null);
    }

    public static SqlExecutionResponse update(int updateCount) {
        return new SqlExecutionResponse(null, null, updateCount, null);
    }

    public static SqlExecutionResponse error(String message) {
        return new SqlExecutionResponse(null, null, null, message);
    }
}
