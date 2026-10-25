-- Questdon on WoW Classic Era (1.15.x), loaded only by Questdon_Vanilla.toc, before Core.lua.
--
-- Era lacks about forty functions of the newer API that Questdon calls (CLASSIC_ERA_PLAN.md). This file builds
-- the ones that have an older counterpart. Core.lua puts them behind ns.QL, ns.ST and ns.TT (proxies that look here
-- first, then in the game's own table); the files take `local C_QuestLog = ns.QL or C_QuestLog` and so on.
-- The game's global tables are never changed (Questie and other addons look at them).
-- Without a counterpart and therefore off on Era: quest lines (C_QuestLine), the game's map pin
-- (C_Map.SetUserWaypoint), the server check of unknown quests (RequestLoadQuestByID), C_Minimap.GetViewRadius,
-- next waypoint of a quest, trivial and tag info of a quest by ID.
local _, ns = ...

ns.ERA = true
-- events Questdon fires itself on Era (Core.lua ns.On keeps their listeners, ns.Fire calls them)
ns.SYNTH_EVENTS = { SUPER_TRACKING_CHANGED = true }

local QL, ST, TT = {}, {}, {}
ns.EraShims = { C_QuestLog = QL, C_SuperTrack = ST, C_TooltipInfo = TT }

local function G(name) local f = _G[name] return type(f) == "function" and f or nil end

-- the log entry as C_QuestLog.GetInfo gives it
local function Info(index)
  local fn = G("GetQuestLogTitle")
  if not (fn and type(index) == "number" and index > 0) then return nil end
  local title, level, group, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, _, isOnMap,
    hasLocalPOI, isTask, _, isStory, isHidden = fn(index)
  if title == nil then return nil end
  return {
    title = title, questLogIndex = index, questID = questID or 0, level = level, difficultyLevel = level,
    suggestedGroup = type(group) == "number" and group or 0, isHeader = isHeader and true or false,
    isCollapsed = isCollapsed and true or false, isComplete = isComplete == 1, isFailed = isComplete == -1,
    frequency = frequency, startEvent = startEvent and true or false, isOnMap = isOnMap and true or false,
    hasLocalPOI = hasLocalPOI and true or false, isTask = isTask and true or false, isStory = isStory and true or false,
    isHidden = isHidden and true or false, readyForTranslation = true,
  }
end

local function IndexOf(questID)
  local fn = G("GetQuestLogIndexByID")
  if not (fn and type(questID) == "number") then return nil end
  local i = fn(questID)
  return type(i) == "number" and i > 0 and i or nil
end

-- run fn with the quest selected in the log, then select the old entry again
local function WithSelected(questID, fn, ...)
  local index, sel, get = IndexOf(questID), G("SelectQuestLogEntry"), G("GetQuestLogSelection")
  if not (index and sel) then return nil end
  local old = get and get() or 0
  sel(index)
  local a, b, c = fn(...)
  if old ~= index then sel(old) end
  return a, b, c
end

function QL.GetNumQuestLogEntries()
  local fn = G("GetNumQuestLogEntries")
  if fn then return fn() end
  return 0, 0
end

QL.GetInfo = Info

function QL.GetLogIndexForQuestID(questID) return IndexOf(questID) end

local function Flag(questID)
  local fn, i = G("GetQuestLogTitle"), IndexOf(questID)
  if not (fn and i) then return nil end
  return select(6, fn(i))
end
function QL.IsComplete(questID) return Flag(questID) == 1 end
function QL.IsFailed(questID) return Flag(questID) == -1 end

function QL.GetTitleForQuestID(questID)
  local fn, i = G("GetQuestLogTitle"), IndexOf(questID)
  if fn and i then return (fn(i)) end
  local info = C_QuestLog and C_QuestLog.GetQuestInfo -- Era has it: the title of any quest the client knows
  if info then
    local ok, title = pcall(info, questID)
    if ok and type(title) == "string" and title ~= "" then return title end
  end
  return nil
end

function QL.GetQuestDifficultyLevel(questID)
  local fn, i = G("GetQuestLogTitle"), IndexOf(questID)
  if fn and i then return (select(2, fn(i))) end
  return nil
end

function QL.GetSelectedQuest()
  local get, fn = G("GetQuestLogSelection"), G("GetQuestLogTitle")
  local i = get and get() or 0
  if not (fn and i and i > 0) then return 0 end
  local id = select(8, fn(i))
  return id or 0
end

function QL.SetSelectedQuest(questID)
  local sel = G("SelectQuestLogEntry")
  if not sel then return end
  sel(IndexOf(questID) or 0)
end

-- the old API works on the selected entry: SetSelectedQuest first (Cleanup.lua does)
function QL.SetAbandonQuest() local f = G("SetAbandonQuest") if f then f() end end
function QL.AbandonQuest() local f = G("AbandonQuest") if f then f() end end
function QL.CanAbandonQuest(questID) return IndexOf(questID) ~= nil end

function QL.IsPushableQuest(questID)
  local push = G("GetQuestLogPushable")
  if not push then return false end
  return WithSelected(questID, push) and true or false
end

function QL.GetRequiredMoney(questID)
  local fn = G("GetQuestLogRequiredMoney")
  if not fn then return 0 end
  return WithSelected(questID, fn) or 0
end

-- C_QuestLog.GetTimeAllowed gives total and elapsed; Era only the seconds left of the selected quest
function QL.GetTimeAllowed(questID)
  local fn = G("GetQuestLogTimeLeft")
  if not fn then return nil end
  local left = WithSelected(questID, fn)
  if type(left) == "number" and left > 0 then return left, 0 end
  return nil
end

function QL.IsQuestWatched(questID)
  local fn, i = G("IsQuestWatched"), IndexOf(questID)
  if not (fn and i) then return false end
  return fn(i) and true or false
end

function QL.GetAllCompletedQuestIDs()
  local fn = G("GetQuestsCompleted")
  local t = fn and fn()
  local out = {}
  if type(t) == "table" then
    for id, done in pairs(t) do if done then out[#out + 1] = id end end
    table.sort(out)
  end
  return out
end

-- No super tracking on Era: Questdon keeps the quest it tracks itself and tells its own listeners.
local tracked = 0
function ST.GetSuperTrackedQuestID() return tracked end
function ST.SetSuperTrackedQuestID(questID)
  questID = type(questID) == "number" and questID or 0
  if questID == tracked then return end
  tracked = questID
  if ns.Fire then ns.Fire("SUPER_TRACKING_CHANGED") end
end

-- No C_TooltipInfo on Era: read our own hidden tooltip. Lines carry only text (no line types).
local scan
local function Lines(setter, ...)
  if not CreateFrame then return nil end
  if not scan then
    scan = CreateFrame("GameTooltip", "QuestdonEraScanTooltip", nil, "GameTooltipTemplate")
    if not scan then return nil end
  end
  scan:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  scan:ClearLines()
  local ok = pcall(scan[setter], scan, ...)
  if not ok then return nil end
  local lines = {}
  for i = 1, scan:NumLines() or 0 do
    local left = _G["QuestdonEraScanTooltipTextLeft" .. i]
    local right = _G["QuestdonEraScanTooltipTextRight" .. i]
    local l = left and left:GetText()
    local r = right and right:GetText()
    if l or r then lines[#lines + 1] = { leftText = l, rightText = r } end
  end
  scan:Hide()
  return { lines = lines }
end
function TT.GetBagItem(bag, slot) return Lines("SetBagItem", bag, slot) end
function TT.GetHyperlink(link) return Lines("SetHyperlink", link) end
function TT.GetItemByID(id) return Lines("SetHyperlink", "item:" .. tostring(id)) end
function TT.GetInventoryItem(unit, slot) return Lines("SetInventoryItem", unit, slot) end
