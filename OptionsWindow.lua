local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (17.10., Daniel: "a Questdon options window: everything easy to find, several tabs and example pictures for the UI
-- parts, instead of the cog and /qd options going to Blizzard's settings"; "clear enough for the least experienced
-- player") Questdon's own options window. The options themselves stay in Options.lua (ns.OPTION_PAGES: name, tip,
-- kind, onChange, parent); here they are sorted into tabs. Each tab shows its main switches with their explanation
-- right under the name (no tooltip needed), the rarely used ones folded under "More settings", a picture of what the
-- tab changes on the right, a search over all options at the top and "Reset this tab" at the bottom. Blizzard's
-- settings only keep a button that opens this window.
-- (01.11.2026, STYLEKIT_PLAN.md "Schritt 3") the window moved to DonCore (Options.lua) and takes the Don style; this file
-- keeps Questdon's tabs and hands them over.
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
local TAB_ICONS = { map = "Interface\\Icons\\INV_Misc_Map_01", list = "Interface\\Icons\\INV_Misc_Note_01",
  accept = "Interface\\Icons\\INV_Letter_15", xp = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
  comfort = "Interface\\Icons\\INV_Misc_Bag_08", share = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  help = "Interface\\Icons\\INV_Misc_QuestionMark" }

-- the tabs: main switches first, the rest under "More settings"; buttons by their name; "tools" from the tool list
local TABS = {
  { key = "map", title = "Map", pic = "setup_questdon",
    text = "What Questdon shows on the world map and the minimap: quests you can pick up, the mobs and places of your quests, dungeon entrances.",
    -- (17.10., Daniel: "shouldn't map style be at the top under Map?") the start window's three map styles, first
    top = { "Map style and first steps" },
    -- (28.10.2026, Daniel: "die Optionen einfach teilweise zu viel ... Sollten wir einfach Sachen vorgeben") 89 switches
    -- down to 52, the hidden ones from 54 to 29; what we decide as developers is in ns.FIXED_OPTIONS (Options.lua)
    main = { "availablePins", "objectivePins", "objectiveIcons", "learnPins", "minimapPins", "dungeonPins", "servicePins" },
    more = { "showLowLevel", "lowLevelRange", "objectivePinsTrackedOnly", "objectiveAreas", "hideGamePOIs", "walkLines",
      "nameplateIcons", "dungeonPinsMinimap", "mapPinScale", "minimapPinScale", "minimapButton" } },
  { key = "list", title = "Quest list and arrow", pic = "opt_list",
    text = "Your quests in Questdon's list with a compass, and the arrow that leads you to the next objective.",
    -- (25.10., Daniel: "you cannot tell at first sight which option is for the list and which for the arrow") headers
    main = { "header:Quest list", "tracker",
      "header:Direction arrow", "wayMode", "arrowNext" },
    more = { "header:Quest list", "trackerPlain", "trackerHideGrey", "trackerScale",
      "header:Direction arrow", "arrowPlain", "arrowLocked", "arrowScale", "button:arrow",
      "header:Targeting and waypoints", "targetButton", "exportTomTom" } },
  { key = "accept", title = "Accept and turn in", pic = "opt_accept",
    text = "Quests taken and turned in for you, the reward that suits you marked, a sound when something is done.",
    main = { "autoAccept", "autoTurnIn", "suggestReward", "notifySound", "notifyText" },
    more = { "skipTrivial", "shareQuests", "unitTooltips", "questieFirst" } },
  { key = "xp", title = "XP bar", pic = "opt_xp",
    text = "Questdon's experience bar: XP, rested XP, finished quests, XP per hour and the time to the next level.",
    main = { "xpBar", "xpBarText", "hideBlizzardXP" },
    more = { "xpBarLocked", "xpBarScale", "xpBarWidth", "button:xp" } },
  { key = "comfort", title = "Comfort", pic = "opt_comfort",
    text = "Small helpers: sell junk and repair at a merchant, fast loot, a button for quest items, and the journal.",
    main = { "sellJunk", "autoRepair", "fastLoot", "questItemButton" },
    more = { "useGuildRepair", "journalShots", "journalMoments", "journalLevelShot" } },
  { key = "share", title = "Sharing and data", pic = "opt_share",
    text = "What Questdon learns while you play and shares with other Questdon players (only quest and map numbers, never names).",
    top = { "Only collect and share data" }, -- (25.10.) Setup.lua ns.SetDataOnly
    -- (28.10.2026, Daniel: "Für Questdon und uns ist das Sammeln immens wichtig ... ab Werk an ist ein Muss") on by default
    main = { "learnQuests", "shareLearned", "shareChannel" },
    tools = { "Export learned data", "Quests hidden as not offered", "Delete learned quest data" } },
  { key = "help", title = "Help", pic = "opt_help",
    text = "Positions, reports for bug reports and the dungeon quests as text.",
    status = true,
    tools = { "Reset positions", "Reset XP session", "Diagnostics", "Dungeon quests" } },
}
ns.OPTION_TABS = TABS -- (tests)

-- a slider's value as text: its own format, else percent (as Blizzard's settings showed it)
function ns.OptionValueText(item, v)
  if item.format then return item.format(v) end
  return ("%d%%"):format(v * 100 + 0.5)
end
---------------------------------------------------------------------------
-- (01.11.2026, STYLEKIT_PLAN.md "Schritt 3") the window itself is DonCore's (Libs\DonCore\Options.lua): one window for
-- every Don addon in the Don style, Questdon only describes its tabs here. NewWindow(src) keeps the old way for other
-- addons (QuestdonAPI.NewOptionsWindow: Leveldon, Luredon): their tabs go into the same window, under their name.
-- src = { frameName, wordmark, media, tabs, pages(), tools(), db(), default(key), changed(key), T(text), status(),
-- help(), buttonKey(section) }; items may be kind = "dropdown" with options() -> { { value, label }, ... }
---------------------------------------------------------------------------
local Opt = LibStub("DonCore-1.0"):Get("Options", 1)
local ORDER = { QuestdonOptions = 1, LeveldonOptions = 2, LuredonOptions = 3 }
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function NewWindow(src)
  if not Opt then return nil end
  local id = Plain(src.name or src.wordmark or src.frameName)
  if id == "" then id = tostring(src.frameName or "Addon") end
  src.name = src.name or id
  src.order = src.order or ORDER[src.frameName]
  src.T = src.T or function(s) return L[s] end
  Opt.Register(id, src)
  return {
    Open = function(tab) return Opt.Open(id, tab) end,
    Toggle = function() return Opt.Toggle(id) end,
    Render = function() return Opt.Render() end,
    Preview = function() return Opt.Preview() end,
    Item = function(key) return Opt.Item(id, key) end,
    Frame = function() return Opt.Frame() end,
    Rows = function() return Opt.Rows() end, -- (tests)
    Search = function(text) return Opt.Search(text) end, -- (tests)
    Menu = function() local K = LibStub("DonCore-1.0"):Get("Kit", 1) return K and K._menu end, -- (tests)
  }
end

-- Questdon's own tabs (Options.lua's pages and tools, ns.db); the window's own words in Questdon's languages
local QD = NewWindow({
  frameName = "QuestdonOptions", name = "Questdon", wordmark = ns.Style.Wordmark("Quest", "don"), media = MEDIA, tabs = TABS,
  icons = TAB_ICONS, labels = function(s) return L[s] end,
  pages = function() return ns.OPTION_PAGES end, tools = function() return ns.OPTION_TOOLS end,
  db = function() return ns.db end, default = function(key) return ns.defaults and ns.defaults[key] end,
  changed = function(key) if ns.OptionChanged then ns.OptionChanged(key) end end,
  T = function(s) return L[s] end,
  status = function() return ns.OptionStatus and ns.OptionStatus() or {} end, help = function() return ns.HELP end,
  buttonKey = function(section) return (section == "XP bar") and "button:xp" or "button:arrow" end,
})
if Opt then Opt.onError = function(where, err) if ns.RecordError then ns.RecordError("options " .. tostring(where), err) end end end
ns.NewOptionsWindow = NewWindow
local function Q(fn) return function(...) if QD then return fn(...) end end end
function ns.OptionItem(key) return QD and QD.Item(key) end
ns.RenderOptions = Q(function() return QD.Render() end)
ns.RefreshOptionsPreview = Q(function() return QD.Preview() end)
ns.OpenOptionsWindow = Q(function(tab) return QD.Open(tab) end)
ns.ToggleOptionsWindow = Q(function() return QD.Toggle() end)
ns.OptionsWindowFrame = Q(function() return QD.Frame() end) -- (tests)
ns.OptionsWindowRows = Q(function() return QD.Rows() end) -- (tests)
ns.OptionsSearch = Q(function(text) return QD.Search(text) end) -- (tests)
