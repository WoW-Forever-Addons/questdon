local _, ns = ...
local C_QuestLog = ns.QL or C_QuestLog -- (25.10.2026) Era shims, Core.lua ApiProxy

---------------------------------------------------------------------------
-- (1.3.12, 28.10.2026, Daniel: "was uns das Spiel selber liefert, können wir
-- ruhig mit reinnehmen") What the game itself says about which quests exist,
-- so the zone lists can be checked for gaps (store/coverage.py).
--
-- 1. Server scan, only on /qd scan: asks the server about every ID of RANGES
--    (C_QuestLog.RequestLoadQuestByID, answer QUEST_DATA_LOAD_RESULT), RATE
--    per second, at most INFLIGHT open at a time. Kept in QuestdonDB.scan:
--      on     true while running (it goes on after /reload and login)
--      next   the next ID to ask (false: all asked); rate the requests per second
--      found  [id] = title ("" if the client gave none), lv [id] = level
--      no     how many IDs the server does not know
--      late   [id] = true: no answer within TIMEOUT
--      wait   [id] = true: asked, answer still open (asked again after /reload)
--      build, t0, t1  client build, time started and finished; retried: the
--      ones without an answer were asked once more at the end
--    It only collects: nothing in Questdon reads the result.
--    /qd scan [fast|stop|status|reset].
-- 2. Each login: the character's completed quest IDs, sorted, in
--    QuestdonCharDB.doneIDs (one call, nothing else).
---------------------------------------------------------------------------
local RANGES = { { 1, 26000 }, { 76000, 100000 }, { 190000, 290000 } }
local RATE, FAST = 10, 20
local INFLIGHT = 60
local TIMEOUT = 30
ns.SCAN_RANGES = RANGES

local pending = {} -- [id] = time sent
local running = false

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end
local function Say(text) print("|cff3fa9f5Questdon|r scan: " .. text) end

local function Store()
  local db = ns.db
  if not db then return nil end
  if type(db.scan) ~= "table" then db.scan = {} end
  local s = db.scan
  if type(s.found) ~= "table" then s.found = {} end
  if type(s.lv) ~= "table" then s.lv = {} end
  if type(s.late) ~= "table" then s.late = {} end
  if type(s.wait) ~= "table" then s.wait = {} end
  s.no = ns.Num(s.no) or 0
  if s.next ~= false then s.next = ns.Num(s.next) or RANGES[1][1] end -- false: all asked
  return s
end

local function Total()
  local n = 0
  for _, r in ipairs(RANGES) do n = n + r[2] - r[1] + 1 end
  return n
end

-- IDs asked so far (by position in RANGES)
local function Asked(s)
  local n = 0
  if s.next == false then return Total() end
  for _, r in ipairs(RANGES) do
    if s.next > r[2] then n = n + r[2] - r[1] + 1
    elseif s.next >= r[1] then n = n + s.next - r[1] end
  end
  return n
end

-- The ID after id within RANGES, nil past the last range.
local function After(id)
  id = id + 1
  for _, r in ipairs(RANGES) do
    if id <= r[2] then return id < r[1] and r[1] or id end
  end
  return nil
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function NotInData(s)
  local n = 0
  for id in pairs(s.found) do
    if not (ns.QuestInData and ns.QuestInData(id)) then n = n + 1 end
  end
  return n
end

function ns.ScanStatus()
  local s = Store()
  if not s then return nil end
  return { asked = Asked(s), total = Total(), found = Count(s.found), notInData = NotInData(s), no = s.no,
    late = Count(s.late), open = Count(pending), on = s.on == true, done = s.t1 ~= nil, rate = ns.Num(s.rate) or RATE }
end

local function PrintStatus()
  local c = ns.ScanStatus()
  if not c then return end
  local left = c.total - c.asked
  Say(("%d of %d IDs asked, %d known to the server (%d of them not in Questdon's data), %d unknown, %d without answer%s.")
    :format(c.asked, c.total, c.found, c.notInData, c.no, c.late,
      c.done and ", finished" or c.on and (", about %d min left"):format(math.ceil(left / c.rate / 60)) or ", paused"))
end

local function CanRequest() return type(C_QuestLog.RequestLoadQuestByID) == "function" end

local function Send(s, id)
  if pcall(C_QuestLog.RequestLoadQuestByID, id) then
    pending[id] = Now()
    s.wait[id] = true
  end
end

local function Finish(s)
  s.on, running = nil, false
  s.t1 = ns.Value(time) or 0
  Say("finished.")
  PrintStatus()
end

local Tick
local function Schedule() ns.After(1, Tick) end

function Tick()
  local s = Store()
  if not (s and s.on) or not CanRequest() then running = false return end
  local now = Now()
  for id, t in pairs(pending) do
    if now - t >= TIMEOUT or now < t then pending[id], s.wait[id], s.late[id] = nil, nil, true end
  end
  local open = Count(pending)
  local budget = ns.Num(s.rate) or RATE
  -- answers lost by a /reload first
  for id in pairs(s.wait) do
    if budget <= 0 or open >= INFLIGHT then break end
    if not pending[id] then Send(s, id); budget, open = budget - 1, open + 1 end
  end
  while budget > 0 and open < INFLIGHT and s.next do
    local id = s.next
    s.next = After(id) or false
    Send(s, id)
    budget, open = budget - 1, open + 1
  end
  if not s.next and open == 0 then
    -- the ones without an answer get one more try
    if not s.retried and next(s.late) then
      s.retried = true
      for id in pairs(s.late) do s.wait[id] = true end
      s.late = {}
    else
      Finish(s) return
    end
  end
  Schedule()
end

ns.ScanTick = function() Tick() end -- tests

local function Start()
  if running then return end
  running = true
  Schedule()
end

-- /qd scan [fast|stop|status|reset]
function ns.ScanCommand(arg)
  local s = Store()
  if not s then return end
  arg = arg or ""
  if arg == "status" then
    PrintStatus()
  elseif arg == "stop" then
    s.on = nil
    Say("paused, /qd scan goes on.")
    PrintStatus()
  elseif arg == "reset" then
    ns.db.scan = nil
    pending, running = {}, false
    Say("cleared.")
  elseif arg == "" or arg == "fast" then
    if not CanRequest() then Say("this client cannot ask the server about quests.") return end
    if s.t1 and not s.next then Say("already finished, /qd scan reset starts again.") PrintStatus() return end
    s.rate = arg == "fast" and FAST or RATE
    s.on = true
    if not s.build and GetBuildInfo then
      local ok, _, build = pcall(GetBuildInfo)
      if ok and build ~= nil and ns.Usable(build) then s.build = tostring(build) end
    end
    s.t0 = s.t0 or ns.Value(time)
    Say(("running, %d IDs per second. /qd scan status, /qd scan stop. The result is saved at /reload or logout."):format(s.rate))
    Start()
  else
    Say("/qd scan, /qd scan fast, /qd scan status, /qd scan stop, /qd scan reset")
  end
end

ns.On("QUEST_DATA_LOAD_RESULT", function(_, questID, success)
  local id = ns.Num(questID)
  if not id or not pending[id] or success == nil or not ns.Usable(success) then return end
  local s = Store()
  if not s then return end
  pending[id], s.wait[id], s.late[id] = nil, nil, nil
  if success == true then
    local title = ns.Value(C_QuestLog.GetTitleForQuestID, id)
    s.found[id] = type(title) == "string" and title or ""
    local lv = ns.Num(ns.Value(C_QuestLog.GetQuestDifficultyLevel, id))
    if lv and lv > 0 then s.lv[id] = lv end
  elseif success == false then
    s.no = s.no + 1
  end
end)

ns.OnInit(function()
  local s = ns.db and type(ns.db.scan) == "table" and Store()
  if s and s.on then Start() end
end)

-- 2. completed quests of this character, once per login
local function ReadDone()
  local ids = ns.Value(C_QuestLog.GetAllCompletedQuestIDs)
  if type(ids) ~= "table" or #ids == 0 or type(QuestdonCharDB) ~= "table" then return end
  local out = {}
  for _, id in ipairs(ids) do
    id = ns.Num(id)
    if id and id > 0 then out[#out + 1] = id end
  end
  table.sort(out)
  QuestdonCharDB.doneIDs = out
end
ns.ScanReadDone = ReadDone

local doneRead = false
ns.On("PLAYER_ENTERING_WORLD", function()
  if doneRead then return end
  doneRead = true
  ns.After(5, ReadDone)
end)
