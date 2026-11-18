local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (10.11.2026, Daniel: "eine Art TomTom ... wenn ich /way und dann die Koordinate schreibe, dann soll es auch dahin
-- gehen ... der Marker sichtbar, bis ich den wegklicke oder das Ziel erreicht habe ... wenn man hinter Way noch was
-- schreibt, dann soll das auch unter unserem Pfeil stehen") A small /way, kept lean on purpose: no switch, nothing
-- saved. Each waypoint has a marker on the world map and the minimap (MapPins.lua, Minimap.lua).
-- (11.11.2026, Daniel: "wenn ich nach und nach mehrere Waypoints mache, dann verschwindet der erste. Das soll schon so
-- bleiben, bis ich das wegklicke" and "in einem Chat ganz viele Waypoints schreiben") Several waypoints stand side by
-- side; each goes within WAY_NEAR yards of its spot or from the menu of a right-click on its marker (this one, those of
-- the zone, all), all also with "/way clear". The
-- arrow leads to the one set last (or clicked), after that to the nearest that is left. Many at once: several
-- "/way ..." in one line, or the window of "/way" without anything (the chat line takes 255 letters only).
--   /way 45.2 61.8 [text]          the zone you are in
--   /way <zone> 45.2 61.8 [text]   a zone by its name (or the start of it), or #<uiMapID>
--   /way                            the window to paste many lines
--   /way clear
-- (13.11.2026, Daniel: after an update's /reload "die waypoints sind verschwunden", kept per character) The list is
-- QuestdonCharDB.ways itself ({ mapID, x, y, label } each), so it survives a /reload and a logout; after a login the
-- markers are back, the arrow is not taken (a click on a marker takes it).
-- With TomTom loaded "/way" stays TomTom's; "/qd way ..." always works.
---------------------------------------------------------------------------
local WAY_NEAR, WAY_MAX = 15, 100
ns.WAY_ICON = "Interface\\AddOns\\Questdon\\Media\\qd_way" -- (11.11.2026, Daniel: an own pin, drawn with Google Flow in the style of our logos)
ns.WAY_PIN_SIZE = 22 -- world map; (11.11.2026, Daniel: "die Größe ist sehr groß")
local ways, lead, ticker = {}, nil, nil
local stats = { set = 0, removed = 0, last = nil }
-- (11.11.2026, Daniel: "in den Optionen die Größe des Pins einstellbar") option wayPinScale, 50 to 300 %, on top of the
-- pin sizes of the map and the minimap
function ns.WayPinScale() return math.max(0.5, math.min(3, tonumber(ns.db and ns.db.wayPinScale) or 1)) end
function ns.Way() return lead end -- the one the arrow leads to
function ns.Ways() return ways end
function ns.WayStats() return stats end

local function RefreshViews()
  if ns.RefreshPins then ns.RefreshPins() end
end

local function ArrowOnWay()
  local t = ns.ArrowTarget and ns.ArrowTarget()
  return t and t.kind == "way" or false
end

local function Point(w)
  if not (w and ns.SetArrowTarget) then return end
  if ns.EnsureArrow then ns.EnsureArrow() end
  ns.SetArrowTarget(w.mapID, w.x, w.y, w.label, "way")
end

-- the nearest waypoint: of the zone you are in first, then any whose distance can be told, else the oldest
local Here -- set further down
local function Nearest()
  local here = Here()
  local best, bestD, bestHere
  for _, w in ipairs(ways) do
    local d = ns.DistanceAndBearing and ns.Num((ns.DistanceAndBearing(w)))
    local same = w.mapID == here
    if d and (not best or (same and not bestHere) or (same == bestHere and d < bestD)) then
      best, bestD, bestHere = w, d, same
    end
  end
  return best or ways[1]
end

-- The arrow leads to w (a click on its marker).
function ns.PickWay(w)
  for _, x in ipairs(ways) do
    if x == w then lead = w Point(w) return true end
  end
  return false
end

-- Removes one waypoint (w), or the one the arrow leads to.
function ns.RemoveWay(reason, w)
  w = w or lead
  local at
  for i, x in ipairs(ways) do if x == w then at = i break end end
  if not at then return false end
  local onWay = ArrowOnWay()
  table.remove(ways, at)
  stats.removed, stats.last = stats.removed + 1, reason or "?"
  if w == lead then
    lead = Nearest()
    if onWay then
      if lead then Point(lead)
      elseif ns.ClearArrow then
        ns.ClearArrow()
        if ns.UpdateArrowTarget then ns.UpdateArrowTarget() end
      end
    end
  end
  if #ways == 0 and ticker then ticker:Cancel() ticker = nil end
  RefreshViews()
  return true
end

function ns.ClearWays(reason)
  if #ways == 0 then return false end
  local onWay = ArrowOnWay()
  stats.removed, stats.last = stats.removed + #ways, reason or "?"
  for i = #ways, 1, -1 do ways[i] = nil end -- the same table stays: it is the saved one
  lead = nil
  if ticker then ticker:Cancel() ticker = nil end
  if onWay and ns.ClearArrow then
    ns.ClearArrow()
    if ns.UpdateArrowTarget then ns.UpdateArrowTarget() end
  end
  RefreshViews()
  return true
end

-- Removes the waypoints of one map.
function ns.RemoveWaysOfMap(mapID, reason)
  local n = 0
  for i = #ways, 1, -1 do
    if ways[i] and ways[i].mapID == mapID and ns.RemoveWay(reason or "zone", ways[i]) then n = n + 1 end
  end
  return n
end

-- (11.11.2026, Daniel: "mit Rechtsklick auf einem Pin ein Optionsfeld: Marker löschen, alle Marker löschen und Marker
-- der Zone löschen") the menu of a pin (right-click on the world map or the minimap). Returns its entries.
local lastMenu
function ns.WayMenuItems() return lastMenu end -- (tests)
function ns.WayMenu(w)
  if type(w) ~= "table" then return nil end
  local items = {
    { text = L["Remove this waypoint"], onClick = function() ns.RemoveWay("pin", w) end },
    { text = L["Remove the waypoints of this zone"], onClick = function() ns.RemoveWaysOfMap(w.mapID, "zone") end },
    { text = L["Remove all waypoints"], onClick = function() ns.ClearWays("menu") end },
  }
  lastMenu = items
  local ok, lib = pcall(LibStub, "DonCore-1.0")
  local Kit = ok and lib and lib:Get("Kit", 3)
  if Kit and Kit.Menu then pcall(Kit.Menu, w.label, items) end
  return items
end

local function Check()
  for i = #ways, 1, -1 do
    local w = ways[i]
    local dist = w and ns.DistanceAndBearing and ns.DistanceAndBearing(w)
    if dist and dist <= WAY_NEAR then ns.RemoveWay("arrived", w) end
  end
end
ns.CheckWay = Check

-- x, y: 0-1 map coordinates. The waypoint when set; the arrow and the views are the caller's.
local function Add(mapID, x, y, label)
  mapID, x, y = ns.Num(mapID), ns.Num(x), ns.Num(y)
  if not (mapID and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  if type(label) ~= "string" or label == "" then label = ("%.1f, %.1f"):format(x * 100, y * 100) end
  for _, w in ipairs(ways) do -- the same spot again: its text is the new one
    if w.mapID == mapID and math.abs(w.x - x) < 0.0005 and math.abs(w.y - y) < 0.0005 then w.label = label return w end
  end
  if #ways >= WAY_MAX then return nil end
  local w = { mapID = mapID, x = x, y = y, label = label }
  ways[#ways + 1] = w
  stats.set = stats.set + 1
  if not ticker then ticker = ns.NewTicker(1, Check) end
  return w
end

-- The saved waypoints of this character come back (at the start), and from here on the list is the saved one.
-- Returns how many came back.
function ns.LoadWays()
  local cdb = ns.charDB
  if type(cdb) ~= "table" then return 0 end
  local saved, n = cdb.ways, 0
  if type(saved) == "table" and saved ~= ways then
    for _, s in ipairs(saved) do
      if type(s) == "table" and Add(s.mapID, s.x, s.y, s.label) then n = n + 1 end
    end
  end
  cdb.ways = ways
  if n > 0 then
    lead = lead or Nearest()
    RefreshViews()
  end
  return n
end

function ns.SetWay(mapID, x, y, label)
  local w = Add(mapID, x, y, label)
  if not w then return false end
  lead = w
  Point(w)
  RefreshViews()
  return true
end

-- The markers for a map (MapPins.lua, Minimap.lua), or nil.
function ns.WayPins(mapID)
  local out
  for _, w in ipairs(ways) do
    if w.mapID == mapID then
      out = out or {}
      out[#out + 1] = { kind = "way", name = w.label, x = w.x, y = w.y, way = w, text = tostring(ns.WayPinScale()) } -- text: a new size draws anew
    end
  end
  return out
end

function ns.WayPinTooltip(pin)
  local lines = {}
  if pin then lines[1] = { L["Location"], ("%.1f, %.1f"):format((pin.x or 0) * 100, (pin.y or 0) * 100) } end
  return pin and pin.name or "?", lines, L["Click: arrow, right-click: remove waypoints"]
end

---------------------------------------------------------------------------
-- The command
---------------------------------------------------------------------------
local function Number(s)
  if type(s) ~= "string" or not s:match("^%d+[.,]?%d*$") then return nil end
  return tonumber((s:gsub(",", ".")))
end

-- "zone 45.2 61.8 text" -> zone (or nil), x, y (0-100), text (or nil); nil when there are no two numbers.
-- Taken as numbers: "45 58", "45.2 61.8", "45,2 61,8", "45.2, 61.8", "45.2,61.8", "45,58", "45/58", "45.2; 61.8".
function ns.ParseWay(msg)
  local tokens = {}
  for tok in tostring(msg or ""):gsub("(%d)%s*[/;]%s*(%d)", "%1 %2"):gmatch("%S+") do
    local a, b = tok:match("^(%d+%.?%d*),(%d+%.?%d*)$") -- "45.2,61.8" in one piece
    if a and tok:find(".", 1, true) then -- without a point "45,2" is a decimal comma
      tokens[#tokens + 1] = { text = a, num = tonumber(a) }
      tokens[#tokens + 1] = { text = b, num = tonumber(b) }
    else
      tokens[#tokens + 1] = { text = tok, num = Number((tok:gsub(",$", ""))) }
    end
  end
  -- "45,58" alone (no second number next to it): two whole numbers, not 45.58
  local pair
  for i = 1, #tokens do
    local t = tokens[i]
    if t.num and ((tokens[i - 1] and tokens[i - 1].num) or (tokens[i + 1] and tokens[i + 1].num)) then pair = true end
  end
  if not pair then
    for i = 1, #tokens do
      local a, b = tokens[i].text:match("^(%d+),(%d+)$")
      if a then
        tokens[i] = { text = a, num = tonumber(a) }
        table.insert(tokens, i + 1, { text = b, num = tonumber(b) })
        break
      end
    end
  end
  for i = 1, #tokens - 1 do
    if tokens[i].num and tokens[i + 1].num then
      local zone, text = {}, {}
      for j = 1, i - 1 do zone[#zone + 1] = tokens[j].text end
      for j = i + 2, #tokens do text[#text + 1] = tokens[j].text end
      return #zone > 0 and table.concat(zone, " ") or nil, tokens[i].num, tokens[i + 1].num,
        #text > 0 and table.concat(text, " ") or nil
    end
  end
end

local CONTINENTS = { 1414, 1415 }
local zones -- { { mapID, lower name } }
local function Zones()
  if zones then return zones end
  zones = {}
  local zoneType = Enum and Enum.UIMapType and ns.Num(Enum.UIMapType.Zone) or 3
  local seen = {}
  for _, cont in ipairs(CONTINENTS) do
    local ok, kids = false, nil
    if C_Map and type(C_Map.GetMapChildrenInfo) == "function" then ok, kids = pcall(C_Map.GetMapChildrenInfo, cont, zoneType, true) end
    for _, k in ipairs(ok and type(kids) == "table" and kids or {}) do
      local m = type(k) == "table" and ns.Num(k.mapID)
      if m and not seen[m] and type(k.name) == "string" then
        seen[m] = true
        zones[#zones + 1] = { m, k.name:lower() }
      end
    end
  end
  return zones
end
function ns.ForgetWayZones() zones = nil end -- (tests)

-- A zone by "#<uiMapID>", its name or the start of its name (when only one zone starts so).
function ns.WayZone(name)
  if type(name) ~= "string" or name == "" then return nil end
  local id = name:match("^#(%d+)$")
  if id then return tonumber(id) end
  local want, hit, hits = name:lower(), nil, 0
  for _, z in ipairs(Zones()) do
    if z[2] == want then return z[1] end
    if z[2]:find(want, 1, true) == 1 then hit, hits = z[1], hits + 1 end
  end
  return hits == 1 and hit or nil
end

function Here()
  local m = C_Map and C_Map.GetBestMapForUnit and ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  if m then return m end
  local map = WorldMapFrame
  return map and map.GetMapID and ns.Num(ns.Value(map.GetMapID, map)) or nil
end

-- The lines of a text: one waypoint each. Also several "/way ..." (or "/qd way ...") in one line, as the chat line
-- makes them of a pasted list. A leading "/way" of a line is dropped.
function ns.WayLines(text)
  text = tostring(text or ""):gsub("\r", "\n")
  text = text:gsub("/[Qq][Dd]%s+[Ww][Aa][Yy]%f[%s%z]", "\n"):gsub("/[Ww][Aa][Yy]%f[%s%z]", "\n")
  local out = {}
  for line in text:gmatch("[^\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then out[#out + 1] = line end
  end
  return out
end

local USAGE = "/way [zone] 45.2 61.8 [text], /way clear"
-- Sets the waypoints of a text (one or many lines). Returns how many were set and how many lines were not understood.
function ns.SetWays(text)
  local set, bad, last = 0, 0, nil
  for _, line in ipairs(ns.WayLines(text)) do
    local zone, x, y, label = ns.ParseWay(line)
    local mapID = x and Here()
    if x and zone then
      mapID = ns.WayZone(zone)
      if not mapID then ns.Print(L["Zone not found: %s"]:format(zone)) end
    end
    local w = mapID and Add(mapID, x / 100, y / 100, label)
    if w then set, last = set + 1, w else bad = bad + 1 end
  end
  if set > 0 then
    lead = set == 1 and last or Nearest()
    Point(lead)
    RefreshViews()
  end
  return set, bad
end

function ns.WayCommand(msg)
  msg = strtrim and strtrim(msg or "") or (msg or "")
  local low = msg:lower()
  if low == "" then ns.OpenWayBox() return end
  if low == "clear" or low == "reset" or low == "off" then ns.ClearWays("command") return end
  local set, bad = ns.SetWays(msg)
  if set > 1 then ns.Print(L["%d waypoints set."]:format(set)) end
  if bad > 0 and set == 0 then ns.Print(USAGE) end
end

---------------------------------------------------------------------------
-- The window of "/way" alone: many lines at once (the chat line cuts a pasted list after 255 letters)
---------------------------------------------------------------------------
local box
function ns.WayBox() return box end
function ns.OpenWayBox()
  -- (16.11.2026, Blizzard look as in Luredon 1.7.0) with the option blizzLook the game's own dialog (ns.LookKit); a box
  -- that fails to build that way is built with the Kit
  local Kit, blizz = LibStub("DonCore-1.0"):Get("Kit", 3), false
  if ns.LookKit then Kit, blizz = ns.LookKit() end
  if not box and blizz then
    local ok, err = pcall(ns.BuildWayBox, Kit, "QuestdonWayBoxBlizz")
    if not ok then
      if box and box.Hide then pcall(box.Hide, box) end
      box = nil
      if ns.RecordError then ns.RecordError("way box blizz look", err) end
      Kit = LibStub("DonCore-1.0"):Get("Kit", 3)
    end
  end
  if not box then ns.BuildWayBox(Kit, "QuestdonWayBox") end
  box:SetTitle(ns.Style.Wordmark("Quest", "don") .. ": " .. L["Waypoints"], nil)
  box.hint:SetText(L["One waypoint per line: [zone or #map] x y [text]"])
  box:SetButtons({
    { text = L["Remove all"], onClick = function() ns.ClearWays("window") end },
    { text = L["Set waypoints"], kind = "primary", onClick = function(d)
      local set = ns.SetWays(d.text:GetText())
      ns.Print(L["%d waypoints set."]:format(set))
      if set > 0 then d.text:SetText("") d:Hide() end
    end },
  })
  box:Show()
  box:Layout()
  if box.text.edit.SetFocus then box.text.edit:SetFocus() end
  return box
end
-- the option blizzLook changed: a closed box is built again in the other look when it opens next
function ns.WayBoxReset()
  if box and not box:IsShown() then box = nil end
end
-- builds the box with the blocks of Kit (DonCore's Kit or the game's look) under the frame name given
function ns.BuildWayBox(Kit, name)
  box = Kit.Dialog(name, { width = 520, height = 340, onLayout = function(self, w, h)
    if not self.hint then return end
    self.hint:ClearAllPoints()
    self.hint:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, 0)
    if self.hint.SetWidth then self.hint:SetWidth(w) end
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -22)
    self.text:Layout(w, math.max(40, h - 22))
  end })
  box.hint = box.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if box.hint.SetJustifyH then box.hint:SetJustifyH("LEFT") end
  box.text = Kit.TextBox(box.body, { maxLetters = 20000, placeholder = "/way #1413 62.7, 36.3 Text" })
  if not box.blizz and type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "QuestdonWayBox" end
  return box
end

-- "/way" is ours only when TomTom is not there (it has the same command)
ns.OnInit(function()
  ns.LoadWays()
  if ns.AddOnLoaded and ns.AddOnLoaded("TomTom") or type(rawget(_G, "TomTom")) == "table" then return end
  SLASH_QUESTDONWAY1 = "/way"
  SlashCmdList.QUESTDONWAY = ns.Guard("way", function(msg) ns.WayCommand(msg) end)
end)
