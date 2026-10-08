local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- (1.3.4) Minimap button (Daniel 08.10.: the window has become superfluous).
--   Left click   quest book
--   Right click  a small menu: the five most used switches, quest book, options
--   Drag         moves the button around the minimap (angle saved)
--   Mouse over   what the window showed: quests here, dungeon quests, log slots
-- Own frames only: one button on the minimap, one menu frame. The minimap
-- itself is not changed (DESIGN.md).
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local DEFAULT_ANGLE = 200
local MENU_W = 250

local button, menu, catcher

local function Enabled() return ns.db and ns.db.minimapButton end

local function Shape()
  local s = ns.Value(GetMinimapShape)
  return type(s) == "string" and s or "ROUND"
end

-- Place the button on the edge of the minimap at the saved angle (degrees, 0 = right, counter-clockwise).
local function Place()
  if not button or not Minimap then return end
  local angle = math.rad(tonumber(ns.db.minimapButtonAngle) or DEFAULT_ANGLE)
  local w = (ns.Num(ns.Value(Minimap.GetWidth, Minimap)) or 140) / 2 + 8
  local h = (ns.Num(ns.Value(Minimap.GetHeight, Minimap)) or 140) / 2 + 8
  local x, y = math.cos(angle), math.sin(angle)
  if Shape() == "SQUARE" then
    local m = math.max(math.abs(x), math.abs(y))
    if m > 0 then x, y = x / m, y / m end
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

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

---------------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------------
-- The switches: label, keys (all set together), what to refresh.
local function RefreshPins() if ns.RefreshPins then ns.RefreshPins() end end
local SWITCHES = {
  { label = "Quest markers on the map", keys = { "availablePins" }, apply = RefreshPins },
  { label = "Quest mobs on the map", keys = { "objectivePins" }, apply = RefreshPins },
  { label = "Direction arrow", keys = { "arrow" }, apply = function() if ns.ApplyArrow then ns.ApplyArrow() end end },
  { label = "Auto accept and turn in", keys = { "autoAccept", "autoTurnIn" } },
  { label = "XP bar", keys = { "xpBar" }, apply = function() if ns.UpdateXPBar then ns.UpdateXPBar() end end },
  { label = "Questdon window", keys = { "showPanel" }, apply = function() if ns.UpdatePanel then ns.UpdatePanel() end end },
}
ns.MINIMAP_SWITCHES = SWITCHES -- (tests)

local function IsOn(sw)
  for _, k in ipairs(sw.keys) do if not ns.db[k] then return false end end
  return true
end

local function Toggle(sw)
  local on = not IsOn(sw)
  for _, k in ipairs(sw.keys) do ns.db[k] = on end
  if sw.apply then ns.SafeCall("minimap menu", sw.apply) end
  if ns.RefreshSettingsUI then ns.SafeCall("minimap menu", ns.RefreshSettingsUI) end
end
ns.MinimapMenuToggle = function(i) local sw = SWITCHES[i] if sw then Toggle(sw) end end -- (tests)

local function HideMenu()
  if menu then menu:Hide() end
  if catcher then catcher:Hide() end
end

local function Row(parent, y, text, onClick, check)
  local r = CreateFrame("Button", nil, parent)
  r:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -y)
  r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -y)
  r:SetHeight(24)
  r.hover = r:CreateTexture(nil, "BACKGROUND")
  r.hover:SetAllPoints(r)
  r.hover:SetColorTexture(1, 1, 1, 0.07)
  r.hover:Hide()
  if check then
    r.box = r:CreateTexture(nil, "ARTWORK")
    r.box:SetSize(20, 20)
    r.box:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    r.tick = r:CreateTexture(nil, "OVERLAY")
    r.tick:SetSize(20, 20)
    r.tick:SetPoint("CENTER", r.box, "CENTER", 0, 0)
    r.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  end
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.text:SetPoint("LEFT", r, "LEFT", check and 28 or 8, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.text:SetText(text)
  r:SetScript("OnEnter", function(self) self.hover:Show() end)
  r:SetScript("OnLeave", function(self) self.hover:Hide() end)
  r:SetScript("OnClick", function(self) ns.SafeCall("minimap menu", onClick, self) end)
  return r
end

local function Edge(f, r, g, b, a)
  local function Line(p1, p2, horiz)
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r, g, b, a)
    t:SetPoint(p1, f, p1) t:SetPoint(p2, f, p2)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
  end
  Line("TOPLEFT", "TOPRIGHT", true) Line("BOTTOMLEFT", "BOTTOMRIGHT", true)
  Line("TOPLEFT", "BOTTOMLEFT") Line("TOPRIGHT", "BOTTOMRIGHT")
end

local function UpdateMenu()
  if not menu then return end
  for _, r in ipairs(menu.switchRows) do
    if IsOn(r.sw) then r.tick:Show() else r.tick:Hide() end
  end
end

local function CreateMenu()
  catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("DIALOG")
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", HideMenu)
  catcher:Hide()
  menu = CreateFrame("Frame", "QuestdonMinimapMenu", UIParent)
  menu:SetFrameStrata("DIALOG")
  local lvl = ns.Num(catcher.GetFrameLevel and catcher:GetFrameLevel())
  if lvl and menu.SetFrameLevel then menu:SetFrameLevel(lvl + 10) end
  menu:SetWidth(MENU_W)
  menu:EnableMouse(true)
  menu:SetClampedToScreen(true)
  menu:Hide()
  local bg = menu:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(menu)
  bg:SetColorTexture(1, 1, 1, 1)
  if bg.SetGradient and CreateColor then
    pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.15, 0.10, 0.25, 0.97), CreateColor(0.10, 0.11, 0.22, 0.97))
  else
    bg:SetColorTexture(0.10, 0.11, 0.22, 0.97)
  end
  Edge(menu, 0.86, 0.71, 0.42, 0.9)
  local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", menu, "TOPLEFT", 14, -10)
  title:SetText(Style.Wordmark("Quest", "don"))
  local y = 32
  Row(menu, y, L["Quest book"], function() HideMenu() if ns.OpenQuestBook then ns.OpenQuestBook() end end)
  y = y + 26
  local line = menu:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.86, 0.71, 0.42, 0.35)
  line:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -y - 2)
  line:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -12, -y - 2)
  line:SetHeight(1)
  y = y + 6
  menu.switchRows = {}
  for _, sw in ipairs(SWITCHES) do
    local r = Row(menu, y, L[sw.label], function() Toggle(sw) UpdateMenu() end, true)
    r.sw = sw
    menu.switchRows[#menu.switchRows + 1] = r
    y = y + 24
  end
  local line2 = menu:CreateTexture(nil, "ARTWORK")
  line2:SetColorTexture(0.86, 0.71, 0.42, 0.35)
  line2:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, -y - 3)
  line2:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -12, -y - 3)
  line2:SetHeight(1)
  y = y + 8
  Row(menu, y, L["All options"], function() HideMenu() if ns.OpenOptions then ns.OpenOptions() end end)
  y = y + 26
  menu:SetHeight(y + 8)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "QuestdonMinimapMenu") end
  menu:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
end

local function ShowMenu()
  if not menu then CreateMenu() end
  UpdateMenu()
  menu:ClearAllPoints()
  -- open towards the middle of the screen
  local _, by = button:GetCenter()
  local _, sy = UIParent:GetCenter()
  if (ns.Num(by) or 0) > (ns.Num(sy) or 0) then
    menu:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 4, 4)
  else
    menu:SetPoint("BOTTOMRIGHT", button, "TOPLEFT", 4, -4)
  end
  catcher:Show()
  menu:Show()
end
ns.ShowMinimapMenu = ShowMenu -- (tests)
function ns.MinimapMenuShown() return menu ~= nil and menu:IsShown() end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
local function Create()
  if button or not Minimap then return end
  button = CreateFrame("Button", "QuestdonMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  local lvl = ns.Num(ns.Value(Minimap.GetFrameLevel, Minimap))
  if lvl and button.SetFrameLevel then button:SetFrameLevel(lvl + 8) end
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(22, 22)
  bg:SetPoint("CENTER", button, "CENTER", 0, 0)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", button, "CENTER", 0, 0)
  icon:SetTexture(ICON)
  if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  if button.CreateMaskTexture then
    local ok, mask = pcall(button.CreateMaskTexture, button)
    if ok and mask then
      pcall(mask.SetTexture, mask, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(icon)
      if icon.AddMaskTexture then pcall(icon.AddMaskTexture, icon, mask) end
    end
  end
  -- the gold ring of the quest book
  local ring = button:CreateTexture(nil, "OVERLAY")
  ring:SetSize(30, 30)
  ring:SetPoint("CENTER", button, "CENTER", 0, 0)
  if ring:SetTexture(MEDIA .. "BookRing") == false then
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(54, 54)
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  end
  local hl = button:CreateTexture(nil, "HIGHLIGHT")
  hl:SetSize(24, 24)
  hl:SetPoint("CENTER", button, "CENTER", 0, 0)
  hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  if hl.SetBlendMode then hl:SetBlendMode("ADD") end
  button.icon = icon

  button:SetScript("OnClick", function(_, which)
    Style.HideTooltip(button)
    if which == "RightButton" then
      if menu and menu:IsShown() then HideMenu() else ShowMenu() end
    else
      HideMenu()
      if ns.ToggleQuestBook then ns.ToggleQuestBook() end
    end
  end)
  button:SetScript("OnEnter", function(self)
    if menu and menu:IsShown() then return end
    Style.Tooltip(self, Style.Wordmark("Quest", "don"), InfoLines(),
      L["Left click: quest book. Right click: menu. Drag: move."], "ANCHOR_LEFT")
  end)
  button:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  -- dragging: the button follows the cursor around the minimap
  button:SetScript("OnDragStart", function(self)
    Style.HideTooltip(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = ns.Num(ns.Value(Minimap.GetEffectiveScale, Minimap)) or 1
      if not (mx and cx) then return end
      local a = math.deg(math.atan2 and math.atan2(cy / scale - my, cx / scale - mx) or math.atan(cy / scale - my, cx / scale - mx))
      ns.db.minimapButtonAngle = math.floor((a % 360) + 0.5)
      Place()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  Place()
end

function ns.RefreshMinimapButton()
  if not Enabled() then
    if button then button:Hide() end
    HideMenu()
    return
  end
  if not button then Create() end
  if button then Place() button:Show() end
end
function ns.MinimapButton() return button end -- (tests)

ns.OnInit(function() ns.SafeCall("minimap button", ns.RefreshMinimapButton) end)
