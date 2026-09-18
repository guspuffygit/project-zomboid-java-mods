# Universal Admin Core

Project Zomboid 42.20.4 administration module. Requires compatible Storm on server
and client. This module does not require the ATF Economy module.

The Admin Panel provides searchable categories and native actions. The User List
provides selected-player administration, membership tools and observation. Ordinary
safehouse/faction invitation searches retain native permissions. Visible-row caching
limits repeated user-list work. The admin can also use Add Item on their own inventory.

Resize handles and Size controls adjust supported windows. Closing a window stores
its geometry immediately; reopening restores it, clamped to the current screen.
The native layout.ini provides persistence across client sessions.

Observe requires server-validated capabilities, invisibility, god mode and noclip.
It follows a streamed target from the admin's client; it is not the target's screen.
Stop/Esc and lease expiration return to the server-recorded origin. A camera-selection
exception disables observation locally and returns the original camera character.

## Extension contract

Register administration actions through AdminCore/Registry.lua. Keep authorization
on the server; UI visibility alone is insufficient. Java bridge membership methods
check capability before querying accounts. Production Java logs use SLF4J.

## Validation

Set gameDir in local.properties. Run ./gradlew :universal-admin-core:test
:universal-admin-core:luaKahluaTest :universal-admin-core:spotlessCheck.
On Windows use gradlew.bat. Lua 5.1 must be installed; override with
-PluaExecutable=/path/to/lua5.1. Tests and Lua formatting are integrated into Gradle.
Use the repository deployMod task for packaging; never publish a test build to Workshop.

## Integration limits

The repository declares Storm 42.20.4_2.10.0; the local test runtime uses
42.20.4_2.10.2-SNAPSHOT. Installed-runtime validation must not be presented as an unmodified build.
UI hooks depend on the supported vanilla Lua layout and camera method signatures.
Fixtures and bytecode weaving checks do not replace an in-game two-client session.
Verify observe start/stop/error recovery, role revocation, membership updates, resize
dragging, long names, different UI scales and close/reopen before merging.
