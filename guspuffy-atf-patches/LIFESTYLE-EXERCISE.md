# Lifestyle Skills and Exercise

When Lifestyle wellness is enabled, Yoga appears under Skills with its existing
hidden-skill XP. Its label and progress boxes match the native skill colors.
Meditation keeps its existing skill row. No XP rows are added to Health.

Exercise adds Do Yoga and Meditate using Lifestyle's existing requirements,
sessions and cancellation rules. The controls fit inside the window so Close,
Cancel and OK remain clickable. Without Lifestyle, these additions stay hidden.

This change does not require UAC or Combat Health. It does not add native perks,
change XP progression or modify the normal exercise definitions.

## Validation

Use Project Zomboid Build 42.21 and the Lifestyle mod root containing
`common/media/lua`. Run both Lua interpreters from the repository root:

```text
./gradlew :guspuffy-atf-patches:luaTest :guspuffy-atf-patches:luaKahluaTest -PgameDir="/path/to/ProjectZomboid" -PlifestyleModDir="/path/to/LifestyleHobbies"
```

`LIFESTYLE_MOD_ROOT` can replace `-PlifestyleModDir`. Direct Lua runs also accept
`PZ_GAME_ROOT`. Set `-PluaExecutable` if Lua 5.1 is not on PATH.

The fixture loads native Skills and Exercise code plus Lifestyle actions. It
checks XP rendering, control placement, native close handlers, action dispatch,
cancellation, disabled wellness and repeated installation.
