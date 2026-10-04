local _, ns = ...
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- (1.19) Shared look for the frames that are no Style.Panel (arrow, XP bar,
-- quest item button): flat plate with a 1 px border in the kit's colours and
-- the one-time migration of the old appearance settings. Own frames only.
---------------------------------------------------------------------------
local Look = {}
ns.Look = Look

local WHITE = "Interface\\Buttons\\WHITE8x8"

local function Clamp(v, lo, hi, default)
  v = tonumber(v)
  if not v or v ~= v then return default end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
Look.Clamp = Clamp

-- One physical pixel in the frame's coordinates (1 if the client cannot tell).
function Look.Pixel(frame)
  local ok, _, h = pcall(GetPhysicalScreenSize)
  local okS, scale = false, nil
  if type(frame) == "table" and frame.GetEffectiveScale then okS, scale = pcall(frame.GetEffectiveScale, frame) end
  h, scale = ok and tonumber(h), okS and tonumber(scale)
  if h and h > 0 and scale and scale > 0 then return 768 / h / scale end
  return 1
end

local function Tint(tex, color, alpha)
  if type(color) == "string" then color = C[color] end
  tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end
Look.Tint = Tint

-- Flat background plus 1 px border on a frame. plate:SetAlpha(a) sets the
-- background opacity (border follows like in Style.Panel). outset: px the
-- plate reaches beyond the frame (textures of the frame itself, so it never
-- covers the frame's own artwork).
function Look.Plate(frame, outset)
  local o = tonumber(outset) or 0
  local plate = { border = {} }
  plate.bg = frame:CreateTexture(nil, "BACKGROUND")
  plate.bg:SetTexture(WHITE)
  plate.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
  plate.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
  for i = 1, 4 do
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture(WHITE)
    plate.border[i] = t
  end
  function plate:Layout(px)
    px = px or Look.Pixel(frame)
    local b = self.border
    for i = 1, 4 do b[i]:ClearAllPoints() end
    b[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o); b[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o); b[1]:SetHeight(px)
    b[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o); b[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o); b[2]:SetHeight(px)
    b[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o); b[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o); b[3]:SetWidth(px)
    b[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o); b[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o); b[4]:SetWidth(px)
  end
  function plate:SetAlpha(alpha)
    alpha = Clamp(alpha, 0, 1, Style.DEFAULT_ALPHA)
    self.alpha = alpha
    Tint(self.bg, "background", alpha)
    local borderA = C.border[4] * math.min(1, alpha / Style.DEFAULT_ALPHA)
    for _, t in ipairs(self.border) do Tint(t, "border", borderA) end
  end
  function plate:SetShown(shown)
    for _, t in ipairs({ self.bg, unpack(self.border) }) do
      if shown then t:Show() else t:Hide() end
    end
  end
  plate:Layout()
  plate:SetAlpha(Style.DEFAULT_ALPHA)
  return plate
end

-- Font string in a GameFont object and a kit colour.
function Look.Font(parent, template, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", template)
  if type(color) == "string" then color = C[color] end
  color = color or C.textPrimary
  fs:SetTextColor(color[1], color[2], color[3], 1)
  return fs
end

function Look.SetColor(fs, color)
  if type(color) == "string" then color = C[color] end
  fs:SetTextColor(color[1], color[2], color[3], 1)
end

---------------------------------------------------------------------------
-- (1.20) Combat dimming of the free frames (arrow, XP bar) is the kit's
-- Style.CombatFade(frame, enabled) since kit version 2: same 0.15 s fade to
-- 40 %, the frame's own alpha restored after combat. Errors in callbacks the
-- kit runs protected (row clicks and tooltips, panel get/set) go to
-- Questdon's error log (/qd diag) through Style.onError.
---------------------------------------------------------------------------
Style.onError = function(where, err)
  if ns.RecordError then ns.RecordError("style " .. tostring(where), err) end
end

---------------------------------------------------------------------------
-- Settings migration (1.19): one appearance page for panel, arrow, XP bar
---------------------------------------------------------------------------
local OLD_PANEL_ALPHA = 0.75 -- default up to 1.18

function ns.MigrateLook(db)
  db = db or ns.db
  if type(db) ~= "table" then return false end
  local version = tonumber(db.lookVersion) or 0
  if version >= 2 then return false end
  local smin, smax = Style.SCALE_MIN, Style.SCALE_MAX
  local d = ns.defaults or {}
  local arrowDefault, xpDefault = d.arrowScale or 1.15, d.xpBarScale or 1.45
  if version < 1 then
    -- untouched old default: the family default now; own values stay
    if db.panelAlpha == OLD_PANEL_ALPHA then db.panelAlpha = Style.DEFAULT_ALPHA end
    db.panelAlpha = Clamp(db.panelAlpha, 0, 1, Style.DEFAULT_ALPHA)
    db.panelScale = Clamp(db.panelScale, smin, smax, 1)
    db.panelWidth = math.floor(Clamp(db.panelWidth, Style.SPACING.minWidth, 500, 300) + 0.5)
  end
  -- (1.25.1) new defaults: arrow 115 %, XP bar 145 %. A stored old default
  -- (1) follows the new one, an own size stays (clamped to 0.6-1.6).
  if db.arrowScale == nil or tonumber(db.arrowScale) == 1 then db.arrowScale = arrowDefault end
  if db.xpBarScale == nil or tonumber(db.xpBarScale) == 1 then db.xpBarScale = xpDefault end
  db.arrowScale = Clamp(db.arrowScale, smin, smax, arrowDefault)
  db.xpBarScale = Clamp(db.xpBarScale, smin, smax, xpDefault)
  db.lookVersion = 2
  return true
end

ns.OnInit(function() ns.MigrateLook() end)
