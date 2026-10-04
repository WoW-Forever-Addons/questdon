local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.27) Target button: one click (or key) targets a mob of the tracked quest.
--
-- A secure button runs a small macro: one "/targetexact <name>" line per mob
-- name Questdon has seen for the open objectives of the tracked quest. Mob
-- names are learned from nameplates and your target (the bundled data only has
-- creature IDs). Macro text is limited to 255 bytes, and German umlauts count
-- as two bytes, so ns.BuildTargetMacro counts bytes and only adds whole names.
-- Attributes of a secure button change only out of combat; in combat the
-- button keeps the macro it has.
---------------------------------------------------------------------------
local MACRO_LIMIT = 255 -- bytes (conservative: also the limit of macros in the macro window)
ns.TARGET_MACRO_LIMIT = MACRO_LIMIT
local COMMAND = "/targetexact "

local button
local current = { macro = nil, names = {}, questID = nil }
local pendingRefresh = false
local pendingStop = false -- drag ended in combat: a protected frame cannot be stopped then

-- Cleans a unit name for a macro line: no control characters or line breaks,
-- no escape sequences, trimmed. Returns nil if nothing usable is left.
local function CleanName(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("[%c]", " "):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil end
  return name
end

ns.CleanName = CleanName

-- names: list of strings. Returns macro (nil if no name fits), number of names used.
-- Every line is "/targetexact <name>", joined with a line feed; the whole text
-- stays at or under `limit` bytes (default 255). A name that does not fit alone
-- is skipped, the next shorter ones still get their chance.
function ns.BuildTargetMacro(names, limit)
  limit = limit or MACRO_LIMIT
  local lines, used, seen = {}, 0, {}
  for _, raw in ipairs(names or {}) do
    local name = CleanName(raw)
    if name and not seen[name] then
      local line = COMMAND .. name
      local add = #line + (#lines > 0 and 1 or 0)
      if used + add <= limit then
        lines[#lines + 1] = line
        used = used + add
        seen[name] = true
      end
    end
  end
  if #lines == 0 then return nil, 0 end
  return table.concat(lines, "\n"), #lines
end

---------------------------------------------------------------------------
-- Learning names
---------------------------------------------------------------------------
-- Only creatures that count for an objective are kept (small table).
local function Learn(unit)
  if not ns.db or type(ns.db.mobNames) ~= "table" then return end
  if type(unit) ~= "string" or not ns.Usable(unit) then return end
  local guid = ns.Value(UnitGUID, unit)
  local id = ns.CreatureIDFromGUID(guid)
  if not id then return end
  local objectives = ns.CreatureQuestIndex(id)
  if not objectives then return end
  local name = ns.Value(UnitName, unit)
  if type(name) ~= "string" or not ns.Usable(name) then return end
  name = CleanName(name)
  if name and ns.db.mobNames[id] ~= name then
    ns.db.mobNames[id] = name
    if ns.QueueRefresh then ns.QueueRefresh("targetbutton") end
  end
end
ns.LearnMobName = Learn

---------------------------------------------------------------------------
-- Which names for the tracked quest
---------------------------------------------------------------------------
local function TrackedQuest()
  local questID = C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  if questID and questID > 0 and ns.InQuestLog(questID) then return questID end
end

-- Names (in data order) of the open objective creatures whose name is known.
function ns.TrackedMobNames()
  local questID = TrackedQuest()
  local names = {}
  if not questID or not ns.OpenObjectiveCreatures then return names, questID end
  local known = ns.db and ns.db.mobNames or {}
  for _, id in ipairs(ns.OpenObjectiveCreatures(questID)) do
    if known[id] then names[#names + 1] = known[id] end
  end
  return names, questID
end

function ns.TargetButtonState()
  return { macro = current.macro, names = current.names, questID = current.questID, bytes = current.macro and #current.macro or 0 }
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
local function SavePosition()
  local point, _, relPoint, x, y = button:GetPoint(1)
  ns.db.targetButtonPos = { point, relPoint, x, y }
end

local function ApplyPosition()
  button:ClearAllPoints()
  local p = ns.db.targetButtonPos
  if p then
    button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    button:SetPoint("CENTER", UIParent, "CENTER", 44, -200)
  end
end

local function CreateButton()
  button = CreateFrame("Button", "QuestdonTargetButton", UIParent, "SecureActionButtonTemplate")
  button:SetSize(36, 36)
  button:SetMovable(true)
  button:SetClampedToScreen(true)
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:RegisterForDrag("LeftButton")
  button:SetAttribute("type", "macro")
  button:Hide()

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  button.icon:SetTexture("Interface\\Icons\\Ability_Hunter_MarkedForDeath")

  button.plate = ns.Look.Plate(button, 2)
  button.plate:SetAlpha(ns.Style.DEFAULT_ALPHA)

  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

  button:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
  end)
  button:SetScript("OnDragStop", function(self)
    if InCombatLockdown() then pendingStop = true return end
    self:StopMovingOrSizing()
    SavePosition()
  end)
  button:SetScript("OnEnter", function(self)
    local Style = ns.Style
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Target a quest mob"], 1, 1, 1)
    if current.questID then
      local c = Style.COLORS.textSecondary
      GameTooltip:AddLine(ns.QuestTitle(current.questID), c[1], c[2], c[3], true)
    end
    for _, name in ipairs(current.names) do GameTooltip:AddLine(name, 1, 1, 1) end
    local h = Style.COLORS.textHint
    GameTooltip:AddLine(L["Click: target. Shift-drag to move. Key binding under Key Bindings > AddOns."], h[1], h[2], h[3], true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function(self) ns.Style.HideTooltip(self) end)

  ApplyPosition()
end

local function Refresh()
  if not button then return end
  if InCombatLockdown() then pendingRefresh = true return end
  pendingRefresh = false

  local names, questID = ns.TrackedMobNames()
  local macro, count = ns.BuildTargetMacro(names)
  -- only the names that made it into the macro are listed in the tooltip
  local used = {}
  for i = 1, count do used[i] = names[i] end
  current = { macro = macro, names = used, questID = questID }

  button:SetAttribute("macrotext", macro or "")
  if macro and ns.Active("targetButton") then
    button:Show() -- (1.28) position is set at creation and on reset only (a refresh must not fight a drag)
  else
    button:Hide()
  end
end

ns.RegisterRefresh("targetbutton", Refresh)
local function QueueRefresh() ns.QueueRefresh("targetbutton") end
ns.RefreshTargetButton = QueueRefresh

function ns.ResetTargetButtonPosition()
  ns.db.targetButtonPos = nil
  if button and not InCombatLockdown() then ApplyPosition() end
end

-- (1.28) names are in the language of the client that saw them: a different
-- client language starts a new list.
local function CheckNameLocale()
  local loc = GetLocale and GetLocale() or "?"
  if ns.db.mobNamesLocale ~= loc then
    ns.db.mobNames = {}
    ns.db.mobNamesLocale = loc
  end
end

ns.CheckMobNameLocale = CheckNameLocale
ns.OnInit(function() CheckNameLocale() CreateButton() end)
ns.On("PLAYER_ENTERING_WORLD", QueueRefresh)
ns.On("QUEST_LOG_UPDATE", QueueRefresh)
ns.On("SUPER_TRACKING_CHANGED", QueueRefresh)
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) Learn(unit) end)
ns.On("PLAYER_TARGET_CHANGED", function() Learn("target") end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if pendingStop and button then
    pendingStop = false
    button:StopMovingOrSizing()
    SavePosition()
  end
  if pendingRefresh then Refresh() end
end)
