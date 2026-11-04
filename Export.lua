local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Community export: what Questdon learned while playing, as compact text the
-- player can paste into a GitHub issue (form "Quest data") so it can be merged
-- into the shipped data.
--
--   QDX2 <version> <locale> <date> <new|all>
--   S <questID> <mapID> <x> <y> <npcID or 0> <A|H|->   quest start at an NPC, faction
--   G <questID> <mapID> <x> <y> <objectID> <A|H|->      (1.0.1) start at an object
--   I <questID> <itemID or 0> <A|H|->                   (1.0.1) start from an item
--   T <questID> <mapID> <x> <y> <npcID or 0>           turn-in
--   O <questID> <objIndex> <mapID> <x> <y>             objective spot
--   F <questID> <previousQuestID> <2|1>                (1.0.1) offered right after
--                                                      turning in the previous
--                                                      quest at the same giver
--                                                      (2 sure, 1 maybe)
--   K <questID> <objIndex> <c|o|i> <id> <count>        (1.0.1) what gave credit:
--                                                      creature, object or item
--   D <itemID> <c|o> <id> <count> <mapID> <x> <y>      (1.0.1) a quest item dropped
--                                                      from that creature or object
--   A <questID> <level>                                (1.0.1) lowest player level
--                                                      the quest was offered at
--   X <questID>                                        the server does not know
--                                                      this quest (1.13, Exists.lua)
--   N <questID> <npcID or 0> <m|a>                     (1.1) the quest giver never
--                                                      offers it: m = reported by
--                                                      the player, a = not offered
--                                                      at 3 levels (NotHere.lua)
--   E <instance> <mapID> <x> <y>                       (1.3.6) a dungeon's way in: the last
--                                                      spot outside before it loaded
--                                                      (Entrances.lua)
--   V <npcID> <role> <mapID> <x> <y>                   (22.10.2026) what an NPC is, seen when its
--                                                      window opened (Services.lua): v vendor, vr
--                                                      repairs too, t:<CLASS> class trainer, p
--                                                      profession trainer, f flight master, i
--                                                      innkeeper, s spirit healer, b banker,
--                                                      a auctioneer, st stable master
--   H <h|m|s|f> <o|c|-> <id> <mapID> <x> <y> <itemID> <n>   (27.10.2026) a gathering find (Gather.lua):
--                                                      herb, mining, skinning, fishing; node or pool
--                                                      object, skinned creature, or - 0 (open water);
--                                                      n = loot windows with that item there
--   M <npcID> <name>                                   (1.3.5) an NPC's name as the
--                                                      game showed it, in the locale
--                                                      of the header (rest of the line)
--   # comments (count, truncation)
--
-- Coordinates 0-100 with one decimal. Only numbers: no character, realm,
-- guild or quest names. (1.3.5) The one exception are M lines: names of NPCs
-- as the game shows them, so the shipped translations can grow. They are only
-- in /qd export, never in what Questdon shares with guild and group. "new" leaves out what the bundled data has
-- already (starts at the same spot, objective spots near its points,
-- known prerequisites, credit sources and levels). (03.11.2026) Also the shipped
-- turn-ins, drop sources, dungeon entrances, service symbols and reward picks, and
-- every fact the data build has already (Known_Facts.lua, ns.KnownLine below).
--
-- (1.3.3) Daniel 06.10.: "new" also leaves out lines already sent. A line
-- counts as sent only after the player clicks "Mark as sent" in the export
-- window (QuestdonDB.exportSent: exact line -> true), so copying without
-- sending loses nothing. The comparison is the exact text: a new spot, a
-- higher count or another coordinate is another line and comes along. X lines
-- only come with "all" (they repeat in every export). "all" shows everything.
---------------------------------------------------------------------------
local MAX_LINES = 3000
local SAME_SPOT = 2   -- start: ATT within 2 map units = the same
local NEAR_ATT = 3    -- objective spot: within 3 map units of an ATT point = known
local ISSUE_URL = "github.com/WoW-Forever-Addons/questdon/issues"

local Q = ns.ATT_QUESTS or {}
local OBJ = ns.ATT_OBJECTIVES or {}
local NPC = ns.ATT_CREATURES or {}

local function Int(v)
  return type(v) == "number" and v >= 0 and v == math.floor(v) and v < 2 ^ 31
end

local function Coord(v)
  return type(v) == "number" and v >= 0 and v <= 1
end

local function Fmt(v) return ("%.1f"):format(v * 100) end

local function Place(p)
  if type(p) ~= "table" or not Int(p.map) or p.map == 0 or not (Coord(p.x) and Coord(p.y)) then return nil end
  return p.map, p.x, p.y, Int(p.npcID) and p.npcID or 0
end

local function Pos(m, x, y)
  return Int(m) and m > 0 and Coord(x) and Coord(y)
end

local function Has(list, v)
  if type(list) == "number" then return list == v end
  for _, x in ipairs(type(list) == "table" and list or {}) do
    if x == v then return true end
  end
  return false
end

-- (1.0.1) Data knows this credit source already (creature or item of the objective)?
local function CreditKnown(questID, index, kind, id)
  local o = OBJ[questID] and OBJ[questID][index]
  if not o then return false end
  if kind == "c" then return Has(o[1], id) end
  if kind == "i" then return Has(o[2], id) end
  return false
end

local function Near(x1, y1, x2, y2, limit)
  return math.abs(x1 - x2) <= limit and math.abs(y1 - y2) <= limit
end

-- Does ATT already have this start? (same map, about the same spot)
local function StartKnown(questID, map, x, y)
  local q = Q[questID]
  return q and q[1] == map and q[2] and q[3] and Near(q[2], q[3], x * 100, y * 100, SAME_SPOT) or false
end

-- Is this objective spot close to an ATT objective point or creature spawn?
local function SpotKnown(questID, index, map, x, y)
  local o = OBJ[questID] and OBJ[questID][index]
  if not o then return false end
  x, y = x * 100, y * 100
  local pts = o[3] or {}
  for i = 1, #pts, 3 do
    if pts[i] == map and Near(pts[i + 1], pts[i + 2], x, y, NEAR_ATT) then return true end
  end
  for _, cr in ipairs(o[1] or {}) do
    local spawns = NPC[cr]
    if spawns then
      for i = 2, #spawns, 3 do
        if spawns[i] == map and Near(spawns[i + 1], spawns[i + 2], x, y, NEAR_ATT) then return true end
      end
    end
  end
  return false
end

-- (03.11.2026) the shipped turn-in (DonData QUEST_ENDS): same map, about the same spot, the same NPC (or none said)
local function EndKnown(questID, map, x, y, npcID)
  local e = ns.QUEST_ENDS and ns.QUEST_ENDS[questID]
  return type(e) == "table" and e[1] == map and type(e[2]) == "number" and type(e[3]) == "number"
    and Near(e[2], e[3], x * 100, y * 100, SAME_SPOT) and (npcID == 0 or e[4] == nil or e[4] == npcID) or false
end

-- (03.11.2026) the shipped drop sources of a quest item (DonData ITEM_SOURCES: creatures that drop it)
local function DropKnown(itemID, kind, id)
  local s = kind == "c" and ns.ITEM_SOURCES and ns.ITEM_SOURCES[itemID]
  return type(s) == "table" and Has(s[1], id) or false
end

---------------------------------------------------------------------------
-- (03.11.2026, Daniel: "nur das senden, was wir noch nicht haben") A line the data has already stays home, in the
-- share as in /qd export "new": the shipped data (above for S G O K F A T D; here E, V, R) and ns.KNOWN_FACTS
-- (DonData/Data/Known_Facts.lua, tools/open/build_known.py): what the data build collected but does not ship (yet),
-- one key per fact (KnownKeys), hashed and sorted, 5 characters each. A hash can match a fact we do not have
-- (about 1 in 10000 lines with 100000 keys): that line is not sent, the next player's is.
---------------------------------------------------------------------------
local HASH_MOD = 1073741789 -- prime below 2^30: 5 digits of 64
local DIGIT = {}            -- byte -> 0..63: "#" to "d" without "\" and "]"
do
  local d = 0
  for b = 35, 100 do
    if b ~= 92 and b ~= 93 then DIGIT[b] = d d = d + 1 end
  end
end
local function KeyHash(s)
  local h = 0
  for i = 1, #s do h = (h * 131 + s:byte(i)) % HASH_MOD end
  return h
end
ns.KnownKeyHash = KeyHash -- (tests)

local function InHash(h)
  local s = ns.KNOWN_FACTS
  if type(s) ~= "string" or #s < 5 then return false end
  local lo, hi = 1, math.floor(#s / 5)
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local p = mid * 5 - 4
    local b1, b2, b3, b4, b5 = s:byte(p, p + 4)
    local v = ((((DIGIT[b1] or 0) * 64 + (DIGIT[b2] or 0)) * 64 + (DIGIT[b3] or 0)) * 64 + (DIGIT[b4] or 0)) * 64 + (DIGIT[b5] or 0)
    if v == h then return true elseif v < h then lo = mid + 1 else hi = mid - 1 end
  end
  return false
end
local function InKnown(key)
  return key ~= nil and type(ns.KNOWN_FACTS) == "string" and InHash(KeyHash(key))
end

-- A walked cell the data build has ("W <map> <cell>", Paths.lua WalkRecords): hashed without a new string per cell
local function HashDigits(h, n)
  if n >= 10 then h = HashDigits(h, math.floor(n / 10)) end
  return (h * 131 + 48 + n % 10) % HASH_MOD
end
local walkPrefix = {} -- map -> hash of "W <map> "
function ns.KnownWalkCell(m, c)
  if type(ns.KNOWN_FACTS) ~= "string" or type(m) ~= "number" or type(c) ~= "number" or c < 0 then return false end
  local h = walkPrefix[m]
  if not h then h = KeyHash(("W %d "):format(m)) walkPrefix[m] = h end
  return InHash(HashDigits(h, c))
end

-- Python's round() of a one-decimal number (the data build's 1 % cells of O and P): halves to the even side
local function PyRound(v)
  v = tonumber(v) or 0
  local f = math.floor(v)
  local d = v - f
  if d > 0.5 + 1e-9 then return f + 1 elseif d < 0.5 - 1e-9 then return f end
  return f % 2 == 0 and f or f + 1
end
local function Cell(v)
  local g = ns.GridCell or function(p, size) return math.floor(math.floor(p * 10 + 0.5) / (size * 10)) end
  return g(tonumber(v) or 0, 1)
end

-- The key of a line as store/build.py fact_key names the fact (and a second one: a "maybe" follow-up is known
-- as "maybe" or "sure"); nil: not keyed (W, a start or turn-in without an NPC).
local KEYS = {
  S = function(l) local q, m, n = l:match("^S (%d+) (%d+) %S+ %S+ (%d+) ") if q and n ~= "0" then return ("S %s %s %s"):format(q, m, n) end end,
  G = function(l) local q, m, o = l:match("^G (%d+) (%d+) %S+ %S+ (%d+) ") if q then return ("G %s %s %s"):format(q, m, o) end end,
  T = function(l) local q, m, n = l:match("^T (%d+) (%d+) %S+ %S+ (%d+)$") if q and n ~= "0" then return ("T %s %s %s"):format(q, m, n) end end,
  I = function(l) local q, i = l:match("^I (%d+) (%d+) ") if q then return ("I %s %s"):format(q, i) end end,
  O = function(l)
    local q, i, m, x, y = l:match("^O (%d+) (%d+) (%d+) (%S+) (%S+)$")
    if q then return ("O %s %s %s %d %d"):format(q, i, m, PyRound(x), PyRound(y)) end
  end,
  F = function(l)
    local q, p, v = l:match("^F (%d+) (%d+) ([12])$")
    if q then return ("F %s %s"):format(q, p), v == "1" and ("F %s %s 1"):format(q, p) or nil end
  end,
  K = function(l) local q, i, k, id = l:match("^K (%d+) (%d+) ([coi]) (%d+) ") if q then return ("K %s %s %s:%s"):format(q, i, k, id) end end,
  D = function(l) local it, k, id = l:match("^D (%d+) ([co]) (%d+) ") if it then return ("D %s %s:%s"):format(it, k, id) end end,
  A = function(l) local q, lv = l:match("^A (%d+) (%d+)$") if q then return ("A %s %s"):format(q, lv) end end,
  X = function(l) local q = l:match("^X (%d+)$") if q then return "X " .. q end end,
  N = function(l) local q, n = l:match("^N (%d+) (%d+) ") if q then return ("N %s %s"):format(q, n) end end,
  R = function(l) local q, c, t, i = l:match("^R (%d+) (%d+) (%d) (%d+)$") if q then return ("R %s %s %s %s"):format(q, c, t, i) end end,
  P = function(l)
    local n, m, x, y = l:match("^P (%d+) (%d+) (%S+) (%S+)$")
    if n then return ("P %s %s %d %d"):format(n, m, PyRound(x), PyRound(y)) end
  end,
  Y = function(l) local q, o = l:match("^Y (%d+) (%S+)$") if q then return ("Y %s %s"):format(q, o) end end,
  H = function(l)
    local k, s, id, m, x, y, item = l:match("^H ([hmsf]) ([oc%-]) (%d+) (%d+) (%S+) (%S+) (%d+) ")
    if k then return ("H %s %s%s %s %s %d %d"):format(k, s, id, item, m, Cell(x), Cell(y)) end
  end,
  E = function(l) local i, m = l:match("^E (%d+) (%d+) ") if i then return ("E %s %s"):format(i, m) end end,
  V = function(l) local n, r, m = l:match("^V (%d+) (%S+) (%d+) ") if n then return ("V %s %s %s"):format(n, r, m) end end,
}
function ns.KnownKeys(line)
  local f = type(line) == "string" and KEYS[line:sub(1, 1)]
  if f then return f(line) end
end

local EMPTY = {}
local SERVICE_ROLES = { i = true, a = true, f = true, b = true } -- the roles Services.lua ships
-- The shipped data has this line already (E, V, R; the other kinds are compared where the lines are made).
local function ShippedLine(line)
  local c = line:sub(1, 1)
  if c == "E" then
    local inst, m, x, y = line:match("^E (%d+) (%d+) (%S+) (%S+)$")
    local list = inst and ns.DUNGEON_ENTRANCES and ns.DUNGEON_ENTRANCES[tonumber(inst)]
    for _, p in ipairs(type(list) == "table" and list or EMPTY) do
      if p[1] == tonumber(m) and Near(p[2], p[3], tonumber(x), tonumber(y), NEAR_ATT) then return true end
    end
  elseif c == "V" then
    local role, m, x, y = line:match("^V %d+ (%S+) (%d+) (%S+) (%S+)$")
    local list = role and SERVICE_ROLES[role] and ns.SERVICES and ns.SERVICES[tonumber(m)]
    for _, p in ipairs(type(list) == "table" and list or EMPTY) do
      if p[1] == role and Near(p[2], p[3], tonumber(x), tonumber(y), SAME_SPOT) then return true end
    end
  elseif c == "R" then
    local q, cl, item = line:match("^R (%d+) (%d+) %d (%d+)$")
    local r = q and ns.LEARNED_REWARDS and ns.LEARNED_REWARDS[tonumber(q)]
    local byClass = type(r) == "table" and r[tonumber(cl)]
    return type(byClass) == "table" and byClass[tonumber(item)] ~= nil
  end
  return false
end

function ns.KnownLine(line)
  if ShippedLine(line) then return true end
  local a, b = ns.KnownKeys(line)
  return InKnown(a) or InKnown(b)
end

-- (23.10., /qd mem round 2) no new table for a missing list: the share send builds all lines every few minutes
local NOKEYS = {}
local KINDS = { "c", "o", "i" }
local function SortedKeys(t)
  if type(t) ~= "table" then return NOKEYS end
  local keys = {}
  for k in pairs(t) do
    if Int(k) and k > 0 then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

local function Locale()
  local l = ns.Value(GetLocale)
  return type(l) == "string" and l:match("^%a%a%a%a$") or "enUS"
end
ns.Locale = Locale

-- Today as YYYY-MM-DD (0000-00-00 if the client has no date()).
function ns.Today()
  local d = ns.Value(date, "%Y-%m-%d")
  return type(d) == "string" and d:match("^%d%d%d%d%-%d%d%-%d%d$") or "0000-00-00"
end

-- (1.0.1) The export records (lines without header), also what Questdon
-- shares with guild and group (Exchange.lua). all: without comparing with the data.
function ns.ExportRecords(all)
  local records = {}
  local learned = ns.db.learned or {}
  local learnedObj = ns.db.learnedObj or {}
  local quests = {}
  for id in pairs(learned) do if Int(id) and id > 0 then quests[id] = true end end
  for id in pairs(learnedObj) do if Int(id) and id > 0 then quests[id] = true end end

  local credits = type(ns.db.learnedCredit) == "table" and ns.db.learnedCredit or {}
  for id in pairs(credits) do if Int(id) and id > 0 then quests[id] = true end end

  for _, id in ipairs(SortedKeys(quests)) do
    local e = learned[id]
    if type(e) == "table" then
      local fac = e.faction == "Alliance" and "A" or e.faction == "Horde" and "H" or "-"
      local st = e.start
      if type(st) == "table" and st.item then
        -- (1.0.1) item start: the item, not the spot (wherever it was used)
        if Int(st.itemID) or all or not Q[id] then
          records[#records + 1] = ("I %d %d %s"):format(id, Int(st.itemID) and st.itemID or 0, fac)
        end
      elseif type(st) == "table" then
        local map, x, y, npcID = Place(st)
        if map and (all or not StartKnown(id, map, x, y)) then
          if npcID == 0 and Int(st.objID) and st.objID > 0 then
            records[#records + 1] = ("G %d %d %s %s %d %s"):format(id, map, Fmt(x), Fmt(y), st.objID, fac)
          else
            records[#records + 1] = ("S %d %d %s %s %d %s"):format(id, map, Fmt(x), Fmt(y), npcID, fac)
          end
        end
      end
      local map, x, y, npcID = Place(e.finish)
      if map and (all or not EndKnown(id, map, x, y, npcID)) then
        records[#records + 1] = ("T %d %d %s %s %d"):format(id, map, Fmt(x), Fmt(y), npcID)
      end
      -- (1.0.1) follow-ups
      if type(e.after) == "table" then
        for _, prev in ipairs(SortedKeys(e.after)) do
          local v = e.after[prev]
          if (v == 1 or v == 2) and (all or not (Q[id] and Has(Q[id][6], prev))) then
            records[#records + 1] = ("F %d %d %d"):format(id, prev, v)
          end
        end
      end
      -- (1.0.1) lowest level offered: when the data has no level or a higher one
      local at = e.offeredAt
      if Int(at) and at > 0 and at < 1000 then
        local lv = Q[id] and Q[id][5]
        if all or not (type(lv) == "number") or at < lv then
          records[#records + 1] = ("A %d %d"):format(id, at)
        end
      end
    end
    local objs = learnedObj[id]
    if type(objs) == "table" then
      for _, index in ipairs(SortedKeys(objs)) do
        local spots = objs[index]
        if type(spots) == "table" then
          for i = 1, #spots - 2, 3 do
            local m, sx, sy = spots[i], spots[i + 1], spots[i + 2]
            if Int(m) and m > 0 and Coord(sx) and Coord(sy) and not (ns.IsZoneMap and not ns.IsZoneMap(m))
                and (all or not SpotKnown(id, index, m, sx, sy)) then
              records[#records + 1] = ("O %d %d %d %s %s"):format(id, index, m, Fmt(sx), Fmt(sy))
            end
          end
        end
      end
    end
    -- (1.0.1) credit sources
    local cr = credits[id]
    if type(cr) == "table" then
      for _, index in ipairs(SortedKeys(cr)) do
        local c = cr[index]
        if type(c) == "table" then
          for _, kind in ipairs(KINDS) do
            for _, sid in ipairs(SortedKeys(c[kind])) do
              local n = c[kind][sid]
              if Int(n) and n > 0 and (all or not CreditKnown(id, index, kind, sid)) then
                records[#records + 1] = ("K %d %d %s %d %d"):format(id, index, kind, sid, n)
              end
            end
          end
        end
      end
    end
  end

  -- (1.0.1) quest items: where they dropped, which item starts which quest
  local drops = type(ns.db.learnedDrops) == "table" and ns.db.learnedDrops or {}
  for _, itemID in ipairs(SortedKeys(drops)) do
    local d = drops[itemID]
    if type(d) == "table" then
      local keys = {}
      for key in pairs(d) do
        if type(key) == "string" and key:match("^[co]%d+$") then keys[#keys + 1] = key end
      end
      table.sort(keys)
      for _, key in ipairs(keys) do
        local v = d[key]
        if type(v) == "table" and Int(v[1]) and v[1] > 0 and Pos(v[2], v[3], v[4])
            and (all or not DropKnown(itemID, key:sub(1, 1), tonumber(key:sub(2)))) then
          records[#records + 1] = ("D %d %s %s %d %d %s %s"):format(itemID, key:sub(1, 1), key:sub(2), v[1], v[2], Fmt(v[3]), Fmt(v[4]))
        end
      end
    end
  end
  local starts = type(ns.db.learnedItemStarts) == "table" and ns.db.learnedItemStarts or {}
  for _, itemID in ipairs(SortedKeys(starts)) do
    local q = starts[itemID]
    if Int(q) and q > 0 then records[#records + 1] = ("I %d %d -"):format(q, itemID) end
  end

  -- quests the server answered with "does not exist"
  for _, id in ipairs(ns.MissingQuestIDs and ns.MissingQuestIDs() or {}) do
    if Int(id) and id > 0 then records[#records + 1] = ("X %d"):format(id) end
  end

  -- (1.1) quests a quest giver never offers
  for _, line in ipairs(ns.NotHereRecords and ns.NotHereRecords(all) or {}) do records[#records + 1] = line end

  -- (1.3.6) dungeon entrances (always: they confirm the listed ones too)
  for _, line in ipairs(ns.EntranceRecords and ns.EntranceRecords() or {}) do records[#records + 1] = line end
  -- (1.3.6) where you walked (Paths.lua): ways around mountains for others
  for _, line in ipairs(ns.WalkRecords and ns.WalkRecords(all) or {}) do records[#records + 1] = line end
  -- (17.10.) where walking NPCs were seen (Walks.lua): "P npc map x y"
  for _, line in ipairs(ns.WalkSeenRecords and ns.WalkSeenRecords() or {}) do records[#records + 1] = line end
  -- (22.10.) what an NPC is (Services.lua): "V npc role map x y"
  for _, line in ipairs(ns.NpcRoleRecords and ns.NpcRoleRecords() or {}) do records[#records + 1] = line end
  -- (23.10.) objective orders the game showed other than the data's, seen for sure: "Y quest 2,1" (QuestData.lua)
  local orders = type(ns.db.objOrder) == "table" and ns.db.objOrder or {}
  local orderKeys = {}
  for q, v in pairs(orders) do if Int(q) and q > 0 and type(v) == "string" and v:match("^%d+[,%d]*$") then orderKeys[#orderKeys + 1] = q end end
  table.sort(orderKeys)
  for _, q in ipairs(orderKeys) do records[#records + 1] = ("Y %d %s"):format(q, orders[q]) end
  -- (27.10.) where herbs, ore, leather and fish came from (Gather.lua): "H kind source id map x y item count"
  for _, line in ipairs(ns.GatherRecords and ns.GatherRecords() or {}) do records[#records + 1] = line end
  -- (1.3.8) the reward each of your characters picked by hand: "R quest class tree item" (Rewards.lua)
  local picks = type(ns.db.rewardPicks) == "table" and ns.db.rewardPicks or {}
  local pickKeys = {}
  for k in pairs(picks) do if type(k) == "string" then pickKeys[#pickKeys + 1] = k end end
  table.sort(pickKeys)
  for _, key in ipairs(pickKeys) do
    local p = picks[key]
    if type(p) == "table" and Int(p.q) and p.q > 0 and Int(p.i) and p.i > 0 and Int(p.c) and p.c > 0 and p.c < 20 then
      records[#records + 1] = ("R %d %d %d %d"):format(p.q, p.c, Int(p.t) and p.t <= 3 and p.t or 0, p.i)
    end
  end

  -- (03.11.2026) what the shipped data or the data build has already stays home (ns.KnownLine)
  if not all then
    local n = 0
    for i = 1, #records do
      local r = records[i]
      if not ns.KnownLine(r) then n = n + 1 records[n] = r end
    end
    for i = #records, n + 1, -1 do records[i] = nil end
  end
  return records
end

-- Returns text, number of records, truncated (number of records left out).
-- all: everything learned, without comparing with ATT.
local lastShown = nil -- records of the export window, for "Mark as sent"

local function Sent()
  if type(ns.db.exportSent) ~= "table" then ns.db.exportSent = {} end
  return ns.db.exportSent
end

-- (1.3.5) M lines: NPC names the game showed in this locale. "new": only names
-- that differ from the shipped translation (or, without one, from the data).
local questNpcs
local function QuestNpcs()
  if questNpcs then return questNpcs end
  questNpcs = {}
  for _, q in pairs(Q) do
    for _, g in ipairs(type(q[7]) == "table" and q[7] or {}) do questNpcs[g] = true end
  end
  for _, e in pairs(ns.QUEST_ENDS or {}) do if type(e) == "table" and e[4] then questNpcs[e[4]] = true end end
  for _, objs in pairs(OBJ) do
    for _, o in pairs(type(objs) == "table" and objs or {}) do
      for _, c in ipairs(type(o) == "table" and type(o[1]) == "table" and o[1] or {}) do questNpcs[c] = true end
    end
  end
  return questNpcs
end

local function NameRecords(all)
  local out = {}
  local relevant = QuestNpcs()  -- quest givers, turn-in NPCs and quest mobs only
  local byLoc = type(ns.db.npcNames) == "table" and ns.db.npcNames[Locale()]
  if type(byLoc) ~= "table" then return out end
  -- English names come with the data already: an English client sends them only with "all"
  if not all and Locale() == "enUS" then return out end
  for _, id in ipairs(SortedKeys(byLoc)) do
    local name = byLoc[id]
    if relevant[id] and type(name) == "string" and name ~= "" and #name <= 80 and not name:find("[%c|]") then
      local known = (ns.NPC_NAMES and ns.NPC_NAMES[id]) or ns.CreatureName(id)
      if all or name ~= known then out[#out + 1] = ("M %d %s"):format(id, name) end
    end
  end
  return out
end

function ns.BuildExport(all)
  local records = ns.ExportRecords(all)
  for _, r in ipairs(NameRecords(all)) do records[#records + 1] = r end
  local skipped = 0
  if not all then
    local sent, kept = Sent(), {}
    for _, r in ipairs(records) do
      if r:sub(1, 2) == "X " or sent[r] then skipped = skipped + 1 else kept[#kept + 1] = r end
    end
    records = kept
  end
  local lines = { ("QDX2 %s %s %s %s"):format(ns.Version(), Locale(), ns.Today(), all and "all" or "new") }
  local n = math.min(#records, MAX_LINES)
  for i = 1, n do lines[#lines + 1] = records[i] end
  local truncated = #records - n
  if truncated > 0 then lines[#lines + 1] = ("# truncated %d"):format(truncated) end
  lines[#lines + 1] = ("# records %d"):format(n)
  lastShown = {}
  for i = 1, n do lastShown[i] = records[i] end
  return table.concat(lines, "\n"), n, truncated, skipped
end

-- Marks the records of the export window as sent; returns how many.
function ns.MarkExportSent()
  if type(lastShown) ~= "table" then return 0 end
  local sent, n = Sent(), 0
  for _, r in ipairs(lastShown) do
    if not sent[r] then sent[r] = true n = n + 1 end
  end
  return n
end
function ns.ExportSentCount()
  local n = 0
  for _ in pairs(type(ns.db.exportSent) == "table" and ns.db.exportSent or {}) do n = n + 1 end
  return n
end

---------------------------------------------------------------------------
-- Window: read-only, multi-line text to copy from. Shared by the export, the
-- diagnostics, the dungeon levels, the XP sources, the journal as text and
-- the missing quests (ns.ShowText).
-- (04.11.2026, Era-Test, Daniel: "das scheint noch im alten stil") DonCore's
-- one copy window of every Don addon (Kit.ShowCopy, like Luredon and
-- Vitaldon: title, hint, the text marked, "Select all" and "Close", Esc
-- closes); Questdon's own text window (1.20 Style.Panel, 1.24 own scroll
-- frame) is gone. Without the kit the text goes to the chat, as before.
---------------------------------------------------------------------------
local text
ns.windowParts = {} -- what the text window has (for /qd diag)

local function Kit() return LibStub("DonCore-1.0"):Get("Kit", 4) end

-- For the tests: the text in the window.
function ns.ShowTextBody() return text end

-- Shows text to copy: heading, note above the box, the text itself.
-- If the window cannot be built on this client, the text goes to the chat.
function ns.ShowText(heading, note, body)
  body = body or ""
  local K = Kit()
  local ok, d = false, nil
  if K and K.ShowCopy then
    ok, d = pcall(K.ShowCopy, ns.Style.Wordmark("Quest", "don") .. ": " .. tostring(heading or ""), note or "", body,
      { selectAll = L["Select all"], close = L["Close"] })
  end
  if not (ok and d) then
    ns.windowParts.built = false
    ns.Print(heading)
    for line in (body .. "\n"):gmatch("(.-)\n") do print(line) end
    return body
  end
  text = body
  ns.windowParts.built, ns.windowParts.kit = true, true
  ns.textWindow = d
  return body, d
end

function ns.OpenExport(all)
  local body, count, truncated, skipped = ns.BuildExport(all)
  local note
  if count == 0 then
    note = all and L["Nothing learned yet. Play a while with \"Learn quest locations\" switched on."]
      or (skipped or 0) > 0 and L["Nothing new since your last export marked as sent. /qd export all shows everything."]
      or L["Nothing new: everything Questdon learned is already in its data. /qd export all shows everything."]
  else
    note = L["%d entries. Ctrl+A selects all, Ctrl+C copies. Paste it into a new issue at %s (form \"Quest data\")."]:format(count, ISSUE_URL)
    if truncated > 0 then note = note .. " " .. L["Truncated: %d more entries left out."]:format(truncated) end
  end
  -- (1.3.5) the M lines carry NPC names as the game showed them
  note = note .. " " .. L["Numbers and the NPC names your game showed: no character, realm or guild names."]
  if not all and (skipped or 0) > 0 then
    note = note .. " " .. L["%d entries you already sent are left out (/qd export all shows everything)."]:format(skipped)
  end
  local shown, d = ns.ShowText(L["Export learned data"], note, body)
  -- (1.3.3) mark the export as sent (only for /qd export); (04.11.2026) a third button in the copy window
  if d and d.SetButtons and count > 0 then
    local function Close(dd) dd:Hide() end
    local function SelectAll(dd) dd.edit:SetFocus() dd.edit:HighlightText() end
    local tip = { L["Mark as sent"], L["Click after you sent the text. Entries that do not change are left out of the next export; anything new or changed comes along. /qd export all still shows everything."] }
    local buttons
    buttons = {
      { text = L["Mark as sent"], tooltip = tip, onClick = ns.Guard("export", function(dd)
        local n = ns.MarkExportSent()
        buttons[1] = { text = L["Marked as sent: %d entries."]:format(n), disabled = true }
        dd:SetButtons(buttons)
      end) },
      { text = L["Select all"], onClick = SelectAll },
      { text = L["Close"], kind = "primary", onClick = Close },
    }
    d:SetButtons(buttons)
  end
  return shown
end
