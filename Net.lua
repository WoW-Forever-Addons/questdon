local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.0.1) Channel test (/qd nettest): which ways of hidden addon messages
-- does WoW Forever allow? Groundwork for sharing learned quest data between
-- Questdon players. One short test signal per way, then we listen whether it
-- comes back: the client echoes addon messages to the sender (whisper to
-- yourself, guild, group, channel; say and yell too where they are allowed).
--
--   ways: whisper (to yourself), guild, group (party or instance), say,
--         yell, channel (a temporary channel "QuestdonNet", joined for the
--         test and left again)
--   per way: result code of C_ChatInfo.SendAddonMessage (0 = sent), echo
--            yes/no, the chat type the echo came in with
--
-- Payload "T1:<nonce>:<way>", only numbers and the way's name. Own prefix,
-- so the group progress (Party.lua) keeps its message budget. Never while
-- the client blocks addon messages (C_ChatInfo.InChatMessagingLockdown).
-- The last result is saved (QuestdonDB.netTest) for /qd diag.
---------------------------------------------------------------------------
local PREFIX = "QuestdonNet"
local CHANNEL = "QuestdonNet"
local WAIT = 6          -- seconds to listen for echoes
local JOIN_WAIT = 2     -- seconds after joining the channel before sending

local WAYS = { "whisper", "guild", "group", "say", "yell", "channel" }
local CHAT = { whisper = "WHISPER", guild = "GUILD", say = "SAY", yell = "YELL", channel = "CHANNEL" }

local running
local registered = false

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

local function Locked()
  local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn)
  if not ok or v == nil then return false end
  return not ns.Usable(v) or v == true
end

-- Name of a result code (Enum.SendAddonMessageResult) or the number.
local function CodeName(code)
  if code == nil then return "nil" end
  local enum = Enum and Enum.SendAddonMessageResult
  if type(enum) == "table" then
    for k, v in pairs(enum) do
      if v == code then return tostring(k) end
    end
  end
  return tostring(code)
end

local function Register()
  if registered then return true end
  if not (C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function") then return false end
  local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  local code = ok and ns.Num(result)
  registered = ok and (result == true or result == nil or code == 0 or code == 1) or false
  return registered
end

local function GroupChat()
  if not ns.True(ns.Value(IsInGroup)) then return nil end
  local instance = LE_PARTY_CATEGORY_INSTANCE and ns.True(ns.Value(IsInGroup, LE_PARTY_CATEGORY_INSTANCE))
  if instance then return "INSTANCE_CHAT" end
  return ns.True(ns.Value(IsInRaid)) and "RAID" or "PARTY"
end

local function ChannelNumber()
  if type(GetChannelName) ~= "function" then return nil end
  local ok, id = pcall(GetChannelName, CHANNEL)
  id = ok and ns.Num(id)
  return id and id > 0 and id or nil
end

local function Send(way, chatType, target)
  local r = running.results[way]
  r.chat = chatType
  if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then
    r.skip = "no API"
    return
  end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, ("T1:%s:%s"):format(running.nonce, way), chatType, target)
  if not ok then
    r.code = "error"
  elseif result == nil or result == true then
    r.code = 0 -- older clients return nothing
  elseif result == false then
    r.code = "false"
  else
    r.code = ns.Num(result) or "secret"
  end
  r.sent = true
end

local function Verdict(r)
  if r.skip then return "skipped", r.skip end
  if r.echo then return "works" end
  if r.sent and r.code ~= 0 then return "blocked", CodeName(r.code) end
  if r.sent then return "no echo" end
  return "skipped", "not sent"
end

local function Text(verdict, detail)
  if verdict == "works" then return L["works"] end
  if verdict == "blocked" then return L["blocked (%s)"]:format(detail) end
  if verdict == "no echo" then return L["sent, no echo"] end
  local reasons = {
    ["not in a guild"] = L["not in a guild"], ["not in a group"] = L["not in a group"],
    ["could not join the channel"] = L["could not join the channel"], ["no API"] = L["missing in the client"],
  }
  return L["skipped (%s)"]:format(reasons[detail] or detail or "?")
end

local WAY_NAMES = {
  whisper = "Whisper (yourself)", guild = "Guild", group = "Group", say = "Say", yell = "Yell", channel = "Channel",
}

local function Finish()
  local t = running
  running = nil
  if t.joined and type(LeaveChannelByName) == "function" then pcall(LeaveChannelByName, CHANNEL) end
  local build = select(2, pcall(GetBuildInfo))
  local saved = { date = ns.Today(), build = (type(build) == "string" and ns.Usable(build)) and build or "?", results = {} }
  ns.Print(L["Channel test result:"])
  for _, way in ipairs(WAYS) do
    local r = t.results[way]
    local verdict, detail = Verdict(r)
    saved.results[way] = { verdict = verdict, detail = detail, code = r.code, echo = r.echo or false, via = r.via, chat = r.chat }
    ns.Print(("  %s: %s"):format(L[WAY_NAMES[way]], Text(verdict, detail)))
  end
  if ns.db then ns.db.netTest = saved end
  ns.Print(L["Saved for /qd diag."])
end

local function SendAll()
  local t = running
  if not t then return end
  -- yourself: the full name works across realms
  local name, realm
  if type(UnitFullName) == "function" then
    local ok, n, r = pcall(UnitFullName, "player")
    if ok then name, realm = n, r end
  end
  if not (type(name) == "string" and ns.Usable(name)) then name = ns.Value(UnitName, "player") end
  if type(name) == "string" and ns.Usable(name) then
    Send("whisper", "WHISPER", (type(realm) == "string" and ns.Usable(realm) and realm ~= "") and (name .. "-" .. realm) or name)
  else
    t.results.whisper.skip = "no name"
  end
  if ns.True(ns.Value(IsInGuild)) then Send("guild", "GUILD") else t.results.guild.skip = "not in a guild" end
  local group = GroupChat()
  if group then Send("group", group) else t.results.group.skip = "not in a group" end
  Send("say", "SAY")
  Send("yell", "YELL")
  local id = ChannelNumber()
  if id then Send("channel", "CHANNEL", tostring(id)) else t.results.channel.skip = "could not join the channel" end
  C_Timer.After(WAIT, Finish)
end

function ns.NetTest()
  if running then ns.Print(L["Channel test already running."]) return false end
  if Locked() then ns.Print(L["Channel test: not possible right now (combat or chat lockdown)."]) return false end
  if not (C_Timer and C_Timer.After) then return false end
  Register()
  running = { nonce = tostring(math.random(100000, 999999)), results = {}, started = Now() }
  for _, way in ipairs(WAYS) do running.results[way] = {} end
  ns.Print(L["Channel test: sends a short hidden test signal to yourself (whisper), your guild, your group, say, yell and a temporary channel \"QuestdonNet\". Result in about 8 seconds."])
  -- the channel: join (temporary, left again after the test) unless already in it
  if not ChannelNumber() then
    local join = JoinTemporaryChannel or JoinChannelByName
    if type(join) == "function" and pcall(join, CHANNEL) then running.joined = true end
    C_Timer.After(JOIN_WAIT, SendAll)
  else
    SendAll()
  end
  return true
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, chatType)
  if prefix ~= PREFIX or not running then return end
  if type(text) ~= "string" or not ns.Usable(text) then return end
  local nonce, way = text:match("^T1:(%d+):(%a+)$")
  if nonce ~= running.nonce or not running.results[way] then return end
  local r = running.results[way]
  r.echo = true
  r.via = (type(chatType) == "string" and ns.Usable(chatType)) and chatType or "?"
end)

-- Short line for /qd diag.
function ns.NetDiag()
  local t = ns.db and ns.db.netTest
  if type(t) ~= "table" or type(t.results) ~= "table" then return "not run yet (/qd nettest)" end
  local parts = {}
  for _, way in ipairs(WAYS) do
    local r = t.results[way]
    if type(r) == "table" then
      parts[#parts + 1] = ("%s %s%s"):format(way, tostring(r.verdict), r.detail and ("(" .. tostring(r.detail) .. ")") or "")
    end
  end
  return ("%s build %s: %s"):format(tostring(t.date), tostring(t.build), table.concat(parts, ", "))
end
