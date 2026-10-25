local _, ns = ...

---------------------------------------------------------------------------
-- (1.3.12, Daniel 25.10.) The postcard of a screenshot: what the journal
-- shows for a screenshot entry when the album has no picture of it. Built
-- only from what the game itself can draw, no helper outside the game:
--   1. the map of the zone around the place, a gold dot on the spot
--   2. the character as a 3D model in the gear worn at the screenshot
--   3. the targeted creature as a model beside it
--   4. a tint by the time of day (morning, day, evening, night)
-- Recorded with the screenshot (Journal.lua, ns.PostcardCapture):
--   eq "slot:item,slot:item" (visible gear), tn creature ID of the target,
--   hr hour of the game clock. Entries from before keep the current look
--   and the hour of the real clock. Nothing runs on a ticker; the models
--   load when the card is shown and are cleared when it hides.
---------------------------------------------------------------------------
local SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }
local HEAD, BACK = 1, 15
local ZOOM = 2.6      -- the card shows 1 / ZOOM of the zone's width
local DOT_X = 0.30    -- the place sits at 30 % of the card's width
local MAX_EQ = 220    -- bytes of the gear string (14 slots fit easily)

local function Call(obj, method, ...)
  local f = obj and obj[method]
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, obj, ...)
  if ok then return a, b end
  return nil
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local function Gear()
  if type(GetInventoryItemID) ~= "function" then return nil end
  local hideHead = type(ShowingHelm) == "function" and ns.Value(ShowingHelm) == false
  local hideBack = type(ShowingCloak) == "function" and ns.Value(ShowingCloak) == false
  local parts = {}
  for _, slot in ipairs(SLOTS) do
    local id = ns.Num(ns.Value(GetInventoryItemID, "player", slot))
    if id and id > 0 and not (slot == HEAD and hideHead) and not (slot == BACK and hideBack) then
      parts[#parts + 1] = slot .. ":" .. id
    end
  end
  local s = table.concat(parts, ",")
  if s == "" or #s > MAX_EQ then return nil end
  return s
end

-- "Creature-0-1-2-3-<npcID>-<spawn>" (also Vehicle and Pet); players have no model to keep
local function TargetCreature()
  if not ns.True(ns.Value(UnitExists, "target")) then return nil end
  if ns.True(ns.Value(UnitIsPlayer, "target")) then return nil end
  local guid = ns.Value(UnitGUID, "target")
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  id = tonumber(id)
  return id and id > 0 and id or nil
end

local function GameHour()
  if type(GetGameTime) ~= "function" then return nil end
  local ok, h = pcall(GetGameTime)
  h = ok and ns.Num(h) or nil
  if h and h >= 0 and h < 24 then return math.floor(h) end
  return nil
end

function ns.PostcardCapture(extra)
  if type(extra) ~= "table" then return extra end
  extra.eq = Gear()
  extra.tn = TargetCreature()
  extra.hr = GameHour()
  return extra
end

function ns.PostcardGear(eq) -- "1:123,5:456" -> { {1,123}, {5,456} }
  local out = {}
  if type(eq) ~= "string" then return out end
  for slot, id in eq:gmatch("(%d+):(%d+)") do out[#out + 1] = { tonumber(slot), tonumber(id) } end
  return out
end

-- hour of the entry: the game clock when recorded, else the real clock of its time
function ns.PostcardHour(e)
  local h = e and ns.Num(e.hr)
  if h then return h end
  if e and e.t and type(date) == "function" then
    local ok, d = pcall(date, "*t", e.t)
    if ok and type(d) == "table" then return d.hour end
  end
  return 12
end

-- tint: color and strength by the hour
local TINTS = {
  night = { 0.10, 0.16, 0.42, 0.42 },
  dawn = { 0.95, 0.60, 0.35, 0.16 },
  dusk = { 0.85, 0.40, 0.25, 0.22 },
}
function ns.PostcardTint(h)
  h = ns.Num(h) or 12
  if h >= 21 or h < 5 then return "night", TINTS.night end
  if h < 8 then return "dawn", TINTS.dawn end
  if h >= 18 then return "dusk", TINTS.dusk end
  return "day", nil
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function NewCard(parent)
  local c = CreateFrame("Frame", nil, parent)
  if c.SetClipsChildren then pcall(c.SetClipsChildren, c, true) end
  c.tiles = {}
  c.bg = c:CreateTexture(nil, "BACKGROUND", nil, 1)
  c.bg:SetAllPoints(c)
  Call(c.bg, "SetColorTexture", 0.08, 0.07, 0.05, 1)
  c.tint = c:CreateTexture(nil, "ARTWORK", nil, 1)
  c.tint:SetAllPoints(c)
  c.shade = c:CreateTexture(nil, "ARTWORK", nil, 2) -- darker right half behind the models
  c.shade:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
  c.shade:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
  Call(c.shade, "SetColorTexture", 0, 0, 0, 0.30)
  c.ring = c:CreateTexture(nil, "ARTWORK", nil, 3)
  c.ring:SetSize(14, 14)
  Call(c.ring, "SetTexture", "Interface\\Buttons\\WHITE8X8")
  Call(c.ring, "SetVertexColor", 0.12, 0.09, 0.03, 0.9)
  c.dot = c:CreateTexture(nil, "ARTWORK", nil, 4)
  c.dot:SetSize(8, 8)
  Call(c.dot, "SetTexture", "Interface\\Buttons\\WHITE8X8")
  Call(c.dot, "SetVertexColor", 1, 0.82, 0.30, 1)
  c.dot:SetPoint("CENTER", c.ring, "CENTER", 0, 0)
  for _, k in ipairs({ "top", "bottom", "left", "right" }) do -- thin gold frame
    local t = c:CreateTexture(nil, "OVERLAY")
    Call(t, "SetColorTexture", 0.78, 0.62, 0.30, 0.65)
    c[k] = t
  end
  c.top:SetPoint("TOPLEFT") c.top:SetPoint("TOPRIGHT") c.top:SetHeight(1)
  c.bottom:SetPoint("BOTTOMLEFT") c.bottom:SetPoint("BOTTOMRIGHT") c.bottom:SetHeight(1)
  c.left:SetPoint("TOPLEFT") c.left:SetPoint("BOTTOMLEFT") c.left:SetWidth(1)
  c.right:SetPoint("TOPRIGHT") c.right:SetPoint("BOTTOMRIGHT") c.right:SetWidth(1)
  -- models: the player in front, the target behind and to the left
  local okT, tm = pcall(CreateFrame, "PlayerModel", nil, c)
  c.target = okT and tm or nil
  local okP, pm = pcall(CreateFrame, "DressUpModel", nil, c)
  c.model = okP and pm or nil
  if c.model and c.target and c.model.SetFrameLevel and c.target.GetFrameLevel then
    pcall(function() c.model:SetFrameLevel((c.target:GetFrameLevel() or 1) + 1) end)
  end
  c:SetScript("OnHide", function(self) ns.PostcardClear(self) end)
  c:Hide()
  return c
end

-- the map around the place: tiles cut to the card (texture coordinates, no clipping needed)
local function DrawMap(c, e, w, h)
  for _, t in ipairs(c.tiles) do t:Hide() end
  c.mapDrawn, c.dotShown = 0, false
  c.ring:Hide() c.dot:Hide()
  local m = e.pm or e.m
  local px, py = ns.Num(e.px), ns.Num(e.py)
  if not (m and ns.MapArt) then return end
  local textures, tw, th, lw, lh = ns.MapArt(m)
  if not textures then return end
  local scale = (w * ZOOM) / lw
  local mh = lh * scale
  if mh < h then scale = h / lh end -- never smaller than the card
  local fx, fy = px or 0.5, py or 0.5
  local sx = fx * lw * scale - w * DOT_X
  local sy = fy * lh * scale - h * 0.5
  sx = math.max(0, math.min(lw * scale - w, sx))
  sy = math.max(0, math.min(lh * scale - h, sy))
  local cols = math.ceil(lw / tw)
  local drawn = 0
  for i, file in ipairs(textures) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = col * tw, row * th
    local X, Y, W, H = x * scale - sx, y * scale - sy, tw * scale, th * scale
    local xa, xb = math.max(0, X), math.min(w, X + W)
    local ya, yb = math.max(0, Y), math.min(h, Y + H)
    if xb > xa and yb > ya then
      drawn = drawn + 1
      local t = c.tiles[drawn]
      if not t then
        t = c:CreateTexture(nil, "BACKGROUND", nil, 2)
        c.tiles[drawn] = t
      end
      Call(t, "SetTexture", file)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", c, "TOPLEFT", xa, -ya)
      t:SetSize(xb - xa, yb - ya)
      Call(t, "SetTexCoord", (xa - X) / W, (xb - X) / W, (ya - Y) / H, (yb - Y) / H)
      t:Show()
    end
  end
  c.mapDrawn = drawn
  if px and py then
    c.ring:ClearAllPoints()
    c.ring:SetPoint("CENTER", c, "TOPLEFT", px * lw * scale - sx, -(py * lh * scale - sy))
    c.ring:Show() c.dot:Show()
    c.dotShown = true
  end
end

local function DressModel(c, e)
  local m = c.model
  if not m then return end
  m.items = {}
  Call(m, "SetUnit", "player")
  local gear = ns.PostcardGear(e.eq)
  if #gear > 0 then
    Call(m, "Undress")
    for _, g in ipairs(gear) do
      Call(m, "TryOn", "item:" .. g[2])
      m.items[#m.items + 1] = g[2]
    end
  end
  Call(m, "SetSheathed", false)
  Call(m, "SetFacing", -0.35)
end

function ns.PostcardShow(c, e, w, h)
  if not (c and e) then return end
  c:SetSize(w, h)
  c.entry = e
  c.shade:SetWidth(math.floor(w * 0.45))
  DrawMap(c, e, w, h)
  local kind, tint = ns.PostcardTint(ns.PostcardHour(e))
  c.tintKind = kind
  if tint then
    Call(c.tint, "SetColorTexture", tint[1], tint[2], tint[3], tint[4])
    c.tint:Show()
  else
    c.tint:Hide()
  end
  c:Show()
  if c.model then
    c.model:ClearAllPoints()
    c.model:SetPoint("TOPRIGHT", c, "TOPRIGHT", -2, -2)
    c.model:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -2, 2)
    c.model:SetWidth(math.floor(w * 0.34))
    c.model:Show()
    DressModel(c, e)
    -- the client loads the model a moment later: dress again when it is there
    if c.model.SetScript then
      pcall(c.model.SetScript, c.model, "OnModelLoaded", function(self)
        if c.entry and c:IsShown() then
          self:SetScript("OnModelLoaded", nil)
          DressModel(c, c.entry)
        end
      end)
    end
  end
  c.targetShown = false
  if c.target then
    local tn = ns.Num(e.tn)
    if tn then
      c.target:ClearAllPoints()
      c.target:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -math.floor(w * 0.26), 4)
      c.target:SetSize(math.floor(w * 0.30), math.floor(h * 0.80))
      c.target:Show()
      Call(c.target, "SetCreature", tn)
      Call(c.target, "SetFacing", 0.45)
      c.target.creature = tn
      c.targetShown = true
    else
      Call(c.target, "ClearModel")
      c.target.creature = nil
      c.target:Hide()
    end
  end
end

function ns.PostcardClear(c)
  if not c then return end
  c.entry = nil
  if c.model then Call(c.model, "ClearModel") c.model.items = nil end
  if c.target then Call(c.target, "ClearModel") c.target.creature = nil end
end

-- the card of a frame (one per frame, made on first use)
function ns.PostcardFor(parent)
  if not parent then return nil end
  if not parent.postcard then parent.postcard = NewCard(parent) end
  return parent.postcard
end

function ns.PostcardHide(parent)
  local c = parent and parent.postcard
  if c then c:Hide() ns.PostcardClear(c) end
end
