package com.sentientsimulations.projectzomboid.atfcasino.npc;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import org.jetbrains.annotations.Nullable;
import zombie.characters.IsoPlayer;
import zombie.characters.SurvivorDesc;
import zombie.characters.SurvivorFactory;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.core.skinnedmodel.visual.ItemVisuals;
import zombie.inventory.InventoryItem;
import zombie.inventory.InventoryItemFactory;
import zombie.inventory.types.Clothing;
import zombie.iso.IsoDirections;
import zombie.iso.IsoWorld;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.packets.INetworkPacket;
import zombie.network.packets.character.PlayerPacket;

/**
 * A stationary synthetic {@link IsoPlayer} streamed to clients the same way the security mod's
 * ESP-trap decoys are: never registered in {@code GameServer.IDToPlayerMap} (so it is not a real
 * player for saves, counts or PvP), introduced to each relevant connection with {@code
 * ConnectedPlayer}/{@code ExtraInfo}/{@code Equip} and kept alive with periodic {@code
 * PlayerUpdateReliable} packets whose position never changes. Because the server never answers
 * {@code PlayerDataRequest} for it, the introduction is simply repeated every few seconds; a repeat
 * is a client-side no-op while the NPC is known and a re-create after a timeout.
 *
 * <p>Construct on the server main thread only — the {@link IsoPlayer} constructor touches the
 * world's object lists.
 */
public final class CasinoNpc {

    // Real players get onlineIds of slot*4 (+index), so this range is far above any live player
    // and below the ESP-trap decoy range (30000+) so the two never collide.
    private static final short ID_BASE = (short) 29000;

    private static final String OUTFIT = "Spiffo";
    private static final String[] REQUIRED_WORN_ITEMS = {
        "Base.SpiffoSuit", "Base.Hat_Spiffo", "Base.SpiffoTail"
    };

    private final String name;
    private final short id;
    private float x;
    private float y;
    private float z;
    private float facing;
    private final @Nullable String weaponType;
    private @Nullable IsoPlayer fake;

    public CasinoNpc(
            int slot,
            String name,
            int tileX,
            int tileY,
            int tileZ,
            float facing,
            @Nullable String weaponType) {
        this.name = name;
        this.id = (short) (ID_BASE + slot);
        this.x = CasinoLayout.centre(tileX);
        this.y = CasinoLayout.centre(tileY);
        this.z = tileZ;
        this.facing = facing;
        this.weaponType = weaponType;
    }

    public String name() {
        return name;
    }

    public short id() {
        return id;
    }

    public float x() {
        return x;
    }

    public float y() {
        return y;
    }

    public float z() {
        return z;
    }

    public boolean isBuilt() {
        return fake != null;
    }

    /**
     * Live reposition (tile coordinates, from sandbox options). Updates the backing IsoPlayer when
     * built; the next keepalive broadcast carries the new spot, so clients see the move within a
     * tick. The table anchors and guard watch radius read these fields, so they follow too.
     */
    public void moveTo(int tileX, int tileY, int tileZ) {
        float nx = CasinoLayout.centre(tileX);
        float ny = CasinoLayout.centre(tileY);
        if (nx == x && ny == y && tileZ == (int) z) {
            return;
        }
        x = nx;
        y = ny;
        z = tileZ;
        if (fake != null) {
            fake.setX(x);
            fake.setY(y);
            fake.setZ(z);
        }
        LOGGER.info("[AtfCasino] moved NPC {} (id {}) to {},{},{}", name, id, x, y, z);
    }

    /**
     * Live re-facing (radians, from the {@code AtfCasino.<Npc>Facing} sandbox option). The next
     * keepalive broadcast carries the new direction, so clients see the turn within a tick.
     */
    public void faceTo(float facingRadians) {
        if (facingRadians == facing) {
            return;
        }
        facing = facingRadians;
        if (fake != null) {
            applyFacing(fake);
        }
        LOGGER.info("[AtfCasino] turned NPC {} (id {}) to {} rad", name, id, facing);
    }

    // Keeps the backing IsoPlayer's direction in step with the packets, so the ConnectedPlayer
    // introduction shows the right facing before the first keepalive lands.
    private void applyFacing(IsoPlayer p) {
        p.setForwardDirection((float) Math.cos(facing), (float) Math.sin(facing));
        p.setDir(IsoDirections.fromAngle(facing));
    }

    public @Nullable IsoPlayer fake() {
        return fake;
    }

    /** Build the backing IsoPlayer. Returns false if the world is not ready yet. */
    public boolean build() {
        if (fake != null) {
            return true;
        }
        if (IsoWorld.instance == null || IsoWorld.instance.currentCell == null) {
            return false;
        }
        SurvivorDesc desc = SurvivorFactory.CreateSurvivor();
        if (desc == null) {
            LOGGER.warn("[AtfCasino] SurvivorFactory.CreateSurvivor returned null for {}", name);
            return false;
        }
        // Dress the desc before constructing: the constructor's Dressup(desc) copies wornItems.
        desc.setFemale(false);
        desc.dressInNamedOutfit(OUTFIT);
        IsoPlayer p = new IsoPlayer(IsoWorld.instance.currentCell, desc, 0, 0, 0);
        p.setUsername(name);
        p.setDisplayName(name);
        p.setOnlineID(id);
        p.setInvisible(false, false);
        p.remote = true;
        dress(p);
        try {
            p.removeFromWorld();
            p.removeFromSquare();
        } catch (Throwable t) {
            LOGGER.debug("[AtfCasino] removeFromWorld noop for {}: {}", name, t.toString());
        }
        p.setX(x);
        p.setY(y);
        p.setZ(z);
        applyFacing(p);
        fake = p;
        LOGGER.info("[AtfCasino] built NPC {} (id {}) at {},{},{}", name, id, x, y, z);
        return true;
    }

    private void dress(IsoPlayer p) {
        try {
            p.setFemale(false);
            if (p.getHumanVisual() != null) {
                ItemVisuals visuals = new ItemVisuals();
                p.getHumanVisual().dressInNamedOutfit(OUTFIT, visuals);
                p.getWornItems().setFromItemVisuals(visuals);
                for (String itemType : REQUIRED_WORN_ITEMS) {
                    InventoryItem item = InventoryItemFactory.CreateItem(itemType);
                    if (item instanceof Clothing) {
                        p.getWornItems().setItem(item.getBodyLocation(), item);
                    }
                }
            }
            if (weaponType != null) {
                InventoryItem weapon = InventoryItemFactory.CreateItem(weaponType);
                if (weapon != null) {
                    p.setPrimaryHandItem(weapon);
                    p.setSecondaryHandItem(weapon);
                }
            }
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] dressing {} failed: {}", name, t.toString(), t);
        }
    }

    /** Push identity, role flags and hand items to one connection. Safe to repeat. */
    public void introduce(UdpConnection conn) {
        if (fake == null) {
            return;
        }
        try {
            GameServer.sendPlayerConnected(fake, conn);
            INetworkPacket.send(conn, PacketTypes.PacketType.ExtraInfo, fake, true);
            if (fake.getPrimaryHandItem() != null || fake.getSecondaryHandItem() != null) {
                INetworkPacket.send(conn, PacketTypes.PacketType.Equip, fake);
            }
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] introduce {} failed: {}", name, t.getMessage());
        }
    }

    /** Static position snapshot; doubles as the client-side timeout keepalive. */
    public void sendUpdate(UdpConnection conn) {
        if (fake == null) {
            return;
        }
        try {
            // Built by hand rather than PlayerPacket.set(): that path goes through
            // NetworkPlayerAI's timer gate and yields an empty prediction for a synthetic
            // player that never ticks.
            PlayerPacket packet = new PlayerPacket();
            packet.id.set(fake);
            packet.variables.set(fake);
            packet.prediction.type = (byte) 0;
            packet.prediction.x = x;
            packet.prediction.y = y;
            packet.prediction.z = (byte) z;
            packet.prediction.direction = facing;
            packet.prediction.moveDirection = facing;
            packet.prediction.speed = 0.0F;
            packet.prediction.distance = 0;
            packet.prediction.pathFindX = x;
            packet.prediction.pathFindY = y;
            packet.prediction.position.set(x, y, z);
            packet.booleanVariables = 0;
            packet.disconnected = false;

            PacketTypes.PacketType type = PacketTypes.PacketType.PlayerUpdateReliable;
            ByteBufferWriter b = conn.startPacket();
            try {
                type.doPacket(b);
                packet.write(b);
                type.send(conn);
            } catch (Throwable inner) {
                conn.cancelPacket();
                throw inner;
            }
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] update {} failed: {}", name, t.getMessage());
        }
    }

    public void sendTimeout(UdpConnection conn) {
        if (fake == null) {
            return;
        }
        try {
            INetworkPacket.send(conn, PacketTypes.PacketType.PlayerTimeout, fake);
        } catch (Throwable t) {
            LOGGER.warn("[AtfCasino] timeout {} failed: {}", name, t.getMessage());
        }
    }

    /** Chebyshev tile distance from this NPC to a point, or +inf when on another floor. */
    public float distanceTo(float px, float py, float pz) {
        if ((int) Math.floor(pz) != (int) z) {
            return Float.POSITIVE_INFINITY;
        }
        return Math.max(Math.abs(px - x), Math.abs(py - y));
    }
}
