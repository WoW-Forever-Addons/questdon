local _, ns = ...
local C_SuperTrack = ns.ST or C_SuperTrack -- (25.10.2026) Era shims, Core.lua ApiProxy
local L = ns.L

---------------------------------------------------------------------------
-- Direction arrow (TomTom style) for the tracked quest or a clicked map pin.
-- Uses world coordinates of the maps; works in the open world. In instances
-- the client gives no map position, then the arrow hides itself.
-- (DonMap M2, 30.10.2026) The window, the corpse and the compass are DonMap's now (DONCORE_PLAN.md "M2"); here stay
-- Questdon's targets and what the arrow shows for them (QuestView at the end).
---------------------------------------------------------------------------
local ARRIVED_YARDS = 8
local ARRIVED_LEAVE = 15 -- (30.10.2026) arrived stays until this far away (no flicker one step on)
local arrivedAt = { mapID = nil, x = nil, y = nil }
local arrow
local manual -- target set by clicking a pin: { mapID, x, y, label }
local auto   -- target from the tracked quest
local external -- target from another addon (e.g. a leveling guide)

-- (30.10.2026, L3) the geometry (world positions, distance and bearing) is DonData's engine now (DonData/Engine/Geo.lua)
local PlayerWorld, TargetWorld = ns.PlayerWorld, ns.TargetWorld
local function FromPlayer(pc, pn, pw, target) return ns.DistanceFrom(pc, pn, pw, target) end

function ns.NeedleDiag()
  local mapID, x, y = ns.PlayerPosition()
  if not mapID then return "no player position" end
  local function F(v, f) return ns.Num(v) and (f):format(v) or "-" end
  local pc, pn, pw = PlayerWorld()
  local us, uo -- (23.10.) not "a and f()": that keeps only the first value, the order always read nil
  if ns.UnitPositionState then us, uo = ns.UnitPositionState() end
  local fac = ns.Num(ns.Value(GetPlayerFacing))
  local s = ("player map %s at %s %s, world %s %s %s, unitpos %s/%s, facing %s"):format(tostring(mapID), F(x, "%.4f"),
    F(y, "%.4f"), tostring(pc), F(pn, "%.0f"), F(pw, "%.0f"), tostring(us), tostring(uo),
    fac and F(math.deg(fac), "%.0f") or "-")
  local tg = ns.ArrowTarget and ns.ArrowTarget()
  if not tg then return s .. "; no target" end
  -- which source wins (Target(): corpse, clicked pin, another addon's guide, the tracked quest)
  local g = ns.guideFrame
  local guideShown = not (type(g) == "table" and g.IsShown and not g:IsShown())
  s = s .. "; source " .. ((ns.CorpseTarget and ns.CorpseTarget()) and "corpse" or manual and "clicked pin"
    or (external and guideShown) and "guide (another addon)" or auto and "tracked quest" or "other")
  s = s .. ("; tracked quest %s, target quest %s"):format(tostring(ns.Num(ns.Value(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID))), tostring(tg.questID))
  local tc, tn, tw = TargetWorld(tg)
  local dist, bearing = FromPlayer(pc, pn, pw, tg)
  s = s .. ("; target map %s at %s %s, world %s %s %s"):format(tostring(tg.mapID), F(tg.x, "%.4f"), F(tg.y, "%.4f"),
    tostring(tc), F(tn, "%.0f"), F(tw, "%.0f"))
  s = s .. ("; distance %s, bearing %s"):format(F(dist, "%.0f"), bearing and F(math.deg(bearing), "%.0f") or "-")
  local way = ns.ArrowWay and ns.ArrowWay()
  if way and way.wp then s = s .. ("; way point map %s %s %s"):format(tostring(way.wp.mapID), F(way.wp.x, "%.4f"), F(way.wp.y, "%.4f")) end
  return s
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
  -- (26.10.2026, Daniel: "wo der Pfeil anderswo nicht so läuft") a dungeon quest whose objectives lie inside: the
  -- entrance, as long as you are not in that dungeon (before: no target, Era has no quest points of the game)
  local inst = (open > 0 or total == 0) and ns.QuestDungeon and ns.QuestDungeon(questID)
  if inst and not (ns.CurrentDungeon and ns.CurrentDungeon() == inst) and ns.DungeonEntrance then
    local em, ex, ey = ns.DungeonEntrance(inst)
    if em and ex then
      pts[1] = { mapID = em, x = ex, y = ey, kind = "entrance", inst = inst }
      return pts
    end
  end
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

-- (1.3.6) The nearest known point of a quest (the arrow's choice for it) and its distance; for the
-- quest list (Tracker.lua). nil for a quest that completes from the log or has no point.
-- (Questdon review 2) The list asks for every quest each second (3 MB of new point tables a second with 20
-- quests): a quest's points are kept until the quest log, the bags or the game's quest points change, the
-- zone changes, or 5 seconds passed; only the distances are measured again.
-- (review 3: still rebuilt after every loot and log update, 10 ms a second) kept per quest while its state is the
-- same: complete, failed, which objectives are done, the game's point, learned and shared data; quests whose places
-- depend on the bags (an item to use, an item still to get) are worked out again after a bag change; 30 s at most.
local nearCache, nearAt, nearSig, nearBags = {}, {}, {}, {}
local function ForgetNear() nearCache, nearAt, nearSig, nearBags = {}, {}, {}, {} end
for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do ns.On(e, ForgetNear) end
ns.On("BAG_UPDATE_DELAYED", function()
  for q in pairs(nearBags) do nearCache[q] = nil end
  nearBags = {}
end)
ns.ForgetNearestPoints = ForgetNear -- (learned data, tests)
-- (30.10.2026, L4) the state a quest's places depend on (ns.QuestStampFill, ns.QuestStampSame, ns.QuestStampWhy) is
-- DonData's engine now (DonData/Engine/API.lua): its API keeps Leveldon's places by it also without Questdon
local StampFill, StampSame = ns.QuestStampFill, ns.QuestStampSame
-- (16.10. evening, Daniel's /qd mem: 1.0 to 1.5 MB of new memory a second, Questie 6 KB) the arrow's own target
-- (BuildAuto, NextAuto) took the quest's places anew at every update: all spawns as new tables. It shares these.
local nearSpecial = {}
local NEAR_SECS = 300
local function CachedPoints(questID)
  local now = ns.Num(ns.Value(GetTime)) or 0
  local points = nearCache[questID]
  -- (18.10., Daniel's /qd mem standing: the list's nearest points 30 KB a second, 0.3 new point sets a second = every
  -- quest anew each 30 s) the state stamp, the bags and the zone catch every change; the time is only a safety net
  if points == nil or not ns.MemPart("near stamp", StampSame, questID, nearSig[questID]) or now - (nearAt[questID] or 0) > NEAR_SECS or now < (nearAt[questID] or 0) then
    ns.MemCount("near points new")
    if points ~= nil then ns.QuestStampWhy(questID, nearSig[questID], "near points new")
    elseif ns.MemProfiling and ns.MemProfiling() then ns.MemCount(nearSig[questID] and "near points new: bags or zone" or "near points new: first") end
    local special
    points, special = QuestPoints(questID)
    if special == "autocomplete" or type(points) ~= "table" then points = false end
    nearSpecial[questID] = special
    nearCache[questID], nearAt[questID] = points, now
    nearSig[questID] = StampFill(questID, nearSig[questID] or {})
    local bags = points == false or #points == 0
    for _, p in ipairs(points or {}) do if p.useSpot or p.needsItem then bags = true break end end
    -- (review 4) each point's world position once, not every second (3700 conversions a tick with 28 quests)
    for _, p in ipairs(points or {}) do
      if p.mapID and p.x and p.y then
        local c, n, w = ns.WorldPos(p.mapID, p.x, p.y)
        if c then p._wc, p._wn, p._ww = c, n, w end
      end
    end
    nearBags[questID] = bags or nil
  end
  return points, nearSpecial[questID]
end
function ns.QuestNearestPoint(questID)
  local points = CachedPoints(questID)
  if not points then return nil end
  return ns.MemPart("near nearest", Nearest, points)
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

-- (1.3.8, F10) Far from the objective area the arrow leads to where the spots are many (a group of spawns near
-- you), not to a lone spawn that happens to be a little nearer: each of the CLUSTER_CAND nearest spots scores its
-- neighbours within CLUSTER_R yards against its distance. Close by (CLUSTER_FAR) the nearest spot wins as before.
-- The current target stays unless another spot scores a quarter better.
local CLUSTER_R, CLUSTER_FAR, CLUSTER_CAND = 70, 150, 30
-- (23.10., Daniel's /qd mem with Leveldon's target far from its places: arrow 15 KB a second) the spots and their
-- distances in three kept arrays, sorted by index with one comparator: no table per spot and call any more
local clPts, clD, clIdx = {}, {}, {}
local function ByDist(a, b) return clD[a] < clD[b] end
local function Cluster(t, pc, pn, pw)
  local np = 0
  for _, p in ipairs(t.points) do
    if not p._wc and p.mapID and p.x and p.y then
      local c, n, w = ns.WorldPos(p.mapID, p.x, p.y)
      if c then p._wc, p._wn, p._ww = c, n, w end
    end
    if p._wc == pc then
      local dn, dw = p._wn - pn, p._ww - pw
      np = np + 1
      clPts[np], clD[np], clIdx[np] = p, math.sqrt(dn * dn + dw * dw), np
    end
  end
  for k = np + 1, #clIdx do clPts[k], clD[k], clIdx[k] = nil, nil, nil end
  if np < 4 then
    for k = 1, np do clPts[k] = nil end
    return nil
  end
  table.sort(clIdx, ByDist)
  local r2 = CLUSTER_R * CLUSTER_R
  local best, bestScore, curScore
  for k = 1, math.min(np, CLUSTER_CAND) do
    local i = clIdx[k]
    local cp = clPts[i]
    local n = 0
    for j = 1, np do
      local q = clPts[j]
      local dn, dw = q._wn - cp._wn, q._ww - cp._ww
      if dn * dn + dw * dw <= r2 then n = n + 1 end
    end
    local score = n / (clD[i] + 150) -- n counts the spot itself
    if not bestScore or score > bestScore then best, bestScore = i, score end
    if cp.mapID == t.mapID and cp.x == t.x and cp.y == t.y then curScore = score end
  end
  local bp, bd = best and clPts[best], best and clD[best]
  for k = 1, np do clPts[k] = nil end -- (the old target's spots are not kept alive)
  if not best then return nil end
  if curScore and curScore * 1.25 >= bestScore then return nil, true end
  return bp, bd
end
ns.ArrowCluster = Cluster -- (tests)

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
  local pick, pickDist, far = best, bestDist, false
  if best and (curDist or bestDist) > CLUSTER_FAR and not area.inside and ns.db.arrowClusters ~= false then
    local c, cd = Cluster(t, pc, pn, pw)
    if c then pick, pickDist, far = c, cd, true
    elseif cd == true then pick = nil end -- the current target is still as good: kept
  end
  if pick and (far or not curDist or pickDist < curDist - SWITCH_YARDS) then
    t.mapID, t.x, t.y, t.source, t.label = pick.mapID, pick.x, pick.y, pick.source, t.LabelFor and t.LabelFor(pick) or t.label
    t.creature, t.index = pick.creature, pick.index
    t.cluster = far or nil -- (review 6) picked as a group: kept when the target is built anew
    curDist = pickDist
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

-- (1.3.5, Daniel 09.10.: after a turn-in the arrow was gone and a new target had to be picked) nothing
-- tracked: the arrow moves on by itself, to the nearest turn-in of a finished quest, or to an open
-- objective close by when that is nearer. A click on the arrow puts this aside until the quest log changes.
local NEXT_NEAR = 400 -- yards: an open objective counts as "close by"
local nextDismissed -- quest log signature when the player clicked the "next" target away
local function LogSignature()
  local parts = {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    local id = info.questID
    if id then parts[#parts + 1] = id .. (ns.IsQuestComplete(id) and "c" or "") end
  end
  return table.concat(parts, ",")
end
local nextCache, nextAt, nextSig = nil, -10, nil
local function NextAuto()
  if ns.db.arrowNext == false then return nil end
  local sig = LogSignature()
  if nextDismissed and nextDismissed == sig then return nil end
  nextDismissed = nil
  -- every quest's places: at most every 2 seconds, at once when the log changed
  local now = ns.Num(ns.Value(GetTime)) or 0
  if sig == nextSig and now - nextAt < 2 then return nextCache end
  nextSig, nextAt = sig, now
  nextCache = nil
  local best, bestD, bestID
  -- (24.10., reviewer c: "blank compass on the card when every objective is more than 400 yards away") the nearest open
  -- objective of a quest in the log at any distance: used only when no turn-in and nothing close by was found
  local far, farD, farID, bestPts, farPts
  local hidden = ns.TrackerHidden and ns.TrackerHidden() or {}
  for _, info in ipairs(ns.QuestLogEntries()) do
    local id = info.questID
    -- (Questdon review 4) not a quest you hid from the quest list
    if id and not ns.IsQuestFailed(id) and not hidden[id] then
      local points, special = CachedPoints(id)
      if points and special ~= "autocomplete" then
        local p, d = Nearest(points)
        if p and d then
          local finished = p.kind == "turnin" or p.kind == "guess"
          if (finished or d <= NEXT_NEAR) and (not bestD or d < bestD) then best, bestD, bestID, bestPts = p, d, id, points end
          if not finished and (not farD or d < farD) then far, farD, farID, farPts = p, d, id, points end
        end
      end
    end
  end
  if not best then best, bestD, bestID, bestPts = far, farD, farID, farPts end
  if not best then return nil end
  local title = ns.QuestTitle(bestID)
  local label = (best.kind == "turnin" or best.kind == "guess") and L["Turn in: %s"]:format(title) or title
  nextCache = { mapID = best.mapID, x = best.x, y = best.y, label = L["Next: %s"]:format(label), questID = bestID, next = true }
  -- (30.10.2026, Daniel at Kobold Candles with no quest picked: the arrow went from mob to mob, "Arrived" and one step
  -- on the next one) a kill or collect objective brings its places here too, so its area counts as for a picked quest
  if best.area and type(bestPts) == "table" then
    local list = {}
    for _, q in ipairs(bestPts) do if q.area then list[#list + 1] = q end end
    nextCache.points = list
  end
  return nextCache
end
function ns.DismissNextTarget() nextDismissed = LogSignature() end

local function BuildAuto()
  local prev = auto
  auto = nil
  if not (ns.ArrowRuns and ns.ArrowRuns() and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then return end
  local questID = ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  if not questID or questID == 0 or not ns.InQuestLog(questID) then auto = NextAuto() return end
  local points, special = CachedPoints(questID)
  if special == "autocomplete" then
    auto = { label = L["%s: complete it from the quest log"]:format(ns.QuestTitle(questID)), questID = questID }
    return
  end
  points = points or {}
  local p = Nearest(points)
  local kept
  -- (review 6) built anew (ticker, loot, bags): the spot picked before stays the start (its group, the quarter rule)
  if p and prev and prev.questID == questID and prev.points and prev.cluster then
    for _, q in ipairs(points) do if q.mapID == prev.mapID and q.x == prev.x and q.y == prev.y then p, kept = q, true break end end
  end
  -- (Questdon review 5) all of the quest's places on another continent: the first one, so the arrow and the card say
  -- "Other zone or no position" instead of nothing
  if not p and type(points) == "table" and points[1] and points[1].mapID then p = points[1] end
  if p then
    local title = ns.QuestTitle(questID)
    local function LabelFor(q)
      if q.kind == "turnin" then return L["Turn in: %s"]:format(title)
      elseif q.kind == "guess" then return L["Turn in (probably): %s"]:format(title)
      elseif q.kind == "failed" then return L["Quest failed: %s"]:format(title)
      elseif q.kind == "start" then return L["%s: starts at the quest giver"]:format(title)
      elseif q.kind == "entrance" then return title .. " (" .. L["Entrance: %s"]:format(ns.DungeonName(q.inst)) .. ")"
      elseif q.needsItem then return L["%s: first get %s"]:format(title, ns.ItemName(q.needsItem)) end
      return title
    end
    auto = { mapID = p.mapID, x = p.x, y = p.y, label = LabelFor(p), questID = questID, source = p.source,
      creature = p.creature, index = p.index, cluster = kept }
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
  -- a new target sits on the nearest spot: pick again at the next update (a group of spots far away), not after
  -- AREA_CHECK
  if auto and auto.points then area.checkAt = nil end
  -- (1.26) no area for this target (turn-in, exact spot, nothing tracked): leave the area state
  if not (auto and auto.points) and area.inside then
    area.inside, area.reason = false, nil
    if ns.QueueRefresh then ns.QueueRefresh("panel") end
  end
end

-- (1.2) The quest you track (super-tracked) when a target was clicked: picking
-- another quest in the log or the tracker afterwards drops the clicked target,
-- so the arrow follows your choice again.
local function Tracked()
  local id = C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  return id or 0
end
-- (1.3.5) kind (optional): what the target is ("entrance": a marked dungeon entrance, Dungeons.lua)
-- spot (1.3.8): the clicked pin's { creature = , index = } (an object to click there).
function ns.SetArrowTarget(mapID, x, y, label, kind, questID, spot)
  questID = ns.Num(questID)
  manual = { mapID = mapID, x = x, y = y, label = label, tracked = Tracked(), kind = kind, questID = questID,
    inLog = questID and ns.InQuestLog(questID) or nil,
    creature = type(spot) == "table" and spot.creature or nil, index = type(spot) == "table" and spot.index or nil }
  if ns.OfferArrowTarget then ns.OfferArrowTarget() end -- (DonMap M2) the newest click at DonMap
  if arrow and ns.ArrowRuns() then arrow:Show() end
end

function ns.ClearArrow()
  manual = nil
end

-- (1.3.8, F2) At an object's spot: what to click there ("Here: click the objects for Sack of Grain"); nil for mobs.
function ns.ArrivedText(t)
  if type(t) ~= "table" or not ns.IsObjectSpot(t.creature) then return nil end
  local thing = t.questID and t.index and ns.ObjectiveThing(t.questID, t.index)
  return thing and L["Here: click the objects for %s"]:format(thing) or L["Here: click the quest objects"]
end

-- Another addon (QuestdonAPI) can point the arrow; a clicked pin still wins.
function ns.SetExternalArrowTarget(target)
  external = target
  -- (1.3.6) a guide's new area target: look at its spots at once (else the needle shows for a moment)
  if type(target) == "table" and target.area then area.checkAt = nil end
  if target and ns.OfferArrowTarget then ns.OfferArrowTarget() end -- (DonMap M2) the newest guide step at DonMap
  if target and arrow and ns.ArrowRuns() then arrow:Show() end
end

-- (1.2) Dead and released (a ghost): the arrow leads back to your corpse. (DonMap M2, 30.10.2026) DonMap does it now
-- (Arrow.lua there, with Questdon's option arrowCorpse); Questdon asks it.
local DM = DonMapAPI
function ns.CorpseTarget() return DM.CorpseTarget() end

-- (DonMap M2) Questdon's own target for DonMap's arrow: a clicked pin (click), a guide's step that came through
-- QuestdonAPI (guide), the tracked quest or the next one (auto). The corpse and other addons' targets are DonMap's.
local function OwnTarget()
  if manual and manual.tracked ~= Tracked() then manual = nil end -- (1.2) another quest picked
  -- (Questdon review 4) a clicked pin of a quest: gone once the quest is turned in or abandoned, a clicked objective
  -- dot once the quest is finished (the compass led there for good, the arrow's right-click is hidden with it)
  local mq = manual and manual.questID
  if mq and ((manual.kind == "available" and ns.IsQuestDone(mq)) or (manual.inLog and not ns.InQuestLog(mq))
      or (manual.inLog and manual.kind == "objective" and ns.IsQuestComplete(mq))) then
    manual = nil
  end
  -- (Questdon review 5) a clicked dot of an objective that is done now (the quest's other objectives still open)
  if manual and mq and manual.kind == "objective" and manual.index and ns.ClientObjectives then
    local o = ns.ClientObjectives(mq)[manual.index]
    if type(o) == "table" and ns.True(o.finished) then manual = nil end
  end
  if manual then return manual, DM.PRIO.click end
  -- (Questdon review 3) the guide's step only while its window is shown (Leveldon closed: your own quest)
  local ext, g = external, ns.guideFrame
  if ext and type(g) == "table" and g.IsShown and not g:IsShown() then ext = nil end
  if ext then return ext, DM.PRIO.guide end
  if auto then return auto, DM.PRIO.auto end
  return nil
end
-- a new click or guide step is the newest among equals at DonMap (a guild member clicked before stays below it)
local function Offer() DM.SetArrowProvider("questdon", OwnTarget) end
Offer()
ns.OfferArrowTarget = Offer

-- What the arrow follows now, from whichever addon: DonMap's choice (the corpse first).
local function Target() return (DM.ArrowTarget()) end
ns.ArrowTarget = Target

---------------------------------------------------------------------------
-- (DonMap M2) The window (needle, seal, plaque, position, size, look) is DonMap's now (DonMap/Arrow.lua, frame
-- DonMapArrow, also known as QuestdonArrow). Questdon controls it: its settings (QuestdonDB, same keys), when it runs
-- and when it draws nothing (the quest list's compass, a guide), and what it shows for a target (QuestView below:
-- objective area, the way around, caves, what to click at an object's spot).
---------------------------------------------------------------------------
-- (1.3.6, Daniel 12.10.: "the arrow built into the window") what the arrow shows, for the compass in the quest list
-- (Tracker.lua): DonMap's own state table (QuestdonAPI.ArrowState hands out a copy).
function ns.ArrowState() return DM.ArrowStateRaw() end
-- (1.3.7, Daniel 13.10.: "by default the compass in the list and the arrow off; switch the list's compass off and
-- the old arrow comes back; both at the same time must be possible") the arrow works whenever someone needs its
-- target (its own window, the list's compass, a guide), but draws only when its window is switched on and no
-- guide (Leveldon) shows the way
local function Runs()
  return ns.db.arrow or (ns.TrackerCompassActive and ns.TrackerCompassActive()) or (ns.GuideActive and ns.GuideActive()) or false
end
ns.ArrowRuns = Runs
local function Ghost() return (ns.GuideActive and ns.GuideActive()) or not ns.db.arrow or false end
ns.ArrowGhost = Ghost

-- (Questdon review 3) "240 yards, the way around" in its parts, in every language: the plain distance (the
-- "%d yards" text of the number) and the rest when the text starts with it; else the whole text and no way
function ns.SplitDistance(full, dist)
  if type(full) ~= "string" then return nil, nil end
  dist = dist or tonumber(full:match("%d+"))
  if not dist then return full, nil end
  local short = L["%d yards"]:format(dist)
  if full == short then return short, nil end
  -- (review 4) only with a separator after it: "240 m" is no prefix of "240 mètres, ..."
  local rest = full:sub(#short + 1)
  if full:sub(1, #short) == short and (rest == "" or rest:find("^[%s,，、:：]")) then
    local way = rest:gsub("^[%s,，、:：]+", "")
    return short, way ~= "" and way or nil
  end
  return full, nil
end

local arrowWay = {}
-- (11.10.) what the needle follows now, for the dots on the map and minimap (PathDots.lua); empty when the arrow
-- shows another target now (or none)
function ns.ArrowWay()
  if arrowWay.t and arrowWay.t ~= DM.ArrowStateRaw().t then arrowWay.t, arrowWay.wp, arrowWay.cave = nil, nil, nil end
  return arrowWay
end

-- One view table, filled anew at each update (33 times a second, no new table each time).
local qv = {}
local function View(mode, label, text, color, dist, bearing)
  qv.mode, qv.label, qv.text, qv.color, qv.dist, qv.bearing = mode, label, text, color, dist, bearing
  qv.needleBearing, qv.distShort, qv.distWay = nil, nil, nil
  return qv
end

local function QuestView(t)
  arrowWay.t, arrowWay.wp, arrowWay.cave = nil, nil, nil
  -- nothing to walk to (a quest that completes from the log): text only
  if not t.mapID then return View("text", t.label, "") end
  -- (1.25) objective area of the tracked quest (auto target only)
  -- (1.3.6, Daniel 11.10.: "the arrow confuses when you are in the area killing the mobs") also for a
  -- guide's target that brings its objective places (QuestdonAPI.SetArrowTarget { area = true, points })
  local inArea = false
  if (t == auto or (t == external and t.area and t.questID)) and t.points then
    CheckArea(t)
    inArea = area.inside
  end
  local dist, bearing = ns.DistanceAndBearing(t)
  -- (Daniel 12.10.: "the arrow towards the quest target, the minimap shows where to walk") the compasses in
  -- the windows point at the target itself; the way around stays on the map's dots (and this arrow)
  -- (11.10., Daniel: the quest deep in the cave) the target inside a cave or building you are not in: first to
  -- its way in (you are not in the objective area while outside, even right above it)
  local cave = ns.PathCave and ns.PathCave(t) or nil
  if cave then inArea = false end
  if inArea then
    if not dist or dist <= AREA_ENTER then
      return View("seal", t.label, ns.ArrivedText(t) or L["In the objective area"], "good", dist, bearing)
    end
    local v = View("needle", t.label, L["In the objective area, nearest spot %d yards"]:format(dist), "good", dist, bearing)
    -- (24.10., Daniel's picture 17.10.: "In the objective area, nearest s..." cut off in Leveldon's window) the
    -- distance and the area hint apart for the cards (Leveldon's station, Questdon's quest card): "52 yards" under the
    -- compass, "In the objective area" in the hint line, both short enough for their lines
    v.distShort, v.distWay = L["%d yards"]:format(dist), L["In the objective area"]
    return v
  end
  if not dist then return View("text", t.label, L["Other zone or no position"], "textHint", nil, bearing) end
  -- (30.10.2026, Daniel: "angekommen, aber wenn man einen Schritt weiter geht, sagt er wieder zurück") arrived stays
  -- until you are ARRIVED_LEAVE yards away from the same place
  local here = arrivedAt.mapID == t.mapID and arrivedAt.x == t.x and arrivedAt.y == t.y
  if dist < ARRIVED_YARDS or (here and dist < ARRIVED_LEAVE) then
    arrivedAt.mapID, arrivedAt.x, arrivedAt.y = t.mapID, t.x, t.y
    local hint = ns.ArrivedText(t)
    -- a clicked object: kept while you stand there (the hint), dropped once you walk on
    if manual == t then if hint then t.arrived = true else manual = nil end end
    return View("seal", t.label, hint or L["Arrived"], "good", dist, bearing)
  end
  if manual == t and t.arrived and dist > 30 then manual = nil end
  -- (1.3.6, Daniel: "with mountains in the way I have to run around") a known way around (Paths.lua): the
  -- needle points at its next waypoint, the distance stays the target's
  local nb = bearing
  local wp = cave or (dist > 60 and ns.PathNext and ns.PathNext(t)) or nil
  if wp then
    local _, wb = ns.DistanceAndBearing(wp)
    if wb then nb = wb else wp, cave = nil, nil end
  end
  arrowWay.t, arrowWay.wp, arrowWay.cave = wp and t or nil, wp, cave and true or nil
  local fmt = (cave and L["%d yards, first to the way in"]) or (wp and L["%d yards, the way around"]) or L["%d yards"]
  local v = View("needle", t.label, fmt:format(dist), "textSecondary", dist, bearing)
  v.needleBearing = nb
  -- (Questdon review 3) the distance and the way apart for the quest list's card (it parsed the translated text:
  -- "240 yards," kept its comma, zhTW showed the way twice): the plain distance, and the rest of the text when it
  -- starts with it
  v.distShort, v.distWay = ns.SplitDistance(fmt:format(dist), dist)
  return v
end

DM.SetArrowControl("questdon", {
  title = "Questdon",
  L = ns.L, -- the arrow's own words (Distance, Arrived, ...) in all of Questdon's languages
  look = function() return ns.db end,
  runs = Runs,
  ghost = Ghost,
  view = QuestView,
  tooltip = function(t, lines)
    if t == auto and t.points and area.inside then
      lines[#lines + 1] = { L["In the objective area"], area.reason == "mob" and L["quest mobs nearby"] or L["near a known spot"], "good" }
    end
  end,
  -- right-click: drop Questdon's clicked target (or put the next quest aside); another addon's click DonMap drops
  onRightClick = function(t, source)
    if source ~= "questdon" and source ~= "corpse" then return end
    if t and t == auto and auto.next then ns.DismissNextTarget() end
    ns.ClearArrow() ns.UpdateArrowTarget()
  end,
})

-- (1.3.6, Daniel 12.10.) the compass for windows is DonMap's now (DonMapAPI.NewCompass)
function ns.NewCompass(parent, size) return DM.NewCompass(parent, size) end

local function Create()
  arrow = DM.CreateArrow()
  QuestdonArrow = arrow -- the old name (macros, other addons, the tests)
  ns.ApplyArrowLook()
end

-- Options (Appearance page): size, plate opacity, combat dimming, shown. DonMap reads them from QuestdonDB.
function ns.ApplyArrowLook()
  if not arrow then return end
  DM.ApplyArrow()
end

function ns.ResetArrowPosition()
  ns.db.arrowPos = nil
  DM.ResetArrowPosition()
end

function ns.ApplyArrow()
  ns.ApplyArrowLook()
  ns.UpdateArrowTarget()
end

function ns.ToggleArrow()
  ns.db.arrow = not ns.db.arrow
  ns.db.arrowAuto = nil -- (review 4) your choice, kept when the quest list comes back
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
