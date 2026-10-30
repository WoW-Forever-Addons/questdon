local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (30.10.2026, Daniel 27.10.: "auf der Karte angezeigt bekommen, wo ein Gasthaus ist, wo ein Auktionshaus und wo ein
-- Flugmeister mit dem entsprechenden Symbol, optional ausschaltbar", then "Bank wäre noch gut") Inns, auction houses,
-- flight masters and banks on the world map, with the game's own minimap tracking symbols.
-- Data: ns.SERVICES (Data/Services.lua, DataEra/Services.lua; tools/open/build_services.py):
--   [uiMapID] = { { kind, x, y, side }, ... }   kind i, a, f, b; x, y in percent; side A, H or N.
-- Shown: your faction's and neutral ones. One option for all four, servicePins (Daniel 30.10.: one switch, not one per
-- kind, so the options stay few). Mouse over: what it is; click: the arrow leads you there.
-- An own map data provider with its own pin template (ServicePins.xml), so the quest pins stay as they are. Pins
-- cannot be made in combat (the map canvas calls SetPassThroughButtons): in combat the pins drawn stay.
---------------------------------------------------------------------------
local TEMPLATE = "QuestdonServicePinTemplate"
local SIZE = 16
local CARD_COLOR = { 0.85, 0.74, 0.52 } -- the stripe of the hover card: warm grey, not a quest colour
local SPREAD = 0.012 -- two symbols on one spot (Undercity's bank inside the auction house) side by side
local KINDS = {
  i = { icon = "Interface\\Minimap\\Tracking\\Innkeeper", name = "Inn", global = "MINIMAP_TRACKING_INNKEEPER" },
  a = { icon = "Interface\\Minimap\\Tracking\\Auctioneer", name = "Auction House", global = "MINIMAP_TRACKING_AUCTIONEER" },
  f = { icon = "Interface\\Minimap\\Tracking\\FlightMaster", name = "Flight Master", global = "MINIMAP_TRACKING_FLIGHTMASTER" },
  b = { icon = "Interface\\Minimap\\Tracking\\Banker", name = "Bank", global = "MINIMAP_TRACKING_BANKER" },
}
ns.SERVICE_KINDS = KINDS -- (tests)

-- The name of a kind: ours (translated), the game's tracking name where we have none.
function ns.ServiceName(kind)
  local k = KINDS[kind]
  if not k then return "?" end
  if L[k.name] ~= k.name or GetLocale() == "enUS" then return L[k.name] end
  local g = rawget(_G, k.global)
  return type(g) == "string" and g ~= "" and g or k.name
end

local function MySide()
  local f = ns.Value(UnitFactionGroup, "player")
  if f == "Alliance" then return "A" elseif f == "Horde" then return "H" end
end

-- The symbols of a map: { { kind = "service", service = "i", x = 0-1, y = 0-1 }, ... }
function ns.ServicePins(mapID)
  local out = {}
  local db = ns.db
  if not (mapID and db and db.servicePins ~= false and type(ns.SERVICES) == "table") then return out end
  local side = MySide()
  for _, p in ipairs(ns.SERVICES[mapID] or {}) do
    local k = KINDS[p[1]]
    if k and (p[4] == "N" or not side or p[4] == side) then
      out[#out + 1] = { kind = "service", service = p[1], x = p[2] / 100, y = p[3] / 100, side = p[4] }
    end
  end
  for i = 1, #out do
    for j = i + 1, #out do
      local a, b = out[i], out[j]
      if math.abs(a.x - b.x) < SPREAD and math.abs(a.y - b.y) < SPREAD then
        local mid = (a.x + b.x) / 2
        a.x, b.x = mid - SPREAD / 2, mid + SPREAD / 2
      end
    end
  end
  return out
end

-- title (the kind's symbol and name), lines, hint
function ns.ServicePinTooltip(pin)
  local lines = {}
  if pin and pin.side == "N" then lines[1] = L["Open to both factions"] end
  local k = pin and KINDS[pin.service]
  return (k and ("|T" .. k.icon .. ":16:16|t ") or "") .. ns.ServiceName(pin and pin.service), lines, L["Click: arrow"]
end

local provider, setupFailed
local stats = { builds = 0, pins = 0, keptInCombat = 0 }
function ns.ServicePinStats() return stats end

local function Setup()
  if provider or setupFailed then return end
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end

  QuestdonServicePinMixin = CreateFromMixins(MapCanvasPinMixin)
  local Pin = QuestdonServicePinMixin
  function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    if self.SetScalingLimits then self:SetScalingLimits(1, 1, 1.4) end
    self:SetSize(SIZE, SIZE)
  end
  function Pin:ApplyCurrentScale()
    if not self.SetScale then return end
    self:SetScale(1)
    if MapCanvasPinMixin.ApplyCurrentScale then MapCanvasPinMixin.ApplyCurrentScale(self) end
    local s = self.GetScale and self:GetScale() or 1
    self:SetScale((tonumber(s) or 1) * (ns.MapPinMult and ns.MapPinMult() or 1))
  end
  function Pin:OnAcquired(pin)
    self.qdPin = pin
    self:SetPosition(pin.x, pin.y)
    local k = KINDS[pin.service]
    if self.Icon and k then self.Icon:SetTexture(k.icon) end
  end
  function Pin:OnMouseClickAction(button)
    if button == "LeftButton" and self.qdPin and ns.PointArrowFromPin then
      ns.PointArrowFromPin(ns.Num(self:GetMap():GetMapID()), self.qdPin.x, self.qdPin.y, ns.ServiceName(self.qdPin.service), "service")
    end
  end
  Pin.OnClick = ns.Guard("map click", function(self, button) self:OnMouseClickAction(button) end)
  -- right-click zooms the map out, as on quest pins
  function Pin:ShouldMouseButtonBePassthrough(button) return button == "RightButton" end
  Pin.OnMouseEnter = ns.Guard("map tooltip", function(self)
    if not self.qdPin then return end
    local title, lines, hint = ns.ServicePinTooltip(self.qdPin)
    ns.PinCard(self, title, lines, hint, "service", CARD_COLOR)
  end)
  function Pin:OnMouseLeave() ns.PinCardHide(self) end

  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  p.qdService = true -- (tests: the harness keeps the quest provider apart)
  local builtMap
  p.RemoveAllData = ns.Guard("map", function(self)
    builtMap = nil
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
  end)
  p.RefreshAllData = ns.Guard("map", function(self)
    local map = self:GetMap()
    local mapID = ns.Num(map:GetMapID())
    if InCombatLockdown() then
      if mapID and mapID == builtMap then stats.keptInCombat = stats.keptInCombat + 1 return end
      self:RemoveAllData()
      return
    end
    self:RemoveAllData()
    if not mapID then return end
    for _, pin in ipairs(ns.ServicePins(mapID)) do map:AcquirePin(TEMPLATE, pin) end
    builtMap = mapID
    stats.builds = stats.builds + 1
  end)
  local ok = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, p)
  if ok then provider = p else setupFailed = true end
end
ns.SetupServicePins = Setup -- (tests)

-- Options: draw anew
function ns.RefreshServicePins()
  if not provider then Setup() end
  if provider and provider:GetMap() and WorldMapFrame:IsShown() and not InCombatLockdown() then provider:RefreshAllData() end
end

ns.OnInit(function()
  Setup()
  -- the world map may load later (Blizzard_WorldMap)
  ns.On("ADDON_LOADED", function() if not provider then Setup() end end)
end)
