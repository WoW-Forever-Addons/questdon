local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (12.11.2026, CurseForge comment: "announce in party chat whenever a quest is
-- completed"; Daniel: in stages, on by default, one line per quest)
-- One line in party chat when a quest of yours is ready to turn in, with
-- the game's quest link. No progress lines, never in a raid, one line per
-- quest. Silent when no other member has the quest (the game knows, Party.lua
-- ns.PartyAnyoneOnQuest): then nobody would care.
-- Stage 2 (Daniel: "Partyabgleich ... nur den Vornamen, das muss dann kurz
-- gehalten werden"): members with Questdon and the same quest. Who finished
-- with you says nothing: one line for all, from the first name in the
-- alphabet who still announces ("A1:<questID>" tells the others it is said).
-- The line names who is still open ("Still open: Mae 5/8") or says that
-- everyone is done.
---------------------------------------------------------------------------
if type(ns.defaults) == "table" and ns.defaults.partyAnnounce == nil then ns.defaults.partyAnnounce = true end

local WAIT = 5        -- seconds: the group's states arrive (Party.lua sends every 3 s at most), an instant turn-in is over
local STAGGER = 1.5   -- seconds per member who finished with you and comes first in the alphabet
local RECENT = 20     -- seconds: "finished with you"
local RETRY = 5       -- seconds between two tries while the client blocks chat
local MAX_TRIES = 12
local MAX_LEN = 255

local announced = {}  -- [questID] = true, until the quest leaves the log
local heard = {}      -- [questID] = time a member said the line is written

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end
local function Text(v) return type(v) == "string" and ns.Usable(v) and v ~= "" and v or nil end

-- (12.11.2026, Daniel to the lines in his chat, "brauchen wir da koordinaten und namen des npc?", chosen: no place at
-- all) the line carries the quest link; the turn-in NPC, zone and coordinates made it two lines long and are gone
local function Others() return math.max((ns.Num(ns.Value(GetNumGroupMembers)) or 1) - 1, 0) end

-- The members with Questdon who have the quest: "Mae 5/8, Tova 3/8" of those not done (nil if none), and whether
-- the whole group has it and is done.
local function Group(questID)
  if not (ns.PartyProgress and ns.PartyQuestLine) then return nil, false end
  local pp = ns.PartyProgress(questID)
  if #pp == 0 then return nil, false end
  local open = ns.PartyQuestLine(questID, true, true)
  return open, not open and #pp >= Others()
end

-- (12.11.2026, Daniel: "Verlinkt er da in der Nachricht auch die Quest?") The game's own quest link, where the client
-- has one: the others click it and read the quest. nil on clients without quest links.
local function Link(questID)
  if type(GetQuestLink) ~= "function" then return nil end
  local ok, link = pcall(GetQuestLink, questID)
  link = ok and Text(link)
  return link and link:find("|Hquest:", 1, true) and link or nil
end

-- (25.11.2026, Daniel: "wenn ich den chat auf habe und aus questdonslist shift linksklick auf ne quest mache, soll sie
-- in den chat verlinkt werden") the quest's link into the open chat line; on clients without quest links the plain
-- title, as Blizzard's own quest log does there. True when it went in; false without an open chat line.
function ns.QuestToChat(questID)
  local CFU = rawget(_G, "ChatFrameUtil")
  local getActive = (CFU and CFU.GetActiveWindow) or rawget(_G, "ChatEdit_GetActiveWindow")
  local insert = (CFU and CFU.InsertLink) or rawget(_G, "ChatEdit_InsertLink")
  if not (questID and type(getActive) == "function" and type(insert) == "function") then return false end
  local ok, box = pcall(getActive)
  if not (ok and box) then return false end
  local text = Link(questID) or Text(ns.QuestTitle and ns.QuestTitle(questID))
    or (ns.DataQuestName and Text(ns.DataQuestName(questID)))
  if not text then return false end
  return pcall(insert, text) and true or false
end

-- (13.11.2026, Daniel to "[What Comes Around...] is ready to turn in. Still open: Fallen 0/1, Laena 0/1, Nermeen 0/1"
-- after looting a head in a dungeon: "wir sind aber in ner ini. da sollte eher die erfolgsmeldung kommen -
-- abgeschlossen") inside an instance nobody can turn in and the others loot a moment later: the line says
-- "completed" there and names nobody as still open.
local function InInstance()
  if type(IsInInstance) ~= "function" then return false end
  local ok, inside, kind = pcall(IsInInstance)
  if not ok then return false end
  return ns.True(inside) and (kind == nil or kind == "party" or kind == "raid" or not ns.Usable(kind)) or false
end

-- The line for the group, nil without a readable title (then the data's English name, never "Quest 123").
-- plain: the title as text instead of the quest link.
function ns.AnnounceText(questID, title, plain)
  title = (not plain and Link(questID)) or Text(title) or (ns.DataQuestName and Text(ns.DataQuestName(questID)))
  if not title then return nil end
  local open, all = Group(questID)
  local inst = InInstance()
  local base = (all and L["Questdon: everyone is done with %s."] or inst and L["Questdon: %s completed."]
    or L["Questdon: %s is ready to turn in."]):format(title)
  local still = open and not inst and (" " .. L["Still open: %s"]:format(open)) or ""
  -- too long for one chat line: without the members
  for _, msg in ipairs({ base .. still, base }) do
    if #msg <= MAX_LEN then return msg end
  end
  return nil
end

-- No other member has the quest: the game says so for everybody (C_QuestLog.IsUnitOnQuest), without it only when
-- every other member uses Questdon. Unknown counts as "somebody may care".
local function NobodyCares(questID)
  return ns.PartyAnyoneOnQuest ~= nil and ns.PartyAnyoneOnQuest(questID) == false
end

-- How many members finished the quest with you and come before you in the alphabet: they speak first.
local function Rank(questID)
  if not (ns.PartyProgress and ns.PartyMyName) then return 0 end
  local me, now, n = ns.PartyMyName(), Now(), 0
  if not me then return 0 end
  for _, p in ipairs(ns.PartyProgress(questID)) do
    local age = p.complete and p.doneAt and now - p.doneAt
    if age and age >= 0 and age <= RECENT and p.name < me then n = n + 1 end
  end
  return n
end

-- Party.lua: a member wrote the line for this quest.
function ns.AnnounceHeard(questID)
  questID = ns.Num(questID)
  if questID then heard[questID] = Now() end
end
local function Heard(questID)
  local at = heard[questID]
  if not at then return false end
  local age = Now() - at
  return age >= 0 and age <= RECENT + WAIT + MAX_TRIES * RETRY
end

local function Send(msg, channel)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if type(send) ~= "function" then return false end
  return (pcall(send, msg, channel))
end

local function Try(questID, title, tries, waited)
  if not ns.db.partyAnnounce or announced[questID] then return end
  if ns.DataOnly and ns.DataOnly() then return end
  local channel = ns.PartyChannel and ns.PartyChannel()
  if not channel then return end
  -- turned in or abandoned meanwhile, or no longer complete (an item left the bags)
  if not ns.InQuestLog(questID) or not ns.IsQuestComplete(questID) then return end
  if NobodyCares(questID) then return end
  if Heard(questID) then announced[questID] = true return end -- a member said it for all
  if not waited then
    local rank = Rank(questID)
    if rank > 0 then ns.After(rank * STAGGER, function() Try(questID, title, tries, true) end) return end
  end
  if ns.PartyLocked and ns.PartyLocked() then
    if tries < MAX_TRIES then ns.After(RETRY, function() Try(questID, title, tries + 1, true) end) end
    return
  end
  local msg = ns.AnnounceText(questID, title)
  if not msg then return end
  if not Send(msg, channel) then
    -- the chat did not take the line (a link it refuses): once more with the title as text
    local text = ns.AnnounceText(questID, title, true)
    if not text or text == msg or not Send(text, channel) then return end
  end
  announced[questID] = true
  if ns.PartySend then ns.PartySend("A1:" .. questID) end
  if not ns.db.partyAnnounceTold then
    ns.db.partyAnnounceTold = true
    ns.Print(L["Questdon told your group that a quest is ready to turn in. To switch it off: /qd announce, or the options under Accept and turn in."])
  end
end

-- Notify.lua: a quest of the log just became complete.
function ns.AnnounceQuestDone(questID, title)
  questID = ns.Num(questID)
  if not questID or not ns.db.partyAnnounce or announced[questID] then return end
  if not (ns.PartyChannel and ns.PartyChannel()) then return end
  ns.After(WAIT, function() Try(questID, title, 1) end)
end

-- /qd announce: on and off.
function ns.ToggleAnnounce()
  ns.db.partyAnnounce = not ns.db.partyAnnounce
  ns.db.partyAnnounceTold = true
  ns.Print(ns.db.partyAnnounce and L["Your group is told when a quest of yours is ready to turn in."]
    or L["Your group is no longer told when a quest is ready to turn in."])
end

-- /qd announce test: the lines as the group would read them, only in your own chat (nothing is sent).
function ns.AnnounceTest()
  local n = 0
  for _, info in ipairs(ns.QuestLogEntries()) do
    if n >= 5 then break end
    local msg = ns.AnnounceText(info.questID, info.title)
    if msg then n = n + 1 print(msg) end
  end
  if n == 0 then ns.Print(L["Quest log empty"]) end
end

ns.On("QUEST_REMOVED", function(_, questID)
  questID = ns.Num(questID)
  if questID then announced[questID], heard[questID] = nil, nil end
end)
