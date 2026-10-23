local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Does a quest exist on this server? The bundled data (All The Things) also
-- holds older classic data, and some of those quests are gone in Forever.
-- The client answers C_QuestLog.RequestLoadQuestByID(id) with the event
-- QUEST_DATA_LOAD_RESULT(id, success); success == false means the server does
-- not know the quest.
--
--   * Only quests Questdon is about to offer are asked (map pins, next quest,
--     chain hint, tooltips, CanTakeQuest/QuestExists from other addons), each
--     at most once per session, at most RATE requests per second (queue).
--   * Only an explicit "false" counts. No answer (TIMEOUT) = unknown = shown.
--   * "false" is kept account-wide in QuestdonDB.questExists[id] = false with
--     the client build in QuestdonDB.questExistsBuild. After a new build each
--     of them is asked once more; "true" removes it.
--   * "true" is kept for this session only.
--   * Quests in the log are never hidden; accepting a quest clears its mark.
---------------------------------------------------------------------------
local RATE = 5        -- requests per second
local TIMEOUT = 30    -- seconds without an answer: unknown
local MAX_QUEUE = 400

local confirmed = {}  -- [id] = true: server said yes (this session)
local asked = {}      -- [id] = true: requested this session (no second request)
local pending = {}    -- [id] = time sent, waiting for the answer
local noAnswer = {}   -- [id] = true: timed out (unknown)
local recheck = {}    -- [id] = true: negative from an older build, asked again
local queue, queued = {}, {}
local windowStart, windowCount = -1, 0
local pumpScheduled = false

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

local function Store()
  local db = ns.db
  if not db then return nil end
  if type(db.questExists) ~= "table" then db.questExists = {} end
  return db.questExists
end

-- Client build as text ("63000"), nil if unknown.
local function Build()
  if type(GetBuildInfo) ~= "function" then return nil end
  local ok, _, build = pcall(GetBuildInfo)
  if not ok or build == nil or not ns.Usable(build) then return nil end
  build = tostring(build)
  return build ~= "" and build or nil
end

local function CanRequest()
  return C_QuestLog and type(C_QuestLog.RequestLoadQuestByID) == "function"
end

-- Up to RATE requests in any one second.
local function Budget()
  local now = Now()
  if now - windowStart >= 1 or now < windowStart then windowStart, windowCount = now, 0 end
  return windowCount < RATE
end

local function Expire()
  local now = Now()
  for id, t in pairs(pending) do
    if now - t >= TIMEOUT or now < t then pending[id], noAnswer[id] = nil, true end
  end
end

local function Send(id)
  windowCount = windowCount + 1
  asked[id] = true
  recheck[id] = nil
  local ok = pcall(C_QuestLog.RequestLoadQuestByID, id)
  if ok then pending[id] = Now() end
end

-- Still worth a request? (not answered, not asked yet, or a recheck)
local function Wanted(id)
  if confirmed[id] or pending[id] then return false end
  if recheck[id] then return true end
  return not asked[id]
end

local Pump
local function Schedule()
  if pumpScheduled or #queue == 0 then return end
  pumpScheduled = true
  local wait = windowStart + 1 - Now()
  ns.After(wait > 0.1 and wait or 0.1, Pump)
end

function Pump()
  pumpScheduled = false
  if not CanRequest() then return end
  Expire()
  while #queue > 0 and Budget() do
    local id = table.remove(queue, 1)
    queued[id] = nil
    if Wanted(id) then Send(id) end
  end
  Schedule()
end

local function Enqueue(id)
  if queued[id] or not Wanted(id) or #queue >= MAX_QUEUE then return end
  queued[id] = true
  queue[#queue + 1] = id
  Schedule()
end

-- Ask the server about a quest (once per session, rate limited). Cheap: does
-- nothing for quests already asked.
function ns.RequestQuestData(questID)
  local id = ns.Num(questID)
  if not id or id <= 0 or not CanRequest() or not Wanted(id) or queued[id] then return end
  if #queue == 0 and Budget() then Send(id) else Enqueue(id) end
end
ns.CheckQuestExists = ns.RequestQuestData

-- Known not to exist on this server (explicit "false", never for quests in the log).
function ns.QuestKnownMissing(questID)
  local store = Store()
  local id = ns.Num(questID)
  if not (store and id) or store[id] ~= false then return false end
  if ns.InQuestLog and ns.InQuestLog(id) then return false end
  return true
end

-- true: exists (in the log or confirmed this session), false: the server said
-- no, nil: unknown (asks the server).
function ns.QuestExists(questID)
  local id = ns.Num(questID)
  if not id or id <= 0 then return nil end
  if ns.InQuestLog and ns.InQuestLog(id) then return true end
  if ns.QuestKnownMissing(id) then return false end
  if confirmed[id] then return true end
  ns.RequestQuestData(id)
  return nil
end

-- Sorted IDs of the quests the server does not know.
function ns.MissingQuestIDs()
  local list = {}
  for id, v in pairs(Store() or {}) do
    if v == false and type(id) == "number" then list[#list + 1] = id end
  end
  table.sort(list)
  return list
end

-- For /qd diag: confirmed, nonexistent, pending, no answer, rechecks left.
function ns.QuestExistsCounts()
  Expire()
  local c = { confirmed = 0, missing = #ns.MissingQuestIDs(), pending = #queue, noAnswer = 0, recheck = 0 }
  for _ in pairs(confirmed) do c.confirmed = c.confirmed + 1 end
  for _ in pairs(pending) do c.pending = c.pending + 1 end
  for _ in pairs(noAnswer) do c.noAnswer = c.noAnswer + 1 end
  for _ in pairs(recheck) do c.recheck = c.recheck + 1 end
  return c
end

ns.On("QUEST_DATA_LOAD_RESULT", function(_, questID, success)
  local id = ns.Num(questID)
  if not id or success == nil or not ns.Usable(success) then return end
  local store = Store()
  if not store then return end
  pending[id], noAnswer[id], recheck[id] = nil, nil, nil
  if success == false then
    confirmed[id] = nil
    -- only quests we know or asked about (other addons ask about many more)
    local ours = asked[id] or (ns.ATT_QUESTS and ns.ATT_QUESTS[id]) or (ns.db.learned and ns.db.learned[id])
    if ours and not ns.InQuestLog(id) then store[id] = false end
  elseif success == true then
    confirmed[id] = true
    store[id] = nil
  end
end)

-- An accepted quest exists, whatever an earlier answer said.
ns.On("QUEST_ACCEPTED", function(_, a, b)
  local id = ns.Num(b) or ns.Num(a)
  local store = Store()
  if id and store and store[id] == false and ns.InQuestLog(id) then
    store[id] = nil
    confirmed[id] = true
  end
end)

ns.OnInit(function()
  local store = Store()
  -- keep only [number] = false
  for id, v in pairs(store) do
    if type(id) ~= "number" or v ~= false then store[id] = nil end
  end
  local build = Build()
  if not build or ns.db.questExistsBuild == build then return end
  local old = ns.db.questExistsBuild
  ns.db.questExistsBuild = build
  if old == nil then return end
  -- new client build: ask each negative once more (they stay hidden until "true")
  for id in pairs(store) do recheck[id] = true end
  ns.After(5, function()
    for _, id in ipairs(ns.MissingQuestIDs()) do
      if recheck[id] then Enqueue(id) end
    end
  end)
end)

-- /qd missing: the IDs, to report them.
function ns.OpenMissing()
  local ids = ns.MissingQuestIDs()
  local note = #ids == 0 and L["No quest has been reported as nonexistent by the server yet."]
    or L["%d quests from the bundled data do not exist on this server. Questdon no longer offers them. They are also part of /qd export."]:format(#ids)
  local lines = {}
  for i = 1, #ids, 10 do
    local row = {}
    for j = i, math.min(i + 9, #ids) do row[#row + 1] = tostring(ids[j]) end
    lines[#lines + 1] = table.concat(row, " ")
  end
  return ns.ShowText(L["Nonexistent quests"], note .. " " .. L["Only numbers: no character, realm or guild names."],
    #lines > 0 and table.concat(lines, "\n") or "-")
end
