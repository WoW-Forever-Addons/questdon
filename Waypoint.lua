local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.27) Optional waypoint export: the spot the arrow points at is also set as
--   * the Blizzard map pin (C_Map.SetUserWaypoint), and / or
--   * a TomTom waypoint (only if TomTom is installed).
-- Both are off by default. The Blizzard pin is only placed on the map; it is
-- NOT super-tracked, because that would switch the super-tracked quest away
-- and the arrow would lose its quest.
---------------------------------------------------------------------------
local INTERVAL = 1
local lastKey          -- "mapID:x:y" of the spot last exported
local lastBlizzard     -- true while our pin is the user waypoint
local lastPin          -- { mapID, x, y } of the pin we set (to tell it from the player's own pin)
local tomtomUID

local function Key(t)
  return ("%d:%.4f:%.4f"):format(t.mapID, t.x, t.y)
end

local function SpotOf(target)
  if type(target) ~= "table" then return nil end
  local m, x, y = ns.Num(target.mapID), ns.Num(target.x), ns.Num(target.y)
  if not (m and x and y) or m <= 0 or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  -- (1.28) the label becomes a TomTom title: a plain, clean string or nothing
  local label = target.label
  if type(label) == "string" and ns.Usable(label) and ns.CleanName then
    label = ns.CleanName(label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  else
    label = nil
  end
  return { mapID = m, x = x, y = y, label = label }
end

-- (1.28) Is the current user waypoint still the one we set? If the player
-- placed their own pin in the meantime, it must not be removed or replaced
-- silently. Unknown (no read API, unreadable) counts as ours.
local function PinIsOurs()
  if not lastPin then return false end
  if not (C_Map and C_Map.GetUserWaypoint) then return true end
  local ok, p = pcall(C_Map.GetUserWaypoint)
  if not ok then return true end
  if p == nil then return false end -- no pin on the map any more
  if type(p) ~= "table" or type(p.position) ~= "table" then return true end
  local m, x, y = ns.Num(p.uiMapID), ns.Num(p.position.x), ns.Num(p.position.y)
  if not (m and x and y) then return true end
  return m == lastPin[1] and math.abs(x - lastPin[2]) < 0.002 and math.abs(y - lastPin[3]) < 0.002
end

local function ClearBlizzard()
  if lastBlizzard and C_Map and C_Map.ClearUserWaypoint and PinIsOurs() then pcall(C_Map.ClearUserWaypoint) end
  lastBlizzard, lastPin = false, nil
end

local function ClearTomTom()
  if tomtomUID and type(TomTom) == "table" and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomUID) end
  tomtomUID = nil
end

local function SetBlizzard(spot)
  if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
  -- (1.28) a spot on a map that cannot take a pin: take our old pin away, do not leave a stale one
  if C_Map.CanSetUserWaypointOnMap and ns.Value(C_Map.CanSetUserWaypointOnMap, spot.mapID) == false then
    ClearBlizzard()
    return false
  end
  -- A new spot replaces the user pin (the option is the player's wish); only
  -- REMOVING a pin is limited to our own (see PinIsOurs).
  local ok = pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(spot.mapID, spot.x, spot.y))
  end)
  lastBlizzard = ok
  lastPin = ok and { spot.mapID, spot.x, spot.y } or nil
  return ok
end

local function SetTomTom(spot)
  if type(TomTom) ~= "table" or not TomTom.AddWaypoint then return false end
  ClearTomTom()
  -- (1.28) only title and persistent: the other options are not documented for sure
  local ok, uid = pcall(TomTom.AddWaypoint, TomTom, spot.mapID, spot.x, spot.y, {
    title = spot.label or "Questdon", persistent = false,
  })
  if ok and uid then tomtomUID = uid end
  return ok and uid ~= nil
end

-- Looks at the arrow's target and exports it when it changed.
function ns.SyncWaypoint()
  local db = ns.db
  if not db then return end
  local blizzard, tomtom = db.exportBlizzardWaypoint, db.exportTomTom
  if not (blizzard or tomtom) then
    if lastKey then ClearBlizzard() ClearTomTom() lastKey = nil end
    return
  end
  local spot = SpotOf(ns.ArrowTarget and ns.ArrowTarget())
  if not spot then
    if lastKey then ClearBlizzard() ClearTomTom() lastKey = nil end
    return
  end
  local key = Key(spot) .. (blizzard and "b" or "") .. (tomtom and "t" or "")
  if key == lastKey then return end
  lastKey = key
  if blizzard then SetBlizzard(spot) else ClearBlizzard() end
  if tomtom then SetTomTom(spot) else ClearTomTom() end
end

function ns.WaypointState()
  return { key = lastKey, blizzard = lastBlizzard and true or false, tomtom = tomtomUID ~= nil }
end

ns.OnInit(function()
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(INTERVAL, function() pcall(ns.SyncWaypoint) end)
  end
end)
