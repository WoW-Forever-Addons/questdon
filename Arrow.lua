local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Direction arrow (TomTom style) for the tracked quest or a clicked map pin.
-- Uses world coordinates of the maps; works in the open world. In instances
-- the client gives no map position, then the arrow hides itself.
---------------------------------------------------------------------------
local ARRIVED_YARDS = 8
local arrow
local manual -- target set by clicking a pin: { mapID, x, y, label }
local auto   -- target from the tracked quest
local external -- target from another addon (e.g. a leveling guide)

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
-- World position (yards) of a map point: continentID, north, west. The
-- client's answer, two vector tables per call.
local function AskWorldPos(mapID, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not ok or not ns.Num(continent) or type(pos) ~= "table" or not pos.GetXY then return nil end
  local ok2, wx, wy = pcall(pos.GetXY, pos)
  if not ok2 or not (ns.Num(wx) and ns.Num(wy)) then return nil end
  return continent, wx, wy
end

-- (1.23) A map is an axis-aligned rectangle in the world, so its world
-- position is linear in x and y (what HereBeDragons does with the map's
-- corners). Per map, the client is asked for three corners once and every
-- point after that is arithmetic: no vectors per call (arrow 33 times a
-- second, minimap 10 times, every pin of a rebuild). The first real point
-- of a map is checked against the client; a map that does not fit (or any
-- unreadable answer) keeps asking the client. Replacing the client
-- function (another addon) starts over.
local transforms, transformFn = {}, nil
local NONLINEAR = false
local function Transform(mapID)
  local fn = C_Map and C_Map.GetWorldPosFromMapPos
  if fn ~= transformFn then transforms, transformFn = {}, fn end
  local t = transforms[mapID]
  if t ~= nil then return t end
  local c0, n0, w0 = AskWorldPos(mapID, 0, 0)
  local c1, n1, w1 = AskWorldPos(mapID, 1, 0)
  local c2, n2, w2 = AskWorldPos(mapID, 0, 1)
  if not (c0 and c1 and c2) or c0 ~= c1 or c0 ~= c2 then return nil end -- not cached: ask again next time
  t = { c = c0, n0 = n0, w0 = w0, nx = n1 - n0, wx = w1 - w0, ny = n2 - n0, wy = w2 - w0, checked = false }
  transforms[mapID] = t
  return t
end
function ns.WorldPos(mapID, x, y)
  mapID, x, y = ns.Num(mapID), ns.Num(x), ns.Num(y)
  if not (mapID and x and y) then return nil end
  local t = Transform(mapID)
  if not t then return AskWorldPos(mapID, x, y) end
  local n, w = t.n0 + x * t.nx + y * t.ny, t.w0 + x * t.wx + y * t.wy
  if not t.checked then
    t.checked = true
    local c, an, aw = AskWorldPos(mapID, x, y)
    if c ~= t.c or not an or math.abs(an - n) > 0.5 or math.abs(aw - w) > 0.5 then
      transforms[mapID] = NONLINEAR
      return c, an, aw
    end
  end
  return t.c, n, w
end

local function PlayerWorld()
  local mapID, x, y = ns.PlayerPosition()
  if not mapID then return nil end
  return ns.WorldPos(mapID, x, y)
end

-- World position of the last target asked for: the arrow asks for the same
-- target many times per second, and targets do not move.
local cT, cMap, cX, cY, cC, cN, cW
local function TargetWorld(target)
  if cT == target and cMap == target.mapID and cX == target.x and cY == target.y then return cC, cN, cW end
  local tc, tn, tw = ns.WorldPos(target.mapID, target.x, target.y)
  if tc then cT, cMap, cX, cY, cC, cN, cW = target, target.mapID, target.x, target.y, tc, tn, tw end
  return tc, tn, tw
end

local function FromPlayer(pc, pn, pw, target)
  if not (pc and target and target.mapID and target.x and target.y) then return nil end
  local tc, tn, tw = TargetWorld(target)
  if not tc or pc ~= tc then return nil end
  local north, east = tn - pn, -(tw - pw)
  local dist = math.sqrt(north * north + east * east)
  local bearing = math.atan2 and math.atan2(east, north) or math.atan(east, north)
  return dist, bearing
end

-- distance (yards) and bearing (radians, clockwise from north) from player to target
function ns.DistanceAndBearing(target)
  local pc, pn, pw = PlayerWorld()
  return FromPlayer(pc, pn, pw, target)
end

-- (1.23) For lists of targets: the player's world position once
-- (ns.PlayerWorld), then ns.DistanceFrom(pc, pn, pw, target) per target.
ns.PlayerWorld = PlayerWorld
function ns.DistanceFrom(pc, pn, pw, target)
  return FromPlayer(pc, pn, pw, target)
end

---------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------
-- All known points for one quest (any map), best source first (1.15):
--   failed:     back to the quest giver (never for quests started by an item)
--   complete:   Blizzard's turn-in point, else learned, else a guess
--   incomplete: Blizzard's objective point (unless it is the place of use of
--               an item still missing), else learned and ATT points of the open
--               objectives. Nothing open but not complete ("return to ..."):
--               the turn-in. Open escort/event objective without data: the
--               quest giver (the escort starts there).
-- Second value: "autocomplete" when the quest completes from the log.
local function QuestPoints(questID)
  local pts = {}
  if ns.IsQuestFailed(questID) then
    local m, x, y = ns.QuestStart(questID)
    if m and x and not ns.IsItemStartQuest(questID) then pts[1] = { mapID = m, x = x / 100, y = y / 100, kind = "failed" } end
    return pts
  end
  local complete = ns.IsQuestComplete(questID)
  local total, open, _, types = ns.ObjectiveState(questID)
  local function TurnIn()
    -- Without Blizzard or learned data: the giver of the next quest in the
    -- chain, or (if the quest had objectives, so no delivery) its own giver.
    local m, x, y, source = ns.TurnInPoint(questID, total > 0)
    if m and x then
      pts[#pts + 1] = { mapID = m, x = x, y = y, kind = (source == "learned" or source == "blizzard" or source == "shared") and "turnin" or "guess" }
    end
    return pts
  end
  if complete then
    if ns.IsAutoComplete(questID) then return pts, "autocomplete" end
    return TurnIn()
  end
  -- (1.25) Blizzard's point is one of the candidates, not the only one: the
  -- arrow takes the nearest of all places where the objective can be done
  -- (Blizzard's point, learned spots, ATT points and spawns). Before, a
  -- Blizzard point (the middle of its area) won even when the player stood
  -- among the mobs (The Woodland Protector: 195 yards away). Only a
  -- "next waypoint" (a route step into another zone) stays alone.
  local m, x, y, _, _, level = ns.QuestPOI(questID)
  if m and level == "waypoint" then
    pts[1] = { mapID = m, x = x, y = y, kind = "objective", source = "blizzard" }
    return pts
  end
  -- (1.26) objective area only for objectives done in an area (kill or
  -- collect several); a single target (talk to an NPC, one object) and the
  -- place where an item must be used are exact spots: the arrow leads there
  -- and says "Arrived".
  if m then pts[1] = { mapID = m, x = x, y = y, kind = "objective", source = "blizzard", area = ns.AnyAreaObjective(questID) } end
  for _, p in ipairs(ns.AllObjectivePoints(questID)) do
    p.area = not p.useSpot and ns.IsAreaObjective(questID, p.index)
    pts[#pts + 1] = p
  end
  if #pts > 0 then return pts end
  if ns.ObjectiveHint(questID) then return pts end -- "first get <item>", nowhere known: no target
  if (total > 0 and open == 0) or (total == 0 and not ns.HasObjectiveData(questID)) then return TurnIn() end
  if open > 0 and (types.event or types.escort) and not ns.IsItemStartQuest(questID) then
    local sm, sx, sy = ns.QuestStart(questID)
    if sm and sx then pts[1] = { mapID = sm, x = sx / 100, y = sy / 100, kind = "start" } end
  end
  return pts
end

local function Nearest(points)
  local best, bestDist
  local pc, pn, pw = PlayerWorld() -- once, not per point
  if not pc then return nil end
  for _, p in ipairs(points) do
    local d = FromPlayer(pc, pn, pw, p)
    if d and (not bestDist or d < bestDist) then best, bestDist = p, d end
  end
  return best, bestDist
end

---------------------------------------------------------------------------
-- (1.25) Objective area. For kill and collect objectives the arrow knows all
-- places (area = true). Within AREA_ENTER yards of one of them, or with a
-- mob of an open objective of the quest in sight (target or nameplate, GUID
-- readable), the player is "in the objective area": the arrow says so
-- instead of sending him away. It leaves that state only beyond AREA_LEAVE
-- yards and AREA_HOLD seconds after the last such mob (no flicker). While in
-- the area, the arrow points only when the nearest spot is farther than
-- AREA_ENTER. The nearest spot is chosen again twice a second; a new one
-- must be SWITCH_YARDS nearer than the current one.
---------------------------------------------------------------------------
-- Distances are world units of C_Map.GetWorldPosFromMapPos: yards (the
-- German client calls them "Meter" with the same numbers).
local AREA_ENTER, AREA_LEAVE, AREA_HOLD, AREA_CHECK, SWITCH_YARDS = 40, 60, 10, 0.5, 10

-- (1.26) Is objective <index> of questID done in an area? Several kills or
-- items (numRequired >= 2). Unknown (no client data, secret): yes, as in 1.25.
function ns.IsAreaObjective(questID, index)
  local o = index and ns.ClientObjectives(questID)[index]
  if type(o) ~= "table" then return true end
  local n = ns.Num(o.numRequired)
  if not n then return true end
  return n >= 2
end
-- Any open objective of the quest done in an area (for Blizzard's point).
function ns.AnyAreaObjective(questID)
  local client = ns.ClientObjectives(questID)
  if #client == 0 then return true end
  for i, o in ipairs(client) do
    if not (type(o) == "table" and ns.True(o.finished)) and ns.IsAreaObjective(questID, i) then return true end
  end
  return false
end
local area = { questID = nil, inside = false, reason = nil, mobAt = nil, checkAt = nil, dist = nil }
local areaStats = { checks = 0, mobs = 0, secret = 0, entered = 0 }

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

-- Is this unit a living mob of an open objective of questID? nil when unreadable.
local function ObjectiveMob(unit, questID)
  local guid = UnitGUID and ns.Value(UnitGUID, unit)
  if guid == nil then
    if UnitExists and ns.True(ns.Value(UnitExists, unit)) then areaStats.secret = areaStats.secret + 1 end
    return nil
  end
  local creature = ns.CreatureIDFromGUID and ns.CreatureIDFromGUID(guid)
  if not creature or not ns.CreatureQuestIndex then return false end
  local objectives = ns.CreatureQuestIndex(creature)
  if not objectives then return false end
  if UnitIsDead and ns.True(ns.Value(UnitIsDead, unit)) then return false end
  local client = ns.ClientObjectives(questID)
  for _, entry in ipairs(objectives) do
    local q, index = ns.ObjectiveEntry(entry)
    if q == questID then
      local o = client[index]
      if not (#client > 0 and index > #client) and not (type(o) == "table" and ns.True(o.finished)) then return true end
    end
  end
  return false
end

local function MobInSight(questID)
  if ObjectiveMob("target", questID) then return true end
  for _, unit in ipairs(ns.NameplateUnits and ns.NameplateUnits() or {}) do
    if ObjectiveMob(unit, questID) then return true end
  end
  return false
end
ns.ObjectiveMobInSight = MobInSight

-- Re-pick the nearest area point of the auto target and work out the state.
local function CheckArea(t)
  local now = Now()
  if area.questID ~= t.questID then
    area.questID, area.inside, area.reason, area.mobAt, area.checkAt, area.dist = t.questID, false, nil, nil, nil, nil
  end
  if area.checkAt and now - area.checkAt < AREA_CHECK and now >= area.checkAt then return end
  area.checkAt = now
  areaStats.checks = areaStats.checks + 1
  local pc, pn, pw = PlayerWorld()
  if not pc then area.inside, area.dist = false, nil return end
  local best, bestDist, curDist
  for _, p in ipairs(t.points) do
    local d = FromPlayer(pc, pn, pw, p)
    if d then
      if not bestDist or d < bestDist then best, bestDist = p, d end
      if p.mapID == t.mapID and p.x == t.x and p.y == t.y then curDist = d end
    end
  end
  if best and (not curDist or bestDist < curDist - SWITCH_YARDS) then
    t.mapID, t.x, t.y, t.source, t.label = best.mapID, best.x, best.y, best.source, t.LabelFor(best)
    curDist = bestDist
  end
  area.dist = curDist
  if MobInSight(t.questID) then
    area.mobAt = now
    areaStats.mobs = areaStats.mobs + 1
  end
  local mobRecent = area.mobAt and now - area.mobAt <= AREA_HOLD and now >= area.mobAt
  local was = area.inside
  if (bestDist and bestDist <= AREA_ENTER) or (area.mobAt == now) then
    area.inside = true
    area.reason = (bestDist and bestDist <= AREA_ENTER) and "spot" or "mob"
  elseif was and ((bestDist and bestDist <= AREA_LEAVE) or mobRecent) then
    area.inside = true
  else
    area.inside, area.reason = false, nil
  end
  if area.inside and not was then areaStats.entered = areaStats.entered + 1 end
  -- the panel's "Nearest quest" line follows (quiet while in the area)
  if area.inside ~= was and ns.QueueRefresh then ns.QueueRefresh("panel") end
end

-- For the panel, /qd diag and the tests.
function ns.ArrowAreaState()
  return { inside = area.inside, reason = area.reason, dist = area.dist, questID = area.questID }
end
function ns.ArrowAreaStats() return areaStats end
function ns.ArrowInArea()
  -- (1.26) only while the auto target has an area (not after the quest became complete)
  return area.inside and auto ~= nil and auto.points ~= nil and area.questID == auto.questID
    and (ns.ArrowTarget and ns.ArrowTarget() == auto) or false
end

local function BuildAuto()
  auto = nil
  if not (ns.db.arrow and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then return end
  local questID = ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  if not questID or questID == 0 or not ns.InQuestLog(questID) then return end
  local points, special = QuestPoints(questID)
  if special == "autocomplete" then
    auto = { label = L["%s: complete it from the quest log"]:format(ns.QuestTitle(questID)), questID = questID }
    return
  end
  local p = Nearest(points)
  if p then
    local title = ns.QuestTitle(questID)
    local function LabelFor(q)
      if q.kind == "turnin" then return L["Turn in: %s"]:format(title)
      elseif q.kind == "guess" then return L["Turn in (probably): %s"]:format(title)
      elseif q.kind == "failed" then return L["Quest failed: %s"]:format(title)
      elseif q.kind == "start" then return L["%s: starts at the quest giver"]:format(title)
      elseif q.needsItem then return L["%s: first get %s"]:format(title, ns.ItemName(q.needsItem)) end
      return title
    end
    auto = { mapID = p.mapID, x = p.x, y = p.y, label = LabelFor(p), questID = questID, source = p.source }
    -- (1.25) kill and collect objectives: all places, for the objective area
    if p.area then
      local list = {}
      for _, q in ipairs(points) do if q.area then list[#list + 1] = q end end
      auto.points, auto.LabelFor = list, LabelFor
    end
  end
end

function ns.UpdateArrowTarget()
  BuildAuto()
  -- (1.26) no area for this target (turn-in, exact spot, nothing tracked): leave the area state
  if not (auto and auto.points) and area.inside then
    area.inside, area.reason = false, nil
    if ns.QueueRefresh then ns.QueueRefresh("panel") end
  end
end

function ns.SetArrowTarget(mapID, x, y, label)
  manual = { mapID = mapID, x = x, y = y, label = label }
  if arrow and ns.db.arrow then arrow:Show() end
end

function ns.ClearArrow()
  manual = nil
end

-- Another addon (QuestdonAPI) can point the arrow; a clicked pin still wins.
function ns.SetExternalArrowTarget(target)
  external = target
  if target and arrow and ns.db.arrow then arrow:Show() end
end

local function Target()
  return manual or external or auto
end
ns.ArrowTarget = Target

---------------------------------------------------------------------------
-- Frame (1.19 family look): the arrow graphic in the accent colour, below it
-- a small dark plate with the target in the primary colour and the distance
-- in the secondary colour (status colours for "arrived" and "no position").
---------------------------------------------------------------------------
local Style = ns.Style
local Look = ns.Look
local ICON = 56
local TEXT_W = 220
local S = Style.SPACING

local function Scale()
  return Look.Clamp(ns.db.arrowScale, Style.SCALE_MIN, Style.SCALE_MAX, 1.15)
end

local function SavePosition()
  local point, _, relPoint, x, y = arrow:GetPoint(1)
  if point then ns.db.arrowPos = { point, relPoint or point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
end

local function DefaultPosition()
  arrow:ClearAllPoints()
  arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
end

local function ApplyPosition()
  local p = ns.db.arrowPos
  arrow:ClearAllPoints()
  if type(p) == "table" and type(p[1]) == "string" and pcall(arrow.SetPoint, arrow, p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0) then return end
  DefaultPosition()
end

function ns.ResetArrowPosition()
  ns.db.arrowPos = nil
  if arrow then DefaultPosition() end
end

-- Text plate: sized from the measured text (falls back to an estimate).
local function TextSize(fs)
  local t = fs:GetText()
  if t == nil or t == "" then return 0, 0 end
  local okW, w = pcall(fs.GetStringWidth, fs)
  local okH, h = pcall(fs.GetStringHeight, fs)
  w = okW and tonumber(w) or nil
  h = okH and tonumber(h) or nil
  local estimated = false
  if not w or w ~= w or w <= 0 then w = #(tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 estimated = true end
  if not h or h ~= h or h <= 0 then h = 12 estimated = true end
  return math.min(TEXT_W, math.ceil(w)), math.ceil(h), estimated
end

local lastLabel, lastDist, lastDistColor
local function SetTexts(self, label, dist, distColor)
  label, dist = label or "", dist or ""
  if label == lastLabel and dist == lastDist and distColor == lastDistColor and not self.box.estimated then return end
  lastLabel, lastDist, lastDistColor = label, dist, distColor
  self.label:SetWidth(TEXT_W)
  self.dist:SetWidth(TEXT_W)
  self.label:SetText(label)
  self.dist:SetText(dist)
  Look.SetColor(self.dist, distColor or "textSecondary")
  local lw, lh, e1 = TextSize(self.label)
  local dw, dh, e2 = TextSize(self.dist)
  self.box.estimated = e1 or e2
  local hasLabel, hasDist = lw > 0, dw > 0
  if not (hasLabel or hasDist) then self.box:Hide() return end
  local w = math.max(lw, dw)
  self.label:SetWidth(w)
  self.dist:SetWidth(w)
  self.dist:ClearAllPoints()
  if hasLabel then
    self.dist:SetPoint("TOP", self.label, "BOTTOM", 0, -S.rowGap)
  else
    self.dist:SetPoint("TOP", self.box, "TOP", 0, -S.padY)
  end
  local h = S.padY * 2 + lh + dh + ((hasLabel and hasDist) and S.rowGap or 0)
  self.box:SetSize(w + 2 * S.padX, h)
  self.box.plate:Layout()
  self.box:Show()
end

local function Update(self)
  local t = Target()
  -- Without a target the frame is invisible: let clicks pass through to the world.
  local wantMouse = (ns.db.arrow and t) and true or false
  if self.qdMouse ~= wantMouse then
    self.qdMouse = wantMouse
    self:EnableMouse(wantMouse)
  end
  if not wantMouse then self.icon:Hide() SetTexts(self, "", "") return end
  if not t.mapID then
    -- nothing to walk to (a quest that completes from the log): text only
    self.icon:Hide() SetTexts(self, t.label, "")
    return
  end
  -- (1.25) objective area of the tracked quest (auto target only)
  local inArea = false
  if t == auto and t.points then
    CheckArea(t)
    inArea = area.inside
  end
  local dist, bearing = ns.DistanceAndBearing(t)
  if inArea then
    if not dist or dist <= AREA_ENTER then
      self.icon:Hide()
      SetTexts(self, t.label, L["In the objective area"], "good")
      return
    end
    SetTexts(self, t.label, L["In the objective area, nearest spot %d yards"]:format(dist), "good")
  end
  if not dist then
    self.icon:Hide()
    SetTexts(self, t.label, L["Other zone or no position"], "textHint")
    return
  end
  if dist < ARRIVED_YARDS then
    self.icon:Hide()
    SetTexts(self, t.label, L["Arrived"], "good")
    if manual == t then manual = nil end
    return
  end
  if not inArea then SetTexts(self, t.label, L["%d yards"]:format(dist), "textSecondary") end
  local facing = ns.Num(ns.Value(GetPlayerFacing))
  if facing then
    -- facing: radians counter-clockwise from north; bearing: clockwise from north.
    -- Angle to turn (clockwise) = bearing + facing; SetRotation turns counter-clockwise.
    self.icon:SetRotation(-(bearing + facing))
    self.icon:Show()
  else
    self.icon:Hide()
  end
end

local function Tooltip(self)
  local t = Target()
  if not t then return end
  local lines = {}
  if t.mapID then
    local dist = ns.DistanceAndBearing(t)
    lines[1] = { L["Distance"], dist and L["%d yards"]:format(dist) or L["Other zone or no position"] }
  end
  if t == auto and t.points and area.inside then
    lines[#lines + 1] = { L["In the objective area"], area.reason == "mob" and L["quest mobs nearby"] or L["near a known spot"], "good" }
  end
  local hint = L["Right-click: drop a clicked target."]
  if not ns.db.arrowLocked then hint = hint .. " " .. L["Drag to move."] end
  Style.Tooltip(self, t.label or L["Direction arrow"], lines, hint)
end

local function Create()
  arrow = CreateFrame("Button", "QuestdonArrow", UIParent)
  arrow:SetSize(ICON, ICON)
  arrow:SetClampedToScreen(true)
  arrow:SetMovable(true)
  arrow:EnableMouse(true)
  arrow:RegisterForDrag("LeftButton")
  arrow:RegisterForClicks("RightButtonUp")
  arrow:SetScript("OnDragStart", function(self) if not ns.db.arrowLocked then self:StartMoving() end end)
  arrow:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
  arrow:SetScript("OnClick", ns.Guard("arrow", function() ns.ClearArrow() ns.UpdateArrowTarget() end))
  arrow:SetScript("OnEnter", ns.Guard("arrow", Tooltip))
  arrow:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  ApplyPosition()

  arrow.icon = arrow:CreateTexture(nil, "ARTWORK")
  arrow.icon:SetAllPoints()
  arrow.icon:SetTexture("Interface\\Minimap\\MinimapArrow")
  local a = Style.COLORS.accent
  arrow.icon:SetVertexColor(a[1], a[2], a[3])

  -- text plate below the arrow (own frame, no mouse: clicks go to the world)
  local box = CreateFrame("Frame", nil, arrow)
  box:SetPoint("TOP", arrow, "BOTTOM", 0, -S.rowGap * 2)
  box:EnableMouse(false)
  box.plate = Look.Plate(box)
  arrow.box = box

  arrow.label = Look.Font(box, "GameFontHighlightSmall", "textPrimary")
  arrow.label:SetPoint("TOP", box, "TOP", 0, -S.padY)
  arrow.label:SetJustifyH("CENTER")
  arrow.label:SetWordWrap(true)
  arrow.dist = Look.Font(box, "GameFontHighlightSmall", "textSecondary")
  arrow.dist:SetJustifyH("CENTER")
  arrow.dist:SetPoint("TOP", arrow.label, "BOTTOM", 0, -S.rowGap)
  box:Hide()

  -- Throttled; the update itself runs protected. (1.23) Without arguments:
  -- no closure or table per frame.
  local elapsed = 0
  local function UpdateArrow() Update(arrow) end
  arrow:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < 0.03 then return end
    elapsed = 0
    ns.SafeCall("arrow", UpdateArrow)
  end)
  ns.ApplyArrowLook()
end

-- Options (Appearance page): size, plate opacity, combat dimming, shown.
function ns.ApplyArrowLook()
  if not arrow then return end
  arrow:SetShown(ns.db.arrow)
  arrow:SetScale(Scale())
  arrow.box.plate:SetAlpha(ns.db.arrowAlpha)
  Style.CombatFade(arrow, ns.db.arrowCombatFade) -- (1.20) kit v2 for own frames
end

function ns.ApplyArrow()
  ns.ApplyArrowLook()
  ns.UpdateArrowTarget()
end

function ns.ToggleArrow()
  ns.db.arrow = not ns.db.arrow
  ns.ApplyArrow()
end

-- (1.23) Batched with the other quest displays (Core.lua, 0.5 s).
ns.RegisterRefresh("arrow", function() ns.UpdateArrowTarget() end)
local function Queue() ns.QueueRefresh("arrow") end

ns.OnInit(function()
  Create()
  ns.NewTicker(5, ns.UpdateArrowTarget) -- nearest point changes while you move
end)
ns.On("SUPER_TRACKING_CHANGED", Queue)
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("ZONE_CHANGED_NEW_AREA", Queue)
ns.On("PLAYER_ENTERING_WORLD", Queue)
ns.On("QUEST_POI_UPDATE", Queue)
ns.On("QUEST_AUTOCOMPLETE", Queue)
-- an item to use at a place came into the bags (or left them): other target
ns.On("BAG_UPDATE_DELAYED", Queue)
