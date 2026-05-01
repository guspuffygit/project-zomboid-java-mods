# Survivor Economy

A Storm mod for Project Zomboid (Build 42) that adds a server-authoritative economy: every credit and debit lands in an append-only SQLite ledger, and a denormalized balance table is updated atomically alongside the ledger so the client can read a single row instead of replaying history.

Workshop: `3717671025` (prod) / `3717671739` (stage) / `3717669793` (dev).
Maven group: `com.sentientsimulations.projectzomboid`.
Requires: [Storm](https://steamcommunity.com/sharedfiles/filedetails/?id=3670772371) mod loader.

## What it does (shipped today)

- **Hourly paycheck.** Each in-game hour, every online player accrues one hour of playtime. Once their accrued hours pass the configured threshold the server credits a paycheck to their `primary` currency, decrements the threshold, and pushes a blue halo (`Paycheck: +$N`) to that player.
- **Zombie bounty.** When a player kills a zombie (not seated in a vehicle, attributed via `IsoZombie.getAttackedBy()`), the server rolls a chance and an amount, credits the rolled amount to the killer's `primary` currency on a hit, and pushes a green halo (`Zombie bounty: +$N`).
- **Player → player money transfer.** Right-clicking another player within range shows a *Send Money* submenu listing every non-zero currency the sender holds. Picking one pops a numeric prompt; on submit the server validates range + balance, atomically debits the sender and credits the recipient, and pushes halo notifications to both sides (`-$N to <recipient>` blue, `+$N from <sender>` green). Failures (insufficient balance, out of range, etc.) push a red halo to the sender with the failure reason.
- **In-game balance window.** A money button is monkey-patched onto the equipped-item bar; clicking it toggles a panel listing every `(currency, balance)` pair the player holds. The panel auto-refreshes whenever the server pushes a balance update.
- **Server-pushed balance sync.** Every transaction recorded by the server triggers a `balanceUpdated` push to the affected player(s) (FROM and TO sides for transfers). Clients also send a one-shot `requestBalance` on first tick after connecting so reconnects start from the server-authoritative value.
- **HTTP API.** Transactions, balances, and a single-event lookup are exposed as JSON for external tooling. An admin SQL escape hatch is also wired up.

The transaction log is the source of truth — every gameplay event that touches money writes one or more rows to `economy_transactions` and an atomic upsert to `economy_balance` in the same SQL transaction.

## Architecture

```
src/main/java/com/sentientsimulations/projectzomboid/survivoreconomy/
├── SurvivorEconomyMod.java                     # Storm entry point + event handlers
├── SurvivorEconomyBridge.java                  # Static facade — game-thread seam to pure logic
├── SurvivorEconomyDatabase.java                # SQLite connection + schema/index DDL
├── SurvivorEconomyRepository.java              # economy_transactions + atomic balance upsert
├── SurvivorEconomyBalanceRepository.java       # economy_balance reads/writes
├── SurvivorEconomyPlayerStateRepository.java   # economy_player_state (online hours)
├── SurvivorEconomyPaycheck.java                # Pure-logic paycheck tick
├── SurvivorEconomyZombieBounty.java            # Pure-logic bounty roll + insert
├── SurvivorEconomyTransfer.java                # Pure-logic player→player transfer
├── SurvivorEconomyConfig.java                  # SandboxOptions accessors with defaults
├── SurvivorEconomyEndpoints.java               # @HttpEndpoint handlers
└── records/                                    # Drafts, DTOs, response shapes
```

```
media/
├── sandbox-options.txt                         # 9 sandbox options (paycheck + bounty + transfer)
├── ui/                                         # Money_Icon_On.png / Money_Icon_Off.png
└── lua/
    ├── shared/Translate/EN/                    # Sandbox.json, UI.json, IG_UI.json
    └── client/
        ├── SurvivorEconomyClient.lua           # OnServerCommand listener + balance cache
        ├── ISUI/SurvivorEconomy/
        │   └── SurvivorEconomy_UI.lua          # Equipped-item bar money button + balance panel
        └── UI/Context/
            └── SurvivorEconomyPay.lua          # Right-click "Send Money" submenu
```

The Bridge is the only class that touches `IsoPlayer`, `SandboxOptions`, `GameServer`, or `ThreadLocalRandom`. The pure-logic classes (`Paycheck`, `ZombieBounty`, `Transfer`) take repos + primitive sandbox values + injected `IntSupplier` rolls so unit tests can drive them with a real SQLite `@TempDir` and zero PZ runtime.

Each DB operation opens a fresh JDBC connection so the game-thread path and HTTP worker threads do not contend on a shared connection.

## Database

SQLite file: `<save>/survivor_economy.db` (resolved via `ZomboidFileSystem.getFileInCurrentSave`). PRAGMAs: `journal_mode=WAL`, `foreign_keys=ON`.

### `economy_transactions` (append-only ledger)

Every credit or debit is one row. SOLE rows for one-sided events (paycheck, bounty, admin grant, death loss). FROM/TO row pairs for two-sided events (player→player transfer); both sides share a generated `event_id` and are written in a single SQL transaction.

| column            | type    | notes                                                            |
|-------------------|---------|------------------------------------------------------------------|
| id                | INTEGER | primary key                                                      |
| event_id          | TEXT    | one per logical event; FROM and TO rows of a transfer share it   |
| event_role        | TEXT    | `SOLE` / `FROM` / `TO` (CHECK constraint)                        |
| timestamp_ms      | INTEGER |                                                                  |
| type              | TEXT    | `PAYCHECK`, `ZOMBIE_BOUNTY`, `BANK_WIRE_TO_PLAYER`, …            |
| parent_event_id   | TEXT    | links child rows (fees / taxes) to the originating event         |
| reason            | TEXT    | optional human-readable annotation                               |
| player_username   | TEXT    | character name                                                   |
| player_steamid    | INTEGER |                                                                  |
| currency          | TEXT    | free-form bucket name (`primary`, `paycheck`, …)                 |
| amount            | REAL    | signed: `+` gained, `−` lost                                     |
| item_id           | TEXT    | for shop / loot rows                                             |
| item_qty          | INTEGER |                                                                  |
| vehicle_id        | TEXT    |                                                                  |
| shop_category     | TEXT    |                                                                  |
| wallet_id         | TEXT    |                                                                  |
| account_number    | TEXT    |                                                                  |
| death_x / y / z   | REAL    | recorded inline on `DEATH_LOSS` rows                             |

Indexes: `event_id`, `(player_username, player_steamid)`, `type`, `timestamp_ms`.

Identity is `(player_username, player_steamid)` — multiple characters on one Steam account are tracked as separate ledgers.

### `economy_balance` (denormalized running balance)

One row per `(player_username, player_steamid, currency)`, holding `SUM(amount)` over `economy_transactions` for the same key. Updated by `SurvivorEconomyBalanceRepository.applyDelta` from inside the same SQL transaction that inserts the matching ledger row(s), so the two tables stay in lockstep. Verified by unit tests including a forced-failure rollback that asserts both tables remain empty.

| column           | type    | notes                                              |
|------------------|---------|----------------------------------------------------|
| player_username  | TEXT    | composite PK part 1                                |
| player_steamid   | INTEGER | composite PK part 2                                |
| currency         | TEXT    | composite PK part 3                                |
| balance          | REAL    | `NOT NULL DEFAULT 0`                               |
| updated_at_ms    | INTEGER | `NOT NULL`                                         |

Index: `idx_econ_bal_steamid (player_steamid)`.

Upsert SQL: `INSERT … ON CONFLICT(player_username, player_steamid, currency) DO UPDATE SET balance = balance + excluded.balance, …`.

### `economy_player_state` (per-player counters)

One row per `(player_username, player_steamid)`. Today this only holds `online_hours` (driving the paycheck tick) and `last_clock_in_ms`. Designed to absorb future per-player state (e.g. per-bucket cooldowns) without a new table.

Index: `idx_econ_ps_steamid (player_steamid)`.

## Event flow

### `OnServerStartedEvent` (Storm)
`SurvivorEconomyMod.onServerStarted` opens the DB and runs DDL — creates the three tables and their indexes if they do not exist.

### `EveryHoursEvent` (Storm) — paycheck tick
Once per in-game hour, the mod iterates `GameServer.Players`. For each online player, `SurvivorEconomyBridge.processClockIn(player)` runs the pure-logic clock-in:

1. `online_hours += 1`.
2. If `online_hours >= HoursUntilPaycheck`:
   - If `IssuePaychecks` is true, insert one `PAYCHECK` SOLE row with `currency=primary` and `amount=+PaycheckValue`.
   - Decrement `online_hours -= HoursUntilPaycheck` regardless (carry-the-remainder).
3. Persist `online_hours` back to `economy_player_state`.

On a payout the bridge pushes `paycheckPaid` (blue halo) and `balanceUpdated` server→client commands to that player only — no broadcast.

### `OnZombieDeadEvent` (Storm) — zombie bounty
`SurvivorEconomyMod.onZombieDead` short-circuits on the client side, then attributes the kill via `zombie.getAttackedBy()` cast to `IsoPlayer`. Non-player kills (fire pre-clears `attackedBy`, ambient/world deaths, kills by other zombies) and vehicle-seated kills fall through. Otherwise `SurvivorEconomyBridge.processZombieKill(player)`:

1. If `PayZombieBounty` is false → no-op.
2. Roll `chanceRoll ∈ [0, 100]`; on `chanceRoll <= ZombieBountyChance` (inclusive) it is a hit.
3. Roll `amount ∈ [ZombieBountyMinAmount, ZombieBountyMaxAmount]`.
4. Insert a `ZOMBIE_BOUNTY` SOLE row with `currency=primary`, `amount=+rolled`, `reason=zombie_bounty`.

On a hit the bridge pushes `zombieBountyPaid` (green halo) and `balanceUpdated` to the killing player.

### `OnFillWorldObjectContextMenu` (Lua) — player → player transfer
Right-clicking another player within `PlayerTransferMaxDistance` tiles surfaces a *Send Money* submenu (one entry per non-zero currency from the local cache). Selecting an entry pops an `ISTextBox` numeric prompt and sends a `transferToPlayer` client→server command with `{ targetUsername, targetSteamId (string), currency, amount }`.

The Lua side stringifies the steamId because Kahlua's number type loses precision at the high end of the 64-bit Steam ID range; `SurvivorEconomyMod.readLong` parses it back to `Long` server-side.

The server (`SurvivorEconomyBridge.processTransfer`) re-checks distance and balance authoritatively, then `SurvivorEconomyTransfer.processTransfer`:

1. Reject non-finite or `≤ 0` amount → `INVALID_AMOUNT`.
2. Reject same-player → `SAME_PLAYER`.
3. Reject `senderBalance < amount` → `INSUFFICIENT_BALANCE`.
4. Insert paired `BANK_WIRE_TO_PLAYER` rows (FROM `−amount` / TO `+amount`) atomically.

On success the bridge pushes `transferSent` (blue halo, sender) + `transferReceived` (green halo, recipient) + `balanceUpdated` to both sides. On failure it pushes `transferFailed` to the sender with the failure-reason enum name as the translation suffix.

The flow requires both players online (the recipient is resolved via `findOnlinePlayer`); offline-recipient transfers will land with the planned `economy_accounts` slice.

### `OnClientCommandEvent` — `requestBalance`
On first tick after connecting, the client fires `requestBalance` once and self-removes the handler. The server responds with a `balanceUpdated` push containing the player's full per-currency balance map. Reconnects always start from the server-authoritative value.

### Server → client commands

| Command            | Payload                                                          | Client handler                                       |
|--------------------|------------------------------------------------------------------|------------------------------------------------------|
| `paycheckPaid`     | `{ amount, currency }`                                           | Blue halo `Paycheck: +$N`                            |
| `zombieBountyPaid` | `{ amount, currency }`                                           | Green halo `Zombie bounty: +$N`                      |
| `transferSent`     | `{ amount, currency, otherUsername, otherDisplayName }`          | Blue halo on sender                                  |
| `transferReceived` | `{ amount, currency, otherUsername, otherDisplayName }`          | Green halo on recipient                              |
| `transferFailed`   | `{ reason }` (enum name)                                         | Red halo on sender (`UI_SurvivorEconomy_TransferFailed_<reason>`) |
| `balanceUpdated`   | `{ balances: { currency → balance, … } }`                        | Rebuild `SurvivorEconomy.balances` cache + refresh balance window if open |

All halos use `IsoPlayer:setHaloNote(text, r, g, b, 300)`.

## Sandbox options

Declared in `media/sandbox-options.txt`, EN translations in `media/lua/shared/Translate/EN/Sandbox.json`, read through `SurvivorEconomyConfig` (which falls back to compile-time defaults if `SandboxOptions.instance.getOptionByName(...)` returns null — e.g. when the mod's options file is not shipped or lookup happens before SandboxOptions populates).

| Option                                    | Type     | Default | Range    | Effect                                                    |
|-------------------------------------------|----------|---------|----------|-----------------------------------------------------------|
| `SurvivorEconomy.IssuePaychecks`          | boolean  | true    |          | Enables paycheck payout. Hours still tick when false.     |
| `SurvivorEconomy.HoursUntilPaycheck`      | integer  | 40      | 1…336    | In-game hours of playtime per paycheck.                   |
| `SurvivorEconomy.PaycheckValue`           | integer  | 200     | 1…50000  | Amount credited per paycheck.                             |
| `SurvivorEconomy.PayZombieBounty`         | boolean  | true    |          | Enables zombie-kill bounties.                             |
| `SurvivorEconomy.ZombieBountyChance`      | integer  | 10      | 1…100    | Percent chance a kill earns a bounty (inclusive).         |
| `SurvivorEconomy.ZombieBountyMinAmount`   | integer  | 1       | 1…100    | Min bounty amount on a hit.                               |
| `SurvivorEconomy.ZombieBountyMaxAmount`   | integer  | 10      | 1…100    | Max bounty amount on a hit.                               |
| `SurvivorEconomy.AllowPlayerTransfers`    | boolean  | true    |          | Master switch for player→player transfers.                |
| `SurvivorEconomy.PlayerTransferMaxDistance` | integer | 4      | 1…50     | Max tile distance for in-person transfer.                 |

The defaults `IssuePaychecks=true` / `PayZombieBounty=true` mean first-run servers without an explicit config still pay out.

## HTTP API

The HTTP server is provided by Storm and enabled by launching the game with `-Dstorm.http.port=<port>`. Endpoints are registered via `@HttpEndpoint`.

| Method | Path                     | Query                                              | Returns                |
|--------|--------------------------|----------------------------------------------------|------------------------|
| GET    | `/economy/transactions`  | `limit?` (default 50, max 1000), `username?`, `steamId?`, `type?` | `TransactionsResponse` |
| GET    | `/economy/balance`       | `username` (req), `steamId` (req)                  | `BalanceResponse`      |
| GET    | `/economy/event`         | `eventId` (req)                                    | `TransactionsResponse` (every row sharing the event id) |
| POST   | `/economy/sql`           | body or `?sql=`                                    | `SqlExecutionResponse` (admin escape hatch — no sanitization) |

Invalid `steamId` → 400. Missing required params → 400.

## Building

```bash
./gradlew :survivor-economy:spotlessApply :survivor-economy:test
./gradlew :survivor-economy:installStorm
```

`installStorm` copies the built jar + `media/` into `~/Zomboid/Workshop/<workshopIdDev>/` for local dev, matching Storm's `-DstormType=local` resolution.

## Tests

Integration tests use real SQLite files in JUnit `@TempDir` — no PZ runtime, no mocked DB. The pure-logic classes (`Paycheck`, `ZombieBounty`, `Transfer`) are driven directly with deterministic timestamps, explicit sandbox values, and injected `IntSupplier` rolls.

- **`SurvivorEconomyTransactionsTest`** — full-column round-trip, `loadRecent` ordering + filtering, `parent_event_id` linkage, paired-insert rollback on failure.
- **`SurvivorEconomyBalanceTest`** — `economy_balance` invariants: stays equal to `SUM(amount)` from `economy_transactions` after every insert path, rolls back atomically on failure, restores auto-commit cleanly.
- **`SurvivorEconomyPaycheckTest`** — below-threshold no-op, threshold payout, carry-the-remainder, multi-character isolation, persistence across DB reopen, `IssuePaychecks=false` still decrements but writes no rows.
- **`SurvivorEconomyZombieBountyTest`** — `PayZombieBounty=false` no-op, chance miss vs hit, inclusive boundary at `chanceRoll == chance`, inclusive min/max bounds, accumulation across kills, multi-character isolation.
- **`SurvivorEconomyTransferTest`** — atomic sender/recipient movement, insufficient balance, self-transfer, zero/negative amount, multi-currency isolation, accumulation across sequential transfers.
