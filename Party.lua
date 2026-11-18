local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.18) Quest progress of the group. Questdon players in a party (at most
-- five players, also in instance groups) send each other the state of their
-- quest log with hidden addon messages: quest IDs, complete/failed and the
-- objective counters. Nothing else, no names in the payload.
--
--   "R1"                         please send me your state
--   "A1:<questID>"               (12.11.2026) I wrote the party chat line for this quest (Announce.lua)
--   "S1:<seq>:<i>:<n>:<payload>" part i of n of a full state, payload:
--                                id,state,f/r,f/r;id,state,...  (state 0 open, 1 complete, 2 failed)
--
-- Every state is complete: it replaces the sender's previous one, so quests
-- turned in or abandoned disappear at once. Members who leave the group are
-- dropped, leaving the group drops everything. States are kept in memory
-- only, never saved. Sending: only on change, at most every SEND_GAP
-- seconds, never while the client blocks addon messages (Midnight rules:
-- C_ChatInfo.InChatMessagingLockdown), then later.
---------------------------------------------------------------------------
local PREFIX = "Questdon"
local MAX_PART = 200        -- payload characters per message (limit 255 with header)
local MAX_GROUP = 5
local SEND_GAP = 3          -- seconds between two states
local MAX_QUESTS = 35       -- per member, more is ignored
local MAX_PARTS = 8

local members = {}          -- [name] = { quests = { [id] = { state, { {f, r}, ... } } }, at = time }
local incoming = {}         -- [name] = { seq, n, parts = {} }
local lastSent, lastSendAt, sendQueued, force = nil, -100, false, false
local seq = 0
local stats = { sent = 0, received = 0, requests = 0, blocked = 0, dropped = 0 }
local registered = false

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

local function Enabled() return ns.db and ns.db.partyProgress end

local function GroupSize()
  return ns.Num(ns.Value(GetNumGroupMembers)) or 0
end

-- Channel for the group, nil when not in a small group.
local function Channel()
  if not ns.True(ns.Value(IsInGroup)) then return nil end
  local size = GroupSize()
  if size > MAX_GROUP or ns.True(ns.Value(IsInRaid)) then return nil end
  local instance = LE_PARTY_CATEGORY_INSTANCE and ns.True(ns.Value(IsInGroup, LE_PARTY_CATEGORY_INSTANCE))
  return instance and "INSTANCE_CHAT" or "PARTY"
end
ns.PartyChannel = Channel

local function Locked()
  local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn)
  if not ok or v == nil then return false end
  return not ns.Usable(v) or v == true -- unreadable: better wait
end
ns.PartyLocked = Locked -- (12.11.2026) Announce.lua

-- Name as the roster shows it: "Name" on the own realm, "Name-Realm" else.
local function Short(name)
  if type(name) ~= "string" or not ns.Usable(name) or name == "" then return nil end
  if type(Ambiguate) == "function" then
    local ok, n = pcall(Ambiguate, name, "none")
    if ok and type(n) == "string" and ns.Usable(n) and n ~= "" then return n end
  end
  local realm = ns.Value(GetNormalizedRealmName)
  if type(realm) == "string" and ns.Usable(realm) and realm ~= "" then
    local base, r = name:match("^(.-)%-(.+)$")
    if base and r == realm then return base end
  end
  return name
end

local function UnitFullName(unit)
  -- (05.11.2026) Forever: "Mae Wipeborn" as the senders say it (GetUnitName would give "Mae-Wipeborn")
  if ns.Surnames() then return Short(ns.UnitNameRealm(unit)) end
  local fn = GetUnitName
  if type(fn) == "function" then
    local n = ns.Value(fn, unit, true)
    if type(n) == "string" and n ~= "" then return Short(n) end
  end
  local n, realm = nil, nil
  local ok, a, b = pcall(UnitName, unit)
  if ok then n, realm = a, b end
  if type(n) ~= "string" or not ns.Usable(n) or n == "" then return nil end
  if type(realm) == "string" and ns.Usable(realm) and realm ~= "" then n = n .. "-" .. realm end
  return Short(n)
end

-- (12.11.2026, Daniel: "Partyabgleich in Klassenfarben der Spieler und nur den Vornamen, das muss dann kurz gehalten
-- werden") the class of each member, read with the roster; shown names are the first name in the class colour
local classOf = {}
local function NoteClass(unit, name)
  local ok, _, class = pcall(UnitClass, unit)
  if ok and type(class) == "string" and ns.Usable(class) and class ~= "" then classOf[name] = class end
end

local function Roster()
  local set = {}
  if not ns.True(ns.Value(IsInGroup)) then return set end
  local raid = ns.True(ns.Value(IsInRaid))
  local n = GroupSize()
  for i = 1, raid and n or math.max(n - 1, 0) do
    local unit = (raid and "raid" or "party") .. i
    local name = UnitFullName(unit)
    if name then set[name] = true NoteClass(unit, name) end
  end
  return set
end

-- "Mae Wipeborn" (Forever) and "Tova-Realm" become "Mae" and "Tova".
function ns.PartyFirstName(name)
  if type(name) ~= "string" or not ns.Usable(name) then return "?" end
  return name:match("^([^%s%-]+)") or name
end
-- The first name in the member's class colour (plain while the class is unknown).
function ns.PartyNameText(name)
  local first = ns.PartyFirstName(name)
  local class = classOf[name]
  if not class then return first end
  local K = LibStub and LibStub("DonCore-1.0", true)
  K = K and K.Get and K:Get("Kit", 16)
  if K and K.ClassText then return K.ClassText(class, first) end
  return first
end
function ns.PartyMyName() return UnitFullName("player") end

---------------------------------------------------------------------------
-- Own state
---------------------------------------------------------------------------
function ns.PartyStateString()
  local entries = {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    local id = info.questID
    if #entries >= MAX_QUESTS then break end
    local state = ns.IsQuestFailed(id) and 2 or ns.IsQuestComplete(id) and 1 or 0
    local parts = { tostring(id), tostring(state) }
    for _, o in ipairs(ns.ClientObjectives(id)) do
      local f, r = 0, 1
      if type(o) == "table" then
        local nf, nr = ns.Num(o.numFulfilled), ns.Num(o.numRequired)
        if nf and nr and nr > 0 then
          f, r = math.max(0, math.min(nf, 9999)), math.min(nr, 9999)
        elseif ns.True(o.finished) then
          f = 1
        end
      end
      parts[#parts + 1] = ("%d/%d"):format(f, r)
    end
    entries[#entries + 1] = table.concat(parts, ",")
  end
  table.sort(entries)
  return table.concat(entries, ";")
end

local Send
-- (12.11.2026) Announce.lua: "A1:<questID>", I told the group about this quest (the others stay silent)
function ns.PartySend(msg)
  if not (ns.db and ns.db.partyProgress and registered) then return false end
  local channel = Channel()
  if not channel or Locked() then return false end
  return Send(msg, channel)
end
function Send(msg, channel, target)
  if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return false end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
  if not ok then return false end
  -- modern clients return a result code (0 = success), older ones nothing
  local code = ns.Num(result)
  if code and code ~= 0 then stats.blocked = stats.blocked + 1 return false end
  return true
end

local SendState
local function Queue(delay)
  if sendQueued then return end
  sendQueued = true
  ns.After(delay or 1, function()
    sendQueued = false
    SendState()
  end)
end

-- Sends the own state if it changed (or force), throttled.
function SendState()
  if not (Enabled() and registered) then return end
  local channel = Channel()
  if not channel then return end
  local wait = lastSendAt + SEND_GAP - Now()
  if wait > SEND_GAP then wait = 0 end -- clock went back (or unreadable): do not wait forever
  if wait > 0 then Queue(wait) return end
  if Locked() then stats.blocked = stats.blocked + 1 Queue(5) return end
  local state = ns.PartyStateString()
  if state == lastSent and not force then return end
  local chunks = {}
  local pos = 1
  repeat
    chunks[#chunks + 1] = state:sub(pos, pos + MAX_PART - 1)
    pos = pos + MAX_PART
  until pos > #state or #chunks >= MAX_PARTS
  seq = (seq % 999) + 1
  for i, chunk in ipairs(chunks) do
    if not Send(("S1:%d:%d:%d:%s"):format(seq, i, #chunks, chunk), channel) then Queue(5) return end
  end
  stats.sent = stats.sent + 1
  lastSent, lastSendAt, force = state, Now(), false
end

local requestAt = -100
local function Request()
  if not (Enabled() and registered) then return end
  local channel = Channel()
  local since = Now() - requestAt
  if not channel or (since >= 0 and since < 10) or Locked() then return end
  if Send("R1", channel) then requestAt = Now() end
end

---------------------------------------------------------------------------
-- Other members
---------------------------------------------------------------------------
local function Parse(payload)
  local quests, n = {}, 0
  for entry in payload:gmatch("[^;]+") do
    local fields = {}
    for v in entry:gmatch("[^,]+") do fields[#fields + 1] = v end
    local id, state = tonumber(fields[1]), tonumber(fields[2])
    if id and id > 0 and id == math.floor(id) and (state == 0 or state == 1 or state == 2) then
      local objs = {}
      for i = 3, #fields do
        local f, r = fields[i]:match("^(%d+)/(%d+)$")
        objs[#objs + 1] = { tonumber(f) or 0, tonumber(r) or 1 }
      end
      n = n + 1
      if n > MAX_QUESTS then break end
      quests[id] = { state, objs }
    end
  end
  return quests
end

local refreshQueued = false
ns.partyGen = 0 -- (12.11.2026) counts every change of the group's data: part of the quest list's signature
local gameCache -- (12.11.2026) the game's own data, read below
local function Changed()
  ns.partyGen = ns.partyGen + 1
  if gameCache and next(gameCache) then wipe(gameCache) end
  if refreshQueued then return end
  refreshQueued = true
  ns.After(0.5, function()
    refreshQueued = false
    if ns.RefreshPinsIfChanged then ns.RefreshPinsIfChanged() end
    if ns.UpdateTracker then ns.UpdateTracker() end -- (12.11.2026) the group line of the quest card (signature: partyGen)
    if ns.RefreshPartyQuestTooltip then ns.RefreshPartyQuestTooltip() end
  end)
end

-- Optional sharing-status extension. Older Questdon clients ignore H2/J2.
-- H2:<request>:<questID> asks the party; J2:<request>:<questID>:<state>
-- replies by whisper. No history lists, names or quest text are transmitted.
local SHARE_AGE, SHARE_WAIT = 10, 3
local sharing = { pending = {}, replies = {}, inbound = {}, seen = {}, serial = math.random(1, 999999), lastQuery = -100 }

local function ResetSharing()
  wipe(sharing.pending) wipe(sharing.replies) wipe(sharing.inbound)
  wipe(sharing.seen)
  sharing.lastQuery = -100
end

local function ShareNumber(text)
  local n = tonumber(text)
  return n and n > 0 and n <= 2147483647 and n == math.floor(n) and n or nil
end

-- The recipient checks its own character. Data requirements are a preflight,
-- not a promise that the server will accept a share.
local function OwnSharingState(questID)
  if ns.Value(ns.InQuestLog, questID) == true then
    if ns.Value(ns.IsQuestFailed, questID) == true then return "F" end
    return ns.Value(ns.IsQuestComplete, questID) == true and "R" or "A"
  end
  local ql = ns.QL or C_QuestLog
  local done = ql and ns.Value(ql.IsQuestFlaggedCompleted, questID)
  if done ~= true then done = ns.Value(ns.IsQuestDone, questID) end
  if done == true then
    return ns.Value(ns.IsRepeatableQuest, questID) == true and "P" or "C"
  end
  if ns.Value(ns.QuestLogFull) == true then return "L" end
  if ns.Value(ns.QuestInData, questID) ~= true then return "U" end
  local eligible = ns.Value(ns.DataCanTakeQuest, questID)
  if eligible == true then return "E" end
  if eligible == false then return "B" end
  return "U"
end

local function RequestSharing(questID)
  if not (Enabled() and registered and Channel()) or Locked() then return end
  if not ShareNumber(questID) or ns.Value(ns.InQuestLog, questID) ~= true then return end
  local now = Now()
  local pending = sharing.pending[questID]
  if pending and now >= pending.at and now - pending.at < SHARE_AGE then return end
  local since = now - sharing.lastQuery
  if since >= 0 and since < 1 then return end
  local count = 0
  for id, request in pairs(sharing.pending) do
    if now < request.at or now - request.at >= SHARE_AGE or ns.Value(ns.InQuestLog, id) ~= true then
      sharing.pending[id] = nil
      for _, replies in pairs(sharing.replies) do replies[id] = nil end
    else count = count + 1 end
  end
  if count >= MAX_QUESTS then return end
  sharing.serial = sharing.serial % 2147483647 + 1
  if Send(("H2:%d:%d"):format(sharing.serial, questID), Channel()) then
    local request = { token = sharing.serial, at = now }
    sharing.pending[questID] = request
    sharing.lastQuery = now
    ns.After(SHARE_WAIT, function()
      if sharing.pending[questID] == request and Enabled() and Channel() then Changed() end
    end)
  end
end

local function OnSharingMessage(name, text, channel, sender)
  if text:sub(1, 3) ~= "H2:" and text:sub(1, 3) ~= "J2:" then return false end
  if not (registered and Channel()) or Locked() or #text > 80 then return true end
  local token, id = text:match("^H2:(%d+):(%d+)$")
  token, id = ShareNumber(token), ShareNumber(id)
  local now = Now()
  if token and id then
    if channel ~= Channel() then return true end
    local last = sharing.inbound[name]
    if last and now >= last and now - last < 1 then return true end
    sharing.inbound[name] = now
    sharing.seen[name] = true
    local state = OwnSharingState(id)
    Send(("J2:%d:%d:%s"):format(token, id, state), "WHISPER", sender)
    if state == "A" or state == "R" or state == "F" then force = true Queue(1) end
    return true
  end
  local state
  token, id, state = text:match("^J2:(%d+):(%d+):([ARFCEBLUP])$")
  token, id = ShareNumber(token), ShareNumber(id)
  local pending = id and sharing.pending[id]
  if channel ~= "WHISPER" or not token or not pending or token ~= pending.token
      or now < pending.at or now - pending.at >= SHARE_AGE or ns.Value(ns.InQuestLog, id) ~= true then return true end
  sharing.replies[name] = sharing.replies[name] or {}
  sharing.replies[name][id] = { state = state, at = now }
  sharing.seen[name] = true
  Changed()
  return true
end

-- A silent client may have no addon, a disabled addon or blocked messages.
-- Only show this after waiting, and never hide available native progress.
local function MissingProgressText(name, questID)
  if members[name] or sharing.seen[name] then return nil end
  local pending, now = sharing.pending[questID], Now()
  if pending and now >= pending.at and now - pending.at >= SHARE_WAIT then
    return L["Questdon not detected or not responding; progress unavailable"]
  end
end

local function SharingText(name, questID, pushable)
  local reply = sharing.replies[name] and sharing.replies[name][questID]
  local now = Now()
  if reply and now >= reply.at and now - reply.at < SHARE_AGE then
    local state = reply.state
    if state == "C" then return L["Already completed"], "good" end
    if state == "P" then return L["Completed before; repeatable"], "textHint" end
    if state == "B" then return L["Quest requirements not met"], "critical" end
    if state == "L" then return L["Quest log full"], "critical" end
    if state == "R" then return L["Ready to turn in"], "good" end
    if state == "F" then return L["failed"], "critical" end
    if state == "A" then return L["in log"], "textPrimary" end
    if state == "E" then
      if pushable == false then return L["Quest cannot be shared"], "textHint" end
      if pushable == true then return L["Can share; known requirements met"], "good" end
      return L["Requirements met; shareability unknown"], "textHint"
    end
  end
  local pending = sharing.pending[questID]
  if not reply and pending and now >= pending.at and now - pending.at < SHARE_WAIT then
    return L["Checking sharing eligibility..."], "textHint"
  end
end

local function OnMessage(_, prefix, text, channel, sender)
  if prefix ~= PREFIX or not Enabled() then return end
  if type(text) ~= "string" or not ns.Usable(text) then return end
  local name = Short(sender)
  if not name or name == UnitFullName("player") then return end
  if not Roster()[name] then stats.dropped = stats.dropped + 1 return end
  if OnSharingMessage(name, text, channel, sender) then return end
  if text == "R1" then
    stats.requests = stats.requests + 1
    force = true
    Queue(1 + math.random() * 2) -- spread the answers of several members
    return
  end
  local told = text:match("^A1:(%d+)$")
  if told then
    if ns.AnnounceHeard then ns.AnnounceHeard(tonumber(told), name) end
    return
  end
  local s, i, n, payload = text:match("^S1:(%d+):(%d+):(%d+):(.*)$")
  s, i, n = tonumber(s), tonumber(i), tonumber(n)
  if not (s and i and n) or i < 1 or n < 1 or i > n or n > MAX_PARTS then stats.dropped = stats.dropped + 1 return end
  local buf = incoming[name]
  if not buf or buf.seq ~= s or buf.n ~= n then
    buf = { seq = s, n = n, parts = {}, count = 0 }
    incoming[name] = buf
  end
  if not buf.parts[i] then
    buf.parts[i] = payload
    buf.count = buf.count + 1
  end
  if buf.count == n then
    incoming[name] = nil
    -- (12.11.2026) when a quest of the member became complete (third field), for the one chat line of several players
    local old, quests = members[name], Parse(table.concat(buf.parts, "", 1, n))
    if old then
      for id, q in pairs(quests) do
        if q[1] == 1 then
          local o = old.quests[id]
          if o and o[1] == 1 then q[3] = o[3] else q[3] = Now() end
        end
      end
    end
    members[name] = { quests = quests, at = Now() }
    stats.received = stats.received + 1
    Changed()
  end
end

local function Prune()
  if not ns.True(ns.Value(IsInGroup)) or not Channel() then
    if next(members) or next(incoming) then wipe(members) wipe(incoming) Changed() end
    lastSent = nil
    return
  end
  local roster = Roster()
  local changed = false
  for name in pairs(members) do
    if not roster[name] then members[name] = nil changed = true end
  end
  for name in pairs(incoming) do
    if not roster[name] then incoming[name] = nil end
  end
  if changed then Changed() end
  return roster
end

---------------------------------------------------------------------------
-- Reading (tooltips, panel, dungeon hints, API)
---------------------------------------------------------------------------
local function SortedNames()
  local names = {}
  for name in pairs(members) do names[#names + 1] = name end
  table.sort(names)
  return names
end

---------------------------------------------------------------------------
-- (12.11.2026, Daniel: "blizzard zeigt in den tooltips jetzt auch an, wie weit wer mit der quest ist. koennen wir uns
-- das nicht zu eigen machen?") The game's own data: C_TooltipInfo.GetQuestPartyProgress(questID, omitTitle,
-- ignoreActivePlayer) gives the lines of the game's tooltip (a QuestPlayer line per member, then its QuestObjective
-- lines with "... 3/8" and completed), for every member, with or without Questdon. Read only for quests of your own
-- log (the game shows it there), at most every 2 seconds per quest. Members who sent their state with Questdon keep
-- that (it also knows failed quests); the game fills in the others.
---------------------------------------------------------------------------
local GAME_AGE = 2
gameCache = {} -- [questID] = { at = time, list = { { shown, objectives, complete }, ... } }
local function Plain(text)
  if type(text) ~= "string" or not ns.Usable(text) then return nil end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return text ~= "" and text or nil
end
local function GameLines(questID)
  local fn = C_TooltipInfo and C_TooltipInfo.GetQuestPartyProgress
  if type(fn) ~= "function" then return nil end
  local ok, data = pcall(fn, questID, true, true)
  if not ok or type(data) ~= "table" or not ns.Usable(data) or type(data.lines) ~= "table" then return nil end
  return data.lines
end
-- (15.11.2026, Daniel to "[Down the Coast] is ready to turn in. Still open: Valentinos 0/1" for a quest with two
-- kill counters that Valentinos had finished too: "Er hatte die quest auch fertig, das irritiert") for a member who
-- is done the game writes one line of text instead of the objectives (no counter, no tick). Such a line was read as
-- an open objective "0/1". A line without numbers and without a tick is an objective only if it is one of the
-- objectives of your own log; otherwise it is the member's state: done (or failed).
local function Norm(text)
  text = Plain(text)
  text = text and text:gsub("^[%-%s]+", ""):lower()
  return text ~= "" and text or nil
end
local function OwnObjectiveTexts(questID)
  local set = {}
  for _, o in ipairs(ns.ClientObjectives and ns.ClientObjectives(questID) or {}) do
    local t = type(o) == "table" and Norm(o.text)
    if t then set[t] = true end
  end
  return set
end
local function GameProgress(questID)
  local now = Now()
  local c = gameCache[questID]
  if c and now - c.at >= 0 and now - c.at < GAME_AGE then return c.list end
  local list = {}
  local lines = GameLines(questID)
  if lines then
    local own
    local T = type(Enum) == "table" and Enum.TooltipDataLineType or nil
    local PLAYER, OBJECTIVE = T and T.QuestPlayer or 18, T and T.QuestObjective or 8
    local cur
    for _, line in ipairs(lines) do
      if type(line) == "table" then
        local text = Plain(line.leftText)
        if line.type == PLAYER and text then
          cur = { shown = text, objectives = {} }
          list[#list + 1] = cur
        elseif line.type == OBJECTIVE and cur then
          local f, r = (text or ""):match("(%d+)%s*/%s*(%d+)")
          f, r = tonumber(f), tonumber(r)
          local done = line.completed == true
          local key = Norm(text)
          if not (f and r and r > 0) and not done and key then
            own = own or OwnObjectiveTexts(questID)
            if not own[key] then
              cur.state = (type(FAILED) == "string" and key:find(FAILED:lower(), 1, true)) and "failed" or "done"
              key = false
            end
          end
          if key ~= false then
            if not (f and r and r > 0) then f, r = done and 1 or 0, 1 end
            if done and f < r then f = r end
            cur.objectives[#cur.objectives + 1] = { math.min(f, 9999), math.min(r, 9999) }
          end
        end
      end
    end
    for _, m in ipairs(list) do
      m.complete = #m.objectives > 0
      for _, o in ipairs(m.objectives) do if o[1] < o[2] then m.complete = false end end
      -- only the state line, no objective: the member is done (or failed)
      if #m.objectives == 0 and m.state then m.complete, m.failed = m.state == "done", m.state == "failed" end
    end
  end
  gameCache[questID] = { at = now, list = list }
  return list
end
-- The roster's name for a name as the game's tooltip writes it (the same, or the same first name).
local function RosterName(shown, roster)
  local short = Short(shown) or shown
  if roster[short] then return short end
  local first = ns.PartyFirstName(short)
  for name in pairs(roster) do if ns.PartyFirstName(name) == first then return name end end
  return short
end

-- { { name, text, complete, failed, objectives = { {fulfilled, required}, ... }, doneAt, source }, ... }
-- source: "questdon" (the member's addon sent it) or "game".
function ns.PartyProgress(questID)
  local out = {}
  if not Enabled() then return out end
  local have = {}
  if next(members) ~= nil then -- (1.23) no group data: nothing to sort
    for _, name in ipairs(SortedNames()) do
      local q = members[name].quests[questID]
      have[name] = true
      if q then
        local objs = {}
        for i, o in ipairs(q[2]) do objs[i] = { o[1], o[2] } end
        out[#out + 1] = { name = name, text = ns.PartyNameText(name), complete = q[1] == 1, failed = q[1] == 2,
          objectives = objs, doneAt = q[3], source = "questdon" }
      end
    end
  end
  -- the game's data for the members without Questdon
  if Channel() and ns.InQuestLog and ns.InQuestLog(questID) then
    local list = GameProgress(questID)
    if #list > 0 then
      local roster, me, added = Roster(), UnitFullName("player"), false
      for _, m in ipairs(list) do
        local name = RosterName(m.shown, roster)
        if not have[name] and name ~= me then
          have[name] = true
          local objs = {}
          for i, o in ipairs(m.objectives) do objs[i] = { o[1], o[2] } end
          out[#out + 1] = { name = name, text = ns.PartyNameText(name), complete = m.complete, failed = m.failed == true,
            objectives = objs, source = "game" }
          added = true
        end
      end
      if added then table.sort(out, function(a, b) return a.name < b.name end) end
    end
  end
  return out
end

-- Whether another member of the group has the quest, as far as the game or Questdon know: true, false, or nil
-- (nobody can say: no such function in this client and not every member sent a state).
function ns.PartyAnyoneOnQuest(questID)
  if #ns.PartyProgress(questID) > 0 then return true end
  local fn = C_QuestLog and C_QuestLog.IsUnitOnQuest
  local others = math.max(GroupSize() - 1, 0)
  if type(fn) == "function" and others > 0 then
    local read = 0
    for i = 1, others do
      local ok, on = pcall(fn, "party" .. i, questID)
      if ok and ns.Usable(on) and type(on) == "boolean" then
        if on then return true end
        read = read + 1
      end
    end
    if read >= others then return false end
  end
  if others > 0 and ns.PartyMemberCount() >= others then return false end
  return nil
end

-- /qd group raw: what the game says about the group's progress, as it comes (to check the reading above).
function ns.PartyRaw()
  local n = 0
  for _, info in ipairs(ns.QuestLogEntries()) do
    local lines = GameLines(info.questID)
    local on = {}
    local fn = C_QuestLog and C_QuestLog.IsUnitOnQuest
    for i = 1, math.max(GroupSize() - 1, 0) do
      local ok, v = false, nil
      if type(fn) == "function" then ok, v = pcall(fn, "party" .. i, info.questID) end
      on[#on + 1] = "party" .. i .. "=" .. tostring(ok and v)
    end
    print(("|cffffd100Questdon|r %d %s: %s, lines %s"):format(info.questID, tostring(info.title), table.concat(on, " "),
      lines and tostring(#lines) or "none"))
    for _, line in ipairs(lines or {}) do
      if type(line) == "table" then
        n = n + 1
        print(("   type %s | %s | completed %s"):format(tostring(line.type), tostring(line.leftText), tostring(line.completed)))
      end
    end
  end
  print(("|cffffd100Questdon|r group raw: %d lines, API %s"):format(n,
    tostring(C_TooltipInfo and type(C_TooltipInfo.GetQuestPartyProgress) == "function")))
end

-- Names of the members who have the quest in their log.
function ns.PartyMembersWithQuest(questID)
  local out = {}
  for _, p in ipairs(ns.PartyProgress(questID)) do out[#out + 1] = p.name end
  return out
end

-- (12.11.2026) The same as shown: first names in class colours.
function ns.PartyNamesText(questID)
  local out = {}
  for _, p in ipairs(ns.PartyProgress(questID)) do out[#out + 1] = p.text end
  return out
end

-- (1.28) Set of all quest IDs any member has: { [questID] = true } (empty when
-- group progress is off or nobody sent data).
function ns.PartyQuestSet()
  local set = {}
  if not Enabled() then return set end
  for _, m in pairs(members) do
    for id in pairs(m.quests) do set[id] = true end
  end
  return set
end

function ns.PartyMemberCount()
  if not Enabled() then return 0 end
  local n = 0
  for _ in pairs(members) do n = n + 1 end
  return n
end

-- Short text of one member's state: "3/8, 0/1", "done" or "failed".
function ns.PartyStateText(p)
  if p.failed then return L["failed"] end
  if p.complete then return L["done"] end
  local parts = {}
  for _, o in ipairs(p.objectives) do parts[#parts + 1] = ns.Fraction(o[1], o[2]) end
  return #parts > 0 and table.concat(parts, ", ") or L["in log"]
end

-- All party members, including those without the quest. Preserve the game's
-- sharing/completion explanations; absence from a quest log proves neither.
function ns.PartyQuestTooltipLines(questID)
  local out = {}
  if not Enabled() or not Channel() then return out end
  RequestSharing(questID)
  local roster, units, guids, names = Roster(), {}, {}, {}
  for i = 1, math.max(GroupSize() - 1, 0) do
    local unit = "party" .. i
    local name = UnitFullName(unit)
    if name and roster[name] then
      units[name] = unit
      local guid = ns.Value(UnitGUID, unit)
      if type(guid) == "string" and ns.Usable(guid) then guids[guid] = name end
    end
  end
  for name in pairs(roster) do names[#names + 1] = name end
  table.sort(names)
  local progress = {}
  for _, p in ipairs(ns.PartyProgress(questID)) do progress[p.name] = p end
  local native, current = {}, nil
  local T = type(Enum) == "table" and Enum.TooltipDataLineType or nil
  local PLAYER, OBJECTIVE = T and T.QuestPlayer or 18, T and T.QuestObjective or 8
  for _, line in ipairs(GameLines(questID) or {}) do
    if type(line) == "table" and ns.Usable(line) then
      if line.type == PLAYER then
        local shown = Plain(line.leftText)
        local guid = ns.Usable(line.guid) and line.guid
        local name = (guid and guids[guid]) or (shown and RosterName(shown, roster))
        current = name and roster[name] and { status = Plain(line.rightText), details = {}, objectives = {} } or nil
        if current then native[name] = current end
      elseif current then
        local left, right = Plain(line.leftText), Plain(line.rightText)
        if left or right then
          local target = line.type == OBJECTIVE and current.objectives or current.details
          target[#target + 1] = { left or "", right }
          if line.type == OBJECTIVE and (left or ""):match("%d+%s*/%s*%d+") then current.counted = true end
        end
      end
    end
  end
  local pushable = C_QuestLog and ns.Value(C_QuestLog.IsPushableQuest, questID)
  for _, name in ipairs(names) do
    local p, game, unit = progress[name], native[name], units[name]
    local state, color
    local connected = unit and ns.Value(UnitIsConnected, unit)
    local onQuest = C_QuestLog and unit and ns.Value(C_QuestLog.IsUnitOnQuest, unit, questID)
    local active = p and (p.source == "questdon" or (onQuest ~= false and (onQuest == true or (game and game.counted))))
    local shared, sharedColor = SharingText(name, questID, pushable)
    if connected == false then
      state, color = L["Offline"], "textHint"
    elseif active then
      state = p.complete and L["Ready to turn in"] or ns.PartyStateText(p)
      color = p.complete and "good" or p.failed and "critical" or "textPrimary"
    elseif shared and shared ~= L["Checking sharing eligibility..."] then
      state, color = shared, sharedColor
    elseif game and (game.status or #game.details > 0 or #game.objectives > 0) then
      state = game.status or ""
    else
      if onQuest == true then state = L["in log"]
      elseif shared then state = shared
      elseif pushable == false then state = L["Quest cannot be shared"]
      elseif onQuest == false or (members[name] and not members[name].quests[questID]) then
        state = L["Not in log; sharing eligibility unknown"]
      else state = L["Quest status unknown"] end
      color = "textHint"
    end
    out[#out + 1] = { ns.PartyNameText(name), state, color }
    local nativeInfo = game and (game.status or #game.details > 0 or #game.objectives > 0)
    local unavailable = not active and not nativeInfo and connected ~= false and MissingProgressText(name, questID)
    if unavailable then out[#out + 1] = { "  " .. unavailable } end
    if game and connected ~= false then
      if game.status and game.status ~= state then out[#out + 1] = { "  " .. game.status } end
      for _, detail in ipairs(game.details) do out[#out + 1] = { "  " .. detail[1], detail[2] } end
      if not active then
        for _, detail in ipairs(game.objectives) do out[#out + 1] = { "  " .. detail[1], detail[2] } end
      end
    end
  end
  if #out > 0 then table.insert(out, 1, { header = L["Group progress"] }) end
  return out
end

-- (12.11.2026) One short word for a member's state: "done", "failed", or all counters as one "5/8".
-- plain: for the chat ("5/8" as typed, no thin spaces).
function ns.PartyShortState(p, plain)
  if p.failed then return L["failed"] end
  if p.complete then return L["done"] end
  local f, r = 0, 0
  for _, o in ipairs(p.objectives) do f, r = f + math.min(o[1], o[2]), r + o[2] end
  if r <= 0 then return L["in log"] end
  return plain and ("%d/%d"):format(f, r) or ns.Fraction(f, r)
end
-- The members with a quest in one short line: "Mae 5/8  Tova done" (class colours), nil if none.
-- plain: "Mae 5/8, Tova done" without colours, for the chat; openOnly: only who is not done.
function ns.PartyQuestLine(questID, plain, openOnly)
  local parts = {}
  for _, p in ipairs(ns.PartyProgress(questID)) do
    if not (openOnly and p.complete) then
      parts[#parts + 1] = (plain and ns.PartyFirstName(p.name) or p.text) .. " " .. ns.PartyShortState(p, plain)
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, plain and ", " or "  ")
end

-- For the panel: quests in your log that members have too, and quests members
-- have that you could pick up. { shared = { questIDs }, takeable = { questIDs } }
function ns.PartyOverview()
  local shared, takeable, seen = {}, {}, {}
  if ns.PartyMemberCount() == 0 then return { shared = shared, takeable = takeable } end
  local log = {}
  for _, info in ipairs(ns.QuestLogEntries()) do log[info.questID] = true end
  for _, name in ipairs(SortedNames()) do
    for id in pairs(members[name].quests) do
      if not seen[id] then
        seen[id] = true
        if log[id] then
          shared[#shared + 1] = id
        elseif not ns.IsQuestDone(id) and not ns.QuestKnownMissing(id)
            and (not (ns.ATT_QUESTS and ns.ATT_QUESTS[id]) or ns.CanTakeQuest(id)) then
          takeable[#takeable + 1] = id
        end
      end
    end
  end
  table.sort(shared)
  table.sort(takeable)
  return { shared = shared, takeable = takeable }
end

-- Tooltip lines of a mob for the members: { {name, progress}, ... } of the
-- members whose objective <index> of the quest is still open.
function ns.PartyObjectiveLines(questID, index)
  local out = {}
  for _, p in ipairs(ns.PartyProgress(questID)) do
    local o = p.objectives[index]
    if not p.complete and not p.failed and o and o[1] < o[2] then
      out[#out + 1] = { p.text, ns.Fraction(o[1], o[2]) }
    end
  end
  return out
end

-- /qd group: shared quests and progress in the chat.
function ns.PrintParty()
  if not Enabled() then ns.Print(L["Group progress is off (options: Quests and automation)."]) return end
  if ns.PartyMemberCount() == 0 then
    ns.Print(L["No group member with Questdon has sent quest progress yet."])
    return
  end
  local po = ns.PartyOverview()
  ns.Print(L["Group: %d shared quests, %d to pick up"]:format(#po.shared, #po.takeable))
  for _, id in ipairs(po.shared) do
    local parts = { L["%s %s (player and quest state)"]:format(L["You"], ns.IsQuestComplete(id) and L["done"] or ns.QuestProgressText and ns.QuestProgressText(id) or L["in log"]) }
    for _, p in ipairs(ns.PartyProgress(id)) do parts[#parts + 1] = L["%s %s (player and quest state)"]:format(p.text, ns.PartyStateText(p)) end
    ns.Print("  " .. ns.QuestTitle(id) .. L[": "] .. table.concat(parts, ", "))
  end
  for _, id in ipairs(po.takeable) do
    ns.Print("  " .. L["To pick up: %s (%s)"]:format(ns.QuestTitle(id), table.concat(ns.PartyNamesText(id), ", ")))
  end
end

-- For /qd diag: only counts.
function ns.PartyDiag()
  return ("on %s, channel %s, members with data %d, sent %d, received %d, requests %d, blocked %d, dropped %d, lockdown %s"):format(
    tostring(Enabled() and true or false), tostring(Channel() or "none"), ns.PartyMemberCount(), stats.sent,
    stats.received, stats.requests, stats.blocked, stats.dropped, tostring(Locked()))
end

-- Option switched: start (request the others) or forget everything.
function ns.ApplyPartyProgress()
  ResetSharing()
  if Enabled() then
    lastSent = nil
    force = true
    Queue(1)
    Request()
  else
    wipe(members) wipe(incoming)
    Changed()
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.OnInit(function()
  if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
    local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    -- true (older clients) or a result code 0 (success) / 1 (already registered)
    local code = ok and ns.Num(result)
    registered = ok and (result == true or result == nil or code == 0 or code == 1)
  end
end)

ns.On("CHAT_MSG_ADDON", OnMessage)

local lastRoster = {}
ns.On("GROUP_ROSTER_UPDATE", function()
  ResetSharing()
  local roster = Prune()
  if not roster then lastRoster = {} return end
  local newMember = false
  for name in pairs(roster) do if not lastRoster[name] then newMember = true end end
  local joined = next(lastRoster) == nil
  lastRoster = roster
  if newMember then
    force = true
    Queue(2)
    if joined then ns.After(2, Request) end
  end
end)

ns.On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
  ResetSharing()
  lastRoster = Prune() or {}
  if (isLogin or isReload) and Channel() then
    force = true
    Queue(3)
    ns.After(3, Request)
  end
end)

local function OnLog() if Enabled() and Channel() then Queue(1) end end
ns.On("QUEST_LOG_UPDATE", OnLog)
ns.On("QUEST_ACCEPTED", OnLog)
ns.On("QUEST_TURNED_IN", OnLog)
ns.On("QUEST_REMOVED", OnLog)
ns.On("PLAYER_REGEN_ENABLED", OnLog)
