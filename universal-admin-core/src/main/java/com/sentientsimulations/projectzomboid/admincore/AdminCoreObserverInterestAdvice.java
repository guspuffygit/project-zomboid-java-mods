package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.core.raknet.UdpConnection;
import zombie.network.ServerMap;

public final class AdminCoreObserverInterestAdvice {
    private AdminCoreObserverInterestAdvice() {}

    public static final class Chunk {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.FieldValue("connection") UdpConnection connection,
                @Advice.Argument(0) int wx,
                @Advice.Argument(1) int wy,
                @Advice.Return(readOnly = false) boolean allowed) {
            if (!allowed) allowed = AdminCoreObserverInterest.chunk(connection, wx, wy);
        }
    }

    public static final class Retain {
        @Advice.OnMethodEnter
        public static void enter(@Advice.This ServerMap map) {
            AdminCoreObserverInterest.retain(map);
        }
    }

    public static final class Outside {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.Argument(0) ServerMap.ServerCell cell,
                @Advice.Return(readOnly = false) boolean outside) {
            if (outside && AdminCoreObserverInterest.retained(cell)) outside = false;
        }
    }
}
