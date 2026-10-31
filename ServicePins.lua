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
-- (30.10.2026, DonMap M3) Drawn by DonMap as the source "services" (own buttons on the map, each symbol only on its
-- own map, not on the continent): no map data provider and no pin template any more, so the symbols are drawn in
-- combat too. /donmap services switches them off as well.
---------------------------------------------------------------------------
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

local src
local stats = { builds = 0, pins = 0 }
function ns.ServicePinStats() return stats end

-- every symbol of every map for DonMap, each shown only on its own map (point.only); in map order, so the same data
-- gives the same list
function ns.ServicePoints()
  local out = {}
  if not (ns.db and ns.db.servicePins ~= false and type(ns.SERVICES) == "table") then return out end
  local maps = {}
  for mapID in pairs(ns.SERVICES) do if type(mapID) == "number" then maps[#maps + 1] = mapID end end
  table.sort(maps)
  for _, mapID in ipairs(maps) do
    for i, p in ipairs(ns.ServicePins(mapID)) do
      p.mapID, p.only, p.key, p.icon = mapID, true, ("%d:%02d"):format(mapID, i), KINDS[p.service].icon
      out[#out + 1] = p
    end
  end
  return out
end

-- the symbol's button (DonMap places it): click points the arrow there, right-click zooms the map out as before
local function NewPin(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetAllPoints(b)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnEnter", ns.Guard("map tooltip", function(self)
    if not self.qdPin then return end
    local title, lines, hint = ns.ServicePinTooltip(self.qdPin)
    ns.PinCard(self, title, lines, hint, "service", CARD_COLOR)
  end))
  b:SetScript("OnLeave", function(self) ns.PinCardHide(self) end)
  b:SetScript("OnClick", ns.Guard("map click", function(self, button)
    local pin = self.qdPin
    if not pin then return end
    if button == "LeftButton" and ns.PointArrowFromPin then
      ns.PointArrowFromPin(pin.mapID, pin.x, pin.y, ns.ServiceName(pin.service), "service")
    elseif button == "RightButton" and WorldMapFrame and WorldMapFrame.NavigateToParentMap then
      WorldMapFrame:NavigateToParentMap()
    end
  end))
  return b
end

local function Paint(b, points, size)
  local pin = points[1]
  b.qdPin = pin
  b:SetSize(size, size)
  local k = KINDS[pin.service]
  if k then b.Icon:SetTexture(k.icon) end
end

local function Setup()
  if src or not (DonMapAPI and DonMapAPI.version and DonMapAPI.version >= 3) then return end
  src = DonMapAPI.Register("services", {
    title = "Questdon: " .. L["Inns, auction houses, flight masters and banks on the map"], layer = 0, minimap = false,
    world = function() return ns.db and ns.db.servicePins ~= false end,
    size = function() return SIZE * (ns.MapPinMult and ns.MapPinMult() or 1) end,
    newPin = NewPin, paint = Paint,
  })
  ns.RefreshServicePins()
end
ns.SetupServicePins = Setup -- (tests)
ns.ServiceSource = function() return src end -- (tests, /qd diag)

-- Options: the symbols anew (DonMap draws them when the map is open)
function ns.RefreshServicePins()
  if not src then return Setup() end
  local list = ns.ServicePoints()
  src:SetPoints(list)
  stats.builds, stats.pins = stats.builds + 1, #list
  src:Refresh("world")
end

ns.OnInit(Setup)
-- the faction may not be readable yet when Questdon loads: the list again once the world is there
ns.On("PLAYER_ENTERING_WORLD", function() if src then ns.RefreshServicePins() end end)
