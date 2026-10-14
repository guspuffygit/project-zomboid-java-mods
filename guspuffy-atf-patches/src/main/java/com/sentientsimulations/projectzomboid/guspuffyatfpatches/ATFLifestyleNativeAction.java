package com.sentientsimulations.projectzomboid.guspuffyatfpatches;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import java.lang.reflect.Field;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.HiddenFromLua;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.NetTimedAction;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameServer;
import zombie.network.fields.character.PlayerID;

/** Sender provenance for Lifestyle server rewards; unrelated native actions are not rejected. */
public final class ATFLifestyleNativeAction {
    private static final NativeActionProvenance RECEIPTS =
            new NativeActionProvenance(System::nanoTime);

    private ATFLifestyleNativeAction() {}

    @SubscribeEvent
    @HiddenFromLua
    public static void expose(OnZomboidGlobalsLoadEvent event) {
        LuaManager.exposer.setExposed(ATFLifestyleNativeAction.class);
        LuaManager.exposer.exposeLikeJavaRecursively(
                ATFLifestyleNativeAction.class, LuaManager.env);
    }

    @HiddenFromLua
    public static void capture(Object action, Object connection) {
        Runtime.capture(action, connection);
    }

    @HiddenFromLua
    public static void forget(Object action) {
        RECEIPTS.forget(action);
    }

    @HiddenFromLua
    public static void copy(Object destination, Object source) {
        Runtime.copy(destination, source);
    }

    @LuaMethod
    public static boolean ownsAction(Object action, Object actor) {
        return Runtime.ownsAction(action, actor);
    }

    // Keep native action types out of exposed signatures and transformer registration.
    private static final class Runtime {
        static void capture(Object action, Object connection) {
            RECEIPTS.forget(action);
            try {
                if (!(action instanceof NetTimedAction nativeAction)
                        || nativeAction.action == null
                        || !(connection instanceof UdpConnection sender)
                        || !GameServer.server) return;
                IsoPlayer owner = owner(action);
                if (currentSender(sender, owner)) RECEIPTS.capture(action, sender, owner);
            } catch (Throwable ignored) {
                // Missing/changed APIs leave no receipt: Lifestyle must fail closed.
            }
        }

        static void copy(Object destination, Object source) {
            try {
                if (!(destination instanceof NetTimedAction)
                        || !(source instanceof NetTimedAction)) {
                    RECEIPTS.forget(destination);
                    return;
                }
                RECEIPTS.copy(destination, source, owner(destination));
            } catch (Throwable ignored) {
                RECEIPTS.forget(destination);
            }
        }

        static boolean ownsAction(Object action, Object actorObject) {
            try {
                if (!GameServer.server
                        || !(action instanceof NetTimedAction)
                        || !(actorObject instanceof IsoPlayer actor)) return false;
                NativeActionProvenance.Receipt receipt = RECEIPTS.get(action);
                if (receipt == null || !(receipt.connection() instanceof UdpConnection sender))
                    return false;
                if (!NativeActionProvenance.matches(
                        actor,
                        receipt.owner(),
                        owner(action),
                        GameServer.getConnectionFromPlayer(actor),
                        sender,
                        sender.players,
                        sender.isFullyConnected(),
                        actor.isDead())) return false;
                RECEIPTS.touch(action);
                return true;
            } catch (Throwable ignored) {
                return false;
            }
        }

        private static boolean currentSender(UdpConnection sender, IsoPlayer actor) {
            return actor != null
                    && NativeActionProvenance.matches(
                            actor,
                            actor,
                            actor,
                            GameServer.getConnectionFromPlayer(actor),
                            sender,
                            sender.players,
                            sender.isFullyConnected(),
                            actor.isDead());
        }

        private static IsoPlayer owner(Object action) throws IllegalAccessException {
            return ((PlayerID) Fields.PLAYER.get(action)).getPlayer();
        }

        private static final class Fields {
            static final Field PLAYER = playerField();

            private static Field playerField() {
                try {
                    Field field =
                            Class.forName(
                                            "zombie.core.Action",
                                            false,
                                            NetTimedAction.class.getClassLoader())
                                    .getDeclaredField("playerId");
                    if (field.getType() != PlayerID.class || !field.trySetAccessible())
                        throw new IllegalStateException("Unsupported native action owner field");
                    return field;
                } catch (ReflectiveOperationException error) {
                    throw new IllegalStateException(error);
                }
            }
        }
    }
}
