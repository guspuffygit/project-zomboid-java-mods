# 📋 After The Fall — Economy System PRD

**Version 0.2** — reconciled with shipped code on 2026-05-29 (was a v0.1 greenfield draft).

Status legend: ✅ shipped · 🟡 partial · ⛏️ planned

> This is the **product-level** view: intent + status. As-built implementation detail lives in
> [`README.md`](./README.md); the slice-by-slice build plan and test coverage live in
> [`CLAUDE.md`](./CLAUDE.md). Where those disagree with this file on detail, they win — this file is
> the map, not the territory.

---

## 0. Snapshot — what's live today

The economy already runs server-authoritatively on a SQLite ledger. Shipped:

- ✅ **Server-authoritative ledger + balances** — append-only `economy_transactions` with an atomic, denormalized `economy_balance`. SQLite (`<save>/survivor_economy.db`, WAL).
- ✅ **Hourly paycheck** — playtime accrues each in-game hour; past a threshold the server credits a paycheck.
- ✅ **Zombie bounty** — attributed kills roll a chance + amount.
- ✅ **In-person player → player transfers** — right-click a nearby player → *Send Money*.
- ✅ **In-game balance window** — money button on the equipped-item bar.
- ✅ **Discord integration (Beacon bot)** — account linking (bidirectional codes), per-Discord escrow wallets, tipping, and balance/account queries over HTTP.
- ✅ **HTTP API** — transactions, balances, single-event lookup, Discord endpoints, admin SQL escape hatch.

**Not built yet:** the **Shop System** (§1), the **Scraps / Relics** currency split (§2), and the **website / market graph** (§3–4).

---

## 🏪 1. Shop System — ⛏️ planned

Shops are constructable stands with tiered capacity. Higher-tier stands require greater carpentry/metalworking skill to build.

- **Tiered capacity** — higher quality stands hold more items (low tier = 10 items per stand).
- **Additive stacking** — 3× low-tier stands = 30 total slots.
- **Shared inventory** — all stands owned by the same player share one global inventory pool.
- **Claiming** — any player can claim an unclaimed stand; builder and owner can differ.

> **Status:** no code today beyond a placeholder `shop_category` column in the ledger. This is the
> largest unbuilt pillar, and §4 (trade tracking / market graph) depends on it — a shop sale is the
> first thing that will actually write trade rows.

---

## 💰 2. Currency — 🟡 partial

The ledger is **multi-bucket**: currencies are free-form strings, so adding currencies needs no
schema change. Today every earning path credits a single `primary` bucket — the Scraps / Relics
split below is the intended shape, not yet wired.

### Scraps (tradeable) — 🟡 not yet split from `primary`

The primary tradeable currency, for buying and selling between players. Earning paths:

- ✅ **Killing zombies** — zombie bounty (defaults: 1–10 @ 10% chance per kill).
- 🟡 **Surviving time** — shipped as an **hourly paycheck** (defaults: 200 every 24 in-game hours of playtime), *not* literally "per day survived." Configurable via Sandbox options. See open question.
- 🟡 **Discord community** — account linking and peer-to-peer tipping are live; a dedicated "award for contributions" grant is not (today an admin grants via `/economy/sql`).

### Relics (non-tradeable, prestige) — ⛏️ planned

No earning path, no bucket, and no non-tradeable enforcement yet. The ledger can hold a `relics`
bucket the moment we decide how it's earned and spent — but "non-tradeable" means actively blocking
transfer / tip / shop on that bucket, which is net-new logic.

---

## 🗄️ 3. Data & Integrations — 🟡 mostly shipped

A shared SQLite database, written by the game server and read/written by the Beacon Discord bot over
Storm's HTTP API.

| Consumer | Access | Status |
|---|---|---|
| Game server | Read/write balances, ledger, player state at runtime | ✅ |
| Discord bot (Beacon) | Link accounts, query balances/accounts, escrow wallets, peer tipping | ✅ |
| Website / API | Read endpoints exist; no site, leaderboard, or market graph yet | 🟡 |

**Database choice: resolved — SQLite** (WAL, `foreign_keys=ON`) at `<save>/survivor_economy.db`. (The
v0.1 "SQLite vs Postgres/MySQL" open question is closed.) Tables: `economy_transactions`,
`economy_balance`, `economy_player_state`, `discord_links`, `discord_link_codes`.

**Discord identity model:** a Discord user is encoded as a synthetic player —
`(username = snowflake, steamid = −snowflake)` — so escrow wallets reuse the exact ledger/balance
machinery with no schema change (a negative steamid is unambiguously a Discord escrow, since real
Steam64 IDs are always positive). See `DiscordPlayerIdentity`.

**Discord HTTP endpoints** (consumed by Beacon):

- `POST /economy/discord/link/code/discord` — mint a link code
- `GET  /economy/discord/link?discordId=` and `…/by-steam?steamId=` — list links (both directions)
- `GET  /economy/discord/accounts?discordId=` — balances across all linked Steam IDs
- `POST /economy/discord/tip` — atomic tip into a recipient's escrow wallet
- `GET  /economy/discord/wallet?discordId=` — escrow wallet balances

In-game, players mint/claim links and pull escrow funds into their character via client→server
commands (`claimDiscordLink`, `requestDiscordLinks`, `claimDiscordWallet`); UI in
`SurvivorEconomy_LinkUI.lua`.

---

## 📈 4. Trade Tracking & Market Graph — 🟡 partial

Every money event is **already** recorded append-only in `economy_transactions`. The per-trade fields
the PRD wants map cleanly onto existing columns:

| PRD field | Ledger column |
|---|---|
| item name | `item_id` (immutable id, not the display name) |
| item category | `shop_category` |
| price (scraps) | `amount` (signed) + `currency` |
| seller / buyer (Steam ID) | `player_steamid` on the FROM / TO rows of the paired event |
| timestamp | `timestamp_ms` |

> **Status:** the data model is ready, but the producers and the front-end are not — ⛏️ no shop
> trades are written yet (depends on §1), and ⛏️ the market graph / website rendering doesn't exist.

> Gus Note: Need to expose item names based on item_id in computed column when pulling data to the website/UI
---

## ❓ 5. Open Questions (updated)

**Resolved since v0.1:**

- ~~Database tech (SQLite vs Postgres/MySQL)~~ → **SQLite**, shipped.

**Still open:**

- **Currency split** — rename `primary` → `scraps`, or run `scraps` as a new bucket alongside legacy `primary`? What happens to existing `primary` balances?
- **Relics** — which activities award them, at what rates? How is "non-tradeable" enforced (block transfer / tip / shop on the `relics` bucket)?
- **"Per survival day" vs hourly paycheck** — keep the shipped hourly-playtime model, or add a true per-in-game-day award?
- **Scraps balance tuning** — per-kill and per-day rates (current defaults: bounty 1–10 @ 10%; paycheck 200 / 40h).
- **Discord "award for contributions" flow** — manual admin (`/economy/sql`) vs a dedicated system→user grant endpoint.
- **Shop tier capacities** — mid / high-tier slot counts (low = 10).
- **Website API auth** — Steam ID + token?
- **Future Relic sinks** — what do you spend prestige currency on?

---

## 6. Where the code lives

- Java package: `src/main/java/com/sentientsimulations/projectzomboid/survivoreconomy/`
- As-built reference: [`README.md`](./README.md)
- Slice-by-slice plan + test coverage: [`CLAUDE.md`](./CLAUDE.md)
- Discord HTTP surface: `DiscordLinkEndpoints.java` · identity model: `DiscordPlayerIdentity.java`
</content>
</invoke>
