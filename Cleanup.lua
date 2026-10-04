local _, ns = ...
local L = ns.L

local LAST_BAG = NUM_BAG_SLOTS or 4

---------------------------------------------------------------------------
-- Grey quests: trivial for your level and not yet finished
---------------------------------------------------------------------------
-- Blizzard's answer if it gives a readable one, else the quest level against
-- the green range.
local function IsGrey(info)
  local trivial = ns.Value(C_QuestLog.IsQuestTrivial, info.questID)
  if type(trivial) == "boolean" then return trivial end
  local level, range = ns.PlayerLevel(), ns.QuestTrivialRange and ns.QuestTrivialRange() or 8 -- (1.26)
  return ns.Num(info.level) and level and info.level < level - range or false
end

function ns.GreyQuests()
  local list = {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    if IsGrey(info) and not ns.IsQuestComplete(info.questID)
        and (not C_QuestLog.CanAbandonQuest or ns.True(ns.Value(C_QuestLog.CanAbandonQuest, info.questID))) then
      list[#list + 1] = info
    end
  end
  return list
end

-- Abandons one quest by ID (IDs stay valid when the log changes, indices do not).
-- (1.23) Secret or missing values never reach a comparison (as in Share.lua).
function ns.AbandonQuest(questID)
  if InCombatLockdown() then ns.Print(L["Not possible in combat."]) return false end
  questID = ns.Num(questID)
  if not questID or (ns.Num(ns.Value(C_QuestLog.GetLogIndexForQuestID, questID)) or 0) <= 0 then return false end
  if not (C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest) then return false end
  local previous = ns.Num(ns.Value(C_QuestLog.GetSelectedQuest))
  if not pcall(C_QuestLog.SetSelectedQuest, questID) then return false end
  local ok = pcall(C_QuestLog.SetAbandonQuest) and pcall(C_QuestLog.AbandonQuest)
  if previous and previous > 0 and previous ~= questID
      and (ns.Num(ns.Value(C_QuestLog.GetLogIndexForQuestID, previous)) or 0) > 0 then
    pcall(C_QuestLog.SetSelectedQuest, previous)
  end
  return ok and true or false
end

---------------------------------------------------------------------------
-- Quest items that no quest in the log needs any more (probably)
---------------------------------------------------------------------------
-- (1.0) A quest "explains itself" when the log names what it needs: a counting
-- objective (item, kill, object ...) with a readable text. A quest without one
-- (deliver a letter, speak to someone, escort ...) may need quest
-- items the log never names, so while one is in the log the list stays quiet
-- instead of calling a needed item useless.
local NOT_EXPLAINING = { event = true }
local function ObjectiveTexts()
  local texts, special, openEnded = {}, {}, false
  for i, info in ipairs(ns.QuestLogEntries()) do
    if type(info.title) == "string" and ns.Usable(info.title) and info.title ~= "" then texts[#texts + 1] = info.title end
    local explains = false
    for _, o in ipairs(ns.ClientObjectives(info.questID)) do
      if type(o) == "table" and type(o.text) == "string" and ns.Usable(o.text) then
        texts[#texts + 1] = o.text
        if o.text ~= "" and not (ns.Usable(o.type) and NOT_EXPLAINING[o.type]) then explains = true end
      end
    end
    if not explains then openEnded = true end
  end
  -- Usable quest items shown in the log belong to active quests.
  if GetQuestLogSpecialItemInfo and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, ns.Num(ns.Value(C_QuestLog.GetNumQuestLogEntries)) or 0 do
      local link = ns.Value(GetQuestLogSpecialItemInfo, i)
      local id = type(link) == "string" and ns.GetItemID(link)
      if id then special[id] = true end
    end
  end
  return texts, special, openEnded
end

-- (1.0) What the data says about an item: "needed" (a quest that provides or
-- needs it is in the log), "ahead" (such a quest is still to come for this
-- character), "orphan" (all of them done or out of reach), nil (unknown item).
-- Second result: the quest to name in the list (a quest in the log, else the
-- first one the data knows).
-- (1.0) What the game told us: ns.db.learnedItems[itemID] = { questID, ... }
-- (tooltip, NPC window: firm) and ns.db.guessedItems (an item that appeared
-- right after accepting a quest: a guess, never enough to call an item unneeded).
local function AddLearned(itemID, questID, guess)
  if not (ns.db.learnQuests and itemID and questID and questID > 0) then return end
  local key = guess and "guessedItems" or "learnedItems"
  ns.db[key] = ns.db[key] or {}
  local list = ns.db[key][itemID]
  if type(list) ~= "table" then list = {} ns.db[key][itemID] = list end
  for _, id in ipairs(list) do if id == questID then return end end
  if #list < 8 then list[#list + 1] = questID end
end

-- All quests known for an item: firm sources first (the game, the data), then
-- guesses. Second result: is there any firm source?
local function QuestsOf(itemID)
  local out, seenQ, firm = {}, {}, false
  local function add(id) if type(id) == "number" and not seenQ[id] then seenQ[id] = true out[#out + 1] = id end end
  local learned = ns.db.learnedItems and ns.db.learnedItems[itemID]
  if type(learned) == "table" then for _, id in ipairs(learned) do add(id) firm = true end end
  for _, id in ipairs(ns.QuestsForItem(itemID) or {}) do add(id) firm = true end
  local guessed = ns.db.guessedItems and ns.db.guessedItems[itemID]
  if type(guessed) == "table" then for _, id in ipairs(guessed) do add(id) end end
  return out, firm
end

-- Third result: false when only guesses back an "orphan" verdict.
local function ItemStatus(itemID)
  local list, firm = QuestsOf(itemID)
  if #list == 0 then return nil end
  local ahead = false
  for _, id in ipairs(list) do
    if ns.InQuestLog(id) then return "needed", id, firm end
    if not ns.IsQuestDone(id) and ns.QuestReachable(id) then ahead = true end
  end
  return ahead and "ahead" or "orphan", list[1], firm
end

-- (1.0) True when every quest known for the item is finished or gone: the ones in the
-- log are ready for turn-in, the others done or out of reach. Unknown item: false.
-- Used by the quest item button (no button for an item nobody needs any more).
function ns.ItemQuestsFinished(itemID)
  if not ns.db then return false end
  local list = QuestsOf(itemID)
  if #list == 0 then return false end
  for _, id in ipairs(list) do
    if ns.InQuestLog(id) then
      if not ns.IsQuestComplete(id) then return false end
    elseif not ns.IsQuestDone(id) and ns.QuestReachable(id) then
      return false
    end
  end
  return true
end

-- (1.0) The game's own word: the tooltip of a quest item names the quest and
-- its objective while a quest needs it (lines of type QuestTitle, QuestObjective,
-- QuestPlayer). Empty list if this client's tooltips do not offer that.
local TIP_TITLE, TIP_QUEST = nil, {}
if Enum and Enum.TooltipDataLineType then
  TIP_TITLE = Enum.TooltipDataLineType.QuestTitle
  for _, name in ipairs({ "QuestTitle", "QuestObjective", "QuestPlayer" }) do
    local v = Enum.TooltipDataLineType[name]
    if v then TIP_QUEST[v] = true end
  end
end
local function TooltipLines(bag, slot)
  local out = {}
  local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and ns.Value(C_TooltipInfo.GetBagItem, bag, slot)
  if type(data) ~= "table" or type(data.lines) ~= "table" then return out end
  for _, line in ipairs(data.lines) do
    if type(line) == "table" then
      local text = type(line.leftText) == "string" and ns.Usable(line.leftText) and line.leftText or nil
      out[#out + 1] = { type = ns.Num(line.type), text = text }
    end
  end
  return out
end
ns.QuestItemTooltipLines = TooltipLines

-- Does the tooltip say a quest needs the item? Quest titles it names are learned
-- for the item (so it can still be assigned once the quest is done).
local function TooltipSaysQuest(lines, titleToID)
  local says = false
  for _, l in ipairs(lines) do
    if l.type and TIP_QUEST[l.type] then
      says = true
      if l.type == TIP_TITLE and l.text and titleToID[l.text] then return true, titleToID[l.text] end
    end
  end
  return says
end

---------------------------------------------------------------------------
-- (1.0) Learn which quest hands out an item the data does not know: a quest
-- item that appears in the bags right after a quest was accepted belongs to it.
---------------------------------------------------------------------------
local function QuestItemSet()
  local set = {}
  if not (C_Container and C_Container.GetContainerItemQuestInfo) then return set end
  for bag = 0, LAST_BAG do
    for slot = 1, ns.Num(ns.Value(C_Container.GetContainerNumSlots, bag)) or 0 do
      local q = C_Container.GetContainerItemQuestInfo(bag, slot)
      local info = type(q) == "table" and ns.True(q.isQuestItem) and C_Container.GetContainerItemInfo(bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      if id then set[id] = true end
    end
  end
  return set
end

local known, older, knownAt -- bag snapshots (replaced, never changed)
ns.On("BAG_UPDATE_DELAYED", function()
  if not (ns.db and ns.db.learnQuests) then known, older = nil, nil return end
  older, known, knownAt = known, QuestItemSet(), GetTime and GetTime() or 0
end)

-- The NPC's "continue" window lists the items the quest needs: the surest
-- source there is, but only seen while talking to the NPC.
local function InstantClass(item)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then return nil end
  local ok, id, _, _, _, _, classID = pcall(fn, item)
  return ok and ns.Num(id) or nil, ok and ns.Num(classID) or nil
end
ns.On("QUEST_PROGRESS", function()
  if not ns.db.learnQuests or not GetNumQuestItems then return end
  local questID = ns.Num(ns.Value(GetQuestID))
  if not questID or questID <= 0 then return end
  for i = 1, ns.Num(ns.Value(GetNumQuestItems)) or 0 do
    local link = GetQuestItemLink and ns.Value(GetQuestItemLink, "required", i)
    local id, classID = InstantClass(type(link) == "string" and link or nil)
    -- quest items only (class 12); an unknown class is taken as well
    if id and (classID == nil or classID == 12) then AddLearned(id, questID) end
  end
end)

ns.On("QUEST_ACCEPTED", function(_, questID)
  questID = ns.Num(questID)
  if not ns.db.learnQuests or not questID or questID <= 0 or not known then return end
  -- the bag update may already have run before this event
  local before = (GetTime and GetTime() or 0) - (knownAt or 0) < 1 and older or known
  ns.After(2, function()
    if not before then return end
    local now = QuestItemSet()
    for id in pairs(now) do
      if not before[id] and not ns.QuestsForItem(id) then
        AddLearned(id, questID, true)
      end
    end
  end)
end)

local function QuestName(questID)
  local title = questID and ns.Value(C_QuestLog.GetTitleForQuestID, questID)
  if type(title) == "string" and title ~= "" then return title end
  return questID and ns.DataQuestName(questID) or nil
end

-- (1.0) Destroys one quest item that is still reported as unneeded (checked again
-- right now) and where the data or the game is sure; a guess from log texts
-- never. One click handler calls this, never a timer or an event: the game
-- may require a click for it, and nothing is deleted without the player's click.
function ns.DestroyQuestItem(itemID)
  if InCombatLockdown() then ns.Print(L["Not possible in combat."]) return false end
  itemID = ns.Num(itemID)
  if not itemID or not (C_Container and C_Container.PickupContainerItem) or not DeleteCursorItem then return false end
  if GetCursorInfo and GetCursorInfo() then ns.Print(L["Your cursor is holding something."]) return false end
  ns.InvalidateOrphans() -- judged again right now, not from the cache
  local target
  for _, o in ipairs(ns.OrphanQuestItems()) do
    if o.itemID == itemID and o.sure then target = o break end
  end
  if not target then return false end
  -- the slot is read again: bags may have moved since the list was built
  local bag, slot
  for b = 0, LAST_BAG do
    for sl = 1, ns.Num(ns.Value(C_Container.GetContainerNumSlots, b)) or 0 do
      local info = C_Container.GetContainerItemInfo(b, sl)
      if not bag and type(info) == "table" and ns.Num(info.itemID) == itemID then bag, slot = b, sl end
    end
  end
  if not bag then return false end
  pcall(C_Container.PickupContainerItem, bag, slot)
  local kind, id = nil, nil
  if GetCursorInfo then kind, id = GetCursorInfo() end
  local ok = false
  if kind == "item" and ns.Num(id) == itemID then
    ok = pcall(DeleteCursorItem)
  end
  if ClearCursor and GetCursorInfo and GetCursorInfo() then ClearCursor() end
  ns.InvalidateOrphans()
  if not ok then ns.Print(L["The game did not allow destroying the item."]) end
  return ok
end

-- (1.0) For /qd diag: what the game and the data say about each quest item in
-- the bags (to find out which source works in this client).
function ns.QuestItemDiag()
  local out = {}
  if not (C_Container and C_Container.GetContainerItemQuestInfo) then return { "no container API" } end
  for bag = 0, LAST_BAG do
    for slot = 1, ns.Num(ns.Value(C_Container.GetContainerNumSlots, bag)) or 0 do
      local q = C_Container.GetContainerItemQuestInfo(bag, slot)
      local info = type(q) == "table" and ns.True(q.isQuestItem) and C_Container.GetContainerItemInfo(bag, slot)
      local id = type(info) == "table" and ns.Num(info.itemID)
      if id then
        local name = ns.GetItemInfo and ns.GetItemInfo(id)
        local status, owner, firm = ItemStatus(id)
        local inLog = {}
        for _, qid in ipairs(QuestsOf(id)) do if ns.InQuestLog(qid) then inLog[#inLog + 1] = qid end end
        out[#out + 1] = ("item %d %s | game questID=%s isActive=%s | data %s | learned %s | guessed %s | in log %s | status %s (quest %s, firm %s)"):format(
          id, type(name) == "string" and ns.Usable(name) and name or "?",
          tostring(ns.Num(q.questID)), tostring(ns.True(q.isActive)),
          "{" .. table.concat(ns.QuestsForItem(id) or {}, ",") .. "}",
          "{" .. table.concat((ns.db.learnedItems and ns.db.learnedItems[id]) or {}, ",") .. "}",
          "{" .. table.concat((ns.db.guessedItems and ns.db.guessedItems[id]) or {}, ",") .. "}",
          "{" .. table.concat(inLog, ",") .. "}",
          tostring(status), tostring(owner), tostring(firm))
        local lines = TooltipLines(bag, slot)
        local parts = {}
        for _, l in ipairs(lines) do
          if l.text then parts[#parts + 1] = ("%s:%s"):format(tostring(l.type), l.text:sub(1, 48)) end
        end
        out[#out + 1] = "  tooltip (" .. #lines .. " lines, quest line types " .. (TIP_TITLE and "known" or "unknown")
          .. "): " .. (#parts > 0 and table.concat(parts, " / ") or "-")
      end
    end
  end
  if #out == 0 then out[1] = "no quest items in the bags" end
  return out
end

-- (1.0) The list is built from the bags, the log and (the expensive part) item
-- tooltips. It is kept until something it depends on happens, or 15 seconds
-- pass, so the panel's regular refreshes cost nothing. Callers only read it.
local function BuildOrphans()
  local list = {}
  if not (C_Container and C_Container.GetContainerItemQuestInfo) then return list end
  local texts, special, openEnded = ObjectiveTexts()
  local blob = table.concat(texts, "\n") -- one search per item instead of one per text
  local titleToID
  local function Titles()
    if not titleToID then
      titleToID = {}
      for _, info in ipairs(ns.QuestLogEntries()) do
        if type(info.title) == "string" and ns.Usable(info.title) and info.title ~= "" then titleToID[info.title] = ns.Num(info.questID) end
      end
    end
    return titleToID
  end
  local seen = {}
  for bag = 0, LAST_BAG do
    -- (1.28) an unreadable slot count (nil, secret) is an empty bag, not an error
    for slot = 1, ns.Num(ns.Value(C_Container.GetContainerNumSlots, bag)) or 0 do
      local q = C_Container.GetContainerItemQuestInfo(bag, slot)
      local info = type(q) == "table" and ns.True(q.isQuestItem) and C_Container.GetContainerItemInfo(bag, slot)
      local itemID = type(info) == "table" and ns.Num(info.itemID)
      if itemID and not seen[itemID] and not special[itemID] then
        seen[itemID] = true
        local orphan, forQuest, sure, status
        local starter = ns.Num(q.questID)
        if starter and starter > 0 then
          -- Quest starter: orphan once that quest is done for this character.
          -- (1.28) a questID of 0 means "no quest", not a quest to look up
          orphan = ns.IsQuestDone(starter)
          forQuest = starter
          sure = true
        else
          local owner, firm
          status, owner, firm = ItemStatus(itemID)
          if status then
            -- known to the data: decided by the quests, not by guessing from texts
            orphan = status == "orphan"
            forQuest = owner
            sure = firm and true or false
          end
          local name = ns.GetItemInfo and ns.GetItemInfo(itemID)
          if type(name) == "string" and ns.Usable(name) and name ~= "" then
            if not status then orphan = not openEnded end
            -- safety net for every verdict: a name the log still mentions is needed
            if orphan and blob:find(name, 1, true) then orphan = false end
          end
        end
        -- The tooltip is only read where it can change something: it vetoes an
        -- orphan verdict, and teaches an unknown item its quest (once).
        local learnedAlready = ns.db.learnedItems and ns.db.learnedItems[itemID]
        if orphan or (not status and not learnedAlready) then
          local says, tipQuest = TooltipSaysQuest(TooltipLines(bag, slot), Titles())
          if tipQuest then AddLearned(itemID, tipQuest) end
          if says then orphan = false end -- the game itself says a quest needs it
        end
        if orphan then list[#list + 1] = { itemID = itemID, link = info.hyperlink, sure = sure and true or false, quest = forQuest and QuestName(forQuest) or nil } end
      end
    end
  end
  return list
end

local orphanCache, orphanCacheAt
function ns.InvalidateOrphans() orphanCache = nil end
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "PLAYER_ENTERING_WORLD" }) do
  ns.On(event, ns.InvalidateOrphans)
end
function ns.OrphanQuestItems()
  local now = GetTime and GetTime() or 0
  if orphanCache and orphanCacheAt and now - orphanCacheAt < 15 then return orphanCache end
  orphanCache, orphanCacheAt = BuildOrphans(), now
  return orphanCache
end
