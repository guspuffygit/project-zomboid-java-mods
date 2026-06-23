# Survivor Skill Obelisk

A Storm mod for Project Zomboid (Build 42) that adds a mysterious obelisk which interacts with survivor skills.

Maven group: `com.sentientsimulations.projectzomboid`.
Requires: [Storm](https://steamcommunity.com/sharedfiles/filedetails/?id=3670772371) mod loader.

## Architecture

```
src/main/java/com/sentientsimulations/projectzomboid/survivorskillobelisk/
└── SurvivorSkillObeliskMod.java   # Storm entry point + event handlers
```

## Building

```bash
./gradlew :survivor-skill-obelisk:spotlessApply :survivor-skill-obelisk:test
```
