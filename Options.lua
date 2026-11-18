local _, ns = ...
local L = ns.L

local category

local function RefreshPins() if ns.RefreshPins then ns.RefreshPins() end end
local function RefreshTargetButton() if ns.RefreshTargetButton then ns.RefreshTargetButton() end end
local function SyncWaypoint() if ns.SyncWaypoint then ns.SyncWaypoint() end end
local function RefreshItemButton() if ns.RefreshItemButton then ns.RefreshItemButton() end end
local function ApplyArrow() if ns.ApplyArrow then ns.ApplyArrow() end end
local function Pixels(v) return ("%d"):format(v) end
local function Levels(v) return ("%d"):format(v) end
local function ArrowLook() if ns.ApplyArrow then ns.ApplyArrow() end end
local function XPBarLook() if ns.ApplyXPBarLook then ns.ApplyXPBarLook() end end
local function UpdateXPBar() if ns.UpdateXPBar then ns.UpdateXPBar() end end
-- (1.2) switching the bar also changes the quest list (its experience lines)
local function UpdateXPBarAndList() UpdateXPBar() if ns.UpdateTracker then ns.UpdateTracker(true) end end
-- (25.10., Daniel: "Show window changes nothing") while a guide (Leveldon) shows the compass in its window, Questdon's
-- arrow and the list's compass stay aside whatever these switches say: the row says so (OptionsWindow.lua item.status)
local function GuideStatus() return ns.GuideActive and ns.GuideActive() and "Leveldon" or nil end
local SMIN, SMAX = ns.Style.SCALE_MIN, ns.Style.SCALE_MAX

local PAGES = {
  { title = "Quests and automation", tip = "Accepting, turning in, rewards, chains, group, dungeons and tooltips.", items = {
    { header = "Accept and turn in" },
    { key = "autoAccept", name = "Auto accept quests", tip = "Accepts offered quests and escort confirmations. Hold Shift to pause." },
    { key = "autoTurnIn", name = "Auto turn in quests", tip = "Turns in completed quests. Quests with several reward choices or a gold cost, and repeatable quests, are left to you." },
    { header = "Chains and group" },
    { key = "shareQuests", name = "Share new quests with group", tip = "Shares every quest you accept with your group, if it can be shared." },
    -- (12.11.2026, CurseForge comment, Daniel: on by default, one line per quest) Announce.lua
    { key = "partyAnnounce", name = "Tell the group when a quest is ready", tip = "Writes one line in party chat when a quest of yours is ready to turn in, with a link to the quest. One line per quest, no progress lines, never in a raid. Nothing is written when everyone in the group uses Questdon and nobody else has the quest." },
  } },
  { title = "Map", tip = "Available quests, quest mobs and learned spots on the world map, the minimap and nameplates.", items = {
    -- (1.23) grouped by what is shown; the level options apply to the world map, minimap, nameplates and panel alike
    { header = "Available quests" },
    { key = "availablePins", name = "Show available quests on the map", tip = "Yellow ! for quests you can pick up now: level, faction, race, class and previous quests are checked. Data from All The Things plus what Questdon learned. Skipped where Forever Quest Pins already shows the quest.", onChange = RefreshPins },
    { key = "showLowLevel", name = "Also show low level quests", tip = "Shows quests far below your level too.", parent = "availablePins", onChange = RefreshPins },
    -- (1.24) replaces "Quests without a level count as low level" (the setting is dropped, see Core.lua)
    -- (1.0) event quests and "confirmed only"
    -- (1.25) no second "!" where the game draws its own
    { header = "Quest mobs and objectives" },
    { key = "objectivePins", name = "Show quest mobs and objectives on the map", tip = "Pins where the mobs and objects for your unfinished quest objectives are, one colour per quest. Mouse over for details.", onChange = RefreshPins },
    { key = "objectivePinsTrackedOnly", name = "Only for tracked quests", tip = "Shows these pins only for the quest picked in the quest list and the quests watched in the quest log, so the map stays clear.", parent = "objectivePins", onChange = RefreshPins },
    { key = "objectiveIcons", name = "Symbols instead of dots", tip = "Quest mobs, loot, named mobs, objects to click, places to reach and the places to use a quest item get their own symbol in the quest's colour, on the world map and the minimap. Spots close together become one symbol.", parent = "objectivePins", onChange = function() RefreshPins() if ns.RefreshNameplates then ns.RefreshNameplates() end end },
    { key = "hideGamePOIs", name = "Hide the game's quest markers on the world map", tip = "Takes the game's own round objective markers and blue quest areas off the world map, so only Questdon's symbols and areas are shown. The game's markers on the minimap stay. Off by default.", onChange = function() if ns.ApplyGamePOIs then ns.ApplyGamePOIs() end end },
    { key = "mapPinScale", kind = "slider", name = "Map pin size", tip = "Size of all Questdon pins on the world map: quest givers, turn-ins, objectives and dungeon entrances. 100 % is the normal size.", min = 0.25, max = 2, step = 0.05, onChange = RefreshPins },
    { header = "Minimap and nameplates" },
    { key = "minimapPinScale", kind = "slider", name = "Minimap pin size", tip = "Size of all Questdon pins on the minimap. 100 % is the normal size.", min = 0.25, max = 2, step = 0.05, parent = "minimapPins", onChange = RefreshPins },
    { key = "wayPinScale", kind = "slider", name = "Waypoint pin size", tip = "Size of the /way waypoint pins on the world map and the minimap, on top of the two pin sizes. 100 % is the normal size.", min = 0.5, max = 3, step = 0.1, onChange = RefreshPins },
    { key = "minimapPins", name = "Show the pins on the minimap too", tip = "The same pins as on the world map (available quests, quest mobs and objectives, learned turn-ins) for the zone you are in, also on the minimap. The options above apply there too. A quest giver with several quests is one pin. Mouse over for details, click to point the arrow there.", onChange = RefreshPins },
    { key = "minimapButton", name = "Minimap button", tip = "A Questdon button on the edge of the minimap. Left click: quest book. Right click: a menu with the most used switches and all options. Mouse over: quests here, dungeon quests and your quest log. Drag it around the minimap.", onChange = function() if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end end },
    { key = "nameplateIcons", name = "Quest mob pins on nameplates", tip = "A pin in the quest's colour above the nameplate of mobs of your open objectives. Quest givers and turn-ins keep the game's own ! and ?. Nameplates must be switched on in the game.", onChange = function() if ns.RefreshNameplates then ns.RefreshNameplates() end end },
    -- (1.3.5) dungeon entrances
    { header = "Dungeon entrances" },
    { key = "dungeonPins", name = "Dungeon entrances on the map", tip = "The entrance of every dungeon and raid Questdon knows, on the world map. Mouse over: level range and your quests there. Click: the dungeon in the quest book. Right-click: the arrow leads you there.", onChange = RefreshPins },
    -- (07.11.2026, Discord tP: too many marks on the minimap) the minimap's own "tracked only"; the world map stays
    { key = "minimapTrackedOnly", name = "Only tracked quests on the minimap", tip = "Quest mobs and objectives on the minimap only for the quest picked in the quest list and the quests watched in the quest log. The world map keeps its own setting. The ! of quests to pick up stay.", parent = "minimapPins", onChange = RefreshPins },
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
    { key = "wayMode", kind = "choice", name = "Show the way with", status = GuideStatus, choices = { "Compass", "Arrow", "Both", "None" }, covers = { "trackerCompass", "arrow" },
      -- (05.11.2026, Daniel: an option to have neither arrow nor compass) None: db.noWay
      tip = "Compass: on the card of the picked quest in the quest list. Arrow: a separate window you can move. Both: the two together. None: neither, also not after a click on a map pin (a guide such as Leveldon keeps its own). Click to switch.",
      get = function()
        local db = ns.db or {}
        if db.noWay then return 4 end
        local compass, arrow = db.trackerCompass ~= false, db.arrow and not db.arrowAuto
        return (compass and arrow) and 3 or (compass and 1 or 2)
      end,
      set = function(i)
        local db = ns.db
        local listOn = db.tracker ~= false and db.trackerShown ~= false
        db.noWay = i == 4 or nil
        if i == 4 then
          db.trackerCompass, db.arrow, db.arrowAuto = false, false, nil
        elseif i == 2 then
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
        if db.noWay and db.trackerCompass ~= false then db.noWay = nil end -- (05.11.2026) switched on: "None" ends
        if db.noWay then -- (05.11.2026) "None": switched off stays without an arrow
          db.arrow, db.arrowAuto = false, nil
        elseif db.trackerCompass == false then
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
    -- (12.11.2026, Daniel: the list as an option "mehr wie blizzards eigene") one choice instead of the switch "No background
    -- and frame": Don (trackerPlain false), Don without background (trackerPlain), like the game (trackerPlain and trackerGame)
    -- (18.11.2026) shown in the order of ns.LOOK_ORDER: the choice's position is not the saved number
    { key = "trackerLook", kind = "choice", name = "Look of the quest list", choices = { "Questdon", "Questdon, transparent", "Blizzard", "Blizzard, transparent" }, covers = { "trackerPlain", "trackerGame" }, parent = "tracker",
      tip = "Questdon: Questdon's own window with background and frame. Blizzard: reads like the game's own quest list, plain text in the game's colours with the objectives under each quest, on the game's dark box with its frame. Transparent: the same without background and frame. Click to switch.",
      get = function()
        local cur = ns.TrackerLook and ns.TrackerLook() or 1
        for pos, n in ipairs(ns.LOOK_ORDER or {}) do if n == cur then return pos end end
        return 1
      end,
      set = function(pos) if ns.SetTrackerLook then ns.SetTrackerLook(ns.LOOK_ORDER and ns.LOOK_ORDER[pos] or pos) end end,
      -- (17.11.2026, DonCore Settings 5) in the game's settings a dropdown on db.trackerLook
      -- the value is the saved number, the list in the shown order
      options = function() local out = {} for pos, n in ipairs(ns.LOOK_ORDER) do local c = ns.LOOK_NAMES[n] out[pos] = { n, L[c] or c } end return out end,
      onChange = function(v) if ns.SetTrackerLook then ns.SetTrackerLook(v) end end },
    { header = "Direction arrow" },
    { key = "arrow", name = "Show window", status = GuideStatus, tip = "Arrow with distance to the quest you picked in the quest list or track in the quest log (nearest objective spot, or the turn-in when it is finished). Left click a Questdon map pin to point the arrow there. Drag to move, right click to drop a clicked target. /qd arrow toggles it.", onChange = function(...) ns.db.arrowAuto = nil if ns.db.arrow then ns.db.noWay = nil end ArrowLook(...) end }, -- (review 4) your choice
    { key = "arrowPlain", name = "No background and frame", tip = "Hides the plate behind the arrow's text and its frame: only the arrow and the writing stay. The background opacity below then does nothing.", parent = "arrow", onChange = ArrowLook },
    { key = "arrowLocked", name = "Lock window", tip = "The arrow can no longer be dragged.", parent = "arrow" },
    { key = "arrowScale", kind = "slider", name = "Size", tip = "Size of the direction arrow and its text.", min = SMIN, max = SMAX, step = 0.05, parent = "arrow", onChange = ArrowLook },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the arrow back to its default place.", onClick = function() if ns.ResetArrowPosition then ns.ResetArrowPosition() end end },
    { header = "XP bar" },
    { key = "xpBar", name = "Show window", tip = "Blue: your XP. Yellow: XP of the finished quests in your log. Light blue: rested XP. Mouse over for details. /qd xpbar toggles it.", onChange = UpdateXPBarAndList },
    { key = "xpBarLocked", name = "Lock window", tip = "When unlocked, drag the bar with the left mouse button.", parent = "xpBar" },
    { key = "xpBarScale", kind = "slider", name = "Size", tip = "Overall size of the XP bar including the text.", min = SMIN, max = SMAX, step = 0.05, parent = "xpBar", onChange = UpdateXPBar },
    { kind = "button", name = "Reset position", button = "Reset", tip = "Puts the XP bar back to its default place.", onClick = function() if ns.ResetXPBarPosition then ns.ResetXPBarPosition() end end },
    { key = "xpBarText", name = "Text under the bar", tip = "Level, percent, quest XP, rested XP, XP per hour and time to the next level as text.", parent = "xpBar", onChange = UpdateXPBar },
    { key = "xpBarWidth", kind = "slider", name = "Width", tip = "Width of the XP bar.", min = 200, max = 1600, step = 10, format = Pixels, parent = "xpBar", onChange = UpdateXPBar },
    -- (16.11.2026, Daniel: "Sollte Standart sein", Blizzard look for all Don addons as in Luredon 1.7.0) the quest book
    -- and the dialogs from the game's own templates (DonCore Blizz); the quest list keeps its own look choice
    { header = "Windows" },
    { key = "blizzLook", name = "Windows in the game's look", tip = "Questdon's windows look like the game's own: the quest book and the dialogs with the game's frame, tabs, buttons and lists. The quest list keeps its own look (above). The options then open in the game's settings (Options > AddOns > Questdon) after a /reload.", onChange = function()
      if ns.QuestBookReset then ns.QuestBookReset() end
      if ns.DialogsReset then ns.DialogsReset() end
    end },
  } },
  { title = "Signals", tip = "Sound and message when something is done, and the nearest quest (/qd next).", items = {
    { header = "When something is done" },
    { key = "notifySound", name = "Sound when done", tip = "Plays a sound when a quest objective or a whole quest is done." },
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
    -- (12.11.2026, Daniel) a button for each quest's usable item beside its row; the single button below stays as an option
    { key = "trackerItemButtons", name = "Item buttons in the quest list", tip = "Shows a button beside each quest in the quest list whose item you can use; a click uses it. In a fight the buttons stay as they are. The key binding (Key Bindings > AddOns) uses the item of your tracked quest.", onChange = function() RefreshItemButton() if ns.UpdateTracker then ns.UpdateTracker(true) end end },
    { key = "questItemButton", name = "Quest item button", tip = "Shows a button for the usable item of your tracked quest. Shift-drag to move. Key binding under Key Bindings > AddOns.", onChange = RefreshItemButton },
    { header = "Targeting and waypoints" },
    { key = "targetButton", name = "Target button", tip = "Shows a button that targets a mob of your tracked quest with one click. Questdon learns the mob names from nameplates and your target, so a mob must have been seen once. Shift-drag to move. Key binding under Key Bindings > AddOns.", onChange = RefreshTargetButton },
    { key = "exportTomTom", name = "Set TomTom waypoint", tip = "Also sets the spot the arrow points at as a TomTom waypoint. Needs TomTom.", onChange = SyncWaypoint },
  } },
}

-- (10.11.2026, Daniel: fewer switches) areas, dungeon entrances on the minimap and the routes of walking NPCs lost
-- their own switches: they follow the switch they belong to, here and with the map styles (Setup.lua)
do
  local function Walks(db) db.walkLines = (db.availablePins or db.objectivePins) and true or false if ns.RefreshWalks then ns.RefreshWalks() end end
  local FOLLOW = {
    objectiveIcons = function(db) db.objectiveAreas = db.objectiveIcons and true or false end,
    dungeonPins = function(db) db.dungeonPinsMinimap = db.dungeonPins and true or false end,
    availablePins = Walks, objectivePins = Walks,
  }
  ns.OPTION_FOLLOW = FOLLOW -- (tests)
  for _, page in ipairs(PAGES) do
    for _, item in ipairs(page.items) do
      local follow, inner = FOLLOW[item.key], item.onChange
      if follow then
        item.onChange = function(...)
          if ns.db then follow(ns.db) end
          if inner then return inner(...) end
        end
      end
    end
  end
end

-- (28.10.2026, Daniel: "Sollten wir einfach Sachen vorgeben, weil wir sind die Entwickler, nicht jeder muss alles
-- einstellen können") options we decide: not in the options window, their default value (Core.lua ns.defaults) is set
-- once for everybody (Core.lua fixedV1313). The features stay; only the switch is gone.
ns.FIXED_OPTIONS = {
  -- map: which quests count, how pins are drawn
  "showNoLevel", "hideEventQuests", "hideRepeatable", "confirmedOnly", "skipGameGivers",
  "thinObjectives", "objectivePinSize", "pinsOnlyUnknown",
  -- quest list and arrow: the background follows "No background and frame", the rest is how the way is shown
  "trackerDock", "trackerHideBlizz", "trackerAlpha", "trackerCombatFade", "arrowAlpha", "arrowCombatFade",
  "nextConfirmedOnly", "pathDots", "arrowCorpse",
  -- quests, XP bar, comfort, sharing
  "highlightBest", "chainHint", "partyProgress", "dungeonHint",
  "xpBarAlpha", "xpBarCombatFade", "xpBarHeight", "artInXPPlace", "ownRepBar",
  "starterNotice", "itemButtonScale", "journalStory", "shareTimes",
  -- (10.11.2026, Daniel: the whole proposal, 56 switches down to 47) second round, set once with fixedV1110
  "arrowNext", "suggestReward", "hideBlizzardXP", "lowLevelRange", "skipTrivial", "unitTooltips",
  "objectiveAreas", "walkLines", "dungeonPinsMinimap",
}
local FIXED_1110 = { "arrowNext", "suggestReward", "hideBlizzardXP", "lowLevelRange", "skipTrivial", "unitTooltips" }

-- (28.10.2026) once: the fixed options to their default; while "Only collect and share data" is on, into the values it
-- gives back, so that mode keeps everything off
-- (10.11.2026) the second round with its own mark; the three that belong to another switch take its value, so a map
-- style stays what it was ("Only the game's map" keeps the routes and the minimap entrances off)
function ns.ApplyFixedOptions(db)
  if type(db) ~= "table" then return end
  local prev = type(db.dataOnlyPrev) == "table" and db.dataOnlyPrev or nil
  local function Get(k)
    local v = db[k]
    if prev and prev[k] ~= nil then v = prev[k] if v == "nil" then v = nil end end
    return v
  end
  local function Put(k, v)
    if prev and prev[k] ~= nil then prev[k] = v == nil and "nil" or v else db[k] = v end
  end
  if not db.fixedV1313 then
    for _, k in ipairs(ns.FIXED_OPTIONS) do Put(k, ns.defaults[k]) end
    db.fixedV1313 = true -- the second round follows at once (a store from before 28.10.2026 keeps its map style too)
  end
  -- (12.11.2026, Daniel chose: once off) the buttons in the quest list take over: the single quest item button, on by
  -- default until then, goes off once for everybody; who wants it back switches it on again
  if not db.itemButtonsV1112 then
    Put("questItemButton", false)
    db.itemButtonsV1112 = true
  end
  if not db.fixedV1110 then
    for _, k in ipairs(FIXED_1110) do Put(k, ns.defaults[k]) end
    Put("objectiveAreas", Get("objectiveIcons") and true or false)
    Put("dungeonPinsMinimap", Get("dungeonPins") and true or false)
    Put("walkLines", (Get("availablePins") or Get("objectivePins")) and true or false)
    db.fixedV1110 = true
  end
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
    lines[#lines + 1] = L["Questie is loaded."]
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
    end, "Starts XP per hour from zero." },
  -- (1.1) quests hidden as "not offered here" (NotHere.lua)
  { "Quests hidden as not offered", "Show again", function()
      if ns.Confirm("nothere", L["Click again within 5 seconds to show all quests again that were hidden as not offered."]) then
        if ns.ResetNotHere then ns.ResetNotHere() end
        ns.Print(L["All quests hidden as not offered are shown again."])
      end
    end, "Questdon hides a quest when its quest giver did not offer it at 3 different levels, or when you reported it (Alt-click on the !, or /qd nothere with the NPC targeted). This shows them all again. /qd nothere list shows them, /qd nothere undo takes back the last report." },
  -- (25.10., Daniel: "can players only collect and share data?") Setup.lua ns.SetDataOnly
  -- (02.11.2026, Daniel: no visual confirmation of the state) a switch in DonCore's window (state), on means data only
  { "Only collect and share data", "On / off", function()
      if ns.SetDataOnly then ns.SetDataOnly() end
    end, state = function() return ns.DataOnly and ns.DataOnly() or false end, "Switches off everything Questdon shows and does by itself (map pins, quest list, arrow, XP bar, tooltips, automation and merchant helpers) and keeps only learning and sharing on. Click again and your settings are back as they were. Also /qd collect." },
  { "Export learned data", "Export", function()
      if ns.OpenExport then ns.OpenExport(false) end
    end, "Shows what Questdon learned and the bundled data does not have yet, as text to copy into a GitHub issue. Helps to improve the quest data for everyone. Numbers, plus the names of NPCs as your game shows them; no names of characters, guilds or players. /qd export (or /qd export all for everything)." },
  { "Diagnostics", "Show", function()
      if ns.OpenDiag then ns.OpenDiag() end
    end, "Report for bug reports: client version, which game functions exist, a few live checks and errors Questdon caught. Only numbers, no names. /qd diag" },
  { "Dungeon quests", "Show", function()
      -- (04.11.2026, Era-Test) the quest book's "dungeons" tab instead of the old text window
      if ns.OpenQuestBook then ns.OpenQuestBook("dungeons") elseif ns.OpenDungeons then ns.OpenDungeons() end
    end, "All dungeon quests in your log and the ones you can pick up now, per dungeon, in the quest book. /qd dungeons" },
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

-- (17.10., Daniel: "Blizzard's settings page is not needed any more") The options live in the window
-- (OptionsWindow.lua); Blizzard's AddOn list keeps one page with the status and a button that opens it.
-- (01.11.2026, STYLEKIT_PLAN.md "Schritt 3") that page is DonCore's (Settings minor 2): status plus "Options / Open",
-- the same for every Don addon. ownWindow: Questdon registers its tabs itself (OptionsWindow.lua), Settings adds none.
ns.OPTION_PAGES, ns.OPTION_TOOLS, ns.OptionStatus = PAGES, TOOLS, Status
-- (16.11.2026, DonCore Settings 3) with the option blizzLook the options are the game's own settings pages, built in
-- full at login (only where the client has the templates: without them the windows are Don's and so are the options)
local fullPages = false
local function Build()
  local spec = { name = "Questdon", status = Status, pages = {}, ownWindow = true }
  if ns.db and ns.db.blizzLook and ns.LookKit and select(2, ns.LookKit()) then
    spec.pages, spec.tools, spec.fullPages, fullPages = PAGES, TOOLS, true, true
  end
  category = ns.BuildSettings(spec)
  ns.settingsCategory = category ~= nil
end
-- true when the game's settings were opened at Questdon (option blizzLook, pages built in full at login, not in combat)
function ns.OpenGameOptions()
  if not (ns.db and ns.db.blizzLook and fullPages and category and Settings and Settings.OpenToCategory) then return false end
  if InCombatLockdown() then ns.Print(L["Options cannot be opened in combat."]) return true end
  Settings.OpenToCategory(category:GetID())
  return true
end
function ns.OptionsLook() return fullPages and "game settings" or "don window" end

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
  if ns.OpenGameOptions and ns.OpenGameOptions() then return end -- (16.11.2026) the game's look: the game's settings
  if ns.OpenOptionsWindow then ns.OpenOptionsWindow(tab) else ns.Print(ns.HELP) end
end

ns.OnInit(Build)
