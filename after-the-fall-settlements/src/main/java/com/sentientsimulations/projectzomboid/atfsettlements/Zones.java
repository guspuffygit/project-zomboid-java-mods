package com.sentientsimulations.projectzomboid.atfsettlements;

import java.util.HashMap;
import java.util.Map;

public class Zones {

    public Map<String, AfterTheFallZone> settlements() {
        Map<String, AfterTheFallZone> zones = new HashMap<>();

        zones.put(
                "Beacon's Car Repair",
                new AfterTheFallZone(
                        8701.0, 8749.0, 8505.0, 8558.0, "Beacon's Car Repair", "PVE", "N/A", true));

        zones.put(
                "The Enclave",
                new AfterTheFallZone(
                        13506.0, 13627.0, 2832.0, 3000.0, "The Enclave", "PVE", "Unknown", false));

        zones.put(
                "Deadman's Depot",
                new AfterTheFallZone(
                        9152.0,
                        9219.0,
                        7405.0,
                        7487.0,
                        "Deadman's Depot",
                        "PVE",
                        "m90x and Mayo",
                        false));

        zones.put(
                "The Ark",
                new AfterTheFallZone(
                        6085.0, 6242.0, 6658.0, 6703.0, "The Ark", "PVE", "Blink", false));

        zones.put(
                "The Dimmadome",
                new AfterTheFallZone(
                        8187.0,
                        8296.0,
                        9793.0,
                        9882.0,
                        "The Dimmadome",
                        "PVE",
                        "CedWitDaLed and JerseyBlue",
                        false));

        zones.put(
                "Secronom Bunker",
                new AfterTheFallZone(
                        9114.0,
                        9291.0,
                        8015.0,
                        8086.0,
                        "Secronom Bunker",
                        "PVE",
                        "PapaMeow",
                        false));

        zones.put(
                "Bedrock",
                new AfterTheFallZone(
                        13911.0,
                        13968.0,
                        10615.0,
                        10671.0,
                        "Bedrock",
                        "PVE",
                        "PvlMadDog, Crackhead Cole, and MrMack",
                        false));

        zones.put(
                "Bedrock 2",
                new AfterTheFallZone(
                        13963.0,
                        13992.0,
                        10625.0,
                        10657.0,
                        "Bedrock",
                        "PVE",
                        "PvlMadDog, Crackhead Cole, and MrMack",
                        false));

        zones.put(
                "Tiger's Woods",
                new AfterTheFallZone(
                        6988.0,
                        7070.0,
                        7382.0,
                        7481.0,
                        "Tiger's Woods",
                        "PVE",
                        "RebirthPyro & Red",
                        false));

        zones.put(
                "Outer Heaven",
                new AfterTheFallZone(
                        13001.0,
                        13144.0,
                        3291.0,
                        3366.0,
                        "Outer Heaven",
                        "PVE",
                        "m90x & Doxigo",
                        false));

        zones.put(
                "Freakville",
                new AfterTheFallZone(
                        11451.0,
                        11524.0,
                        8801.0,
                        8851.0,
                        "Freakville",
                        "PVE",
                        "Ebbie & Hades",
                        false));

        zones.put(
                "Obscura",
                new AfterTheFallZone(
                        9368.0,
                        9436.0,
                        9685.0,
                        9784.0,
                        "Obscura",
                        "PVE",
                        "Calamity Jane & Neil Fallon",
                        false));

        zones.put(
                "The Crossroads",
                new AfterTheFallZone(
                        11652.0,
                        11747.0,
                        8333.0,
                        8395.0,
                        "The Crossroads",
                        "PVE",
                        "Freemaysin",
                        false));

        zones.put(
                "The Block",
                new AfterTheFallZone(
                        10628.0,
                        10733.0,
                        10158.0,
                        10264.0,
                        "The Block",
                        "PVE",
                        "Rytherynn",
                        false));

        return zones;
    }

    public Map<String, AfterTheFallZone> individualSmallAreas() {
        Map<String, AfterTheFallZone> zones = new HashMap<>();

        zones.put(
                "The Bureau of Server Administration",
                new AfterTheFallZone(
                        6489.0,
                        6589.0,
                        11222.0,
                        11390.0,
                        "The Bureau of Server Administration",
                        "PVE",
                        "N/A",
                        true));

        zones.put(
                "The Rockwell Estate",
                new AfterTheFallZone(
                        9025.0,
                        9075.0,
                        10210.0,
                        10276.0,
                        "The Rockwell Estate",
                        "PVP",
                        "N/A",
                        true));

        zones.put(
                "Apocafists Fight Club",
                new AfterTheFallZone(
                        13130.0,
                        13150.0,
                        1561.0,
                        1591.0,
                        "Apocafists Fight Club",
                        "PVP",
                        "N/A",
                        true));

        zones.put(
                "Smokey's Saloon",
                new AfterTheFallZone(
                        9284.0, 9293.0, 10048.0, 10057.0, "Smokey's Saloon", "PVP", "N/A", true));

        zones.put(
                "West Point Town Hall",
                new AfterTheFallZone(
                        11927.0,
                        11956.0,
                        6861.0,
                        6894.0,
                        "West Point Town Hall",
                        "PVP",
                        "N/A",
                        true));

        zones.put(
                "The Bar at the End of the Universe",
                new AfterTheFallZone(
                        10170.0,
                        10185.0,
                        12664.0,
                        12667.0,
                        "The Bar at the End of the Universe",
                        "PVP",
                        "N/A",
                        true));

        zones.put(
                "The Bar at the End of the Universe 2",
                new AfterTheFallZone(
                        10161.0,
                        10185.0,
                        12668.0,
                        12686.0,
                        "The Bar at the End of the Universe",
                        "PVP",
                        "N/A",
                        true));

        zones.put(
                "Bright Flag Inn",
                new AfterTheFallZone(
                        8014.0, 8032.0, 11422.0, 11439.0, "Bright Flag Inn", "PVP", "N/A", true));

        zones.put(
                "Whiskey River Bar",
                new AfterTheFallZone(
                        5954.0, 5973.0, 5412.0, 5434.0, "Whiskey River Bar", "PVP", "N/A", true));

        zones.put(
                "Canvasback Studios",
                new AfterTheFallZone(
                        10035.0,
                        10162.0,
                        10230.0,
                        10306.0,
                        "Canvasback Studios",
                        "PVP",
                        "N/A",
                        true));

        zones.put(
                "Rusty Rifle",
                new AfterTheFallZone(
                        10751.0, 10775.0, 10545.0, 10587.0, "Rusty Rifle", "PVP", "N/A", true));

        zones.put(
                "Smokey's Saloon 2",
                new AfterTheFallZone(
                        10613.0, 10640.0, 9212.0, 9257.0, "Smokey's Saloon", "PVP", "N/A", true));

        return zones;
    }

    public Map<String, AfterTheFallZone> largeZones() {
        Map<String, AfterTheFallZone> zones = new HashMap<>();

        zones.put(
                "Louisville",
                new AfterTheFallZone(
                        11920.0, 14615.0, 965.0, 3440.0, "Louisville", "PVP", "N/A", false));

        zones.put(
                "West Point",
                new AfterTheFallZone(
                        10890.0, 12170.0, 6500.0, 7175.0, "West Point", "PVP", "N/A", false));

        zones.put(
                "Muldraugh",
                new AfterTheFallZone(
                        10580.0, 11030.0, 9200.0, 10680.0, "Muldraugh", "PVP", "N/A", false));

        zones.put(
                "March Ridge",
                new AfterTheFallZone(
                        9590.0, 10520.0, 12570.0, 13160.0, "March Ridge", "PVP", "N/A", false));

        zones.put(
                "Rosewood",
                new AfterTheFallZone(
                        7550.0, 8470.0, 11250.0, 12010.0, "Rosewood", "PVP", "N/A", false));

        zones.put(
                "Riverside",
                new AfterTheFallZone(
                        6031.0, 6829.0, 5150.0, 5610.0, "Riverside", "PVP", "N/A", false));

        zones.put(
                "Riverside 2",
                new AfterTheFallZone(
                        6031.0, 6829.0, 5150.0, 5610.0, "Riverside", "PVP", "N/A", false));

        return zones;
    }

    public Map<String, AfterTheFallZone> moddedMaps() {
        Map<String, AfterTheFallZone> zones = new HashMap<>();

        zones.put(
                "Addam's Family Mansion",
                new AfterTheFallZone(
                        11318.0,
                        11390.0,
                        9426.0,
                        9560.0,
                        "Addam's Family Mansion",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Bedford Falls",
                new AfterTheFallZone(
                        12877.0, 14095.0, 9884.0, 11416.0, "Bedford Falls", "PVP", "N/A", false));

        zones.put(
                "Big Bear Lake",
                new AfterTheFallZone(
                        4851.0, 6849.0, 7178.0, 8054.0, "Big Bear Lake", "PVP", "N/A", false));

        zones.put(
                "Betsy's Farm",
                new AfterTheFallZone(
                        9002.0, 9317.0, 9144.0, 9600.0, "Betsy's Farm", "PVP", "N/A", false));

        zones.put(
                "Crowlake",
                new AfterTheFallZone(
                        6297.0, 6592.0, 11143.0, 11651.0, "Crowlake", "PVP", "N/A", false));

        zones.put(
                "Foxwood",
                new AfterTheFallZone(
                        7856.0, 8079.0, 7511.0, 7795.0, "Foxwood", "PVP", "N/A", false));

        zones.put(
                "Greenport",
                new AfterTheFallZone(
                        8100.0, 8693.0, 7421.0, 7791.0, "Greenport", "PVP", "N/A", false));

        zones.put(
                "Homepie",
                new AfterTheFallZone(
                        8700.0, 9300.0, 7800.0, 8400.0, "Homepie", "PVP", "N/A", false));

        zones.put(
                "Ekron",
                new AfterTheFallZone(6902.0, 7798.0, 8075.0, 8682.0, "Ekron", "PVP", "N/A", false));

        zones.put(
                "Exotic's Rest Stop",
                new AfterTheFallZone(
                        6987.0,
                        7078.0,
                        11147.0,
                        11265.0,
                        "Exotic's Rest Stop",
                        "PVP",
                        "Exotic Steve'",
                        false));

        zones.put(
                "Grapeseed",
                new AfterTheFallZone(
                        7198.0, 7497.0, 11099.0, 11398.0, "Grapeseed", "PVP", "N/A", false));

        zones.put(
                "Greenleaf",
                new AfterTheFallZone(
                        6300.0, 6898.0, 10115.0, 10797.0, "Greenleaf", "PVP", "N/A", false));

        zones.put(
                "Oakridge Estate",
                new AfterTheFallZone(
                        12995.0, 13136.0, 6992.0, 7149.0, "Oakridge Estate", "PVP", "N/A", false));

        zones.put(
                "Overlook Hotel",
                new AfterTheFallZone(
                        4501.0, 4783.0, 6333.0, 6593.0, "Overlook Hotel", "PVE", "N/A", false));

        zones.put(
                "Orchidwood",
                new AfterTheFallZone(
                        8101.0, 8705.0, 9598.0, 10198.0, "Orchidwood", "PVP", "N/A", false));

        zones.put(
                "Lake Ivy Township",
                new AfterTheFallZone(
                        8706.0, 9459.0, 9587.0, 10465.0, "Lake Ivy Township", "PVP", "N/A", false));

        zones.put(
                "Little Township",
                new AfterTheFallZone(
                        8110.0, 8602.0, 8420.0, 8677.0, "Little Township", "PVP", "N/A", false));

        zones.put(
                "Rabbit Hash",
                new AfterTheFallZone(
                        9015.0, 9533.0, 7207.0, 7509.0, "Rabbit Hash", "PVP", "N/A", false));

        zones.put(
                "Redstone Raceway",
                new AfterTheFallZone(
                        12028.0,
                        12220.0,
                        10846.0,
                        11400.0,
                        "Redstone Raceway",
                        "PVP",
                        "Stroker Ace",
                        false));

        zones.put(
                "Redstone Research Facility",
                new AfterTheFallZone(
                        5478.0,
                        5969.0,
                        12366.0,
                        12820.0,
                        "Redstone Research Facility",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Rosewood Cabins",
                new AfterTheFallZone(
                        7509.0, 7723.0, 11413.0, 11620.0, "Rosewood Cabins", "PVP", "N/A", false));

        zones.put(
                "Fort Rock Ridge",
                new AfterTheFallZone(
                        6702.0, 7168.0, 6001.0, 6501.0, "Fort Rock Ridge", "PVP", "N/A", false));

        zones.put(
                "Fort Redstone",
                new AfterTheFallZone(
                        5425.0, 5925.0, 11718.0, 12268.0, "Fort Redstone", "PVP", "N/A", false));

        zones.put(
                "Louisville International Airport",
                new AfterTheFallZone(
                        12844.0,
                        13465.0,
                        4204.0,
                        4800.0,
                        "Louisville International Airport",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Louisville Quarantine Zone",
                new AfterTheFallZone(
                        13419.0,
                        13753.0,
                        4002.0,
                        4186.0,
                        "Louisville Quarantine Zone",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Lost Coast Lighthouse",
                new AfterTheFallZone(
                        10915.0,
                        10950.0,
                        6568.0,
                        6602.0,
                        "Lost Coast Lighthouse",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Monmouth County",
                new AfterTheFallZone(
                        11697.0, 12894.0, 8102.0, 8688.0, "Monmouth County", "PVP", "N/A", false));

        zones.put(
                "Northwest Blockade",
                new AfterTheFallZone(
                        3057.0, 3298.0, 6050.0, 6233.0, "Northwest Blockade", "PVP", "N/A", false));

        zones.put(
                "Nettle Township",
                new AfterTheFallZone(
                        6601.0, 7273.0, 8999.0, 9592.0, "Nettle Township", "PVP", "N/A", false));

        zones.put(
                "Shelter 22-28",
                new AfterTheFallZone(
                        6600.0, 6655.0, 9000.0, 8432.0, "Shelter 22-28", "PVP", "N/A", false));

        zones.put(
                "Shelter 49-12",
                new AfterTheFallZone(
                        14890.0, 14922.0, 3814.0, 3844.0, "Shelter 49-12", "PVP", "N/A", false));

        zones.put(
                "Merriweather Ranch",
                new AfterTheFallZone(
                        12419.0,
                        12527.0,
                        7600.0,
                        7700.0,
                        "Merriweather Ranch",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "That One Prison",
                new AfterTheFallZone(
                        9640.0, 9804.0, 9363.0, 9492.0, "That One Prison", "PVP", "N/A", false));

        zones.put(
                "Tikitown",
                new AfterTheFallZone(
                        6900.0, 7612.0, 6900.0, 7749.0, "Tikitown", "PVP", "N/A", false));

        zones.put(
                "The Peninsula Retreat",
                new AfterTheFallZone(
                        6683.0,
                        6704.0,
                        11576.0,
                        11605.0,
                        "The Peninsula Retreat",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Uncle Red's Bunker",
                new AfterTheFallZone(
                        10958.0,
                        11051.0,
                        10846.0,
                        10919.0,
                        "Uncle Red's Bunker",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Wellsburg Lake",
                new AfterTheFallZone(
                        7500.0, 7772.0, 10125.0, 10442.0, "Wellsburg Lake", "PVP", "N/A", false));

        zones.put(
                "West Outskirts Shipping Company",
                new AfterTheFallZone(
                        9666.0,
                        9719.0,
                        9641.0,
                        9679.0,
                        "West Outskirts Shipping Company",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Vault-Tec Demo Unit",
                new AfterTheFallZone(
                        13321.0,
                        13370.0,
                        3733.0,
                        3844.0,
                        "Vault-Tec Demo Unit",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "ValuTech Amusement Park",
                new AfterTheFallZone(
                        13526.0,
                        13799.0,
                        4202.0,
                        4751.0,
                        "ValuTech Amusement Park",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "North of Killian Country",
                new AfterTheFallZone(
                        7202.0,
                        8688.0,
                        8700.0,
                        9580.0,
                        "North of Killian Country",
                        "PVP",
                        "N/A",
                        false));

        zones.put(
                "Killian Country",
                new AfterTheFallZone(
                        7503.0, 8100.0, 9601.0, 10196.0, "Killian Country", "PVP", "N/A", false));

        zones.put(
                "Shortrest City",
                new AfterTheFallZone(
                        12908.0, 14699.0, 6603.0, 7490.0, "Shortrest City", "PVP", "N/A", false));

        zones.put(
                "Knox County History Museum",
                new AfterTheFallZone(
                        10566.0,
                        10780.0,
                        8129.0,
                        8291.0,
                        "Knox County History Museum",
                        "PVP",
                        "N/A",
                        false));

        return zones;
    }
}
