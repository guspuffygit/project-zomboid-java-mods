package com.sentientsimulations.projectzomboid.extralogging.patch;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.extralogging.pvphit.PvpHitServerLog;
import com.sentientsimulations.projectzomboid.extralogging.pvphit.PvpShotClientLog;
import io.pzstorm.storm.core.StormClassTransformer;
import java.io.InputStream;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import org.junit.jupiter.api.Test;

/** Weaves every PvP hit audit patch against the real game class bytes. */
class PvpHitPatchesTest {

    private static final String SERVER = PvpHitServerLog.class.getName().replace('.', '/');
    private static final String CLIENT = PvpShotClientLog.class.getName().replace('.', '/');

    @Test
    void parsePatchCapturesSentFlags() throws Exception {
        byte[] woven = weave(new PvpHitParsePatch());
        assertEquals(1, countCalls(woven, "parse", SERVER, "afterParse"));
        assertEquals(0, countCalls(woven, "write", SERVER, null));
    }

    @Test
    void processPatchBracketsProcess() throws Exception {
        byte[] woven = weave(new PvpHitProcessPatch());
        assertEquals(1, countCalls(woven, "process", SERVER, "beforeProcess"));
        assertTrue(countCalls(woven, "process", SERVER, "afterProcess") >= 1);
        assertEquals(0, countCalls(woven, "parse", SERVER, null));
    }

    @Test
    void bodyDamagePatchCountsDamageFromWeapon() throws Exception {
        byte[] woven = weave(new PvpHitBodyDamagePatch());
        assertEquals(1, countCalls(woven, "DamageFromWeapon", SERVER, "onDamageFromWeapon"));
    }

    @Test
    void idleStatePatchWatchesEnter() throws Exception {
        byte[] woven = weave(new PvpShotIdleStatePatch());
        assertEquals(1, countCalls(woven, "enter", CLIENT, "onIdleEnter"));
        assertEquals(0, countCalls(woven, "exit", CLIENT, null));
    }

    @Test
    void doAttackPatchBracketsDoAttack() throws Exception {
        byte[] woven = weave(new PvpShotDoAttackPatch());
        assertEquals(1, countCalls(woven, "doAttack", CLIENT, "beforeDoAttack"));
        assertTrue(countCalls(woven, "doAttack", CLIENT, "afterDoAttack") >= 1);
    }

    @Test
    void combatManagerPatchWatchesRollAndClientHits() throws Exception {
        byte[] woven = weave(new PvpShotCombatManagerPatch());
        assertEquals(1, countCalls(woven, "attackCollisionCheck", CLIENT, "beforeCollision"));
        assertTrue(countCalls(woven, "attackCollisionCheck", CLIENT, "afterCollision") >= 1);
        assertEquals(1, countCalls(woven, "addTargetHitCharacter", CLIENT, "onClientHit"));
        assertEquals(0, countCalls(woven, "calculateHitInfoList", CLIENT, null));
    }

    @Test
    void aimResetPatchBracketsResetAimingDelay() throws Exception {
        byte[] woven = weave(new PvpShotAimResetPatch());
        assertEquals(1, countCalls(woven, "resetAimingDelay", CLIENT, "beforeReset"));
        assertTrue(countCalls(woven, "resetAimingDelay", CLIENT, "afterReset") >= 1);
        assertEquals(0, countCalls(woven, "updateAimingDelay", CLIENT, null));
    }

    private static byte[] weave(StormClassTransformer patch) throws Exception {
        String resource = "/" + patch.getClassName().replace('.', '/') + ".class";
        byte[] raw;
        try (InputStream is = PvpHitPatchesTest.class.getResourceAsStream(resource)) {
            assertNotNull(is, resource + " must be on the test classpath");
            raw = is.readAllBytes();
        }
        byte[] woven = patch.transform(raw);
        assertNotNull(woven, patch.getClass().getSimpleName() + " must weave");
        return woven;
    }

    private static int countCalls(
            byte[] classBytes, String method, String helperOwner, String calledName) {
        int[] hits = new int[1];
        new ClassReader(classBytes)
                .accept(
                        new ClassVisitor(Opcodes.ASM9) {
                            @Override
                            public MethodVisitor visitMethod(
                                    int access,
                                    String name,
                                    String descriptor,
                                    String signature,
                                    String[] exceptions) {
                                if (!method.equals(name)) {
                                    return null;
                                }
                                return new MethodVisitor(Opcodes.ASM9) {
                                    @Override
                                    public void visitMethodInsn(
                                            int opcode,
                                            String owner,
                                            String mName,
                                            String mDesc,
                                            boolean isInterface) {
                                        if (helperOwner.equals(owner)
                                                && (calledName == null
                                                        || calledName.equals(mName))) {
                                            hits[0]++;
                                        }
                                    }
                                };
                            }
                        },
                        0);
        return hits[0];
    }
}
