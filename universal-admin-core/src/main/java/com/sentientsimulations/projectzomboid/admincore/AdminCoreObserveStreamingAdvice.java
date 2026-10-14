package com.sentientsimulations.projectzomboid.admincore;

import net.bytebuddy.asm.Advice;
import zombie.characters.IsoGameCharacter;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoChunkMap;
import zombie.iso.IsoGridSquare;

public final class AdminCoreObserveStreamingAdvice {
    public static class PhysicalMap {
        @Advice.OnMethodEnter
        public static void enter(
                @Advice.This IsoChunkMap map,
                @Advice.Argument(value = 0, readOnly = false) IsoGameCharacter character) {
            character = AdminCoreObserveStreaming.physicalCharacter(map, character);
        }
    }

    public static class Accept {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.Argument(0) IsoChunk chunk,
                @Advice.Return(readOnly = false) boolean accepted) {
            if (AdminCoreObserveStreaming.accept(chunk)) accepted = true;
        }
    }

    public static class Request {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.Argument(0) IsoChunk chunk,
                @Advice.Return(readOnly = false) boolean allowed) {
            if (AdminCoreObserveStreaming.shouldRequest(chunk)) allowed = true;
        }
    }

    public static class Square {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.This IsoCell cell,
                @Advice.Argument(0) int x,
                @Advice.Argument(1) int y,
                @Advice.Argument(2) int z,
                @Advice.Return(readOnly = false) IsoGridSquare square) {
            if (square == null) square = AdminCoreObserveStreaming.square(cell, x, y, z);
        }
    }

    public static class Chunk {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.This IsoCell cell,
                @Advice.Argument(0) int x,
                @Advice.Argument(1) int y,
                @Advice.Return(readOnly = false) IsoChunk chunk) {
            if (chunk == null) chunk = AdminCoreObserveStreaming.chunk(cell, x, y);
        }
    }

    public static class ChunkSquare {
        @Advice.OnMethodExit
        public static void exit(
                @Advice.This IsoCell cell,
                @Advice.Argument(0) int x,
                @Advice.Argument(1) int y,
                @Advice.Return(readOnly = false) IsoChunk chunk) {
            if (chunk == null)
                chunk =
                        AdminCoreObserveStreaming.chunk(
                                cell, Math.floorDiv(x, 8), Math.floorDiv(y, 8));
        }
    }
}
