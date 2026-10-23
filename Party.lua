local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.18) Quest progress of the group. Questdon players in a party (at most
-- five players, also in instance groups) send each other the state of their
-- quest log with hidden addon messages: quest IDs, complete/failed and the
-- objective counters. Nothing else, no names in the payload.
--
--   "R1"                         please send me your state
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

local function Roster()
  local set = {}
  if not ns.True(ns.Value(IsInGroup)) then return set end
  local raid = ns.True(ns.Value(IsInRaid))
  local n = GroupSize()
  for i = 1, raid and n or math.max(n - 1, 0) do
    local name = UnitFullName((raid and "raid" or "party") .. i)
    if name then set[name] = true end
  end
  return set
end

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

local function Send(msg, channel)
  if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return false end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
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
local function Changed()
  if refreshQueued then return end
  refreshQueued = true
  ns.After(0.5, function()
    refreshQueued = false
    if ns.UpdatePanel then ns.UpdatePanel("ifChanged") end
    if ns.RefreshPinsIfChanged then ns.RefreshPinsIfChanged() end
  end)
end

local function OnMessage(_, prefix, text, _, sender)
  if prefix ~= PREFIX or not Enabled() then return end
  if type(text) ~= "string" or not ns.Usable(text) then return end
  local name = Short(sender)
  if not name or name == UnitFullName("player") then return end
  if not Roster()[name] then stats.dropped = stats.dropped + 1 return end
  if text == "R1" then
    stats.requests = stats.requests + 1
    force = true
    Queue(1 + math.random() * 2) -- spread the answers of several members
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
    members[name] = { quests = Parse(table.concat(buf.parts, "", 1, n)), at = Now() }
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

-- { { name, complete, failed, objectives = { {fulfilled, required}, ... } }, ... }
function ns.PartyProgress(questID)
  local out = {}
  if not Enabled() or next(members) == nil then return out end -- (1.23) no group data: nothing to sort
  for _, name in ipairs(SortedNames()) do
    local q = members[name].quests[questID]
    if q then
      local objs = {}
      for i, o in ipairs(q[2]) do objs[i] = { o[1], o[2] } end
      out[#out + 1] = { name = name, complete = q[1] == 1, failed = q[1] == 2, objectives = objs }
    end
  end
  return out
end

-- Names of the members who have the quest in their log.
function ns.PartyMembersWithQuest(questID)
  local out = {}
  for _, p in ipairs(ns.PartyProgress(questID)) do out[#out + 1] = p.name end
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
  for _, o in ipairs(p.objectives) do parts[#parts + 1] = ("%d/%d"):format(o[1], o[2]) end
  return #parts > 0 and table.concat(parts, ", ") or L["in log"]
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
      out[#out + 1] = { p.name, ("%d/%d"):format(o[1], o[2]) }
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
    for _, p in ipairs(ns.PartyProgress(id)) do parts[#parts + 1] = L["%s %s (player and quest state)"]:format(p.name, ns.PartyStateText(p)) end
    ns.Print("  " .. ns.QuestTitle(id) .. L[": "] .. table.concat(parts, ", "))
  end
  for _, id in ipairs(po.takeable) do
    ns.Print("  " .. L["To pick up: %s (%s)"]:format(ns.QuestTitle(id), table.concat(ns.PartyMembersWithQuest(id), ", ")))
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
