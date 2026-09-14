package com.sentientsimulations.projectzomboid.admincore;

/** Wait for the previous relocation to arrive before issuing another one. */
final class ObserveMove {
    private final float x, y, z;
    private final long sentAt;

    ObserveMove(float x, float y, float z, long sentAt) {
        this.x = x;
        this.y = y;
        this.z = z;
        this.sentAt = sentAt;
    }

    boolean waiting(float currentX, float currentY, float currentZ, long now) {
        double dx = currentX - x, dy = currentY - y;
        boolean arrived = dx * dx + dy * dy <= 16 && (int) currentZ == (int) z;
        return !arrived && now - sentAt >= 0 && now - sentAt < 6_000_000_000L;
    }
}
