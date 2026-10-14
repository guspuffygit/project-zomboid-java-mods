# UAC operations review

Version 0.2.7-alpha targets PZ 42.21.0 with compatible Storm on both peers.

| Area | Behavior |
| --- | --- |
| Navigation | Four sections, expandable groups, search, responsive paging and persistent window geometry. |
| Compact Admin | Personal pins, search, collapse and unfocused fade. Uses the same registered actions as full UAC. |
| Admin Powers | Native powers grouped by function, search, presets and server-confirmed state. |
| Lists | Safehouse/faction name and owner search, tag search and alphabetical sorting. |
| Safehouses | Placement preview and in-place Expand/Redraw with confirmation and bounded history. |
| Observe | Follow, Soft Follow, Free Camera, selected-player information, overlays and a minimized status bar. |
| Travel | Teleport To without observing, server-recorded origin and separate one-shot Return. |
| User Panel | Tickets removed, including search and stale Compact Admin pins. |

Safehouse respawn selection, Mini UI Core/Combat Health and Lifestyle integration
are separate PRs. Ordinary safehouse and faction membership permissions remain
native. Server layout editing and expanded horde behavior remain future work.

## Authorization

New operations require existing native capabilities and a server feature grant.
UI visibility never grants access. Feature gates include `ADMIN_POWER_BASIC`,
`ADMIN_POWER_MOVEMENT`, `ADMIN_SPECTATOR`, `ADMIN_RENDER_DEBUG`,
`ADMIN_SAFEHOUSE_EDIT`, `ADMIN_WORLD_EDIT`, `ADMIN_DEBUG_TOOLS` and
`ADMIN_HORDE_MANAGER`.

Operators can restrict features in persisted world ModData
`UniversalAdminCore.OperationsPolicy.v1`: `disabled[feature]=true`,
`users[username][feature]=false`, or `disabledTools[toolId]=true`.
No client policy-editing command is provided. Native tools retain native server
authorization; new powers/debug handlers also enforce their UAC restrictions.

Power requests use a fixed list of native getters/setters. They cannot select
another player or arbitrary method. Saved UAC powers are rechecked on rejoin;
revocation disables disallowed UAC values without enabling saved ones.

## Boundary editing and observation

Boundary commits recheck permissions, snapshot, coordinates and overlap. The
same claim keeps its owner, members and existing respawn preferences. Community
and Garage need their companion identity readers before boundary edits. See
[boundary use](docs/SAFEHOUSE-BOUNDARY.md) and
[compatibility patches](docs/compatibility/SAFEHOUSE-BOUNDARIES.md).

Observation uses a bounded server-approved region and expiring lease. Camera
updates never move the avatar or widen its gameplay relevance. The old periodic
follow teleport and movement tracker are removed. Missing patch support fails
closed. Player Info shows available replicated position and held item; Facing
means body direction rather than weapon aim. See the
[observer review](docs/OBSERVE-VISIBILITY-REVIEW.md) for streaming and render limits.

## Validation

Java tests weave the installed native game methods; Lua fixtures run under Lua
5.1 and installed-game Kahlua. Formatting, static analysis and package scope are
checked separately. The user reports local boundary editing and observation
working. No measured FPS improvement or live-server acceptance is claimed.
