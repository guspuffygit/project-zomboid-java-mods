# ATF Mini UI Core

Version 0.1.2-alpha. Shared Lua window controls for Project Zomboid 42.21.0:
header dragging, focus fade, collapse/close controls, input capture and saved
layouts. No Storm or admin permissions are required.

Enable this module before [Combat Health](../combat-health/README.md). Other
client windows can use `require("MiniUI/Core")`. The production mod ID is
`atf-mini-ui-core-b42`; development and staging builds use the repository's
normal environment suffixes.

Native UI fixtures verify deferred resize handling, focus and capture cleanup,
one-time attachment and saved layout restoration. With the game installation
configured in `local.properties`, run:

```text
./gradlew :mini-ui-core:luaTest :mini-ui-core:luaKahluaTest :mini-ui-core:spotlessCheck
```

Lua 5.1 is required for `luaTest`; set `-PluaExecutable` if needed. The Kahlua
suite uses the installed game's interpreter. Test support is not deployed.
