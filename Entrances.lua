local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.3.6, Daniel 10.10.: "the confirmation by our players when they enter the new zone, shared through
-- QuestdonNet") Dungeon entrances learned in the game.
--
-- Outside an instance Questdon notes the player's position every SAMPLE seconds, on the zone map (a
-- cave or Blackrock Mountain is a sub-map: its point goes up to the zone through the world position).
-- When a dungeon or raid loads and that spot is at most FRESH seconds old, the spot is the way in:
-- QuestdonDB.learnedEntrances[inst] = { map, x, y, time, times }. Not learned: dungeon finder
-- teleports (IsInLFGDungeon), a taxi, a spot on another zone map than every listed entrance of that
-- dungeon (a summon or a portal), or the option learnQuests off.
--
-- Use (Dungeons.lua, ns.DungeonEntrances): a learned spot within NEAR_LIST map units of a listed entrance
-- confirms it ("You entered here", "Entrance confirmed by %d players"); farther away it is another way in
-- (source "learned", or "shared" when others confirmed it).
--
-- Sharing: /qd export and Exchange.lua send "E <inst> <map> <x> <y>" like every other learned fact
-- (guild, group, QuestdonNet). Others count reporters; two through guild or group or three in all
-- make it confirmed (ns.SharedEntrance).
---------------------------------------------------------------------------
local SAMPLE = 2
local FRESH = 20
local NEAR_LIST = 3 -- map units (percent)
local ZONE = 3       -- Enum.UIMapType.Zone

local stats = { samples = 0, learned = 0, confirmed = 0, skipped = {}, last = nil }
function ns.EntranceLearnStats() return stats end
local function Skip(why) stats.skipped[why] = (stats.skipped[why] or 0) + 1 stats.last = why end

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end
local function Clock() return ns.Num(ns.Value(time)) or Now() end

local function MapType(m)
  local info = C_Map and ns.Value(C_Map.GetMapInfo, m)
  return type(info) == "table" and ns.Num(info.mapType), type(info) == "table" and ns.Num(info.parentMapID)
end

-- A point of a sub-map (cave, Blackrock Mountain) on its zone map, through the world position.
function ns.ZonePoint(m, x, y)
  for _ = 1, 4 do
    local kind, parent = MapType(m)
    if not kind or kind == ZONE or kind < ZONE then return m, x, y, kind end
    if not (parent and parent > 0 and C_Map and type(C_Map.GetWorldPosFromMapPos) == "function"
      and type(C_Map.GetMapPosFromWorldPos) == "function" and CreateVector2D) then return nil end
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
    if not (ok and world) then return nil end
    local ok2, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, parent)
    if not (ok2 and type(pos) == "table" and pos.GetXY) then return nil end
    local ok3, px, py = pcall(pos.GetXY, pos)
    if not (ok3 and ns.Num(px) and ns.Num(py)) then return nil end
    m, x, y = parent, px, py
  end
end

local outside -- { m, x, y, t } the last spot outside an instance (zone map)
local inside = false

local function InInstance()
  if type(IsInInstance) ~= "function" then return false end
  local ok, isIn, kind = pcall(IsInInstance)
  if not ok then return false end
  if not (ns.Usable(isIn) and ns.Usable(kind)) then return false end -- secret values: unknown
  return isIn == true or isIn == 1, type(kind) == "string" and kind or nil
end

local function Sample()
  if not (ns.db and ns.db.learnQuests) then return end
  if InInstance() then return end
  if ns.True(ns.Value(UnitOnTaxi, "player")) then outside = nil return end
  local m, x, y = ns.PlayerPosition()
  if not m then return end
  local zm, zx, zy, kind = ns.ZonePoint(m, x, y)
  if not zm or kind ~= ZONE then return end
  stats.samples = stats.samples + 1
  outside = { zm, zx, zy, Now() }
end
ns.SampleOutside = Sample -- (tests)
function ns.LastOutside() return outside end

local function Learned()
  if type(ns.db.learnedEntrances) ~= "table" then ns.db.learnedEntrances = {} end
  return ns.db.learnedEntrances
end

-- Called when an instance has loaded (and from the tests).
function ns.LearnEntrance(inst)
  if not (ns.db and ns.db.learnQuests) then return Skip("off") end
  if not inst then return Skip("no dungeon") end
  if not outside or Now() - outside[4] > FRESH then return Skip("no fresh spot") end
  if ns.True(ns.Value(IsInLFGDungeon)) then return Skip("dungeon finder") end
  local m, x, y = outside[1], outside[2], outside[3]
  -- a summon or a portal: the listed entrances are all on other zone maps
  local list = ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[inst]
  if type(list) == "table" and #list > 0 then
    local sameMap = false
    for _, p in ipairs(list) do if p[1] == m then sameMap = true end end
    if not sameMap then return Skip("other zone") end
  end
  local db = Learned()
  local e = db[inst]
  if type(e) == "table" and e[1] == m and math.abs(e[2] - x) * 100 <= NEAR_LIST and math.abs(e[3] - y) * 100 <= NEAR_LIST then
    e[5] = (ns.Num(e[5]) or 1) + 1
    e[4] = Clock()
  else
    db[inst] = { m, x, y, Clock(), 1 }
  end
  stats.learned = stats.learned + 1
  outside = nil
  -- a way in nobody listed: say so once
  local known = false
  for _, p in ipairs(type(list) == "table" and list or {}) do
    if p[1] == m and math.abs(p[2] / 100 - x) * 100 <= NEAR_LIST and math.abs(p[3] / 100 - y) * 100 <= NEAR_LIST then known = true end
  end
  if known then stats.confirmed = stats.confirmed + 1
  elseif ns.Print then ns.Print(L["Entrance of %s learned."]:format(ns.DungeonName(inst))) end
  if ns.ResetDungeonEntrances then ns.ResetDungeonEntrances() end
  if ns.RefreshPins then ns.RefreshPins() end
  return true
end

-- Own learned entrance: map, x, y (0-1), times, or nil.
function ns.LearnedEntrance(inst)
  local e = ns.db and type(ns.db.learnedEntrances) == "table" and ns.db.learnedEntrances[inst]
  if type(e) == "table" and ns.Num(e[1]) and ns.Num(e[2]) and ns.Num(e[3]) then return e[1], e[2], e[3], ns.Num(e[5]) or 1 end
end

-- /qd export and sharing: "E <inst> <map> <x> <y>"
function ns.EntranceRecords()
  local out = {}
  local db = ns.db and type(ns.db.learnedEntrances) == "table" and ns.db.learnedEntrances or {}
  local ids = {}
  for inst in pairs(db) do if type(inst) == "number" then ids[#ids + 1] = inst end end
  table.sort(ids)
  for _, inst in ipairs(ids) do
    local m, x, y = ns.LearnedEntrance(inst)
    if m and inst >= 0 and inst < 1e6 and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      out[#out + 1] = ("E %d %d %.1f %.1f"):format(inst, m, x * 100, y * 100)
    end
  end
  return out
end

local function OnWorld()
  local isIn, kind = InInstance()
  if isIn and (kind == "party" or kind == "raid") then
    if not inside then
      inside = true
      -- the map is ready a moment later
      ns.After(1, function() ns.LearnEntrance(ns.CurrentDungeon and ns.CurrentDungeon()) end)
    end
  else
    inside = false
  end
end
ns.EntranceOnWorld = OnWorld -- (tests)

ns.OnInit(function()
  ns.On("PLAYER_ENTERING_WORLD", OnWorld)
  ns.On("ZONE_CHANGED_NEW_AREA", OnWorld)
  ns.NewTicker(SAMPLE, Sample)
end)
