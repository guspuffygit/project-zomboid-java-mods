package com.sentientsimulations.projectzomboid.extralogging.pvphit;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sentientsimulations.projectzomboid.extralogging.ExtraLoggerFactory;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import zombie.CombatManager;
import zombie.SandboxOptions;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.characters.action.ActionContext;
import zombie.characters.action.ActionState;
import zombie.characters.animals.IsoAnimal;
import zombie.inventory.InventoryItem;
import zombie.inventory.types.HandWeapon;
import zombie.iso.IsoMovingObject;
import zombie.network.GameClient;
import zombie.network.fields.hit.HitInfo;

/**
 * Client half of the PvP hit audit, for the local shooter only. Writes JSON lines to {@code
 * extra-logging/pvp-shots.json}:
 *
 * <ul>
 *   <li>{@code shot}: one line per aimed-firearm shot. It carries the aim delay at trigger pull,
 *       after the post-shot penalty, and at the roll. It also carries the action and AI state, and
 *       every candidate target with its hit chance and queued outcome. {@code missIgnoreDamage} is
 *       a failed roll that {@code FirearmUseDamageChance=3} still sends as a zero-damage hit. Only
 *       zombie hits are rolled on the client; player and animal hits are always queued and the
 *       server rolls them.
 *   <li>{@code idleWhileAiming}: {@code IdleState} entered while the aiming flag was set. Entering
 *       idle clears the flag.
 *   <li>{@code aimDelayReset}: the aim delay jumped back up within {@value #RESET_WINDOW_MS} ms of
 *       a shot.
 * </ul>
 *
 * <p>Combat runs on the main thread, so the shot state is plain statics. Methods take {@code
 * Object} so the inlined advice carries no game-class checkcasts.
 */
public final class PvpShotClientLog {

    static final long RESET_WINDOW_MS = 10_000L;
    static final long TRIGGER_MATCH_MS = 3_000L;
    static final float RESET_JUMP = 0.5F;

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static final VarHandle AIM_FLAG;

    static {
        VarHandle aimFlag = null;
        try {
            aimFlag =
                    MethodHandles.privateLookupIn(IsoGameCharacter.class, MethodHandles.lookup())
                            .findVarHandle(IsoGameCharacter.class, "isAiming", boolean.class);
        } catch (ReflectiveOperationException | RuntimeException e) {
            LOGGER.warn("extra-logging: PvP shot audit cannot read the aiming flag", e);
        }
        AIM_FLAG = aimFlag;
    }

    private static final class Out {
        static final Logger LOG = ExtraLoggerFactory.createLogger("pvp-shots", "json", 3);
    }

    static final class Trigger {
        final long ms = System.currentTimeMillis();
        final float aimDelayBefore;
        float aimDelayAfter = Float.NaN;
        final Map<String, Object> state;

        Trigger(IsoPlayer player) {
            this.aimDelayBefore = player.getAimingDelay();
            this.state = stateOf(player);
        }
    }

    static final class Shot {
        final IsoPlayer owner;
        final HandWeapon weapon;
        final float aimDelayAtRoll;
        final Map<Object, int[]> sent = new IdentityHashMap<>();

        Shot(IsoPlayer owner, HandWeapon weapon) {
            this.owner = owner;
            this.weapon = weapon;
            this.aimDelayAtRoll = owner.getAimingDelay();
        }
    }

    private static Trigger trigger;
    private static Shot shot;
    private static long lastShotMs;
    private static long lastIdleWhileAimingMs;
    private static int idleWhileAimingSinceShot;

    private PvpShotClientLog() {}

    public static void onIdleEnter(Object characterObj) {
        IsoPlayer player = localPlayer(characterObj);
        if (player == null || !aimFlag(player)) {
            return;
        }
        long now = System.currentTimeMillis();
        idleWhileAimingSinceShot++;
        lastIdleWhileAimingMs = now;
        Map<String, Object> out = event("idleWhileAiming", player, now);
        out.put("aimDelay", player.getAimingDelay());
        out.putAll(stateOf(player));
        write(out);
    }

    public static void beforeDoAttack(Object playerObj) {
        IsoPlayer player = localPlayer(playerObj);
        trigger = player == null ? null : new Trigger(player);
    }

    public static void afterDoAttack(Object playerObj) {
        IsoPlayer player = localPlayer(playerObj);
        if (player != null && trigger != null) {
            trigger.aimDelayAfter = player.getAimingDelay();
        }
    }

    public static void beforeCollision(Object ownerObj, Object weaponObj) {
        IsoPlayer player = localPlayer(ownerObj);
        shot =
                player != null && weaponObj instanceof HandWeapon weapon && weapon.isAimedFirearm()
                        ? new Shot(player, weapon)
                        : null;
    }

    public static void onClientHit(Object target, Object hitDataObj) {
        if (shot != null && target != null) {
            int[] counts = shot.sent.computeIfAbsent(target, k -> new int[2]);
            counts[0]++;
            if (hitDataObj instanceof CombatManager.HitData hitData && hitData.isIgnoreDamage()) {
                counts[1]++;
            }
        }
    }

    public static void afterCollision(Object ownerObj) {
        Shot current = shot;
        shot = null;
        if (current == null || current.owner != ownerObj) {
            return;
        }
        long now = System.currentTimeMillis();
        Map<String, Object> out = event("shot", current.owner, now);
        out.put(
                "firearmUseDamageChance",
                SandboxOptions.instance.firearmUseDamageChance.getValue());
        Trigger t = trigger;
        boolean matched = t != null && now - t.ms <= TRIGGER_MATCH_MS;
        out.put("aimDelayAtTrigger", matched ? t.aimDelayBefore : null);
        out.put("aimDelayAfterPenalty", matched ? t.aimDelayAfter : null);
        out.put("aimDelayAtRoll", current.aimDelayAtRoll);
        out.put("weaponAimingTime", current.weapon.getAimingTime());
        out.put("aimAtFloor", current.owner.isAimAtFloor());
        out.put("msSinceLastShot", lastShotMs == 0L ? null : now - lastShotMs);
        out.put("idleWhileAimingSinceLastShot", idleWhileAimingSinceShot);
        if (matched) {
            out.put("atTrigger", t.state);
        }
        out.put("atRoll", stateOf(current.owner));
        out.put("targets", targets(current));
        trigger = null;
        lastShotMs = now;
        idleWhileAimingSinceShot = 0;
        write(out);
    }

    public static float beforeReset(Object characterObj) {
        IsoPlayer player = localPlayer(characterObj);
        return player == null ? Float.NaN : player.getAimingDelay();
    }

    public static void afterReset(Object characterObj, float before) {
        IsoPlayer player = localPlayer(characterObj);
        if (player == null || Float.isNaN(before)) {
            return;
        }
        float after = player.getAimingDelay();
        long now = System.currentTimeMillis();
        if (!isResetJump(before, after, now - lastShotMs, lastShotMs != 0L)) {
            return;
        }
        Map<String, Object> out = event("aimDelayReset", player, now);
        out.put("before", before);
        out.put("after", after);
        out.put("msSinceLastShot", now - lastShotMs);
        out.put(
                "msSinceIdleWhileAiming",
                lastIdleWhileAimingMs == 0L ? null : now - lastIdleWhileAimingMs);
        out.putAll(stateOf(player));
        write(out);
    }

    static boolean isResetJump(float before, float after, long msSinceShot, boolean hasShot) {
        return hasShot && msSinceShot <= RESET_WINDOW_MS && after - before > RESET_JUMP;
    }

    static String outcome(int[] counts) {
        if (counts == null) {
            return "notSent";
        }
        if (counts[1] == 0) {
            return "hit";
        }
        return counts[1] == counts[0] ? "missIgnoreDamage" : "mixed";
    }

    static String targetType(Object target) {
        if (target instanceof IsoAnimal) {
            return "animal";
        }
        if (target instanceof IsoPlayer) {
            return "player";
        }
        if (target instanceof IsoZombie) {
            return "zombie";
        }
        return target == null ? "none" : target.getClass().getSimpleName();
    }

    private static List<Map<String, Object>> targets(Shot current) {
        List<Map<String, Object>> out = new ArrayList<>();
        List<HitInfo> hitInfos = current.owner.getHitInfoList();
        for (int i = 0; i < hitInfos.size(); i++) {
            HitInfo info = hitInfos.get(i);
            IsoMovingObject object = info.getObject();
            if (object == null) {
                continue;
            }
            Map<String, Object> t = new LinkedHashMap<>();
            t.put("type", targetType(object));
            t.put(
                    "name",
                    object instanceof IsoPlayer p && !(object instanceof IsoAnimal)
                            ? p.getUsername()
                            : null);
            t.put("chance", info.chance);
            t.put("distance", (float) Math.sqrt(info.distSq));
            int[] counts = current.sent.get(object);
            t.put("outcome", outcome(counts));
            t.put("sentHits", counts == null ? 0 : counts[0]);
            if (object instanceof IsoGameCharacter character) {
                t.put("state", PvpHitStates.movement(character));
            }
            out.add(t);
        }
        return out;
    }

    private static Map<String, Object> event(String name, IsoPlayer player, long now) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ts", now);
        out.put("event", name);
        out.put("player", player.getUsername());
        InventoryItem item = player.getPrimaryHandItem();
        out.put("weapon", item == null ? null : item.getFullType());
        return out;
    }

    private static Map<String, Object> stateOf(IsoPlayer player) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("aimFlag", aimFlag(player));
        out.put("isAiming", player.isAiming());
        out.put("recoilDelay", player.getRecoilDelay());
        out.put("aiState", player.getCurrentStateName());
        out.put("prevAiState", player.getPreviousStateName());
        ActionContext context = player.getActionContext();
        if (context != null) {
            out.put("actionState", context.getCurrentStateName());
            out.put("prevActionState", context.peekPreviousStateName());
            out.put("actionChildren", context.getChildStates(ActionState::getName));
        }
        return out;
    }

    private static IsoPlayer localPlayer(Object characterObj) {
        return characterObj instanceof IsoPlayer player
                        && !(characterObj instanceof IsoAnimal)
                        && GameClient.client
                        && player.isLocalPlayer()
                ? player
                : null;
    }

    private static boolean aimFlag(IsoGameCharacter character) {
        return AIM_FLAG != null && (boolean) AIM_FLAG.get(character);
    }

    private static void write(Map<String, Object> record) {
        try {
            Out.LOG.info(MAPPER.writeValueAsString(record));
        } catch (Exception e) {
            LOGGER.warn("extra-logging: PvP shot audit write failed", e);
        }
    }
}
