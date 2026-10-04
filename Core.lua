local addonName, ns = ...
local L = ns.L

ns.defaults = {
  autoAccept = true,
  autoTurnIn = true,
  skipTrivial = true,
  highlightBest = true,
  autoPickBest = false,
  sellJunk = true,
  autoRepair = true,
  useGuildRepair = false,
  fastLoot = true,
  questItemButton = true,
  -- 1.27: target button (macro of mob names, learned), waypoint export (both off)
  targetButton = false,
  targetButtonPos = nil,
  mobNames = {}, -- [creatureID] = name, learned from nameplates and target
  exportBlizzardWaypoint = false,
  exportTomTom = false,
  buttonPos = nil, -- { point, relPoint, x, y }
  -- 1.1
  notifySound = true,
  notifyText = true,
  learnQuests = true,
  learnPins = true,
  pinsOnlyUnknown = true,
  shareQuests = false,
  questieFirst = true,
  -- 1.2
  availablePins = true,
  objectivePins = true,
  showLowLevel = false,
  chainHint = true,
  -- 1.3
  arrow = true,
  arrowPos = nil,
  -- 1.4
  arrowScale = 1.15,
  objectivePinSize = 12,
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
  learnedObj = {}, -- [questID] = { [objectiveIndex] = { map,x,y, ... } }
  learnedCredit = {}, -- (1.0.1) [questID] = { [index] = { c|o|i = { [id] = n } } } what gave objective credit (Learn.lua)
  learnedDrops = {}, -- (1.0.1) [itemID] = { ["c123"] = { n, map, x, y } } where a quest item dropped
  learnedItemStarts = {}, -- (1.0.1) [itemID] = questID started by a looted item
  shareLearned = true, -- (1.0.1) send own learned data to guild and group (Exchange.lua)
  shared = {}, -- (1.0.1) what other players reported: [key] = { v = { variants }, c, t }
  shareSent = {}, -- (1.0.1) [key] = what was last sent
  showPanel = true,
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
  arrowCombatFade = false,
  xpBarAlpha = 0.82,
  xpBarCombatFade = false,
  -- 1.21
  minimapPins = true, -- the map pins of the current zone on the minimap too
  -- 1.22
  nameplateIcons = true, -- quest marks above nameplates (quest mobs, quest givers, turn-ins)
  lowLevelRange = 10,    -- a quest is low level this many levels below yours (was fixed)
  -- 1.24: quests without a level in the data on the map/minimap/nameplates/panel
  -- even when neither the client nor a quest giver confirmed them (replaces
  -- "noLevelIsLow", see the migration in ADDON_LOADED)
  showNoLevel = false,
  -- 1.0: event quests (Darkmoon Faire, Lunar Festival, ...) have quest givers that
  -- are only there while the event runs. Hidden until the game or the quest giver
  -- confirms them; off shows them like any other quest.
  hideEventQuests = true,
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
function ns.SafeCall(context, fn, ...)
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
      C_Timer.After(REFRESH_DELAY, runGuarded)
    else
      ns.SafeCall("timer", RunParts)
    end
  end
end

function ns.After(delay, fn)
  if C_Timer and C_Timer.After then C_Timer.After(delay, ns.Guard("timer", fn)) end
end

function ns.NewTicker(interval, fn, iterations)
  if C_Timer and C_Timer.NewTicker then return C_Timer.NewTicker(interval, ns.Guard("timer", fn), iterations) end
end

-- Event dispatcher: several modules may listen to the same event.
local frame = CreateFrame("Frame")
local listeners, initCallbacks = {}, {}

function ns.On(event, fn)
  if not listeners[event] then
    listeners[event] = {}
    -- Unknown events throw in the modern client, so register defensively.
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then listeners[event] = nil return false end
  end
  table.insert(listeners[event], fn)
  return true
end

function ns.OnInit(fn) table.insert(initCallbacks, fn) end

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
    -- (1.24) per character: what quest givers offered (Offers.lua)
    if type(QuestdonCharDB) ~= "table" then QuestdonCharDB = {} end
    ns.charDB = QuestdonCharDB
    for _, fn in ipairs(initCallbacks) do ns.SafeCall("init", fn) end
    frame:UnregisterEvent("ADDON_LOADED")
    return
  end
  if not ns.db then return end
  local list = listeners[event]
  if list then
    for i = 1, #list do ns.SafeCall(event, list[i], event, ...) end
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
local function ReadQuestLog()
  local list = {}
  if not C_QuestLog then return list end
  for i = 1, ns.Num(ns.Value(C_QuestLog.GetNumQuestLogEntries)) or 0 do
    local info = ns.Value(C_QuestLog.GetInfo, i)
    -- secret flags count as "not a header / not hidden" only if the quest ID is readable
    if type(info) == "table" and not ns.True(info.isHeader) and not ns.True(info.isHidden) and (ns.Num(info.questID) or 0) > 0 then
      list[#list + 1] = info
    end
  end
  return list
end
function ns.QuestLogEntries()
  return ns.ScopeValue("questLog", ReadQuestLog)
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

-- Failed (escort died, timer ran out): the objectives no longer count.
function ns.IsQuestFailed(questID)
  return ns.True(ns.Value(C_QuestLog.IsFailed, questID))
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

function ns.PlayerPosition()
  if not C_Map then return nil end
  local mapID = ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  if not mapID then return nil end
  local pos = ns.Value(C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) ~= "table" or not pos.GetXY then return nil end
  local ok, x, y = pcall(pos.GetXY, pos)
  if not ok or not (ns.Num(x) and ns.Num(y)) or (x == 0 and y == 0) then return nil end
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
ns.HELP = L["Commands: /qd (options), /qd panel, /qd arrow, /qd xpbar, /qd next, /qd xp, /qd dungeons, /qd group, /qd questie, /qd export, /qd diag (diagnostics), /qd missing (nonexistent quests), /qd xpcheck (XP sources), /qd nettest (channel test), /qd reset (reset button position)"]
SlashCmdList.QUESTDON = ns.Guard("slash", function(msg)
  msg = strtrim and strtrim(msg or ""):lower() or (msg or "")
  if msg == "reset" then
    if ns.ResetButtonPosition then ns.ResetButtonPosition() end
  elseif msg == "panel" then
    if ns.TogglePanel then ns.TogglePanel() end
  elseif msg == "xpbar" then
    if ns.ToggleXPBar then ns.ToggleXPBar() end
  elseif msg == "next" then
    if ns.PointToNextQuest then ns.PointToNextQuest() end
  elseif msg == "arrow" then
    if ns.ToggleArrow then ns.ToggleArrow() end
  elseif msg == "questie" then
    if ns.PrintQuestieStatus then ns.PrintQuestieStatus() end
  elseif msg == "xp" then
    if ns.PrintPlanner then ns.PrintPlanner() end
  elseif msg == "export" or msg == "export all" then
    if ns.OpenExport then ns.OpenExport(msg == "export all") end
  elseif msg == "missing" then
    if ns.OpenMissing then ns.OpenMissing() end
  elseif msg == "diag" then
    if ns.OpenDiag then ns.OpenDiag() end
  elseif msg == "xpcheck" or msg == "xpcheck reset" then
    if ns.OpenXPCheck then ns.OpenXPCheck(msg == "xpcheck reset" and "reset" or nil) end
  elseif msg == "dungeons" or msg == "dungeon" then
    if ns.OpenDungeons then ns.OpenDungeons() end
  elseif msg == "group" or msg == "party" then
    if ns.PrintParty then ns.PrintParty() end
  elseif msg == "nettest" then
    if ns.NetTest then ns.NetTest() end
  elseif msg == "help" then
    ns.Print(ns.HELP)
  else
    if ns.OpenOptions then ns.OpenOptions() end
  end
end)
