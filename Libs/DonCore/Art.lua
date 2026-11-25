local M = LibStub("DonCore-1.0"):NewModule("Art", 4)
if not M then return end

---------------------------------------------------------------------------
-- DonCore Art (23.11.2026, Guildon Groups; Daniel: "für die Dungeon-Auswahl ... die ganzen Blizzard-Bilder", "ein
-- Charakterbild"): the game client's own pictures, referenced at runtime, no file shipped.
--   M.DungeonIcon(inst, names, gameMap, journalID) -> texture, source   the picture of a dungeon or raid (instanceID as in
--        ATT and Dropdon); names = its names to match the Dungeon Finder by (the client's and the English one), gameMap = the
--        instance's map ID when known, journalID = its Encounter Journal ID when the caller knows it (Questdon's entrance
--        scan; minor 2, 23.11.2026, when Questdon moved onto this). Order as in Questdon's Dungeons.lua (1.3.5): Encounter Journal (needs gameMap),
--        Dungeon Finder (GetLFGDungeonInfo, read once, by map or name), the known LFG icon paths of the classic dungeons,
--        then a fitting icon of the client's icon set (new Forever dungeons, raids). nil when none of them is there.
--   M.DungeonIconTag(inst, size, names, gameMap) -> "|T...|t " or ""
--   M.RaceIcon(race, sex) -> atlas or texture, coords   race = raceID (number) or the race's file name ("Dwarf"),
--        sex = 2 male, 3 female (UnitSex) or "m"/"f". The game's round race picture (atlas raceicon-<race>-<sex>), else
--        the old race sheet of the character creation (Interface\Glues\CharacterCreate\UI-CharacterCreate-Races), else nil.
--   M.RaceIconTag(race, sex, size) -> "|A...|a " / "|T...|t " or ""
--   M.RoleIconTag(role, size) -> the game's role symbol for "t", "h", "d" ("|A...|a " or "|T...|t "), "" without one
--   M.LookCode() -> "<raceID><m|f>" of the player ("3m"), "" when unknown; M.ParseLook(code) -> raceID, sex (2/3)
--   (minor 3) M.ZoneArt, M.DrawZoneMap, M.ZoneThumb: the world map of a zone, see "Zone maps" below
-- Everything is checked: a path the client does not have (GetFileIDFromPath) or an atlas it does not know
-- (C_Texture.GetAtlasInfo) counts as none. Questdon and Guildon Groups use it (Questdon's ns.DungeonIcon wraps it).
---------------------------------------------------------------------------
local function Str(v) return type(v) == "string" and v ~= "" and v or nil end
local function Num(v) v = tonumber(v) return v and v == v and v or nil end

local function PathExists(path)
  if type(path) == "number" then return path > 0 end
  if type(path) ~= "string" or path == "" then return false end
  if type(GetFileIDFromPath) == "function" then
    local ok, id = pcall(GetFileIDFromPath, path)
    if ok then return Num(id) ~= nil and id > 0 end
  end
  return true -- the client cannot tell: the texture shows whether it takes it
end

local function AtlasExists(name)
  local T = C_Texture
  if type(T) ~= "table" or type(T.GetAtlasInfo) ~= "function" then return false end
  local ok, info = pcall(T.GetAtlasInfo, name)
  return ok and type(info) == "table"
end
M.AtlasExists = AtlasExists

---------------------------------------------------------------------------
-- Dungeons
---------------------------------------------------------------------------
local LFG_ICON = "Interface\\LFGFrame\\LFGIcon-"
local KNOWN_ICON = { [63] = "Deadmines", [226] = "RagefireChasm", [240] = "WailingCaverns", [64] = "ShadowFangKeep",
  [227] = "BlackfathomDeeps", [238] = "StormwindStockades", [231] = "Gnomeregan", [234] = "RazorfenKraul",
  [316] = "ScarletMonastery", [233] = "RazorfenDowns", [239] = "Uldaman", [241] = "ZulFarak", [232] = "Maraudon",
  [237] = "SunkenTemple", [228] = "BlackrockDepths", [229] = "BlackrockSpire", [230] = "DireMaul", [236] = "Stratholme",
  [246] = "Scholomance", [741] = "MoltenCore", [742] = "BlackwingLair", [760] = "OnyxiaEncounter",
  [76] = "ZulGurub", [743] = "AQRuins", [744] = "AQTemple", [754] = "Naxxramas" }
local ICONS = "Interface\\Icons\\"
local ICON_CANDIDATES = {
  [3065] = { "INV_Misc_Head_Dwarf_01", "Spell_Nature_StoneSkinTotem", "INV_Hammer_04" },          -- Hall of Thanes
  [2999] = { "Spell_Shadow_RaiseDead", "INV_Misc_Bone_HumanSkull_01", "Spell_Shadow_AnimateDead" }, -- Ruins of Lordaeron
  [2959] = { "Spell_Arcane_Blink", "Spell_Holy_MagicalSentry", "Spell_Nature_WispSplode" },        -- City of Dalaran
  [2998] = { "Trade_Mining", "INV_Pick_02", "INV_Misc_Shovel_01" },                                -- Excavation Site
  -- (minor 4, 23.11.2026, Daniel: Krol'dok Stronghold in Riverglades ohne Bild) the other new Forever dungeons: the client's
  -- Dungeon Finder and Encounter Journal have no picture for them (LFGDungeons IconTextureFileID 0, build 1.60.1.71037)
  [3039] = { "Ability_Hunter_Pet_Crocolisk", "Spell_Shadow_Twilight", "INV_Misc_MonsterScales_05" },  -- Krol'dok Stronghold
  [2970] = { "Spell_Frost_SummonWaterElemental", "INV_Misc_Idol_03", "Ability_Hunter_Pet_WindSerpent" }, -- The Drowned City
  [2974] = { "Spell_Nature_StrangleVines", "INV_Misc_Root_02", "Ability_Hunter_Pet_Bear" },        -- Blackmaw Hold
  [2994] = { "INV_Misc_Key_03", "Spell_Frost_ChainsOfIce", "INV_Misc_Key_01" },                 -- Alcaz Prison
  [3001] = { "Ability_Hunter_Pet_Raptor", "INV_Misc_Orb_03", "Spell_Nature_EarthQuake" },        -- The Shaper's Terrace
  [3109] = { "INV_Misc_Bone_HumanSkull_01", "Spell_Shadow_GatherShadows", "Spell_Shadow_DeathScream" }, -- Manor Mistmantle
  [741] = { "Spell_Fire_LavaSpawn", "Spell_Fire_Incinerate" },                                     -- Molten Core
  [742] = { "INV_Misc_Head_Dragon_Black", "INV_Misc_Head_Dragon_01" },                             -- Blackwing Lair
  [760] = { "INV_Misc_Head_Dragon_01", "INV_Misc_Head_Dragon_Black" },                             -- Onyxia's Lair
  [76] = { "Ability_Mount_JungleTiger", "INV_Misc_Coin_08" },                                      -- Zul'Gurub
  [743] = { "INV_Misc_AhnQirajTrinket_01", "INV_Qiraj_JewelBlessed", "Spell_Nature_InsectSwarm" },  -- Ruins of Ahn'Qiraj
  [744] = { "INV_Misc_AhnQirajTrinket_03", "INV_Qiraj_JewelEncased", "Spell_Nature_InsectSwarm" },  -- Temple of Ahn'Qiraj
  [754] = { "INV_Trinket_Naxxramas03", "Spell_Shadow_RaiseDead", "Spell_Shadow_AnimateDead" },      -- Naxxramas
}
M.KNOWN_ICON, M.ICON_CANDIDATES = KNOWN_ICON, ICON_CANDIDATES -- (tests)
local MAX_LFG_ID = 3000
M.icons = M.icons or {}
local lfgIcons -- { byMap = {}, byName = {} } from the Dungeon Finder, read once a session (on the first ask)

local function LfgPath(tex)
  if type(tex) == "number" then return tex > 0 and tex or nil end
  tex = Str(tex)
  if not tex then return nil end
  if tex:find("\\", 1, true) or tex:find("/", 1, true) then return tex end
  return LFG_ICON .. tex
end

local function ScanLfg()
  if lfgIcons then return lfgIcons end
  lfgIcons = { byMap = {}, byName = {} }
  if type(GetLFGDungeonInfo) ~= "function" then return lfgIcons end
  local miss = 0
  for id = 1, MAX_LFG_ID do
    local r = { pcall(GetLFGDungeonInfo, id) }
    -- (no "Datenfresser") a long run of empty IDs ends the scan: the finder's dungeons sit at the low IDs
    if not (r[1] and Str(r[2])) then miss = miss + 1 if miss >= 400 then break end else miss = 0 end
    if r[1] and Str(r[2]) then
      local tex = LfgPath(r[12])
      local m = Num(r[23])
      if tex then
        if m and not lfgIcons.byMap[m] then lfgIcons.byMap[m] = tex end
        local low = r[2]:lower()
        if not lfgIcons.byName[low] then lfgIcons.byName[low] = tex end
      end
    end
  end
  return lfgIcons
end

local function JournalIcon(gameMap, jid)
  if type(EJ_GetInstanceInfo) ~= "function" then return nil end
  jid = Num(jid)
  local api = C_EncounterJournal
  if not jid and gameMap and type(api) == "table" and type(api.GetInstanceForGameMap) == "function" then
    local ok, id = pcall(api.GetInstanceForGameMap, gameMap)
    jid = ok and Num(id) or nil
  end
  if not jid then return nil end
  local ok2, _, _, _, button = pcall(EJ_GetInstanceInfo, jid)
  if not ok2 then return nil end
  if type(button) == "number" and button > 0 then return button end
  return Str(button)
end

function M.DungeonIcon(inst, names, gameMap, journalID)
  inst = Num(inst)
  if not inst then return nil end
  local c = M.icons[inst]
  if c ~= nil then if c then return c[1], c[2] end return nil end
  local tex, source = JournalIcon(Num(gameMap), journalID), "journal"
  if not (tex and PathExists(tex)) then
    tex, source = nil, "lfg"
    local lfg = ScanLfg()
    local cand = gameMap and lfg.byMap[gameMap]
    if not cand then
      for _, n in ipairs(type(names) == "table" and names or { names }) do
        local low = Str(n) and n:lower()
        if low then
          cand = lfg.byName[low] or lfg.byName[(low:gsub("^the%s+", ""))]
          if cand then break end
        end
      end
    end
    if cand and PathExists(cand) then tex = cand end
  end
  -- a known LFG path counts when the client has it or cannot tell (the texture shows whether it takes it, Questdon 1.3.5);
  -- an icon of the icon set only when the client says it has it
  if not tex and KNOWN_ICON[inst] and PathExists(LFG_ICON .. KNOWN_ICON[inst]) then
    tex, source = LFG_ICON .. KNOWN_ICON[inst], "known"
  end
  if not tex and ICON_CANDIDATES[inst] then
    for _, name in ipairs(ICON_CANDIDATES[inst]) do
      if type(GetFileIDFromPath) == "function" and PathExists(ICONS .. name) then tex, source = ICONS .. name, "icon" break end
    end
  end
  M.icons[inst] = tex and { tex, source } or false
  if tex then return tex, source end
  return nil
end

function M.DungeonIconTag(inst, size, names, gameMap, journalID)
  local tex, source = M.DungeonIcon(inst, names, gameMap, journalID)
  if not tex then return "" end
  size = size or 16
  if source == "icon" then return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(tostring(tex), size, size) end
  return ("|T%s:%d:%d|t "):format(tostring(tex), size, size)
end

function M.ResetIcons() M.icons, lfgIcons = {}, nil end -- (tests)

---------------------------------------------------------------------------
-- Race pictures
---------------------------------------------------------------------------
local RACE_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"
-- the old sheet (4 x 2 per sex): column, row of male; female one row lower by 2 rows (as the classic character creation)
local SHEET = { Human = { 0, 0 }, Dwarf = { 1, 0 }, Gnome = { 2, 0 }, NightElf = { 3, 0 },
  Tauren = { 0, 1 }, Scourge = { 1, 1 }, Troll = { 2, 1 }, Orc = { 3, 1 } }
-- the game's own corrections of race names for its atlases (SharedUtils GetRaceAtlas)
local FIXED = { HighmountainTauren = "highmountain", LightforgedDraenei = "lightforged", Scourge = "undead",
  ZandalariTroll = "zandalari" }

local function RaceFile(race)
  if type(race) == "string" then return Str(race) end
  local id = Num(race)
  local CI = C_CreatureInfo
  if not id or type(CI) ~= "table" or type(CI.GetRaceInfo) ~= "function" then return nil end
  local ok, info = pcall(CI.GetRaceInfo, id)
  return ok and type(info) == "table" and Str(info.clientFileString) or nil
end

local function Sex(sex)
  if sex == "f" or sex == 3 then return 3 end
  if sex == "m" or sex == 2 then return 2 end
  return nil
end

M.races = M.races or {}
function M.RaceIcon(race, sex)
  local file, s = RaceFile(race), Sex(sex)
  if not (file and s) then return nil end
  local key = file .. s
  local c = M.races[key]
  if c ~= nil then if c then return c[1], c[2] end return nil end
  local atlas = ("raceicon-%s-%s"):format((FIXED[file] or file):lower(), s == 3 and "female" or "male")
  local out
  if AtlasExists(atlas) then
    out = { atlas, nil }
  elseif SHEET[file] and type(GetFileIDFromPath) == "function" and PathExists(RACE_SHEET) then
    local col, row = SHEET[file][1], SHEET[file][2] + (s == 3 and 2 or 0)
    out = { RACE_SHEET, { col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25 } }
  end
  M.races[key] = out or false
  if out then return out[1], out[2] end
  return nil
end

function M.RaceIconTag(race, sex, size)
  local tex, coords = M.RaceIcon(race, sex)
  if not tex then return "" end
  size = size or 14
  if not coords then return ("|A:%s:%d:%d|a "):format(tex, size, size) end
  return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t "):format(tex, size, size, coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

-- the player's look as it travels: raceID and m/f, e.g. "3m"
function M.LookCode()
  local ok, _, _, id = pcall(UnitRace, "player")
  local ok2, sex = pcall(UnitSex, "player")
  id, sex = ok and Num(id), ok2 and Sex(Num(sex))
  if not (id and id > 0 and id < 1000 and sex) then return "" end
  return ("%d%s"):format(id, sex == 3 and "f" or "m")
end
function M.ParseLook(code)
  local id, s = tostring(code or ""):match("^(%d+)([mf])$")
  if not id then return nil end
  return tonumber(id), s == "f" and 3 or 2
end

---------------------------------------------------------------------------
-- Role symbols
---------------------------------------------------------------------------
local ROLE_ATLAS = { t = "roleicon-tiny-tank", h = "roleicon-tiny-healer", d = "roleicon-tiny-dps" }
local ROLE_SHEET = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local ROLE_COORDS = { t = { 0, 67, 67, 134 }, h = { 67, 134, 0, 67 }, d = { 67, 134, 67, 134 } } -- GetTexCoordsForRole, 256 px
M.roles = M.roles or {}
function M.RoleIconTag(role, size)
  if not ROLE_ATLAS[role or ""] then return "" end
  size = size or 14
  local how = M.roles[role]
  if how == nil then
    how = AtlasExists(ROLE_ATLAS[role]) and "atlas" or (type(GetFileIDFromPath) == "function" and PathExists(ROLE_SHEET) and "sheet") or false
    M.roles[role] = how
  end
  if how == "atlas" then return ("|A:%s:%d:%d|a "):format(ROLE_ATLAS[role], size, size) end
  if how == "sheet" then
    local c = ROLE_COORDS[role]
    return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t "):format(ROLE_SHEET, size, size, c[1], c[2], c[3], c[4])
  end
  return ""
end

function M.Reset() M.icons, M.races, M.roles, lfgIcons = {}, {}, {}, nil end -- (tests)

---------------------------------------------------------------------------
-- Zone maps (minor 3, 23.11.2026, Guildon Groups; Daniel: "oben könnte ne zonenvorschau ... das gleiche dann auch in der
-- liste"): the world map of a zone, drawn from the client's own map tiles (as Questdon's quest book and Luredon's book do).
--   M.ZoneArt(mapID) -> textures, tileW, tileH, layerW, layerH   the client's map art (C_Map.GetMapArtLayers and
--        GetMapArtLayerTextures), else the classic files Interface\WorldMap\<Zone>\<Zone>1..12 (4 by 3, 1002 by 668 count)
--   M.DrawZoneMap(frame, mapID, width, height) -> true when drawn   the map covers the frame (middle part shown) with the
--        parts the player explored on top; the textures stay on the frame (frame.donZoneTiles) and are reused
--   M.ZoneThumb(mapID) -> texture   the tile in the middle of the map: a square piece of the zone for a list or a |T tag
---------------------------------------------------------------------------
local MAPFILE = {
  [1438] = "Teldrassil", [1411] = "Durotar", [1412] = "Mulgore", [1439] = "Darkshore", [1413] = "Barrens",
  [1442] = "StonetalonMountains", [1440] = "Ashenvale", [1441] = "ThousandNeedles", [1443] = "Desolace",
  [1445] = "Dustwallow", [1444] = "Feralas", [1446] = "Tanaris", [1447] = "Aszhara", [1448] = "Felwood",
  [1449] = "UngoroCrater", [1452] = "Winterspring", [1450] = "Moonglade", [1451] = "Silithus",
  [1457] = "Darnassis", [1454] = "Ogrimmar", [1456] = "ThunderBluff",
  [1429] = "Elwynn", [1426] = "DunMorogh", [1420] = "Tirisfal", [1436] = "Westfall", [1432] = "LochModan",
  [1421] = "Silverpine", [1433] = "Redridge", [1431] = "Duskwood", [1437] = "Wetlands", [1424] = "Hilsbrad",
  [1416] = "Alterac", [1417] = "Arathi", [1434] = "Stranglethorn", [1418] = "Badlands", [1435] = "SwampOfSorrows",
  [1425] = "Hinterlands", [1427] = "SearingGorge", [1419] = "BlastedLands", [1428] = "BurningSteppes",
  [1422] = "WesternPlaguelands", [1423] = "EasternPlaguelands", [1430] = "DeadwindPass",
  [1453] = "Stormwind", [1455] = "Ironforge", [1458] = "Undercity",
}
M.MAPFILE = MAPFILE

local function ArtFromClient(m)
  local C = C_Map
  if type(C) ~= "table" or type(C.GetMapArtLayers) ~= "function" or type(C.GetMapArtLayerTextures) ~= "function" then return nil end
  local okL, layers = pcall(C.GetMapArtLayers, m)
  local okT, textures = pcall(C.GetMapArtLayerTextures, m, 1)
  local layer = okL and type(layers) == "table" and layers[1]
  if type(layer) ~= "table" or not okT or type(textures) ~= "table" or #textures == 0 then return nil end
  local tw, th, lw, lh = Num(layer.tileWidth), Num(layer.tileHeight), Num(layer.layerWidth), Num(layer.layerHeight)
  if not (tw and th and lw and lh) or tw <= 0 or th <= 0 or lw <= 0 or lh <= 0 then return nil end
  return textures, tw, th, lw, lh
end

local function ArtFromFiles(m)
  local name = MAPFILE[m]
  if not name then return nil end
  local textures = {}
  for i = 1, 12 do textures[i] = "Interface\\WorldMap\\" .. name .. "\\" .. name .. i end
  if not PathExists(textures[1]) then return nil end
  return textures, 256, 256, 1002, 668
end

function M.ZoneArt(m)
  m = Num(m)
  if not m then return nil end
  local a, b, c, d, e = ArtFromClient(m)
  if a then return a, b, c, d, e end
  return ArtFromFiles(m)
end

function M.ZoneThumb(m)
  local textures, tw, th, lw, lh = M.ZoneArt(m)
  if not textures then return nil end
  local cols = math.max(1, math.ceil(lw / tw))
  local col, row = math.floor((lw / 2) / tw), math.floor((lh / 2) / th)
  return textures[row * cols + col + 1] or textures[1]
end

function M.DrawZoneMap(frame, m, width, height)
  if type(frame) ~= "table" or type(frame.CreateTexture) ~= "function" then return false end
  frame.donZoneTiles = frame.donZoneTiles or {}
  local tiles = frame.donZoneTiles
  for _, t in ipairs(tiles) do t:Hide() end
  width, height = Num(width) or 0, Num(height) or 0
  local textures, tw, th, lw, lh = M.ZoneArt(m)
  if not textures or width <= 0 or height <= 0 then return false end
  local scale = math.max(width / lw, height / lh)
  local shiftX, shiftY = (lw * scale - width) / 2, (lh * scale - height) / 2
  local drawn = 0
  local function Piece(file, x, y, w, h, u, v, sub)
    local X, Y, Wd, Ht = x * scale - shiftX, y * scale - shiftY, w * scale, h * scale
    local xa, xb = math.max(0, X), math.min(width, X + Wd)
    local ya, yb = math.max(0, Y), math.min(height, Y + Ht)
    if xb <= xa or yb <= ya then return end
    drawn = drawn + 1
    local t = tiles[drawn]
    if not t then t = frame:CreateTexture(nil, "ARTWORK") tiles[drawn] = t end
    if t.SetDrawLayer then t:SetDrawLayer("ARTWORK", sub) end
    t:SetTexture(file)
    t:SetTexCoord(u * (xa - X) / Wd, u * (xb - X) / Wd, v * (ya - Y) / Ht, v * (yb - Y) / Ht)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", xa, -ya)
    t:SetSize(xb - xa, yb - ya)
    t:Show()
  end
  local cols = math.max(1, math.ceil(lw / tw))
  for i, file in ipairs(textures) do
    Piece(file, ((i - 1) % cols) * tw, math.floor((i - 1) / cols) * th, tw, th, 1, 1, 1)
  end
  -- the parts the player explored (the base tiles leave them out in the classic client)
  local E = C_MapExplorationInfo
  local ok, explored = false, nil
  if type(E) == "table" and type(E.GetExploredMapTextures) == "function" then ok, explored = pcall(E.GetExploredMapTextures, m) end
  if ok and type(explored) == "table" then
    for _, info in ipairs(explored) do
      pcall(function()
        if info.isShownByMouseOver then return end
        local w, h = Num(info.textureWidth), Num(info.textureHeight)
        local ox, oy = Num(info.offsetX) or 0, Num(info.offsetY) or 0
        local files = info.fileDataIDs
        if not (w and h and w > 0 and h > 0 and type(files) == "table") then return end
        local wide, tall = math.ceil(w / tw), math.ceil(h / th)
        for jj = 1, tall do
          local ph, fh = th, th
          if jj == tall then ph = h % th if ph == 0 then ph = th end fh = 16 while fh < ph do fh = fh * 2 end end
          for kk = 1, wide do
            local pw, fw = tw, tw
            if kk == wide then pw = w % tw if pw == 0 then pw = tw end fw = 16 while fw < pw do fw = fw * 2 end end
            local file = files[(jj - 1) * wide + kk]
            if file then Piece(file, ox + tw * (kk - 1), oy + th * (jj - 1), pw, ph, pw / fw, ph / fh, 2) end
          end
        end
      end)
    end
  end
  return drawn > 0
end
