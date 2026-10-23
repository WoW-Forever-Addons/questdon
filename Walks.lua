local _, ns = ...

---------------------------------------------------------------------------
-- (17.10., Daniel: "and what about the walking routes?") Quest NPCs that walk a route (a quest giver like Gordo, a
-- named mob like Old Murk-Eye): their route as a red dotted line on the world map and the minimap, so you know
-- where to look. Only for NPCs that matter now: the mobs of your open objectives, the turn-in NPC of a finished
-- quest, the giver of a quest shown as available on that map. Data: ns.WALKS (Data/Walks.lua, qk-tools/walks.py).
--
-- Own frames only (like PathDots.lua): a container on the minimap and an own data provider with an own pin template
-- on the world map. Cost: the dots of a route are worked out once; which NPCs matter is read again only when the
-- quest log, the map or the level changed, at most every RELEVANT_EVERY seconds.
---------------------------------------------------------------------------
local SPACING = 12          -- yards between two dots
local MAX_MAP_DOTS = 400    -- on the world map, all routes together
local MAX_DOTS = 80         -- on the minimap
local DOT_PX, RING_PX = 4, 7
local MIN_GAP_PX = 8
local UPDATE_INTERVAL = 0.1
local RELEVANT_EVERY = 30 -- (17.10., /qd mem: 5 s before) the log, the level and the map count at once anyway
local COLOR = { 0.92, 0.14, 0.1, 1 }
local RING = { 0.08, 0.02, 0.02, 0.75 }
local ROUND = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function Enabled() return ns.db and ns.db.walkLines ~= false and type(ns.WALKS) == "table" end

-- the NPCs with a route on a map: built once
local byMap
local function NpcsOnMap(mapID)
  if not byMap then
    byMap = {}
    for npc, maps in pairs(ns.WALKS or {}) do
      for m in pairs(maps) do
        local l = byMap[m] or {}
        l[#l + 1] = npc
        byMap[m] = l
      end
    end
    for _, l in pairs(byMap) do table.sort(l) end
  end
  return byMap[mapID]
end

-- The points of one route (0-1), decoded once: { {x, y}, ... } per route
local decoded = {}
local function Routes(npc, mapID)
  local key = npc * 10000 + mapID
  local r = decoded[key]
  if r then return r end
  r = {}
  local maps = ns.WALKS and ns.WALKS[npc]
  for _, s in ipairs(maps and maps[mapID] or {}) do
    local pts = {}
    for i = 1, #s - 3, 4 do
      local x, y = tonumber(s:sub(i, i + 1), 36), tonumber(s:sub(i + 2, i + 3), 36)
      if x and y then pts[#pts + 1] = { x / 1000, y / 1000 } end
    end
    if #pts >= 2 then r[#r + 1] = pts end
  end
  decoded[key] = r
  return r
end

-- The dots of one route (closed: back from the last point to the first), every SPACING yards: { x = {}, y = {}, n }
local dotCache = {}
local function RouteDots(npc, mapID)
  local key = npc * 10000 + mapID
  local d = dotCache[key]
  if d then return d end
  d = { x = {}, y = {}, n = 0 }
  for _, pts in ipairs(Routes(npc, mapID)) do
    local carry = 0
    for k = 1, #pts do
      local a, b = pts[k], pts[k % #pts + 1]
      local ac, an, aw = ns.WorldPos(mapID, a[1], a[2])
      local bc, bn, bw = ns.WorldPos(mapID, b[1], b[2])
      if not (ac and bc and ac == bc) then return d end -- the map's corners are not known yet: ask again later
      local len = math.sqrt((bn - an) ^ 2 + (bw - aw) ^ 2)
      local s = carry
      while s <= len do
        local f = len > 0 and s / len or 0
        d.n = d.n + 1
        d.x[d.n], d.y[d.n] = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
        s = s + SPACING
      end
      carry = s - len
    end
  end
  dotCache[key] = d
  return d
end
ns.WalkDots = RouteDots -- (tests)

-- Which NPCs with a route on mapID matter now
local function Relevant(mapID)
  local list = NpcsOnMap(mapID)
  local out = {}
  if not list then return out end
  local want = {}
  -- the mobs of your open objectives
  for _, info in ipairs(ns.QuestLogEntries and ns.QuestLogEntries() or {}) do
    local q = info.questID
    if q and not (ns.IsQuestComplete and ns.IsQuestComplete(q)) and ns.OpenObjectiveCreatures then
      for _, cr in ipairs(ns.OpenObjectiveCreatures(q)) do want[cr] = true end
    end
  end
  -- quest givers of the quests on this map, turn-in NPCs of finished quests
  for _, p in ipairs(ns.PinsForMapBase and ns.PinsForMapBase(mapID) or {}) do
    if p.kind == "turnin" and p.npcID then want[p.npcID] = true
    elseif p.kind == "available" and p.questID and not p.dimmed then
      for _, g in ipairs(ns.QuestGiverIDs(p.questID) or {}) do want[g] = true end
    end
  end
  for _, npc in ipairs(list) do
    if want[npc] and ns.WalkState(npc, mapID) ~= "doubtful" then out[#out + 1] = npc end
  end
  return out
end

local relevant = { } -- [mapID] = { npcs = {}, sig = "", at = time, gen = logGen, level = level }
local function RelevantNpcs(mapID)
  local r = relevant[mapID]
  local now = type(GetTime) == "function" and GetTime() or 0
  local gen = ns.LogGen and ns.LogGen() or 0
  local level = ns.PlayerLevel and ns.PlayerLevel() or 0
  if r and r.gen == gen and r.level == level and now - r.at < RELEVANT_EVERY then return r end
  if not NpcsOnMap(mapID) then
    r = { npcs = {}, sig = "", at = now, gen = gen, level = level }
  else
    local npcs = ns.ScopeCall and ns.ScopeCall(Relevant, mapID) or Relevant(mapID)
    r = { npcs = npcs, sig = table.concat(npcs, ","), at = now, gen = gen, level = level }
  end
  relevant[mapID] = r
  return r
end
ns.WalkNpcs = function(mapID) return Relevant(mapID) end -- (tests)
function ns.ForgetWalks() relevant = {} end

---------------------------------------------------------------------------
-- (17.10., Daniel: "let the players confirm the routes") Where a walking NPC was seen: its nameplate within about 28
-- yards (the follow distance, Learn.lua's sightings), your target or the unit under the mouse that close, or the NPC
-- you talk to (exact). Your position then is a point of its route. Account wide, out of combat, at most once per NPC
-- every SEEN_SECS, points closer than SEEN_GAP map widths count once, at most SEEN_MAX per NPC and map:
--   QuestdonDB.walkSeen[npcID][mapID] = { x1, y1, x2, y2, ... } (0-1)
-- Shared like the objective spots ("P npc map x y", Export.lua and Exchange.lua). With the points of you and others,
-- a route counts as confirmed (most points on it) or doubtful (most points far off it): a doubtful one is not drawn.
---------------------------------------------------------------------------
local SEEN_SECS, SEEN_GAP, SEEN_MAX = 5, 0.01, 40
local ON_ROUTE, OFF_ROUTE = 0.03, 0.05     -- map widths from the route: on it / clearly off it
local CONFIRM_ON, DOUBT_OFF = 3, 4         -- points needed
local lastSeen = {}
local seenStats = { seen = 0, added = 0 }
function ns.WalkSeenStats() return seenStats end

local function SegDist(px, py, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local l = dx * dx + dy * dy
  local t = l > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l)) or 0
  return math.sqrt((ax + t * dx - px) ^ 2 + (ay + t * dy - py) ^ 2)
end
-- distance of a point from the NPC's routes on that map (map widths), nil without a route there
function ns.WalkDistance(npc, mapID, x, y)
  local best
  for _, pts in ipairs(Routes(npc, mapID)) do
    for k = 1, #pts do
      local a, b = pts[k], pts[k % #pts + 1]
      local d = SegDist(x, y, a[1], a[2], b[1], b[2])
      if not best or d < best then best = d end
    end
  end
  return best
end

local function AddSeen(npc, mapID, x, y)
  local db = ns.db
  db.walkSeen = type(db.walkSeen) == "table" and db.walkSeen or {}
  local per = db.walkSeen[npc]
  if type(per) ~= "table" then per = {} db.walkSeen[npc] = per end
  local l = per[mapID]
  if type(l) ~= "table" then l = {} per[mapID] = l end
  for i = 1, #l - 1, 2 do
    if (l[i] - x) ^ 2 + (l[i + 1] - y) ^ 2 < SEEN_GAP * SEEN_GAP then return false end
  end
  if #l >= 2 * SEEN_MAX then return false end
  l[#l + 1] = math.floor(x * 1000 + 0.5) / 1000
  l[#l + 1] = math.floor(y * 1000 + 0.5) / 1000
  return true
end
ns.AddWalkSeen = AddSeen -- (tests)

local function CloseEnough(unit)
  if unit == "npc" then return true end
  if not CheckInteractDistance then return false end
  local ok, near = pcall(CheckInteractDistance, unit, 4)
  return ok and ns.Usable(near) and near and true or false
end
-- unit: a unit token; creatureID from its GUID. Only NPCs with a route.
function ns.NoteWalkSighting(unit, creatureID)
  if not (creatureID and ns.WALKS and ns.WALKS[creatureID] and ns.db) then return end
  if ns.db.learnQuests == false or (InCombatLockdown and InCombatLockdown()) then return end
  local now = type(GetTime) == "function" and GetTime() or 0
  if lastSeen[creatureID] and now - lastSeen[creatureID] < SEEN_SECS then return end
  if not CloseEnough(unit) then return end
  local m, x, y = ns.PlayerPosition()
  -- only on a map where the NPC has a route (another map: another NPC of that ID, or a wrong reading)
  if not (m and x and y and ns.WALKS[creatureID][m]) then return end
  lastSeen[creatureID] = now
  seenStats.seen = seenStats.seen + 1
  if AddSeen(creatureID, m, x, y) then seenStats.added = seenStats.added + 1 end
end
local function FromUnit(unit)
  if not (UnitGUID and ns.CreatureIDFromGUID) then return end
  local guid = ns.Value(UnitGUID, unit)
  if guid ~= nil then ns.NoteWalkSighting(unit, ns.CreatureIDFromGUID(guid)) end
end
ns.On("PLAYER_TARGET_CHANGED", function() ns.SafeCall("walk seen", FromUnit, "target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() ns.SafeCall("walk seen", FromUnit, "mouseover") end)
for _, ev in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
  ns.On(ev, function() ns.SafeCall("walk seen", FromUnit, "npc") end)
end

-- Export lines "P npc map x y" (percent, one decimal): every point you saw (they confirm a route or move it)
function ns.WalkSeenRecords()
  local out = {}
  local seen = type(ns.db.walkSeen) == "table" and ns.db.walkSeen or {}
  local npcs = {}
  for npc in pairs(seen) do if type(npc) == "number" then npcs[#npcs + 1] = npc end end
  table.sort(npcs)
  for _, npc in ipairs(npcs) do
    local maps = {}
    for m in pairs(seen[npc]) do if type(m) == "number" then maps[#maps + 1] = m end end
    table.sort(maps)
    for _, m in ipairs(maps) do
      local l = seen[npc][m]
      for i = 1, #l - 1, 2 do out[#out + 1] = ("P %d %d %.1f %.1f"):format(npc, m, l[i] * 100, l[i + 1] * 100) end
    end
  end
  return out
end

-- The state of an NPC's route on a map from your points and the confirmed points of others:
-- "confirmed", "doubtful" or "open"; on, off: points on and clearly off the route
function ns.WalkState(npc, mapID)
  local on, off = 0, 0
  local function Count(x, y)
    local d = ns.WalkDistance(npc, mapID, x, y)
    if d then
      if d <= ON_ROUTE then on = on + 1 elseif d > OFF_ROUTE then off = off + 1 end
    end
  end
  local own = type(ns.db.walkSeen) == "table" and type(ns.db.walkSeen[npc]) == "table" and ns.db.walkSeen[npc][mapID]
  if type(own) == "table" then for i = 1, #own - 1, 2 do Count(own[i], own[i + 1]) end end
  for _, p in ipairs(ns.SharedWalkSeen and ns.SharedWalkSeen(npc, mapID) or {}) do Count(p[1], p[2]) end
  local state = "open"
  if off >= DOUBT_OFF and off > 2 * on then state = "doubtful"
  elseif on >= CONFIRM_ON and on >= 3 * off then state = "confirmed" end
  return state, on, off
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local container
local tex, shown = {}, 0
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
  if not Enabled() or ns.db.minimapPins == false or not (Minimap and ns.MinimapRadius) then HideFrom(1) return end
  local m, px, py = ns.PlayerPosition()
  if not (m and px) or not NpcsOnMap(m) then HideFrom(1) return end
  local npcs = RelevantNpcs(m).npcs
  if #npcs == 0 then HideFrom(1) return end
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
  local stride = math.max(1, math.ceil(MIN_GAP_PX / (SPACING * half / radius)))
  local shape = type(GetMinimapShape) == "function" and ns.Value(GetMinimapShape) or "ROUND"
  local n = 0
  for _, npc in ipairs(npcs) do
    local d = RouteDots(npc, m)
    for i = 1, d.n, stride do
      local c, dn, dw = ns.WorldPos(m, d.x[i], d.y[i])
      if c == pc then
        local x, y = ns.MinimapOffset(dn - pn, -(dw - pw), radius, half, facing)
        if ns.OnMinimap(x, y, half, 3, shape) then
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
    if n >= MAX_DOTS then break end
  end
  if n > shown then shown = n end
  HideFrom(n + 1)
  shown = n
end
ns.WalkMinimapShown = function() return shown end -- (tests)
ns.WalkMinimapUpdate = function() ns.SafeCall("walks", UpdateMinimap) end -- (tests)

function SetupMinimap()
  if container or not Minimap then return end
  container = CreateFrame("Frame", "QuestdonWalks", Minimap)
  container:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
  container:SetSize(1, 1)
  local level = ns.Num(ns.Value(Minimap.GetFrameLevel, Minimap))
  if level then container:SetFrameLevel(level + 3) end -- under the way's dots and the quest pins
  local elapsed = 0
  container:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0
    ns.SafeCall("walks", UpdateMinimap)
  end)
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local TEMPLATE = "QuestdonWalkDotPinTemplate"
local provider, mapSig, mapSigNpcs, setupFailed -- (17.10., /qd mem) the map and its NPCs, two values: no new string each second
-- the world map canvas in its own units (the pins' size is in these too); a zone map is about 1000 wide
local MAP_GAP = 12
local function MapCanvasSize(map)
  local c = map and map.GetCanvas and ns.Value(map.GetCanvas, map)
  local w = c and ns.Num(ns.Value(c.GetWidth, c))
  local h = c and ns.Num(ns.Value(c.GetHeight, c))
  if not (w and w > 0) then w = 1002 end
  if not (h and h > 0) then h = 668 end
  return w, h
end
ns.WalkMapCanvasSize = MapCanvasSize -- (tests)

local function SetupMap()
  if provider or setupFailed then return end
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end
  QuestdonWalkDotPinMixin = CreateFromMixins(MapCanvasPinMixin)
  local Pin = QuestdonWalkDotPinMixin
  function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    if self.SetScalingLimits then self:SetScalingLimits(1, 0.7, 1.1) end
    if self.EnableMouse then self:EnableMouse(false) end
  end
  function Pin:OnAcquired(x, y)
    self:SetSize(RING_PX, RING_PX)
    self:SetPosition(x, y)
    if self.Ring then self.Ring:SetVertexColor(RING[1], RING[2], RING[3], RING[4]) end
    if self.Dot then self.Dot:SetVertexColor(COLOR[1], COLOR[2], COLOR[3], COLOR[4]) end
  end
  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  p.RemoveAllData = ns.Guard("walks map", function(self) self:GetMap():RemoveAllPinsByTemplate(TEMPLATE) end)
  p.RefreshAllData = ns.Guard("walks map", function(self)
    local mapID = ns.Num(self:GetMap():GetMapID())
    if InCombatLockdown and InCombatLockdown() then
      -- pins cannot be made in combat (see MapPins.lua): another map's dots go, this map's stay
      if mapSig ~= mapID then self:RemoveAllData() mapSig, mapSigNpcs = nil, nil end
      return
    end
    self:RemoveAllData()
    mapSig, mapSigNpcs = nil, nil
    if not (Enabled() and mapID and NpcsOnMap(mapID)) then return end
    local r = RelevantNpcs(mapID)
    local n = 0
    -- (17.10., Daniel's screenshot of Holland near Brill: a thick red line, not dots) a dot every 12 yards is about
    -- 2 px on a zone map: keep a dot only MAP_GAP canvas units away from every dot kept on that route, which also
    -- keeps a route that doubles back from piling up
    local cw, chh = MapCanvasSize(self:GetMap())
    for _, npc in ipairs(r.npcs) do
      local d = RouteDots(npc, mapID)
      local kx, ky = {}, {}
      for i = 1, d.n do
        if n >= MAX_MAP_DOTS then break end
        local x, y = d.x[i], d.y[i]
        local free = true
        for k = 1, #kx do
          local dx, dy = (x - kx[k]) * cw, (y - ky[k]) * chh
          if dx * dx + dy * dy < MAP_GAP * MAP_GAP then free = false break end
        end
        if free then
          kx[#kx + 1], ky[#ky + 1] = x, y
          n = n + 1
          self:GetMap():AcquirePin(TEMPLATE, x, y)
        end
      end
    end
    mapSig, mapSigNpcs = mapID, r.sig
  end)
  local ok = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, p)
  if ok then provider = p else setupFailed = true end
end
-- once a second while the world map is open: the dots again when the NPCs that matter changed
local function TickMap()
  if not provider then SetupMap() end
  if not (provider and provider:GetMap() and WorldMapFrame:IsShown()) then return end
  local mapID = ns.Num(provider:GetMap():GetMapID())
  local on = Enabled() and mapID and NpcsOnMap(mapID) and true or false
  local wantMap, wantNpcs = on and mapID or nil, on and RelevantNpcs(mapID).sig or nil
  if wantMap ~= mapSig or wantNpcs ~= mapSigNpcs then provider:RefreshAllData() end
end
ns.WalkMapState = function() return provider and "ready" or (setupFailed and "failed" or "waiting") end -- (/qd diag, tests)
ns.WalkTickMap = TickMap -- (tests)
function ns.RefreshWalks()
  relevant = {}
  if provider and provider:GetMap() then provider:RefreshAllData() end
  ns.SafeCall("walks", UpdateMinimap)
end

ns.OnInit(function()
  SetupMinimap()
  ns.NewTicker(1, function() ns.SafeCall("walks map", TickMap) end)
end)
