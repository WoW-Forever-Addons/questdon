local _, ns = ...
local L = ns.L

local category

local function QuestieBlocks(key)
  return function()
    return ns.QuestieHandles and ns.QuestieHandles(key) and "Questie" or nil
  end
end
local function RefreshPins() if ns.RefreshPins then ns.RefreshPins() end end
local function RefreshTargetButton() if ns.RefreshTargetButton then ns.RefreshTargetButton() end end
local function SyncWaypoint() if ns.SyncWaypoint then ns.SyncWaypoint() end end
local function RefreshItemButton() if ns.RefreshItemButton then ns.RefreshItemButton() end end
local function UpdatePanel() if ns.UpdatePanel then ns.UpdatePanel() end end
local function ApplyArrow() if ns.ApplyArrow then ns.ApplyArrow() end end
local function Pixels(v) return ("%d"):format(v) end
local function Levels(v) return ("%d"):format(v) end
local function Upcoming(v) v = math.floor((tonumber(v) or 0) + 0.5) return v == 0 and L["off"] or ("+%d"):format(v) end
local function RefreshLevels() RefreshPins() UpdatePanel() end
local function PanelLook() if ns.ApplyPanelLook then ns.ApplyPanelLook() end end
local function ArrowLook() if ns.ApplyArrow then ns.ApplyArrow() end end
local function XPBarLook() if ns.ApplyXPBarLook then ns.ApplyXPBarLook() end end
local function UpdateXPBar() if ns.UpdateXPBar then ns.UpdateXPBar() end end
local SMIN, SMAX = ns.Style.SCALE_MIN, ns.Style.SCALE_MAX

local PAGES = {
  { title = "Quests and automation", tip = "Accepting, turning in, rewards, chains, group, dungeons and tooltips.", items = {
    { header = "Accept and turn in" },
    { key = "autoAccept", name = "Auto accept quests", tip = "Accepts offered quests and escort confirmations. Hold Shift to pause.", blockedBy = QuestieBlocks("autoAccept") },
    { key = "skipTrivial", name = "Ignore grey quests", tip = "Do not auto accept quests that are trivial for your level.", parent = "autoAccept" },
    { key = "autoTurnIn", name = "Auto turn in quests", tip = "Turns in completed quests. Quests with several reward choices or a gold cost are left to you.", blockedBy = QuestieBlocks("autoTurnIn") },
    { header = "Rewards" },
    { key = "highlightBest", name = "Highlight most valuable reward", tip = "Marks the reward with the highest vendor price with a gold coin." },
    { key = "autoPickBest", name = "Auto pick most valuable reward", tip = "Picks the highest vendor price reward when auto turn-in is on. Careful: ignores possible upgrades.", parent = "autoTurnIn" },
    { header = "Chains and group" },
    { key = "chainHint", name = "Hint for the next quest in a chain", tip = "After turning in a quest, names the follow-up quest and its zone in the chat." },
    { key = "shareQuests", name = "Share new quests with group", tip = "Shares every quest you accept with your group, if it can be shared." },
    { key = "partyProgress", name = "Quest progress with the group", tip = "Group members who use Questdon too see each other's quest progress: in mob tooltips (who still needs this mob), in the panel and on quest pins (who has a quest you can pick up). Only in groups of up to five, only quest numbers and counters are sent. /qd group", onChange = function() if ns.ApplyPartyProgress then ns.ApplyPartyProgress() end UpdatePanel() end },
    { header = "Dungeons" },
    { key = "dungeonHint", name = "Hint when entering a dungeon", tip = "When you enter a dungeon, the chat names its quests in your log and the ones you are missing (and who in the group has them)." },
    { header = "Tooltips" },
    { key = "unitTooltips", name = "Quest info in mob and NPC tooltips", tip = "Mouse over a mob: shows which of your quests it counts for and your progress. Mouse over an NPC: shows quests it has for you. Where Questie's tooltips already show the quest, Questdon adds nothing." },
  } },
  { title = "Map", tip = "Available quests, quest mobs and learned spots on the world map, the minimap and nameplates.", items = {
    -- (1.23) grouped by what is shown; the level options apply to the world map, minimap, nameplates and panel alike
    { header = "Available quests" },
    { key = "availablePins", name = "Show available quests on the map", tip = "Yellow ! for quests you can pick up now: level, faction, race, class and previous quests are checked. Data from All The Things plus what Questdon learned. Skipped where Questie or Forever Quest Pins already show the quest.", onChange = RefreshPins },
    { key = "showLowLevel", name = "Also show low level quests", tip = "Shows quests far below your level too.", parent = "availablePins", onChange = RefreshPins },
    { key = "lowLevelRange", kind = "slider", name = "Low level from levels below yours", tip = "A quest counts as low level when its level is at least this many levels below yours. Low level quests are hidden on the map, the minimap, the nameplates, in the panel and in the dungeon list unless 'Also show low level quests' is on. Default 10.", min = 3, max = 20, step = 1, format = Levels, parent = "availablePins", onChange = RefreshLevels },
    -- (1.24) replaces "Quests without a level count as low level" (the setting is dropped, see Core.lua)
    { key = "showNoLevel", name = "Show quests without a level on the map", tip = "Some quests have no level in the data (mostly start zone quests and quests new in Forever), and some of them are only offered later. Off: such a quest is shown only once the game lists it for the map or a quest giver offered it to you. On: always shown, with 'Level unknown'. The next quest prefers quests with a known level either way.", parent = "availablePins", onChange = RefreshLevels },
    -- (1.0) event quests and "confirmed only"
    { key = "hideEventQuests", name = "Hide event quests until confirmed", tip = "Quests of holidays and world events (Darkmoon Faire, Lunar Festival, ...) have quest givers who are only there while the event runs. On: such a quest is shown only once the game lists it or a quest giver offered it to you, so the arrow never leads to an empty spot. Off: shown like any other quest.", parent = "availablePins", onChange = RefreshLevels },
    { key = "confirmedOnly", name = "Only quests confirmed by the game", tip = "Shows only quests the game itself lists for the map or a quest giver has offered you. Safest, but a quest giver you have not met yet shows nothing until the game or the quest giver confirms it. Off: the data decides, with a note 'data only, not confirmed' in the tooltip.", parent = "availablePins", onChange = RefreshLevels },
    -- (1.25) no second "!" where the game draws its own
    { key = "skipGameGivers", name = "No second ! where the game shows one", tip = "The game draws its own ! for quests it lists as available on the map. Questdon then leaves that quest giver to the game on the world map and the minimap, so there is only one !. The panel, the nameplates and the tooltips still name the quests.", parent = "availablePins", onChange = RefreshPins },
    { key = "clusterPins", name = "Merge markers", tip = "On the world map, quest markers (!) that lie close together are merged into one marker with a count (+n). Hover it to see all quests, click it to point the arrow at it. How close depends on the zoom: zoom in to pull them apart. The minimap is not changed.", parent = "availablePins", onChange = RefreshPins },
    { key = "upcomingLevels", kind = "slider", name = "Quests of the next levels", tip = "Also shows quests you can pick up within the next levels, dimmed, with 'from level n' in the tooltip. Only on the world map and the minimap; the panel, the next quest and the nameplates stay with what you can take now. Off by default.", min = 0, max = 5, step = 1, format = Upcoming, parent = "availablePins", onChange = RefreshLevels },
    { header = "Quest mobs and objectives" },
    { key = "objectivePins", name = "Show quest mobs and objectives on the map", tip = "Coloured dots where the mobs and objects for your unfinished quest objectives are (one colour per quest). Mouse over for details.", onChange = RefreshPins },
    { key = "objectivePinsTrackedOnly", name = "Only for tracked quests", tip = "Shows the coloured dots only for quests you track in the quest tracker, so the map stays clear.", parent = "objectivePins", onChange = RefreshPins },
    { key = "objectivePinSize", kind = "slider", name = "Size of the objective dots", tip = "Size of the coloured dots on the world map.", min = 8, max = 24, step = 1, format = Pixels, parent = "objectivePins", onChange = RefreshPins },
    { header = "Minimap and nameplates" },
    { key = "minimapPins", name = "Show the pins on the minimap too", tip = "The same pins as on the world map (available quests, quest mobs and objectives, learned turn-ins) for the zone you are in, also on the minimap. The options above apply there too. A quest giver with several quests is one pin. Mouse over for details, click to point the arrow there.", onChange = RefreshPins },
    { key = "nameplateIcons", name = "Quest icons on nameplates", tip = "A small mark above the nameplate: a dot in the quest's colour for mobs of your open objectives, a yellow ! for NPCs with a quest you can pick up now, a ? where a finished quest is turned in (learned NPC). Nameplates must be switched on in the game. If the game hides who a nameplate belongs to (Midnight rules), that nameplate gets no icon.", onChange = function() if ns.RefreshNameplates then ns.RefreshNameplates() end end },
    { header = "Learning" },
    { key = "learnQuests", name = "Learn quest locations", tip = "Remembers where you accept and turn in quests and where your objective counters went up (account wide), so your other characters see them on the map too." },
    { key = "shareLearned", name = "Share learned data with guild and group", tip = "Sends what you learned and the data does not have yet (only numbers: quest, NPC, map and item numbers, coordinates) to Questdon players in your guild and group. What two or more players reported is used by everyone, also when this is off.", parent = "learnQuests" },
    { key = "learnPins", name = "Show learned turn-in points on the map", tip = "Shows where you turned in a quest before (also on other characters), once that quest is finished.", onChange = RefreshPins },
    { key = "pinsOnlyUnknown", name = "Only quests Questie does not know", tip = "Hides learned pins for quests that Questie already shows.", parent = "learnPins", onChange = RefreshPins },
  } },
  { title = "Appearance", tip = "Panel, direction arrow and XP bar: show, lock, size, background opacity, dimming in combat and position. The same options in all our addons.", items = {
    { header = "Panel" },
    { key = "showPanel", name = "Show window", tip = "XP of finished quests and the level after turning them in, XP per hour, quests nearby, dungeon quests, group progress, grey quests and quest items you no longer need. Drag the header to move. /qd panel toggles it.", onChange = UpdatePanel },
    { key = "panelLocked", name = "Lock window", tip = "The window can no longer be dragged by its header.", parent = "showPanel", onChange = PanelLook },
    { key = "panelScale", kind = "slider", name = "Size", tip = "Size of the window including its text.", min = SMIN, max = SMAX, step = 0.05, parent = "showPanel", onChange = PanelLook },
    { key = "panelAlpha", kind = "slider", name = "Background opacity", tip = "How dark the background is. The text stays fully visible.", min = 0, max = 1, step = 0.05, parent = "showPanel", onChange = PanelLook },
    { key = "panelCombatFade", name = "Dim in combat", tip = "Dims the window to 40 % while you are in combat.", parent = "showPanel", onChange = PanelLook },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the window back to its default place.", onClick = function() if ns.ResetPanelPosition then ns.ResetPanelPosition() end end },
    { key = "panelWidth", kind = "slider", name = "Width", tip = "Width of the window. Long lines wrap and the window grows in height.", min = 220, max = 500, step = 10, format = Pixels, parent = "showPanel", onChange = PanelLook },
    { header = "Direction arrow" },
    { key = "arrow", name = "Show window", tip = "Arrow with distance to the quest you track in the quest log or tracker (nearest objective spot, or the turn-in when it is finished). Left click a Questdon map pin to point the arrow there. Drag to move, right click to drop a clicked target. /qd arrow toggles it.", onChange = ArrowLook },
    { key = "arrowLocked", name = "Lock window", tip = "The arrow can no longer be dragged.", parent = "arrow" },
    { key = "arrowScale", kind = "slider", name = "Size", tip = "Size of the direction arrow and its text.", min = SMIN, max = SMAX, step = 0.05, parent = "arrow", onChange = ArrowLook },
    { key = "arrowAlpha", kind = "slider", name = "Background opacity", tip = "How dark the plate behind the target and distance is.", min = 0, max = 1, step = 0.05, parent = "arrow", onChange = ArrowLook },
    { key = "arrowCombatFade", name = "Dim in combat", tip = "Dims the arrow to 40 % while you are in combat.", parent = "arrow", onChange = ArrowLook },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the arrow back to its default place.", onClick = function() if ns.ResetArrowPosition then ns.ResetArrowPosition() end end },
    { header = "XP bar" },
    { key = "xpBar", name = "Show window", tip = "Blue: your XP. Yellow: XP of the finished quests in your log. Light blue: rested XP. Mouse over for details. /qd xpbar toggles it.", onChange = UpdateXPBar },
    { key = "xpBarLocked", name = "Lock window", tip = "When unlocked, drag the bar with the left mouse button.", parent = "xpBar" },
    { key = "xpBarScale", kind = "slider", name = "Size", tip = "Overall size of the XP bar including the text.", min = SMIN, max = SMAX, step = 0.05, parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarAlpha", kind = "slider", name = "Background opacity", tip = "How dark the strip behind the bar is.", min = 0, max = 1, step = 0.05, parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarCombatFade", name = "Dim in combat", tip = "Dims the XP bar to 40 % while you are in combat.", parent = "xpBar", onChange = XPBarLook },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the XP bar back to its default place.", onClick = function() if ns.ResetXPBarPosition then ns.ResetXPBarPosition() end end },
    { key = "xpBarText", name = "Text under the bar", tip = "Level, percent, quest XP, rested XP, XP per hour and time to the next level as text.", parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarWidth", kind = "slider", name = "Width", tip = "Width of the XP bar.", min = 200, max = 1600, step = 10, format = Pixels, parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarHeight", kind = "slider", name = "Height", tip = "Height of the XP bar.", min = 6, max = 40, step = 1, format = Pixels, parent = "xpBar", onChange = UpdateXPBar },
  } },
  { title = "Panel and signals", tip = "What the panel shows, completion sound and message.", items = {
    { header = "Panel content" },
    { key = "nextQuestHint", name = "Nearest quest", tip = "Shows the nearest quest you can pick up within 400 yards. Off by default: the map and minimap show the game's own ! anyway. Click the line to point the arrow there (/qd next).", parent = "showPanel", onChange = UpdatePanel },
    { key = "nextConfirmedOnly", name = "Nearest quest: only confirmed ones", tip = "The nearest quest line, the arrow from it and /qd next only use quests the game or a quest giver confirmed. The map still shows all quests.", parent = "nextQuestHint", onChange = UpdatePanel },
    { key = "dungeonQuests", name = "Dungeon quests in the panel", tip = "Lists the dungeon quests in your log and the ones you can pick up now, per dungeon. Forever pays dungeon quests extra XP: take them before you go in. Click the line: arrow to the nearest quest giver. /qd dungeons", parent = "showPanel", onChange = UpdatePanel },
    { header = "When something is done" },
    { key = "notifySound", name = "Sound when done", tip = "Plays a sound when a quest objective or a whole quest is done. Where Questie plays its own sound, Questdon stays quiet." },
    { key = "notifyText", name = "Message when done", tip = "Shows a message in the middle of the screen when an objective or quest is done." },
  } },
  { title = "Comfort", tip = "Merchant, loot, quest item button, targeting and waypoints.", items = {
    { header = "Merchant" },
    { key = "sellJunk", name = "Sell junk", tip = "Sells all grey items when you open a merchant." },
    { key = "autoRepair", name = "Auto repair", tip = "Repairs all items at merchants that can repair." },
    { key = "useGuildRepair", name = "Use guild bank for repairs", tip = "Tries the guild bank first, then your own gold.", parent = "autoRepair" },
    { header = "Loot and items" },
    { key = "fastLoot", name = "Fast loot", tip = "Loots everything instantly when auto loot applies." },
    { key = "questItemButton", name = "Quest item button", tip = "Shows a button for the usable item of your tracked quest. Shift-drag to move. Key binding under Key Bindings > AddOns.", blockedBy = QuestieBlocks("questItemButton"), onChange = RefreshItemButton },
    { key = "itemButtonScale", kind = "slider", name = "Quest item button size", tip = "Size of the quest item button (changes after combat).", min = 0.6, max = 2, step = 0.05, parent = "questItemButton", onChange = RefreshItemButton },
    { header = "Targeting and waypoints" },
    { key = "targetButton", name = "Target button", tip = "Shows a button that targets a mob of your tracked quest with one click. Questdon learns the mob names from nameplates and your target, so a mob must have been seen once. The macro stays under 255 bytes. Shift-drag to move. Key binding under Key Bindings > AddOns.", onChange = RefreshTargetButton },
    { key = "exportBlizzardWaypoint", name = "Set Blizzard map pin", tip = "Also places the spot the arrow points at as the map pin of the game (visible on the world map and the minimap). The arrow keeps working as before.", onChange = SyncWaypoint },
    { key = "exportTomTom", name = "Set TomTom waypoint", tip = "Also sets the spot the arrow points at as a TomTom waypoint. Needs TomTom.", onChange = SyncWaypoint },
  } },
  { title = "Questie", tip = "How Questdon works together with Questie.", items = {
    { header = "Working together" },
    { key = "questieFirst", name = "Questie has priority", tip = "If Questie already does something (auto accept, auto turn-in, quest item buttons in its tracker, completion sounds), Questdon steps back there. /qd questie shows the current state.", onChange = function() RefreshItemButton() RefreshPins() end },
  } },
}

local function Status()
  local lines = {}
  local version = ns.Version()
  if version ~= "?" then lines[#lines + 1] = L["Version %s"]:format(version) end
  local learned = 0
  for _ in pairs(ns.db.learned or {}) do learned = learned + 1 end
  local att = ns.ATT_META and ns.ATT_META.quests or 0
  lines[#lines + 1] = L["Quest database: %d quests from All The Things, %d learned"]:format(att, learned)
  if ns.AddOnLoaded("Questie") then
    lines[#lines + 1] = ns.db.questieFirst and L["Questie is loaded and has priority."] or L["Questie is loaded, priority is off."]
  else
    lines[#lines + 1] = L["Questie is not loaded."]
  end
  return lines
end

local TOOLS = {
  { "Reset positions", "Reset", function()
      if ns.ResetPanelPosition then ns.ResetPanelPosition() end
      if ns.ResetArrowPosition then ns.ResetArrowPosition() end
      if ns.ResetXPBarPosition then ns.ResetXPBarPosition() end
      if ns.ResetButtonPosition then ns.ResetButtonPosition() end
    end, "Puts the panel, the arrow, the XP bar and the quest item button back to their default places." },
  { "Test the arrow", "Test", function()
      local map, x, y = ns.PlayerPosition()
      if map and ns.SetArrowTarget then
        ns.db.arrow = true
        ApplyArrow()
        ns.SetArrowTarget(map, x, math.max(0, y - 0.03), L["Test: a bit to the north"])
      end
    end, "Points the arrow a little to the north of you." },
  { "Reset XP session", "Reset", function()
      if ns.ResetXPSession then ns.ResetXPSession() end
      UpdatePanel()
    end, "Starts XP per hour from zero." },
  -- (1.1) quests hidden as "not offered here" (NotHere.lua)
  { "Quests hidden as not offered", "Show again", function()
      if ns.Confirm("nothere", L["Click again within 5 seconds to show all quests again that were hidden as not offered."]) then
        if ns.ResetNotHere then ns.ResetNotHere() end
        ns.Print(L["All quests hidden as not offered are shown again."])
      end
    end, "Questdon hides a quest when its quest giver did not offer it at 3 different levels, or when you reported it (Alt-click on the !, or /qd nothere with the NPC targeted). This shows them all again. /qd nothere list shows them, /qd nothere undo takes back the last report." },
  { "Export learned data", "Export", function()
      if ns.OpenExport then ns.OpenExport(false) end
    end, "Shows what Questdon learned and the bundled data does not have yet, as text to copy into a GitHub issue. Helps to improve the quest data for everyone. Only numbers, no names. /qd export (or /qd export all for everything)." },
  { "Diagnostics", "Show", function()
      if ns.OpenDiag then ns.OpenDiag() end
    end, "Report for bug reports: client version, which game functions exist, a few live checks and errors Questdon caught. Only numbers, no names. /qd diag" },
  { "Dungeon quests", "Show", function()
      if ns.OpenDungeons then ns.OpenDungeons() end
    end, "All dungeon quests in your log and the ones you can pick up now, per dungeon, as text. /qd dungeons" },
  { "XP sources", "Show", function()
      if ns.OpenXPCheck then ns.OpenXPCheck() end
    end, "Where your XP comes from: kills (in and outside dungeons), quests (normal and dungeon), exploration, rested bonus, auras during kills and rested XP growth. Checks Forever's XP rules while you play. Only numbers, no names. /qd xpcheck (/qd xpcheck reset clears it)." },
  { "Delete learned quest data", "Delete", function()
      if ns.Confirm("learned", L["Click again within 5 seconds to delete all learned quest data."]) then
        wipe(ns.db.learned)
        if ns.db.learnedObj then wipe(ns.db.learnedObj) end
        if ns.db.learnedItems then wipe(ns.db.learnedItems) end
        for _, k in ipairs({ "learnedCredit", "learnedDrops", "learnedItemStarts", "shared", "shareSent", "notHere" }) do
          if type(ns.db[k]) == "table" then wipe(ns.db[k]) end
        end
        if ns.db.guessedItems then wipe(ns.db.guessedItems) end
        RefreshPins()
        ns.Print(L["Learned quest data deleted."])
      end
    end, "Deletes everything Questdon learned while playing (all characters). The All The Things data stays." },
}

-- Tool buttons run protected (Blizzard's settings code calls them).
for _, t in ipairs(TOOLS) do t[3] = ns.Guard("tool", t[3]) end

local function Build()
  category = ns.BuildSettings({ name = "Questdon", status = Status, tools = TOOLS, pages = PAGES })
  ns.settingsCategory = category ~= nil
end

function ns.OpenOptions()
  if InCombatLockdown() then
    ns.Print(L["Options cannot be opened in combat."])
    return
  end
  if category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(category:GetID())
  else
    ns.Print(ns.HELP)
  end
end

ns.OnInit(Build)
