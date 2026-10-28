local _, ns = ...

---------------------------------------------------------------------------
-- (27.10.2026, Daniel: "für Questdon, weil es am weitesten verbreitet ist, auch mit tracken lassen, wo Erze, Blumen,
-- Leder, Fische gefunden werden ... erstmal nur sammeln und teilen für unsere Datenbestände, Fischfänge dann für
-- Luredon") Where herbs, ore, leather and fish come from. Nothing is shown in the game; the finds go into /qd export
-- and are shared like the other learned facts (Exchange.lua, line H), so the data of all players grows.
--
-- How: the player's last gathering cast (UNIT_SPELLCAST_SUCCEEDED for "player", Learn.lua's cast frame; spell IDs from CMaNGOS spell_template: open lock
-- herb 2, open lock mining 3, skinning, fishing) or, for fish, IsFishingLoot; then the loot window: the source from
-- GetLootSourceInfo (the node, pool or skinned creature), the player's place and every item of the loot.
--
--   QuestdonDB.learnedGather["<k> <s><id> <map> <gx> <gy>"] = { x, y, n, items = { [itemID] = count } }
--     k  h herb, m mining, s skinning, f fishing
--     s  o object (node, fishing pool), c creature (skinned), - none (open water: the bobber)
--     gx gy  a grid of CELL map units (one entry per node place), x y the first place seen there (0..1)
--   export / share line:  H <k> <s> <id> <map> <x> <y> <itemID> <count>
-- At most MAX_CELLS places are kept; places already full keep counting.
---------------------------------------------------------------------------
local CELL = 1.0       -- map units (0..100): one place
local MAX_CELLS = 3000
local CAST_SECS = 6    -- the loot window opens this soon after the cast
local MAX_ITEMS = 6    -- different items per place

-- CMaNGOS spell_template: Effect 33 open lock with misc 2 (herb) and 3 (mining), 95 skinning, 50 the fishing bobber
local SPELLS = {
  [2366] = "h", [2368] = "h", [2369] = "h", [2371] = "h", [3570] = "h", [11993] = "h",
  [2575] = "m", [2576] = "m", [2577] = "m", [2578] = "m", [2579] = "m", [3564] = "m", [10248] = "m",
  [8613] = "s", [8617] = "s", [8618] = "s", [10768] = "s",
  [7620] = "f", [7731] = "f", [7732] = "f", [18248] = "f",
}
ns.GATHER_SPELLS = SPELLS
-- Forever may give the casts new IDs: the names of the classic ones, read from the client, count as well
local NAME_OF = { h = 2366, m = 2575, s = 8613, f = 7620 }
local byName
local function SpellName(id)
  if C_Spell and type(C_Spell.GetSpellName) == "function" then
    local n = ns.Value(C_Spell.GetSpellName, id)
    if type(n) == "string" and n ~= "" then return n end
  end
  if type(GetSpellInfo) == "function" then
    local n = ns.Value(GetSpellInfo, id)
    if type(n) == "string" and n ~= "" then return n end
  end
  return nil
end
local function KindOfSpell(spellID)
  spellID = ns.Num(spellID)
  if not spellID then return nil end
  if SPELLS[spellID] then return SPELLS[spellID] end
  if not byName then
    byName = {}
    for k, id in pairs(NAME_OF) do
      local n = SpellName(id)
      if n then byName[n] = k end
    end
    if not next(byName) then byName = nil return nil end
  end
  local n = SpellName(spellID)
  return n and byName[n] or nil
end
ns.GatherKindOfSpell = KindOfSpell

local last -- { kind, t }
local function Clock() return ns.Num(ns.Value(GetTime)) or 0 end

function ns.GatherCast(spellID)
  local kind = KindOfSpell(spellID)
  if kind then last = { kind, Clock() } end
  return kind
end
-- called from Learn.lua's frame for the player's own casts (a unit event: other units' casts never reach Questdon)

local function ItemID(link)
  if type(link) ~= "string" or not ns.Usable(link) then return nil end
  local id = tonumber(link:match("item:(%d+)"))
  return id and id > 0 and id or nil
end

local function DB()
  local db = ns.db
  if type(db.learnedGather) ~= "table" then db.learnedGather = {} end
  return db.learnedGather
end

local count -- number of places, counted once
local function Places(t)
  if not count then
    count = 0
    for _ in pairs(t) do count = count + 1 end
  end
  return count
end
function ns.GatherReset() count = nil last = nil byName = nil end -- (tests, Options reset)

-- note one loot window; returns the key of the place or nil
function ns.NoteGather()
  if not (ns.db and ns.db.learnQuests) or not (GetNumLootItems and GetLootSlotLink) then return nil end
  local kind = last and Clock() - last[2] <= CAST_SECS and last[1] or nil
  if ns.True(ns.Value(IsFishingLoot)) then kind = "f" end
  if not kind then return nil end
  last = nil
  local map, x, y = ns.PlayerPosition()
  if not map then return nil end
  local items, src, srcID = {}, "-", 0
  for slot = 1, ns.Num(ns.Value(GetNumLootItems)) or 0 do
    local id = ItemID(ns.Value(GetLootSlotLink, slot))
    if id then
      local ok, _, _, qty = pcall(GetLootSlotInfo, slot)
      items[id] = (items[id] or 0) + (ok and ns.Num(qty) or 1)
      if srcID == 0 and GetLootSourceInfo then
        local info = { pcall(GetLootSourceInfo, slot) }
        if info[1] then
          local k, id2 = ns.GUIDKindID(info[2])
          -- the fishing bobber is no place of its own: open water
          if k and not (k == "o" and id2 == 35591) then src, srcID = k, id2 end
        end
      end
    end
  end
  if not next(items) then return nil end
  local t = DB()
  local key = ("%s %s%d %d %d %d"):format(kind, src, srcID, map, math.floor(x * 100 / CELL), math.floor(y * 100 / CELL))
  local e = t[key]
  if not e then
    if Places(t) >= MAX_CELLS then return nil end
    e = { math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000, 0, items = {} }
    t[key] = e
    count = count + 1
  end
  e[3] = math.min((ns.Num(e[3]) or 0) + 1, 9999)
  e.items = type(e.items) == "table" and e.items or {}
  local have = 0
  for _ in pairs(e.items) do have = have + 1 end
  for id in pairs(items) do
    if e.items[id] or have < MAX_ITEMS then
      if not e.items[id] then have = have + 1 end
      e.items[id] = math.min((ns.Num(e.items[id]) or 0) + 1, 9999) -- loot windows with this item, not the stack size
    end
  end
  return key
end
ns.On("LOOT_READY", function() ns.NoteGather() end)

-- export and share lines, sorted
function ns.GatherRecords()
  local out = {}
  local t = type(ns.db and ns.db.learnedGather) == "table" and ns.db.learnedGather or {}
  local keys = {}
  for k in pairs(t) do if type(k) == "string" then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local kind, src, id, map = k:match("^([hmsf]) ([oc%-])(%d+) (%d+) ")
    local e = t[k]
    if kind and type(e) == "table" and type(e.items) == "table" then
      local x, y = ns.Num(e[1]), ns.Num(e[2])
      if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        local ids = {}
        for item in pairs(e.items) do if type(item) == "number" then ids[#ids + 1] = item end end
        table.sort(ids)
        for _, item in ipairs(ids) do
          local n = ns.Num(e.items[item])
          if n and n > 0 then
            out[#out + 1] = ("H %s %s %s %s %.1f %.1f %d %d"):format(kind, src, id, map, x * 100, y * 100, item, math.floor(n))
          end
        end
      end
    end
  end
  return out
end
