local addonName, ns = ...
local L = ns.L

-- (25.10.2026, Classic Era) the game's API tables behind a proxy: on Era (Classic.lua) a missing function comes
-- from ns.EraShims, otherwise the game's own table, looked up at each access. Files take `local C_QuestLog = ns.QL
-- or C_QuestLog`. On Forever there are no shims and every field is the game's.
local function ApiProxy(name)
  local shims = ns.EraShims and ns.EraShims[name]
  return setmetatable({}, { __index = function(_, k)
    local s = shims and shims[k]
    if s ~= nil then return s end
    local t = _G[name]
    if type(t) == "table" then return t[k] end
    return nil
  end })
end
ns.QL, ns.ST, ns.TT = ApiProxy("C_QuestLog"), ApiProxy("C_SuperTrack"), ApiProxy("C_TooltipInfo")
local C_QuestLog = ns.QL

ns.defaults = {
  autoAccept = true,
  autoTurnIn = true,
  skipTrivial = true,
  highlightBest = true,
  autoPickBest = false,
  suggestReward = true, -- (1.3.8) a green frame on the reward players of your class pick (or the class rule)
  sellJunk = true,
  autoRepair = true,
  useGuildRepair = false,
  fastLoot = true,
  questItemButton = true,
  starterNotice = true, -- (1.3.5) a small note above the button when a looted item starts a quest
  -- 1.27: target button (macro of mob names, learned), waypoint export (both off)
  targetButton = false,
  targetButtonPos = nil,
  mobNames = {}, -- [creatureID] = name, learned from nameplates and target
  exportBlizzardWaypoint = false,
  exportTomTom = false,
  buttonPos = nil, -- { point, relPoint, x, y }
  -- 1.1
  notifySound = true,
  journalShots = true, -- (1.3.11, Daniel 23.10.) every screenshot an entry in the journal
  journalMoments = true, -- (1.3.11) deaths, dungeons, new zones, loot, home, professions, reputation
  journalStory = true, -- (1.3.12) the turn-in text (db.questTexts[id].c), shortened, in the card of a completed quest's entry
  journalLevelShot = false, -- (1.3.11) a screenshot at each level-up
  notifyText = true,
  learnQuests = true,
  learnPins = true,
  pinsOnlyUnknown = true,
  shareQuests = false,
  questieFirst = false, -- (1.3.6, Daniel 12.10.: "we no longer need to give Questie priority")
  -- 1.2
  availablePins = true,
  objectivePins = true,
  showLowLevel = false,
  chainHint = true,
  -- 1.3
  -- (1.3.6, Daniel 12.10.) own quest list instead of Blizzard's tracker, with the arrow built in as a compass
  tracker = true,
  trackerShown = true,
  trackerCompass = true,
  trackerDock = true, -- (1.3.6) under Leveldon's window when both are open
  trackerHideBlizz = true,
  trackerMode = "near",
  trackerSortLevel = false,
  trackerAlpha = 0.82,
  trackerPlain = true, -- (17.10.) no background and frame; (18.10., Daniel) on for new players, a switch in the start window
  trackerHideGrey = false, -- (1.3.7) grey quests folded into one line at the bottom of the quest list
  trackerScale = 1.2, -- (Daniel 12.10.: "the writing looks very small") text size 120 %, Ctrl + mouse wheel changes it
  trackerCombatFade = true,
  questTexts = {}, -- (1.3.6) [questID] = { d, o, p, c }: the game's quest texts, kept when a quest giver shows them
  arrow = true,
  arrowNext = true, -- (1.3.5) nothing tracked: the arrow moves on to the next turn-in or an objective close by
  arrowCorpse = true, -- (1.2) as a ghost the arrow leads to your corpse
  pathDots = true, -- (1.3.6) the arrow's way around a mountain or into a cave as dots on the map and minimap
  arrowPos = nil,
  -- 1.4
  arrowScale = 1.15,
  objectivePinSize = 12,
  thinObjectives = true, -- (1.3.5) many objective dots: fewer, bundled markers (minimap and world map)
  objectiveIcons = true, -- (17.10.) symbols instead of dots (mob, loot, named mob, object, place, item), groups as one
  objectiveAreas = true, -- (17.10.) the area of a group of spots in the quest's colour (world map)
  walkLines = true, -- (17.10.) routes of walking quest NPCs as red dots (Walks.lua)
  hideGamePOIs = false, -- (17.10.) the game's own quest markers and areas off the world map
  panelScale = 1,
  panelAlpha = 0.82, -- 1.19: family default (was 0.75)
  panelWidth = 300, -- 1.15.1: wider for German texts, adjustable
  itemButtonScale = 1,
  -- 1.5
  xpBar = true,
  xpBarWidth = 600,
  xpBarHeight = 14,
  xpBarScale = 1.45,
  xpBarText = true,
  xpBarLocked = false,
  xpBarPos = nil,
  unitTooltips = true,
  objectivePinsTrackedOnly = false,
  nextQuestHint = false, -- (1.0) off: the game shows ! on map and minimap itself
  guessedItems = {}, -- (1.0) [itemID] = { questID } guessed from items that appeared after accepting a quest
  learnedItems = {}, -- (1.0) [itemID] = questID that handed the item out (Cleanup.lua)
  npcSpots = {}, -- (1.3.6) [creatureID] = { { map, x, y }, ... } where you talked to a quest NPC (Learn.lua: walks around)
  learnedObj = {}, -- [questID] = { [objectiveIndex] = { map,x,y, ... } }
  learnedCredit = {}, -- (1.0.1) [questID] = { [index] = { c|o|i = { [id] = n } } } what gave objective credit (Learn.lua)
  learnedDrops = {}, -- (1.0.1) [itemID] = { ["c123"] = { n, map, x, y } } where a quest item dropped
  learnedItemStarts = {}, -- (1.0.1) [itemID] = questID started by a looted item
  notHere = {}, -- (1.1) [questID] = { lv, man, ok, npc }: quests a quest giver never offers (NotHere.lua)
  shareLearned = true,
  shareChannel = true, -- (1.1) also through the open channel QuestdonNet (all Questdon players) -- (1.0.1) send own learned data to guild and group (Exchange.lua)
  shared = {}, -- (1.0.1) what other players reported: [key] = { v = { variants }, c, t }
  shareSent = {}, -- (1.0.1) [key] = what was last sent
  showPanel = false, -- (1.3.4) off for new players: the minimap button shows what the window did
  minimapButton = true, -- (1.3.4) minimap button: quest book, menu, info tooltip
  minimapButtonAngle = 200,
  bookButton = true, -- (1.3) quest book button at the bottom of the window
  panelPos = nil,
  learned = {}, -- [questID] = { title, level, faction, start = {...}, finish = {...} }
  -- 1.13: [questID] = false for quests the server does not know (Exists.lua)
  questExists = {},
  -- 1.18
  dungeonQuests = true, -- panel row "Dungeon quests"
  dungeonHint = true,   -- chat line when entering a dungeon
  partyProgress = true, -- quest progress with group members (addon messages)
  -- 1.19: one appearance page (Style kit) for panel, arrow and XP bar
  panelLocked = false,
  panelCollapsed = false,
  panelCombatFade = false,
  arrowLocked = false,
  arrowAlpha = 0.82,
  arrowPlain = true, -- (25.10.) no plate and frame behind the arrow's text; (25.10., Daniel) the default, like the list
  arrowCombatFade = false,
  xpBarAlpha = 0.82,
  xpBarCombatFade = false,
  hideBlizzardXP = true, -- (1.3.2) game's own XP bar hidden while ours is shown
  artInXPPlace = true, -- (1.3.2) an ornament strip in the action bar style fills the free place
  ownRepBar = true, -- (1.3.2) a tracked faction is shown in Questdon's own (clickable) reputation bar
  -- 1.21
  minimapPins = true, -- the map pins of the current zone on the minimap too
  shareTimes = true, -- (18.10.) play times of quests, drop rates, flights and abandons measured and shared (Timing.lua)
  -- 1.22
  nameplateIcons = true, -- pins above the nameplates of quest mobs (1.3.6: no more ! and ? over NPCs)
  lowLevelRange = 10,    -- a quest is low level this many levels below yours (was fixed)
  -- 1.24: quests without a level in the data on the map/minimap/nameplates/panel
  -- even when neither the client nor a quest giver confirmed them (replaces
  -- "noLevelIsLow", see the migration in ADDON_LOADED)
  showNoLevel = false,
  -- 1.0: event quests (Darkmoon Faire, Lunar Festival, ...) have quest givers that
  -- are only there while the event runs. Hidden until the game or the quest giver
  -- confirms them; off shows them like any other quest.
  hideEventQuests = true,
  -- 1.3.5: repeatable quests are always available, so their ! would stay on the map for good
  hideRepeatable = true,
  -- 1.0: only quests the game itself confirmed (its quest lines or the quest
  -- giver's own offer) on the map, minimap, nameplates and panel
  confirmedOnly = false,
  -- 1.0: only confirmed quests count for the nearest quest line and /qd next
  nextConfirmedOnly = true, -- (1.0) the data alone is not enough for "go there"
  -- 1.25: quest givers the game itself marks with ! (its quest lines list the
  -- quest with a spot) get no second ! from Questdon on the map and minimap
  skipGameGivers = true,
  clusterPins = false, -- (1.28) merge close available pins on the world map
  upcomingLevels = 0,    -- map pins: also quests of the next 0-5 levels, dimmed
  -- 1.3.5: the entrance of every dungeon with a known entrance: world map; minimap only within 300 yards
  dungeonPins = true,
  dungeonPinsMinimap = true,
}

---------------------------------------------------------------------------
-- Error guard: every event handler, timer callback and a few UI callbacks run
-- protected. A failing module does not stop the others; the first distinct
-- errors are kept (file, line, message, short stack, no names) for /qd diag,
-- and one chat line per session says that something went wrong.
---------------------------------------------------------------------------
local MAX_ERRORS, MAX_MSG = 10, 160
local errors, warned = {}, false

-- Interface/AddOns/Questdon/Learn.lua:12: msg -> Learn.lua:12: msg
local function Shorten(msg)
  msg = tostring(msg or "?"):gsub("\\", "/")
  msg = msg:gsub("[^%s:]*/([%w_]+%.[lx][um][al])", "%1")
  if #msg > MAX_MSG then msg = msg:sub(1, MAX_MSG) .. "..." end
  return msg
end

local function ShortStack()
  if not debugstack then return nil end
  local ok, stack = pcall(debugstack, 3, 4, 0)
  if not ok or type(stack) ~= "string" then return nil end
  local lines = {}
  for line in stack:gmatch("[^\n]+") do
    line = Shorten(line)
    if not line:find("Core.lua", 1, true) and #lines < 3 then lines[#lines + 1] = line end
  end
  return #lines > 0 and table.concat(lines, " < ") or nil
end

local function Record(context, err, noStack)
  local ok, msg = pcall(Shorten, err)
  if not ok then msg = "(unreadable error)" end
  for _, e in ipairs(errors) do
    if e.msg == msg and e.context == context then e.count = e.count + 1 return end
  end
  if #errors < MAX_ERRORS then
    errors[#errors + 1] = {
      module = msg:match("([%w_]+)%.lua[\"%]]*:%d+") or "?",
      context = context, msg = msg, count = 1, stack = not noStack and ShortStack() or nil,
    }
  end
  if not warned then
    warned = true
    print("|cff3fa9f5Questdon|r: " .. L["an error occurred, /qd diag for details"])
  end
end

function ns.Errors() return errors end

-- (1.20) Errors caught elsewhere (the Style kit's Style.onError): same log,
-- same one-time chat line. The stack at this point would only show the kit.
function ns.RecordError(context, err)
  pcall(Record, context, err, true)
end

---------------------------------------------------------------------------
-- (1.23) Read cache for one unit of work. Every protected call (event
-- handler, timer, guarded UI callback) is one scope; the outermost one opens
-- it. Inside a scope the quest log list, the per-quest states (done, in log,
-- complete, objectives) and the player's static data are read from the client
-- once and reused. Nothing is kept beyond the scope, so a later event always
-- sees fresh data. Calls outside any scope (tests, other addons through the
-- API) read the client directly as before.
---------------------------------------------------------------------------
local scopeDepth, scopeGen = 0, 0
local memo, memoGen = {}, {} -- [kind][id] = value / generation (old generations are simply ignored)

-- Cached value of kind for a numeric id (quest ID, map ID) within the
-- current scope, else read(id, extra).
function ns.Memo(kind, id, read, extra)
  if scopeDepth == 0 or type(id) ~= "number" or not ns.Usable(id) then return read(id, extra) end
  local gens = memoGen[kind]
  if not gens then gens = {} memoGen[kind], memo[kind] = gens, {} end
  if gens[id] == scopeGen then return memo[kind][id] end
  local v = read(id, extra)
  memo[kind][id], gens[id] = v, scopeGen
  return v
end
-- One value per scope (quest log list, player): fn() once, then the same value.
local scopeValues, scopeValueGen = {}, {}
function ns.ScopeValue(key, fn)
  if scopeDepth == 0 then return fn() end
  if scopeValueGen[key] == scopeGen then return scopeValues[key] end
  local v = fn()
  scopeValues[key], scopeValueGen[key] = v, scopeGen
  return v
end
function ns.InScope() return scopeDepth > 0 end
-- (16.10. evening, /qd mem) The quest log changes only with its events: what is read from it (the list with
-- C_QuestLog.GetInfo, a new table of about twenty fields per entry, and each quest's objectives) is kept from one
-- quest log event to the next instead of one scope (the quest list, the compass, the item button and the arrow
-- read it every second, each in its own scope). Outside a scope (tests, other addons) it is read directly as before.
local logGen = 0
function ns.LogGen() return logGen end
function ns.InScope() return scopeDepth > 0 end -- (24.10.) inside a protected call (event, timer, UI part)
function ns.ForgetQuestLog() logGen = logGen + 1 end
local logValues, logValueGen = {}, {}
-- (tests) QD_TEST_FRESH_LOG: the test harness changes its quest log without the game's events
function ns.LogValue(key, fn)
  if scopeDepth == 0 or QD_TEST_FRESH_LOG then return fn() end
  if logValueGen[key] == logGen then return logValues[key] end
  local v = fn()
  logValues[key], logValueGen[key] = v, logGen
  return v
end
local logMemo, logMemoGen = {}, {}
function ns.LogMemo(kind, id, read)
  if scopeDepth == 0 or QD_TEST_FRESH_LOG or type(id) ~= "number" or not ns.Usable(id) then return read(id) end
  local gens = logMemoGen[kind]
  if not gens then gens = {} logMemoGen[kind], logMemo[kind] = gens, {} end
  if gens[id] == logGen then return logMemo[kind][id] end
  local v = read(id)
  logMemo[kind][id], gens[id] = v, logGen
  return v
end
-- (23.10., /qd mem) the log's state as two plain numbers: which quests, which are complete or failed, which objectives
-- are done (h), and how many quests (n). A quest log event without such a change (most kills and loots) leaves both as they
-- were, so what depends only on them is not worked out again (Walks.lua, Cleanup.lua). Once per log event in a scope.
local stateGen, stateH, stateN = nil, 0, 0
local NO_OBJECTIVES = {}
function ns.QuestLogState()
  local cached = scopeDepth > 0 and not QD_TEST_FRESH_LOG
  if cached and stateGen == logGen then return stateH, stateN end
  local h, n = 0, 0
  for _, info in ipairs(ns.QuestLogEntries()) do
    local q = ns.Num(info.questID)
    if q then
      n = n + 1
      local mask = (ns.IsQuestComplete(q) and 1 or 0) + (ns.IsQuestFailed and ns.IsQuestFailed(q) and 2 ^ 21 or 0)
      for i, o in ipairs(ns.ClientObjectives and ns.ClientObjectives(q) or NO_OBJECTIVES) do
        if i > 20 then break end
        if type(o) == "table" and ns.True(o.finished) then mask = mask + 2 ^ i end
      end
      h = (h * 31 + q * 3 + mask) % 4294967291
    end
  end
  if cached then stateGen = logGen end
  stateH, stateN = h, n
  return h, n
end
local scopeStats = { scopes = 0 }
function ns.ScopeStats() return scopeStats end

-- Runs fn(...) protected. context: event name, "timer" or a UI part.
-- (1.23) No closure or argument table per call: one error handler reads the
-- context of the innermost call (it runs before the stack unwinds); WoW's
-- xpcall passes arguments on, plain Lua 5.1 gets a closure only when needed.
local currentContext
local function OnError(err)
  pcall(Record, currentContext, err)
  return err
end
local XPCALL_ARGS = select(2, xpcall(function(v) return v end, OnError, true)) == true
local function Finish(outer, opened, ok, a, b, c)
  currentContext = outer
  if opened then scopeDepth = 0 end
  if ok then return a, b, c end
end
-- (16.10. evening, Daniel's /qd mem: Questdon about 1 MB of new memory a second, Questie 6 KB) While /qd mem
-- measures, every protected call counts the Lua memory it took (collectgarbage("count") before and after; the
-- game runs one thing at a time). Calls inside another one count again under their own name (inner).
local memProf -- { top = {}, inner = {} } while measuring
local RawSafeCall
local function Measure(prof, context, opened, kb, a, b, c)
  local d = collectgarbage("count") - kb
  local key = opened and context or (context .. " (inner)")
  prof.calls[key] = (prof.calls[key] or 0) + 1 -- (18.10.) how often, so few big calls and many small ones differ
  if d > 0 then
    local t = opened and prof.top or prof.inner
    t[context] = (t[context] or 0) + d
  end
  return a, b, c
end
-- (16.10. late, Daniel's /qd mem: 408 KB a second standing, the named parts only about 100) other addons call
-- Questdon's API from their own frames (Leveldon's window and its route fitting): those calls are Questdon's
-- memory too, outside any protected call. While measuring, every QuestdonAPI function counts its own.
local apiSaved
local function MeasureAPI(prof, name, kb, ...)
  local d = collectgarbage("count") - kb
  local key = scopeDepth == 0 and name or (name .. " (inner)")
  prof.calls[key] = (prof.calls[key] or 0) + 1
  if d > 0 then
    local t = scopeDepth == 0 and prof.top or prof.inner
    t[name] = (t[name] or 0) + d
  end
  return ...
end
local function WrapAPI(prof)
  local api = rawget(_G, "QuestdonAPI")
  if type(api) ~= "table" or apiSaved then return end
  apiSaved = {}
  for k, f in pairs(api) do
    if type(f) == "function" then
      apiSaved[k] = f
      local name = "API " .. tostring(k)
      api[k] = function(...) return MeasureAPI(prof, name, collectgarbage("count"), f(...)) end
    end
  end
end
local function UnwrapAPI()
  local api = rawget(_G, "QuestdonAPI")
  if type(api) == "table" and apiSaved then
    for k, f in pairs(apiSaved) do api[k] = f end
  end
  apiSaved = nil
end
function ns.MemProfile(on)
  if on then
    memProf = { top = {}, inner = {}, calls = {} }
    WrapAPI(memProf)
    return memProf
  end
  UnwrapAPI()
  local was = memProf
  memProf = nil
  return was
end
-- "Arrow.lua:123" of the code that called the caller (for timers and event listeners)
-- (review 7) the first place outside Core.lua: debugstack counts the pcall around it as a level too, so the fixed
-- level landed on ns.After / ns.NewTicker / ns.On themselves and every part was named "Core.lua:..."
local function Where(level)
  if not debugstack then return "?" end
  local ok, stack = pcall(debugstack, level, 6, 0)
  if not ok or type(stack) ~= "string" then return "?" end
  stack = stack:gsub("\\", "/")
  -- (23.10., Leveldon's /lvd mem) the game writes [Interface/AddOns/Questdon/Arrow.lua]:123: in function <...:100>:
  -- with the bracket after ".lua" allowed the calling line is found, not the start of the function around it
  local first
  for file, line in stack:gmatch('([%w_]+%.lua)["%]]*:(%d+)') do
    local at = file .. ":" .. line
    if file ~= "Core.lua" then return at end
    first = first or at
  end
  return first or "?"
end
ns.CodeWhere = Where

-- (18.10., Daniel's /qd mem: the quest list's ticker 29 KB a second) a part inside a bigger one, measured only while
-- /qd mem runs (inner, with its calls); otherwise just called. Up to three results.
function ns.MemPart(label, fn, ...)
  if not memProf then return fn(...) end
  return Measure(memProf, label, false, collectgarbage("count"), fn(...))
end
function ns.MemProfiling() return memProf ~= nil end -- (23.10.) a part that names its caller only while /qd mem runs
function ns.MemCount(label)
  if memProf then memProf.calls[label .. " (inner)"] = (memProf.calls[label .. " (inner)"] or 0) + 1 memProf.inner[label] = memProf.inner[label] or 0 end
end
function ns.SafeCall(context, fn, ...)
  if memProf then
    return Measure(memProf, context, scopeDepth == 0, collectgarbage("count"), RawSafeCall(context, fn, ...))
  end
  return RawSafeCall(context, fn, ...)
end
function RawSafeCall(context, fn, ...)
  local outer = currentContext
  currentContext = context
  local opened = scopeDepth == 0
  if opened then
    scopeDepth, scopeGen = 1, scopeGen + 1
    scopeStats.scopes = scopeStats.scopes + 1
  end
  local n = select("#", ...)
  if n == 0 then return Finish(outer, opened, xpcall(fn, OnError)) end
  if XPCALL_ARGS then return Finish(outer, opened, xpcall(fn, OnError, ...)) end
  local args = { ... }
  return Finish(outer, opened, xpcall(function() return fn(unpack(args, 1, n)) end, OnError))
end

-- (17.10., Daniel's /qd mem: "API ObjectivePoints" 160 KB a second standing) Another addon's call (Leveldon asks
-- several times a second) ran outside any scope: the quest log, each quest's objectives and state were read anew
-- for every call. QuestdonAPI functions run in a scope of their own (unprotected for the caller: an error is raised
-- on as before).
local function CloseScope(ok, ...)
  scopeDepth = 0
  if not ok then error((...), 0) end
  return ...
end
function ns.ScopeCall(fn, ...)
  if scopeDepth > 0 then return fn(...) end
  scopeDepth, scopeGen = 1, scopeGen + 1
  scopeStats.scopes = scopeStats.scopes + 1
  return CloseScope(pcall(fn, ...))
end

-- A protected copy of fn for timers and script handlers.
function ns.Guard(context, fn)
  return function(...) return ns.SafeCall(context, fn, ...) end
end

---------------------------------------------------------------------------
-- (1.23) One batched refresh after quest events. Map pins, minimap pins,
-- nameplate icons, panel, XP bar and arrow target used to start their own
-- timers on every QUEST_LOG_UPDATE and each read the quest log again. Now
-- they register a part, events mark the parts, and one timer runs all marked
-- parts in one scope (each part protected on its own), so the quest log,
-- the quest states and the pins of the player's map are read once.
---------------------------------------------------------------------------
local REFRESH_DELAY = 0.5
local parts, partOrder, partContext, pendingParts = {}, {}, {}, {}
local flushQueued, runGuarded = false, nil
local refreshStats = { flushes = 0, parts = 0 }
function ns.RefreshStats() return refreshStats end

function ns.RegisterRefresh(name, fn)
  if not parts[name] then partOrder[#partOrder + 1] = name end
  parts[name], partContext[name] = fn, "refresh " .. name
end

local function RunParts()
  flushQueued = false
  refreshStats.flushes = refreshStats.flushes + 1
  for _, name in ipairs(partOrder) do
    if pendingParts[name] then
      pendingParts[name] = nil
      refreshStats.parts = refreshStats.parts + 1
      ns.SafeCall(partContext[name], parts[name])
    end
  end
end

-- Marks parts ("map", "minimap", ...) for the next batched refresh.
function ns.QueueRefresh(a, b, c, d)
  if a then pendingParts[a] = true end
  if b then pendingParts[b] = true end
  if c then pendingParts[c] = true end
  if d then pendingParts[d] = true end
  if not flushQueued then
    flushQueued = true
    if C_Timer and C_Timer.After then
      runGuarded = runGuarded or ns.Guard("timer", RunParts)
      -- (16.10., stutter report) in a fight (kills and loot update the log again and again) once a second at most
      C_Timer.After((InCombatLockdown and InCombatLockdown()) and 1 or REFRESH_DELAY, runGuarded)
    else
      ns.SafeCall("timer", RunParts)
    end
  end
end

function ns.After(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, ns.Guard(memProf and "timer " .. Where(3) or "timer", fn)) end
end

-- (16.10.) a ticker says where it was made (made rarely; /qd mem names it)
function ns.NewTicker(interval, fn, iterations)
  if C_Timer and C_Timer.NewTicker then return C_Timer.NewTicker(interval, ns.Guard("ticker " .. Where(3), fn), iterations) end
end

-- Event dispatcher: several modules may listen to the same event.
local frame = CreateFrame("Frame")
local listeners, initCallbacks = {}, {}
local listenerWhere = {}

function ns.On(event, fn)
  if not listeners[event] then
    listeners[event] = {}
    -- Unknown events throw in the modern client, so register defensively.
    local ok = pcall(frame.RegisterEvent, frame, event)
    -- (25.10.2026) events Questdon fires itself on Era (ns.SYNTH_EVENTS, Classic.lua) keep their listeners
    if not ok and not (ns.SYNTH_EVENTS and ns.SYNTH_EVENTS[event]) then listeners[event] = nil return false end
  end
  table.insert(listeners[event], fn)
  listenerWhere[fn] = listenerWhere[fn] or Where(3) -- (16.10.) for /qd mem: which module's listener
  return true
end

function ns.OnInit(fn) table.insert(initCallbacks, fn) end

-- (25.10.2026) call the listeners of an event the client does not send (Era: SUPER_TRACKING_CHANGED)
function ns.Fire(event, ...)
  local list = listeners[event]
  if not list then return end
  for i = 1, #list do ns.SafeCall(event, list[i], event, ...) end
end

-- (16.10.) the quest log read anew after each of its events (the first listener of each, before any reader)
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED",
    "QUEST_AUTOCOMPLETE", "QUEST_WATCH_LIST_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do
  ns.On(e, ns.ForgetQuestLog)
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= addonName then return end
    if QuestdonDB == nil and type(QuestKompassDB) == "table" then QuestdonDB = QuestKompassDB end -- data from QuestKompass
    QuestKompassDB = nil
    QuestdonDB = QuestdonDB or {}
    for k, v in pairs(ns.defaults) do
      if QuestdonDB[k] == nil then
        QuestdonDB[k] = type(v) == "table" and {} or v
      end
    end
    ns.db = QuestdonDB
    -- (1.24) "Quests without a level count as low level" is replaced by "Show
    -- quests without a level on the map" (default off). Both values of the
    -- old option end up hiding unconfirmed quests without a level by default.
    QuestdonDB.noLevelIsLow = nil
    -- (1.0) "Nearest quest" is off by default now and only uses confirmed quests
    -- nearby: it sent players far away to quests the data knew but the game
    -- did not offer, while the game's own ! were closer.
    if not QuestdonDB.nextHintV10 then
      QuestdonDB.nextQuestHint, QuestdonDB.nextConfirmedOnly, QuestdonDB.nextHintV10 = false, true, true
    end
    -- (1.3.6, Daniel 12.10.: "we are at the stage where Questie no longer needs priority") off once for everybody;
    -- who wants it back switches it on again (page "Questie")
    if not QuestdonDB.questieV136 then
      QuestdonDB.questieFirst, QuestdonDB.questieV136 = false, true
    end
    -- (1.3.7, Daniel 13.10.: "by default the compass in the list and the arrow off") once: with the list and its
    -- compass on, the separate arrow window goes off (switch it on again for both at once)
    -- (1.3.8, Daniel 13.10.: "the old window can go completely") its lines are at the bottom of the quest list now
    if not QuestdonDB.panelV138 then
      QuestdonDB.showPanel, QuestdonDB.panelV138 = false, true
    end
    if not QuestdonDB.arrowV137 then
      -- (Questdon review 5) not when the list was closed: then the arrow is the only way shown
      if QuestdonDB.tracker ~= false and QuestdonDB.trackerCompass ~= false and QuestdonDB.trackerShown ~= false then QuestdonDB.arrow = false end
      QuestdonDB.arrowV137 = true
    end
    -- (1.3.11, Daniel 25.10.: "no background and no frame shall be the default for Questdon and Leveldon, also with the
    -- arrow") once for everybody: the quest list and the arrow see-through; who wants the frame switches it on again
    if not QuestdonDB.plainV1311 then
      QuestdonDB.trackerPlain, QuestdonDB.arrowPlain, QuestdonDB.plainV1311 = true, true, true
    end
    -- (1.24) per character: what quest givers offered (Offers.lua)
    if type(QuestdonCharDB) ~= "table" then QuestdonCharDB = {} end
    ns.charDB = QuestdonCharDB
    -- (Questdon review 5) once with 1.3.8: list, compass and arrow agree (a closed list or a compass off: the arrow);
    -- later an arrow switched off by hand stays off
    if ns.SyncArrowData and not QuestdonDB.arrowSyncV138 then
      ns.SafeCall("arrow sync", ns.SyncArrowData, QuestdonDB)
      QuestdonDB.arrowSyncV138 = true
    end
    for _, fn in ipairs(initCallbacks) do ns.SafeCall("init", fn) end
    frame:UnregisterEvent("ADDON_LOADED")
    return
  end
  if not ns.db then return end
  local list = listeners[event]
  if list then
    if memProf then
      for i = 1, #list do ns.SafeCall(event .. " " .. (listenerWhere[list[i]] or "?"), list[i], event, ...) end
    else
      for i = 1, #list do ns.SafeCall(event, list[i], event, ...) end
    end
  end
end)

-- Helpers
function ns.Print(msg)
  print("|cff3fa9f5Questdon|r: " .. msg)
end

-- Holding Shift pauses all automation.
function ns.IsPaused()
  return IsShiftKeyDown()
end

function ns.Money(copper)
  if GetMoneyString then return GetMoneyString(copper, true) end
  if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
    return C_CurrencyInfo.GetCoinTextureString(copper)
  end
  return tostring(copper)
end

-- C_Item.GetItemInfo returns legacy multi-values; 11th is the vendor price.
function ns.GetSellPrice(item)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return nil end
  local name, _, _, _, _, _, _, _, _, _, price = getInfo(item)
  if not name then return nil end -- not cached yet
  return ns.Num(price) or 0
end

function ns.GetItemInfo(item)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if fn then return fn(item) end
end

function ns.GetItemID(item)
  local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  return getInstant and getInstant(item) or nil
end

function ns.RequestItem(itemID)
  if itemID and C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(itemID)
  end
end

-- Quest log entries (no headers, no hidden quests). (1.23) Read once per
-- scope (see ns.SafeCall); callers only read the list.
-- (Questdon review 5) A heading collapsed in Blizzard's quest log hides its quests from the log's index: the quest
-- left Questdon's list, its dots and arrow went and its "!" came back. The quests last seen are kept (with their zone)
-- as long as the game says you are on them.
local lastSeen = {} -- [questID] = { info = , zone = }
local function OnQuest(questID)
  return C_QuestLog.IsOnQuest ~= nil and ns.True(ns.Value(C_QuestLog.IsOnQuest, questID))
end
local function ReadQuestLog()
  local list = {}
  if not C_QuestLog then return list end
  local here, zone = {}, nil
  for i = 1, ns.Num(ns.Value(C_QuestLog.GetNumQuestLogEntries)) or 0 do
    local info = ns.Value(C_QuestLog.GetInfo, i)
    if type(info) == "table" and ns.True(info.isHeader) then
      zone = type(info.title) == "string" and ns.Usable(info.title) and info.title or zone
    -- secret flags count as "not a header / not hidden" only if the quest ID is readable
    elseif type(info) == "table" and not ns.True(info.isHidden) and (ns.Num(info.questID) or 0) > 0 then
      list[#list + 1] = info
      here[info.questID] = true
      local e = lastSeen[info.questID]
      if e then e.info, e.zone, e.index = info, zone, i else lastSeen[info.questID] = { info = info, zone = zone, index = i } end
    end
  end
  local kept
  for id, e in pairs(lastSeen) do
    if not here[id] then
      if OnQuest(id) then kept = kept or {} kept[#kept + 1] = id e.index = nil else lastSeen[id] = nil end
    end
  end
  if kept then
    table.sort(kept)
    for _, id in ipairs(kept) do list[#list + 1] = lastSeen[id].info end
  end
  return list
end
-- the zone heading a quest was last seen under (Tracker.lua, for quests under a collapsed heading)
function ns.QuestLogZone(questID) local e = lastSeen[questID] return e and e.zone or nil end
-- (23.10.) its row in the game's log at the last read (nil under a collapsed heading); the quest list read the whole
-- log a second time for zone and row (a new table of about twenty fields per row, at every quest log event)
function ns.QuestLogIndex(questID) local e = lastSeen[questID] return e and e.index or nil end
function ns.InCollapsedHeading(questID)
  return lastSeen[questID] ~= nil and (ns.Num(ns.Value(C_QuestLog.GetLogIndexForQuestID, questID)) or 0) <= 0
end
function ns.QuestLogEntries()
  return ns.LogValue("questLog", ReadQuestLog)
end

-- Quest log full? (false if the client cannot tell). Counts only quests that
-- take a slot: no headers, hidden quests, bonus objectives or bounties.
function ns.QuestLogFull()
  local n, max = ns.QuestLogCount()
  if not max then return false end
  return n >= max
end

-- (1.16) Quests taking a log slot and the client's limit (nil if unknown).
function ns.QuestLogCount()
  local max = ns.Num(ns.Value(C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept))
  if max and max <= 0 then max = nil end
  local n = 0
  for _, info in ipairs(ns.QuestLogEntries()) do
    if not ns.True(info.isTask) and not ns.True(info.isBounty) then n = n + 1 end
  end
  return n, max
end

-- Secret values and missing APIs: these helpers never error.
-- Number or nil (nil if missing, not a number or secret).
function ns.Num(v)
  if type(v) == "number" and ns.Usable(v) then return v end
  return nil
end

-- true only for a readable true (secret booleans count as unknown).
function ns.True(v)
  return v ~= nil and ns.Usable(v) and v == true
end

-- First result of fn(...) if fn exists, did not error and the value is readable.
function ns.Value(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok and v ~= nil and ns.Usable(v) then return v end
  return nil
end

local function ReadComplete(questID) return ns.True(ns.Value(C_QuestLog.IsComplete, questID)) end
function ns.IsQuestComplete(questID)
  return ns.Memo("complete", questID, ReadComplete)
end

-- (Questdon review 1) seconds left of a timed quest in the log (the game's own tracker, which shows it, is
-- hidden behind the quest list), nil when the quest has no timer
function ns.QuestTimeLeft(questID)
  if not (C_QuestLog and C_QuestLog.GetTimeAllowed) or not ns.Num(questID) then return nil end
  local ok, total, elapsed = pcall(C_QuestLog.GetTimeAllowed, questID)
  total, elapsed = ok and ns.Num(total), ok and ns.Num(elapsed)
  if total and elapsed and total > 0 then return math.max(0, math.floor(total - elapsed)) end
  return nil
end

-- Failed (escort died, timer ran out): the objectives no longer count.
function ns.IsQuestFailed(questID)
  return ns.True(ns.Value(C_QuestLog.IsFailed, questID))
end

-- (Questdon review 5) Lower case beyond A-Z for the searches (lower() folds only ASCII): Latin-1 letters (À-Þ but
-- not ×), Cyrillic А-Я and Ё. Korean and Chinese have no case.
function ns.FoldCase(s)
  s = tostring(s or ""):lower()
  s = s:gsub("\195([\128-\158])", function(b)
    local n = b:byte()
    if n == 151 then return nil end -- ×
    return "\195" .. string.char(n + 32)
  end)
  s = s:gsub("\208([\144-\175])", function(b)
    local n = b:byte()
    if n <= 159 then return "\208" .. string.char(n + 32) end -- А-П -> а-п
    return "\209" .. string.char(n - 32) -- Р-Я -> р-я
  end)
  s = s:gsub("\208\129", "\209\145") -- Ё -> ё
  s = s:gsub("\209\145", "\208\181") -- (review 6) ё -> е: most players type е
  return s
end

function ns.AddOnLoaded(name)
  local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local v = ns.Value(fn, name)
  return v ~= nil and v ~= false
end

function ns.Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local v = ns.Value(get, addonName, "Version")
  v = type(v) == "string" and v:gsub("%s", "") or ""
  return v ~= "" and v or "?"
end

-- Own handler for OnLeave scripts (no Blizzard helper functions).
function ns.HideTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

function ns.Warn(msg)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
  else
    ns.Print(msg)
  end
end

-- Secret values (Midnight rules) must never reach comparisons.
function ns.Usable(v)
  if v == nil then return false end
  if canaccessvalue then return canaccessvalue(v) end
  if issecretvalue then return not issecretvalue(v) end
  return true
end

-- (16.10., Daniel's undead export) a zone, dungeon or smaller map (Enum.UIMapType 3 and up). Right after a /reload or
-- a loading screen the game names the continent as the player's map for a moment: places on it are not places of
-- the zone (66 objective spots of the exports were on Eastern Kingdoms). Unknown maps count as zones.
local mapKind = {}
function ns.IsZoneMap(mapID)
  mapID = ns.Num(mapID)
  if not mapID or mapID <= 0 then return false end
  local k = mapKind[mapID]
  if k == nil then
    local info = C_Map and C_Map.GetMapInfo and ns.Value(C_Map.GetMapInfo, mapID)
    local t = type(info) == "table" and ns.Num(info.mapType) or nil
    k = not t or t >= 3
    if info ~= nil then mapKind[mapID] = k end
  end
  return k
end

local function MapRead(mapID)
  local pos = ns.Value(C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) ~= "table" or not pos.GetXY then return nil end
  local ok, x, y = pcall(pos.GetXY, pos)
  if not ok or not (ns.Num(x) and ns.Num(y)) or (x == 0 and y == 0) then return nil end
  return x, y
end
-- (16.10. evening, Daniel's /qd mem: about 1 MB of new memory a second) C_Map.GetPlayerMapPosition makes a new
-- vector (a table with all of Vector2DMixin's functions) at each call, and the arrow, the compass, the minimap and the
-- quest list ask about a hundred times a second. UnitPosition answers with plain numbers: the world position,
-- turned into the map position with the map's corners (Arrow.lua). Checked against the map's own answer on each new
-- map and every 20 seconds (which of its two numbers is north is checked too); one mismatch and it is not used again.
local unitPos = { state = nil, order = nil, map = nil, at = -100 } -- state: nil unknown, true fine, false off
local UNITPOS_TOLERANCE = 0.002 -- map units (2 to 8 yards on a zone map)
local function FromUnitPosition(mapID)
  if unitPos.state == false or type(UnitPosition) ~= "function" or not ns.MapFromWorld then return nil end
  local ok, a, b, _, inst = pcall(UnitPosition, "player")
  a, b, inst = ok and ns.Num(a), ok and ns.Num(b), ok and ns.Num(inst)
  if not (a and b and inst) then return nil end -- instances, secret values: the map's answer
  local now = ns.Num(ns.Value(GetTime)) or 0
  if unitPos.state and unitPos.map == mapID and now - unitPos.at < 20 and now >= unitPos.at then
    if unitPos.order == 1 then return ns.MapFromWorld(mapID, inst, a, b) end
    return ns.MapFromWorld(mapID, inst, b, a)
  end
  -- check against the map's answer
  local mx, my = MapRead(mapID)
  if not mx then return nil end
  local x1, y1 = ns.MapFromWorld(mapID, inst, a, b)
  local x2, y2 = ns.MapFromWorld(mapID, inst, b, a)
  local fit1 = x1 and math.abs(x1 - mx) < UNITPOS_TOLERANCE and math.abs(y1 - my) < UNITPOS_TOLERANCE
  local fit2 = x2 and math.abs(x2 - mx) < UNITPOS_TOLERANCE and math.abs(y2 - my) < UNITPOS_TOLERANCE
  if not x1 and not x2 then return mx, my end -- the map's corners not known yet: ask again next time
  -- (review 7) where both world numbers are about equal (a line across every continent) both orders fit: that says
  -- nothing about the order. Not learned there (it took order 1 and mirrored the position as soon as the player
  -- walked on), and a known order is not switched off there; asked again at the next call.
  if fit1 and fit2 then
    if unitPos.state and unitPos.order then unitPos.map, unitPos.at = mapID, now end
    return mx, my
  end
  local order = fit1 and 1 or fit2 and 2 or nil
  if not order or (unitPos.order and order ~= unitPos.order) then
    unitPos.state = false -- does not fit this client: the map's answer from now on
    return mx, my
  end
  unitPos.state, unitPos.order, unitPos.map, unitPos.at = true, order, mapID, now
  return mx, my
end
function ns.UnitPositionState() return unitPos.state, unitPos.order end -- (diag, tests)
function ns.ResetUnitPosition() unitPos.state, unitPos.order, unitPos.map, unitPos.at = nil, nil, nil, -100 end -- (tests)

function ns.PlayerPosition()
  if not C_Map then return nil end
  local mapID = ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  if not mapID then return nil end
  local x, y = FromUnitPosition(mapID)
  if not x then x, y = MapRead(mapID) end
  if not x then return nil end
  return mapID, x, y
end

-- Player level as a plain number (nil while the client hides it).
function ns.PlayerLevel()
  return ns.Num(ns.Value(UnitLevel, "player"))
end

-- Addon compartment (minimap addon menu)
function Questdon_OnAddonCompartmentClick()
  if ns.OpenOptions then ns.OpenOptions() end
end

SLASH_QUESTDON1 = "/qd"
SLASH_QUESTDON2 = "/questdon"
ns.HELP = L["Commands: /qd (options), /qd list (quest list), /qd arrow, /qd xpbar, /qd next, /qd xp, /qd dungeons, /qd zone (quests of the zone), /qd journal (quest journal), /qd search [text], /qd group, /qd questie, /qd export, /qd diag (diagnostics), /qd missing (nonexistent quests), /qd xpcheck (XP sources), /qd nettest (channel test), /qd nothere (targeted NPC has no quest: hide it; undo, list), /qd why [quest ID] (why no !), /qd reset (reset button position)"]
SlashCmdList.QUESTDON = ns.Guard("slash", function(msg)
  local raw = strtrim and strtrim(msg or "") or (msg or "")
  msg = raw:lower()
  -- (1.3.5, Daniel 10.10.) /qd search <text>: the search with that text
  local text = raw:match("^[Ss][Uu][Cc][Hh][Ee]%s+(.+)$") or raw:match("^[Ss][Ee][Aa][Rr][Cc][Hh]%s+(.+)$")
  if text then
    if ns.OpenQuestBook then ns.OpenQuestBook("search") end
    if ns.JournalSetQuery then ns.JournalSetQuery(text) end
    return
  end
  if msg == "" or msg == "options" or msg == "config" then
    if ns.OpenOptions then ns.OpenOptions() end
  elseif msg == "reset" then
    if ns.ResetButtonPosition then ns.ResetButtonPosition() end
  elseif msg == "setup" then
    if ns.OpenSetup then ns.OpenSetup() end -- (17.10.) the map style and first steps window
  elseif msg == "panel" then
    -- (1.3.8) the old window is gone: its lines are at the bottom of the quest list
    if ns.ToggleTracker then ns.ToggleTracker() end
  elseif msg == "collect" or msg == "sammeln" then
    if ns.SetDataOnly then ns.SetDataOnly() end -- (25.10.) only learning and sharing on, again: settings back
  elseif msg == "xpbar" then
    if ns.ToggleXPBar then ns.ToggleXPBar() end
  elseif msg == "next" then
    if ns.PointToNextQuest then ns.PointToNextQuest() end
  elseif msg == "arrow" then
    if ns.ToggleArrow then ns.ToggleArrow() end
  elseif msg == "list" then
    if ns.ToggleTracker then ns.ToggleTracker() end
  elseif msg == "questie" then
    if ns.PrintQuestieStatus then ns.PrintQuestieStatus() end
  elseif msg == "xp" then
    if ns.PrintPlanner then ns.PrintPlanner() end
  elseif msg == "export" or msg == "export all" then
    if ns.OpenExport then ns.OpenExport(msg == "export all") end
  elseif msg == "missing" then
    if ns.OpenMissing then ns.OpenMissing() end
  elseif msg == "mapsizes" then
    -- (1.3.4) map rectangles and flight points for the level guide (saved at /reload)
    if ns.DumpMapSizes then
      local n, k = ns.DumpMapSizes()
      print(("|cff3fa9f5Questdon|r: %d maps, %d flight points stored. /reload saves them."):format(n, k))
    end
  elseif msg:match("^npcname") then
    -- (1.3.5) test: an NPC's name from every source (does the tooltip way work in this client?)
    local id = tonumber(msg:match("^npcname%s+(%d+)$") or "")
    local r = id and ns.NpcNameReport and ns.NpcNameReport(id)
    if not r then
      print("|cff3fa9f5Questdon|r: /qd npcname <NPC ID>, e.g. /qd npcname 823")
    else
      local function S(v) return v and ('"' .. v .. '"') or "-" end
      print(("|cff3fa9f5Questdon|r: NPC %d: %s (from %s)"):format(r.id, S(r.name), r.source or "-"))
      print(("  game tooltip: %s%s, learned: %s, shipped: %s, data: %s"):format(S(r.game), r.gameBroken and " (tooltip way not available)" or "",
        S(r.learned), S(r.shipped), S(r.data)))
      if not r.game and not r.gameBroken then print("  The client may ask the server first: try again in a few seconds.") end
    end
  elseif msg:match("^why%s+%d+$") then
    -- (1.3.6) why a quest has no "!" (QuestData.lua ns.WhyQuest)
    for _, l in ipairs(ns.WhyQuest(tonumber(msg:match("(%d+)$")))) do print("|cffffd100Questdon|r " .. l) end
  elseif msg == "mem" or msg:match("^mem%s+%d+$") then
    if ns.MemoryCheck then ns.MemoryCheck(tonumber(msg:match("(%d+)$"))) end
  elseif msg == "diag" then
    if ns.OpenDiag then ns.OpenDiag() end
  elseif msg == "xpcheck" or msg == "xpcheck reset" then
    if ns.OpenXPCheck then ns.OpenXPCheck(msg == "xpcheck reset" and "reset" or nil) end
  elseif msg == "dungeonlevels" then
    -- (1.3.5) the level ranges of the data and the game, and the entrances, to check the data
    if ns.OpenDungeonLevels then ns.OpenDungeonLevels() end
  elseif msg == "dungeons" or msg == "dungeon" then
    if ns.OpenDungeons then ns.OpenDungeons() end
  elseif msg == "group" or msg == "party" then
    if ns.PrintParty then ns.PrintParty() end
  elseif msg == "nothere" then
    if ns.ReportTarget then ns.ReportTarget() end
  elseif msg == "nothere undo" then
    if ns.UndoNotHere then ns.UndoNotHere() end
  elseif msg == "nothere list" then
    if ns.PrintNotHere then ns.PrintNotHere() end
  elseif msg == "zone" or msg == "quests" then
    if ns.ToggleZoneQuests then ns.ToggleZoneQuests() end
  elseif msg == "journal" or msg == "tagebuch" then
    if ns.ToggleJournal then ns.ToggleJournal() end
  elseif msg == "search" or msg == "suche" then
    if ns.OpenQuestBook then ns.OpenQuestBook("search") end
  elseif msg == "nettest" then
    if ns.NetTest then ns.NetTest() end
  elseif msg == "help" then
    ns.Print(ns.HELP)
  else
    -- (1.3.5) a typo no longer opens the options without a word
    ns.Print(L["Unknown command: %s"]:format(raw))
    ns.Print(ns.HELP)
  end
end)
