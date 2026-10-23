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
local SMIN, SMAX = ns.Style.SCALE_MIN, ns.Style.SCALE_MAX

local PAGES = {
  { title = "Quests and automation", tip = "Accepting, turning in, rewards, chains, group, dungeons and tooltips.", items = {
    { header = "Accept and turn in" },
    { key = "autoAccept", name = "Auto accept quests", tip = "Accepts offered quests and escort confirmations. Hold Shift to pause.", blockedBy = QuestieBlocks("autoAccept") },
    { key = "skipTrivial", name = "Ignore grey quests", tip = "Do not auto accept quests that are trivial for your level.", parent = "autoAccept" },
    { key = "autoTurnIn", name = "Auto turn in quests", tip = "Turns in completed quests. Quests with several reward choices or a gold cost, and repeatable quests, are left to you.", blockedBy = QuestieBlocks("autoTurnIn") },
    { header = "Rewards" },
    { key = "highlightBest", name = "Highlight most valuable reward", tip = "Marks the reward with the highest vendor price with a gold coin." },
    { key = "suggestReward", name = "Suggest a reward for your class", tip = "A green frame marks the reward players of your class pick most. Until enough players have picked, it marks the one with armor and stats for your class that beats what you wear." },
    { key = "autoPickBest", name = "Auto pick most valuable reward", tip = "Picks the highest vendor price reward when auto turn-in is on. Careful: ignores possible upgrades.", parent = "autoTurnIn" },
    { header = "Chains and group" },
    { key = "chainHint", name = "Hint for the next quest in a chain", tip = "After turning in a quest, names the follow-up quest and its zone in the chat." },
    { key = "shareQuests", name = "Share new quests with group", tip = "Shares every quest you accept with your group, if it can be shared." },
    { key = "partyProgress", name = "Quest progress with the group", tip = "Group members who use Questdon too see each other's quest progress: in mob tooltips (who still needs this mob), at the bottom of the quest list and on quest pins (who has a quest you can pick up). Only in groups of up to five, only quest numbers and counters are sent. /qd group", onChange = function() if ns.ApplyPartyProgress then ns.ApplyPartyProgress() end UpdatePanel() end },
    { header = "Dungeons" },
    { key = "dungeonHint", name = "Hint when entering a dungeon", tip = "When you enter a dungeon, the chat names its quests in your log and the ones you are missing (and who in the group has them)." },
    { header = "Tooltips" },
    { key = "unitTooltips", name = "Quest info in mob and NPC tooltips", tip = "Mouse over a mob: shows which of your quests it counts for and your progress. Mouse over an NPC: shows quests it has for you. With 'Questie has priority' on, Questdon adds nothing where Questie's tooltips already show the quest." },
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
    { key = "hideRepeatable", name = "Hide repeatable quests", tip = "Repeatable quests (turn in more of the same items, again and again) are always available, so their ! would never leave the map. On: they are not shown on the map, the minimap, the nameplates and in the panel; the zone list still names them as repeatable. Off: shown like any other quest.", parent = "availablePins", onChange = RefreshLevels },
    { key = "confirmedOnly", name = "Only quests confirmed by the game", tip = "Shows only quests the game itself lists for the map or a quest giver has offered you. Safest, but a quest giver you have not met yet shows nothing until the game or the quest giver confirms it. Off: the data decides, with a note 'data only, not confirmed' in the tooltip.", parent = "availablePins", onChange = RefreshLevels },
    -- (1.25) no second "!" where the game draws its own
    { key = "skipGameGivers", name = "No second ! or ? where the game shows one", tip = "The game draws its own ! for quests it lists as available on the map, and on the minimap for every quest giver near you. Questdon then leaves those quest givers to the game on the world map and the minimap, so there is only one !. The panel, the nameplates and the tooltips still name the quests. The same for the ? of a finished quest: where the game marks the turn-in, Questdon draws no learned turn-in point.", parent = "availablePins", onChange = RefreshPins },
    { key = "clusterPins", name = "Merge markers", tip = "On the world map, quest markers (!) that lie close together are merged into one marker with a count (+n). Hover it to see all quests, click it to point the arrow at it. How close depends on the zoom: zoom in to pull them apart. The minimap is not changed.", parent = "availablePins", onChange = RefreshPins },
    { key = "upcomingLevels", kind = "slider", name = "Quests of the next levels", tip = "Also shows quests you can pick up within the next levels, dimmed, with 'from level n' in the tooltip. Only on the world map and the minimap; the panel, the next quest and the nameplates stay with what you can take now. Off by default.", min = 0, max = 5, step = 1, format = Upcoming, parent = "availablePins", onChange = RefreshLevels },
    { header = "Quest mobs and objectives" },
    { key = "objectivePins", name = "Show quest mobs and objectives on the map", tip = "Coloured dots where the mobs and objects for your unfinished quest objectives are (one colour per quest). Mouse over for details.", onChange = RefreshPins },
    { key = "objectivePinsTrackedOnly", name = "Only for tracked quests", tip = "Shows the coloured dots only for quests you track in the quest tracker, so the map stays clear.", parent = "objectivePins", onChange = RefreshPins },
    { key = "thinObjectives", name = "Thin out dense objective dots", tip = "Where many dots lie close together, spots near each other become one slightly larger dot, so the map and the minimap stay readable. On the minimap the spots nearest to you stay single dots. Mouse over a bundled dot to see its quests and how many spots it stands for.", parent = "objectivePins", onChange = RefreshPins },
    { key = "objectiveIcons", name = "Symbols instead of dots", tip = "Quest mobs, loot, named mobs, objects to click, places to reach and the places to use a quest item get their own symbol in the quest's colour, on the world map and the minimap. Spots close together become one symbol.", parent = "objectivePins", onChange = function() RefreshPins() if ns.RefreshNameplates then ns.RefreshNameplates() end end },
    { key = "objectiveAreas", name = "Areas under the symbols", tip = "On the world map a group of spots shows its area in the quest's colour, like the game's own quest areas.", parent = "objectiveIcons", onChange = RefreshPins },
    { key = "walkLines", name = "Routes of walking NPCs", tip = "Some quest givers and quest mobs walk a route. A red dotted line on the world map and minimap shows where they walk.", onChange = function() if ns.RefreshWalks then ns.RefreshWalks() end end },
    { key = "hideGamePOIs", name = "Hide the game's quest markers on the world map", tip = "Takes the game's own round objective markers and blue quest areas off the world map, so only Questdon's symbols and areas are shown. The game's markers on the minimap stay. Off by default.", onChange = function() if ns.ApplyGamePOIs then ns.ApplyGamePOIs() end end },
    { key = "objectivePinSize", kind = "slider", name = "Size of the objective dots", tip = "Size of the coloured dots on the world map.", min = 8, max = 24, step = 1, format = Pixels, parent = "objectivePins", onChange = RefreshPins },
    { header = "Minimap and nameplates" },
    { key = "minimapPins", name = "Show the pins on the minimap too", tip = "The same pins as on the world map (available quests, quest mobs and objectives, learned turn-ins) for the zone you are in, also on the minimap. The options above apply there too. A quest giver with several quests is one pin. Mouse over for details, click to point the arrow there.", onChange = RefreshPins },
    { key = "minimapButton", name = "Minimap button", tip = "A Questdon button on the edge of the minimap. Left click: quest book. Right click: a menu with the most used switches and all options. Mouse over: quests here, dungeon quests and your quest log. Drag it around the minimap.", onChange = function() if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end end },
    { key = "nameplateIcons", name = "Quest mob pins on nameplates", tip = "A pin in the quest's colour above the nameplate of mobs of your open objectives. Quest givers and turn-ins keep the game's own ! and ?. Nameplates must be switched on in the game.", onChange = function() if ns.RefreshNameplates then ns.RefreshNameplates() end end },
    -- (1.3.5) dungeon entrances
    { header = "Dungeon entrances" },
    { key = "dungeonPins", name = "Dungeon entrances on the map", tip = "The entrance of every dungeon and raid Questdon knows, on the world map. Mouse over: level range and your quests there. Click: the dungeon in the quest book. Right-click: the arrow leads you there.", onChange = RefreshPins },
    { key = "dungeonPinsMinimap", name = "Dungeon entrances on the minimap", tip = "The same entrances on the minimap, but only when you are within about 300 yards, so the edge of the minimap stays clear.", parent = "minimapPins", onChange = RefreshPins },
    { header = "Learning" },
    { key = "learnQuests", name = "Learn quest locations", tip = "Remembers where you accept and turn in quests and where your objective counters went up (account wide), so your other characters see them on the map too." },
    { key = "shareLearned", name = "Share learned data with guild and group", tip = "Sends what you learned and the data does not have yet (only numbers: quest, NPC, map and item numbers, coordinates) to Questdon players in your guild and group. What two or more players reported is used by everyone, also when this is off.", parent = "learnQuests" },
    { key = "shareTimes", name = "Share play times", tip = "Measures how long quests take in their objective area, how often quest items drop, how long flights take and which quests are abandoned, and shares these numbers with the other Questdon players. Only numbers (quest, item, mob and map numbers, seconds, your level and class), no names. They make the quest data and Leveldon's routes better.", parent = "shareLearned" },
    { key = "shareChannel", name = "Share with all Questdon players (channel)", tip = "Also sends and receives through the hidden channel QuestdonNet, so data comes from every Questdon player, not only your guild and group. Only numbers are sent. Anybody can join a channel: a fact from there is used only when three players reported it (or two through guild or group). Addon messages never show in your chat; the game may show one line when the channel is joined.", parent = "shareLearned", onChange = function() if ns.ApplyShareChannel then ns.ApplyShareChannel() end end },
    { key = "learnPins", name = "Show turn-ins on the map", tip = "A ? where you hand in a finished quest: where you turned it in before (also on other characters), what other Questdon players reported, or the turn-in NPC of the quest data. Not where the game shows its own ?.", onChange = RefreshPins },
    { key = "pinsOnlyUnknown", name = "Only quests Questie does not know", tip = "Hides this ? for quests that Questie already shows.", parent = "learnPins", onChange = RefreshPins },
  } },
  { title = "Appearance", tip = "Panel, direction arrow and XP bar: show, lock, size, background opacity, dimming in combat and position. The same options in all our addons.", items = {
    -- (1.3.8, Daniel 13.10.) the old window and its options are gone: its lines are at the bottom of the quest list
    -- (1.3.6, Daniel 12.10.) the quest list with the compass
    { header = "Quest list" },
    { key = "tracker", name = "Show the quest list", tip = "Your quests in Questdon's own window instead of Blizzard's quest tracker: on top the quest you picked with a compass, below the others; the tabs switch between nearby, by zone and by level. Click a quest to pick it, Shift-click to read it. /qd list toggles it.", onChange = function()
        -- (1.3.7) without the list its compass is gone too: the arrow comes back
        if ns.SyncArrowWithList then ns.SyncArrowWithList() end -- (review 4) and gone again with the list
        if ns.UpdateTracker then ns.UpdateTracker(true) end if ns.ApplyArrowLook then ns.ApplyArrowLook() end end },
    -- (1.3.7, Daniel 13.10.: "by default the compass in the list and the arrow off; switch it off and the old arrow
    -- comes back; both at once must be possible")
    { key = "trackerCompass", name = "Compass in the quest list", tip = "A compass on the card of the picked quest. Off: the separate direction arrow comes back. Both at once: also switch on 'Show window' under Direction arrow.", parent = "tracker", onChange = function()
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
    { key = "trackerDock", name = "Under Leveldon's window", tip = "With Leveldon open, the quest list hangs right under its window, as wide as it, and moves with it. Leveldon then shows the compass.", parent = "tracker", onChange = function() if ns.UpdateTracker then ns.UpdateTracker(true) end end },
    -- (1.3.7, Discord: "how do I remove low level quests from the quest panel?")
    { key = "trackerHideGrey", name = "Hide grey quests", tip = "Quests that give no XP for your level are not listed at all. Off: they are folded into one line at the bottom.", parent = "tracker", onChange = function() if ns.UpdateTracker then ns.UpdateTracker(true) end end },
    { key = "trackerHideBlizz", name = "Hide Blizzard's quest tracker", tip = "While the quest list is shown, Blizzard's quest tracker is invisible and lets clicks through. Never changed in combat.", parent = "tracker", onChange = function() if ns.ApplyBlizzTracker then ns.ApplyBlizzTracker() end end },
    { key = "trackerScale", kind = "slider", name = "Text size", tip = "Size of the quest list and its text. Ctrl + mouse wheel over the title bar does it too.", min = SMIN, max = SMAX, step = 0.05, parent = "tracker", onChange = function() local f = ns.TrackerFrame and ns.TrackerFrame() if f then f:SetPanelScale(ns.db.trackerScale, true) end if ns.UpdateTracker then ns.UpdateTracker(true) end end },
    { key = "trackerAlpha", kind = "slider", name = "Background opacity", tip = "From a dark window down to no background and no frame, only the text. Shift + mouse wheel over the title bar does it too.", min = 0, max = 1, step = 0.05, parent = "tracker", onChange = function() local f = ns.TrackerFrame and ns.TrackerFrame() if f then f:SetBackgroundAlpha(ns.db.trackerAlpha) end end },
    { key = "trackerPlain", name = "No background and frame", tip = "Hides the window's background, its frame and the quest card's gold box: only the text, the compass and the buttons up top stay.", parent = "tracker", onChange = function() if ns.ApplyTrackerChrome then ns.ApplyTrackerChrome() end end },
    { key = "trackerCombatFade", name = "Dim in combat", tip = "Dims the window to 40 % while you are in combat.", parent = "tracker", onChange = function() local f = ns.TrackerFrame and ns.TrackerFrame() if f then ns.Style.CombatFade(f, ns.db.trackerCombatFade) end end },
    { header = "Direction arrow" },
    { key = "arrow", name = "Show window", tip = "Arrow with distance to the quest you track in the quest log or tracker (nearest objective spot, or the turn-in when it is finished). Left click a Questdon map pin to point the arrow there. Drag to move, right click to drop a clicked target. /qd arrow toggles it.", onChange = function(...) ns.db.arrowAuto = nil ArrowLook(...) end }, -- (review 4) your choice
    { key = "arrowLocked", name = "Lock window", tip = "The arrow can no longer be dragged.", parent = "arrow" },
    { key = "arrowNext", name = "Move on to the next quest by itself", tip = "When no quest is tracked (after a turn-in, or after you arrived at a clicked target), the arrow points to the nearest turn-in of a finished quest, or to an open objective close by when that is nearer. Click the arrow to put it aside until your quest log changes.", parent = "arrow", onChange = function() ns.UpdateArrowTarget() end },
    { key = "pathDots", name = "Show the way as dots", tip = "Where the arrow leads around a mountain or first to the way into a cave, dots on the world map and minimap show the way.", parent = "arrow" },
    { key = "arrowCorpse", name = "Lead to your corpse when dead", tip = "After you released your spirit, the arrow points to your corpse until you are alive again. Then it goes back to your quest.", parent = "arrow" },
    { key = "arrowScale", kind = "slider", name = "Size", tip = "Size of the direction arrow and its text.", min = SMIN, max = SMAX, step = 0.05, parent = "arrow", onChange = ArrowLook },
    { key = "arrowAlpha", kind = "slider", name = "Background opacity", tip = "How dark the plate behind the target and distance is.", min = 0, max = 1, step = 0.05, parent = "arrow", onChange = ArrowLook },
    { key = "arrowCombatFade", name = "Dim in combat", tip = "Dims the arrow to 40 % while you are in combat.", parent = "arrow", onChange = ArrowLook },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the arrow back to its default place.", onClick = function() if ns.ResetArrowPosition then ns.ResetArrowPosition() end end },
    { header = "XP bar" },
    { key = "xpBar", name = "Show window", tip = "Blue: your XP. Yellow: XP of the finished quests in your log. Light blue: rested XP. Mouse over for details. While the bar is shown, the Questdon window leaves its experience lines out. /qd xpbar toggles it.", onChange = UpdateXPBarAndPanel },
    { key = "xpBarLocked", name = "Lock window", tip = "When unlocked, drag the bar with the left mouse button.", parent = "xpBar" },
    { key = "xpBarScale", kind = "slider", name = "Size", tip = "Overall size of the XP bar including the text.", min = SMIN, max = SMAX, step = 0.05, parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarAlpha", kind = "slider", name = "Background opacity", tip = "How dark the strip behind the bar is.", min = 0, max = 1, step = 0.05, parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarCombatFade", name = "Dim in combat", tip = "Dims the XP bar to 40 % while you are in combat.", parent = "xpBar", onChange = XPBarLook },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the XP bar back to its default place.", onClick = function() if ns.ResetXPBarPosition then ns.ResetXPBarPosition() end end },
    { key = "hideBlizzardXP", name = "Hide Blizzard's XP bar", tip = "While this bar is shown, the game's own XP bar at the bottom of the screen is hidden. Your action bars do not move. A tracked reputation bar stays visible.", parent = "xpBar", onChange = UpdateXPBar },
    { key = "artInXPPlace", name = "Ornament in the free place", tip = "In the place of the game's XP bar, an ornate band joins the two end pieces of the action bar.", parent = "hideBlizzardXP", onChange = UpdateXPBar },
    { key = "ownRepBar", name = "Clickable reputation bar", tip = "If you track a faction in the reputation list, Questdon shows it in its own bar in place of the game's: same look, and a click opens the reputation list.", parent = "hideBlizzardXP", onChange = UpdateXPBar },
    { key = "xpBarText", name = "Text under the bar", tip = "Level, percent, quest XP, rested XP, XP per hour and time to the next level as text.", parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarWidth", kind = "slider", name = "Width", tip = "Width of the XP bar.", min = 200, max = 1600, step = 10, format = Pixels, parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarHeight", kind = "slider", name = "Height", tip = "Height of the XP bar.", min = 6, max = 40, step = 1, format = Pixels, parent = "xpBar", onChange = UpdateXPBar },
  } },
  { title = "Signals", tip = "Sound and message when something is done, and the nearest quest (/qd next).", items = {
    { header = "Nearest quest" },
    { key = "nextConfirmedOnly", name = "Nearest quest: only confirmed ones", tip = "/qd next and the arrow from it only use quests the game or a quest giver confirmed. The map still shows all quests." },
    { header = "When something is done" },
    { key = "notifySound", name = "Sound when done", tip = "Plays a sound when a quest objective or a whole quest is done. With 'Questie has priority' on, Questdon stays quiet where Questie plays its own sound." },
    { key = "notifyText", name = "Message when done", tip = "Shows a message in the middle of the screen when an objective or quest is done." },
  } },
  { title = "Comfort", tip = "Merchant, loot, quest item button, targeting and waypoints.", items = {
    { header = "Merchant" },
    { key = "sellJunk", name = "Sell junk", tip = "Sells all grey items when you open a merchant." },
    { key = "autoRepair", name = "Auto repair", tip = "Repairs all items at merchants that can repair." },
    { key = "useGuildRepair", name = "Use guild bank for repairs", tip = "Tries the guild bank first, then your own gold.", parent = "autoRepair" },
    { header = "Loot and items" },
    { key = "fastLoot", name = "Fast loot", tip = "Loots everything instantly when auto loot applies. Items that bind on pickup and quest items are left to the game's own auto loot." },
    { key = "questItemButton", name = "Quest item button", tip = "Shows a button for the usable item of your tracked quest. Shift-drag to move. Key binding under Key Bindings > AddOns.", blockedBy = QuestieBlocks("questItemButton"), onChange = RefreshItemButton },
    { key = "itemButtonScale", kind = "slider", name = "Quest item button size", tip = "Size of the quest item button (changes after combat).", min = 0.6, max = 2, step = 0.05, parent = "questItemButton", onChange = RefreshItemButton },
    { key = "starterNotice", name = "Notice for quest-starting items", tip = "When you loot an item that starts a quest (a book, a letter), a small note above the quest item button shows it, with a quiet sound and a line in the chat. A click on the quest button opens the quest; a click on the note only closes it.", parent = "questItemButton" },
    { header = "Targeting and waypoints" },
    { key = "targetButton", name = "Target button", tip = "Shows a button that targets a mob of your tracked quest with one click. Questdon learns the mob names from nameplates and your target, so a mob must have been seen once. The macro stays under 255 bytes. Shift-drag to move. Key binding under Key Bindings > AddOns.", onChange = RefreshTargetButton },
    { key = "exportBlizzardWaypoint", name = "Set Blizzard map pin", tip = "Also places the spot the arrow points at as the map pin of the game (visible on the world map and the minimap). The arrow keeps working as before.", onChange = SyncWaypoint },
    { key = "exportTomTom", name = "Set TomTom waypoint", tip = "Also sets the spot the arrow points at as a TomTom waypoint. Needs TomTom.", onChange = SyncWaypoint },
  } },
  { title = "Questie", tip = "How Questdon works together with Questie.", items = {
    { header = "Working together" },
    { key = "questieFirst", name = "Questie has priority", tip = "Off by default. On: if Questie already does something (auto accept, auto turn-in, quest item buttons in its tracker, completion sounds, nameplate icons, tooltips), Questdon steps back there. /qd questie shows the current state.", onChange = function() RefreshItemButton() RefreshPins() end },
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
  { "Test the arrow", "Test", function()
      local map, x, y = ns.PlayerPosition()
      if map and ns.SetArrowTarget then
        -- (Questdon review 5) the window for the test only: taken back after a while when the list shows the way
        if not ns.db.arrow then
          ns.db.arrow, ns.db.arrowAuto = true, true
          ns.After(30, function() if ns.db.arrowAuto and ns.SyncArrowWithList then ns.SyncArrowWithList() end end)
        end
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
    end, "Shows what Questdon learned and the bundled data does not have yet, as text to copy into a GitHub issue. Helps to improve the quest data for everyone. Numbers, plus the names of NPCs as your game shows them; no names of characters, guilds or players. /qd export (or /qd export all for everything)." },
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
        -- (1.3.5) the NPC names the game showed too (/qd export M lines)
        for _, k in ipairs({ "learnedCredit", "learnedDrops", "learnedItemStarts", "shareSent", "shareSentAt", "notHere", "exportSent", "npcNames" }) do
          if type(ns.db[k]) == "table" then wipe(ns.db[k]) end
        end
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
