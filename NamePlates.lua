local _, ns = ...

---------------------------------------------------------------------------
-- (1.22) Quest icons on nameplates, like Questie: a small mark above the
-- nameplate of
--   * an NPC where a finished quest of yours is turned in (learned NPC): "?"
--   * a mob or object that counts for an open objective of a quest in your
--     log (ATT data): a dot in the quest's colour, as on the map
--   * an NPC with a quest you can pick up now (same rules as the map: level,
--     faction, race, class, previous quests, low level option): "!"
--
-- Midnight rules: the creature is known only through UnitGUID of the
-- nameplate's unit. When the client hides it (secret value), that nameplate
-- simply gets no icon; names are never used instead (many mobs share one).
-- Hidden (forbidden) nameplates, e.g. in instances, are left alone too.
-- /qd diag counts both, so a missing icon can be explained.
--
-- Own frames only: one small frame per shown icon, parented to the nameplate
-- (like the minimap pins on the minimap), nothing of the nameplate changed.
-- Cost: one lookup when a nameplate appears; after quest events (batched,
-- at most every 0.5 s) the marks of the visible nameplates are worked out
-- again. With the option off, nothing runs.
---------------------------------------------------------------------------
local QUEST_SIZE, DOT_SIZE = 16, 10

local units = {}  -- [unit token] = icon frame or false (no icon)
local free = {}
local marks = {}  -- [creatureID] = { kind, questID } or false, cleared on refresh
local stats = { plates = 0, shown = 0, secret = 0, noPlate = 0, failed = 0, refreshes = 0 }
local registered = false

local function Enabled() return ns.db and ns.db.nameplateIcons end

local function QuestieDrawsNameplates(questID)
  if not (ns.db.questieFirst and ns.AddOnLoaded("Questie")) then return false end
  local p = type(Questie) == "table" and type(Questie.db) == "table" and Questie.db.profile
  if type(p) ~= "table" or p.nameplateEnabled == false then return false end
  return ns.QuestieKnows and ns.QuestieKnows(questID) == true
end

-- Is objective <index> of a quest in the log still open (client state)?
local function ObjectiveOpen(questID, index)
  if not ns.InQuestLog(questID) or ns.IsQuestComplete(questID) or ns.IsQuestFailed(questID) then return false end
  local client = ns.ClientObjectives(questID)
  if #client > 0 and index > #client then return false end
  local o = client[index]
  if type(o) == "table" and ns.True(o.finished) then return false end
  -- (1.3.4) no mark for an optional objective ("listen to ...", often the quest giver himself)
  if ns.IsOptionalObjective and ns.IsOptionalObjective(questID, index) then return false end
  return true
end

-- Turn-ins learned with the NPC: [npcID] = questID, for finished quests in the log.
local turnins
local function TurnIns()
  if turnins then return turnins end
  turnins = {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    local id = info.questID
    local e = ns.db.learned[id]
    local npc = e and e.finish and ns.Num(e.finish.npcID)
    if npc and ns.IsQuestComplete(id) then turnins[npc] = id end
  end
  return turnins
end

-- What the icon of a creature shows: { kind, questID } or false. Also used by the tests.
function ns.NameplateMark(creatureID)
  if not creatureID then return false end
  local m = marks[creatureID]
  if m ~= nil then return m end
  m = false
  local t = TurnIns()[creatureID]
  if t then m = { kind = "turnin", questID = t } end
  local objectives, gives = ns.CreatureQuestIndex(creatureID)
  if not m then
    for _, entry in ipairs(objectives or {}) do
      local questID, index = ns.ObjectiveEntry(entry)
      if ObjectiveOpen(questID, index) and not QuestieDrawsNameplates(questID) then
        m = { kind = "objective", questID = questID }
        break
      end
    end
  end
  if not m then
    for _, questID in ipairs(gives or {}) do
      if ns.ShowAsAvailable(questID) then -- (1.24) same rule as the map
        m = { kind = "available", questID = questID }
        break
      end
    end
  end
  marks[creatureID] = m
  return m
end

---------------------------------------------------------------------------
-- Icon frames
---------------------------------------------------------------------------
local function Take()
  local f = table.remove(free)
  if f then return f end
  f = CreateFrame("Frame", nil, UIParent)
  f.icon = f:CreateTexture(nil, "OVERLAY")
  f.icon:SetAllPoints(f)
  if f.EnableMouse then f:EnableMouse(false) end
  return f
end

local function Release(unit)
  local f = units[unit]
  units[unit] = nil
  if not f then return end
  f:Hide()
  f:ClearAllPoints()
  f:SetParent(UIParent)
  f.mark = nil
  free[#free + 1] = f
  stats.shown = math.max(0, stats.shown - 1)
end

local function Dress(f, mark)
  f.mark = mark
  if mark.kind == "objective" then
    f:SetSize(DOT_SIZE, DOT_SIZE)
    f.icon:SetTexture("Interface\\COMMON\\Indicator-Yellow")
    f.icon:SetVertexColor(ns.QuestColor(mark.questID))
  else
    f:SetSize(QUEST_SIZE, QUEST_SIZE)
    local atlas = mark.kind == "turnin" and "QuestTurnin" or "QuestNormal"
    local ok, res = false, nil
    if f.icon.SetAtlas then ok, res = pcall(f.icon.SetAtlas, f.icon, atlas, false) end
    if not ok or res == false then
      f.icon:SetTexture(mark.kind == "turnin" and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\AvailableQuestIcon")
    end
    f.icon:SetVertexColor(1, 1, 1)
  end
end

-- The nameplate of a unit, nil when the client has none for us (forbidden).
local function Plate(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local plate = ns.Value(C_NamePlate.GetNamePlateForUnit, unit)
  if type(plate) ~= "table" then return nil end
  if plate.IsForbidden then
    local ok, forbidden = pcall(plate.IsForbidden, plate)
    -- an error, a secret or a true answer: leave that nameplate alone
    if not ok or (forbidden ~= nil and (not ns.Usable(forbidden) or forbidden ~= false)) then return nil end
  end
  return plate
end

local function Apply(unit)
  if type(unit) ~= "string" or not ns.Usable(unit) then return end
  local guid = ns.Value(UnitGUID, unit)
  if guid == nil then
    -- secret (Midnight) or gone: no icon, never a guess from the name
    stats.secret = stats.secret + 1
    Release(unit)
    units[unit] = false
    return
  end
  local mark = ns.NameplateMark(ns.CreatureIDFromGUID(guid))
  if not mark then Release(unit) units[unit] = false return end
  local f = units[unit]
  if f and f.mark and f.mark.kind == mark.kind and f.mark.questID == mark.questID then return end
  local plate = Plate(unit)
  if not plate then stats.noPlate = stats.noPlate + 1 Release(unit) units[unit] = false return end
  if not f then
    f = Take()
    stats.shown = stats.shown + 1
  end
  units[unit] = f
  Dress(f, mark)
  local ok = pcall(function()
    f:SetParent(plate)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", plate, "TOP", 0, 0)
    local level = ns.Num(ns.Value(plate.GetFrameLevel, plate))
    if level then f:SetFrameLevel(level + 5) end
  end)
  if not ok then stats.failed = stats.failed + 1 Release(unit) units[unit] = false return end
  f:Show()
end

-- Unit tokens first: Apply and Release change the table.
local function Units()
  local list = {}
  for unit in pairs(units) do list[#list + 1] = unit end
  return list
end

-- (1.25) Unit tokens of the visible nameplates (with or without an icon, also
-- with the option off): the arrow looks for mobs of the tracked objective.
ns.NameplateUnits = Units

-- Work out the marks of all visible nameplates again.
local function RefreshAll()
  marks, turnins = {}, nil
  stats.refreshes = stats.refreshes + 1
  for _, unit in ipairs(Units()) do
    if Enabled() then Apply(unit) else Release(unit) units[unit] = false end
  end
end

-- Options: on/off and everything that changes the marks.
function ns.RefreshNameplates()
  if not Enabled() then
    for _, unit in ipairs(Units()) do Release(unit) units[unit] = false end
    return
  end
  RefreshAll()
end

-- (1.23) Batched with the other quest displays (Core.lua, 0.5 s).
ns.RegisterRefresh("nameplates", function() if Enabled() then RefreshAll() end end)
local function Queue()
  if Enabled() then ns.QueueRefresh("nameplates") end
end

function ns.NameplateStats() return stats end
function ns.NameplateState()
  if not registered then return "not available (no nameplate events)" end
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return "not available (C_NamePlate missing)" end
  if not ns.db.nameplateIcons then return "off" end
  local n = 0
  for _ in pairs(units) do n = n + 1 end
  return ("on, %d shown of %d nameplates, guid secret %d, no plate %d, failed %d"):format(stats.shown, n,
    stats.secret, stats.noPlate, stats.failed)
end
-- tests
function ns.NameplateIcon(unit) return units[unit] or nil end

registered = ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
  if type(unit) ~= "string" or not ns.Usable(unit) then return end
  stats.plates = stats.plates + 1
  -- (1.2) learn where quest mobs are (Learn.lua), also with the icons off
  if ns.NoteSighting then
    local guid = ns.Value(UnitGUID, unit)
    if guid ~= nil then ns.SafeCall("sighting", ns.NoteSighting, unit, ns.CreatureIDFromGUID(guid)) end
  end
  if not Enabled() then units[unit] = false return end
  Apply(unit)
end) and true or false
ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
  if type(unit) ~= "string" or not ns.Usable(unit) then return end
  Release(unit)
end)
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("QUEST_TURNED_IN", Queue)
ns.On("PLAYER_LEVEL_UP", Queue)
ns.On("QUEST_DATA_LOAD_RESULT", Queue)
ns.On("PLAYER_ENTERING_WORLD", function()
  for _, unit in ipairs(Units()) do Release(unit) end
  units = {}
end)
