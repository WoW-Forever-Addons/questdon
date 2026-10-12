local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.3.6, Daniel 11.10.: "the tooltips of the Questdon points on the map are too old-school, they must look
-- nicer when you hover them: short, to the point, fitting colours") The hover card of our map and minimap
-- pins: an own frame in the quest book's look (a rounded navy card, a thin gold edge), a stripe in the colour
-- of the pin's kind (gold: quest to take, green: turn in, the quest's dot colour: objective, blue: dungeon),
-- the game's quest icon, the level as a small badge in its difficulty colour, the title, a few short lines and
-- the click hint in small letters at the bottom.
--
-- Own frame only (DESIGN): GameTooltip is not touched for our pins. Its content comes from the same builders
-- as before (ns.QuestPinTooltip and friends: title, lines, hint); only the drawing is new.
---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
local PAD_X, PAD_Y = 12, 9
local STRIPE = 3
local MIN_W, MAX_W = 170, 280
local ICON = 16
local LABEL_MAX = 92     -- the label column of key/value lines at most this wide
local GAP = 3            -- between lines
local MAX_LINES = 14     -- a group of quests: the builder already cuts at 10 (+ "and n more")

local KIND = {
  available = { 1.00, 0.82, 0.10 },
  turnin    = { 0.40, 0.85, 0.45 },
  upcoming  = { 0.55, 0.56, 0.62 },
  focus     = { 0.25, 0.66, 0.96 },
  dungeon   = { 0.45, 0.62, 1.00 },
}
local ATLAS = { available = "QuestNormal", turnin = "QuestTurnin", upcoming = "QuestNormal", dungeon = "Dungeon" }

local function B(name) return ns.Style and ns.Style.BOOK and ns.Style.BOOK[name] end
local function C(name)
  local c = ns.Style and ns.Style.COLORS and ns.Style.COLORS[name]
  return c or { 1, 1, 1 }
end
local function Num(v) v = tonumber(v) return (v and v == v) and v or nil end
local function Call(o, m, ...)
  local f = o and o[m]
  if type(f) ~= "function" then return false end
  return pcall(f, o, ...)
end
local function Plain(t)
  return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

-- The kind of a pin -> stripe colour and icon. pin: the pin table (or nil for a bundle of objectives).
function ns.PinCardKind(pin, questID)
  if not pin then return "objective", { ns.QuestColor(questID or 0) }, nil end
  local kind = pin.kind
  if kind == "dungeon" or kind == "entrance" then return "dungeon", KIND.dungeon, ATLAS.dungeon end
  if kind == "objective" then return "objective", { ns.QuestColor(pin.questID or 0) }, nil end
  if kind == "focus" then return "focus", KIND.focus, ATLAS.available end
  if kind == "turnin" or pin.iconKind == "turnin" then return "turnin", KIND.turnin, ATLAS.turnin end
  if pin.upcoming or pin.notOffered then return "upcoming", KIND.upcoming, ATLAS.upcoming end
  return "available", KIND.available, ATLAS.available
end

---------------------------------------------------------------------------
-- The frame (made on first use)
---------------------------------------------------------------------------
local card
local SLICE

local function CardTex(parent, layer, file, sub)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  if SLICE == nil then SLICE = type(t.SetTextureSliceMargins) == "function" end
  if SLICE and t:SetTexture(MEDIA .. file) ~= false then
    if not pcall(t.SetTextureSliceMargins, t, 12, 12, 12, 12) then SLICE = false end
    if SLICE and t.SetTextureSliceMode then pcall(t.SetTextureSliceMode, t, 0) end
  end
  if not SLICE then t:SetTexture(WHITE) end
  return t
end

local function Font(parent, template, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", template)
  if fs.GetFontObject and not fs:GetFontObject() and _G[template] then Call(fs, "SetFontObject", _G[template]) end
  Call(fs, "SetJustifyH", "LEFT")
  Call(fs, "SetJustifyV", "TOP")
  Call(fs, "SetWordWrap", true)
  return fs
end

local function Make()
  if card then return card end
  local f = CreateFrame("Frame", "QuestdonPinCard", UIParent)
  Call(f, "SetFrameStrata", "TOOLTIP")
  Call(f, "SetFrameLevel", 100)
  Call(f, "SetClampedToScreen", true)
  Call(f, "EnableMouse", false)
  f:Hide()
  local bg = B("card") or { 0.17, 0.21, 0.40 }
  local low = B("cardLow") or { 0.11, 0.13, 0.28 }
  f.fill = CardTex(f, "BACKGROUND", "CardFill", 1)
  f.fill:SetAllPoints(f)
  local okG = false
  if f.fill.SetGradient and CreateColor then
    okG = pcall(f.fill.SetGradient, f.fill, "VERTICAL", CreateColor(low[1], low[2], low[3], 0.96), CreateColor(bg[1], bg[2], bg[3], 0.96))
  end
  if not okG then f.fill:SetVertexColor(low[1], low[2], low[3], 0.96) end
  local gold = B("gold") or { 0.86, 0.71, 0.42 }
  if SLICE then
    f.edge = CardTex(f, "BORDER", "CardBorder", 1)
    f.edge:SetAllPoints(f)
    f.edge:SetVertexColor(gold[1], gold[2], gold[3], 0.45)
  else
    f.edges = {}
    local function Line(a, b, horiz)
      local t = f:CreateTexture(nil, "BORDER")
      t:SetTexture(WHITE)
      t:SetPoint(a, f, a) t:SetPoint(b, f, b)
      if horiz then t:SetHeight(1) else t:SetWidth(1) end
      t:SetVertexColor(gold[1], gold[2], gold[3], 0.45)
      f.edges[#f.edges + 1] = t
    end
    Line("TOPLEFT", "TOPRIGHT", true) Line("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Line("TOPLEFT", "BOTTOMLEFT") Line("TOPRIGHT", "BOTTOMRIGHT")
  end
  -- the kind's stripe on the left, inside the rounded corners
  f.stripe = f:CreateTexture(nil, "ARTWORK")
  f.stripe:SetTexture(WHITE)
  f.stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -6)
  f.stripe:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 6)
  f.stripe:SetWidth(STRIPE)
  -- the kind's glow behind the head (a faint wash of the kind's colour)
  f.wash = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  f.wash:SetTexture(WHITE)
  f.wash:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
  f.wash:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(ICON, ICON)
  f.dot = f:CreateTexture(nil, "ARTWORK")
  f.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  f.dot:SetSize(10, 10)
  f.badge = f:CreateTexture(nil, "ARTWORK")
  f.badge:SetTexture(WHITE)
  f.badgeText = Font(f, "GameFontNormalSmall")
  Call(f.badgeText, "SetJustifyH", "CENTER")
  f.title = Font(f, "GameFontHighlight")
  f.divider = f:CreateTexture(nil, "ARTWORK")
  f.divider:SetTexture(WHITE)
  f.divider:SetHeight(1)
  f.hint = Font(f, "GameFontDisableSmall")
  f.rows = {}
  -- safety: the owner went away without OnLeave (a map refresh released the pin)
  local elapsed = 0
  f:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < 0.2 then return end
    elapsed = 0
    local o = self.owner
    local okV, visible = Call(o, "IsVisible")
    local okM, over = Call(o, "IsMouseOver")
    if not o or (okV and not visible) or (okM and not over) then self:Hide() self.owner = nil end
  end)
  card = f
  return f
end

local function Row(f, i)
  local r = f.rows[i]
  if not r then
    r = { label = Font(f, "GameFontNormalSmall"), value = Font(f, "GameFontHighlightSmall") }
    f.rows[i] = r
  end
  return r
end

local function Width(fs, text)
  local ok, w = Call(fs, "GetUnboundedStringWidth")
  w = ok and Num(w)
  if not w or w <= 0 then ok, w = Call(fs, "GetStringWidth") w = ok and Num(w) end
  if not w or w <= 0 then w = #Plain(text) * 6 end
  return w
end
local function Height(fs, text, width)
  local ok, h = Call(fs, "GetStringHeight")
  h = ok and Num(h)
  if not h or h <= 0 then h = math.max(1, math.ceil(#Plain(text) * 6 / math.max(width, 1))) * 12 end
  return h
end
local function SetColor(fs, c, a) Call(fs, "SetTextColor", c[1], c[2], c[3], a or 1) end

-- The title as the builders make it: an optional texture escape (dungeon icon, dot swatch), an optional level
-- tag "|cffxxxxxx[6]|r " and the title. -> badge text, badge colour (r, g, b) or nil, title
local function SplitTitle(title)
  local t = tostring(title or "")
  t = t:gsub("^|T.-|t%s*", "")
  local hex, lv, rest = t:match("^|cff(%x%x%x%x%x%x)%[(.-)%]|r%s*(.*)$")
  if hex then
    local c = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
    return lv, c, rest
  end
  return nil, nil, t
end

-- What the card shows, for tests and /qd diag: { kind = "title"|"line"|"double"|"header"|"hint", left, right, r, g, b }
local shownRows = {}
function ns.PinCardRows() return shownRows end
function ns.PinCardShown() return card and card:IsShown() and card.owner ~= nil or false end
function ns.PinCardOwned(owner) return card ~= nil and card.owner == owner and card:IsShown() and true or false end

-- owner: the pin frame; title, lines, hint: as Style.Tooltip takes them; kind, color, atlas: ns.PinCardKind.
function ns.PinCard(owner, title, lines, hint, kind, color, atlas)
  if not owner then return end
  local f = Make()
  local P = B("textPrimary") or C("textPrimary")
  local S = B("textSecondary") or C("textSecondary")
  local H = B("textHint") or C("textHint")
  color = color or KIND.available
  for i = #shownRows, 1, -1 do shownRows[i] = nil end
  f.owner, f.kind, f.kindColor, f.lead = owner, kind, color, nil
  f.stripe:SetVertexColor(color[1], color[2], color[3], 1)
  f.wash:SetVertexColor(color[1], color[2], color[3], 0.10)

  -- head: icon (or the objective's dot), level badge, title
  local badge, badgeColor, text = SplitTitle(title)
  local x = PAD_X + STRIPE + 2
  f.icon:Hide() f.dot:Hide()
  local lead = 0
  if atlas and f.icon.SetAtlas and pcall(f.icon.SetAtlas, f.icon, atlas, false) then
    f.icon:SetAlpha(kind == "upcoming" and 0.6 or 1)
    f.icon:Show()
    f.lead = atlas
    lead = ICON + 5
  elseif kind == "objective" then
    f.dot:SetVertexColor(color[1], color[2], color[3], 1)
    f.dot:Show()
    f.lead = "dot"
    lead = 10 + 6
  end
  local badgeW = 0
  if badge then
    f.badgeText:SetText(badge)
    SetColor(f.badgeText, badgeColor)
    badgeW = math.max(18, Width(f.badgeText, badge) + 8)
    f.badge:SetVertexColor(badgeColor[1], badgeColor[2], badgeColor[3], 0.20)
    f.badge:SetSize(badgeW, 14)
    f.badge:Show() f.badgeText:Show()
    badgeW = badgeW + 5
  else
    f.badge:Hide() f.badgeText:Hide()
  end
  f.title:SetText(text)
  SetColor(f.title, P)
  shownRows[#shownRows + 1] = { kind = "title", left = title, r = P[1], g = P[2], b = P[3], badge = badge }

  -- the lines: plain text, key/value, sub-heading
  local list = {}
  if type(lines) == "table" then
    for _, l in ipairs(lines) do
      if #list >= MAX_LINES then break end
      if type(l) == "table" then
        if l.header ~= nil then list[#list + 1] = { header = tostring(l.header) }
        elseif l[2] ~= nil then
          local c = l[3]
          if type(c) == "string" then c = (c == "textHint" and H) or C(c) end
          list[#list + 1] = { label = tostring(l[1] or ""), value = tostring(l[2]), color = type(c) == "table" and c or P }
        else list[#list + 1] = { text = tostring(l[1] or "") } end
      elseif l ~= nil then
        list[#list + 1] = { text = tostring(l) }
      end
    end
  end
  hint = hint and hint ~= "" and tostring(hint):gsub(", ", "  ·  ") or nil

  -- width: the widest natural line, between MIN_W and MAX_W
  local inner = Width(f.title, text) + lead + badgeW
  local labelW = 0
  for i, l in ipairs(list) do
    local r = Row(f, i)
    if l.label then
      r.label:SetText(l.label)
      labelW = math.max(labelW, math.min(LABEL_MAX, Width(r.label, l.label)))
    end
  end
  for i, l in ipairs(list) do
    local r = Row(f, i)
    if l.label then
      r.value:SetText(l.value)
      inner = math.max(inner, labelW + 10 + Width(r.value, l.value))
    else
      r.value:SetText(l.header or l.text)
      inner = math.max(inner, Width(r.value, l.header or l.text))
    end
  end
  if hint then f.hint:SetText(hint) inner = math.max(inner, Width(f.hint, hint)) end
  local left = PAD_X + STRIPE + 2
  local width = math.floor(math.min(MAX_W, math.max(MIN_W, inner + left + PAD_X)) + 0.5)
  local avail = width - left - PAD_X

  -- layout, top down
  local y = -PAD_Y
  local titleW = avail - lead - badgeW
  if lead > 0 then
    local tex = f.icon:IsShown() and f.icon or f.dot
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - (tex == f.dot and 3 or 0))
  end
  if badge then
    f.badge:ClearAllPoints()
    f.badge:SetPoint("TOPLEFT", f, "TOPLEFT", x + lead, y - 1)
    f.badgeText:ClearAllPoints()
    f.badgeText:SetPoint("CENTER", f.badge, "CENTER", 0, 0)
  end
  f.title:ClearAllPoints()
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", x + lead + badgeW, y - 1)
  f.title:SetWidth(titleW)
  local th = math.max(ICON, Height(f.title, text, titleW) + 2)
  y = y - th
  f.wash:SetHeight(PAD_Y + th + 2)

  if #list > 0 then
    y = y - 5
    f.divider:ClearAllPoints()
    f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", left, y)
    f.divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X, y)
    local gold = B("gold") or { 0.86, 0.71, 0.42 }
    f.divider:SetVertexColor(gold[1], gold[2], gold[3], 0.25)
    f.divider:Show()
    y = y - 6
  else
    f.divider:Hide()
  end
  for i, l in ipairs(list) do
    local r = Row(f, i)
    r.label:ClearAllPoints() r.value:ClearAllPoints()
    if l.label then
      SetColor(r.label, S)
      SetColor(r.value, l.color)
      r.label:SetWidth(labelW)
      r.label:SetPoint("TOPLEFT", f, "TOPLEFT", left, y)
      r.value:SetWidth(avail - labelW - 10)
      r.value:SetPoint("TOPLEFT", f, "TOPLEFT", left + labelW + 10, y)
      r.label:Show() r.value:Show()
      local h = math.max(Height(r.label, l.label, labelW), Height(r.value, l.value, avail - labelW - 10))
      y = y - h - GAP
      shownRows[#shownRows + 1] = { kind = "double", left = l.label, right = l.value, r = S[1], g = S[2], b = S[3],
        rr = l.color[1], rg = l.color[2], rb = l.color[3] }
    else
      r.label:Hide()
      local c = l.header and (B("gold") or S) or S
      if l.header and i > 1 then y = y - 4 end
      SetColor(r.value, c)
      r.value:SetWidth(avail)
      r.value:SetPoint("TOPLEFT", f, "TOPLEFT", left, y)
      r.value:Show()
      y = y - Height(r.value, l.header or l.text, avail) - GAP
      shownRows[#shownRows + 1] = { kind = l.header and "header" or "line", left = l.header or l.text, r = c[1], g = c[2], b = c[3] }
    end
  end
  for i = #list + 1, #f.rows do f.rows[i].label:Hide() f.rows[i].value:Hide() end
  if hint then
    y = y - (#list > 0 and 3 or 6)
    SetColor(f.hint, H)
    f.hint:ClearAllPoints()
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", left, y)
    f.hint:SetWidth(avail)
    f.hint:Show()
    y = y - Height(f.hint, hint, avail)
    shownRows[#shownRows + 1] = { kind = "hint", left = hint, r = H[1], g = H[2], b = H[3] }
  else
    f.hint:Hide()
  end
  f:SetSize(width, math.floor(-y + PAD_Y + 0.5))

  -- beside the pin, on the side with more room (like the tooltips' "auto")
  f:ClearAllPoints()
  local side = ns.Style and ns.Style.AutoAnchor and ns.Style.AutoAnchor(owner) or "ANCHOR_RIGHT"
  if side == "ANCHOR_LEFT" then f:SetPoint("BOTTOMRIGHT", owner, "TOPLEFT", -2, 2)
  else f:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 2, 2) end
  f:Show()
end

function ns.PinCardHide(owner)
  if card and (owner == nil or card.owner == owner) then
    card:Hide()
    card.owner = nil
  end
end
