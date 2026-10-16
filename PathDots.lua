local _, ns = ...

---------------------------------------------------------------------------
-- (1.3.6, Daniel 11.10.: "a dotted line on the map and minimap for the way") Where the arrow leads around a
-- mountain or first to the way into a cave (Paths.lua), small dots show that way on the minimap and on the
-- world map. Straight ahead: no dots. One arrow stays: it points at the next point of the way.
--
-- Own frames only: a container on the minimap (like the minimap pins), and an own data provider with an own
-- pin template on the world map. The minimap and the map are only read.
-- Cost: nothing while there is no way; with a way the dots are placed 10 times a second on the minimap when you
-- moved or turned, the world map's dots are made again at most once a second when the way changed.
---------------------------------------------------------------------------
local SPACING = 14        -- yards between two dots
local MAX_DOTS = 60       -- on the minimap (the rest of the way is outside the view anyway)
local MAX_MAP_DOTS = 120  -- on the world map
-- (11.10., Daniel's screenshot: "the dots on the minimap are hard to see" on snow) a gold dot in a dark ring:
-- it stands out on snow, grass and sand alike
local DOT_PX, RING_PX = 5, 8
local MIN_GAP_PX = 11    -- on the minimap at least this far apart (zoomed out: every second or third dot)
local UPDATE_INTERVAL = 0.1
local COLOR = { 1, 0.82, 0.1, 1 }
local RING = { 0.05, 0.05, 0.05, 0.85 }
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a plain white disc

local function Enabled() return ns.db and ns.db.pathDots ~= false and ns.db.arrowPaths ~= false end

-- The dots along the way: { mapID, n = count, x = {}, y = {} } in zone map coordinates, every SPACING yards,
-- starting one step ahead of you. Remade only when the way changed (its points moved).
local dots = { x = {}, y = {}, n = 0 }
local sig
local function Dots()
  local w = ns.ArrowWay and ns.ArrowWay()
  -- (Questdon review 4) nothing leads (list closed, arrow off): no way dots left behind
  if ns.ArrowRuns and not ns.ArrowRuns() then w = nil end
  if not (Enabled() and w and w.t and w.wp and ns.PathLine) then dots.n = 0 sig = nil return nil end
  local line = ns.PathLine(w.t, w.wp, w.cave)
  if not line or #line.pts < 2 then dots.n = 0 sig = nil return nil end
  local m, pts = line.mapID, line.pts
  -- the same way as before (you only moved a little along it): keep the dots
  local s = m .. ":" .. #pts
  for k = 2, #pts do s = s .. (":%.3f,%.3f"):format(pts[k][1], pts[k][2]) end
  local px, py = pts[1][1], pts[1][2]
  if s == sig and dots.n > 0 and dots.px and (px - dots.px) ^ 2 + (py - dots.py) ^ 2 < 1e-6 then return dots end
  sig, dots.px, dots.py, dots.mapID = s, px, py, m
  local n = 0
  local carry = SPACING  -- the first dot one step ahead of you
  for k = 1, #pts - 1 do
    local ax, ay, bx, by = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
    local ac, an, aw = ns.WorldPos(m, ax, ay)
    local bc, bn, bw = ns.WorldPos(m, bx, by)
    if ac and bc and ac == bc then
      local len = math.sqrt((bn - an) ^ 2 + (bw - aw) ^ 2)
      local d = carry
      while d <= len and n < MAX_MAP_DOTS do
        n = n + 1
        local f = d / len
        dots.x[n], dots.y[n] = ax + (bx - ax) * f, ay + (by - ay) * f
        d = d + SPACING
      end
      carry = d - len
    end
  end
  dots.n = n
  return dots
end
ns.PathDots = Dots -- (tests)

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local container
local tex = {}
local shown = 0
local function HideFrom(k)
  for i = k, shown do if tex[i] then tex[i].ring:Hide() tex[i].dot:Hide() end end
  shown = math.min(shown, k - 1)
end
local function Texture(i)
  local t = tex[i]
  if not t then
    local ring = container:CreateTexture(nil, "ARTWORK")
    ring:SetTexture(ROUND)
    ring:SetSize(RING_PX, RING_PX)
    ring:SetVertexColor(RING[1], RING[2], RING[3], RING[4])
    local dot = container:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(ROUND)
    dot:SetSize(DOT_PX, DOT_PX)
    dot:SetVertexColor(COLOR[1], COLOR[2], COLOR[3], COLOR[4])
    t = { ring = ring, dot = dot }
    tex[i] = t
  end
  return t
end
local SetupMinimap
local function UpdateMinimap()
  if not container then SetupMinimap() end
  if not container then return end
  local d = Dots()
  if not d or d.n == 0 or not (Minimap and ns.MinimapRadius) then HideFrom(1) return end
  local m, px, py = ns.PlayerPosition()
  if m ~= d.mapID or not px then HideFrom(1) return end
  local pc, pn, pw = ns.WorldPos(m, px, py)
  local radius = ns.MinimapRadius()
  local size = ns.Num(ns.Value(Minimap.GetWidth, Minimap))
  if not (pc and radius and size and size > 0) then HideFrom(1) return end
  local facing
  if ns.MinimapRotating and ns.MinimapRotating() then
    facing = ns.Num(ns.Value(GetPlayerFacing))
    if not facing then HideFrom(1) return end
  end
  local half = size / 2
  local n = 0
  local stride = math.max(1, math.ceil(MIN_GAP_PX / (SPACING * half / radius)))
  for i = stride, d.n, stride do
    local c, dn, dw = ns.WorldPos(m, d.x[i], d.y[i])
    if c == pc then
      local x, y = ns.MinimapOffset(dn - pn, -(dw - pw), radius, half, facing)
      if ns.OnMinimap(x, y, half, 3) then
        n = n + 1
        local t = Texture(n)
        t.ring:ClearAllPoints()
        t.ring:SetPoint("CENTER", container, "CENTER", x, y)
        t.dot:ClearAllPoints()
        t.dot:SetPoint("CENTER", container, "CENTER", x, y)
        t.ring:Show()
        t.dot:Show()
        if n >= MAX_DOTS then break end
      end
    end
  end
  if n > shown then shown = n end
  HideFrom(n + 1)
  shown = n
end
ns.PathDotsMinimapShown = function() return shown end -- (tests)

function SetupMinimap()
  if container or not Minimap then return end
  container = CreateFrame("Frame", "QuestdonPathDots", Minimap)
  container:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
  container:SetSize(1, 1)
  local level = ns.Num(ns.Value(Minimap.GetFrameLevel, Minimap))
  if level then container:SetFrameLevel(level + 4) end -- under the quest pins
  local elapsed = 0
  container:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0
    ns.SafeCall("path dots", UpdateMinimap)
  end)
end
ns.PathDotsUpdate = function() ns.SafeCall("path dots", UpdateMinimap) end -- (tests)

---------------------------------------------------------------------------
-- World map: an own data provider, dots of our own template, no mouse (clicks go through to the map)
---------------------------------------------------------------------------
local TEMPLATE = "QuestdonPathDotPinTemplate"
local provider, mapSig, setupFailed
local function SetupMap()
  if provider or setupFailed then return end
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end
  QuestdonPathDotPinMixin = CreateFromMixins(MapCanvasPinMixin)
  local Pin = QuestdonPathDotPinMixin
  function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    if self.SetScalingLimits then self:SetScalingLimits(1, 0.8, 1.2) end
    if self.EnableMouse then self:EnableMouse(false) end
  end
  function Pin:OnAcquired(x, y)
    self:SetSize(RING_PX, RING_PX)
    self:SetPosition(x, y)
    if self.Ring then self.Ring:SetVertexColor(RING[1], RING[2], RING[3], RING[4]) end
    if self.Dot then self.Dot:SetVertexColor(COLOR[1], COLOR[2], COLOR[3], COLOR[4]) end
  end
  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  p.RemoveAllData = ns.Guard("path dots map", function(self) self:GetMap():RemoveAllPinsByTemplate(TEMPLATE) end)
  p.RefreshAllData = ns.Guard("path dots map", function(self)
    if InCombatLockdown and InCombatLockdown() then
      -- pins cannot be made in combat (see MapPins.lua): another map's dots go, this map's stay
      local m = ns.Num(self:GetMap():GetMapID())
      if m ~= dots.mapID then self:RemoveAllData() mapSig = nil end
      return
    end
    self:RemoveAllData()
    mapSig = nil
    local d = Dots()
    local mapID = ns.Num(self:GetMap():GetMapID())
    if not (d and d.n > 0 and mapID) then return end
    -- the zone's map (a cave's own small map: none)
    if mapID ~= d.mapID then return end
    for i = 1, math.min(d.n, MAX_MAP_DOTS) do self:GetMap():AcquirePin(TEMPLATE, d.x[i], d.y[i]) end
    mapSig = sig
  end)
  local ok = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, p)
  if ok then provider = p else setupFailed = true end
end
-- once a second while the world map is open: the dots again when the way changed
local function TickMap()
  if not provider then SetupMap() end
  if not (provider and provider:GetMap() and WorldMapFrame:IsShown()) then return end
  Dots()
  if (sig or "") ~= (mapSig or "") then provider:RefreshAllData() end
end
ns.PathDotsMapState = function() return provider and "ready" or (setupFailed and "failed" or "waiting") end -- (/qd diag, tests)
ns.PathDotsTickMap = TickMap -- (tests)

ns.OnInit(function()
  SetupMinimap()
  ns.NewTicker(1, function() ns.SafeCall("path dots map", TickMap) end)
end)
