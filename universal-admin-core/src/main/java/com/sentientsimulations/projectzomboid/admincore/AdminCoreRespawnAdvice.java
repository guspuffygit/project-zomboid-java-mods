package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.core.network.ByteBufferReader;
import zombie.core.raknet.UdpConnection;
import zombie.network.IConnection;
import zombie.network.PacketTypes;

public final class AdminCoreRespawnAdvice {
    private AdminCoreRespawnAdvice() {}

    public static final class Command {
        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter(
                @Advice.Argument(0) ByteBufferReader reader,
                @Advice.Argument(1) UdpConnection connection) {
            return AdminCoreRespawnServer.command(reader, connection);
        }
    }

    public static final class Create {
        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter(
                @Advice.FieldValue("spawnRegionName") String region,
                @Advice.FieldValue("playerIndex") byte slot,
                @Advice.Argument(1) UdpConnection connection) {
            return AdminCoreRespawnServer.begin(region, slot, connection);
        }

        @Advice.OnMethodExit(onThrowable = Throwable.class)
        public static void exit() {
            AdminCoreRespawnServer.end();
        }
    }

    public static final class Connect {
        @Advice.OnMethodEnter
        public static Object enter(@Advice.Argument(1) IConnection connection) {
            return AdminCoreRespawnServer.enterConnect(connection);
        }

        @Advice.OnMethodExit(onThrowable = Throwable.class)
        public static void exit(@Advice.Enter Object scope) {
            AdminCoreRespawnServer.exitConnect(scope);
        }
    }

    public static final class Loading {
        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter(
                @Advice.This PacketTypes.PacketType type,
                @Advice.Argument(0) ByteBufferReader reader) {
            return AdminCoreRespawnBridge.loading(type, reader);
        }

        @Advice.OnMethodExit
        public static void exit(
                @Advice.Enter boolean handled, @Advice.Return(readOnly = false) boolean result) {
            if (handled) result = true;
        }
    }

    public static final class Response {
        @Advice.OnMethodEnter
        public static void enter(@Advice.Argument(0) ByteBufferReader reader) {
            AdminCoreRespawnBridge.response(reader, false);
        }
    }
}
