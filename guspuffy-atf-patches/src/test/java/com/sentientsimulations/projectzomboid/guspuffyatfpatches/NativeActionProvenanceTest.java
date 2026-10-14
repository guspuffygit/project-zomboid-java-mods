package com.sentientsimulations.projectzomboid.guspuffyatfpatches;

import static org.junit.jupiter.api.Assertions.*;

import java.util.ArrayList;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;

class NativeActionProvenanceTest {
    @Test
    void luaCanVerifyButCannotCreateOrEraseNativeReceipts() throws Exception {
        assertFalse(
                ATFLifestyleNativeAction.class
                        .getMethod("ownsAction", Object.class, Object.class)
                        .isAnnotationPresent(zombie.HiddenFromLua.class));
        for (String name : new String[] {"capture", "copy"})
            assertTrue(
                    ATFLifestyleNativeAction.class
                            .getMethod(name, Object.class, Object.class)
                            .isAnnotationPresent(zombie.HiddenFromLua.class));
        assertTrue(
                ATFLifestyleNativeAction.class
                        .getMethod("forget", Object.class)
                        .isAnnotationPresent(zombie.HiddenFromLua.class));
    }

    @Test
    void constructorActorAndOnlinePresenceDoNotReplaceSenderOwnership() {
        Object sender = new Object(), owner = new Object(), victim = new Object();
        Object[] members = {owner};
        assertTrue(
                NativeActionProvenance.matches(
                        owner, owner, owner, sender, sender, members, true, false));
        assertFalse(
                NativeActionProvenance.matches(
                        victim, owner, owner, sender, sender, members, true, false));
        assertFalse(
                NativeActionProvenance.matches(
                        owner, owner, victim, sender, sender, members, true, false));
        assertFalse(
                NativeActionProvenance.matches(
                        victim, victim, victim, sender, sender, members, true, false));
    }

    @Test
    void disconnectReconnectAndCharacterReplacementInvalidateReceipts() {
        Object sender = new Object(), actor = new Object(), replacement = new Object();
        assertFalse(
                NativeActionProvenance.matches(
                        actor, actor, actor, null, sender, new Object[] {actor}, true, false));
        assertFalse(
                NativeActionProvenance.matches(
                        actor,
                        actor,
                        actor,
                        new Object(),
                        sender,
                        new Object[] {actor},
                        true,
                        false));
        assertFalse(
                NativeActionProvenance.matches(
                        actor,
                        actor,
                        actor,
                        sender,
                        sender,
                        new Object[] {replacement},
                        true,
                        false));
        assertFalse(
                NativeActionProvenance.matches(
                        actor, actor, actor, sender, sender, new Object[] {actor}, false, false));
        assertFalse(
                NativeActionProvenance.matches(
                        actor, actor, actor, sender, sender, new Object[] {actor}, true, true));
    }

    @Test
    void splitScreenMembersRemainBoundToTheirOwnAction() {
        Object sender = new Object(), actor = new Object(), second = new Object();
        Object[] members = {actor, second};
        assertTrue(
                NativeActionProvenance.matches(
                        second, second, second, sender, sender, members, true, false));
        assertFalse(
                NativeActionProvenance.matches(
                        actor, second, second, sender, sender, members, true, false));
    }

    @Test
    void nativeCopyCarriesReceiptOnlyForSameDeclaredOwner() {
        var registry = new NativeActionProvenance(() -> 1);
        Object packet = new Object(),
                active = new Object(),
                connection = new Object(),
                owner = new Object();
        registry.capture(packet, connection, owner);
        registry.copy(active, packet, owner);
        assertSame(connection, registry.get(active).connection());
        assertSame(owner, registry.get(active).owner());
        registry.copy(active, packet, new Object());
        assertNull(registry.get(active));
        registry.capture(active, connection, owner);
        registry.copy(active, new Object(), owner);
        assertNull(registry.get(active));
    }

    @Test
    void reparsedOrUnownedObjectHasNoPreviousReceipt() {
        var registry = new NativeActionProvenance(() -> 1);
        Object action = new Object(), connection = new Object(), owner = new Object();
        registry.capture(action, connection, owner);
        registry.capture(action, null, owner);
        assertNull(registry.get(action));
        registry.capture(action, connection, owner);
        registry.forget(action);
        assertNull(registry.get(action));
        assertNull(registry.get(new Object()));
    }

    @Test
    void inactiveBindingsExpireAndVerifiedActiveBindingsRefresh() {
        AtomicLong now = new AtomicLong();
        var registry = new NativeActionProvenance(now::get);
        Object active = new Object(),
                inactive = new Object(),
                connection = new Object(),
                owner = new Object();
        registry.capture(active, connection, owner);
        registry.capture(inactive, connection, owner);
        now.set(NativeActionProvenance.EXPIRY - 1);
        registry.touch(active);
        now.incrementAndGet();
        assertNotNull(registry.get(active));
        assertNull(registry.get(inactive));
    }

    @Test
    void registryIsBoundedAndDoesNotStronglyRetainConnectionOrCharacter() {
        var registry = new NativeActionProvenance(() -> 1);
        Object connection = new Object(), owner = new Object(), action = new Object();
        registry.capture(action, connection, owner);
        registry.get(action).connection.clear();
        assertNull(registry.get(action));
        registry.capture(action, connection, owner);
        registry.get(action).owner.clear();
        assertNull(registry.get(action));
        var retained = new ArrayList<Object>();
        for (int i = 0; i < NativeActionProvenance.LIMIT + 20; i++) {
            Object entry = new Object();
            retained.add(entry);
            registry.capture(entry, connection, owner);
        }
        assertEquals(NativeActionProvenance.LIMIT, registry.size());
        assertNotNull(registry.get(retained.getLast()));
    }
}
