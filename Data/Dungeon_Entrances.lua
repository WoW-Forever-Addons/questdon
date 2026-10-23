local _, ns = ...
---------------------------------------------------------------------------
-- (1.3.6, Daniel 10.10.2026: "the dungeon entrances must be described somewhere") Dungeon entrances
-- where you walk in, in WoW Forever's own map coordinates:
--   [instanceID (ns.ATT_DUNGEONS)] = { { uiMapID, x, y }, ... }   x, y in percent; the first is the main one.
-- Every entrance was checked by hand in the game (Daniel, 11.10.2026). More exact points come from
-- the players: Questdon learns where someone with Questdon walks into a dungeon (Entrances.lua) and
-- shares it (Exchange.lua).
-- Blackrock Depths, Blackrock Spire and Blackwing Lair share Blackrock Mountain's two ways in (Searing
-- Gorge, Burning Steppes); both Ahn'Qiraj raids the Scarab Gate. Where All The Things has a point deeper
-- inside (Deadmines, Gnomeregan, Maraudon) or on the continent map (Wailing Caverns), this list's point
-- outside wins.
---------------------------------------------------------------------------
ns.DUNGEON_ENTRANCES = {
  [63]   = { { 1436, 42.5, 71.7 } },                          -- The Deadmines: the mine in Moonbrook (Westfall)
  [64]   = { { 1421, 44.8, 67.8 } },                          -- Shadowfang Keep (Silverpine Forest)
  [226]  = { { 1454, 52.6, 49.0 } },                          -- Ragefire Chasm (Orgrimmar, Cleft of Shadow)
  [227]  = { { 1440, 14.5, 14.2 } },                          -- Blackfathom Deeps (Ashenvale)
  [228]  = { { 1427, 34.8, 85.3 }, { 1428, 29.4, 38.3 } },   -- Blackrock Depths: Blackrock Mountain
  [229]  = { { 1427, 34.8, 85.3 }, { 1428, 29.4, 38.3 } },   -- Blackrock Spire: Blackrock Mountain
  [230]  = { { 1444, 59.2, 45.1 } },                          -- Dire Maul (Feralas)
  [231]  = { { 1426, 24.3, 39.8 } },                          -- Gnomeregan (Dun Morogh)
  [232]  = { { 1443, 29.1, 62.5 } },                          -- Maraudon (Desolace)
  [233]  = { { 1413, 49.0, 93.9 } },                          -- Razorfen Downs (The Barrens)
  [234]  = { { 1413, 42.9, 90.2 } },                          -- Razorfen Kraul (The Barrens)
  [236]  = { { 1423, 26.52, 10.36 }, { 1423, 41.45, 17.74 } }, -- Stratholme: main gate, service gate
  [237]  = { { 1435, 69.9, 53.5 } },                          -- The Temple of Atal'Hakkar (Swamp of Sorrows)
  [238]  = { { 1453, 52.41, 70.01 } },                        -- The Stockade (Stormwind)
  [239]  = { { 1418, 44.6, 12.1 }, { 1418, 65.2, 43.5 } },   -- Uldaman: front, back (Badlands)
  [240]  = { { 1413, 46.0, 36.5 } },                          -- Wailing Caverns (The Barrens)
  [241]  = { { 1446, 38.7, 20.1 } },                          -- Zul'Farrak (Tanaris)
  [246]  = { { 1422, 69.1, 73.0 } },                          -- Scholomance (Western Plaguelands, Caer Darrow; 22.10.: ATT 0bb8f4b's point, not yet checked in the game)
  [316]  = { { 1420, 82.6, 33.8 } },                          -- Scarlet Monastery (Tirisfal Glades)
  [742]  = { { 1427, 34.8, 85.3 }, { 1428, 29.4, 38.3 } },   -- Blackwing Lair: Blackrock Mountain
  [743]  = { { 1451, 28.6, 92.3 } },                          -- Ruins of Ahn'Qiraj: Scarab Gate (Silithus)
  [744]  = { { 1451, 28.6, 92.3 } },                          -- Temple of Ahn'Qiraj: Scarab Gate (Silithus)
  [754]  = { { 1423, 34.25, 19.45 } },                        -- Naxxramas (Eastern Plaguelands, Plaguewood)
  [760]  = { { 1445, 52.6, 76.8 } },                          -- Onyxia's Lair (Dustwallow Marsh)
  [2959] = { { 1416, 8.46, 59.21 } },                         -- City of Dalaran (Alterac Mountains)
  [2998] = { { 1437, 47.79, 56.16 } },                        -- Excavation Site: Wetlands
  [2999] = { { 1420, 63.19, 67.45 }, { 1458, 72.48, 11.33 } }, -- Ruins of Lordaeron: Tirisfal, Undercity map
  [3065] = { { 1455, 27.63, 47.83 } },                        -- Hall of Thanes (below Ironforge)
}
