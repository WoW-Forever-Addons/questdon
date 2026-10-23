local _, ns = ...
local L = ns.L

-- Remembered state per quest: objectives finished and quest complete.
local known = {}   -- [questID] = { complete = bool, failed = bool, objectives = { [i] = bool } }
local ready = false

local function PlayFirst(keys)
  if not (PlaySound and SOUNDKIT) then return end
  for _, key in ipairs(keys) do
    if SOUNDKIT[key] then PlaySound(SOUNDKIT[key]) return end
  end
end
local QUEST_SOUND = { "UI_WORLDQUEST_COMPLETE", "IG_QUEST_LIST_COMPLETE", "READY_CHECK" }
local OBJECTIVE_SOUND = { "UI_QUEST_ROLLING_FORWARD_01", "IG_QUEST_LIST_SELECT" }

-- (1.23) A title or objective text the client keeps secret is not shown.
local function Text(v) return type(v) == "string" and ns.Usable(v) and v ~= "" and v or nil end

local function Read(questID)
  local state = { complete = ns.IsQuestComplete(questID), failed = ns.IsQuestFailed(questID), objectives = {} }
  local objectives = ns.ClientObjectives(questID)
  for i, o in ipairs(objectives) do
    state.objectives[i] = type(o) == "table" and ns.True(o.finished)
  end
  return state, objectives
end

local function Scan(silent)
  local seen = {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    local id = info.questID
    seen[id] = true
    local state, objectives = Read(id)
    local old = known[id]
    if old and not silent then
      if state.failed and not old.failed then
        if ns.db.notifyText then ns.Warn(L["Quest failed: %s"]:format(Text(info.title) or "?")) end
      elseif state.complete and not old.complete then
        if ns.Active("soundQuest") then PlayFirst(QUEST_SOUND) end
        if ns.db.notifyText then ns.Warn(L["Quest complete: %s"]:format(Text(info.title) or "?")) end
      else
        for i, done in ipairs(state.objectives) do
          if done and old.objectives[i] == false then
            if ns.Active("soundObjective") then PlayFirst(OBJECTIVE_SOUND) end
            local text = type(objectives[i]) == "table" and Text(objectives[i].text)
            if ns.db.notifyText and text then
              ns.Warn(L["Objective done: %s"]:format(text))
            end
          end
        end
      end
    end
    known[id] = state -- new quests become the baseline without a sound
  end
  for id in pairs(known) do
    if not seen[id] then known[id] = nil end
  end
end

local queued = false
local function Queue()
  if queued or not ready then return end
  queued = true
  ns.After(0.3, function() queued = false Scan(false) end)
end

ns.On("PLAYER_ENTERING_WORLD", function()
  Scan(true)
  ready = true
end)
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("UNIT_QUEST_LOG_CHANGED", Queue)
