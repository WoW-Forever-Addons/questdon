local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.3.11 Stufe 3, Daniel 23.10.) The journal as a story (TAGEBUCH_PLAN.md):
--   chapters  stretches of the time line in one zone ("Westfall, level 12 to
--             16, 23 quests, 4:10 h, 2 pictures"); a short stop elsewhere
--             (a city, two quests) stays in the chapter around it
--   review    played time per level, longest and fastest quest, best day,
--             "a week ago", totals, who you quested with most
--   text      the journal as text to copy (Discord, forums), see QuestBook.lua
--   with whom the group at each turn-in (e.pt, as for moments)
--   characters every character of the account: level, quests, last played
--
-- Played time: Questdon keeps its own clock per character, only from events
-- (no ticker): QuestdonCharDB.journal.pc = { s = seconds counted, t = since
-- when it runs (nil: logged out), lv = { l, s } the level's start after
-- /played }. Every new entry gets e.pc, the clock at that moment. Time
-- between two entries is the difference of their clocks; for entries
-- without it (older than this) the time between them, at most 20 minutes.
--
-- Account: QuestdonDB.chars = { ["Realm/Name"] = { n, r, c = class file,
-- cn = class, ra = race, f = faction, l = level, q = quests, g = copper,
-- m = zone map, t = last seen } }
---------------------------------------------------------------------------
local GAP_CAP = 20 * 60       -- without the clock: a pause longer than this counts as this
local CHAPTER_QUESTS = 3      -- a stretch with fewer quest events is a stop inside a chapter ...
local CHAPTER_DUNGEON = 600   -- ... unless it holds a dungeon visit of 10 minutes or a boss
local FASTEST_MIN = 60        -- the fastest quest: at least a minute (no "talk to" quests)
local MAX_MATES = 5

local function Now() return ns.Num(ns.Value(time)) end
local function Store() return ns.JournalStore and ns.JournalStore() end
local function Name(v) return type(v) == "string" and ns.Usable(v) and v ~= "" and v or nil end

local function ZoneOf(m)
  m = ns.Num(m)
  if not m then return nil end
  return ns.MinimapZoneMap and ns.MinimapZoneMap(m) or m
end

---------------------------------------------------------------------------
-- The played clock
---------------------------------------------------------------------------
local function Clock(j)
  local p = j.pc
  if type(p) ~= "table" then p = { s = 0 } j.pc = p end
  p.s = ns.Num(p.s) or 0
  return p
end

-- the clock now; fold = true moves what ran into s (a checkpoint)
local function PlayedNow(j, fold)
  local p = Clock(j)
  local now = Now()
  local s = p.s
  local t = ns.Num(p.t)
  if t and now and now > t then s = s + (now - t) end
  if fold then p.s, p.t = s, now end
  return s
end

-- Journal.lua calls this for every new entry: the clock, and at a turn-in the group
function ns.JournalStamp(e, j)
  if type(e) ~= "table" or type(j) ~= "table" then return end
  e.pc = PlayedNow(j, true)
  if e.k == "c" and not e.pt and ns.JournalGroupNames then e.pt = ns.JournalGroupNames() end
end

function ns.JournalPlayed()
  local j = Store()
  return j and PlayedNow(j) or 0
end

ns.On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
  local j = Store()
  if not j then return end
  local p = Clock(j)
  -- a new session: the clock runs from now (a session that ended without a
  -- logout, a crash, keeps what it had at its last entry); a loading screen
  -- inside the session changes nothing
  if isLogin or isReload or not p.t then p.t = Now() end
end)

ns.On("PLAYER_LOGOUT", function()
  local j = Store()
  if not j then return end
  PlayedNow(j, true)
  Clock(j).t = nil
end)

-- /played (the player's or another addon's): the exact time on this level
ns.On("TIME_PLAYED_MSG", function(_, total, thisLevel)
  local j = Store()
  local lv = ns.Num(thisLevel)
  if not (j and lv and lv >= 0) then return end
  local p = Clock(j)
  p.lv = { l = ns.PlayerLevel(), s = PlayedNow(j) - lv }
end)

---------------------------------------------------------------------------
-- Time between entries
---------------------------------------------------------------------------
-- played seconds from entry a to entry b (b later); exact = both have the clock
local function Between(a, b)
  local pa, pb = ns.Num(a.pc), ns.Num(b.pc)
  if pa and pb and pb >= pa then return pb - pa, true end
  local ta, tb = ns.Num(a.t), ns.Num(b.t)
  if not (ta and tb) or tb < ta then return 0, false end
  return math.min(tb - ta, GAP_CAP), false
end

-- played seconds over a run of entries (oldest first), and whether all of it is exact
local function Active(list, i1, i2)
  local s, exact = 0, true
  for i = (i1 or 1) + 1, i2 or #list do
    local d, ok = Between(list[i - 1], list[i])
    s = s + d
    exact = exact and ok
  end
  return s, exact
end
ns.JournalActive = Active

-- dated entries, oldest first (the stored ones, not copies)
local function Dated(j)
  local out = {}
  for i = 1, #j.e do
    local e = j.e[i]
    if type(e) == "table" and e.k and ns.Num(e.t) then out[#out + 1] = e end
  end
  return out
end

local function CacheKey(j)
  local last = j.e[#j.e]
  return #j.e .. ":" .. tostring(type(last) == "table" and last.t) .. ":" .. tostring(type(last) == "table" and last.note)
end

---------------------------------------------------------------------------
-- Chapters
---------------------------------------------------------------------------
local QUESTY = { a = true, c = true }

local function Big(run)
  local n = 0
  for _, e in ipairs(run.e) do
    if QUESTY[e.k] then n = n + 1 end
    if e.k == "i" and ((ns.Num(e.d) or 0) >= CHAPTER_DUNGEON or (type(e.b) == "table" and #e.b > 0)) then return true end
  end
  return n >= CHAPTER_QUESTS
end

local function Append(dst, src) for _, e in ipairs(src) do dst[#dst + 1] = e end end

local chapCache, chapKey
function ns.JournalChapters()
  local j = Store()
  if not j then return {} end
  local key = CacheKey(j)
  if chapCache and chapKey == key then return chapCache end
  local entries = Dated(j)
  -- runs of one zone (entries without a zone stay where they are)
  local runs, cur = {}, nil
  for _, e in ipairs(entries) do
    local z = ZoneOf(e.m)
    if not cur then
      cur = { z = z, e = {} } runs[#runs + 1] = cur
    elseif z and not cur.z then
      cur.z = z
    elseif z and z ~= cur.z then
      cur = { z = z, e = {} } runs[#runs + 1] = cur
    end
    cur.e[#cur.e + 1] = e
  end
  -- a small run joins the chapter before it; small runs at the very start join the next big one
  local chapters, waiting = {}, nil
  for _, r in ipairs(runs) do
    local last = chapters[#chapters]
    if not Big(r) then
      if last then Append(last.e, r.e) else waiting = waiting or {} Append(waiting, r.e) end
    elseif last and last.z == r.z then
      Append(last.e, r.e)
    else
      local ch = { z = r.z, e = {} }
      if waiting then Append(ch.e, waiting) waiting = nil end
      Append(ch.e, r.e)
      chapters[#chapters + 1] = ch
    end
  end
  if waiting then chapters[#chapters + 1] = { z = ZoneOf(waiting[#waiting].m) or ZoneOf(waiting[1].m), e = waiting } end
  -- what each chapter holds
  for _, ch in ipairs(chapters) do
    local first, last = ch.e[1], ch.e[#ch.e]
    ch.key, ch.t1, ch.t2 = first.t, first.t, last.t
    ch.q, ch.xp, ch.g, ch.d, ch.s, ch.i, ch.a = 0, 0, 0, 0, 0, 0, 0
    local mates = {}
    for _, e in ipairs(ch.e) do
      local lv = ns.Num(e.l)
      if lv and e.k ~= "l" then ch.l1 = math.min(ch.l1 or lv, lv) ch.l2 = math.max(ch.l2 or lv, lv) end
      if e.k == "l" and lv then ch.l1 = math.min(ch.l1 or lv - 1, lv - 1) ch.l2 = math.max(ch.l2 or lv, lv) end
      if e.k == "c" then
        ch.q = ch.q + 1
        ch.xp = ch.xp + (ns.Num(e.x) or 0)
        ch.g = ch.g + (ns.Num(e.g) or 0)
      elseif e.k == "a" then ch.a = ch.a + 1
      elseif e.k == "d" then ch.d = ch.d + 1
      elseif e.k == "s" then ch.s = ch.s + 1
      elseif e.k == "i" then ch.i = ch.i + 1 ch.dungeon = ch.dungeon or e.n
      end
      if type(e.pt) == "string" and e.k == "c" then
        for n in e.pt:gmatch("[^,]+") do n = n:gsub("^%s+", ""):gsub("%s+$", "") if n ~= "" then mates[n] = (mates[n] or 0) + 1 end end
      end
    end
    ch.time, ch.exact = Active(ch.e)
    local names = {}
    for n, c in pairs(mates) do names[#names + 1] = { n = n, c = c } end
    table.sort(names, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.n < b.n end)
    ch.mates = names
  end
  -- newest first
  local n = #chapters
  for i = 1, math.floor(n / 2) do chapters[i], chapters[n - i + 1] = chapters[n - i + 1], chapters[i] end
  chapCache, chapKey = chapters, key
  return chapters
end

-- the chapter's name: its zone, or the dungeon of a dungeon chapter
function ns.JournalChapterTitle(ch)
  local name = ch.z and ns.JournalMapName and ns.JournalMapName(ch.z)
  return name or ch.dungeon or L["Unknown zone"]
end

---------------------------------------------------------------------------
-- Review
---------------------------------------------------------------------------
local function DayKey(t) return ns.JournalFmt and ns.JournalFmt.DayKey(t) or 0 end

local recapCache, recapKey
function ns.JournalRecap()
  local j = Store()
  local r = { levels = {}, mates = {}, totals = { q = 0, xp = 0, g = 0, d = 0, i = 0, s = 0, r = 0, days = 0, zones = 0, a = 0 } }
  if not j then return r end
  local key = CacheKey(j) .. ":" .. tostring(ns.PlayerLevel())
  if recapCache and recapKey == key then return recapCache end
  local entries = Dated(j)
  local tot = r.totals
  local days, zones, mates, accepted = {}, {}, {}, {}
  local prevLevelAt -- index of the last level-up (or the start of a fresh character)
  if entries[1] and ns.Num(entries[1].l) == 1 then prevLevelAt = 1 end
  for i, e in ipairs(entries) do
    local k = e.k
    if days[DayKey(e.t)] == nil then days[DayKey(e.t)] = { t = e.t, q = 0, xp = 0, n = 0 } tot.days = tot.days + 1 end
    local day = days[DayKey(e.t)]
    day.n = day.n + 1
    local z = ZoneOf(e.m)
    if z and not zones[z] then zones[z] = true tot.zones = tot.zones + 1 end
    if k == "a" and e.q then accepted[e.q] = e tot.a = tot.a + 1
    elseif k == "c" then
      tot.q = tot.q + 1
      tot.xp = tot.xp + (ns.Num(e.x) or 0)
      tot.g = tot.g + (ns.Num(e.g) or 0)
      day.q = day.q + 1
      day.xp = day.xp + (ns.Num(e.x) or 0)
      local a = e.q and accepted[e.q]
      if a then
        accepted[e.q] = nil
        local exact = ns.Num(a.pc) and ns.Num(e.pc)
        local took = exact and (e.pc - a.pc) or (e.t - a.t)
        if took and took >= 0 then
          local rec = { e = e, a = a, s = took, played = exact and true or false }
          if not r.longest or took > r.longest.s then r.longest = rec end
          if took >= FASTEST_MIN and (not r.fastest or took < r.fastest.s) then r.fastest = rec end
        end
      end
      if type(e.pt) == "string" then
        for n in e.pt:gmatch("[^,]+") do n = n:gsub("^%s+", ""):gsub("%s+$", "") if n ~= "" then mates[n] = (mates[n] or 0) + 1 end end
      end
    elseif k == "d" then tot.d = tot.d + 1
    elseif k == "i" then tot.i = tot.i + 1
    elseif k == "s" then tot.s = tot.s + 1
    elseif k == "r" then tot.r = tot.r + 1
    elseif k == "l" then
      local lv = ns.Num(e.l)
      if prevLevelAt and lv then
        local s, exact = Active(entries, prevLevelAt, i)
        r.levels[#r.levels + 1] = { l = lv - 1, s = s, exact = exact, t = e.t }
      end
      prevLevelAt = i
    end
  end
  -- the best day: the most experience (then the most quests)
  for _, d in pairs(days) do
    if d.q > 0 and (not r.best or d.xp > r.best.xp or (d.xp == r.best.xp and d.q > r.best.q)) then r.best = d end
  end
  -- a week ago today
  local now = Now()
  if now then
    local wk = days[DayKey(now - 7 * 86400)]
    if wk then
      r.week = wk
      r.weekEntries = {}
      local key7 = DayKey(now - 7 * 86400)
      for _, e in ipairs(entries) do if DayKey(e.t) == key7 then r.weekEntries[#r.weekEntries + 1] = e end end
    end
  end
  for n, c in pairs(mates) do r.mates[#r.mates + 1] = { n = n, c = c } end
  table.sort(r.mates, function(a, b) if a.c ~= b.c then return a.c > b.c end return a.n < b.n end)
  while #r.mates > MAX_MATES do table.remove(r.mates) end
  r.played = j.pc and ns.Num(j.pc.s) and PlayedNow(j) or nil
  recapCache, recapKey = r, key
  return r
end

-- played time on the level you are on (not cached: the clock runs), and whether it is exact
function ns.JournalLevelPlayed()
  local j = Store()
  if not j then return nil end
  local level = ns.PlayerLevel()
  local p = Clock(j)
  if type(p.lv) == "table" and p.lv.l == level and ns.Num(p.lv.s) then return math.max(0, PlayedNow(j) - p.lv.s), true end
  local i = #j.e
  while i >= 1 and not (type(j.e[i]) == "table" and j.e[i].k == "l") do i = i - 1 end
  if i < 1 then
    if type(j.e[1]) == "table" and ns.Num(j.e[1].l) == 1 then i = 1 else return nil end
  end
  local list = {}
  for k = i, #j.e do
    local e = j.e[k]
    if type(e) == "table" and ns.Num(e.t) then list[#list + 1] = e end
  end
  if #list == 0 then return nil end
  local s, exact = Active(list)
  local last = list[#list]
  if ns.Num(last.pc) then s = s + math.max(0, PlayedNow(j) - last.pc) else exact = false end
  return s, exact
end

-- (tests) forget the cached chapters and review
function ns.JournalChronicleReset() chapCache, chapKey, recapCache, recapKey = nil, nil, nil, nil end

---------------------------------------------------------------------------
-- Characters of the account
---------------------------------------------------------------------------
local function MyKey()
  local name = Name(ns.Value(UnitName, "player"))
  local realm = Name(ns.Value(GetRealmName))
  if not name then return nil end
  return (realm or "?") .. "/" .. name, name, realm
end
ns.JournalMyKey = MyKey

local function UpdateMe()
  local db = ns.db
  local key, name, realm = MyKey()
  if type(db) ~= "table" or not key then return end
  if type(db.chars) ~= "table" then db.chars = {} end
  local c = db.chars[key]
  if type(c) ~= "table" then c = {} db.chars[key] = c end
  c.n, c.r = name, realm
  local ok, cn, cf = false, nil, nil
  if type(UnitClass) == "function" then ok, cn, cf = pcall(UnitClass, "player") end
  if ok then c.cn, c.c = Name(cn) or c.cn, Name(cf) or c.c end
  c.ra = Name((ns.Value(UnitRace, "player"))) or c.ra
  c.f = Name((ns.Value(UnitFactionGroup, "player"))) or c.f
  c.l = ns.PlayerLevel() or c.l
  local counts = ns.JournalCounts and ns.JournalCounts()
  if counts then c.q = (counts.c or 0) + (counts.old or 0) end
  c.g = ns.Num(ns.Value(GetMoney)) or c.g
  local m = ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  c.m = ZoneOf(m) or c.m
  c.t = Now() or c.t
end
ns.JournalUpdateMe = UpdateMe

ns.On("PLAYER_ENTERING_WORLD", function() ns.After(4, UpdateMe) end)
ns.On("PLAYER_LEVEL_UP", function() ns.After(1, UpdateMe) end)
ns.On("PLAYER_LOGOUT", UpdateMe)

-- every character, the one you play first, then the last played
function ns.JournalCharacters()
  UpdateMe() -- the one you play: as it is now
  local out = {}
  local db = ns.db
  local mine = MyKey()
  for key, c in pairs(type(db) == "table" and type(db.chars) == "table" and db.chars or {}) do
    if type(c) == "table" and c.n then
      local copy = { key = key, me = key == mine }
      for k, v in pairs(c) do copy[k] = v end
      out[#out + 1] = copy
    end
  end
  table.sort(out, function(a, b)
    if a.me ~= b.me then return a.me end
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
    return tostring(a.key) < tostring(b.key)
  end)
  return out
end

-- a character that no longer exists: off the list (not the one you play)
function ns.JournalForgetCharacter(key)
  local db = ns.db
  if key == MyKey() or type(db) ~= "table" or type(db.chars) ~= "table" then return false end
  if db.chars[key] == nil then return false end
  db.chars[key] = nil
  return true
end
