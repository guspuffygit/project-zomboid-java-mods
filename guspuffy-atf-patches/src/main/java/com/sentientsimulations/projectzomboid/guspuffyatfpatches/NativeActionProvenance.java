package com.sentientsimulations.projectzomboid.guspuffyatfpatches;

import java.lang.ref.WeakReference;
import java.util.Iterator;
import java.util.Map;
import java.util.WeakHashMap;
import java.util.function.LongSupplier;

/** Bounded weak receipts; a decoded Lua argument is never an action owner receipt. */
final class NativeActionProvenance {
    static final int LIMIT = 4096;
    static final long EXPIRY = 90_000_000_000L;
    private final Map<Object, Receipt> receipts = new WeakHashMap<>();
    private final LongSupplier clock;
    private long nextSweep;

    NativeActionProvenance(LongSupplier clock) {
        this.clock = clock;
    }

    synchronized void capture(Object action, Object connection, Object owner) {
        forget(action);
        if (action == null || connection == null || owner == null) return;
        long now = clock.getAsLong();
        if (now >= nextSweep || receipts.size() >= LIMIT) {
            receipts.values()
                    .removeIf(
                            receipt ->
                                    now - receipt.used >= EXPIRY
                                            || receipt.owner() == null
                                            || receipt.connection() == null);
            nextSweep = now + 30_000_000_000L;
        }
        if (receipts.size() >= LIMIT) {
            Iterator<Object> oldest = receipts.keySet().iterator();
            if (oldest.hasNext()) {
                oldest.next();
                oldest.remove();
            }
        }
        receipts.put(action, new Receipt(connection, owner, now));
    }

    synchronized void copy(Object destination, Object source, Object declaredOwner) {
        if (destination == source) return;
        forget(destination);
        Receipt original = get(source);
        if (original != null && original.owner() == declaredOwner)
            capture(destination, original.connection(), original.owner());
    }

    synchronized Receipt get(Object action) {
        Receipt receipt = receipts.get(action);
        if (receipt != null
                && (clock.getAsLong() - receipt.used >= EXPIRY
                        || receipt.owner() == null
                        || receipt.connection() == null)) {
            receipts.remove(action);
            return null;
        }
        return receipt;
    }

    synchronized void touch(Object action) {
        Receipt receipt = get(action);
        if (receipt != null) receipt.used = clock.getAsLong();
    }

    synchronized void forget(Object action) {
        if (action != null) receipts.remove(action);
    }

    synchronized int size() {
        return receipts.size();
    }

    static boolean matches(
            Object actor,
            Object recordedOwner,
            Object declaredOwner,
            Object currentConnection,
            Object recordedConnection,
            Object[] members,
            boolean fullyConnected,
            boolean dead) {
        if (actor == null
                || recordedOwner != actor
                || declaredOwner != actor
                || currentConnection == null
                || currentConnection != recordedConnection
                || !fullyConnected
                || dead
                || members == null) return false;
        for (Object member : members) if (member == actor) return true;
        return false;
    }

    static final class Receipt {
        final WeakReference<Object> connection;
        final WeakReference<Object> owner;
        long used;

        Receipt(Object connection, Object owner, long used) {
            this.connection = new WeakReference<>(connection);
            this.owner = new WeakReference<>(owner);
            this.used = used;
        }

        Object connection() {
            return connection.get();
        }

        Object owner() {
            return owner.get();
        }
    }
}
