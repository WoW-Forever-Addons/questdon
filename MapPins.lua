local _, ns = ...
local L = ns.L

-- World map pins: available quests (ATT + learned), learned turn-in points and
-- quest objective spawns (ATT). Our own data provider and pin templates only.
local QUEST_TEMPLATE = "QuestdonQuestPinTemplate"
local OBJECTIVE_TEMPLATE = "QuestdonObjectivePinTemplate"
local provider

-- A stable colour per quest, so objective dots of different quests can be told apart.
local COLORS = {
  { 1, 0.82, 0 }, { 0.35, 0.8, 1 }, { 1, 0.45, 0.3 }, { 0.6, 1, 0.4 },
  { 0.9, 0.5, 1 }, { 1, 1, 1 }, { 1, 0.6, 0.8 }, { 0.5, 1, 0.9 },
}
local function QuestColor(questID)
  local c = COLORS[questID % #COLORS + 1]
  return c[1], c[2], c[3]
end
ns.QuestColor = QuestColor

local function LearnedTurnIns(mapID)
  local list = {}
  if not ns.db.learnPins then return list end
  for questID, e in pairs(ns.db.learned) do
    if e.finish and e.finish.map == mapID and ns.InQuestLog(questID) and ns.IsQuestComplete(questID)
        and not (ns.db.pinsOnlyUnknown and ns.QuestieKnows(questID) == true) then
      list[#list + 1] = { kind = "turnin", questID = questID, x = e.finish.x, y = e.finish.y, npc = e.finish.npc }
    end
  end
  return list
end

-- Everything for one map (also used by the tests).
-- (1.23) Once per map and scope: the world map and the minimap of the same
-- zone share it in the batched refresh. Callers only read the list.
local BuildPins
function ns.PinsForMap(mapID)
  return ns.Memo("pins", mapID, BuildPins)
end
function BuildPins(mapID)
  local pins = {}
  if not mapID then return pins end
  if ns.db.availablePins then
    -- (1.22) with the quests of the next levels (option "upcomingLevels"), dimmed
    for _, a in ipairs(ns.AvailableQuestsOnMap(mapID, true)) do
      if not ns.DrawnElsewhere(a.questID, "start") then
        a.kind = "available"
        pins[#pins + 1] = a
      end
    end
  end
  for _, t in ipairs(LearnedTurnIns(mapID)) do pins[#pins + 1] = t end
  -- (1.2) the quest picked in the zone quest list (ZoneQuests.lua)
  local focus = ns.ZoneFocusPin and ns.ZoneFocusPin(mapID)
  if focus then pins[#pins + 1] = focus end
  if ns.db.objectivePins then
    for _, o in ipairs(ns.ObjectivePointsOnMap(mapID)) do
      o.kind = "objective"
      pins[#pins + 1] = o
    end
  end
  return pins
end

local function GiverText(pin)
  if pin.npc then return pin.npc end
  local givers = ns.QuestGiverIDs(pin.questID)
  local name = givers and ns.CreatureName(givers[1])
  return name
end

-- (1.21) Quest givers with several quests. Available quests that start at
-- the same spot (closer than GROUP_DIST in 0-1 map coordinates, about the
-- size of a pin) used to stack: only the top pin could be hovered. Now they
-- become one pin with pin.group = { pins, sorted by level }. The pin list of
-- ns.PinsForMap (API, signature) stays one entry per quest; only the display
-- (world map, minimap) groups. Turn-ins and objective dots are never grouped.
-- (1.25) Two nearly overlapping "!" for one quest giver: a start Questdon
-- learned is where the player stood when talking (a few yards off the NPC),
-- the data has the NPC's own spot, and two NPCs can stand side by side.
-- Pins of the same quest giver (creature ID from the data or the learned
-- start) now group up to GIVER_DIST apart, any two up to GROUP_DIST as before.
local GROUP_DIST, GIVER_DIST = 0.004, 0.015
local dupStats = { merged = 0, lastMerged = 0, suppressed = 0, lastSuppressed = 0 }
local function MinLevel(questID)
  return ns.QuestLevel(questID) or 0
end
-- Creature IDs of the quest giver(s) of a pin: learned start NPC, else the data.
-- (pin lists are never changed after they are built: a weak cache instead of a field)
local giverCache = setmetatable({}, { __mode = "k" })
local function GiverIDs(p)
  local ids = giverCache[p]
  if ids == nil then
    local e = ns.db.learned and ns.db.learned[p.questID]
    local npc = e and e.start and not e.start.item and ns.Num(e.start.npcID)
    ids = npc and { npc } or ns.QuestGiverIDs(p.questID) or false
    giverCache[p] = ids
  end
  return ids or nil
end
local function SameGiver(a, b)
  local ga, gb = GiverIDs(a), GiverIDs(b)
  if not (ga and gb) then return false end
  for _, x in ipairs(ga) do
    for _, y in ipairs(gb) do if x == y then return true end end
  end
  return false
end
-- One spot for display: close together, or the same quest giver a bit apart.
-- (1.28) cluster: optional wider distance (world map only, option "clusterPins")
local function SameSpot(a, b, cluster)
  local dx, dy = math.abs(a.x - b.x), math.abs(a.y - b.y)
  if dx < GROUP_DIST and dy < GROUP_DIST then return true, false end
  if dx < GIVER_DIST and dy < GIVER_DIST and SameGiver(a, b) then return true, true end
  if cluster and dx < cluster and dy < cluster then return true, false end
  return false, false
end
ns.SameQuestGiverSpot = SameSpot
function ns.GroupQuestPins(pins, cluster)
  local out, heads = {}, {}
  dupStats.lastMerged = 0
  for _, p in ipairs(pins or {}) do
    local head
    if p.kind == "available" and p.x and p.y then
      for _, h in ipairs(heads) do
        local same, byGiver = SameSpot(h.pin, p, cluster)
        if same then
          head = h
          if byGiver then dupStats.merged = dupStats.merged + 1 dupStats.lastMerged = dupStats.lastMerged + 1 end
          break
        end
      end
    end
    if head then
      head.members[#head.members + 1] = p
    else
      local entry = { pin = p, members = { p }, x = p.x, y = p.y }
      if p.kind == "available" then heads[#heads + 1] = entry end
      out[#out + 1] = entry
    end
  end
  for i, e in ipairs(out) do
    if #e.members == 1 then
      out[i] = e.pin
    else
      table.sort(e.members, function(a, b)
        local la, lb = MinLevel(a.questID), MinLevel(b.questID)
        if la ~= lb then return la < lb end
        return a.questID < b.questID
      end)
      -- a copy: the original pins stay untouched (signature, precomputed list)
      local g = {}
      for k, v in pairs(e.members[1]) do g[k] = v end
      g.group = e.members
      out[i] = g
    end
  end
  return out
end

-- (1.25) Quests the game itself shows as available (its quest lines list
-- them with a spot): the modern client draws its own "!" for them, so a
-- Questdon "!" there is a second one. With the option "skipGameGivers" (on
-- by default) Questdon leaves such quest givers to the game: the quest and
-- every other available pin at the same giver are not drawn (world map and
-- minimap). Panel, nameplates and unit tooltips keep them.
function ns.SkipGameShownPins(pins)
  local n = 0
  if not (ns.db and ns.db.skipGameGivers) then dupStats.lastSuppressed = 0 return pins or {}, 0 end
  local game = {}
  for _, p in ipairs(pins or {}) do
    if p.kind == "available" and p.gameShown and p.x and p.y then game[#game + 1] = p end
  end
  if #game == 0 then dupStats.lastSuppressed = 0 return pins or {}, 0 end
  local out = {}
  for _, p in ipairs(pins) do
    local drop = false
    if p.kind == "available" and p.x and p.y then
      if p.gameShown then
        drop = true
      else
        for _, g in ipairs(game) do
          if SameSpot(g, p) then drop = true break end
        end
      end
    end
    if drop then n = n + 1 else out[#out + 1] = p end
  end
  dupStats.suppressed = dupStats.suppressed + n
  dupStats.lastSuppressed = n
  return out, n
end

-- (1.25) What the world map and the minimap draw: game-drawn givers left
-- out, the rest grouped per quest giver.
function ns.DisplayQuestPins(pins, cluster)
  return ns.GroupQuestPins((ns.SkipGameShownPins(pins)), cluster)
end

-- (1.28) Option "Merge markers": distance (0-1 map coordinates) under which
-- available pins of the world map merge, from the zoom of the map canvas.
-- The canvas scale is rounded to half steps (a zoom animation must not
-- rebuild the pins every frame). Zoomed in, the same distance is a smaller
-- part of the map, so the markers come apart. nil when the option is off.
local CLUSTER_DIST = 0.015
function ns.ClusterBucket(scale)
  scale = ns.Num(scale)
  if not scale or scale < 1 then return 1 end
  if scale > 8 then scale = 8 end
  return math.floor(scale * 2 + 0.5) / 2
end
function ns.ClusterDistance(scale)
  if not (ns.db and ns.db.clusterPins) then return nil end
  return CLUSTER_DIST / ns.ClusterBucket(scale)
end
function ns.DuplicatePinStats() return dupStats end

-- (1.21) Title of a grouped pin: the quest giver if all quests share it,
-- else "n quests here".
local function GroupTitle(pin)
  local name
  for i, p in ipairs(pin.group) do
    local giver = GiverText(p)
    if i == 1 then name = giver elseif giver ~= name then name = nil end
    if not name then break end
  end
  return name or L["%d quests here"]:format(#pin.group)
end
ns.QuestGroupTitle = GroupTitle

-- (1.26) How many levels below yours a quest is still green (not grey): the
-- client's own answer (UnitQuestTrivialLevelRange, in the Forever API
-- documentation), else the older GetQuestGreenRange, else 8.
function ns.QuestTrivialRange()
  local r = ns.Num(ns.Value(UnitQuestTrivialLevelRange, "player")) or ns.Num(ns.Value(GetQuestGreenRange))
  if r and r >= 0 then return r end
  return 8
end

-- (1.17) Difficulty colour for a quest level against the player level, own
-- rules (no Blizzard helper): red +5, orange +3, yellow +-2, green inside the
-- green range, grey below.
function ns.LevelColor(level, player)
  player = player or ns.PlayerLevel()
  if not (ns.Num(level) and ns.Num(player)) then return "|cffffffff" end
  local d = level - player
  if d >= 5 then return "|cffff2020" end
  if d >= 3 then return "|cffff8040" end
  if d >= -2 then return "|cffffff00" end
  if d >= -ns.QuestTrivialRange() then return "|cff40c040" end
  return "|cff808080"
end

-- (1.17) Where the start point of an available quest comes from:
-- "game" (the client's quest lines), "learned" (Questdon saw it) or "database" (ATT).
function ns.StartSource(questID)
  local e = ns.db.learned[questID]
  if e and e.start and not e.start.item then
    return e.start.source == "blizzard" and "game" or "learned"
  end
  return "database"
end

local SOURCE_TEXT = {
  game = L["Location: from the game (quest lines)"],
  learned = L["Location: learned by Questdon"],
  database = L["Location: database (All The Things)"],
}

-- (1.24) Who confirmed that the quest is available.
local AVAILABLE_TEXT = {
  game = L["Available: confirmed by the game"],
  npc = L["Available: confirmed by the quest giver"],
  database = L["Available: only the data says so (not confirmed)"],
}
local AVAILABLE_SHORT = {
  game = L["confirmed by the game"],
  npc = L["confirmed by the quest giver"],
  database = L["data only, not confirmed"],
}
ns.AVAILABLE_SHORT = AVAILABLE_SHORT

-- (1.17) Tooltip text of a quest start / turn-in pin (also used by the tests).
function ns.QuestPinDescription(pin)
  local desc
  if pin.kind == "turnin" then
    desc = L["Turn in here"]
    local rewards = ns.QuestRewardLines and ns.QuestRewardLines(pin.questID) or {}
    if #rewards > 0 then desc = desc .. "\n" .. table.concat(rewards, "\n") end
  elseif pin.notOffered and not pin.upcoming then
    desc = L["Not offered by the quest giver (level %d)"]:format(pin.notOffered) -- (1.24)
  elseif pin.learned then
    desc = L["Quest available (learned by Questdon)"]
  else
    desc = L["Quest available"]
  end
  local function Add(line) desc = desc .. "\n" .. line end
  if pin.kind ~= "turnin" then
    -- (1.22) an unknown level is said, never guessed
    local level = ns.QuestLevel(pin.questID)
    if level then Add(ns.LevelColor(level) .. L["Level %d"]:format(level) .. "|r")
    else Add("|cff737880" .. L["Level unknown"] .. "|r") end
    if pin.upcoming then Add("|cff737880" .. L["Not yet: from level %d"]:format(pin.upcoming) .. "|r") end
    if pin.upcoming and pin.notOffered then Add("|cff737880" .. L["Not offered by the quest giver (level %d)"]:format(pin.notOffered) .. "|r") end
  end
  local giver = GiverText(pin)
  if giver then Add(L["Quest giver: %s"]:format(giver)) end
  if pin.kind ~= "turnin" then
    local follow = #(ns.FollowUpQuests and ns.FollowUpQuests(pin.questID) or {})
    if follow == 1 then Add(L["Starts a chain: 1 follow-up quest known"])
    elseif follow > 1 then Add(L["Starts a chain: %d follow-up quests known"]:format(follow)) end
  end
  if ns.QuestFlags(pin.questID):find("b", 1, true) then Add(L["Breadcrumb quest"]) end
  -- (1.18) dungeon quest: name of the dungeon (Forever pays these quests extra XP)
  local dungeon = ns.QuestDungeon and ns.QuestDungeon(pin.questID)
  if dungeon then Add("|cff66ccff" .. L["Dungeon quest: %s"]:format(ns.DungeonName(dungeon)) .. "|r") end
  -- (1.18) group members with this quest (dungeon quests cannot be shared since beta 2026-09-24)
  local who = pin.kind ~= "turnin" and ns.PartyMembersWithQuest and ns.PartyMembersWithQuest(pin.questID) or {}
  if #who > 0 then Add("|cff99ccff" .. L["Your group has it: %s"]:format(table.concat(who, ", ")) .. "|r") end
  if pin.kind ~= "turnin" and ns.IsItemStartQuest(pin.questID) then
    Add(L["Starts from an item (drop or object nearby)"])
  end
  if pin.kind ~= "turnin" then Add("|cff999999" .. SOURCE_TEXT[ns.StartSource(pin.questID)] .. "|r") end
  -- (1.24) who says it is available: the game, a quest giver or only the data
  if pin.kind ~= "turnin" and not (pin.upcoming or pin.notOffered) then
    Add("|cff999999" .. AVAILABLE_TEXT[ns.AvailabilitySource(pin.questID)] .. "|r")
  end
  -- (1.21) grouped pin: the other quests of this quest giver
  if pin.group and #pin.group > 1 then
    Add(L["Also here:"])
    for i = 2, #pin.group do Add("  " .. ns.QuestTitle(pin.group[i].questID)) end
  end
  return desc
end

-- (1.1) Hint of a quest pin: Alt-click reports "no quest here" (not for turn-ins).
function ns.QuestPinHint(pin)
  if pin and pin.kind ~= "turnin" and ns.ReportPin then
    return L["Click: point the arrow here"] .. "\n" .. L["Alt-click: no quest here (hide it)"]
  end
  return L["Click: point the arrow here"]
end

-- (1.1) "level 5, 6 (hidden after 3)"
function ns.NotHereLevelText(levels)
  local parts = {}
  for _, lv in ipairs(levels) do parts[#parts + 1] = tostring(lv) end
  return L["level %s (hidden after %d)"]:format(table.concat(parts, ", "), ns.NOT_HERE_LEVELS or 3)
end

-- (1.19) Quest pin tooltip in the family structure: title, key/value lines,
-- hint last (rendered with Style.Tooltip). Returns title, lines, hint.
local SOURCE_SHORT = {
  game = L["from the game (quest lines)"],
  learned = L["learned by Questdon"],
  database = L["database (All The Things)"],
}
local function LevelRGB(level)
  local code = ns.LevelColor(level)
  local r, g, b = code:match("|cff(%x%x)(%x%x)(%x%x)")
  if not r then return nil end
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

function ns.QuestPinTooltip(pin)
  local lines = {}
  local function KV(label, value, color) lines[#lines + 1] = { label, value, color } end
  -- (1.2) the quest picked in the zone quest list: its status there
  if pin.kind == "focus" then
    KV(L["Status"], pin.statusText or "")
    local level = ns.QuestLevel(pin.questID)
    if level then KV(L["Level"], level, LevelRGB(level)) else KV(L["Level"], L["unknown"], "textHint") end
    local giver = GiverText(pin)
    if giver then KV(L["Quest giver"], giver) end
    return ns.QuestTitle(pin.questID), lines, L["Picked in the quest list of the zone."]
  end
  if pin.kind == "turnin" then
    lines[#lines + 1] = L["Turn in here"]
    for _, r in ipairs(ns.QuestRewardLines and ns.QuestRewardLines(pin.questID) or {}) do KV(L["Reward"], r) end
  else
    if pin.upcoming then
      lines[#lines + 1] = L["Not yet: from level %d"]:format(pin.upcoming)
      if pin.notOffered then lines[#lines + 1] = L["Not offered by the quest giver (level %d)"]:format(pin.notOffered) end
    elseif pin.notOffered then
      lines[#lines + 1] = L["Not offered by the quest giver (level %d)"]:format(pin.notOffered) -- (1.24)
    else
      lines[#lines + 1] = pin.learned and L["Quest available (learned by Questdon)"] or L["Quest available"]
    end
    -- (1.22) an unknown level is said, never guessed
    local level = ns.QuestLevel(pin.questID)
    if level then KV(L["Level"], level, LevelRGB(level)) else KV(L["Level"], L["unknown"], "textHint") end
  end
  local giver = GiverText(pin)
  if giver then KV(L["Quest giver"], giver) end
  if pin.kind ~= "turnin" then
    local follow = #(ns.FollowUpQuests and ns.FollowUpQuests(pin.questID) or {})
    if follow > 0 then KV(L["Chain"], L["%d follow-up quests known"]:format(follow)) end
  end
  if ns.QuestFlags(pin.questID):find("b", 1, true) then lines[#lines + 1] = L["Breadcrumb quest"] end
  local dungeon = ns.QuestDungeon and ns.QuestDungeon(pin.questID)
  if dungeon then KV(L["Dungeon"], ns.DungeonName(dungeon), "accent") end
  local who = pin.kind ~= "turnin" and ns.PartyMembersWithQuest and ns.PartyMembersWithQuest(pin.questID) or {}
  if #who > 0 then KV(L["Your group has it"], table.concat(who, ", "), "good") end
  if pin.kind ~= "turnin" and ns.IsItemStartQuest(pin.questID) then
    lines[#lines + 1] = L["Starts from an item (drop or object nearby)"]
  end
  if pin.kind ~= "turnin" then KV(L["Location"], SOURCE_SHORT[ns.StartSource(pin.questID)]) end
  -- (1.24) who says it is available
  if pin.kind ~= "turnin" and not (pin.upcoming or pin.notOffered) then
    local src = ns.AvailabilitySource(pin.questID)
    KV(L["Available"], AVAILABLE_SHORT[src], src == "database" and "textHint" or "good")
  end
  -- (1.1) levels at which the quest giver did not offer it (hidden after 3)
  local refused = pin.kind ~= "turnin" and ns.NotHereLevels and ns.NotHereLevels(pin.questID)
  if refused then KV(L["Not offered at"], ns.NotHereLevelText(refused), "textHint") end
  return ns.QuestTitle(pin.questID), lines, ns.QuestPinHint(pin)
end

-- (1.21) Tooltip of a grouped quest giver pin: one line per quest (title,
-- level in difficulty colour), below it dungeon and group if known. At most
-- GROUP_LINES quests, then "and n more".
local GROUP_LINES = 10
function ns.QuestGroupTooltip(pin)
  local lines = {}
  local group = pin.group or { pin }
  for i, p in ipairs(group) do
    if i > GROUP_LINES then
      lines[#lines + 1] = L["and %d more"]:format(#group - GROUP_LINES)
      break
    end
    local level = ns.QuestLevel(p.questID)
    local title = ns.QuestTitle(p.questID)
    if ns.QuestFlags(p.questID):find("b", 1, true) then title = title .. " (" .. L["Breadcrumb quest"] .. ")" end
    if p.upcoming then
      lines[#lines + 1] = { title, L["from level %d"]:format(p.upcoming), "textHint" }
    elseif p.notOffered then
      lines[#lines + 1] = { title, L["not offered (level %d)"]:format(p.notOffered), "textHint" } -- (1.24)
    elseif level then
      lines[#lines + 1] = { title, L["Level %d"]:format(level), LevelRGB(level) }
    else
      lines[#lines + 1] = { title, L["Level unknown"], "textHint" } -- (1.22) said, never guessed
    end
    local dungeon = ns.QuestDungeon and ns.QuestDungeon(p.questID)
    if dungeon then lines[#lines + 1] = { "   " .. L["Dungeon"], ns.DungeonName(dungeon), "accent" } end
    local who = ns.PartyMembersWithQuest and ns.PartyMembersWithQuest(p.questID) or {}
    if #who > 0 then lines[#lines + 1] = { "   " .. L["Your group has it"], table.concat(who, ", "), "good" } end
  end
  return GroupTitle(pin), lines, ns.QuestPinHint(pin)
end

-- Small square in the quest's dot colour (texture escape with vertex colour).
local function Swatch(questID)
  local r, g, b = QuestColor(questID)
  return ("|TInterface\\Buttons\\WHITE8x8:8:8:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(r * 255, g * 255, b * 255)
end

-- (1.19) Objective dot tooltip: title with the dot colour, what to do, where
-- it comes from, rewards; hint last.
function ns.ObjectivePinTooltip(pin)
  local lines = {}
  if pin.text then lines[#lines + 1] = { L["Objective"], pin.text } end
  local creature = pin.creature and ns.CreatureName(pin.creature)
  if creature then lines[#lines + 1] = { L["Creature"], creature } end
  if pin.needsItem then
    lines[#lines + 1] = { L[pin.dimmed and "Use %s here. First get it." or "Get %s here."]:format(ns.ItemName(pin.needsItem)) }
  end
  -- (1.2) no rewards here any more: the dot says what to do, the rewards are in the quest log
  return Swatch(pin.questID) .. ns.QuestTitle(pin.questID), lines, L["Click: point the arrow here"]
end

-- (1.17) Signature of a pin set: refreshes from events skip the rebuild when
-- nothing visible changed (same map, same pins, same texts).
local lastSig, precomputed
local clusterBucket = 1 -- (1.28) zoom step the pins were last built for
local stats = { builds = 0, skipped = 0 }
local function PinKey(p)
  local extra = ""
  if p.kind ~= "objective" then
    extra = ns.QuestTitle(p.questID)
    if p.kind == "turnin" and ns.QuestRewardLines then extra = extra .. table.concat(ns.QuestRewardLines(p.questID) or {}, ",") end
    if p.kind ~= "turnin" and ns.PartyMemberCount and ns.PartyMemberCount() > 0 then
      extra = extra .. "|" .. table.concat(ns.PartyMembersWithQuest(p.questID), ",")
    end
  end
  -- (1.23) one string per pin (was a table of 13 strings)
  return ("%s:%s:%s:%.4f:%.4f:%s:%s:%s:%s:%s:%s:%s:%s"):format(tostring(p.kind), tostring(p.questID), tostring(p.index or ""),
    tonumber(p.x) or 0, tonumber(p.y) or 0, (p.dimmed and "d" or "") .. (p.small and "s" or ""), p.learned and "l" or "",
    tostring(p.upcoming or "") .. "/" .. tostring(p.notOffered or "") .. (p.confirmed and "c" or "") .. (p.gameShown and "g" or ""), -- (1.24, 1.25)
    tostring(p.npc or ""), tostring(p.text or "") .. tostring(p.statusText or "") .. tostring(p.iconKind or ""), tostring(p.needsItem or ""), tostring(p.creature or ""), extra)
end
local function Signature(mapID, pins)
  local keys = {}
  for i, p in ipairs(pins) do keys[i] = PinKey(p) end
  table.sort(keys)
  return tostring(mapID) .. "|" .. tostring(ns.db.objectivePinSize or 12) .. "|" .. table.concat(keys, ";")
end
-- (1.23) The world map and the minimap of the same zone compare the same pin
-- list (ns.PinsForMap, once per scope) in the batched refresh: the signature
-- of that list is worked out once. Pin lists are never changed after they
-- are built; every refresh builds a new one.
local sigPins, sigMap, sigValue
function ns.PinsSignature(mapID, pins)
  if pins ~= sigPins or mapID ~= sigMap then
    sigPins, sigMap, sigValue = pins, mapID, Signature(mapID, pins)
  end
  return sigValue
end
function ns.MapPinStats() return stats end

local setupFailed = false
local Setup
function Setup()
  if provider or setupFailed then return end
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and BaseMapPoiPinMixin
          and BaseMapPoiPinMixin.CreateSubPin and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end

  -- Quest start / turn-in: Blizzard's POI pin look ("!" and "?").
  QuestdonQuestPinMixin = BaseMapPoiPinMixin:CreateSubPin("PIN_FRAME_LEVEL_AREA_POI")
  local QuestPin = QuestdonQuestPinMixin
  function QuestPin:OnAcquired(pin)
    local title = ns.QuestTitle(pin.questID)
    -- (1.22) "[?]" for a quest without a known level (never guessed)
    -- (1.26) the level in its difficulty colour, as in the panel and the tooltips
    title = ns.QuestLevelTag(pin.questID) .. title
    -- (1.21) quest giver with several quests: one pin
    if pin.group and #pin.group > 1 then title = title .. " " .. L["(+%d more)"]:format(#pin.group - 1) end
    -- (1.20) the description (rewards, chain, group, giver) is built only
    -- when something asks for it: our own tooltip does not use it
    BaseMapPoiPinMixin.OnAcquired(self, {
      name = title,
      atlasName = (pin.kind == "turnin" or pin.iconKind == "turnin") and "QuestTurnin" or "QuestNormal",
      position = CreateVector2D(pin.x, pin.y),
    })
    self.qdName, self.qdDesc, self.qdPin = title, nil, pin
    -- (1.22) quests of the next levels: dimmed, like on the minimap
    -- (1.24) and quests the quest giver did not offer at your level
    if self.SetAlpha then pcall(self.SetAlpha, self, (pin.upcoming or pin.notOffered or pin.dimmed) and 0.5 or 1) end
  end
  -- Left click: point the arrow there.
  function QuestPin:OnMouseClickAction(button)
    -- (1.1) Alt-click: "no quest here" (NotHere.lua)
    if button == "LeftButton" and self.qdPin and self.qdPin.kind ~= "focus" and ns.True(ns.Value(IsAltKeyDown)) and ns.ReportPin then
      ns.ReportPin(self.qdPin)
      return
    end
    if button == "LeftButton" and self.qdPin then
      local label = self.qdPin.group and ns.QuestGroupTitle(self.qdPin) or ns.QuestTitle(self.qdPin.questID)
      ns.PointArrowFromPin(ns.Num(self:GetMap():GetMapID()), self.qdPin.x, self.qdPin.y, label)
    end
  end
  -- (1.2) map canvases that call OnClick instead of OnMouseClickAction
  QuestPin.OnClick = ns.Guard("map click", function(self, button) self:OnMouseClickAction(button) end)
  function QuestPin.UseTooltip() return true end
  function QuestPin:GetBestNameAndDescription()
    if self.qdDesc == nil and self.qdPin then self.qdDesc = ns.QuestPinDescription(self.qdPin) end
    return self.qdName, self.qdDesc
  end
  -- (1.19) own tooltip in the family structure (our mixin, our pins only)
  QuestPin.OnMouseEnter = ns.Guard("map tooltip", function(self)
    if not self.qdPin then return end
    local tip = self.qdPin.group and ns.QuestGroupTooltip or ns.QuestPinTooltip
    local title, lines, hint = tip(self.qdPin)
    ns.Style.Tooltip(self, title, lines, hint)
  end)
  function QuestPin:OnMouseLeave() ns.Style.HideTooltip(self) end

  -- Objective spawns: small coloured dots.
  QuestdonObjectivePinMixin = CreateFromMixins(MapCanvasPinMixin)
  local ObjPin = QuestdonObjectivePinMixin
  function ObjPin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    if self.SetScalingLimits then self:SetScalingLimits(1, 0.9, 1.4) end
  end
  function ObjPin:OnAcquired(pin)
    self.pin = pin
    local size = ns.db.objectivePinSize or 12
    if pin.small then size = math.max(6, math.floor(size * 0.7 + 0.5)) end -- (1.2) many spawns: smaller dots
    self:SetSize(size, size)
    self:SetPosition(pin.x, pin.y)
    if self.Dot then self.Dot:SetVertexColor(QuestColor(pin.questID)) end
    -- place of use of an item not yet in the bags: dimmed
    if self.SetAlpha then self:SetAlpha(pin.dimmed and 0.35 or 1) end
  end
  ObjPin.OnMouseEnter = ns.Guard("map tooltip", function(self)
    if not self.pin then return end
    local title, lines, hint = ns.ObjectivePinTooltip(self.pin)
    ns.Style.Tooltip(self, title, lines, hint)
  end)
  function ObjPin:OnMouseLeave() ns.Style.HideTooltip(self) end
  function ObjPin:OnMouseClickAction(button)
    if button == "LeftButton" and self.pin then
      ns.PointArrowFromPin(ns.Num(self:GetMap():GetMapID()), self.pin.x, self.pin.y, ns.QuestTitle(self.pin.questID))
    end
  end
  ObjPin.OnClick = ns.Guard("map click", function(self, button) self:OnMouseClickAction(button) end)

  -- The map canvas calls these: protected, so an error here never breaks the map.
  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  p.RemoveAllData = ns.Guard("map", function(self)
    lastSig = nil
    self:GetMap():RemoveAllPinsByTemplate(QUEST_TEMPLATE)
    self:GetMap():RemoveAllPinsByTemplate(OBJECTIVE_TEMPLATE)
  end)
  p.RefreshAllData = ns.Guard("map", function(self)
    self:RemoveAllData()
    if InCombatLockdown() then return end
    local mapID = ns.Num(self:GetMap():GetMapID())
    if not mapID then precomputed = nil return end
    local pins, sig
    if precomputed and precomputed.mapID == mapID then
      pins, sig = precomputed.pins, precomputed.sig
    else
      if ns.HarvestQuestLines then ns.HarvestQuestLines(mapID) end
      pins = ns.PinsForMap(mapID)
    end
    precomputed = nil
    -- (1.21) quest givers with several quests: one pin (display only)
    -- (1.25) and no second "!" where the game draws one
    local map = self:GetMap()
    local scale = ns.db.clusterPins and map.GetCanvasScale and ns.Value(map.GetCanvasScale, map) or nil
    clusterBucket = ns.ClusterBucket(scale)
    for _, pin in ipairs(ns.DisplayQuestPins(pins, ns.ClusterDistance(scale))) do
      self:GetMap():AcquirePin(pin.kind == "objective" and OBJECTIVE_TEMPLATE or QUEST_TEMPLATE, pin)
    end
    stats.builds = stats.builds + 1
    lastSig = sig or ns.PinsSignature(mapID, pins)
  end)
  -- (1.28) zoomed: only with "Merge markers" on, and only when the rounded zoom step changed
  p.OnCanvasScaleChanged = ns.Guard("map", function(self)
    if not ns.db.clusterPins or InCombatLockdown() or not self:GetMap() then return end
    local map = self:GetMap()
    local scale = map.GetCanvasScale and ns.Value(map.GetCanvasScale, map) or nil
    if ns.ClusterBucket(scale) ~= clusterBucket then self:RefreshAllData() end
  end)
  local ok = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, p)
  if ok then provider = p else setupFailed = true end
end

-- For /qd diag: are the map pins set up?
function ns.MapPinsState()
  if provider then return "ready" end
  if setupFailed then return "failed (AddDataProvider)" end
  if not WorldMapFrame then return "waiting for the world map" end
  return "not available (map APIs missing)"
end

-- (1.2) A click on a pin points the arrow there and switches the arrow on if
-- it was off (before, the click set the target of a hidden arrow).
function ns.PointArrowFromPin(mapID, x, y, label)
  if not (mapID and x and y and ns.SetArrowTarget) then return end
  if not ns.db.arrow then
    ns.db.arrow = true
    if ns.ApplyArrow then ns.ApplyArrow() end
  end
  ns.SetArrowTarget(mapID, x, y, label)
end

function ns.RefreshPins()
  if not provider then Setup() end -- world map loaded later than expected
  if provider and provider:GetMap() and WorldMapFrame:IsShown() then
    provider:RefreshAllData()
  end
  -- (1.21) options and /qd commands: the minimap pins follow
  if ns.RefreshMinimapPins then ns.RefreshMinimapPins(true) end
  -- (1.22) and the nameplate icons
  if ns.RefreshNameplates then ns.RefreshNameplates() end
end

-- (1.17) Event path: rebuild only when the pins changed.
-- (1.20) In combat the pins stay as they are (before, every quest log update
-- in combat removed them all); the refresh after combat (PLAYER_REGEN_ENABLED)
-- compares the signature and rebuilds only if something changed.
local function RefreshIfChanged()
  if not provider then Setup() end
  if not (provider and provider:GetMap() and WorldMapFrame:IsShown()) then return end
  if InCombatLockdown() then stats.combat = (stats.combat or 0) + 1 return end
  local mapID = ns.Num(provider:GetMap():GetMapID())
  if mapID then
    if ns.HarvestQuestLines then ns.HarvestQuestLines(mapID) end
    local pins = ns.PinsForMap(mapID)
    local sig = ns.PinsSignature(mapID, pins)
    if lastSig and sig == lastSig then stats.skipped = stats.skipped + 1 return end
    precomputed = { mapID = mapID, pins = pins, sig = sig }
  end
  provider:RefreshAllData()
end
ns.RefreshPinsIfChanged = RefreshIfChanged

-- (1.23) Event path: one batched refresh for all quest displays (Core.lua).
ns.RegisterRefresh("map", RefreshIfChanged)
local function Queue() ns.QueueRefresh("map") end

-- (1.23) Learning (accept, turn-in) and other modules: the same batched
-- refresh for map, minimap and nameplates instead of a forced rebuild of all
-- three right before the QUEST_LOG_UPDATE batch does the same work again.
function ns.QueuePinRefresh()
  ns.QueueRefresh("map", "minimap", "nameplates")
end

ns.OnInit(Setup)
-- If the world map is loaded later (load on demand), set up then.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", ns.Guard("ADDON_LOADED", function(self, _, name)
  if name == "Blizzard_WorldMap" and ns.db then
    self:UnregisterEvent("ADDON_LOADED")
    Setup()
  end
end))
ns.On("PLAYER_REGEN_ENABLED", Queue)
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("QUEST_DATA_LOAD_RESULT", Queue)
ns.On("QUESTLINE_UPDATE", Queue)
ns.On("PLAYER_LEVEL_UP", Queue) -- (1.23) new level: other quests available (minimap and nameplates did this already)
ns.On("BAG_UPDATE_DELAYED", function()
  -- only matters while a pin depends on the bags (cheap check, queued refresh)
  if WorldMapFrame and WorldMapFrame:IsShown() then Queue() end
end)
