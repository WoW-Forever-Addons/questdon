local _, ns = ...
local C_QuestLog = ns.QL or C_QuestLog -- (25.10.2026) Era shims, Core.lua ApiProxy
local C_SuperTrack = ns.ST or C_SuperTrack -- (25.10.2026) Era shims, Core.lua ApiProxy
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
--   (Stufe 3) pc = the character's played clock then, pt = the group at a turn-in (Chronicle.lua)
---------------------------------------------------------------------------
local MAX_ENTRIES = 5000
local MAX_RESULTS = 40
local REMOVED_WAIT = 1.5   -- seconds before a quest gone from the log counts as abandoned

local KIND_TEXT = { a = "accepted", c = "completed", x = "abandoned", f = "failed",
  -- (1.3.11) moments
  s = "screenshot", d = "death", i = "dungeon", z = "new zone", r = "loot", h = "home", p = "profession", u = "reputation" }
local KIND_COLOR = { a = "accent", c = "good", x = "textHint", f = "critical", l = "warning",
  s = "accent", d = "critical", i = "warning", z = "good", r = "goldLight", h = "textSecondary", p = "good", u = "goldLight" }

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
  if ns.JournalStamp then ns.JournalStamp(e, j) end -- (Stufe 3) played clock, group at a turn-in
  j.e[#j.e + 1] = e
  while #j.e > MAX_ENTRIES do table.remove(j.e, 1) end
  Changed()
  return e
end

-- (1.3.12, Tagebuch 3.3) The story of a completed quest: the text the quest giver showed when it was turned in.
-- Tracker.lua keeps it in db.questTexts[questID].c (all characters, for the reader), so the entry stores no copy;
-- the card shows it shortened (STORY_MAX letters, cut at a word, never inside a letter). Option journalStory.
local STORY_MAX = 420
ns.JOURNAL_STORY_MAX = STORY_MAX

local function Clip(s, max)
  if #s <= max then return s end
  local cut = s:sub(1, max)
  local word = cut:match("^(.+) %S*$")
  if word and #word >= max / 2 then
    cut = word
  else
    local j = #cut
    while j > 0 and cut:byte(j) >= 0x80 and cut:byte(j) < 0xC0 do j = j - 1 end
    local lead = cut:byte(j)
    if lead and lead >= 0xC0 then
      local len = lead >= 0xF0 and 4 or (lead >= 0xE0 and 3 or 2)
      if j + len - 1 > #cut then cut = cut:sub(1, j - 1) end
    end
  end
  return (cut:gsub("[%s,;:]+$", "")) .. "..."
end

function ns.JournalStory(e)
  if type(e) ~= "table" or e.k ~= "c" or not e.q then return nil end
  if type(ns.db) ~= "table" or ns.db.journalStory == false then return nil end
  local t = type(ns.db.questTexts) == "table" and ns.db.questTexts[e.q]
  local s = type(t) == "table" and t.c
  if type(s) ~= "string" or s == "" or not ns.Usable(s) then return nil end
  s = (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
  if s == "" then return nil end
  return Clip(s, STORY_MAX)
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
      if ns.TimingAbandoned then ns.TimingAbandoned(id) end -- (18.10.) shared as B (Timing.lua)
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
-- (1.3.11, Daniel 23.10.) Moments: screenshots and milestones of the
-- character, written from events only (no ticker). TAGEBUCH_PLAN.md.
--   s screenshot (auto = "l": Questdon took it at a level-up)
--   d death (tg: the enemy you had targeted)
--   i dungeon visit (iid, d = seconds inside, b = bosses beaten)
--   z first time in a zone   h new home (hearthstone)
--   r loot of rare quality or better (it = item ID, iq = quality)
--   p profession step 75/150/225/300 (sp = spell, rk = rank)
--   u new reputation standing (st = standing, fa = faction)
-- Fields of all: px, py (position on pm, or on m when pm is missing),
-- z subzone, tg target, rq picked quest, pt group, note (the player's own).
-- Not x and g: those are XP and money of turned-in quests.
---------------------------------------------------------------------------
local MOMENT = { s = true, d = true, i = true, z = true, r = true, h = true, p = true, u = true }
ns.JOURNAL_MOMENT = MOMENT
local NOTE_LETTERS, NOTE_BYTES = 200, 800
local RUN_GAP = 900      -- back in the same dungeon within 15 minutes: the same visit
local AUTO_SHOT_WAIT = 10 -- a screenshot this soon after Questdon asked for one is the level-up picture
local PROF_STEP = { [75] = true, [150] = true, [225] = true, [300] = true }

local function MomentsOn() return not (type(ns.db) == "table" and ns.db.journalMoments == false) end
local function ShotsOn() return not (type(ns.db) == "table" and ns.db.journalShots == false) end

local function Round(v) v = ns.Num(v) return v and math.floor(v * 10000 + 0.5) / 10000 or nil end

-- where the player stands, as fields of a new entry
local function Here(extra)
  extra = extra or {}
  local zone = ZoneNow()
  local pm, x, y = ns.PlayerPosition()
  x, y = Round(x), Round(y)
  if pm and x and y then
    extra.px, extra.py = x, y
    if pm ~= zone then extra.pm = pm end
  end
  local sub = Title(ns.Value(GetSubZoneText))
  if sub and sub ~= MapName(zone) then extra.z = sub end
  return extra
end

local function TargetName()
  if not ns.True(ns.Value(UnitExists, "target")) then return nil end
  return Title(ns.Value(UnitName, "target"))
end

local function GroupNames()
  local n = ns.Num(ns.Value(GetNumGroupMembers)) or 0
  if n <= 1 then return nil end
  local raid = ns.True(ns.Value(IsInRaid))
  local names = {}
  for i = 1, math.min(raid and n or (n - 1), 40) do -- party1..4 are the others; raid1..40 include you
    local unit = (raid and "raid" or "party") .. i
    local name = Title(ns.Value(UnitName, unit))
    if name and not ns.True(ns.Value(UnitIsUnit, unit, "player")) then names[#names + 1] = name end
    if #names >= 4 then break end
  end
  return #names > 0 and table.concat(names, ", ") or nil
end
ns.JournalGroupNames = GroupNames

local function PickedQuest()
  local id = C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  if id and id > 0 and ns.InQuestLog(id) then return id end
  return nil
end

-- "You are now %s with %s." and the like as a pattern: the captures by argument number.
-- Kept per global string; a different text of the global (another language) makes a new one.
local patterns = {}
local function Parse(global, msg)
  local fmt = _G[global]
  if type(fmt) ~= "string" or not ns.Usable(fmt) then return nil end
  local p = patterns[global]
  if not p or p.fmt ~= fmt then
    local pat, args
    if ns.FormatPattern then pat, args = ns.FormatPattern(fmt) end -- (not "a and f()": that keeps one value)
    p = { fmt = fmt, pat = pat, args = args }
    patterns[global] = p
  end
  if not (p.pat and p.args) then return nil end
  local c1, c2, c3, c4 = msg:match(p.pat) -- no table for the many lines that do not match
  if c1 == nil then return nil end
  local caps, out = { c1, c2, c3, c4 }, {}
  for i, a in ipairs(p.args) do out[a] = caps[i] end
  return out
end
ns.JournalParse, ns.JournalPatterns = Parse, patterns -- (tests)

local function Digits(s)
  if type(s) ~= "string" then return ns.Num(s) end
  return tonumber((s:gsub("[^%d]", "")))
end

-- the newest entry of a kind within a few seconds (one message on two channels)
local function Recent(kind, secs, same)
  local j = Store()
  local now = Now()
  if not (j and now) then return nil end
  for i = #j.e, math.max(1, #j.e - 5), -1 do
    local e = j.e[i]
    if e.k == kind and e.t and now - e.t <= secs and (not same or same(e)) then return e end
  end
  return nil
end

-- Screenshots (and one at each level-up when the player wants it)
local autoShotAt
ns.On("SCREENSHOT_SUCCEEDED", function()
  if not ShotsOn() then return end
  local now = Now()
  local extra = Here({ tg = TargetName(), rq = PickedQuest(), pt = GroupNames() })
  if autoShotAt and now and now - autoShotAt <= AUTO_SHOT_WAIT then extra.auto = "l" end
  if ns.PostcardCapture then ns.PostcardCapture(extra) end -- (1.3.12) gear, target, hour for the postcard
  autoShotAt = nil
  ns.JournalAdd("s", nil, extra)
end)

ns.On("PLAYER_LEVEL_UP", function()
  if not (type(ns.db) == "table" and ns.db.journalLevelShot == true) then return end
  ns.After(1, function()
    if type(Screenshot) ~= "function" then return end
    autoShotAt = Now()
    pcall(Screenshot)
  end)
end)

ns.On("PLAYER_DEAD", function()
  if not MomentsOn() then return end
  local tg = ns.True(ns.Value(UnitCanAttack, "player", "target")) and TargetName() or nil
  ns.JournalAdd("d", nil, Here({ tg = tg }))
end)

-- Dungeon visits: one entry from entering to leaving. j.run = { t, iid, out }
-- names the open visit by its time (SavedVariables would copy a shared table).
local function InstanceNow()
  if type(IsInInstance) ~= "function" then return nil end
  local ok, inside, kind = pcall(IsInInstance)
  if not ok or not ns.Usable(inside) or not ns.Usable(kind) then return nil end
  if not inside or (kind ~= "party" and kind ~= "raid") then return false end
  local ok2, name, _, _, _, _, _, _, iid = pcall(GetInstanceInfo)
  if not ok2 then return nil end
  return Title(name) or "?", ns.Num(iid)
end

local function OpenRun(j)
  local r = j.run
  if type(r) ~= "table" then return nil end
  for i = #j.e, math.max(1, #j.e - 500), -1 do
    local e = j.e[i]
    if e.k == "i" and e.t == r.t then return e end
  end
  j.run = nil
  return nil
end

local function CloseRun(j, e)
  local r = j.run
  if e and r and e.t then e.d = math.max(0, (r.out or Now() or e.t) - e.t) end
  j.run = nil
end

local function CheckInstance()
  local j = Store()
  if not j then return end
  local name, iid = InstanceNow()
  if name == nil then return end -- the client does not say: next time
  local now = Now() or 0
  local e = OpenRun(j)
  local r = j.run
  if name then
    if e and r.iid == iid and e.n == name and (not r.out or now - r.out <= RUN_GAP) then r.out = nil return end
    if e then CloseRun(j, e) end
    if not MomentsOn() then return end
    local ne = ns.JournalAdd("i", nil, { n = name, iid = iid, pt = GroupNames() })
    if ne and ne.t then j.run = { t = ne.t, iid = iid } end
  elseif e then
    if not r.out then r.out = now end
    if now - r.out > RUN_GAP then CloseRun(j, e) Changed() end
  end
end
ns.JournalCheckInstance = CheckInstance -- (tests)
-- (25.10., review round 8) logging out inside a dungeon: the visit ends there unless you are back within RUN_GAP (a quick
-- relog); before, the offline hours counted as time inside
ns.On("PLAYER_LOGOUT", function()
  local j = Store()
  local r = j and j.run
  if type(r) == "table" and not r.out then r.out = Now() end
end)

-- (tests and the window) is this dungeon visit still going on?
function ns.JournalRunOpen(e)
  local j = Store()
  local r = j and j.run
  return type(e) == "table" and e.k == "i" and type(r) == "table" and r.t == e.t and not r.out
end

ns.On("ENCOUNTER_END", function(_, _, name, _, _, success)
  if not (ns.Num(success) == 1 or ns.True(success)) then return end
  local j = Store()
  local e = j and OpenRun(j)
  name = Title(name)
  if not (e and name) then return end
  e.b = type(e.b) == "table" and e.b or {}
  for _, b in ipairs(e.b) do if b == name then return end end
  if #e.b < 20 then e.b[#e.b + 1] = name Changed() end
end)

-- First time in a zone. j.zv = { [zone map] = true }. Its first run marks
-- what the character knows: the zones of its journal and the one it is in.
-- After that a new zone counts when the map shows at most one explored part
-- (the one you just found); a zone without any explored part (a city) only
-- for a character that started with this (j.zvFresh).
local function ExploredParts(m)
  local list = C_MapExplorationInfo and ns.Value(C_MapExplorationInfo.GetExploredMapTextures, m)
  return type(list) == "table" and #list or 0
end

local function CheckZone()
  local j = Store()
  if not j then return end
  local m = ZoneNow()
  if type(j.zv) ~= "table" then
    j.zv = {}
    for _, e in ipairs(j.e) do
      local z = e.m and ns.MinimapZoneMap and ns.MinimapZoneMap(e.m) or e.m
      if z then j.zv[z] = true end
    end
    local level = ns.PlayerLevel()
    local old = 0
    for _ in pairs(j.old) do old = old + 1 break end
    j.zvFresh = level ~= nil and level <= 1 and old == 0 and #j.e == 0 or nil
    if m then j.zv[m] = true end
    return
  end
  if not m or j.zv[m] or InstanceNow() ~= false then return end
  if ns.IsZoneMap and not ns.IsZoneMap(m) then return end
  local parts = ExploredParts(m)
  j.zv[m] = true
  if parts >= 2 or (parts == 0 and not j.zvFresh) or not MomentsOn() then return end
  ns.JournalAdd("z", nil, Here({ n = MapName(m) }))
end
ns.JournalCheckZone = CheckZone -- (tests)

-- A new home: the bind location changed (a system message comes with it)
local function CheckHome(record)
  local j = Store()
  local home = Title(ns.Value(GetBindLocation))
  if not (j and home) or j.home == home then return end
  local had = j.home
  j.home = home
  if had and record and MomentsOn() then ns.JournalAdd("h", nil, Here({ n = home })) end
end

local function OnSystem(_, msg)
  if type(msg) ~= "string" or not ns.Usable(msg) then return end
  CheckHome(true)
  if not MomentsOn() then return end
  local v = Parse("FACTION_STANDING_CHANGED", msg)
  local st, fa = v and Title(v[1]), v and Title(v[2])
  if st and fa and not Recent("u", 5, function(e) return e.fa == fa and e.st == st end) then
    ns.JournalAdd("u", nil, { st = st, fa = fa })
  end
end
ns.On("CHAT_MSG_SYSTEM", OnSystem)
ns.On("CHAT_MSG_COMBAT_FACTION_CHANGE", OnSystem)
ns.On("CONFIRM_BINDER", function()
  ns.After(3, function() CheckHome(true) end)
  ns.After(8, function() CheckHome(true) end)
end)

-- Loot of rare quality or better: only the player's own lines ("You receive ...")
local LOOT_SELF = { "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
  "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE" }
local LINK_QUALITY = { ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6 }

local function ItemQuality(id, msg)
  local q = C_Item and C_Item.GetItemQualityByID and ns.Num(ns.Value(C_Item.GetItemQualityByID, id))
  if not q then
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, _, _, quality = pcall(get, id)
    if ok and ns.Usable(quality) then q = ns.Num(quality) end
  end
  if not q then
    q = ns.Num(msg:match("|cnIQ(%d):"))
    if not q then
      local hex = msg:match("|c%x%x(%x%x%x%x%x%x)|Hitem:")
      q = hex and LINK_QUALITY[hex:lower()] or nil
    end
  end
  return q
end

ns.On("CHAT_MSG_LOOT", function(_, msg)
  if type(msg) ~= "string" or not ns.Usable(msg) or not MomentsOn() then return end
  local id = ns.Num(tonumber(msg:match("|Hitem:(%d+)") or ""))
  if not id then return end
  local mine
  for _, g in ipairs(LOOT_SELF) do if Parse(g, msg) then mine = true break end end
  if not mine then return end
  local q = ItemQuality(id, msg)
  if not q or q < 3 then return end
  local name = Title(msg:match("|h%[(.-)%]|h"))
  ns.JournalAdd("r", nil, Here({ it = id, iq = q, n = name }))
end)

-- Profession steps: "Your skill in %s has increased to %d."
ns.On("CHAT_MSG_SKILL", function(_, msg)
  if type(msg) ~= "string" or not ns.Usable(msg) or not MomentsOn() then return end
  local v = Parse("SKILL_RANK_UP", msg)
  local name, rank = v and Title(v[1]), v and Digits(v[2])
  if not (name and rank and PROF_STEP[rank]) then return end
  local sp = ns.ProfessionSpell and ns.ProfessionSpell(name)
  if not sp then return end -- a weapon skill
  ns.JournalAdd("p", nil, { n = name, rk = rank, sp = sp })
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  ns.After(3, function()
    CheckHome(false)
    CheckInstance()
    CheckZone()
  end)
end)
ns.On("ZONE_CHANGED_NEW_AREA", function()
  CheckInstance()
  ns.After(3, CheckZone) -- the part you enter is explored by then
end)

-- The player's own note on an entry (also quests): at most 200 letters
function ns.JournalSetNote(e, text)
  if type(e) ~= "table" then return nil end
  e = type(e.src) == "table" and e.src or e
  text = type(text) == "string" and ns.Usable(text) and text or ""
  text = text:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if #text > NOTE_BYTES then text = text:sub(1, NOTE_BYTES):gsub("[\192-\255][\128-\191]*$", "") end
  e.note = text ~= "" and text or nil
  return e.note
end
ns.JOURNAL_NOTE_LETTERS = NOTE_LETTERS

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
  -- (Questdon review 1) the game's coins, not English g/s/c in every language; above a gold without the copper
  if copper >= 10000 then copper = copper - copper % 100 end
  return ns.Money(copper)
end

local function EntryTitle(e)
  local k = e.k
  if k == "l" then return L["Reached level %d"]:format(e.l or 0) end
  if k == "s" then return L["Screenshot"] end
  if k == "d" then return L["You died"] end
  if k == "i" then return e.n or L["Dungeon"] end
  if k == "z" then return L["First time in %s"]:format(MapName(e.m) or e.n or "?") end
  if k == "r" then return e.n or ns.Value(C_Item and C_Item.GetItemNameByID, e.it) or ("#" .. tostring(e.it)) end
  if k == "h" then return L["New home: %s"]:format(e.n or "?") end
  if k == "p" then return L["%s: skill %d"]:format(e.n or "?", e.rk or 0) end
  if k == "u" then return L["%s with %s"]:format(e.st or "?", e.fa or "?") end
  return e.n or ns.QuestTitle(e.q)
end

-- (1.3.4) Did this character turn the quest in while Questdon recorded? (cached per journal size)
local turnedInSet, turnedInN
function ns.JournalTurnedIn(questID)
  local j = Store()
  if not (j and questID) then return false end
  if turnedInN ~= #j.e then
    turnedInSet, turnedInN = {}, #j.e
    for i = 1, #j.e do
      local e = j.e[i]
      if type(e) == "table" and e.k == "c" and e.q then turnedInSet[e.q] = true end
    end
  end
  return turnedInSet[questID] == true
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
      local copy = { src = e } -- (1.3.11) the stored entry, for notes
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
  local c = { a = 0, c = 0, x = 0, f = 0, l = 0, old = 0, m = 0 }
  if not j then return c end
  for _, e in ipairs(j.e) do
    if c[e.k] then c[e.k] = c[e.k] + 1 elseif MOMENT[e.k] then c.m = c.m + 1 end
  end
  for _ in pairs(j.old) do c.old = c.old + 1 end
  return c
end

-- (1.3.11) what a moment knows besides date, zone and level, as { label, text, color } lines
local function MomentLines(e, lines)
  if e.z then lines[#lines + 1] = { L["Place"], e.z } end
  if e.k == "i" then
    local open = ns.JournalRunOpen(e)
    local now = Now()
    local d = open and e.t and now and (now - e.t) or e.d
    if d then lines[#lines + 1] = { L["Time inside"], (Span(d) or "?") .. (open and ("  " .. L["(still inside)"]) or "") } end
    if type(e.b) == "table" and #e.b > 0 then lines[#lines + 1] = { L["Bosses"], table.concat(e.b, ", "), "goldLight" } end
  end
  if e.tg then lines[#lines + 1] = { e.k == "d" and L["Enemy"] or L["Target"], e.tg } end
  if e.rq then lines[#lines + 1] = { L["Quest"], ns.QuestTitle(e.rq) or ("#" .. tostring(e.rq)) } end
  if e.pt then lines[#lines + 1] = { L["Group"], e.pt } end
  if e.auto == "l" then lines[#lines + 1] = { L["Taken"], L["at the level-up"], "warning" } end
  return lines
end

local function EntryTooltip(e)
  return function()
    local lines = {}
    if e.t then lines[#lines + 1] = { L["Date"], DayTitle(e.t) .. "  " .. Clock(e.t) } end
    if e.k ~= "l" then lines[#lines + 1] = { L["Event"], L[KIND_TEXT[e.k] or "done earlier"], KIND_COLOR[e.k] or "textHint" } end
    local zone = MapName(e.m)
    if zone then lines[#lines + 1] = { L["Zone"], zone } end
    if e.l and e.k ~= "l" then lines[#lines + 1] = { L["Your level"], tostring(e.l) } end
    if MOMENT[e.k] then MomentLines(e, lines) elseif e.pt then lines[#lines + 1] = { L["Group"], e.pt } end
    if e.note then lines[#lines + 1] = { L["Note"], e.note, "goldLight" } end
    if e.x then lines[#lines + 1] = { L["Experience"], "+" .. Style.Number(e.x), "warning" } end
    local money = Money(e.g)
    if money then lines[#lines + 1] = { L["Money"], money } end
    if e.since then lines[#lines + 1] = { L["Since the last level"], Span(e.since) or "?" } end
    if e.q then
      local status, text, color = ns.ZoneQuestStatus(e.q)
      if status then lines[#lines + 1] = { L["Status"], text, color } end
      if e.k == "o" then return EntryTitle(e), lines, L["Click: details. Shift-click: also the arrow and the world map."] end
      return EntryTitle(e), lines, L["Click: details. Shift-click: also the arrow and the world map. Right-click: your note."]
    end
    if MOMENT[e.k] then return EntryTitle(e), lines, L["Click: details and your note. Shift-click: arrow and world map."] end
    if e.k == "l" then return EntryTitle(e), lines, L["Right-click: your note."] end
    return EntryTitle(e), lines
  end
end

---------------------------------------------------------------------------
-- Search: journal entries and quests of the data whose title, zone,
-- level ("12") or ID match. Returns the journal hits and the quests.
---------------------------------------------------------------------------
local clientTitle = {} -- questID -> title the client already knows (no requests)

local function Norm(s) return ns.FoldCase(s) end -- (review 5) "ärger" finds "Ärger", "кобольды" "Кобольды"

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
    if Matches(q, EntryTitle(e), zone, e.note, e.z, e.tg, e.n, e.pt) or (num and (e.q == num or (e.k == "l" and e.l == num))) then
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
        quests[#quests + 1] = { q = id, level = ns.QuestLevel(id) or 0, title = KnownTitle(id) or ns.DataQuestName(id) or L["Quest %d"]:format(id), m = m }
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
  KIND_TEXT = KIND_TEXT, KIND_COLOR = KIND_COLOR, MomentLines = MomentLines, MOMENT = MOMENT, MapName = MapName,
}
