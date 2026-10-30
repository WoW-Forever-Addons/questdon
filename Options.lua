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
-- (1.2) switching the bar also changes the window (its experience lines)
local function UpdateXPBarAndPanel() UpdateXPBar() if ns.UpdatePanel then ns.UpdatePanel() end if ns.UpdateTracker then ns.UpdateTracker(true) end end
-- (25.10., Daniel: "Show window changes nothing") while a guide (Leveldon) shows the compass in its window, Questdon's
-- arrow and the list's compass stay aside whatever these switches say: the row says so (OptionsWindow.lua item.status)
local function GuideStatus() return ns.GuideActive and ns.GuideActive() and "Leveldon" or nil end
local SMIN, SMAX = ns.Style.SCALE_MIN, ns.Style.SCALE_MAX

local PAGES = {
  { title = "Quests and automation", tip = "Accepting, turning in, rewards, chains, group, dungeons and tooltips.", items = {
    { header = "Accept and turn in" },
    { key = "autoAccept", name = "Auto accept quests", tip = "Accepts offered quests and escort confirmations. Hold Shift to pause.", blockedBy = QuestieBlocks("autoAccept") },
    { key = "skipTrivial", name = "Ignore grey quests", tip = "Do not auto accept quests that are trivial for your level.", parent = "autoAccept" },
    { key = "autoTurnIn", name = "Auto turn in quests", tip = "Turns in completed quests. Quests with several reward choices or a gold cost, and repeatable quests, are left to you.", blockedBy = QuestieBlocks("autoTurnIn") },
    { header = "Rewards" },
    { key = "suggestReward", name = "Suggest a reward for your class", tip = "A green frame marks the reward players of your class pick most. Until enough players have picked, it marks the one with armor and stats for your class that beats what you wear." },
    { header = "Chains and group" },
    { key = "shareQuests", name = "Share new quests with group", tip = "Shares every quest you accept with your group, if it can be shared." },
    { header = "Tooltips" },
    { key = "unitTooltips", name = "Quest info in mob and NPC tooltips", tip = "Mouse over a mob: shows which of your quests it counts for and your progress. Mouse over an NPC: shows quests it has for you. With 'Questie has priority' on, Questdon adds nothing where Questie's tooltips already show the quest." },
  } },
  { title = "Map", tip = "Available quests, quest mobs and learned spots on the world map, the minimap and nameplates.", items = {
    -- (1.23) grouped by what is shown; the level options apply to the world map, minimap, nameplates and panel alike
    { header = "Available quests" },
    { key = "availablePins", name = "Show available quests on the map", tip = "Yellow ! for quests you can pick up now: level, faction, race, class and previous quests are checked. Data from All The Things plus what Questdon learned. Skipped where Questie or Forever Quest Pins already show the quest.", onChange = RefreshPins },
    { key = "showLowLevel", name = "Also show low level quests", tip = "Shows quests far below your level too.", parent = "availablePins", onChange = RefreshPins },
    { key = "lowLevelRange", kind = "slider", name = "Low level from levels below yours", tip = "A quest counts as low level when its level is at least this many levels below yours. Low level quests are hidden on the map, the minimap, the nameplates and in the dungeon list unless 'Also show low level quests' is on. Default 10.", min = 3, max = 20, step = 1, format = Levels, parent = "availablePins", onChange = RefreshLevels },
    -- (1.24) replaces "Quests without a level count as low level" (the setting is dropped, see Core.lua)
    -- (1.0) event quests and "confirmed only"
    -- (1.25) no second "!" where the game draws its own
    { header = "Quest mobs and objectives" },
    { key = "objectivePins", name = "Show quest mobs and objectives on the map", tip = "Pins where the mobs and objects for your unfinished quest objectives are, one colour per quest. Mouse over for details.", onChange = RefreshPins },
    { key = "objectivePinsTrackedOnly", name = "Only for tracked quests", tip = "Shows these pins only for the quest picked in the quest list and the quests watched in the quest log, so the map stays clear.", parent = "objectivePins", onChange = RefreshPins },
    { key = "objectiveIcons", name = "Symbols instead of dots", tip = "Quest mobs, loot, named mobs, objects to click, places to reach and the places to use a quest item get their own symbol in the quest's colour, on the world map and the minimap. Spots close together become one symbol.", parent = "objectivePins", onChange = function() RefreshPins() if ns.RefreshNameplates then ns.RefreshNameplates() end end },
    { key = "objectiveAreas", name = "Areas under the symbols", tip = "On the world map a group of spots shows its area in the quest's colour, like the game's own quest areas.", parent = "objectiveIcons", onChange = RefreshPins },
    { key = "walkLines", name = "Routes of walking NPCs", tip = "Some quest givers and quest mobs walk a route. A red dotted line on the world map and minimap shows where they walk.", onChange = function() if ns.RefreshWalks then ns.RefreshWalks() end end },
    { key = "hideGamePOIs", name = "Hide the game's quest markers on the world map", tip = "Takes the game's own round objective markers and blue quest areas off the world map, so only Questdon's symbols and areas are shown. The game's markers on the minimap stay. Off by default.", onChange = function() if ns.ApplyGamePOIs then ns.ApplyGamePOIs() end end },
    { key = "mapPinScale", kind = "slider", name = "Map pin size", tip = "Size of all Questdon pins on the world map: quest givers, turn-ins, objectives and dungeon entrances. 100 % is the normal size.", min = 0.25, max = 2, step = 0.05, onChange = RefreshPins },
    { header = "Minimap and nameplates" },
    { key = "minimapPinScale", kind = "slider", name = "Minimap pin size", tip = "Size of all Questdon pins on the minimap. 100 % is the normal size.", min = 0.25, max = 2, step = 0.05, parent = "minimapPins", onChange = RefreshPins },
    { key = "minimapPins", name = "Show the pins on the minimap too", tip = "The same pins as on the world map (available quests, quest mobs and objectives, learned turn-ins) for the zone you are in, also on the minimap. The options above apply there too. A quest giver with several quests is one pin. Mouse over for details, click to point the arrow there.", onChange = RefreshPins },
    { key = "minimapButton", name = "Minimap button", tip = "A Questdon button on the edge of the minimap. Left click: quest book. Right click: a menu with the most used switches and all options. Mouse over: quests here, dungeon quests and your quest log. Drag it around the minimap.", onChange = function() if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end end },
    { key = "nameplateIcons", name = "Quest mob pins on nameplates", tip = "A pin in the quest's colour above the nameplate of mobs of your open objectives. Quest givers and turn-ins keep the game's own ! and ?. Nameplates must be switched on in the game.", onChange = function() if ns.RefreshNameplates then ns.RefreshNameplates() end end },
    -- (1.3.5) dungeon entrances
    { header = "Dungeon entrances" },
    { key = "dungeonPins", name = "Dungeon entrances on the map", tip = "The entrance of every dungeon and raid Questdon knows, on the world map. Mouse over: level range and your quests there. Click: the dungeon in the quest book. Right-click: the arrow leads you there.", onChange = RefreshPins },
    { key = "dungeonPinsMinimap", name = "Dungeon entrances on the minimap", tip = "The same entrances on the minimap, but only when you are within about 300 yards, so the edge of the minimap stays clear.", parent = "minimapPins", onChange = RefreshPins },
    -- (30.10.2026, Daniel 27.10.) inns, auction houses, flight masters and banks
    { header = "Towns" },
    { key = "servicePins", name = "Inns, auction houses, flight masters and banks on the map", tip = "Their symbols on the world map, for your faction and the neutral towns. Mouse over: what it is. Click: the arrow leads you there.", onChange = function() if ns.RefreshServicePins then ns.RefreshServicePins() end end },
    { header = "Learning" },
    { key = "learnQuests", name = "Learn quest locations", tip = "Remembers where you accept and turn in quests and where your objective counters went up (account wide), so your other characters see them on the map too." },
    { key = "shareLearned", name = "Share learned data with guild and group", tip = "Sends what you learned and the data does not have yet (only numbers: quest, NPC, map and item numbers, coordinates) to Questdon players in your guild and group. What two or more players reported is used by everyone, also when this is off.", parent = "learnQuests" },
    { key = "shareChannel", name = "Share with all Questdon players (channel)", tip = "Also sends and receives through the hidden channel QuestdonNet, so data comes from every Questdon player, not only your guild and group. Only numbers are sent. Anybody can join a channel: a fact from there is used only when three players reported it (or two through guild or group). Addon messages never show in your chat; the game may show one line when the channel is joined.", parent = "shareLearned", onChange = function() if ns.ApplyShareChannel then ns.ApplyShareChannel() end end },
    { key = "learnPins", name = "Show turn-ins on the map", tip = "A ? where you hand in a finished quest: where you turned it in before (also on other characters), what other Questdon players reported, or the turn-in NPC of the quest data. Not where the game shows its own ?.", onChange = RefreshPins },
  } },
  { title = "Appearance", tip = "Panel, direction arrow and XP bar: show, lock, size, background opacity, dimming in combat and position. The same options in all our addons.", items = {
    -- (1.3.8, Daniel 13.10.) the old window and its options are gone: its lines are at the bottom of the quest list
    -- (1.3.6, Daniel 12.10.) the quest list with the compass
    { header = "Quest list" },
    { key = "tracker", name = "Show the quest list", tip = "Your quests in Questdon's own window instead of Blizzard's quest tracker: on top the quest you picked with a compass, below the others; the tabs switch between nearby, by zone and by level. Click a quest to pick it, Shift-click to open it in the quest book. /qd list toggles it.", onChange = function()
        -- (1.3.7) without the list its compass is gone too: the arrow comes back
        if ns.SyncArrowWithList then ns.SyncArrowWithList() end -- (review 4) and gone again with the list
        if ns.UpdateTracker then ns.UpdateTracker(true) end if ns.ApplyArrowLook then ns.ApplyArrowLook() end end },
    -- (1.3.7, Daniel 13.10.: "by default the compass in the list and the arrow off; switch it off and the old arrow
    -- comes back; both at once must be possible")
    -- (29.10.2026, round 6) compass and arrow as one choice in the options window instead of two switches that turn
    -- each other on and off; the settings behind it stay trackerCompass and arrow (Blizzard's panel, API, Leveldon)
    { key = "wayMode", kind = "choice", name = "Show the way with", status = GuideStatus, choices = { "Compass", "Arrow", "Both" }, covers = { "trackerCompass", "arrow" },
      tip = "Compass: on the card of the picked quest in the quest list. Arrow: a separate window you can move. Both: the two together. Click to switch.",
      get = function()
        local db = ns.db or {}
        local compass, arrow = db.trackerCompass ~= false, db.arrow and not db.arrowAuto
        return (compass and arrow) and 3 or (compass and 1 or 2)
      end,
      set = function(i)
        local db = ns.db
        local listOn = db.tracker ~= false and db.trackerShown ~= false
        if i == 2 then
          db.trackerCompass, db.arrow, db.arrowAuto = false, true, nil
        elseif i == 3 then
          db.trackerCompass, db.arrow, db.arrowAuto = true, true, nil
        else -- without the list on screen the arrow stands in for the compass and goes with the list's return
          db.trackerCompass, db.arrow, db.arrowAuto = true, not listOn, (not listOn) or nil
        end
        ApplyArrow()
        if ns.UpdateTracker then ns.UpdateTracker(true) end
        if ns.RefreshSettingsUI then ns.RefreshSettingsUI() end
      end },
    { key = "trackerCompass", name = "Compass in the quest list", status = GuideStatus, tip = "A compass on the card of the picked quest. Off: the separate direction arrow comes back. Both at once: also switch on 'Show window' under Direction arrow.", parent = "tracker", onChange = function()
        -- (Questdon review 5) off: the arrow window leads; on: the list's compass leads when the list is there (the
        -- window goes, as before), else the window stays and goes with the list's return
        local db = ns.db
        local listOn = db.tracker ~= false and db.trackerShown ~= false
        if db.trackerCompass == false then
          db.arrow, db.arrowAuto = true, nil
        else
          db.arrow, db.arrowAuto = not listOn, (not listOn) or nil
        end
        ApplyArrow()
        if ns.UpdateTracker then ns.UpdateTracker(true) end
        if ns.RefreshSettingsUI then ns.RefreshSettingsUI() end
      end },
    -- (1.3.7, Discord: "how do I remove low level quests from the quest panel?")
    { key = "trackerHideGrey", name = "Hide grey quests", tip = "Quests that give no XP for your level are not listed at all. Off: they are folded into one line at the bottom.", parent = "tracker", onChange = function() if ns.UpdateTracker then ns.UpdateTracker(true) end end },
    { key = "trackerScale", kind = "slider", name = "Text size", tip = "Size of the quest list and its text. Ctrl + mouse wheel over the title bar does it too.", min = SMIN, max = SMAX, step = 0.05, parent = "tracker", onChange = function() local f = ns.TrackerFrame and ns.TrackerFrame() if f then f:SetPanelScale(ns.db.trackerScale, true) end if ns.UpdateTracker then ns.UpdateTracker(true) end end },
    { key = "trackerPlain", name = "No background and frame", tip = "Hides the quest list's background, its frame and the quest card's gold box: only the text, the compass and the buttons up top stay.", parent = "tracker", onChange = function() if ns.ApplyTrackerChrome then ns.ApplyTrackerChrome() end end },
    { header = "Direction arrow" },
    { key = "arrow", name = "Show window", status = GuideStatus, tip = "Arrow with distance to the quest you picked in the quest list or track in the quest log (nearest objective spot, or the turn-in when it is finished). Left click a Questdon map pin to point the arrow there. Drag to move, right click to drop a clicked target. /qd arrow toggles it.", onChange = function(...) ns.db.arrowAuto = nil ArrowLook(...) end }, -- (review 4) your choice
    { key = "arrowPlain", name = "No background and frame", tip = "Hides the plate behind the arrow's text and its frame: only the arrow and the writing stay. The background opacity below then does nothing.", parent = "arrow", onChange = ArrowLook },
    { key = "arrowLocked", name = "Lock window", tip = "The arrow can no longer be dragged.", parent = "arrow" },
    { key = "arrowNext", name = "Move on to the next quest by itself", tip = "When no quest is tracked (after a turn-in, or after you arrived at a clicked target), the arrow points to the nearest turn-in of a finished quest, or to an open objective close by when that is nearer. Click the arrow to put it aside until your quest log changes.", parent = "arrow", onChange = function() ns.UpdateArrowTarget() end },
    { key = "arrowScale", kind = "slider", name = "Size", tip = "Size of the direction arrow and its text.", min = SMIN, max = SMAX, step = 0.05, parent = "arrow", onChange = ArrowLook },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the arrow back to its default place.", onClick = function() if ns.ResetArrowPosition then ns.ResetArrowPosition() end end },
    { header = "XP bar" },
    { key = "xpBar", name = "Show window", tip = "Blue: your XP. Yellow: XP of the finished quests in your log. Light blue: rested XP. Mouse over for details. /qd xpbar toggles it.", onChange = UpdateXPBarAndPanel },
    { key = "xpBarLocked", name = "Lock window", tip = "When unlocked, drag the bar with the left mouse button.", parent = "xpBar" },
    { key = "xpBarScale", kind = "slider", name = "Size", tip = "Overall size of the XP bar including the text.", min = SMIN, max = SMAX, step = 0.05, parent = "xpBar", onChange = UpdateXPBar },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the XP bar back to its default place.", onClick = function() if ns.ResetXPBarPosition then ns.ResetXPBarPosition() end end },
    { key = "hideBlizzardXP", name = "Hide Blizzard's XP bar", tip = "While this bar is shown, the game's own XP bar at the bottom of the screen is hidden. Your action bars do not move. A tracked reputation bar stays visible.", parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarText", name = "Text under the bar", tip = "Level, percent, quest XP, rested XP, XP per hour and time to the next level as text.", parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarWidth", kind = "slider", name = "Width", tip = "Width of the XP bar.", min = 200, max = 1600, step = 10, format = Pixels, parent = "xpBar", onChange = UpdateXPBar },
  } },
  { title = "Signals", tip = "Sound and message when something is done, and the nearest quest (/qd next).", items = {
    { header = "When something is done" },
    { key = "notifySound", name = "Sound when done", tip = "Plays a sound when a quest objective or a whole quest is done. With 'Questie has priority' on, Questdon stays quiet where Questie plays its own sound." },
    { key = "notifyText", name = "Message when done", tip = "Shows a message in the middle of the screen when an objective or quest is done." },
  } },
  { title = "Comfort", tip = "Merchant, loot, quest item button, targeting and waypoints.", items = {
    { header = "Journal" },
    { key = "journalShots", name = "Screenshots in the journal", tip = "Every screenshot you take becomes an entry in the journal: place, level, target, the quest you follow and your group." },
    { key = "journalLevelShot", name = "Screenshot at level-up", tip = "Takes a screenshot a second after each level-up. The journal marks it." },
    { key = "journalMoments", name = "Moments in the journal", tip = "Also writes deaths, dungeon visits with bosses and time, the first visit of a zone, loot of rare quality or better, a new home, profession steps (75, 150, 225, 300) and new reputation standings into the journal." },
    { header = "Merchant" },
    { key = "sellJunk", name = "Sell junk", tip = "Sells all grey items when you open a merchant." },
    { key = "autoRepair", name = "Auto repair", tip = "Repairs all items at merchants that can repair." },
    { key = "useGuildRepair", name = "Use guild bank for repairs", tip = "Tries the guild bank first, then your own gold.", parent = "autoRepair" },
    { header = "Loot and items" },
    { key = "fastLoot", name = "Fast loot", tip = "Loots everything instantly when auto loot applies. Items that bind on pickup and quest items are left to the game's own auto loot." },
    { key = "questItemButton", name = "Quest item button", tip = "Shows a button for the usable item of your tracked quest. Shift-drag to move. Key binding under Key Bindings > AddOns.", blockedBy = QuestieBlocks("questItemButton"), onChange = RefreshItemButton },
    { header = "Targeting and waypoints" },
    { key = "targetButton", name = "Target button", tip = "Shows a button that targets a mob of your tracked quest with one click. Questdon learns the mob names from nameplates and your target, so a mob must have been seen once. Shift-drag to move. Key binding under Key Bindings > AddOns.", onChange = RefreshTargetButton },
    { key = "exportTomTom", name = "Set TomTom waypoint", tip = "Also sets the spot the arrow points at as a TomTom waypoint. Needs TomTom.", onChange = SyncWaypoint },
  } },
  { title = "Questie", tip = "How Questdon works together with Questie.", items = {
    { header = "Working together" },
    { key = "questieFirst", name = "Questie has priority", tip = "Off by default. On: if Questie already does something (auto accept, auto turn-in, quest item buttons in its tracker, completion sounds, nameplate icons, tooltips), Questdon steps back there. /qd questie shows the current state.", onChange = function() RefreshItemButton() RefreshPins() end },
  } },
}

-- (28.10.2026, Daniel: "Sollten wir einfach Sachen vorgeben, weil wir sind die Entwickler, nicht jeder muss alles
-- einstellen können") options we decide: not in the options window, their default value (Core.lua ns.defaults) is set
-- once for everybody (Core.lua fixedV1313). The features stay; only the switch is gone.
ns.FIXED_OPTIONS = {
  -- map: which quests count, how pins are drawn
  "showNoLevel", "hideEventQuests", "hideRepeatable", "confirmedOnly", "skipGameGivers", "clusterPins", "upcomingLevels",
  "thinObjectives", "objectivePinSize", "pinsOnlyUnknown",
  -- quest list and arrow: the background follows "No background and frame", the rest is how the way is shown
  "trackerDock", "trackerHideBlizz", "trackerAlpha", "trackerCombatFade", "arrowAlpha", "arrowCombatFade",
  "nextConfirmedOnly", "pathDots", "arrowCorpse", "exportBlizzardWaypoint",
  -- quests, XP bar, comfort, sharing
  "highlightBest", "autoPickBest", "chainHint", "partyProgress", "dungeonHint",
  "xpBarAlpha", "xpBarCombatFade", "xpBarHeight", "artInXPPlace", "ownRepBar",
  "starterNotice", "itemButtonScale", "journalStory", "shareTimes",
}

-- (28.10.2026) once: the fixed options to their default; while "Only collect and share data" is on, into the values it
-- gives back, so that mode keeps everything off
function ns.ApplyFixedOptions(db)
  if type(db) ~= "table" or db.fixedV1313 then return end
  local prev = type(db.dataOnlyPrev) == "table" and db.dataOnlyPrev or nil
  for _, k in ipairs(ns.FIXED_OPTIONS) do
    local v = ns.defaults[k]
    if prev and prev[k] ~= nil then prev[k] = v == nil and "nil" or v else db[k] = v end
  end
  db.fixedV1313 = true
end

local function Status()
  local lines = {}
  local version = ns.Version()
  if version ~= "?" then lines[#lines + 1] = L["Version %s"]:format(version) end
  local learned = 0
  for _ in pairs(ns.db.learned or {}) do learned = learned + 1 end
  local att = ns.ATT_META and ns.ATT_META.quests or 0
  lines[#lines + 1] = L["Quest database: %d quests from All The Things, %d learned"]:format(att, learned)
  if ns.AddOnLoaded("Questie") and not (ns.QuestieOn and ns.QuestieOn()) then
    lines[#lines + 1] = L["Questie is switched off."] -- (Questdon review 3)
  elseif ns.AddOnLoaded("Questie") then
    lines[#lines + 1] = ns.db.questieFirst and L["Questie is loaded and has priority."] or L["Questie is loaded, priority is off."]
  else
    lines[#lines + 1] = L["Questie is not loaded."]
  end
  return lines
end

local TOOLS = {
  { "Map style and first steps", "Open", function() if ns.OpenSetup then ns.OpenSetup() end end,
    "The window from the first start: Questdon's symbols, Questdon's dots or only the game's map, and the most used switches. Also /qd setup." },
  { "Reset positions", "Reset", function()
      if ns.ResetTrackerPosition then ns.ResetTrackerPosition() end
      if ns.ResetArrowPosition then ns.ResetArrowPosition() end
      if ns.ResetXPBarPosition then ns.ResetXPBarPosition() end
      if ns.ResetButtonPosition then ns.ResetButtonPosition() end
    end, "Puts the quest list, the arrow, the XP bar and the quest item button back to their default places." },
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
  -- (25.10., Daniel: "can players only collect and share data?") Setup.lua ns.SetDataOnly
  { "Only collect and share data", "On / off", function()
      if ns.SetDataOnly then ns.SetDataOnly() end
    end, "Switches off everything Questdon shows and does by itself (map pins, quest list, arrow, XP bar, tooltips, automation and merchant helpers) and keeps only learning and sharing on. Click again and your settings are back as they were. Also /qd collect." },
  { "Export learned data", "Export", function()
      if ns.OpenExport then ns.OpenExport(false) end
    end, "Shows what Questdon learned and the bundled data does not have yet, as text to copy into a GitHub issue. Helps to improve the quest data for everyone. Numbers, plus the names of NPCs as your game shows them; no names of characters, guilds or players. /qd export (or /qd export all for everything)." },
  { "Diagnostics", "Show", function()
      if ns.OpenDiag then ns.OpenDiag() end
    end, "Report for bug reports: client version, which game functions exist, a few live checks and errors Questdon caught. Only numbers, no names. /qd diag" },
  { "Dungeon quests", "Show", function()
      if ns.OpenDungeons then ns.OpenDungeons() end
    end, "All dungeon quests in your log and the ones you can pick up now, per dungeon, as text. /qd dungeons" },
  { "Delete learned quest data", "Delete", function()
      if ns.Confirm("learned", L["Click again within 5 seconds to delete all learned quest data."]) then
        wipe(ns.db.learned)
        if ns.db.learnedObj then wipe(ns.db.learnedObj) end
        if ns.db.learnedItems then wipe(ns.db.learnedItems) end
        -- (1.3.5) the NPC names the game showed too (/qd export M lines)
        for _, k in ipairs({ "learnedCredit", "learnedDrops", "learnedItemStarts", "learnedGather", "shareSent", "shareSentAt", "notHere", "exportSent", "npcNames" }) do
          if type(ns.db[k]) == "table" then wipe(ns.db[k]) end
        end
        if ns.GatherReset then ns.GatherReset() end
        if ns.db.guessedItems then wipe(ns.db.guessedItems) end
        -- (1.3.5, Daniel 10.10.) and every cache built from it: shared facts (count, spots), the
        -- creature index of tooltips and nameplates (learned credit), the objective points
        if ns.ResetShared then ns.ResetShared() elseif type(ns.db.shared) == "table" then wipe(ns.db.shared) end
        if ns.ResetCreatureIndex then ns.ResetCreatureIndex() end
        if ns.LearnedChanged then ns.LearnedChanged() end
        RefreshPins()
        ns.Print(L["Learned quest data deleted."])
      end
    end, "Deletes everything Questdon learned while playing (all characters). The All The Things data stays." },
}

-- Tool buttons run protected (Blizzard's settings code calls them).
for _, t in ipairs(TOOLS) do t[3] = ns.Guard("tool", t[3]) end

-- (17.10., Daniel: "Blizzard's settings page is not needed any more") The options live in Questdon's own window
-- (OptionsWindow.lua); Blizzard's AddOn list keeps one page with the status and a button that opens it.
ns.OPTION_PAGES, ns.OPTION_TOOLS, ns.OptionStatus = PAGES, TOOLS, Status
local function Build()
  category = ns.BuildSettings({ name = "Questdon", status = Status, pages = {}, tools = {
    { "Questdon's options", "Open", ns.Guard("tool", function()
        if SettingsPanel and SettingsPanel.Hide then pcall(SettingsPanel.Hide, SettingsPanel) end
        if ns.OpenOptionsWindow then ns.OpenOptionsWindow() end
      end), "All options in Questdon's own window, sorted in tabs with a picture of what they change. Also /qd or the cog." } } })
  ns.settingsCategory = category ~= nil
end

-- (17.10.) an option changed outside the settings (the setup window): its own onChange as if clicked there
function ns.OptionChanged(key)
  for _, page in ipairs(PAGES) do
    for _, item in ipairs(page.items or {}) do
      if item.key == key and item.onChange then ns.SafeCall("setting", item.onChange, ns.db[key]) end
    end
  end
  if ns.RefreshSettingsUI then ns.RefreshSettingsUI() end
end

function ns.OpenOptions(tab)
  if ns.OpenOptionsWindow then ns.OpenOptionsWindow(tab) else ns.Print(ns.HELP) end
end

ns.OnInit(Build)
