package com.sentientsimulations.projectzomboid.avcsmapview;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class AvcsClaimKeyTest {

    @Test
    void decodesTimestampPrefixedSqlId() {
        // tonumber(getTimestamp() .. sqlId) with getTimestamp()=1712345678, sqlId=1234
        assertEquals(1234, AvcsClaimKey.sqlIdFromClaimKey(17123456781234d));
        assertEquals(1, AvcsClaimKey.sqlIdFromClaimKey(17123456781d));
        assertEquals(987654, AvcsClaimKey.sqlIdFromClaimKey(1712345678987654d));
    }

    @Test
    void rejectsKeysThatCannotBeClaimKeys() {
        assertEquals(AvcsClaimKey.INVALID, AvcsClaimKey.sqlIdFromClaimKey("17123456781234"));
        assertEquals(AvcsClaimKey.INVALID, AvcsClaimKey.sqlIdFromClaimKey(null));
        assertEquals(AvcsClaimKey.INVALID, AvcsClaimKey.sqlIdFromClaimKey(1712345678d));
        assertEquals(AvcsClaimKey.INVALID, AvcsClaimKey.sqlIdFromClaimKey(17123456781234.5d));
        assertEquals(AvcsClaimKey.INVALID, AvcsClaimKey.sqlIdFromClaimKey(1e17));
        assertEquals(AvcsClaimKey.INVALID, AvcsClaimKey.sqlIdFromClaimKey(-17123456781234d));
    }
}
