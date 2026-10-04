local _, ns = ...
local L = ns.L

-- Questie overlaps with a few Questdon features. When both are switched on,
-- Questie gets priority and Questdon steps back (setting "questieFirst").
-- Questie's settings are only read, never changed.

local function Profile()
  if not ns.AddOnLoaded("Questie") then return nil end
  local p = type(Questie) == "table" and type(Questie.db) == "table" and Questie.db.profile
  if type(p) ~= "table" or p.enabled == false then return nil end
  return p
end

-- Which Questdon feature Questie covers, and how to read Questie's switch for it.
local OVERLAPS = {
  autoAccept = function(p)
    return (type(p.autoAccept) == "table" and p.autoAccept.enabled == true) or p.autoaccept == true
  end,
  autoTurnIn = function(p) return p.autocomplete == true end,
  questItemButton = function(p) return p.trackerEnabled == true end, -- Questie's tracker has item buttons
  soundQuest = function(p) return p.soundOnQuestComplete == true end,
  soundObjective = function(p) return p.soundOnObjectiveComplete == true end,
}
local NAMES = {
  autoAccept = "Auto accept quests",
  autoTurnIn = "Auto turn in quests",
  questItemButton = "Quest item button",
  soundQuest = "Sound when a quest is done",
  soundObjective = "Sound when an objective is done",
}
local ORDER = { "autoAccept", "autoTurnIn", "questItemButton", "soundQuest", "soundObjective" }

function ns.QuestieHandles(key)
  if not ns.db.questieFirst then return false end
  local p = Profile()
  local check = OVERLAPS[key]
  if not (p and check) then return false end
  local ok, result = pcall(check, p)
  return ok and result or false
end

-- A Questdon feature runs only if it is switched on and Questie does not already do it.
function ns.Active(key)
  local setting = key
  if key == "soundQuest" or key == "soundObjective" then setting = "notifySound" end
  return ns.db[setting] and not ns.QuestieHandles(key)
end

local function Handled()
  local list = {}
  for _, key in ipairs(ORDER) do
    local setting = (key == "soundQuest" or key == "soundObjective") and "notifySound" or key
    if ns.db[setting] and ns.QuestieHandles(key) then list[#list + 1] = L[NAMES[key]] end
  end
  return list
end

function ns.PrintQuestieStatus()
  if not Profile() then
    ns.Print(L["Questie is not loaded. All Questdon features are active."])
    return
  end
  if not ns.db.questieFirst then
    ns.Print(L["Questie priority is off: Questdon runs everything, even where Questie does the same."])
    return
  end
  local handled = Handled()
  if #handled == 0 then
    ns.Print(L["Questie is loaded, no overlaps. Map pins only show quests Questie does not know."])
  else
    ns.Print(L["Questie handles: %s. Questdon steps back there."]:format(table.concat(handled, ", ")))
  end
end

-- One short note after login if something overlaps.
ns.On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
  if not (isLogin or isReload) then return end
  ns.After(3, function()
    if not Profile() or not ns.db.questieFirst then return end
    local handled = Handled()
    if #handled > 0 then
      ns.Print(L["Questie handles: %s. Questdon steps back there."]:format(table.concat(handled, ", "))
        .. " " .. L["(/qd questie)"])
    end
  end)
end)
