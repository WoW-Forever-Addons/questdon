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

-- (1.3) The game marks the turn-in of a finished quest itself (its quest
-- POI, a "?"): with the option "skipGameGivers" no second "?" from Questdon.
local function GameShowsTurnIn(questID)
  if not (ns.db and ns.db.skipGameGivers) or not ns.QuestPOI then return false end
  local m, _, _, kind = ns.QuestPOI(questID)
  return m ~= nil and kind == "turnin"
end
ns.GameShowsTurnIn = GameShowsTurnIn

-- (1.3.5, Daniel 10.10.) The "?" of a finished quest: not only where you turned it in before,
-- also what other players reported and the turn-in NPC of the data (ns.KnownTurnIn), as long as
-- the game does not mark the turn-in itself. Quests that complete from the log get none.
local function TurnIns(mapID)
  local list = {}
  if not ns.db.learnPins then return list end
  for _, info in ipairs(ns.QuestLogEntries()) do
    local questID = info.questID
    if ns.IsQuestComplete(questID) and not (ns.IsAutoComplete and ns.IsAutoComplete(questID))
        and not (ns.db.pinsOnlyUnknown and ns.QuestieKnows(questID) == true)
        and not GameShowsTurnIn(questID) then
      local m, x, y, npc, source = ns.KnownTurnIn(questID)
      if m == mapID and x and y then
        list[#list + 1] = { kind = "turnin", questID = questID, x = x, y = y, npc = npc, source = source }
      end
    end
  end
  return list
end

-- Everything for one map (also used by the tests).
-- (1.23) Once per map and scope: the world map and the minimap of the same
-- zone share it in the batched refresh. Callers only read the list.
-- (1.3.5) ns.PinsForMapBase: the same without the objective dots (the minimap takes its own).
local BuildPins, BuildBase
function ns.PinsForMap(mapID)
  return ns.Memo("pins", mapID, BuildPins)
end
function ns.PinsForMapBase(mapID)
  return ns.Memo("pinsBase", mapID, BuildBase)
end
function BuildPins(mapID)
  local pins = {}
  if not mapID then return pins end
  for _, p in ipairs(ns.PinsForMapBase(mapID)) do pins[#pins + 1] = p end
  if ns.db.objectivePins then
    for _, o in ipairs(ns.ObjectivePointsOnMap(mapID)) do
      o.kind = "objective"
      pins[#pins + 1] = o
    end
  end
  return pins
end
function BuildBase(mapID)
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
  for _, t in ipairs(TurnIns(mapID)) do pins[#pins + 1] = t end
  -- (1.2) the quest picked in the zone quest list (ZoneQuests.lua)
  local focus = ns.ZoneFocusPin and ns.ZoneFocusPin(mapID)
  if focus then pins[#pins + 1] = focus end
  -- (1.3.5) a marked dungeon entrance (Dungeons.lua), and the entrances of all dungeons
  local entrance = ns.EntrancePin and ns.EntrancePin(mapID)
  if entrance then pins[#pins + 1] = entrance end
  for _, d in ipairs(ns.DungeonEntrancePins and ns.DungeonEntrancePins(mapID) or {}) do pins[#pins + 1] = d end
  return pins
end

local function GiverText(pin)
  if pin.npc then return pin.npc end
  if pin.kind == "turnin" then return nil end -- (1.3.5) never the quest giver for a turn-in
  local givers = ns.QuestGiverIDs(pin.questID)
  local name = givers and ns.LocalNpcName(givers[1])
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
-- (1.3.3) Daniel 08.10., Zephras Isle: a Questdon "!" still stood next to the
-- game's one. The game draws at the spot of its quest lines (pin.gx/gy), which
-- can lie a little off the data's spot of the same quest; our other quests of
-- that giver were compared with the data's spot only and, with the tiny
-- distance, stayed. Now both spots count, with the overlap distance of the map.
function ns.SkipGameShownPins(pins, dist)
  local n = 0
  if not (ns.db and ns.db.skipGameGivers) then dupStats.lastSuppressed = 0 return pins or {}, 0 end
  local game = {}
  for _, p in ipairs(pins or {}) do
    if p.kind == "available" and p.gameShown and p.x and p.y then
      game[#game + 1] = p
      if p.gx and p.gy then game[#game + 1] = { kind = "available", questID = p.questID, x = p.gx, y = p.gy } end
    end
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
          if SameSpot(g, p, dist) then drop = true break end
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
  return ns.GroupQuestPins((ns.SkipGameShownPins(pins, cluster)), cluster)
end

-- (1.28) Option "Merge markers": distance (0-1 map coordinates) under which
-- available pins of the world map merge, from the zoom of the map canvas.
-- The canvas scale is rounded to half steps (a zoom animation must not
-- rebuild the pins every frame). Zoomed in, the same distance is a smaller
-- part of the map, so the markers come apart. nil when the option is off.
local CLUSTER_DIST = 0.015
-- (1.3.3) Daniel 08.10., Zephras Isle: its quest givers stand 0.2 to 0.8 map
-- units apart (0.002-0.008), so their "!" covered each other although none of
-- them shared a giver. Markers that would overlap on screen now always merge
-- (OVERLAP_DIST, zoom-scaled like the cluster); "Merge markers" merges wider.
local OVERLAP_DIST = 0.012
ns.MINIMAP_OVERLAP = 0.01 -- minimap: a fixed distance (about one marker at its usual zoom)
function ns.ClusterBucket(scale)
  scale = ns.Num(scale)
  if not scale or scale < 1 then return 1 end
  if scale > 8 then scale = 8 end
  return math.floor(scale * 2 + 0.5) / 2
end
function ns.ClusterDistance(scale)
  local d = ns.db and ns.db.clusterPins and CLUSTER_DIST or OVERLAP_DIST
  return d / ns.ClusterBucket(scale)
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
-- (1.3.4) One short grey line; Shift shows the details (where the data comes from).
local function Details() return ns.True(ns.Value(IsShiftKeyDown)) end
ns.TooltipDetails = Details
function ns.QuestPinHint(pin)
  local hint = (pin and pin.kind ~= "turnin" and ns.ReportPin) and L["Click: arrow, Alt-click: hide"] or L["Click: arrow"]
  if pin and pin.kind ~= "turnin" and not Details() then hint = hint .. ", " .. L["Shift: details"] end
  return hint
end

-- (1.3.4) Pressing or releasing Shift over a marker redraws its tooltip (details).
local hover = { owner = nil, fn = nil }
function ns.SetHoverTooltip(owner, fn) hover.owner, hover.fn = owner, owner and fn or nil end
ns.On("MODIFIER_STATE_CHANGED", function(key)
  if not (hover.owner and hover.fn) then return end
  if type(key) == "string" and not key:find("SHIFT", 1, true) then return end
  local tt = GameTooltip
  local ok, owned = pcall(tt and tt.IsOwned or function() return false end, tt, hover.owner)
  if ok and owned then ns.SafeCall("tooltip details", hover.fn, hover.owner) else hover.owner, hover.fn = nil, nil end
end)

-- (1.3.4) Daniel 08.10.: the level belongs in the title, "[6] Al'Aketh Assassins",
-- in the difficulty colour; "[?]" when the data has none (said, never guessed).
function ns.LevelTitle(questID)
  local level = ns.QuestLevel(questID)
  local tag = level and (ns.LevelColor(level) .. "[" .. level .. "]|r ") or "|cff737880[?]|r "
  return tag .. ns.QuestTitle(questID)
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
  -- (1.3.4) Daniel 08.10.: compact. The "!" already says "quest available" and the
  -- title carries the level; source and confirmation only with Shift held.
  local details = Details()
  if pin.kind == "turnin" then
    lines[#lines + 1] = L["Turn in here"]
    for _, r in ipairs(ns.QuestRewardLines and ns.QuestRewardLines(pin.questID) or {}) do KV(L["Reward"], r) end
  elseif pin.upcoming then
    lines[#lines + 1] = L["Not yet: from level %d"]:format(pin.upcoming)
    if pin.notOffered then lines[#lines + 1] = L["Not offered by the quest giver (level %d)"]:format(pin.notOffered) end
  elseif pin.notOffered then
    lines[#lines + 1] = L["Not offered by the quest giver (level %d)"]:format(pin.notOffered) -- (1.24)
  end
  local giver = GiverText(pin)
  if giver then KV(pin.kind == "turnin" and L["Turn in"] or L["Quest giver"], giver) end -- (1.3.5) the turn-in NPC as such
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
  -- (1.1) levels at which the quest giver did not offer it (hidden after 3)
  local refused = pin.kind ~= "turnin" and ns.NotHereLevels and ns.NotHereLevels(pin.questID)
  if refused then KV(L["Not offered at"], ns.NotHereLevelText(refused), "textHint") end
  if pin.kind ~= "turnin" then
    local src = not (pin.upcoming or pin.notOffered) and ns.AvailabilitySource(pin.questID) or nil
    if details then
      KV(L["Location"], SOURCE_SHORT[ns.StartSource(pin.questID)])
      if src then KV(L["Available"], AVAILABLE_SHORT[src], src == "database" and "textHint" or "good") end
    elseif src == "database" then
      -- (1.24) only the data says so: one small line instead of two
      lines[#lines + 1] = "|cff737880" .. L["Not confirmed yet"] .. "|r"
    end
  end
  return ns.LevelTitle(pin.questID), lines, ns.QuestPinHint(pin)
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
    -- (1.3.4) "[6] Title" like the single tooltip; a status only when there is one
    local title = ns.LevelTitle(p.questID)
    if ns.QuestFlags(p.questID):find("b", 1, true) then title = title .. " (" .. L["Breadcrumb quest"] .. ")" end
    if p.upcoming then
      lines[#lines + 1] = { title, L["from level %d"]:format(p.upcoming), "textHint" }
    elseif p.notOffered then
      lines[#lines + 1] = { title, L["not offered (level %d)"]:format(p.notOffered), "textHint" } -- (1.24)
    else
      lines[#lines + 1] = { title }
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
  local creature = pin.creature and ns.LocalNpcName(pin.creature)
  if creature then lines[#lines + 1] = { L["Creature"], creature } end
  if pin.needsItem then
    lines[#lines + 1] = { L[pin.dimmed and "Use %s here. First get it." or "Get %s here."]:format(ns.ItemName(pin.needsItem)) }
  end
  -- (1.2) no rewards here any more: the dot says what to do, the rewards are in the quest log
  return Swatch(pin.questID) .. ns.QuestTitle(pin.questID), lines, L["Click: point the arrow here"]
end

-- (1.3.5) A bundled dot (minimap, world map): how many spots, every objective it stands for once with its
-- quest in its colour and its number of spots, and the creatures there.
function ns.ObjectiveBundleTooltip(pins)
  pins = pins or {}
  local seen, list, spots, crSeen, creatures = {}, {}, {}, {}, {}
  for _, p in ipairs(pins) do
    local key = tostring(p.questID) .. ":" .. tostring(p.index)
    if not seen[key] then seen[key] = true list[#list + 1] = p end
    spots[p.questID or 0] = (spots[p.questID or 0] or 0) + 1
    local name = p.creature and ns.LocalNpcName(p.creature)
    if name and not crSeen[name] then crSeen[name] = true creatures[#creatures + 1] = name end
  end
  if #pins <= 1 then return ns.ObjectivePinTooltip(pins[1]) end
  table.sort(list, function(a, b)
    if (a.questID or 0) ~= (b.questID or 0) then return (a.questID or 0) < (b.questID or 0) end
    return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
  end)
  local lines, lastQuest = {}, nil
  for _, p in ipairs(list) do
    if p.questID ~= lastQuest then
      lastQuest = p.questID
      lines[#lines + 1] = { header = Swatch(p.questID) .. ns.QuestTitle(p.questID) .. " (" .. (spots[p.questID or 0] or 1) .. ")" }
    end
    if p.text then lines[#lines + 1] = { L["Objective"], p.text } end
  end
  if #creatures > 0 then lines[#lines + 1] = { L["Creature"], table.concat(creatures, ", ") } end
  return L["%d objective spots"]:format(#pins), lines, L["Click: point the arrow here"]
end

---------------------------------------------------------------------------
-- (1.3.5, Daniel 10.10., a quest field in Dun Morogh: "can be clustered more, or thinned, with that many")
-- Dense objective dots: a budget of markers. First the dots that lie on top of each other become one (the
-- round 5 rule, any quests). While more markers than the budget are left, the bundling distance grows by GROW
-- per step: up to SAME_STEPS steps only spots of the same quest join (the colour still tells the quest), then
-- MIX_STEPS more steps where any spots join. A bundle is the same dot a little larger (ns.BundleScale, at most
-- 1.3 times) at the middle of its spots; its tooltip names the quests and how many spots each has.
-- Points: { x, y (the same unit on both axes), q = quest, g = group (only the same group joins), f = how
-- willing it is to join (0.5-1; the minimap: near the player less), anchor = true: from the second step on it
-- joins nothing and takes only dots on top of it (the minimap: the nearest spot of each objective), pin }.
-- inView(point) says whether a marker counts for the budget (nil: all). Once per refresh or zoom step, never per
-- frame; a grid of cells, so 500 spots cost a few milliseconds at most. The same input gives the same output.
---------------------------------------------------------------------------
local GROW, SAME_STEPS, MIX_STEPS = 1.5, 8, 4
ns.THIN_GROW, ns.THIN_SAME_STEPS, ns.THIN_MIX_STEPS = GROW, SAME_STEPS, MIX_STEPS -- (tests)
local floor = math.floor

function ns.BundleScale(n)
  if n <= 1 then return 1 end
  if n <= 3 then return 1.1 end
  if n <= 6 then return 1.2 end
  return 1.3
end

-- The points live in reused arrays (ns.ThinBuffer), not in tables of their own: Daniel's minimap rebuilds a few
-- times a second while you walk, and fields added to its entries made every entry table larger. T.n points,
-- T.x, T.y, T.q, T.g, T.f (default 1), T.a (anchor) per point; T.order: the order they are taken in.
-- Out: T.head[i] = the point that draws point i, T.mx/T.my/T.cnt for heads.
local T = { n = 0, x = {}, y = {}, q = {}, g = {}, f = {}, a = {}, order = {}, head = {}, mx = {}, my = {}, sx = {}, sy = {}, cnt = {}, nxt = {} }
local grid, gridKeys = {}, {}
function ns.ThinBuffer(n)
  T.n = n
  local f, a, order = T.f, T.a, T.order
  for i = 1, n do f[i], a[i], order[i] = 1, false, i end
  for i = #order, n + 1, -1 do order[i] = nil end -- a longer list before: the order is sorted whole
  return T
end
local function Pass(base, level)
  local cell = base * GROW ^ level
  local mixed = level > SAME_STEPS
  local inv = 1 / cell
  local base2 = base * base
  local X, Y, Q, G, F, A, head, MX, MY, SX, SY, CNT, NXT = T.x, T.y, T.q, T.g, T.f, T.a, T.head, T.mx, T.my, T.sx, T.sy, T.cnt, T.nxt
  for i = 1, #gridKeys do grid[gridKeys[i]] = nil gridKeys[i] = nil end
  local order = T.order
  for k = 1, T.n do
    local i = order[k]
    local x, y = X[i], Y[i]
    head[i], MX[i], MY[i], SX[i], SY[i], CNT[i], NXT[i] = i, x, y, x, y, 1, false
    local cx, cy = floor(x * inv), floor(y * inv)
    local join
    if not (A[i] and level > 0) then -- an anchor joins nothing (it only takes dots on top of it)
      local r = level == 0 and cell or math.max(base, cell * F[i])
      local r2 = r * r
      local g, q = G[i], Q[i]
      for gx = cx - 1, cx + 1 do
        for gy = cy - 1, cy + 1 do
          local h = grid[gx * 1048576 + gy]
          while h and not join do
            if G[h] == g then
              local d2 = (MX[h] - x) ^ 2 + (MY[h] - y) ^ 2
              -- on top of each other: one; farther: same quest (later any quest), never into an anchor
              if d2 <= base2 or (level > 0 and d2 <= r2 and not A[h] and (mixed or Q[h] == q)) then join = h end
            end
            h = NXT[h]
          end
        end
      end
    end
    if join then
      head[i] = join
      local n = CNT[join] + 1
      CNT[join] = n
      SX[join], SY[join] = SX[join] + x, SY[join] + y
      MX[join], MY[join] = SX[join] / n, SY[join] / n
    else
      local key = cx * 1048576 + cy
      local first = grid[key]
      if not first then gridKeys[#gridKeys + 1] = key end
      NXT[i] = first or false
      grid[key] = i
    end
  end
end

-- Thins the points of the buffer (ns.ThinBuffer, filled by the caller). Returns the step used; T.head etc.
-- tell the result. budget nil: only the dots on top of each other. inView(T, i) says whether a head counts
-- for the budget (nil: all). prepare(T): called once before the first thinning step (order, anchors, f), so
-- a list within its budget costs one pass as in round 5.
function ns.ThinObjectivePoints(base, budget, inView, prepare)
  local level = 0
  local head = T.head
  while true do
    Pass(base, level)
    if not budget then break end
    local shown = 0
    for i = 1, T.n do if head[i] == i and (not inView or inView(T, i)) then shown = shown + 1 end end
    if shown <= budget or level >= SAME_STEPS + MIX_STEPS then break end
    if level == 0 and prepare then prepare(T) end
    -- the first step over the budget jumps by a guess from the area of a cell (the square of its size), rounded
    -- down so it seldom goes too far (fewer passes for 500 spots)
    local jump = level == 0 and math.floor(0.5 * math.log(shown / budget) / math.log(GROW)) or 1
    level = math.min(SAME_STEPS + MIX_STEPS, level + math.max(1, jump))
  end
  for i = 1, #gridKeys do grid[gridKeys[i]] = nil gridKeys[i] = nil end
  return level
end

-- (1.3.5) World map: about WORLD_BUDGET objective markers on a zone map seen whole; zoomed in (the canvas scale,
-- in the half steps of ns.ClusterBucket) the budget grows with the area (bucket squared), so about as many are
-- on screen. Distances in canvas pixels of a zone map (1002 x 668, so y counts 1/1.5 of x).
local WORLD_BUDGET, CANVAS_W, CANVAS_ASPECT = 50, 1002, 1.5
ns.WORLD_OBJECTIVE_BUDGET = WORLD_BUDGET
local worldStats = { thinned = 0, level = 0, before = 0, after = 0 }
function ns.WorldThinStats() return worldStats end
-- pins: the display list of the world map; objective dots in it become fewer markers, everything else as it is.
function ns.ThinWorldObjectives(pins, bucket, dotSize)
  worldStats.before, worldStats.after, worldStats.level, worldStats.thinned = 0, 0, 0, 0
  if ns.db.thinObjectives == false then return pins end
  bucket = bucket or 1
  local objs, out = {}, {}
  for _, p in ipairs(pins) do
    if p.kind == "objective" and tonumber(p.x) and tonumber(p.y) then objs[#objs + 1] = p else out[#out + 1] = p end
  end
  local n = #objs
  worldStats.before = n
  if n == 0 then return pins end
  local B = ns.ThinBuffer(n)
  for i, p in ipairs(objs) do B.x[i], B.y[i], B.q[i], B.g[i] = p.x, p.y / CANVAS_ASPECT, p.questID or 0, 0 end
  -- over the budget: quest by quest (then objective, place), so the same pins always give the same markers
  local function Prepare(T)
    table.sort(T.order, function(a, b)
      local pa, pb = objs[a], objs[b]
      if T.q[a] ~= T.q[b] then return T.q[a] < T.q[b] end
      local ia, ib = tonumber(pa.index) or 0, tonumber(pb.index) or 0
      if ia ~= ib then return ia < ib end
      if pa.x ~= pb.x then return pa.x < pb.x end
      if pa.y ~= pb.y then return pa.y < pb.y end
      return a < b
    end)
  end
  local base = 0.8 * (dotSize or 12) / (CANVAS_W * bucket)
  local level = ns.ThinObjectivePoints(base, WORLD_BUDGET * bucket * bucket, nil, Prepare)
  local members = {}
  for i = 1, n do
    local h = B.head[i]
    if h ~= i then
      local m = members[h]
      if not m then m = { objs[h] } members[h] = m end
      m[#m + 1] = objs[i]
    end
  end
  local heads = 0
  for i = 1, n do
    if B.head[i] == i then
      heads = heads + 1
      local m = members[i]
      if m then
        -- the bundle's colour: the quest with the most spots in it (the first of them on a tie)
        local count, best = {}, nil
        local dimmed, small = true, true
        for _, mp in ipairs(m) do
          local q = mp.questID or 0
          count[q] = (count[q] or 0) + 1
          if not best or count[q] > count[best] then best = q end
          if not mp.dimmed then dimmed = false end
          if not mp.small then small = false end
        end
        local p = objs[i]
        out[#out + 1] = { kind = "objective", questID = best, index = p.index, x = B.mx[i], y = B.my[i] * CANVAS_ASPECT,
          members = m, scale = ns.BundleScale(#m), dimmed = dimmed or nil, small = small or nil, text = p.text, creature = p.creature }
      else
        out[#out + 1] = objs[i]
      end
    end
  end
  worldStats.after, worldStats.level = heads, level
  worldStats.thinned = n - heads
  return out
end

-- (1.17) Signature of a pin set: refreshes from events skip the rebuild when
-- nothing visible changed (same map, same pins, same texts).
local lastSig, precomputed
local clusterBucket = 1 -- (1.28) zoom step the pins were last built for
local objBucket, objThinned = 1, false -- (1.3.5) zoom step of the objective thinning; true: another zoom can change the dots
local stats = { builds = 0, skipped = 0 }
local function PinKey(p)
  local extra = ""
  if p.kind == "entrance" or p.kind == "dungeon" then
    extra = tostring(p.name) .. tostring(p.inst)
  elseif p.kind ~= "objective" then
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
local builtMap -- (1.3.5) the map whose pins are drawn now (kept in combat)
local Setup
function Setup()
  if provider or setupFailed then return end
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and BaseMapPoiPinMixin
          and BaseMapPoiPinMixin.CreateSubPin and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end

  -- Quest start / turn-in: Blizzard's POI pin look ("!" and "?").
  QuestdonQuestPinMixin = BaseMapPoiPinMixin:CreateSubPin("PIN_FRAME_LEVEL_AREA_POI")
  local QuestPin = QuestdonQuestPinMixin
  -- (1.3.5, Daniel 10.10.) "Show on map": the entrance's pin pulses for a few seconds (our own glow
  -- texture on our own pin; pooled pins hide it again for anything else)
  local function ApplyHighlight(self, pin)
    local on = pin and (pin.kind == "dungeon" or pin.kind == "entrance") and ns.EntranceHighlighted and ns.EntranceHighlighted(pin.inst)
    if on and not self.qdGlow and self.CreateTexture then
      local g = self:CreateTexture(nil, "BACKGROUND")
      g:SetPoint("CENTER", self, "CENTER", 0, 0)
      g:SetSize(52, 52)
      g:SetTexture("Interface\\AddOns\\Questdon\\Media\\ArrowSealGlow")
      if g.SetBlendMode then pcall(g.SetBlendMode, g, "ADD") end
      g:SetVertexColor(1, 0.85, 0.5)
      if g.CreateAnimationGroup then
        local ok, group = pcall(g.CreateAnimationGroup, g)
        if ok and group then
          group:SetLooping("BOUNCE")
          local fade = group:CreateAnimation("Alpha")
          if fade then fade:SetFromAlpha(0.25) fade:SetToAlpha(1) fade:SetDuration(0.6) end
          self.qdPulse = group
        end
      end
      self.qdGlow = g
    end
    if self.qdGlow then
      if on then self.qdGlow:Show() if self.qdPulse then self.qdPulse:Play() end
      else self.qdGlow:Hide() if self.qdPulse then self.qdPulse:Stop() end end
    end
    self.qdHighlighted = on and true or false
  end
  function QuestPin:OnAcquired(pin)
    ApplyHighlight(self, pin)
    -- (1.3.5) a marked dungeon entrance: the game's dungeon entrance icon
    if pin.kind == "entrance" then
      local name = L["Entrance: %s"]:format(pin.name or "?")
      BaseMapPoiPinMixin.OnAcquired(self, { name = name, atlasName = "Dungeon", position = CreateVector2D(pin.x, pin.y) })
      self.qdName, self.qdDesc, self.qdPin = name, L["Click: dungeon journal, right-click: remove the mark"], pin
      if self.SetAlpha then pcall(self.SetAlpha, self, 1) end
      return
    end
    -- (1.3.5) the entrance of a dungeon (always there): the same icon, a little quieter than the mark
    if pin.kind == "dungeon" then
      BaseMapPoiPinMixin.OnAcquired(self, { name = pin.name or "?", atlasName = "Dungeon", position = CreateVector2D(pin.x, pin.y) })
      self.qdName, self.qdDesc, self.qdPin = pin.name or "?", L["Click: dungeon journal, right-click: arrow"], pin
      if self.SetAlpha then pcall(self.SetAlpha, self, 0.8) end
      return
    end
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
    -- (1.3.5) a dungeon entrance: a click opens the dungeon journal, right-click marks it (or removes the mark)
    if self.qdPin and self.qdPin.kind == "dungeon" then
      if button == "RightButton" then ns.DungeonPinRightClick(self.qdPin.inst)
      elseif button == "LeftButton" then ns.OpenDungeonJournal(self.qdPin.inst) end
      return
    end
    -- (round 8) the mark's pin: a click opens the dungeon journal too (the arrow already points there)
    if self.qdPin and self.qdPin.kind == "entrance" then
      if button == "RightButton" then ns.RemoveEntranceMark("pin")
      elseif button == "LeftButton" then ns.OpenDungeonJournal(self.qdPin.inst) end
      return
    end
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
  -- (1.3.5, Daniel 10.10.: "right-click on a dungeon entrance zooms out of the map") The map canvas lets
  -- right-clicks of every pin pass through to the map (zoom out) unless the pin says otherwise; it asks
  -- after OnAcquired. Entrance pins keep their right-click (the arrow mark); quest pins zoom out as before.
  function QuestPin:ShouldMouseButtonBePassthrough(button)
    local kind = self.qdPin and self.qdPin.kind
    if button == "RightButton" and (kind == "dungeon" or kind == "entrance") then return false end
    return button == "RightButton"
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
    local tip = self.qdPin.kind == "entrance" and ns.EntrancePinTooltip or self.qdPin.kind == "dungeon" and ns.DungeonPinTooltip
      or self.qdPin.group and ns.QuestGroupTooltip or ns.QuestPinTooltip
    local title, lines, hint = tip(self.qdPin)
    ns.Style.Tooltip(self, title, lines, hint)
    ns.SetHoverTooltip(self, self.OnMouseEnter) -- (1.3.4) Shift redraws it
  end)
  function QuestPin:OnMouseLeave() ns.Style.HideTooltip(self) ns.SetHoverTooltip(nil) end

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
    if pin.scale then size = math.min(math.floor(size * pin.scale + 0.5), math.floor(size * 1.3)) end -- (1.3.5) a bundle, at most 1.3 times
    self:SetSize(size, size)
    self:SetPosition(pin.x, pin.y)
    if self.Dot then self.Dot:SetVertexColor(QuestColor(pin.questID)) end
    -- place of use of an item not yet in the bags: dimmed
    if self.SetAlpha then self:SetAlpha(pin.dimmed and 0.35 or 1) end
  end
  ObjPin.OnMouseEnter = ns.Guard("map tooltip", function(self)
    if not self.pin then return end
    local title, lines, hint
    if self.pin.members then title, lines, hint = ns.ObjectiveBundleTooltip(self.pin.members) -- (1.3.5) a bundle
    else title, lines, hint = ns.ObjectivePinTooltip(self.pin) end
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
    lastSig, builtMap = nil, nil
    self:GetMap():RemoveAllPinsByTemplate(QUEST_TEMPLATE)
    self:GetMap():RemoveAllPinsByTemplate(OBJECTIVE_TEMPLATE)
  end)
  p.RefreshAllData = ns.Guard("map", function(self)
    -- (1.3.5, Daniel 10.10.: "entrance pins are not shown on the map in combat") New pins cannot be made in
    -- combat: the map canvas calls SetPassThroughButtons on every pin it hands out, and that may not be called
    -- by addon code in combat (#nocombat since 10.1.5). So the pins of the map last drawn stay as they are
    -- when that map is opened again in combat; only another map's pins go (they would stand in wrong places).
    -- Entering combat with the map closed, the player's zone is drawn beforehand (PLAYER_REGEN_DISABLED below).
    if InCombatLockdown() then
      local m = ns.Num(self:GetMap():GetMapID())
      if m and m == builtMap then stats.keptInCombat = (stats.keptInCombat or 0) + 1 return end
      self:RemoveAllData()
      return
    end
    self:RemoveAllData()
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
    local canvas = map.GetCanvasScale and ns.Value(map.GetCanvasScale, map) or nil
    local scale = ns.db.clusterPins and canvas or nil
    clusterBucket = ns.ClusterBucket(scale)
    -- (1.3.5) dense objective dots: fewer markers (quest givers and turn-ins are never thinned)
    objBucket = ns.ClusterBucket(canvas)
    local display = ns.ThinWorldObjectives(ns.DisplayQuestPins(pins, ns.ClusterDistance(scale)), objBucket, ns.db.objectivePinSize or 12)
    local ts = ns.WorldThinStats()
    objThinned = ts.before > ts.after or ts.before > ns.WORLD_OBJECTIVE_BUDGET
    for _, pin in ipairs(display) do
      -- (1.3.5) dungeon entrances only with their option (the minimap has its own)
      if not (pin.kind == "dungeon" and ns.db.dungeonPins == false) then
        self:GetMap():AcquirePin(pin.kind == "objective" and OBJECTIVE_TEMPLATE or QUEST_TEMPLATE, pin)
      end
    end
    stats.builds = stats.builds + 1
    builtMap = mapID
    lastSig = sig or ns.PinsSignature(mapID, pins)
  end)
  -- (1.28) zoomed: only with "Merge markers" on, and only when the rounded zoom step changed
  -- (1.3.5) and when objective dots were thinned for another zoom step (the budget follows the zoom)
  p.OnCanvasScaleChanged = ns.Guard("map", function(self)
    if InCombatLockdown() or not self:GetMap() then return end
    local thin = objThinned and ns.db.thinObjectives ~= false
    if not ns.db.clusterPins and not thin then return end
    local map = self:GetMap()
    local scale = map.GetCanvasScale and ns.Value(map.GetCanvasScale, map) or nil
    local bucket = ns.ClusterBucket(scale)
    if (ns.db.clusterPins and bucket ~= clusterBucket) or (thin and bucket ~= objBucket) then self:RefreshAllData() end
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
function ns.PointArrowFromPin(mapID, x, y, label, kind)
  if not (mapID and x and y and ns.SetArrowTarget) then return end
  if not ns.db.arrow then
    ns.db.arrow = true
    if ns.ApplyArrow then ns.ApplyArrow() end
  end
  ns.SetArrowTarget(mapID, x, y, label, kind)
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
-- (1.3.5) Combat starts (the lockdown begins right after this event): with the world map closed and set to
-- the player's zone, its pins are drawn now, unless they are drawn already, so the map opened in combat
-- shows them (entrances included).
ns.On("PLAYER_REGEN_DISABLED", function()
  if not provider or InCombatLockdown() or WorldMapFrame:IsShown() or not provider:GetMap() then return end
  local m = ns.Num(provider:GetMap():GetMapID())
  local zone = C_Map and C_Map.GetBestMapForUnit and ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  if not m or m ~= zone or m == builtMap then return end
  stats.preCombat = (stats.preCombat or 0) + 1
  provider:RefreshAllData()
end)
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("QUEST_DATA_LOAD_RESULT", Queue)
ns.On("QUESTLINE_UPDATE", Queue)
ns.On("PLAYER_LEVEL_UP", Queue) -- (1.23) new level: other quests available (minimap and nameplates did this already)
ns.On("BAG_UPDATE_DELAYED", function()
  -- only matters while a pin depends on the bags (cheap check, queued refresh)
  if WorldMapFrame and WorldMapFrame:IsShown() then Queue() end
end)
