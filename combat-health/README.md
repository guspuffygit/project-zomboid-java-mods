# ATF Combat Health

Version 0.2.5-alpha. Optional local-player HUD for Project Zomboid 42.21.0 with
injuries, recent XP and temperature. Requires [Mini UI Core](../mini-ui-core/README.md)
0.1.2-alpha. Neither module requires Storm, Universal Admin or Lifestyle.
The production mod ID is `atf-combat-health-b42`.

Open the normal **Health** panel and click **Mini HUD**, or use the sidebar's
right-click menu. An optional shortcut is under **Options > Key Bindings >
ATF Combat Health** and starts unbound. Enable both mods before joining for the
binding to appear.

Drag the header, use minus to collapse, X to close and the cog for settings.
The enabled HUD remains open while healthy. Injury rows scroll on small screens
or with large fonts. Position, section visibility and fade settings are saved.
**Keep open on respawn** is off by default; a manually closed HUD stays closed.

**Treat** uses native medical menus and timed actions with current inventory
and skill requirements. Best Treatment and Conserve Supplies choose an eligible
supply; Manual Selection and individual item choices remain available. Dirty
bandages use normal removal followed by bandaging. Treat and cog menus retain
focus while their submenu is open.

Rapid damage temporarily reveals the HUD and flashes red three times. The cog
can adjust the threshold, select reveal only or disable the alert. It does not
change the saved fade preference. Health warnings remain yellow at 50 or below
and red at 25 or below. Muscle strain is informational, without a Treat action.

Recent XP shows up to three skills for 30 seconds. Temperature uses visible
moodle information. Health refreshes at most five times a second, temperature
twice a second and multiplayer XP once a second. Disabled sections stop polling;
death and disconnect clear cached character data. Lifestyle Yoga XP is an
optional adapter and leaves that mod's award behavior intact.

## Validation

Configure `gameDir` in `local.properties`, then run:

```text
./gradlew :mini-ui-core:luaTest :combat-health:luaTest :mini-ui-core:luaKahluaTest :combat-health:luaKahluaTest :mini-ui-core:spotlessCheck :combat-health:spotlessCheck
```

Lua 5.1 is required for `luaTest`; use `-PluaExecutable` if needed. Tests load
installed native Health, context menu, sidebar and Options methods. To also
exercise the actual Lifestyle helper, pass `-PlifestyleModDir=/path/to/LifestyleHobbies`
or set `LIFESTYLE_MOD_ROOT`. That integration section is explicitly skipped when
no path is supplied; ordinary XP, temperature and cleanup checks still run.

Interactive multiplayer wounds, treatment, respawn, reconnect and scaling still
need acceptance testing. Live FPS cost has not been measured.
