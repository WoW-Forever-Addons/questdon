local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- (1.2.2) Quest journal: a personal diary per character. What it keeps:
-- accepted, completed (with XP and money), abandoned and failed quests and
-- level-ups, each with date, time, zone and player level. Quests completed
-- before the journal existed are taken over once from the game, without a
-- date ("done earlier").
--
-- Shown in the quest book window (QuestBook.lua) on the tabs "Journal" and
-- "Search". Search looks through the journal and through all quests of the
-- data (title, zone, level, quest ID).
--
-- Stored in QuestdonCharDB.journal = { v = 1, e = { entry, ... }, old = { [questID] = true }, seeded = true }
--   entry = { t = time, k = "a"|"c"|"x"|"f"|"l", q = questID, l = level, m = mapID, x = xp, g = copper, n = title }
---------------------------------------------------------------------------
local MAX_ENTRIES = 5000
local MAX_RESULTS = 40
local REMOVED_WAIT = 1.5   -- seconds before a quest gone from the log counts as abandoned

local KIND_TEXT = { a = "accepted", c = "completed", x = "abandoned", f = "failed" }
local KIND_COLOR = { a = "accent", c = "good", x = "textHint", f = "critical", l = "warning" }

local function Now() return ns.Num(ns.Value(time)) end

local function Store()
  local c = ns.charDB
  if type(c) ~= "table" then return nil end
  local j = c.journal
  if type(j) ~= "table" then j = { v = 1 } c.journal = j end
  if type(j.e) ~= "table" then j.e = {} end
  if type(j.old) ~= "table" then j.old = {} end
  return j
end
ns.JournalStore = Store

local function Title(v) return type(v) == "string" and ns.Usable(v) and v ~= "" and v or nil end

local function ZoneNow()
  local m = ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  if m and ns.MinimapZoneMap then m = ns.MinimapZoneMap(m) or m end
  return m
end

local function MapName(mapID)
  local info = mapID and ns.Value(C_Map.GetMapInfo, mapID)
  local name = type(info) == "table" and info.name
  if type(name) == "string" and ns.Usable(name) and name ~= "" then return name end
  return nil
end
ns.JournalMapName = MapName

local function Changed()
  if ns.UpdateZoneQuests then ns.UpdateZoneQuests() end
end

function ns.JournalAdd(kind, questID, extra)
  local j = Store()
  if not j then return end
  local e = { t = Now(), k = kind, q = questID, l = ns.PlayerLevel(), m = ZoneNow() }
  if type(extra) == "table" then for k, v in pairs(extra) do e[k] = v end end
  if questID and not e.n then e.n = Title(ns.Value(C_QuestLog.GetTitleForQuestID, questID)) end
  j.e[#j.e + 1] = e
  while #j.e > MAX_ENTRIES do table.remove(j.e, 1) end
  Changed()
  return e
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local turnedIn = {}   -- questID -> true while its removal from the log is pending
local tracked         -- { q = { [questID] = { n = title, f = failed } }, count = n }
local logTitles = {}  -- last known title of quests in the log (also secret-safe)

ns.On("QUEST_ACCEPTED", function(_, a, b)
  local id = ns.Num(b) or ns.Num(a)
  if not id or id <= 0 then return end
  ns.JournalAdd("a", id)
end)

ns.On("QUEST_TURNED_IN", function(_, questID, xp, money)
  local id = ns.Num(questID)
  if not id then return end
  turnedIn[id] = true
  local x, g = ns.Num(xp), ns.Num(money)
  ns.JournalAdd("c", id, { x = x and x > 0 and x or nil, g = g and g > 0 and g or nil, n = logTitles[id] })
end)

ns.On("PLAYER_LEVEL_UP", function(_, level)
  local lv = ns.Num(level)
  ns.JournalAdd("l", nil, { l = lv or ((ns.PlayerLevel() or 0) + 1) })
end)

local function Gone(id, old)
  ns.After(REMOVED_WAIT, function()
    if turnedIn[id] then turnedIn[id] = nil return end
    if ns.InQuestLog(id) then return end -- back in the log: a hiccup of the client
    if ns.IsQuestDone(id) then
      ns.JournalAdd("c", id, { n = old.n })
    else
      ns.JournalAdd("x", id, { n = old.n })
    end
  end)
end

local function ScanLog()
  local now, n = {}, 0
  for _, info in ipairs(ns.QuestLogEntries()) do
    local id = ns.Num(info.questID)
    if id and not ns.True(info.isTask) and not ns.True(info.isBounty) then
      local t = Title(info.title)
      if t then logTitles[id] = t end
      now[id] = { n = t or logTitles[id], f = ns.IsQuestFailed(id) or nil }
      n = n + 1
    end
  end
  if not tracked then
    tracked = { q = now, count = n }
    return
  end
  -- an empty log right after several quests: the client is still loading
  if n == 0 and tracked.count > 1 then return end
  for id, s in pairs(now) do
    local o = tracked.q[id]
    if o and s.f and not o.f then ns.JournalAdd("f", id, { n = s.n }) end
  end
  for id, o in pairs(tracked.q) do
    if not now[id] then Gone(id, o) end
  end
  tracked = { q = now, count = n }
end
ns.JournalScanLog = ScanLog

ns.RegisterRefresh("journal", ScanLog)
ns.On("QUEST_LOG_UPDATE", function() if tracked then ns.QueueRefresh("journal") end end)

-- Quests done before the journal: once per character, without a date.
local function Seed()
  local j = Store()
  if not j or j.seeded then return end
  local ids = ns.Value(C_QuestLog.GetAllCompletedQuestIDs)
  if type(ids) == "table" and #ids > 0 then
    for _, id in ipairs(ids) do
      id = ns.Num(id)
      if id then j.old[id] = true end
    end
  else
    for id in pairs(ns.ATT_QUESTS or {}) do
      if ns.IsQuestDone(id) then j.old[id] = true end
    end
  end
  j.seeded = true
end

ns.On("PLAYER_ENTERING_WORLD", function()
  ns.After(3, function()
    Seed()
    -- fresh baseline after every loading screen: what changed meanwhile is not
    -- something the player did (the log can arrive in pieces)
    tracked = nil
    ScanLog()
  end)
end)

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local WEEKDAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December" }

local function DateTable(t) local d = t and ns.Value(date, "*t", t) return type(d) == "table" and d or nil end
local function DayKey(t) local d = DateTable(t) return d and (d.year * 1000 + d.yday) or 0 end

local function DayTitle(t)
  local d = DateTable(t)
  if not d then return L["Unknown date"] end
  local today = DayKey(Now())
  local wd = L[WEEKDAYS[d.wday] or "?"]
  if DayKey(t) == today then wd = L["Today"] elseif DayKey(t + 86400) == today then wd = L["Yesterday"] end
  -- the order of the parts is the language's ("{wd}, {mon} {d}, {y}")
  local s = L["{wd}, {mon} {d}, {y}"]
  s = s:gsub("{wd}", wd):gsub("{mon}", L[MONTHS[d.month] or "?"]):gsub("{d}", tostring(d.day)):gsub("{y}", tostring(d.year))
  return s
end

local function Clock(t) return t and ns.Value(date, "%H:%M", t) or "--:--" end

local function Span(sec)
  sec = ns.Num(sec)
  if not sec or sec < 0 then return nil end
  if sec < 3600 then return L["%d min"]:format(math.max(1, math.floor(sec / 60 + 0.5))) end
  if sec < 48 * 3600 then return L["%d:%02d h"]:format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
  return L["%d days"]:format(math.floor(sec / 86400))
end

local function Money(copper)
  copper = ns.Num(copper)
  if not copper or copper <= 0 then return nil end
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  if g > 0 then return ("%dg %ds"):format(g, s) end
  if s > 0 then return ("%ds %dc"):format(s, c) end
  return ("%dc"):format(c)
end

local function EntryTitle(e)
  if e.k == "l" then return L["Reached level %d"]:format(e.l or 0) end
  return e.n or ns.QuestTitle(e.q)
end

---------------------------------------------------------------------------
-- Entries for the window: newest first, level-ups know the time since the last one
---------------------------------------------------------------------------
function ns.JournalEntries()
  local j = Store()
  if not j then return {} end
  local out, prevLevel = {}, nil
  for i = 1, #j.e do
    local e = j.e[i]
    if type(e) == "table" and e.k then
      local copy = {}
      for k, v in pairs(e) do copy[k] = v end
      if e.k == "l" then
        if prevLevel and e.t and prevLevel.t then copy.since = e.t - prevLevel.t end
        prevLevel = e
      end
      out[#out + 1] = copy
    end
  end
  -- newest first (stable for equal times: later entries first)
  local n = #out
  for i = 1, math.floor(n / 2) do out[i], out[n - i + 1] = out[n - i + 1], out[i] end
  return out
end

local function OldDone()
  local j = Store()
  local list = {}
  if not j then return list end
  local logged = {}
  for _, e in ipairs(j.e) do if e.k == "c" and e.q then logged[e.q] = true end end
  for id in pairs(j.old) do
    if not logged[id] then list[#list + 1] = { q = id, level = ns.QuestLevel(id) or 0, title = ns.QuestTitle(id) } end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.title ~= b.title then return tostring(a.title) < tostring(b.title) end
    return a.q < b.q
  end)
  return list
end

function ns.JournalCounts()
  local j = Store()
  local c = { a = 0, c = 0, x = 0, f = 0, l = 0, old = 0 }
  if not j then return c end
  for _, e in ipairs(j.e) do if c[e.k] then c[e.k] = c[e.k] + 1 end end
  for _ in pairs(j.old) do c.old = c.old + 1 end
  return c
end

local function EntryTooltip(e)
  return function()
    local lines = {}
    if e.t then lines[#lines + 1] = { L["Date"], DayTitle(e.t) .. "  " .. Clock(e.t) } end
    if e.k ~= "l" then lines[#lines + 1] = { L["Event"], L[KIND_TEXT[e.k] or "done earlier"], KIND_COLOR[e.k] or "textHint" } end
    local zone = MapName(e.m)
    if zone then lines[#lines + 1] = { L["Zone"], zone } end
    if e.l and e.k ~= "l" then lines[#lines + 1] = { L["Your level"], tostring(e.l) } end
    if e.x then lines[#lines + 1] = { L["Experience"], "+" .. Style.Number(e.x), "warning" } end
    local money = Money(e.g)
    if money then lines[#lines + 1] = { L["Money"], money } end
    if e.since then lines[#lines + 1] = { L["Since the last level"], Span(e.since) or "?" } end
    if e.q then
      local status, text, color = ns.ZoneQuestStatus(e.q)
      if status then lines[#lines + 1] = { L["Status"], text, color } end
      return EntryTitle(e), lines, L["Click: arrow and mark on the map. Shift-click: also open the map."]
    end
    return EntryTitle(e), lines
  end
end

---------------------------------------------------------------------------
-- Search: journal entries and quests of the data whose title, zone,
-- level ("12") or ID match. Returns the journal hits and the quests.
---------------------------------------------------------------------------
local clientTitle = {} -- questID -> title the client already knows (no requests)

local function Norm(s) return tostring(s or ""):lower() end

local function Matches(q, ...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v and Norm(v):find(q, 1, true) then return true end
  end
  return false
end

local function KnownTitle(id)
  local t = clientTitle[id]
  if t == nil then
    t = Title(ns.Value(C_QuestLog.GetTitleForQuestID, id)) or false
    clientTitle[id] = t
  end
  return t or nil
end

local mapNames = {}
local function CachedMapName(m)
  if not m then return nil end
  local n = mapNames[m]
  if n == nil then n = MapName(m) or false mapNames[m] = n end
  return n or nil
end

-- a new search session: titles the client learned since then count too
function ns.JournalSearchReset() clientTitle = {} end

function ns.JournalSearch(text)
  local q = Norm(text):gsub("^%s+", ""):gsub("%s+$", "")
  local hits, quests = {}, {}
  if q == "" then return hits, quests end
  local num = tonumber(q)
  local seen = {}
  for _, e in ipairs(ns.JournalEntries()) do
    if #hits >= MAX_RESULTS then break end
    local zone = MapName(e.m)
    if Matches(q, EntryTitle(e), zone) or (num and (e.q == num or (e.k == "l" and e.l == num))) then
      hits[#hits + 1] = e
      if e.q then seen[e.q] = true end
    end
  end
  for id, row in pairs(ns.ATT_QUESTS or {}) do
    if not seen[id] and type(row) == "table" then
      local m = ns.Num(row[1])
      local ok
      if num then
        ok = id == num or ns.QuestLevel(id) == num
      else
        ok = Matches(q, ns.DataQuestName(id), KnownTitle(id), CachedMapName(m))
      end
      if ok and ns.QuestReachable(id) and not (ns.QuestKnownMissing and ns.QuestKnownMissing(id)) then
        quests[#quests + 1] = { q = id, level = ns.QuestLevel(id) or 0, title = KnownTitle(id) or ns.DataQuestName(id) or ("Quest " .. id), m = m }
      end
    end
  end
  table.sort(quests, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.title ~= b.title then return tostring(a.title) < tostring(b.title) end
    return a.q < b.q
  end)
  return hits, quests
end

---------------------------------------------------------------------------
-- (1.3) For the quest book window (QuestBook.lua): formatting and lists
---------------------------------------------------------------------------
ns.JournalFmt = {
  DayTitle = DayTitle, DayKey = DayKey, Clock = Clock, Span = Span, Money = Money,
  EntryTitle = EntryTitle, EntryTooltip = EntryTooltip, OldDone = OldDone, Now = Now,
  KIND_TEXT = KIND_TEXT, KIND_COLOR = KIND_COLOR,
}
