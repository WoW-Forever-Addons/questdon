local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- (1.3.4) Minimap button (Daniel 08.10.: the window has become superfluous).
--   Left click   quest book
--   Right click  a small menu: the five most used switches, quest book, options
--   Drag         moves the button around the minimap (angle saved in ns.db.minimapButtonAngle)
--   Mouse over   what the window showed: quests here, dungeon quests, log slots
-- (31.10.2026, DONCORE_PLAN.md step 3) the button and its menu come from DonCore (Libs\DonCore\MinimapButton.lua);
-- here only what is Questdon's: icon, ring, tooltip lines, the menu's rows and switches.
-- Own frames only: one button on the minimap, one menu frame. The minimap
-- itself is not changed (DESIGN.md).
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"

-- What the old window showed, for the tooltip.
local function InfoLines()
  local lines = {}
  local map = ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  if ns.db.availablePins and map and ns.AvailableQuestsOnMap then
    local ok, available = pcall(ns.AvailableQuestsOnMap, map)
    if ok and type(available) == "table" then lines[#lines + 1] = { L["Available quests here"], Style.Number(#available) } end
  end
  if ns.DungeonOverview and ns.DungeonCounts then
    local ok, overview = pcall(ns.DungeonOverview)
    if ok and type(overview) == "table" and #overview > 0 then
      local inLog, toTake = ns.DungeonCounts(overview)
      lines[#lines + 1] = { L["Dungeon quests"], L["%d in log, %d to pick up"]:format(inLog, toTake) }
    end
  end
  local n, max = ns.QuestLogCount()
  if max then
    lines[#lines + 1] = { L["Quests in log"], ("%d/%d"):format(n, max), n >= max and "critical" or (n >= max - 3 and "warning") or nil }
  end
  return lines
end

-- The switches: label, keys (all set together), what to refresh.
local function RefreshPins() if ns.RefreshPins then ns.RefreshPins() end end
local SWITCHES = {
  { label = "Available quests on the map", keys = { "availablePins" }, apply = RefreshPins },
  { label = "Quest mobs on the map", keys = { "objectivePins" }, apply = RefreshPins },
  { label = "Direction arrow", keys = { "arrow" }, apply = function() ns.db.arrowAuto = nil if ns.ApplyArrow then ns.ApplyArrow() end end }, -- (review 4) your choice
  { label = "Auto accept and turn in", keys = { "autoAccept", "autoTurnIn" } },
  { label = "XP bar", keys = { "xpBar" }, apply = function() if ns.UpdateXPBar then ns.UpdateXPBar() end end },
  -- (1.3.8) the quest list instead of the old window; without the list its compass is gone, the arrow comes back
  { label = "Quest list", keys = { "tracker", "trackerShown" }, apply = function()
      if ns.SyncArrowWithList then ns.SyncArrowWithList() end -- (review 4) and gone again with the list
      if ns.UpdateTracker then ns.UpdateTracker(true) end
      if ns.ApplyArrowLook then ns.ApplyArrowLook() end
    end },
  -- (25.10.) everything off but learning and sharing; again: the settings back (Setup.lua)
  { label = "Only collect and share data", keys = { "dataOnly" },
    isOn = function() return ns.DataOnly and ns.DataOnly() end,
    toggle = function() if ns.SetDataOnly then ns.SetDataOnly() end end },
}
ns.MINIMAP_SWITCHES = SWITCHES -- (tests)

local function IsOn(sw)
  if sw.isOn then return sw.isOn() and true or false end
  for _, k in ipairs(sw.keys) do if not ns.db[k] then return false end end
  return true
end

local function Toggle(sw)
  if sw.toggle then
    ns.SafeCall("minimap menu", sw.toggle)
    if ns.RefreshSettingsUI then ns.SafeCall("minimap menu", ns.RefreshSettingsUI) end
    return
  end
  local on = not IsOn(sw)
  for _, k in ipairs(sw.keys) do ns.db[k] = on end
  if sw.apply then ns.SafeCall("minimap menu", sw.apply) end
  if ns.RefreshSettingsUI then ns.SafeCall("minimap menu", ns.RefreshSettingsUI) end
end
ns.MinimapMenuToggle = function(i) local sw = SWITCHES[i] if sw then Toggle(sw) end end -- (tests)

-- The menu's rows: quest book, a line, the switches (check rows), a line, all options.
local function MenuItems()
  local items = {
    { text = L["Quest book"], onClick = function() if ns.OpenQuestBook then ns.OpenQuestBook() end end },
    { line = true },
  }
  for _, sw in ipairs(SWITCHES) do
    items[#items + 1] = { text = L[sw.label], onClick = function() Toggle(sw) end, isOn = function() return IsOn(sw) end }
  end
  items[#items + 1] = { line = true }
  items[#items + 1] = { text = L["All options"], onClick = function() if ns.OpenOptions then ns.OpenOptions() end end }
  return items
end

LibStub("DonCore-1.0"):Get("MinimapButton", 1):Attach(ns, {
  name = "QuestdonMinimapButton",
  icon = "Interface\\Icons\\INV_Misc_Map_01",
  angleKey = "minimapButtonAngle", defaultAngle = 200,
  title = function() return Style.Wordmark("Quest", "don") end,
  lines = InfoLines,
  hint = function() return L["Left click: quest book. Right click: menu. Drag: move."] end,
  onLeft = function() if ns.ToggleQuestBook then ns.ToggleQuestBook() end end,
  ring = MEDIA .. "BookRing", -- the gold ring of the quest book
  mask = true,
  menu = { name = "QuestdonMinimapMenu", width = 250, items = MenuItems },
})

ns.OnInit(function() ns.SafeCall("minimap button", ns.RefreshMinimapButton) end)
