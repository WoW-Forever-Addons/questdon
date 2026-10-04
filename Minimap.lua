local _, ns = ...

---------------------------------------------------------------------------
-- (1.21) Minimap pins: the same pins as on the world map (available quests,
-- learned turn-ins, quest mobs and objectives, same options and the same
-- rules for Questie), for the map the player is on, drawn on the minimap.
-- Quest givers with several quests are one pin (ns.GroupQuestPins).
--
-- Own frames only: a container parented to the minimap, our own buttons on
-- it. The minimap is only read (size, zoom); nothing of it is changed.
--
-- Cost: the pin list is rebuilt at most once per second after quest events
-- (and at once on a new map), skipped when its signature did not change. The
-- positions are recalculated 10 times per second, only when the player moved
-- or turned or the zoom changed, with a few multiplications per pin.
--
-- (1.22) Review: every pin keeps its button while it stays in view (before,
-- buttons were handed out by position in the list, so one pin leaving the view
-- re-dressed all buttons after it and could swap the pin under the mouse);
-- after a hidden phase (no position, secret facing or size) the pins come back
-- even when the player did not move; the rotation setting is read with
-- C_CVar.GetCVarBool, a secret answer keeps the last readable one, else the
-- minimap's own compass ring tells; caves and buildings with their own small
-- map use the zone around them.
---------------------------------------------------------------------------
local UPDATE_INTERVAL = 0.1 -- seconds between position updates
local MAX_SHOWN = 60        -- pins shown at the same time (available quests first)
local QUEST_SIZE, DOT_SIZE = 14, 9

-- Minimap view in yards (diameter) per zoom level 0-5, used only when the
-- client has no C_Minimap.GetViewRadius.
local DIAMETER = {
  outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local container
local free = {}          -- buttons not in use
local entries = {}       -- { pin = displayPin, c, n, w (world position), btn = button while shown }
local curMap, lastSig
local last = {}          -- last position update: n, w, facing, radius, size
local dirty = false
local stats = { builds = 0, skipped = 0, updates = 0, shown = 0, radius = "?", rotate = "?", dressed = 0 }
local RotateText

local function Enabled()
  return ns.db and ns.db.minimapPins and Minimap ~= nil
end

---------------------------------------------------------------------------
-- Geometry (also used by the tests)
---------------------------------------------------------------------------
-- Radius of the minimap view in yards; second value: where it comes from.
function ns.MinimapRadius()
  if C_Minimap and C_Minimap.GetViewRadius then
    local r = ns.Num(ns.Value(C_Minimap.GetViewRadius))
    if r and r > 0 then return r, "client" end
  end
  local zoom = Minimap and ns.Num(ns.Value(Minimap.GetZoom, Minimap)) or 0
  zoom = math.max(0, math.min(5, math.floor(zoom)))
  local indoors = IsIndoors and ns.True(ns.Value(IsIndoors)) or false
  return DIAMETER[indoors and "indoor" or "outdoor"][zoom] / 2, "zoom"
end

-- (1.22) Does the minimap rotate? Second value: where the answer comes from
-- ("cvar", "cached" = last readable answer while the CVar is secret,
-- "compass" = the minimap's compass ring is shown, "unknown" = assume no).
local rotateCache
local function ReadRotateCVar()
  if C_CVar and C_CVar.GetCVarBool then
    local v = ns.Value(C_CVar.GetCVarBool, "rotateMinimap")
    if type(v) == "boolean" then return v end
  end
  local v = ns.Value((C_CVar and C_CVar.GetCVar) or GetCVar, "rotateMinimap")
  if v == nil then return nil end
  return v == "1" or v == 1 or v == true
end
local function Rotating()
  local v = ReadRotateCVar()
  if v ~= nil then rotateCache = v return v, "cvar" end
  if rotateCache ~= nil then return rotateCache, "cached" end
  local compass = MinimapCompassTexture
  if type(compass) == "table" and compass.IsShown then
    local ok, shown = pcall(compass.IsShown, compass)
    if ok and type(shown) == "boolean" and ns.Usable(shown) then return shown, "compass" end
  end
  return false, "unknown"
end
ns.MinimapRotating = Rotating

-- (1.22) Caves, mines and buildings can have their own small map (micro map)
-- without any pins: use the zone around them. Static per map, cached.
local zoneOf = {}
local MICRO, DUNGEON, ZONE = 5, 4, 3
function ns.MinimapZoneMap(mapID)
  if not mapID then return nil end
  local z = zoneOf[mapID]
  if z ~= nil then return z or mapID end
  z = false
  local info = C_Map and ns.Value(C_Map.GetMapInfo, mapID)
  local t = type(info) == "table" and ns.Num(info.mapType)
  local types = Enum and Enum.UIMapType
  local micro = types and ns.Num(types.Micro) or MICRO
  local dungeon = types and ns.Num(types.Dungeon) or DUNGEON
  local zone = types and ns.Num(types.Zone) or ZONE
  if t and (t == micro or t == dungeon) then
    local parent = ns.Num(info.parentMapID)
    local pinfo = parent and parent > 0 and ns.Value(C_Map.GetMapInfo, parent)
    if type(pinfo) == "table" and ns.Num(pinfo.mapType) == zone then z = parent end
  end
  zoneOf[mapID] = z
  return z or mapID
end

-- Player position on the zone map (caves and buildings: the zone around them).
local function PlayerOnZone()
  local mapID, px, py = ns.PlayerPosition()
  if not mapID then return nil end
  local zone = ns.MinimapZoneMap(mapID)
  if zone ~= mapID then
    local pos = ns.Value(C_Map.GetPlayerMapPosition, zone, "player")
    if type(pos) ~= "table" or not pos.GetXY then return mapID, px, py end
    local ok, x, y = pcall(pos.GetXY, pos)
    if ok and ns.Num(x) and ns.Num(y) and not (x == 0 and y == 0) then return zone, x, y end
    return mapID, px, py
  end
  return mapID, px, py
end

-- Offset in pixels from the minimap centre for a target (dNorth, dEast in
-- yards from the player): x to the right, y up. facing: radians counter-
-- clockwise from north (only when the minimap rotates, else nil).
function ns.MinimapOffset(dNorth, dEast, radius, halfSize, facing)
  local x, y = dEast, dNorth
  if facing then
    local c, s = math.cos(facing), math.sin(facing)
    x, y = dEast * c + dNorth * s, -dEast * s + dNorth * c
  end
  local k = halfSize / radius
  return x * k, y * k
end

-- Inside the visible minimap? Round unless an addon says the minimap is square.
-- (1.23) shape: optional, read once per update by the caller.
local function MinimapShape()
  return type(GetMinimapShape) == "function" and ns.Value(GetMinimapShape) or "ROUND"
end
function ns.OnMinimap(x, y, halfSize, margin, shape)
  local r = halfSize - (margin or 0)
  if (shape or MinimapShape()) == "SQUARE" then return math.abs(x) <= r and math.abs(y) <= r end
  return x * x + y * y <= r * r
end

---------------------------------------------------------------------------
-- Pin frames (our own buttons)
---------------------------------------------------------------------------
local function PinTooltip(self)
  local pin = self.pin
  if not pin then return end
  local title, lines, hint
  if pin.group then title, lines, hint = ns.QuestGroupTooltip(pin)
  elseif pin.kind == "objective" then title, lines, hint = ns.ObjectivePinTooltip(pin)
  else title, lines, hint = ns.QuestPinTooltip(pin) end
  ns.Style.Tooltip(self, title, lines, hint, "auto")
end

local function PinClick(self, button)
  local pin = self.pin
  if button ~= "LeftButton" or not pin or not curMap or not ns.SetArrowTarget then return end
  local label = pin.group and ns.QuestGroupTitle(pin) or ns.QuestTitle(pin.questID)
  ns.SetArrowTarget(curMap, pin.x, pin.y, label)
end

local function SetQuestIcon(tex, kind)
  local atlas = kind == "turnin" and "QuestTurnin" or "QuestNormal"
  local ok, res = false, nil
  if tex.SetAtlas then ok, res = pcall(tex.SetAtlas, tex, atlas, false) end
  if not ok or res == false then
    tex:SetTexture(kind == "turnin" and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\AvailableQuestIcon")
  end
  tex:SetVertexColor(1, 1, 1)
end

local function NewPin()
  local b = CreateFrame("Button", nil, container)
  b:SetSize(QUEST_SIZE, QUEST_SIZE)
  b.icon = b:CreateTexture(nil, "OVERLAY")
  b.icon:SetAllPoints(b)
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnEnter", ns.Guard("minimap tooltip", PinTooltip))
  b:SetScript("OnLeave", function(self) ns.Style.HideTooltip(self) end)
  b:SetScript("OnClick", ns.Guard("minimap click", PinClick))
  return b
end

local function Take()
  local b = table.remove(free)
  return b or NewPin()
end

local function Give(e)
  local b = e.btn
  if not b then return end
  b:Hide()
  b.pin = nil
  e.btn = nil
  free[#free + 1] = b
end

local function Look(b, pin)
  b.pin = pin
  stats.dressed = stats.dressed + 1
  if pin.kind == "objective" then
    b:SetSize(DOT_SIZE, DOT_SIZE)
    b.icon:SetTexture("Interface\\COMMON\\Indicator-Yellow")
    b.icon:SetVertexColor(ns.QuestColor(pin.questID))
  else
    b:SetSize(QUEST_SIZE, QUEST_SIZE)
    SetQuestIcon(b.icon, pin.kind)
  end
  b:SetAlpha(pin.dimmed and 0.35 or 1)
  b.kind = pin.kind
end

-- Hide every pin. The next update draws them again even when the player did
-- not move (1.22: before, pins hidden for a moment, e.g. while the facing or
-- the minimap size was secret, stayed hidden until the player moved).
local function HideAll()
  for _, e in ipairs(entries) do Give(e) end
  stats.shown = 0
  dirty = true
end

---------------------------------------------------------------------------
-- Pin list for the player's map
---------------------------------------------------------------------------
local function Rebuild(force)
  if not Enabled() or not curMap then
    HideAll()
    entries, lastSig = {}, nil
    return
  end
  local pins = ns.PinsForMap(curMap)
  local sig = ns.PinsSignature(curMap, pins)
  if not force and lastSig and sig == lastSig then stats.skipped = stats.skipped + 1 return end
  lastSig = sig
  for _, e in ipairs(entries) do Give(e) end
  entries = {}
  -- available quests first (they are what you look for), then turn-ins, then dots
  local order = { available = 1, turnin = 2, objective = 3 }
  local display = ns.DisplayQuestPins(pins) -- (1.25) no second "!" where the game draws one
  table.sort(display, function(a, b)
    local oa, ob = order[a.kind] or 4, order[b.kind] or 4
    if oa ~= ob then return oa < ob end
    return (a.questID or 0) < (b.questID or 0)
  end)
  for _, pin in ipairs(display) do
    local c, n, w = ns.WorldPos(curMap, pin.x, pin.y)
    if c then entries[#entries + 1] = { pin = pin, c = c, n = n, w = w } end
  end
  stats.builds = stats.builds + 1
  dirty = true
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
local function Update()
  if not Enabled() then if stats.shown > 0 then HideAll() end return end
  local mapID, px, py = PlayerOnZone()
  if not mapID then if stats.shown > 0 then HideAll() end curMap = nil return end
  if mapID ~= curMap then curMap = mapID Rebuild(true) end
  local pc, pn, pw = ns.WorldPos(mapID, px, py)
  if not pc then if stats.shown > 0 then HideAll() end return end
  local radius, source = ns.MinimapRadius()
  stats.radius = source
  local size = ns.Num(ns.Value(Minimap.GetWidth, Minimap))
  if not size or size <= 0 or not radius then if stats.shown > 0 then HideAll() end return end
  local facing
  local rotating, rsource = Rotating()
  stats.rotating, stats.rotateSource = rotating, rsource
  if rotating then
    facing = ns.Num(ns.Value(GetPlayerFacing))
    if not facing then if stats.shown > 0 then HideAll() end return end -- cannot place them right
  end
  if not dirty and last.n == pn and last.w == pw and last.facing == facing and last.radius == radius and last.size == size then
    return
  end
  last.n, last.w, last.facing, last.radius, last.size = pn, pw, facing, radius, size
  dirty = false
  stats.updates = stats.updates + 1
  local half = size / 2
  local shape = MinimapShape()
  -- cheap cut before the rotation: farther than the view's corner (square minimap)
  local reach = radius * 1.5
  local reach2 = reach * reach
  local n = 0
  for _, e in ipairs(entries) do
    local x, y, inView
    if n < MAX_SHOWN and e.c == pc then
      local dn, de = e.n - pn, -(e.w - pw)
      if dn * dn + de * de <= reach2 then
        x, y = ns.MinimapOffset(dn, de, radius, half, facing)
        inView = ns.OnMinimap(x, y, half, 4, shape)
      end
    end
    if inView then
      n = n + 1
      local b = e.btn
      if not b then
        b = Take()
        e.btn = b
        Look(b, e.pin)
      end
      b:ClearAllPoints()
      b:SetPoint("CENTER", container, "CENTER", x, y)
      b:Show()
    elseif e.btn then
      Give(e)
    end
  end
  stats.shown = n
end

---------------------------------------------------------------------------
-- Setup and events
---------------------------------------------------------------------------
local function Setup()
  if container or not Minimap then return end
  container = CreateFrame("Frame", "QuestdonMinimapPins", Minimap)
  container:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
  container:SetSize(1, 1)
  local level = ns.Num(ns.Value(Minimap.GetFrameLevel, Minimap))
  if level then container:SetFrameLevel(level + 5) end
  -- (1.23) Throttled before the protected call: no closure or table per frame.
  local elapsed = 0
  container:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0
    ns.SafeCall("minimap", Update)
  end)
  -- option off: the container is hidden, so its OnUpdate does not run at all
  container:SetShown(Enabled())
end

-- force: options or commands changed something (rebuild at once).
function ns.RefreshMinimapPins(force)
  if not container then Setup() end
  if not container then return end
  if not Enabled() then HideAll() entries, lastSig = {}, nil container:Hide() return end
  container:Show()
  Rebuild(force)
  Update()
end

-- (1.23) Batched with the other quest displays (Core.lua, 0.5 s).
ns.RegisterRefresh("minimap", function() if Enabled() then Rebuild(false) end end)
local function Queue()
  if Enabled() then ns.QueueRefresh("minimap") end
end

-- "on (cvar)" / "off (unknown)" for /qd diag
function RotateText()
  if stats.rotateSource == nil then return "?" end
  return (stats.rotating and "on (" or "off (") .. tostring(stats.rotateSource) .. ")"
end
function ns.MinimapPinStats() stats.rotate = RotateText() return stats end
function ns.MinimapPinsState()
  if not Minimap then return "not available (no minimap)" end
  if not container then return "waiting" end
  if not ns.db.minimapPins then return "off" end
  return ("ready, %d shown of %d, radius %s, rotate %s, builds %d, skipped %d"):format(stats.shown, #entries,
    tostring(stats.radius), RotateText(), stats.builds, stats.skipped)
end
-- tests
ns.MinimapUpdate = Update
function ns.MinimapShownPins()
  local list = {}
  for _, e in ipairs(entries) do if e.btn then list[#list + 1] = e.btn end end
  return list
end

ns.OnInit(Setup)
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("QUEST_DATA_LOAD_RESULT", Queue)
ns.On("QUESTLINE_UPDATE", Queue)
ns.On("BAG_UPDATE_DELAYED", Queue)
ns.On("PLAYER_LEVEL_UP", Queue)
ns.On("ZONE_CHANGED_NEW_AREA", function() curMap = nil dirty = true end)
