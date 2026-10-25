local _, ns = ...
local L = ns.L

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
local MAX_SHOWN = 150       -- pins shown at the same time (available quests first; 1.2: was 60, more spawn dots; 1.3.5: 150, all spawns near you)
-- (1.3.5, Daniel 05.10.: "only 2 dots in a field") The quest mob dots are the minimap's own:
-- every spawn point within NEAR_REACH times the view radius (ns.ObjectivePointsNear), not the
-- zone-wide 80 of the world map. The list is made again when the player has moved REBUILD_MOVE
-- times the radius from where it was made, or the view got larger.
local NEAR_REACH, REBUILD_MOVE = 1.5, 0.4
local QUEST_SIZE, DOT_SIZE = 14, 9
-- (1.3.5, Daniel 10.10., Fargodeep Mine: "bundle dots that lie almost on top of each other into one dot, but do
-- not let that dot get too big") Objective dots closer on screen than BUNDLE_PX (about 0.8 of a dot) are one dot
-- at their middle, a little larger (BundleScale by count, at most 1.3), no number. On the minimap the
-- distances between pins only depend on the scale (pixels per yard), not on where you stand or look, so the
-- bundles are made when the pins are made or the zoom changes, in world yards on a grid (cell = threshold),
-- never per frame. Quest givers, turn-ins and entrances are never bundled.
local BUNDLE_PX = 0.8 * DOT_SIZE
ns.MinimapBundleScale = function(n) return ns.BundleScale(n) end -- (tests; the sizes are in MapPins.lua)
-- (1.3.5, Daniel 10.10., a quest field: about 40 dots on the minimap) At most MINIMAP_BUDGET objective markers
-- in view: above it the bundling distance grows (ns.ThinObjectivePoints). The nearest spot of each objective
-- (the ANCHORS nearest objectives) stays a single dot, and near you dots join less willingly than far ones
-- (half the distance next to you, the full one at the edge of the view), so far spots are bundled first.
local MINIMAP_BUDGET, ANCHORS = 16, 8
ns.MINIMAP_OBJECTIVE_BUDGET = MINIMAP_BUDGET
-- (1.3.4) Daniel 08.10., Zephras Isle: on the minimap a Questdon "!" stood on
-- top of the game's own "!". The game puts a blip on every quest giver near
-- you that offers you a quest (or takes a finished one), and that blip is not
-- in its quest lines, so the 1.25 rule (SkipGameShownPins) did not see it.
-- With "skipGameGivers" on, the minimap leaves givers to the game: no Questdon
-- "!" or "?" there (1.3.7: in the whole view, the game marks them up to the
-- minimap's edge). Dots of quest mobs stay.
-- (1.3.5) dungeon entrances: on the minimap only within this many yards (the mark always)
local DUNGEON2 = (ns.DUNGEON_PIN_MINIMAP_YARDS or 300) ^ 2

-- Minimap view in yards (diameter) per zoom level 0-5, used only when the
-- client has no C_Minimap.GetViewRadius.
local DIAMETER = {
  outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}

local container
local nearAt             -- (1.3.5) where and for which radius the dots were made: { c, n, w, r }
local free = {}          -- buttons not in use
local entryPool = {}
local entries = {}       -- { pin = displayPin, c, n, w (world position), btn = button while shown }
local curMap, lastSig
local last = {}          -- last position update: n, w, facing, radius, size
local dirty = false
local stats = { builds = 0, skipped = 0, updates = 0, shown = 0, radius = "?", rotate = "?", dressed = 0, nearGame = 0 }
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
local hoverQuests, HoverDots -- (1.3.8, F8) set further down
local function PinTooltip(self)
  local pin = self.pin
  if not pin then return end
  local title, lines, hint
  if self.members and #self.members > 1 then title, lines, hint = ns.ObjectiveBundleTooltip(self.members) -- (1.3.5) a bundle
  elseif pin.kind == "entrance" then title, lines, hint = ns.EntrancePinTooltip(pin) -- (1.3.5)
  elseif pin.kind == "dungeon" then title, lines, hint = ns.DungeonPinTooltip(pin)
  elseif pin.group then title, lines, hint = ns.QuestGroupTooltip(pin)
  elseif pin.kind == "objective" then title, lines, hint = ns.ObjectivePinTooltip(pin)
  else title, lines, hint = ns.QuestPinTooltip(pin) end
  -- (1.3.6) our own hover card (PinCard.lua)
  local first = self.members and #self.members > 1 and self.members[1] or nil
  if first then ns.PinCard(self, title, lines, hint, ns.PinCardKind(nil, first.questID))
  else ns.PinCard(self, title, lines, hint, ns.PinCardKind(pin.group and pin.group[1] or pin)) end
  if ns.SetHoverTooltip then ns.SetHoverTooltip(self, PinTooltip) end -- (1.3.4) Shift redraws it
  if self.kind == "objective" then HoverDots(self) end
end

local function PinClick(self, button)
  local pin = self.pin
  -- (1.3.5) a dungeon entrance: a click opens the dungeon journal, right-click marks it (or removes the mark)
  if pin and pin.kind == "dungeon" then
    if button == "RightButton" then ns.DungeonPinRightClick(pin.inst)
    elseif button == "LeftButton" then ns.OpenDungeonJournal(pin.inst) end
    return
  end
  -- (round 8) the mark: a click opens the dungeon journal (the arrow already points there), right-click removes it
  if pin and pin.kind == "entrance" then
    if button == "RightButton" then ns.RemoveEntranceMark("pin")
    elseif button == "LeftButton" then ns.OpenDungeonJournal(pin.inst) end
    return
  end
  -- (1.1) Alt-click: "no quest here" (NotHere.lua)
  if button == "LeftButton" and pin and ns.True(ns.Value(IsAltKeyDown)) and ns.ReportPin then
    if (pin.kind ~= "turnin" or pin.group) and pin.kind ~= "objective" and pin.kind ~= "focus" then ns.ReportPin(pin) end
    return
  end
  if button ~= "LeftButton" or not pin or not curMap then return end
  local label = pin.group and ns.QuestGroupTitle(pin) or ns.QuestTitle(pin.questID)
  ns.PointArrowFromPin(curMap, pin.x, pin.y, label, nil, pin) -- (1.2) also switches the arrow on
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
  -- (1.3) dark ring behind the objective dots: a green dot on green ground stays visible
  b.ring = b:CreateTexture(nil, "ARTWORK")
  b.ring:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.ringTex = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
  if b.ring:SetTexture(b.ringTex) == false then
    b.ringTex = "Interface\\COMMON\\Indicator-Gray"
    b.ring:SetTexture(b.ringTex)
  end
  b.ring:SetVertexColor(0, 0, 0, 0.85)
  b.ring:Hide()
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- (1.3.5) right-click removes an entrance mark
  b:SetScript("OnEnter", ns.Guard("minimap tooltip", PinTooltip))
  b:SetScript("OnLeave", function(self)
    ns.PinCardHide(self)
    if ns.SetHoverTooltip then ns.SetHoverTooltip(nil) end
    if hoverQuests then HoverDots(nil) end
  end)
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
  b.pin, b.members = nil, nil
  e.btn = nil
  free[#free + 1] = b
end

-- (1.3.8, F2) objects to click: a diamond in the quest colour with a dark edge, mobs keep the round dot
local SQUARE, QUARTER = "Interface\\Buttons\\WHITE8X8", math.pi / 4
local SYMBOLS = "Interface\\AddOns\\Questdon\\Media\\"
local function Turn(tex, angle) if tex and tex.SetRotation then pcall(tex.SetRotation, tex, angle) end end
local function Unturn(b)
  if not b.shape then return end
  b.shape = nil
  Turn(b.icon, 0) Turn(b.ring, 0)
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0, 1, 0, 1) end
  if b.ringTex then b.ring:SetTexture(b.ringTex) end
  b.ring:SetVertexColor(0, 0, 0, 0.85)
  if b.rim then b.rim:Hide() end
end

-- (20.10.) the quest's colour can change after a button was dressed (the log loads late, a quest is accepted):
-- look again at every update, a lookup per dot
local function Retint(b)
  local pin = b.pin
  if not (pin and b.kind == "objective") then return end
  local idx = ns.QuestColorIndex(pin.questID)
  if b.colorIdx == idx then return end
  b.colorIdx = idx
  local r, g, bl = ns.QuestColor(pin.questID)
  if b.shape == "symbol" then
    if b.rim then b.rim:SetVertexColor(r, g, bl) end
  elseif b.shape == "item" then b.ring:SetVertexColor(r, g, bl)
  else b.icon:SetVertexColor(r, g, bl) end
end
local function Look(b, pin, scale)
  b.pin = pin
  stats.dressed = stats.dressed + 1
  Unturn(b)
  -- (review 6) a reused button: the texture coordinates an atlas or an item icon set before go
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0, 1, 0, 1) end
  if pin.kind == "entrance" or pin.kind == "dungeon" then
    -- (1.3.5) the game's dungeon entrance icon; the mark a bit larger than a quest marker, the others smaller
    b.ring:Hide()
    local size = pin.kind == "entrance" and QUEST_SIZE + 20 or QUEST_SIZE + 8 -- (20.10., Daniel: far too small, the atlas icon has a wide empty edge) 34 and 22
    b:SetSize(size, size)
    local ok, res = false, nil
    if b.icon.SetAtlas then ok, res = pcall(b.icon.SetAtlas, b.icon, "Dungeon", false) end
    if not ok or res == false then b.icon:SetTexture("Interface\\Icons\\INV_Misc_Key_03") end
    b.icon:SetVertexColor(1, 1, 1)
  elseif pin.kind == "objective" then
    local d = pin.small and math.max(5, math.floor(DOT_SIZE * 0.75 + 0.5)) or DOT_SIZE -- (1.2) many spawns: smaller dots
    d = math.min(math.floor(d * (scale or 1) + 0.5), math.floor(d * 1.3)) -- (1.3.5) a bundle: a little larger, never above 1.3 times
    -- (1.3.8, F9) the place of use of a quest item: the item's icon in a frame of the quest's colour
    local whole = b.members and #b.members > 1 and { members = b.members } or pin -- a bundle: all its spots
    local item = ns.PinUseItem(whole)
    local icon = item and C_Item and ns.Value(C_Item.GetItemIconByID, item) or nil
    -- (17.10.) a single target's own symbol in a halo of the quest's colour
    local sym = not icon and ns.PinIconKind(whole)
    if sym then
      local s = math.floor(d * 1.7 + 0.5)
      b:SetSize(s, s)
      b.icon:SetTexture(SYMBOLS .. ns.PIN_ICONS[sym])
      -- (20.10.) the symbol's rim in the quest's colour, no halo behind it
      if not b.rim then
        b.rim = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.rim:SetAllPoints(b)
        b.rim:SetTexture(SYMBOLS .. "qd_rim")
      end
      b.rim:SetVertexColor(ns.QuestColor(pin.questID))
      b.rim:Show()
      b.ring:SetVertexColor(0, 0, 0, 0)
      b.shape = "symbol"
      icon = true
    elseif icon then
      local s = math.floor(d * 1.5 + 0.5)
      b:SetSize(s, s)
      b.icon:SetTexture(icon)
      if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
      b.ring:SetTexture(SQUARE)
      b.ring:SetVertexColor(ns.QuestColor(pin.questID))
      b.ring:SetSize(s + 3, s + 3)
      b.shape = "item"
    elseif ns.IsObjectPin(whole) then
      local s = math.max(4, math.floor(d * 0.75 + 0.5)) -- turned by 45 degrees it is as wide as the dot
      b:SetSize(s, s)
      b.icon:SetTexture(SQUARE)
      b.ring:SetTexture(SQUARE)
      Turn(b.icon, QUARTER) Turn(b.ring, QUARTER)
      b.shape = "diamond"
      b.ring:SetSize(s + 3, s + 3)
    else
      b:SetSize(d, d)
      b.icon:SetTexture("Interface\\COMMON\\Indicator-Yellow")
      b.ring:SetSize(d + 4, d + 4)
    end
    if icon then b.icon:SetVertexColor(1, 1, 1) else b.icon:SetVertexColor(ns.QuestColor(pin.questID)) end
    b.ring:Show()
    b.colorIdx = ns.QuestColorIndex(pin.questID)
  else
    b.ring:Hide()
    b:SetSize(QUEST_SIZE, QUEST_SIZE)
    SetQuestIcon(b.icon, pin.iconKind or pin.kind) -- (1.2) the picked quest of the zone list
  end
  b.baseAlpha = pin.dimmed and 0.35 or (pin.kind == "dungeon" and 0.8) or 1
  b.close = nil
  b:SetAlpha(b.baseAlpha)
  b.kind = pin.kind
end

-- (1.3.8, F8) A dot you stand on fades (the mob or the object is right there and the dot hid it and the player
-- arrow); while the mouse is on a quest's dot the other quests' dots step back.
local CLOSE_YARDS = 12
-- hoverQuests: { [questID] = true } of the dot under the mouse
local function QuestsOf(b)
  local set = {}
  if b.members and #b.members > 0 then
    for _, m in ipairs(b.members) do if m.questID then set[m.questID] = true end end
  elseif b.pin and b.pin.questID then set[b.pin.questID] = true end
  return set
end
local function Alpha(b)
  local a = b.baseAlpha or 1
  if b.kind == "objective" then
    if b.close then a = a * 0.35 end
    if hoverQuests and b.pin then
      local mine = hoverQuests[b.pin.questID]
      for _, m in ipairs(not mine and b.members or {}) do if hoverQuests[m.questID] then mine = true break end end
      if not mine then a = a * 0.3 end
    end
  end
  return a
end
function HoverDots(b)
  hoverQuests = b and b.kind == "objective" and QuestsOf(b) or nil
  for _, e in ipairs(entries) do if e.btn then e.btn:SetAlpha(Alpha(e.btn)) end end
end
ns.MinimapHoverDots = HoverDots -- (tests)
function ns.MinimapHoverQuests(set) -- (20.10.) from the quest list: { [questID] = true } or nil
  hoverQuests = set
  for _, e in ipairs(entries) do if e.btn then e.btn:SetAlpha(Alpha(e.btn)) end end
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
-- The pins of the minimap: the map's quest pins (ns.PinsForMapBase) and (1.3.5) the quest mob
-- dots near the player.
-- (17.10., /qd mem: the minimap 49 KB a second walking) after a move the quest givers and turn-ins of the last build
-- (they change with the log, the level and the events that rebuild the minimap anyway), only the dots near you anew
-- (18.10., /qd mem: the minimap 12 KB a second walking) 60 s instead of 10: every event that changes the givers
-- (log, level, learned data, options) rebuilds without "moved" and makes the base anew anyway
local BASE_SECS = 60
local baseMap, baseGen, baseLevel, baseAt, baseList
-- (24.10., Daniel's list: the minimap rebuilt its pins on every quest log event; bench "quest, map closed": refresh
-- minimap 88 KB/s, 10 of 16 builds ended with the same pins) a quest log event (kills, loot) that leaves the log's state
-- (quests, complete, finished objectives: ns.QuestLogState) as it was keeps the base pins for BASE_SECS like a move;
-- any other event that can change them (data loaded, quest lines, level, accept, turn-in, options) builds them anew
local baseH, baseN
local function ForgetBase() baseList = nil end
-- (25.10., review round 8: hiding a quest stayed on the minimap up to a minute) ns.ForgetAvailable lets the base go too
ns.ForgetMinimapBase = ForgetBase
local function MinimapPins(mapID, moved)
  local now = ns.Num(ns.Value(GetTime)) or 0
  local gen, level = ns.LogGen and ns.LogGen(), ns.PlayerLevel and ns.PlayerLevel()
  local base
  local h, n
  if not moved and ns.QuestLogState then h, n = ns.QuestLogState() end
  if baseList and baseMap == mapID and baseLevel == level and baseAt and now - baseAt <= BASE_SECS and now >= baseAt
      and ((moved and baseGen == gen) or (not moved and h ~= nil and h == baseH and n == baseN)) then
    base = baseList
    if not moved then stats.baseKept = (stats.baseKept or 0) + 1 end
  else
    base = ns.PinsForMapBase(mapID)
    if not moved and h == nil and ns.QuestLogState then h, n = ns.QuestLogState() end
    baseMap, baseGen, baseLevel, baseAt, baseList, baseH, baseN = mapID, gen, level, now, base, h, n
  end
  local was = nearAt
  nearAt = nil
  if not ns.db.objectivePins then return base, base end
  local _, px, py = PlayerOnZone()
  local pc, pn, pw
  if px then pc, pn, pw = ns.WorldPos(mapID, px, py) end
  local radius = ns.MinimapRadius()
  if not (pc and radius) then return base, base end
  -- (16.10. evening, /qd mem) a quest log update while walking: the dots around the place they were made for,
  -- as long as the player is still near it (Update makes them anew beyond REBUILD_MOVE). Before, every update
  -- took a slightly other set of dots, so the signature never matched and all minimap pins were made anew.
  if was and was.map == mapID and was.c == pc and radius <= was.r * 1.05 and radius >= was.r * 0.95
      and (pn - was.n) ^ 2 + (pw - was.w) ^ 2 <= (REBUILD_MOVE * was.r) ^ 2 then
    pn, pw, radius = was.n, was.w, was.r
  end
  local pins = {}
  for i, p in ipairs(base) do pins[i] = p end
  for _, o in ipairs(ns.ObjectivePointsNear(mapID, pc, pn, pw, radius * NEAR_REACH)) do
    o.kind = "objective"
    pins[#pins + 1] = o
  end
  nearAt = { c = pc, n = pn, w = pw, r = radius, map = mapID }
  return pins, base
end

-- (1.3.5) Bundles for k pixels per yard: e.head = the entry drawn for it (itself or another), the head
-- keeps its members (pins) and draws at their middle (e.dn, e.dw), e.scale its size. Round 7: with more
-- than MINIMAP_BUDGET markers in view (radius around where the dots were made) the dots are thinned.
local bundledFor, bundledK -- the entries list and the scale the bundles were made for
-- (18.10., /qd mem) the lists, the distance table and the two budget functions are kept (new ones each bundling
-- before); member lists come from a pool (the buttons give them up before every bundling, see Update)
local objs, dist, seenKey = {}, {}, {}
local membersPool, membersUsed = {}, 0
local bAt, bRadius, bN
local function InView(B, i)
  return B.g[i] == bAt.c and (B.mx[i] - bAt.n) ^ 2 + (B.my[i] - bAt.w) ^ 2 <= bRadius * bRadius
end
-- nearest first; the same distance: the list's own order (the same pins give the same list)
local function ByDist(a, b) local da, db = dist[a], dist[b] if da ~= db then return da < db end return a < b end
-- over the budget: nearest first, the nearest spot of each objective an anchor, near spots join less
local function Prepare(B)
  local at, radius, n = bAt, bRadius, bN
  for i = 1, n do
    local e = objs[i]
    dist[i] = e.c == at.c and math.sqrt((e.n - at.n) ^ 2 + (e.w - at.w) ^ 2) or math.huge
    B.f[i] = 0.5 + 0.5 * math.min(1, dist[i] / radius)
  end
  table.sort(B.order, ByDist)
  for k in pairs(seenKey) do seenKey[k] = nil end
  local anchors = 0
  for k2 = 1, n do
    local i = B.order[k2]
    if anchors >= ANCHORS or dist[i] > radius then break end
    local key = B.q[i] * 64 + (tonumber(objs[i].pin.index) or 0)
    if not seenKey[key] then seenKey[key] = true B.a[i] = true anchors = anchors + 1 end
  end
end
local function Members(first)
  membersUsed = membersUsed + 1
  local m = membersPool[membersUsed]
  if m then for i = #m, 2, -1 do m[i] = nil end m[1] = first
  else m = { first } membersPool[membersUsed] = m end
  return m
end
local function Bundle(k, radius)
  bundledFor, bundledK = entries, k
  membersUsed = 0
  local n = 0
  for _, e in ipairs(entries) do
    e.head, e.members, e.scale, e.dn, e.dw = e, nil, 1, e.n, e.w
    if e.pin.kind == "objective" then n = n + 1 objs[n] = e end
  end
  for i = #objs, n + 1, -1 do objs[i] = nil end
  local T = ns.ThinBuffer(n)
  for i = 1, n do local e = objs[i] T.x[i], T.y[i], T.q[i], T.g[i] = e.n, e.w, e.pin.questID or 0, e.c end
  local at = nearAt
  local budget = ns.db.thinObjectives ~= false and at and radius and MINIMAP_BUDGET or nil
  local inView, prepare
  if budget then
    bAt, bRadius, bN = at, radius, n
    inView, prepare = InView, Prepare
  end
  -- (17.10.) symbols are larger than dots: spots join from twice the distance
  local px = ns.SymbolsOn and ns.SymbolsOn() and BUNDLE_PX * 2 or BUNDLE_PX
  local level = ns.ThinObjectivePoints(px / k, budget, inView, prepare)
  local shown, heads = 0, 0
  for i = 1, n do
    local h = T.head[i]
    local e = objs[i]
    if h == i then
      heads = heads + 1
      e.dn, e.dw = T.mx[i], T.my[i]
      if T.cnt[i] > 1 then e.scale = ns.BundleScale(T.cnt[i]) end
      if not inView or inView(T, i) then shown = shown + 1 end
    else
      local he = objs[h]
      e.head = he
      local m = he.members
      if not m then m = Members(he.pin) he.members = m end
      m[#m + 1] = e.pin
    end
  end
  for i = 1, n do objs[i] = nil end -- no entry stays held here
  stats.bundled = n - heads
  stats.thinLevel, stats.objMarkers = level, shown
end
ns.MinimapEntries = function() return entries end -- (tests)

-- available quests first (they are what you look for), then turn-ins, then dots
local ORDER = { entrance = 0, focus = 0, dungeon = 1, available = 1, turnin = 2, objective = 3 }
local function ByKind(a, b)
  local oa, ob = ORDER[a.kind] or 4, ORDER[b.kind] or 4
  if oa ~= ob then return oa < ob end
  return (a.questID or 0) < (b.questID or 0)
end
-- (18.10., /qd mem) the givers' display (game givers left out, grouped, sorted) is kept per base list: after a
-- move only the dots are new. Dots never join a giver's marker (ns.GroupQuestPins passes them through).
local dispBase, dispSkip, dispList
local display, dots = {}, {}
local function Display(pins, base)
  local skip = ns.db.skipGameGivers and true or false
  if not (base and base == dispBase and skip == dispSkip and dispList) then
    dispList = ns.DisplayQuestPins(base or {}, ns.MINIMAP_OVERLAP) -- (1.25) no second "!" where the game draws one; (1.3.3) overlapping markers merge
    table.sort(dispList, ByKind)
    dispBase, dispSkip = base, skip
    stats.displays = (stats.displays or 0) + 1
  end
  local nd = 0
  for i = #(base or {}) + 1, #pins do nd = nd + 1 dots[nd] = pins[i] end
  for i = #dots, nd + 1, -1 do dots[i] = nil end
  table.sort(dots, ByKind)
  local n = 0
  for _, p in ipairs(dispList) do n = n + 1 display[n] = p end
  for i = 1, nd do n = n + 1 display[n] = dots[i] dots[i] = nil end
  for i = #display, n + 1, -1 do display[i] = nil end
  return display
end

local function Rebuild(force, moved)
  if force then ForgetBase() end
  if not Enabled() or not curMap then
    HideAll()
    entries, lastSig = {}, nil
    return
  end
  local pins, base = MinimapPins(curMap, moved)
  local sig = ns.PinsSignature(curMap, pins)
  if not force and lastSig and sig == lastSig then stats.skipped = stats.skipped + 1 return end
  lastSig = sig
  -- (17.10., /qd mem) the entry tables of the last build are used again (a new one per pin at each build before)
  for _, e in ipairs(entries) do
    Give(e)
    e.pin, e.head, e.members = nil, nil, nil
    entryPool[#entryPool + 1] = e
  end
  entries = {}
  for _, pin in ipairs(Display(pins, base)) do
    local c, n, w = ns.WorldPos(curMap, pin.x, pin.y)
    if c then
      local e = entryPool[#entryPool]
      if e then entryPool[#entryPool] = nil else e = {} end
      e.pin, e.c, e.n, e.w = pin, c, n, w
      entries[#entries + 1] = e
    end
  end
  for i = #display, 1, -1 do display[i] = nil end
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
  -- (1.3.5) moved on or zoomed out: the dots near you again
  if nearAt and (nearAt.c ~= pc or radius > nearAt.r * 1.05
      or (pn - nearAt.n) ^ 2 + (pw - nearAt.w) ^ 2 > (REBUILD_MOVE * nearAt.r) ^ 2) then
    stats.moved = (stats.moved or 0) + 1
    Rebuild(false, true)
  end
  if not dirty and last.n == pn and last.w == pw and last.facing == facing and last.radius == radius and last.size == size then
    return
  end
  last.n, last.w, last.facing, last.radius, last.size = pn, pw, facing, radius, size
  dirty = false
  stats.updates = stats.updates + 1
  local half = size / 2
  -- (1.3.5) new pins or another zoom: bundle again (the dressed buttons follow)
  local k = half / radius
  if bundledFor ~= entries or bundledK ~= k then
    for _, e in ipairs(entries) do Give(e) end
    Bundle(k, radius)
    stats.bundles = (stats.bundles or 0) + 1
  end
  local shape = MinimapShape()
  -- cheap cut before the rotation: farther than the view's corner (square minimap)
  local reach = radius * 1.5
  local reach2 = reach * reach
  local n, near = 0, 0
  local leaveNear = ns.db.skipGameGivers
  for _, e in ipairs(entries) do
    local x, y, inView
    if n < MAX_SHOWN and e.c == pc and e.head == e then
      local dn, de = e.dn - pn, -(e.dw - pw)
      local d2 = dn * dn + de * de
      local kind = e.pin.kind
      -- (1.3.7, Daniel 13.10.: "still double !, when I come closer one goes away"; the game's own ! shows right at
      -- the edge of the minimap, zoomed out fully) the game marks givers in the whole view: Questdon leaves them all
      if leaveNear and (kind == "available" or kind == "turnin") then
        near = near + 1 -- the game's own blip marks this giver
      elseif kind == "dungeon" and (ns.db.dungeonPinsMinimap == false or d2 > DUNGEON2) then
        -- (1.3.5) entrances only close by (and with their option on): no clutter at the edge
      elseif d2 <= reach2 then
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
        b.members = e.members
        Look(b, e.pin, e.scale)
      end
      Retint(b)
      b:ClearAllPoints()
      b:SetPoint("CENTER", container, "CENTER", x, y)
      local close = b.kind == "objective" and e.dn and (e.dn - pn) ^ 2 + (e.dw - pw) ^ 2 < CLOSE_YARDS * CLOSE_YARDS or nil
      if close ~= b.close then b.close = close b:SetAlpha(Alpha(b)) end
      b:Show()
    elseif e.btn then
      Give(e)
    end
  end
  stats.shown = n
  stats.nearGame = near
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
  return ("ready, %d shown of %d, radius %s, rotate %s, builds %d, skipped %d, near givers left to the game %d"):format(stats.shown, #entries,
    tostring(stats.radius), RotateText(), stats.builds, stats.skipped, stats.nearGame or 0)
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
local function QueueFresh() ForgetBase() Queue() end
ns.On("QUEST_DATA_LOAD_RESULT", QueueFresh)
ns.On("QUESTLINE_UPDATE", QueueFresh)
ns.On("BAG_UPDATE_DELAYED", Queue) -- the base pins (quests to take, turn-ins, entrances) do not read the bags
ns.On("PLAYER_LEVEL_UP", QueueFresh)
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do ns.On(e, ForgetBase) end
ns.On("ZONE_CHANGED_NEW_AREA", function() curMap = nil dirty = true end)
