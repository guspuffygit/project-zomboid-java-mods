# GlobalModDataPacket Bug in Project Zomboid Build 42.15.0

## Summary

Build 42.15.0 introduced a regression in `GlobalModDataPacket.parse()` that causes **all** `ModData.request()` responses to deliver `false` instead of the actual `KahluaTable` to Lua. This breaks any mod that uses `OnReceiveGlobalModData` to receive global mod data on the client.

## Affected File

`zombie.network.packets.service.GlobalModDataPacket`

## Root Cause

When the packet format was refactored from raw byte/ByteBuffer operations to the `ByteBufferReader`/`ByteBufferWriter` API, the boolean condition in `parse()` was inverted.

### Old code (Build 42.14.1)

```java
public void write(ByteBufferWriter b) {
    b.putUTF(this.tag);
    b.putByte((byte)1);          // 1 = data follows
    this.table.save(b.bb);
}

public void parse(ByteBuffer b, IConnection connection) {
    String tag = GameWindow.ReadString(b);
    if (b.get() != 1) {          // byte != 1 → no data
        LuaEventManager.triggerEvent("OnReceiveGlobalModData", tag, false);
        return;
    }
    KahluaTable table = LuaManager.platform.newTable();
    table.load(b, 243);
    LuaEventManager.triggerEvent("OnReceiveGlobalModData", tag, table);
}
```

### New code (Build 42.15.0) — BUGGY

```java
public void write(ByteBufferWriter b) {
    b.putUTF(this.tag);
    b.putBoolean(true);           // true = data follows
    this.table.save(b.bb);
}

public void parse(ByteBufferReader b, IConnection connection) {
    String tag = b.getUTF();
    if (b.getBoolean()) {         // BUG: true means data IS present, but this branch sends false
        LuaEventManager.triggerEvent("OnReceiveGlobalModData", tag, false);
        return;                   // returns early, never reads the table
    }
    KahluaTable table = LuaManager.platform.newTable();
    table.load(b.bb, 244);
    LuaEventManager.triggerEvent("OnReceiveGlobalModData", tag, table);
}
```

### What should have been written

```java
if (!b.getBoolean()) {            // negated — false means no data
    LuaEventManager.triggerEvent("OnReceiveGlobalModData", tag, false);
    return;
}
```

The `write()` method always writes `true` (data present). The `parse()` method reads that `true`, enters the `if` branch, fires the event with `false`, and returns — **never deserializing the table data**.

## How It Manifests

Any mod that listens for `OnReceiveGlobalModData` receives `false` as the second argument instead of a `KahluaTable`. When the mod then tries to index into this value (e.g., `modData[key]`), the Kahlua VM throws:

```
attempted index: <key> of non-table: false
```

### Example stack traces (from Another Vehicle Claim System)

```
attempted index: 1.77310742615E11 of non-table: false
  function: checkPermission -- file: AVCSShared.lua line # 152
```

```
attempted index: Gus Puffy of non-table: false
  function: updateListVehicles -- file: AVCSUserManagerMain.lua line # 145
```

In both cases, `AVCS.dbByVehicleSQLID` and `AVCS.dbByPlayerID` are `false` because `ClientOnReceiveGlobalModData` stored the `false` value it received from the event.

## Impact

- **Severity:** High — breaks all mods using `ModData.request()` / `OnReceiveGlobalModData` on multiplayer clients.
- **Scope:** Any mod using the global mod data system. Single-player and server-side `ModData.get()` calls are unaffected (they read directly from the `HashMap`).

## Workarounds

### Option 1: Lua guard (partial)

Add a type check in `OnReceiveGlobalModData` handlers:

```lua
function MyMod.ClientOnReceiveGlobalModData(key, modData)
    if key == "MyModData" and type(modData) == "table" then
        MyMod.data = modData
    end
end
```

This prevents the crash but **does not fix the underlying issue** — the client still never receives the actual data because `parse()` never deserializes the table.

### Option 2: Storm bytecode patch (full fix)

Use Storm's Byte Buddy patching to fix the inverted boolean in `GlobalModDataPacket.parse()`. This restores correct behavior for all mods.

## Diff (42.14.1 → 42.15.0)

```diff
--- a/zombie/network/packets/service/GlobalModDataPacket.java
+++ b/zombie/network/packets/service/GlobalModDataPacket.java
@@ -25,7 +24,7 @@
    public void write(ByteBufferWriter b) {
       b.putUTF(this.tag);
-      b.putByte((byte)1);
+      b.putBoolean(true);

@@ -35,16 +34,16 @@
-   public void parse(ByteBuffer b, IConnection connection) {
+   public void parse(ByteBufferReader b, IConnection connection) {
       try {
-         String tag = GameWindow.ReadString(b);
-         if (b.get() != 1) {
+         String tag = b.getUTF();
+         if (b.getBoolean()) {              // ← inverted condition
             LuaEventManager.triggerEvent("OnReceiveGlobalModData", tag, false);
             return;
          }
          KahluaTable table = LuaManager.platform.newTable();
-         table.load(b, 243);
+         table.load(b.bb, 244);
          LuaEventManager.triggerEvent("OnReceiveGlobalModData", tag, table);
```
