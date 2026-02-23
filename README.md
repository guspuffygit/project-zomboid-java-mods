# Storm Project Zomboid Mods

### Setup local.properties

1. Create a new file in the repo named local.properties
2. Specify these two required directories

* gameDir - Project Zomboid Installation directory
* zomboidDir - Project Zomboid configuration directory

```
gameDir=E:\\SteamLibrary\\steamapps\\common\\ProjectZomboid
zomboidDir=C:\\Users\\user\\Zomboid
```

Deploy the mods locally:

Linux:
```
./gradlew deployMod
```

Windows:
```
.\gradlew.bat deployMod
```
