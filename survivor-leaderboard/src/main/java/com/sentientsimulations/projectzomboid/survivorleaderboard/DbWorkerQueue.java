package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

/**
 * Off-thread DB plumbing (same pattern as the ATF economy mod's DbWorkerQueue): ops enqueued from
 * the game thread run on a lazily started, named daemon worker (where the SQLite fsync commit is
 * allowed to stall); results the worker hands back are drained on the game thread, which is the
 * only place game-thread-only APIs ({@code GameServer.sendServerCommand}, {@code LuaEventManager})
 * may run.
 *
 * <p>Usage: the bridge holds one {@code static final DbWorkerQueue<Op, Result>} with its worker
 * ({@code runner}) and game-thread ({@code deliverer}) halves, calls {@link #submit} from its
 * validated game-thread entry point, {@link #offerResult} from the worker, and {@link
 * #drainResults} from its {@code @SubscribeEvent onTick} (gated on {@code StormEnv.isStormServer()}
 * — the same mod jar loads on the client JVM too, and the gate also keeps the drain callback off
 * clients).
 *
 * <p>The worker thread is started on first {@link #submit}, so a JVM that never enqueues (the
 * client, an idle server) never spawns it. A single worker per queue serializes DB ops, preserving
 * the old sync path's ordering.
 */
final class DbWorkerQueue<O, R> {

    private final String name;
    private final Consumer<O> runner;
    private final Consumer<R> deliverer;
    private final BlockingQueue<O> pending = new LinkedBlockingQueue<>();
    private final BlockingQueue<R> results = new LinkedBlockingQueue<>();
    private final AtomicBoolean workerStarted = new AtomicBoolean(false);

    /**
     * @param name worker thread name (also the log prefix)
     * @param runner worker-side op handler; expected to catch its own domain exceptions and enqueue
     *     failure results — anything that still escapes is logged here and the op is dropped
     * @param deliverer game-thread result handler; a throw is logged and that result is dropped so
     *     one poisoned result can't wedge the drain
     */
    DbWorkerQueue(String name, Consumer<O> runner, Consumer<R> deliverer) {
        this.name = name;
        this.runner = runner;
        this.deliverer = deliverer;
    }

    /** Game-thread half: enqueue a validated op, starting the daemon worker on first use. */
    void submit(O op) {
        if (workerStarted.compareAndSet(false, true)) {
            Thread worker = new Thread(this::workerLoop, name);
            worker.setDaemon(true);
            worker.start();
        }
        pending.offer(op);
    }

    /** Worker half: hand a result back for the next tick drain. */
    void offerResult(R result) {
        results.offer(result);
    }

    /** Game-thread half: deliver every queued result. Call from the bridge's onTick subscriber. */
    void drainResults() {
        R result;
        while ((result = results.poll()) != null) {
            try {
                deliverer.accept(result);
            } catch (Throwable t) {
                LOGGER.error("{}: failed to deliver result: {}", name, t.getMessage(), t);
            }
        }
    }

    private void workerLoop() {
        while (true) {
            O op;
            try {
                op = pending.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            try {
                runner.accept(op);
            } catch (Throwable t) {
                LOGGER.error("{}: worker iteration failed: {}", name, t.getMessage(), t);
            }
        }
    }
}
