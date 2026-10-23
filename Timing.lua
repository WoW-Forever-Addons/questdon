local _, ns = ...

---------------------------------------------------------------------------
-- (1.3.9, Daniel 18.10.: "what can Questdon collect for the routes", DATENPLAN_QUESTDON.md) Play times.
-- What a quest really costs, measured while you play and shared like the learned places (only numbers):
--   Q <quest> <level> <class> <secs> <deaths> <group> <parallel> <ld> <xp> <copper>   at the turn-in
--       secs: seconds in the quest's objective area (within AREA_YARDS of its nearest open spot, not on a flight,
--       not dead, not AFK, not standing idle IDLE_SECS out of a fight); parallel: most quests counted in the same
--       second; group: largest group; ld: 1 when Leveldon was loaded; xp and copper of the turn-in
--   L <item> <creature> <corpses> <drops>   at the turn-in, per quest item: corpses of that creature looted while
--       a quest item was needed, and how many of the item they gave (drop rate)
--   J <map> <x> <y> <map> <x> <y> <secs>   a flight: where it started, where it landed, how long
--   B <quest> <level>                     a quest abandoned
-- No new per-frame work: the quest list's distances of each second are handed in (ns.TimingSeen from
-- Tracker.lua); without the list, a check every TICK seconds asks for them. Kept per character while a quest
-- runs (QuestdonCharDB.timing, survives a /reload); the finished lines wait in QuestdonDB.sampleOut until they
-- were sent SAMPLE_SENDS times (Exchange.lua) and are kept with what others sent in QuestdonDB.samples.
---------------------------------------------------------------------------
local AREA_YARDS, IDLE_SECS, IDLE_MOVE, TICK = 60, 30, 3, 2
local MAX_OWN = 400            -- own lines waiting to be sent
local SAMPLE_SENDS = 3         -- each own line goes out this often (receivers miss what is sent while offline)
local SAMPLE_GAP = 8 * 3600    -- seconds between two sends of the same line
local SAMPLE_AGE = 7 * 86400   -- an own line older than this is not sent any more
local PER_KEY = { Q = 12, L = 20, J = 8, B = 30 } -- lines kept per subject (quest, item and creature, flight)
local MAX_SAMPLES = 30000      -- lines kept in all
local MAX_CORPSES = 300        -- corpse GUIDs remembered (one count per corpse)

local stats = { seconds = 0, quests = 0, lines = 0, flights = 0, received = 0, dup = 0, pruned = 0 }
ns.timingStats = stats

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end
local function Clock() return ns.Num(ns.Value(time)) or Now() end
local function On() return ns.db and ns.db.shareTimes ~= false end

local function CharState()
  local c = ns.charDB
  if type(c) ~= "table" then return nil end
  local t = c.timing
  if type(t) ~= "table" or t.v ~= 1 then t = { v = 1, q = {}, cor = {}, drop = {} } c.timing = t end
  if type(t.q) ~= "table" then t.q = {} end
  if type(t.cor) ~= "table" then t.cor = {} end
  if type(t.drop) ~= "table" then t.drop = {} end
  return t
end

local function Account()
  local db = ns.db
  if type(db.sampleOut) ~= "table" then db.sampleOut = {} end
  if type(db.samples) ~= "table" then db.samples = {} end
  return db
end

---------------------------------------------------------------------------
-- Storing lines (own and received)
---------------------------------------------------------------------------
local sampleCount
local function SampleKey(line)
  local kind = line:sub(1, 1)
  if kind == "Q" or kind == "B" then return kind .. " " .. (line:match("^%a (%d+)") or "?") end
  if kind == "L" then return "L " .. (line:match("^L (%d+ %d+)") or "?") end
  if kind == "J" then
    -- a flight by its two ends, rounded to whole map units
    local m1, x1, y1, m2, x2, y2 = line:match("^J (%d+) ([%d%.]+) ([%d%.]+) (%d+) ([%d%.]+) ([%d%.]+)")
    if not m1 then return "J ?" end
    return ("J %s %d %d %s %d %d"):format(m1, tonumber(x1), tonumber(y1), m2, tonumber(x2), tonumber(y2))
  end
  return kind .. " ?"
end
local function CountSamples()
  local n = 0
  for _, list in pairs(Account().samples) do if type(list) == "table" then n = n + #list end end
  return n
end
-- Make room: the subjects with the most lines give up their oldest first.
local function PruneSamples()
  local samples = Account().samples
  local keys = {}
  for k, list in pairs(samples) do if type(list) == "table" and #list > 1 then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) return #samples[a] > #samples[b] end)
  local over = (sampleCount or CountSamples()) - math.floor(MAX_SAMPLES * 0.9)
  for _, k in ipairs(keys) do
    if over <= 0 then break end
    local list = samples[k]
    while #list > 1 and over > 0 do table.remove(list, 1) over = over - 1 stats.pruned = stats.pruned + 1 end
  end
  sampleCount = nil
end

-- One line as "<reporter> <line>"; the same reporter with the same line again (a resend) changes nothing.
-- Returns true when it was new.
function ns.StoreSample(line, reporter)
  if type(line) ~= "string" or type(reporter) ~= "string" then return false end
  local samples = Account().samples
  local key = SampleKey(line)
  local list = samples[key]
  if type(list) ~= "table" then list = {} samples[key] = list end
  local entry = reporter .. " " .. line
  for i = 1, #list do if list[i] == entry then stats.dup = stats.dup + 1 return false end end
  list[#list + 1] = entry
  local cap = PER_KEY[line:sub(1, 1)] or 10
  while #list > cap do table.remove(list, 1) end
  sampleCount = (sampleCount or CountSamples()) + 1
  if sampleCount > MAX_SAMPLES then PruneSamples() end
  return true
end
function ns.SampleCount() if not sampleCount then sampleCount = CountSamples() end return sampleCount end

-- An own line: kept with the others' (reporter "me") and queued for sending.
local function Emit(line)
  stats.lines = stats.lines + 1
  ns.StoreSample(line, "me")
  if not On() then return end
  local out = Account().sampleOut
  out[#out + 1] = { line, 0, 0, Clock() }
  while #out > MAX_OWN do table.remove(out, 1) end
end
ns.TimingEmit = Emit -- (tests)

-- For Exchange.lua: own lines due to be sent, oldest first: { index, line } (at most n).
function ns.SamplesDue(n)
  local out, list, now = Account().sampleOut, {}, Clock()
  local i = 1
  while i <= #out do
    local e = out[i]
    if type(e) ~= "table" or (ns.Num(e[2]) or 0) >= SAMPLE_SENDS or now - (ns.Num(e[4]) or now) > SAMPLE_AGE then
      table.remove(out, i) -- done or too old
    else
      local last = ns.Num(e[3]) or 0
      if #list < n and (last == 0 or now - last >= SAMPLE_GAP) then list[#list + 1] = e end -- never sent, or hours ago
      i = i + 1
    end
  end
  return list
end
-- When the next own line is due again (nil: none waits).
function ns.SamplesNextDue()
  local best
  for _, e in ipairs(Account().sampleOut) do
    if type(e) == "table" and (ns.Num(e[2]) or 0) < SAMPLE_SENDS then
      local t = (ns.Num(e[3]) or 0) == 0 and 0 or e[3] + SAMPLE_GAP
      if not best or t < best then best = t end
    end
  end
  return best
end
function ns.SampleSent(e)
  if type(e) == "table" then e[2], e[3] = (ns.Num(e[2]) or 0) + 1, Clock() end
end

---------------------------------------------------------------------------
-- Measuring
---------------------------------------------------------------------------
local function ClassID()
  local ok, _, _, id = pcall(UnitClass, "player")
  return ok and ns.Num(id) or 0
end
local function GroupSize()
  local n = GetNumGroupMembers and ns.Num(ns.Value(GetNumGroupMembers)) or 0
  return n or 0
end
local function LeveldonOn()
  local fn = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  return type(fn) == "function" and ns.True(ns.Value(fn, "Leveldon")) and 1 or 0
end
local function Busy()
  -- on a flight, dead or AFK nothing counts
  if UnitOnTaxi and ns.True(ns.Value(UnitOnTaxi, "player")) then return "taxi" end
  if UnitIsDeadOrGhost and ns.True(ns.Value(UnitIsDeadOrGhost, "player")) then return "dead" end
  if UnitIsAFK and ns.True(ns.Value(UnitIsAFK, "player")) then return "afk" end
  return nil
end

local lastPos = { c = nil, n = 0, w = 0, t = 0 } -- where the player last moved (or fought)
local lastFeed, lastCount = -100, -100
local function Idle(now)
  local pc, pn, pw
  if ns.PlayerWorld then pc, pn, pw = ns.PlayerWorld() end -- (not "a and f()": that keeps only the first value)
  local fight = ns.True(ns.Value(InCombatLockdown)) or (UnitAffectingCombat and ns.True(ns.Value(UnitAffectingCombat, "player")))
  if not (pn and pw) then pc = nil end
  if fight or not pc or pc ~= lastPos.c or (pn - lastPos.n) ^ 2 + (pw - lastPos.w) ^ 2 > IDLE_MOVE * IDLE_MOVE then
    if pc then lastPos.c, lastPos.n, lastPos.w = pc, pn, pw end
    lastPos.t = now
  end
  return now - lastPos.t > IDLE_SECS
end

-- The quest list's entries of this second (Tracker.lua Entries): every open quest within AREA_YARDS of its
-- nearest spot gets the seconds since the last count.
function ns.TimingSeen(list, now)
  now = now or Now()
  lastFeed = now
  local st = CharState()
  if not st or type(list) ~= "table" then return end
  local dt = now - lastCount
  lastCount = now
  if dt <= 0 or dt > 5 then return end -- the first second, or a gap (loading screen, list off for a while)
  if Busy() or Idle(now) then return end
  local level, n = ns.PlayerLevel and ns.PlayerLevel() or 0, 0
  for _, e in ipairs(list) do
    if e.questID and not e.complete and not e.failed and e.dist and e.dist <= AREA_YARDS then n = n + 1 end
  end
  if n == 0 then return end
  local group = GroupSize()
  for _, e in ipairs(list) do
    if e.questID and not e.complete and not e.failed and e.dist and e.dist <= AREA_YARDS then
      local q = st.q[e.questID]
      if not q then q = { s = 0, d = 0, g = 0, p = 0, l = level } st.q[e.questID] = q stats.quests = stats.quests + 1 end
      q.s, q.at = q.s + dt, now
      if n > q.p then q.p = n end
      if group > q.g then q.g = group end
    end
  end
  stats.seconds = stats.seconds + dt
end

-- Without the quest list (switched off or closed) the entries are asked for every TICK seconds.
local taxi -- { m, x, y, t } while on a flight
local function Tick()
  local now = Now()
  -- flights
  local onTaxi = UnitOnTaxi and ns.True(ns.Value(UnitOnTaxi, "player"))
  if onTaxi and not taxi then
    local m, x, y = ns.PlayerPosition()
    taxi = m and { m, x, y, now } or false
  elseif not onTaxi and taxi ~= nil then
    local t = taxi
    taxi = nil
    if t then
      local m, x, y = ns.PlayerPosition()
      local secs = math.floor(now - t[4] + 0.5)
      if m and secs >= 10 and secs <= 1800 then
        stats.flights = stats.flights + 1
        Emit(("J %d %.1f %.1f %d %.1f %.1f %d"):format(t[1], t[2] * 100, t[3] * 100, m, x * 100, y * 100, secs))
      end
    end
  end
  if now - lastFeed > TICK + 1 and ns.TrackerEntries then
    local list = ns.TrackerEntries()
    if now - lastFeed > TICK + 1 then ns.TimingSeen(list, now) end -- the list did not hand them in itself
  end
end

-- deaths in the area of a quest that is being counted right now
ns.On("PLAYER_DEAD", function()
  local st = CharState()
  if not st then return end
  local now = Now()
  if now - lastCount > 5 then return end
  for _, q in pairs(st.q) do if q.at and now - q.at <= 5 then q.d = (q.d or 0) + 1 end end
end)

---------------------------------------------------------------------------
-- Drop rates: corpses looted while a quest item is needed
---------------------------------------------------------------------------
local corpseSeen, corpseOrder = {}, {}
local function NeedsQuestItem()
  for _, info in ipairs(ns.QuestLogEntries and ns.QuestLogEntries() or {}) do
    local id = info.questID
    if id and not (ns.IsQuestComplete and ns.IsQuestComplete(id)) then
      for _, o in ipairs(ns.ClientObjectives and ns.ClientObjectives(id) or {}) do
        if type(o) == "table" and o.type == "item" and not ns.True(o.finished) then return true end
      end
    end
  end
  return false
end
ns.On("LOOT_READY", function()
  if not (GetNumLootItems and GetLootSourceInfo) then return end
  local st = CharState()
  if not st or not NeedsQuestItem() then return end
  local items = {} -- quest items of this loot: [itemID] = { [creature] = count }
  local corpses = {}
  for slot = 1, ns.Num(ns.Value(GetNumLootItems)) or 0 do
    local src = { pcall(GetLootSourceInfo, slot) }
    local itemID
    if GetLootSlotInfo then
      local ok, _, _, _, _, _, _, isQuestItem = pcall(GetLootSlotInfo, slot)
      if ok and ns.True(isQuestItem) then
        local link = ns.Value(GetLootSlotLink, slot)
        itemID = type(link) == "string" and ns.Usable(link) and tonumber(link:match("item:(%d+)")) or nil
      end
    end
    if src[1] then
      for i = 2, #src, 2 do
        local guid = src[i]
        local kind, id
        if ns.GUIDKindID then kind, id = ns.GUIDKindID(guid) end
        if kind == "c" and id and type(guid) == "string" then
          corpses[guid] = id
          if itemID then
            items[itemID] = items[itemID] or {}
            items[itemID][id] = (items[itemID][id] or 0) + (ns.Num(src[i + 1]) or 1)
          end
        end
      end
    end
  end
  for guid, id in pairs(corpses) do
    if not corpseSeen[guid] then
      corpseSeen[guid] = true
      corpseOrder[#corpseOrder + 1] = guid
      if #corpseOrder > MAX_CORPSES then corpseSeen[table.remove(corpseOrder, 1)] = nil end
      st.cor[id] = math.min((st.cor[id] or 0) + 1, 9999)
    end
  end
  for itemID, by in pairs(items) do
    local d = st.drop[itemID] or {}
    st.drop[itemID] = d
    for id, n in pairs(by) do d[id] = math.min((d[id] or 0) + n, 9999) end
  end
end)

-- The quest's item objectives (QuestData), for the L lines at its turn-in.
local function QuestItems(questID)
  return ns.QuestObjectiveItems and ns.QuestObjectiveItems(questID) or {}
end

---------------------------------------------------------------------------
-- Turn-in and abandon
---------------------------------------------------------------------------
function ns.TimingTurnedIn(questID, xp, money)
  questID = ns.Num(questID)
  local st = CharState()
  if not (questID and st) then return end
  local q = st.q[questID]
  st.q[questID] = nil
  if q and q.s >= 5 then
    Emit(("Q %d %d %d %d %d %d %d %d %d %d"):format(questID, q.l or 0, ClassID(), math.floor(q.s + 0.5), q.d or 0,
      q.g or 0, q.p or 1, LeveldonOn(), ns.Num(xp) or 0, ns.Num(money) or 0))
  end
  for _, itemID in ipairs(QuestItems(questID)) do
    local d = st.drop[itemID]
    if type(d) == "table" then
      for id, got in pairs(d) do
        local n = st.cor[id] or 0
        if n >= got and n > 0 then Emit(("L %d %d %d %d"):format(itemID, id, n, got)) end
        st.cor[id] = nil
      end
      st.drop[itemID] = nil
    end
  end
end
ns.On("QUEST_TURNED_IN", function(_, questID, xp, money) ns.TimingTurnedIn(questID, xp, money) end)

-- Journal.lua calls this when a quest left the log without a turn-in
function ns.TimingAbandoned(questID)
  questID = ns.Num(questID)
  local st = CharState()
  if not questID then return end
  if st then st.q[questID] = nil end
  Emit(("B %d %d"):format(questID, ns.PlayerLevel and ns.PlayerLevel() or 0))
end

function ns.TimingState() return CharState() end -- (tests, /qd diag)
ns.TimingTick = function() Tick() end -- (tests)
function ns.TimingDiag()
  local st = CharState()
  local n = 0
  for _ in pairs(st and st.q or {}) do n = n + 1 end
  return ("%d quests counting, %d s counted, %d lines made (%d flights), %d waiting to send, %d kept (%d received)"):format(
    n, math.floor(stats.seconds), stats.lines, stats.flights, #Account().sampleOut, ns.SampleCount(), stats.received)
end

ns.OnInit(function()
  ns.NewTicker(TICK, function() ns.SafeCall("timing", Tick) end)
end)
