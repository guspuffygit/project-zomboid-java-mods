package com.sentientsimulations.projectzomboid.extralogging.pvphit;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sentientsimulations.projectzomboid.extralogging.ExtraLoggerFactory;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;
import org.slf4j.Logger;
import zombie.SandboxOptions;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.characters.BodyDamage.BodyPart;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.inventory.types.HandWeapon;
import zombie.network.GameServer;
import zombie.network.fields.hit.Hit;
import zombie.network.packets.hit.PlayerHit;
import zombie.network.packets.hit.PlayerHitPlayerPacket;

/**
 * Server half of the PvP hit audit. Writes one JSON line per processed {@code
 * PlayerHitPlayerPacket} to {@code extra-logging/pvp-hits.json}:
 *
 * <ul>
 *   <li>{@code ignoreDamageSent} is the flag as it came off the wire. It is captured when {@code
 *       PlayerHit.parse} returns, before any mod's {@code PlayerHitPlayerPacket.parse} exit advice
 *       can rewrite it. The server's own roll in {@code preProcess} may later set it or drop the
 *       hit, so {@code hits} at process time can be shorter than the sent flags.
 *   <li>{@code ignoreDamageApplied} is the flag {@code process()} actually hands to {@code
 *       IsoGameCharacter.Hit}.
 *   <li>{@code damageFromWeaponCalls} counts {@code BodyDamage.DamageFromWeapon} calls on the
 *       target during {@code process()}. Zero means the server skipped body damage.
 *   <li>{@code partHealthBefore}/{@code partHealthAfter} sum the target's body part health. {@code
 *       overallBodyHealth} is only recomputed in the body damage update, so it lags a tick.
 * </ul>
 *
 * <p>Player hits are rolled on the server since 42.22. A hit the server rolls as a miss under
 * {@code FirearmUseDamageChance} 1 or 2 is removed before {@code process()} and shows up here as a
 * sent flag with no matching hit.
 *
 * <p>Methods take {@code Object} so the inlined advice carries no game-class checkcasts.
 */
public final class PvpHitServerLog {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static final VarHandle HITS;
    private static final VarHandle IGNORE_DAMAGE;
    private static final VarHandle HIT_HEAD;
    private static final VarHandle HIT_LEGS;
    private static final VarHandle HIT_DAMAGE;

    static {
        VarHandle hits = null;
        VarHandle ignoreDamage = null;
        VarHandle hitHead = null;
        VarHandle hitLegs = null;
        VarHandle hitDamage = null;
        try {
            MethodHandles.Lookup packet =
                    MethodHandles.privateLookupIn(PlayerHit.class, MethodHandles.lookup());
            hits = packet.findVarHandle(PlayerHit.class, "hits", List.class);
            MethodHandles.Lookup hit =
                    MethodHandles.privateLookupIn(Hit.class, MethodHandles.lookup());
            ignoreDamage = hit.findVarHandle(Hit.class, "isIgnoreDamage", boolean.class);
            hitHead = hit.findVarHandle(Hit.class, "hitHead", byte.class);
            hitLegs = hit.findVarHandle(Hit.class, "isHitLegs", boolean.class);
            hitDamage = hit.findVarHandle(Hit.class, "hitDamage", float.class);
        } catch (ReflectiveOperationException | RuntimeException e) {
            LOGGER.warn("extra-logging: PvP hit audit cannot read hit fields", e);
        }
        HITS = hits;
        IGNORE_DAMAGE = ignoreDamage;
        HIT_HEAD = hitHead;
        HIT_LEGS = hitLegs;
        HIT_DAMAGE = hitDamage;
    }

    private static final Map<PlayerHitPlayerPacket, boolean[]> SENT_FLAGS =
            Collections.synchronizedMap(new WeakHashMap<>());

    private static final ThreadLocal<Before> PROCESSING = new ThreadLocal<>();

    /** Taken at {@code process()} entry and threaded to the exit advice. */
    public static final class Before {
        final long nanos = System.nanoTime();
        final IsoGameCharacter target;
        final boolean[] ignoreDamageSent;
        final float partHealth;
        final float overallBodyHealth;
        int damageFromWeaponCalls;

        Before(IsoGameCharacter target, boolean[] ignoreDamageSent) {
            this.target = target;
            this.ignoreDamageSent = ignoreDamageSent;
            this.partHealth = partHealth(target);
            this.overallBodyHealth = overallBodyHealth(target);
        }
    }

    private static final class Out {
        static final Logger LOG = ExtraLoggerFactory.createLogger("pvp-hits", "json", 5);
    }

    private PvpHitServerLog() {}

    public static void afterParse(Object packetObj) {
        if (GameServer.server && packetObj instanceof PlayerHitPlayerPacket packet) {
            SENT_FLAGS.put(packet, ignoreFlags(hits(packet)));
        }
    }

    public static Object beforeProcess(Object packetObj) {
        if (!GameServer.server || !(packetObj instanceof PlayerHitPlayerPacket packet)) {
            return null;
        }
        IsoGameCharacter target =
                packet.getTarget() instanceof IsoGameCharacter character ? character : null;
        Before before = new Before(target, SENT_FLAGS.remove(packet));
        PROCESSING.set(before);
        return before;
    }

    public static void onDamageFromWeapon(Object bodyDamageObj) {
        Before before = PROCESSING.get();
        if (before != null
                && bodyDamageObj instanceof BodyDamage bodyDamage
                && before.target != null
                && bodyDamage.getParentChar() == before.target) {
            before.damageFromWeaponCalls++;
        }
    }

    public static void afterProcess(Object packetObj, Object beforeObj) {
        if (!(beforeObj instanceof Before before)) {
            return;
        }
        PROCESSING.remove();
        if (!(packetObj instanceof PlayerHitPlayerPacket packet)) {
            return;
        }
        try {
            Out.LOG.info(MAPPER.writeValueAsString(record(packet, before)));
        } catch (Exception e) {
            LOGGER.warn("extra-logging: PvP hit audit write failed", e);
        }
    }

    static Map<String, Object> record(PlayerHitPlayerPacket packet, Before before) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ts", System.currentTimeMillis());
        IsoPlayer shooter = packet.getPlayer();
        IsoGameCharacter target = before.target;
        out.put("shooter", shooter == null ? null : shooter.getUsername());
        out.put("target", target instanceof IsoPlayer p ? p.getUsername() : null);
        HandWeapon weapon = packet.getHandWeapon();
        out.put("weapon", weapon == null ? null : weapon.getFullType());
        out.put("aimedFirearm", weapon != null && weapon.isAimedFirearm());
        out.put("distance", packet.getDistance());
        out.put(
                "firearmUseDamageChance",
                SandboxOptions.instance.firearmUseDamageChance.getValue());
        out.put("shooterAimAtFloor", shooter != null && shooter.isAimAtFloor());
        if (target != null) {
            out.put("targetState", PvpHitStates.movement(target));
        }

        List<Hit> hits = hits(packet);
        List<Map<String, Object>> hitList = new ArrayList<>();
        for (int i = 0; i < hits.size(); i++) {
            Hit hit = hits.get(i);
            Map<String, Object> h = new LinkedHashMap<>();
            h.put("damage", HIT_DAMAGE == null ? null : (float) HIT_DAMAGE.get(hit));
            h.put("part", hitPartName(hit));
            boolean[] sent = before.ignoreDamageSent;
            h.put("ignoreDamageSent", sent != null && i < sent.length ? sent[i] : null);
            h.put("ignoreDamageApplied", ignoreDamage(hit));
            hitList.add(h);
        }
        out.put("hits", hitList);
        out.put("damageFromWeaponCalls", before.damageFromWeaponCalls);
        float partAfter = partHealth(target);
        out.put("partHealthBefore", before.partHealth);
        out.put("partHealthAfter", partAfter);
        out.put("partHealthDelta", partAfter - before.partHealth);
        out.put("overallBodyHealthBefore", before.overallBodyHealth);
        out.put("targetDead", target != null && target.isDead());
        out.put("processMicros", (System.nanoTime() - before.nanos) / 1000L);
        return out;
    }

    @SuppressWarnings("unchecked")
    static List<Hit> hits(PlayerHit packet) {
        if (HITS == null) {
            return List.of();
        }
        List<Hit> hits = (List<Hit>) HITS.get(packet);
        return hits == null ? List.of() : hits;
    }

    static boolean[] ignoreFlags(List<Hit> hits) {
        boolean[] flags = new boolean[hits.size()];
        for (int i = 0; i < flags.length; i++) {
            Boolean flag = ignoreDamage(hits.get(i));
            flags[i] = flag != null && flag;
        }
        return flags;
    }

    static Boolean ignoreDamage(Hit hit) {
        return IGNORE_DAMAGE == null ? null : (boolean) IGNORE_DAMAGE.get(hit);
    }

    static String hitPartName(Hit hit) {
        if (HIT_HEAD == null || HIT_LEGS == null) {
            return null;
        }
        return hitPartName((byte) HIT_HEAD.get(hit), (boolean) HIT_LEGS.get(hit));
    }

    static String hitPartName(byte hitHead, boolean hitLegs) {
        if (hitHead > 0) {
            return "head";
        }
        return hitLegs ? "legs" : "other";
    }

    static float partHealth(IsoGameCharacter character) {
        if (character == null || character.getBodyDamage() == null) {
            return Float.NaN;
        }
        float sum = 0.0F;
        for (BodyPart part : character.getBodyDamage().getBodyParts()) {
            sum += part.getHealth();
        }
        return sum;
    }

    static float overallBodyHealth(IsoGameCharacter character) {
        return character == null || character.getBodyDamage() == null
                ? Float.NaN
                : character.getBodyDamage().getOverallBodyHealth();
    }
}
