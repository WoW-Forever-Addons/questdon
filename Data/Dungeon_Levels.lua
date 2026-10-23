-- (1.3.5, Daniel 10.10.) Level range of every dungeon in WoW Forever: [ATT instanceID] = { min, max }.
-- Written by hand, not generated. The game's own values (Group Finder, Dungeons.lua) win over this table
-- where the client gives them; /qd dungeonlevels shows both side by side.
--
-- Source (taken for every value): warcrafttavern.com/forever/guides/dungeons, fetched 10.10.2026. It matches
-- a popular Forever dungeon addon for every value that could be compared.
-- Scarlet Monastery is one instance in the data; its wings: Graveyard 30-38, Library 33-41, Armory 36-44,
-- Cathedral 38-46 (here the whole span 30-46). Raids: 60.
--
-- (10.10., Daniel's /qd dungeonlevels) The game's Group Finder (client 1.60.1) gives 22 of these ranges; 16 match
-- the table, 6 differ and are taken from the game here (marked "game"), so the table and the game agree before the
-- Group Finder data is loaded. The game gives nothing for Ragefire Chasm and the raids.
--
-- Conflicts (not taken):
--   * Ragefire Chasm: 13-18 in that dungeon addon, 13-20 here.
--   * The September announcement (Icy Veins 15.09.): Hall of Thanes 13-18, Ruins of Lordaeron 15-20,
--     Excavation Site: Wetlands 24-29, City of Dalaran 28-33.
local _, ns = ...
ns.DUNGEON_LEVELS = {
  [226] = { 13, 20 },  -- Ragefire Chasm
  [3065] = { 13, 20 }, -- Hall of Thanes
  [2999] = { 15, 22 }, -- Ruins of Lordaeron
  [240] = { 15, 24 },  -- Wailing Caverns
  [63] = { 17, 26 },   -- The Deadmines
  [64] = { 20, 30 },   -- Shadowfang Keep
  [227] = { 24, 32 },  -- Blackfathom Deeps
  [238] = { 24, 32 },  -- The Stockade
  [2998] = { 26, 33 }, -- Excavation Site: Wetlands
  [2959] = { 28, 35 }, -- City of Dalaran (game; table 28-33)
  [231] = { 29, 38 },  -- Gnomeregan
  [234] = { 29, 38 },  -- Razorfen Kraul
  [316] = { 30, 46 },  -- Scarlet Monastery (wings 30-38, 33-41, 36-44, 38-46)
  [233] = { 37, 46 },  -- Razorfen Downs
  [239] = { 41, 51 },  -- Uldaman
  [241] = { 44, 54 },  -- Zul'Farrak (game; table 40-47)
  [232] = { 46, 55 },  -- Maraudon (game; table 45-51)
  [237] = { 50, 60 },  -- The Temple of Atal'Hakkar (game; table 50-55)
  [228] = { 52, 60 },  -- Blackrock Depths
  [229] = { 55, 60 },  -- Blackrock Spire (game; table 57-60)
  [230] = { 54, 60 },  -- Dire Maul (game; table 58-60)
  [236] = { 58, 60 },  -- Stratholme
  [742] = { 60, 60 },  -- Blackwing Lair
  [743] = { 60, 60 },  -- Ruins of Ahn'Qiraj
  [744] = { 60, 60 },  -- Temple of Ahn'Qiraj
  [754] = { 60, 60 },  -- Naxxramas
  [760] = { 60, 60 },  -- Onyxia's Lair
}
