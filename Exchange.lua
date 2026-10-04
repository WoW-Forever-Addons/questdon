local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.0.1) Sharing learned quest data with guild and group.
--
-- Every Questdon sends only its OWN observations: the lines of /qd export
-- (Export.lua, ns.ExportRecords) that the bundled data does not have yet.
-- Others keep them apart from their own learning (QuestdonDB.shared) and use
-- a fact only once two different players reported it. Nothing is passed on:
-- what a client only knows from others it never sends, so "two reporters"
-- really are two players and there are no echo loops.
--
--   message  "D1:<seq>:<line>;<line>;..."  (at most MAX_MSG characters)
--   lines    S G I T O F K D A X as in Export.lua, only numbers
--
-- Sending: option shareLearned (on), to the guild and the own group (not to
-- the group when all members are in the guild: the guild message reaches
-- them), at most MAX_PER_FLUSH messages every FLUSH_GAP seconds and
-- MAX_PER_HOUR per hour, never in a chat lockdown or combat. What was sent is
-- remembered (QuestdonDB.shareSent: key -> line); counters are sent again only
-- at the next step (1, 5, 25, 100); facts KNOWN others already reported the
-- same way and spots beyond SPOTS_PER_OBJECTIVE per objective are not sent.
-- Receiving is always on (decision 2026-10-04: everybody may use shared data).
--
-- Checks on receipt: exact line shapes, number ranges, own echoes ignored,
-- at most PER_SENDER facts per sender and hour, at most MAX_SHARED facts.
-- Reporters are kept as a 24 bit checksum of "Name-Realm" (to count them),
-- never shown or exported. Shared data never overrides own learning or the
-- game; it ranks before the bundled data where it is used (turn-ins,
-- objective spots).
---------------------------------------------------------------------------
local PREFIX = "QdShare"
local FLUSH_GAP = 60        -- seconds between two sends
local MAX_PER_FLUSH = 5     -- messages per send
local MAX_PER_HOUR = 30     -- messages per hour (a long backlog is spread out)
local SPOTS_PER_OBJECTIVE = 5 -- objective spots sent per objective
local KNOWN = 3             -- others who reported a fact the same way: no need to send it
local MAX_MSG = 240         -- characters per message (limit 255)
local MAX_SHARED = 20000    -- facts kept
local MAX_VARIANTS = 3      -- differing reports per fact
local MAX_REPORTERS = 8     -- reporters kept per variant
local PER_SENDER = 200      -- facts per sender and hour
local CONFIRM = 2           -- reporters needed before a fact is used
local NEAR = 2              -- map units: two spots this close are the same

local stats = { saved = 0, sentMsgs = 0, sentFacts = 0, recvMsgs = 0, recvLines = 0, bad = 0, own = 0, limited = 0, blocked = 0, pruned = 0 }
ns.shareStats = stats
local registered = false
local seq = 0
local senders = {}          -- [hash] = { t = window start, n = facts }
local version = 0           -- changes whenever shared data changes (caches)

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end
local function Clock() return ns.Num(ns.Value(time)) or Now() end

local function DB()
  local db = ns.db
  if type(db.shared) ~= "table" then db.shared = {} end
  if type(db.shareSent) ~= "table" then db.shareSent = {} end
  return db
end

local function Locked()
  local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn)
  if not ok or v == nil then return false end
  return not ns.Usable(v) or v == true
end

-- 24 bit checksum of a name (counting reporters; not reversible on its own,
-- but not anonymous either: never shown, never exported).
local function Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777216 end
  return ("%06x"):format(h)
end

local myName
local function MyFullName()
  if myName then return myName end
  local name, realm
  if type(UnitFullName) == "function" then
    local ok, n, r = pcall(UnitFullName, "player")
    if ok then name, realm = n, r end
  end
  if not (type(name) == "string" and ns.Usable(name)) then return nil end
  if not (type(realm) == "string" and ns.Usable(realm) and realm ~= "") then
    realm = ns.Value(GetNormalizedRealmName) or ns.Value(GetRealmName)
    realm = type(realm) == "string" and realm:gsub("%s", "") or nil
  end
  if realm and realm ~= "" then myName = name .. "-" .. realm end
  return myName or name
end

local function FullSender(sender)
  if type(sender) ~= "string" or not ns.Usable(sender) or sender == "" then return nil end
  if sender:find("-", 1, true) then return sender end
  local me = MyFullName()
  local realm = me and me:match("%-(.+)$")
  return realm and (sender .. "-" .. realm) or sender
end

---------------------------------------------------------------------------
-- Lines: shape check, key (what the fact is about), value, count
---------------------------------------------------------------------------
local function Int(v, hi) v = tonumber(v) return v and v >= 0 and v < hi and v == math.floor(v) and v or nil end
local function Pos(v) v = tonumber(v) return v and v >= 0 and v <= 100 and v or nil end

-- Returns key, value, count, kind (or nil for a bad line).
-- value: what has to agree between reporters; positions are compared loosely.
local PARSE = {
  S = function(l)
    local q, m, x, y, npc, f = l:match("^S (%d+) (%d+) (%d+%.%d) (%d+%.%d) (%d+) ([AH%-])$")
    if not (Int(q, 1e6) and Int(m, 1e5) and Pos(x) and Pos(y) and Int(npc, 1e7)) then return nil end
    return "S " .. q, { m = tonumber(m), x = tonumber(x), y = tonumber(y), id = tonumber(npc), f = f }
  end,
  G = function(l)
    local q, m, x, y, obj, f = l:match("^G (%d+) (%d+) (%d+%.%d) (%d+%.%d) (%d+) ([AH%-])$")
    if not (Int(q, 1e6) and Int(m, 1e5) and Pos(x) and Pos(y) and Int(obj, 1e7)) then return nil end
    return "G " .. q, { m = tonumber(m), x = tonumber(x), y = tonumber(y), id = tonumber(obj), f = f }
  end,
  T = function(l)
    local q, m, x, y, npc = l:match("^T (%d+) (%d+) (%d+%.%d) (%d+%.%d) (%d+)$")
    if not (Int(q, 1e6) and Int(m, 1e5) and Pos(x) and Pos(y) and Int(npc, 1e7)) then return nil end
    return "T " .. q, { m = tonumber(m), x = tonumber(x), y = tonumber(y), id = tonumber(npc) }
  end,
  I = function(l)
    local q, item, f = l:match("^I (%d+) (%d+) ([AH%-])$")
    if not (Int(q, 1e6) and Int(item, 1e7)) then return nil end
    return "I " .. q, { v = item }
  end,
  O = function(l)
    local q, i, m, x, y = l:match("^O (%d+) (%d+) (%d+) (%d+%.%d) (%d+%.%d)$")
    if not (Int(q, 1e6) and Int(i, 21) and tonumber(i) >= 1 and Int(m, 1e5) and Pos(x) and Pos(y)) then return nil end
    -- one fact per spot: a grid of NEAR map units
    return ("O %s %s %s %d %d"):format(q, i, m, math.floor(tonumber(x) / NEAR), math.floor(tonumber(y) / NEAR)),
      { m = tonumber(m), x = tonumber(x), y = tonumber(y) }
  end,
  F = function(l)
    local q, prev, v = l:match("^F (%d+) (%d+) ([12])$")
    if not (Int(q, 1e6) and Int(prev, 1e6)) then return nil end
    return ("F %s %s"):format(q, prev), { v = "1" }, tonumber(v)
  end,
  K = function(l)
    local q, i, kind, id, n = l:match("^K (%d+) (%d+) ([coi]) (%d+) (%d+)$")
    if not (Int(q, 1e6) and Int(i, 21) and tonumber(i) >= 1 and Int(id, 1e7) and Int(n, 1e4)) then return nil end
    return ("K %s %s %s %s"):format(q, i, kind, id), { v = "1" }, tonumber(n)
  end,
  D = function(l)
    local item, kind, id, n, m, x, y = l:match("^D (%d+) ([co]) (%d+) (%d+) (%d+) (%d+%.%d) (%d+%.%d)$")
    if not (Int(item, 1e7) and Int(id, 1e7) and Int(n, 1e4) and Int(m, 1e5) and Pos(x) and Pos(y)) then return nil end
    return ("D %s %s %s"):format(item, kind, id), { v = "1" }, tonumber(n)
  end,
  A = function(l)
    local q, lv = l:match("^A (%d+) (%d+)$")
    if not (Int(q, 1e6) and Int(lv, 100) and tonumber(lv) >= 1) then return nil end
    return "A " .. q, { v = lv }
  end,
  X = function(l)
    local q = l:match("^X (%d+)$")
    if not Int(q, 1e6) then return nil end
    return "X " .. q, { v = "1" }
  end,
}

function ns.ParseShareLine(line)
  if type(line) ~= "string" or #line > 80 then return nil end
  local p = PARSE[line:sub(1, 1)]
  if not p then return nil end
  return p(line)
end
local Parse = ns.ParseShareLine

-- Two reports agree: same value, positions within NEAR map units on the same map.
local function Same(a, b)
  if a.v ~= b.v or a.id ~= b.id or a.f ~= b.f then return false end
  if a.m or b.m then
    if a.m ~= b.m then return false end
    if math.abs((a.x or 0) - (b.x or 0)) > NEAR or math.abs((a.y or 0) - (b.y or 0)) > NEAR then return false end
  end
  return true
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

---------------------------------------------------------------------------
-- Storing what others reported
---------------------------------------------------------------------------
local sharedCount
local function SharedCount()
  if not sharedCount then sharedCount = Count(DB().shared) end
  return sharedCount
end

-- Make room: facts with one reporter go first, oldest first.
local function Prune()
  local shared = DB().shared
  local list = {}
  for key, e in pairs(shared) do
    local best = 0
    for _, v in ipairs(type(e.v) == "table" and e.v or {}) do best = math.max(best, ns.Num(v.n) or 0) end
    list[#list + 1] = { key = key, n = best, t = ns.Num(e.t) or 0 }
  end
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n < b.n end return a.t < b.t end)
  local remove = #list - math.floor(MAX_SHARED * 0.9)
  for i = 1, math.max(remove, 0) do shared[list[i].key] = nil stats.pruned = stats.pruned + 1 end
  sharedCount = nil
end

local function Store(key, value, count, reporter)
  local shared = DB().shared
  local e = shared[key]
  if not e then
    if SharedCount() >= MAX_SHARED then Prune() end
    e = { v = {} }
    shared[key] = e
    sharedCount = (sharedCount or 0) + 1
  end
  e.t = Clock()
  if count and count > (ns.Num(e.c) or 0) then e.c = math.min(count, 9999) end
  for _, v in ipairs(e.v) do
    if Same(v, value) then
      if not v.r[reporter] and v.n < MAX_REPORTERS then
        v.r[reporter] = true
        v.n = v.n + 1
        version = version + 1
      end
      return
    end
  end
  if #e.v < MAX_VARIANTS then
    value.r, value.n = { [reporter] = true }, 1
    e.v[#e.v + 1] = value
    version = version + 1
  end
end

-- The variant most players reported, if CONFIRM or more did.
local function Best(e)
  if type(e) ~= "table" or type(e.v) ~= "table" then return nil end
  local best
  for _, v in ipairs(e.v) do
    if type(v) == "table" and (ns.Num(v.n) or 0) >= CONFIRM and (not best or v.n > best.n) then best = v end
  end
  return best
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Allowed(reporter, lines)
  local now = Now()
  local s = senders[reporter]
  if not s or now - s.t > 3600 then s = { t = now, n = 0 } senders[reporter] = s end
  if s.n >= PER_SENDER then return false end
  s.n = s.n + lines
  return true
end

local function OnMessage(_, prefix, text, chatType, sender)
  if prefix ~= PREFIX then return end
  if type(text) ~= "string" or not ns.Usable(text) or #text > 255 then return end
  local full = FullSender(sender)
  if not full then return end
  if full == MyFullName() then stats.own = stats.own + 1 return end
  local payload = text:match("^D1:%d+:(.+)$")
  if not payload then stats.bad = stats.bad + 1 return end
  stats.recvMsgs = stats.recvMsgs + 1
  local reporter = Hash(full)
  local lines = {}
  for line in payload:gmatch("[^;]+") do lines[#lines + 1] = line end
  if not Allowed(reporter, #lines) then stats.limited = stats.limited + #lines return end
  for _, line in ipairs(lines) do
    local key, value, count = Parse(line)
    if key then
      Store(key, value, count, reporter)
      stats.recvLines = stats.recvLines + 1
    else
      stats.bad = stats.bad + 1
    end
  end
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- Counters are sent again only at the next step.
-- Counters are sent again only at the next step (1, 5, 25, 100): the count only
-- weighs a source, its existence is what matters.
local STEPS = { 100, 25, 5, 1 }
local function Step(n)
  n = n or 0
  for _, s in ipairs(STEPS) do if n >= s then return s end end
  return 1
end

local function Signature(line, value, count)
  if count then return "c" .. Step(count) end
  return line
end

-- Everybody in the group is in the guild too: the guild message reaches them already.
local function GroupInGuild()
  if type(UnitIsInMyGuild) ~= "function" then return false end
  local raid = ns.True(ns.Value(IsInRaid))
  local n = ns.Num(ns.Value(GetNumGroupMembers)) or 0
  if n <= 1 then return false end
  for i = 1, raid and n or math.min(n - 1, 4) do
    local unit = (raid and "raid" or "party") .. i
    if ns.True(ns.Value(UnitExists, unit)) and not ns.True(ns.Value(UnitIsUnit, unit, "player"))
        and not ns.True(ns.Value(UnitIsInMyGuild, unit)) then
      return false
    end
  end
  return true
end

local function Channels()
  local list = {}
  local guild = ns.True(ns.Value(IsInGuild))
  if guild then list[#list + 1] = "GUILD" end
  if ns.True(ns.Value(IsInGroup)) and not (guild and GroupInGuild()) then
    local instance = LE_PARTY_CATEGORY_INSTANCE and ns.True(ns.Value(IsInGroup, LE_PARTY_CATEGORY_INSTANCE))
    list[#list + 1] = instance and "INSTANCE_CHAT" or (ns.True(ns.Value(IsInRaid)) and "RAID" or "PARTY")
  end
  return list
end

local function Register()
  if registered then return true end
  if not (C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function") then return false end
  local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  local code = ok and ns.Num(result)
  registered = ok and (result == true or result == nil or code == 0 or code == 1) or false
  return registered
end

local function SendTo(msg, channels)
  local any = false
  for _, ch in ipairs(channels) do
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    if ok and (result == nil or result == true or result == 0) then any = true else stats.blocked = stats.blocked + 1 end
  end
  return any
end

-- What is new to send: { {key, sig, line}, ... }
-- What is new to send: { {key, sig, line}, ... }. Left out (and marked as sent):
-- facts three or more others already reported the same way, and objective
-- spots beyond SPOTS_PER_OBJECTIVE per objective.
local function Pending()
  local sent = DB().shareSent
  local shared = DB().shared
  local list, spots = {}, {}
  for _, line in ipairs(ns.ExportRecords and ns.ExportRecords(false) or {}) do
    local key, value, count = Parse(line)
    if key then
      local sig = Signature(line, value, count)
      local skip = false
      if line:sub(1, 1) == "O" then
        local obj = line:match("^O (%d+ %d+) ")
        spots[obj] = (spots[obj] or 0) + 1
        skip = spots[obj] > SPOTS_PER_OBJECTIVE
      end
      if sent[key] ~= sig and not skip then
        local best = Best(shared[key])
        if best and best.n >= KNOWN and Same(best, value) then
          sent[key] = sig -- known well enough already
          stats.saved = stats.saved + 1
        else
          list[#list + 1] = { key, sig, line }
        end
      end
    end
  end
  return list
end

-- Messages sent within the last hour (session).
local sentTimes = {}
local function HourBudget()
  local now = Now()
  while sentTimes[1] and now - sentTimes[1] > 3600 do table.remove(sentTimes, 1) end
  return MAX_PER_HOUR - #sentTimes
end

function ns.ShareFlush()
  if not (ns.db and ns.db.shareLearned and ns.db.learnQuests) then return 0 end
  if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return 0 end
  if Locked() or ns.True(ns.Value(InCombatLockdown)) then stats.blocked = stats.blocked + 1 return 0 end
  local channels = Channels()
  if #channels == 0 or not Register() then return 0 end
  local budget = math.min(MAX_PER_FLUSH, HourBudget())
  if budget <= 0 then return 0 end
  local pending = Pending()
  local sent = DB().shareSent
  local msgs, i = 0, 1
  while i <= #pending and msgs < budget do
    seq = (seq + 1) % 1000
    local head = ("D1:%d:"):format(seq)
    local parts, used, size = {}, {}, #head
    while i <= #pending and size + #pending[i][3] + (#parts > 0 and 1 or 0) <= MAX_MSG do
      parts[#parts + 1] = pending[i][3]
      used[#used + 1] = pending[i]
      size = size + #pending[i][3] + (#parts > 1 and 1 or 0)
      i = i + 1
    end
    if #parts == 0 then i = i + 1 -- a line that never fits (cannot happen with export lines)
    elseif SendTo(head .. table.concat(parts, ";"), channels) then
      msgs = msgs + 1
      sentTimes[#sentTimes + 1] = Now()
      stats.sentMsgs = stats.sentMsgs + 1
      stats.sentFacts = stats.sentFacts + #used
      for _, p in ipairs(used) do sent[p[1]] = p[2] end
    else
      break
    end
  end
  return msgs
end

---------------------------------------------------------------------------
-- Using shared data
---------------------------------------------------------------------------
-- Turn-in point others reported: map, x, y (0-1), reporters.
function ns.SharedTurnIn(questID)
  local v = Best(ns.db and ns.db.shared and ns.db.shared["T " .. tostring(questID)])
  if v and v.m and v.x and v.y then return v.m, v.x / 100, v.y / 100, v.n end
end

-- Objective spots others reported (confirmed): { [index] = { map, x, y, ... } (0-1) }
local spotCache, spotVersion = nil, -1
function ns.SharedSpots(questID)
  if spotVersion ~= version or not spotCache then
    spotCache, spotVersion = {}, version
    for key, e in pairs(ns.db and ns.db.shared or {}) do
      local q, i
      if type(key) == "string" then q, i = key:match("^O (%d+) (%d+) ") end
      if q then
        local v = Best(e)
        if v and v.m then
          q, i = tonumber(q), tonumber(i)
          spotCache[q] = spotCache[q] or {}
          local list = spotCache[q][i] or {}
          spotCache[q][i] = list
          list[#list + 1] = v.m
          list[#list + 1] = v.x / 100
          list[#list + 1] = v.y / 100
        end
      end
    end
  end
  return spotCache[questID]
end

-- Own spots plus shared ones for a quest: { [index] = flat spots } or nil.
function ns.ObjectiveSpots(questID)
  local own = (ns.db.learnedObj or {})[questID]
  local shared = ns.SharedSpots(questID)
  if not shared then return own end
  local merged = {}
  for index, spots in pairs(own or {}) do merged[index] = spots end
  for index, spots in pairs(shared) do
    if merged[index] then
      local copy = {}
      for k = 1, #merged[index] do copy[k] = merged[index][k] end
      for k = 1, #spots do copy[#copy + 1] = spots[k] end
      merged[index] = copy
    else
      merged[index] = spots
    end
  end
  return merged
end

function ns.SharedVersion() return version end

---------------------------------------------------------------------------
-- Diagnostics, reset
---------------------------------------------------------------------------
function ns.ShareDiag()
  local shared = ns.db and ns.db.shared or {}
  local facts, confirmed = 0, 0
  for _, e in pairs(shared) do
    facts = facts + 1
    if Best(e) then confirmed = confirmed + 1 end
  end
  return ("%s, sent %d facts in %d messages (left out as known %d), received %d lines in %d messages (bad %d, limited %d, own %d), blocked %d, shared %d facts (confirmed %d), pruned %d"):format(
    ns.db and ns.db.shareLearned and "on" or "off", stats.sentFacts, stats.sentMsgs, stats.saved, stats.recvLines, stats.recvMsgs,
    stats.bad, stats.limited, stats.own, stats.blocked, facts, confirmed, stats.pruned)
end

function ns.ResetShared()
  local db = DB()
  wipe(db.shared)
  sharedCount, version = 0, version + 1
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.On("CHAT_MSG_ADDON", OnMessage)

local ticker
ns.OnInit(function()
  Register()
  -- every FLUSH_GAP seconds for the whole session (C_Timer.NewTicker repeats)
  if not ticker and C_Timer and type(C_Timer.NewTicker) == "function" then
    ticker = C_Timer.NewTicker(FLUSH_GAP, function() ns.SafeCall("share", ns.ShareFlush) end)
  end
end)
