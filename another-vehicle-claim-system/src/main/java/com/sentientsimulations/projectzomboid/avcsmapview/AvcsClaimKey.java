package com.sentientsimulations.projectzomboid.avcsmapview;

/**
 * Decodes AVCS's claim key back to the vehicle's {@code vehicles.db} row id.
 *
 * <p>AVCSServer.lua mints the key as {@code tonumber(getTimestamp() .. vehicleObj:getSqlId())}: a
 * 10-digit unix-seconds timestamp immediately followed by the decimal sqlId, stored as a Lua number
 * (Java {@code Double}). The timestamp is exactly 10 digits for 2001–2286, so everything after the
 * first ten digits is the sqlId.
 */
final class AvcsClaimKey {

    static final int INVALID = -1;

    private static final int TIMESTAMP_DIGITS = 10;
    private static final double MAX_EXACT_DOUBLE = 9_007_199_254_740_992d;

    private AvcsClaimKey() {}

    /** Returns the sqlId encoded in {@code key}, or {@link #INVALID} when it cannot be one. */
    static int sqlIdFromClaimKey(Object key) {
        if (!(key instanceof Double boxed)) {
            return INVALID;
        }
        double value = boxed;
        if (value != Math.floor(value) || value < 1e10 || value >= MAX_EXACT_DOUBLE) {
            return INVALID;
        }
        String digits = Long.toString((long) value);
        String sqlIdDigits = digits.substring(TIMESTAMP_DIGITS);
        if (sqlIdDigits.isEmpty() || sqlIdDigits.charAt(0) == '0' || sqlIdDigits.length() > 9) {
            return INVALID;
        }
        int sqlId = Integer.parseInt(sqlIdDigits);
        return sqlId >= 1 ? sqlId : INVALID;
    }
}
