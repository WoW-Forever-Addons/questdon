local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.1) Quests a quest giver never offers. The bundled data has quests that
-- are not offered where it says (helper quests, removed quests, wrong NPC):
-- Questdon showed a "!" there for every character and every player.
--
-- Account wide, per quest (QuestdonDB.notHere[questID]):
--   lv  = { [level] = true }  levels at which the quest giver's dialog did not
--                             list the quest although the data called it
--                             available (Offers.lua judges, single giver only)
--   man = time                you reported it yourself (Alt-click on the "!",
--                             /qd nothere with the NPC targeted): for quest
--                             givers without a dialog
--   ok  = time                the quest was offered to you: it exists, every
--                             verdict (own, shared, bundled) is void
--   npc = creature ID
-- Hidden on the map, the minimap, the nameplates and in the panel when:
-- reported by you, or not offered at LEVELS different levels, or reported by
-- two other players (Exchange.lua, line "N"), or in the bundled data
-- (ns.EXTRA_NOT_HERE, from exports). Never when it was offered to you, and
-- never when the game itself lists the quest (its quest lines win).
-- A turn-in at the same NPC starts the level count again (the data may miss
-- a previous quest that is turned in there).
---------------------------------------------------------------------------
local LEVELS = 3     -- different levels without the quest: hidden
local MAX_LEVELS = 10 -- levels kept per quest

local stats = { auto = 0, hiddenAuto = 0, manual = 0, offered = 0, restarted = 0, undone = 0 }
local last = {}       -- quest IDs of the last report (/qd nothere undo)

local function Clock() return ns.Num(ns.Value(time)) or ns.Num(ns.Value(GetTime)) or 0 end
local function Count(t)
  local n = 0
  for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
  return n
end

local function Store()
  local db = ns.db
  if type(db) ~= "table" then return {} end
  if type(db.notHere) ~= "table" then db.notHere = {} end
  return db.notHere
end

local function Refresh()
  if ns.QueuePinRefresh then ns.QueuePinRefresh() end
  if ns.QueueRefresh then ns.QueueRefresh("panel") end
end

-- Is the quest hidden as "not offered here"? Second value: why ("you",
-- "auto", "shared", "data").
function ns.NeverOffered(questID)
  if type(questID) ~= "number" then return false end
  local e = Store()[questID]
  if type(e) == "table" then
    if e.ok then return false end
    if e.man then return true, "you" end
    if Count(e.lv) >= LEVELS then return true, "auto" end
  end
  if ns.SharedNotHere and ns.SharedNotHere(questID) then return true, "shared" end
  if ns.EXTRA_NOT_HERE and ns.EXTRA_NOT_HERE[questID] then return true, "data" end
  return false
end

-- Levels at which the quest giver did not offer it (sorted), while it is not
-- hidden yet: for the tooltip ("not offered at level 5, 6").
function ns.NotHereLevels(questID)
  local e = Store()[questID]
  if type(e) ~= "table" or e.ok or type(e.lv) ~= "table" then return nil end
  local list = {}
  for lv in pairs(e.lv) do list[#list + 1] = lv end
  if #list == 0 then return nil end
  table.sort(list)
  return list
end
ns.NOT_HERE_LEVELS = LEVELS

-- Offers.lua: the dialog of npcID did not list the quest at this level.
function ns.NoteNotOffered(questID, npcID, level)
  level = ns.Num(level)
  if not (questID and level) then return end
  local s = Store()
  local e = s[questID]
  if type(e) ~= "table" then e = {} s[questID] = e end
  if e.ok then return end -- it was offered once: it exists
  if type(e.lv) ~= "table" then e.lv = {} end
  e.npc = npcID or e.npc
  if e.lv[level] then return end
  if Count(e.lv) >= MAX_LEVELS then return end
  e.lv[level] = true
  stats.auto = stats.auto + 1
  if Count(e.lv) == LEVELS and not e.man then
    stats.hiddenAuto = stats.hiddenAuto + 1
    ns.Print(L["%s is hidden: the quest giver did not offer it at %d different levels. Undo: /qd nothere undo"]:format(
      ns.QuestTitle(questID), LEVELS))
    last = { questID }
    Refresh()
  end
end

-- Offers.lua: the quest was offered (dialog or quest window). Every verdict ends.
function ns.NoteOfferedHere(questID, npcID)
  if not questID then return end
  local s = Store()
  local e = s[questID]
  local was = ns.NeverOffered(questID)
  if type(e) == "table" and e.ok then return end
  s[questID] = { ok = Clock(), npc = npcID or (type(e) == "table" and e.npc) or nil }
  stats.offered = stats.offered + 1
  if was then Refresh() end
end

-- Offers.lua: a quest turned in at npcID. The level count of that NPC's
-- quests starts again (a missing previous quest may just have been done);
-- own reports stay.
function ns.NotHereTurnIn(npcID)
  if not npcID then return end
  for _, e in pairs(Store()) do
    if type(e) == "table" and e.npc == npcID and not e.ok and type(e.lv) == "table" and next(e.lv) then
      e.lv = nil
      stats.restarted = stats.restarted + 1
    end
  end
end

-- Report quests yourself: they are hidden right away (all characters).
function ns.ReportNotHere(questIDs, npcID)
  local s, now, done, titles = Store(), Clock(), {}, {}
  for _, id in ipairs(questIDs or {}) do
    if type(id) == "number" and not done[id] then
      done[id] = true
      local e = s[id]
      if type(e) ~= "table" or e.ok then e = {} s[id] = e end
      e.man, e.npc = now, npcID or e.npc
      stats.manual = stats.manual + 1
      titles[#titles + 1] = ns.QuestTitle(id)
    end
  end
  if #titles == 0 then return 0 end
  last = {}
  for id in pairs(done) do last[#last + 1] = id end
  ns.Print(L["Reported as not offered here, now hidden: %s. Undo: /qd nothere undo"]:format(table.concat(titles, ", ")))
  Refresh()
  return #titles
end

function ns.UndoNotHere()
  local s, n = Store(), 0
  for _, id in ipairs(last) do
    local e = s[id]
    if type(e) == "table" and not e.ok then
      s[id] = nil
      n = n + 1
    end
  end
  last = {}
  stats.undone = stats.undone + n
  if n > 0 then
    ns.Print(L["Shown again: %d quests."]:format(n))
    Refresh()
  else
    ns.Print(L["Nothing to undo."])
  end
  return n
end

-- The quest giver of an available quest (one creature), or nil.
local function GiverOf(questID)
  local e = ns.db and ns.db.learned and ns.db.learned[questID]
  if type(e) == "table" and type(e.start) == "table" and ns.Num(e.start.npcID) and e.start.npcID > 0 then
    return e.start.npcID
  end
  local g = ns.QuestGiverIDs and ns.QuestGiverIDs(questID)
  if type(g) == "table" and #g == 1 then return g[1] end
end

-- Alt-click on a "!" (world map, minimap): every quest of that pin.
function ns.ReportPin(pin)
  if type(pin) ~= "table" or pin.kind == "turnin" or pin.kind == "objective" then return 0 end
  local ids, npc = {}, nil
  for _, p in ipairs(pin.group or { pin }) do
    if p.questID and p.kind ~= "turnin" then
      ids[#ids + 1] = p.questID
      npc = npc or GiverOf(p.questID)
    end
  end
  return ns.ReportNotHere(ids, npc)
end

-- /qd nothere: the quests Questdon shows at the targeted NPC.
function ns.ReportTarget()
  local ok, guid = pcall(UnitGUID, "target")
  local id = ok and type(guid) == "string" and ns.Usable(guid) and ns.CreatureIDFromGUID and ns.CreatureIDFromGUID(guid)
  if not id then
    ns.Print(L["Target the quest giver first (an NPC), then /qd nothere."])
    return 0
  end
  local ids = {}
  for _, q in ipairs(ns.GiverQuests and ns.GiverQuests(id) or {}) do
    if ns.CanTakeQuest(q) or (ns.NotOfferedLevel and ns.NotOfferedLevel(q)) then ids[#ids + 1] = q end
  end
  if #ids == 0 then
    ns.Print(L["Questdon shows no quest at this NPC."])
    return 0
  end
  return ns.ReportNotHere(ids, id)
end

-- /qd nothere list: hidden quests and why.
local WHY = { you = "reported by you", auto = "never offered (3 levels)", shared = "reported by other players", data = "Questdon data" }
function ns.PrintNotHere()
  local list = {}
  for id in pairs(Store()) do
    local hidden, why = ns.NeverOffered(id)
    if hidden then list[#list + 1] = { id, why } end
  end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  if #list == 0 then ns.Print(L["No quest hidden as not offered."]) return 0 end
  ns.Print(L["Hidden as not offered (%d):"]:format(#list))
  for i = 1, math.min(#list, 20) do
    ns.Print(("  %s (%d): %s"):format(ns.QuestTitle(list[i][1]), list[i][1], L[WHY[list[i][2]]]))
  end
  return #list
end

-- Export.lua and Exchange.lua: "N <questID> <npcID or 0> <m|a>" for own
-- verdicts that hide a quest (m = reported by you, a = 3 levels). all = false
-- leaves out quests the bundled data has hidden already.
function ns.NotHereRecords(all)
  local out, ids = {}, {}
  for id in pairs(Store()) do if type(id) == "number" then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local e = Store()[id]
    if type(e) == "table" and not e.ok and (e.man or Count(e.lv) >= LEVELS)
        and (all or not (ns.EXTRA_NOT_HERE and ns.EXTRA_NOT_HERE[id])) then
      local npc = ns.Num(e.npc)
      out[#out + 1] = ("N %d %d %s"):format(id, (npc and npc > 0) and npc or 0, e.man and "m" or "a")
    end
  end
  return out
end

function ns.NotHereDiag()
  local own, auto, shared, data, counting, offered = 0, 0, 0, 0, 0, 0
  for id, e in pairs(Store()) do
    local hidden, why = ns.NeverOffered(id)
    if type(e) == "table" and e.ok then offered = offered + 1 end
    if hidden then
      if why == "you" then own = own + 1 elseif why == "auto" then auto = auto + 1 end
    elseif type(e) == "table" and not e.ok and Count(e.lv) > 0 then
      counting = counting + 1
    end
  end
  for id in pairs(ns.EXTRA_NOT_HERE or {}) do
    local hidden, why = ns.NeverOffered(id)
    if hidden and why == "data" then data = data + 1 end
  end
  shared = ns.SharedNotHereCount and ns.SharedNotHereCount() or 0
  return ("hidden: by you %d, after %d levels %d, by other players %d, by data %d; counting %d, offered %d; this session: levels %d, reports %d, offers %d, restarts %d, undone %d"):format(
    own, LEVELS, auto, shared, data, counting, offered, stats.auto, stats.manual, stats.offered, stats.restarted, stats.undone)
end

function ns.ResetNotHere()
  local s = Store()
  for id, e in pairs(s) do
    if type(e) ~= "table" or not e.ok then s[id] = nil end
  end
  last = {}
  Refresh()
end
