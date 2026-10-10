local _, ns = ...
local L = ns.L
local Style = ns.Style
local C = Style.COLORS

---------------------------------------------------------------------------
-- (1.3) The quest book: one large window with three tabs.
--
--   Journal  the personal diary (Journal.lua): today's numbers at the top
--            (quests, XP, money, progress of the level), filters, then a
--            time line, newest first, with a mark per event; level-ups as a
--            golden band; at the end the quests done before the journal.
--   Zones    every zone of Kalimdor, the Eastern Kingdoms and the new Forever zones (Zephras Isle) on the left
--            (level range, your progress, a filter box); the picked zone on
--            the right with a picture of its map, "23 / 72 done", its
--            quests (ZoneQuests.lua) or your journal entries there. Quests
--            of a chain with the same name are one line ("2/6") that opens.
--   Dungeons (1.3.3, Daniel 08.10.) every dungeon with its quests for you,
--            sorted by level; under each open quest the quests still to do
--            before it ("First: ..."), with quest giver and zone.
--   Search   journal, all quests and zones by name, level or quest ID.
--
-- Long lists are drawn as a window onto the list (mouse wheel), only the
-- visible lines exist as frames. Our own frames only; nothing of Blizzard's
-- is hooked. Escape closes the book.
---------------------------------------------------------------------------
-- (1.3.4) Daniel 08.10.: a richer look in the direction of his drafts:
-- navy to violet background, a gold frame with ornaments in the corners,
-- gold-framed tabs, every line as a card, the zone map round in a gold ring,
-- statistic cards. Plus: a detail card for the clicked quest, dungeons as
-- "ready" cards with a route to the quest givers, zone filters and sorting
-- by distance, and a shorter journal (accepted and turned in in one line,
-- day totals, the last seven days).
local W, H = 980, 640
local HEADER_H = 42
local GEAR_SIZE, GEAR_GAP = 18, 8 -- (round 8b) the options gear in the title bar, next to the X (14 px)
local SIDE_W = 232
local HERO_H = 116
local JHERO_H = 188 -- journal: round map and four statistic cards
local DETAIL_W = 320
local ROW_H, HEAD_H, SMALL_H = 46, 30, 32
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
local MAX_QUESTS = 100

local WHITE = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local ICON = {
  c = "Interface\\RAIDFRAME\\ReadyCheck-Ready",
  o = "Interface\\RAIDFRAME\\ReadyCheck-Ready",
  x = "Interface\\RAIDFRAME\\ReadyCheck-NotReady",
  f = "Interface\\RAIDFRAME\\ReadyCheck-NotReady",
  a = "Interface\\GossipFrame\\AvailableQuestIcon",
  l = "Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_1",
}
local TAB_ICON = {
  journal = "Interface\\Icons\\INV_Misc_Book_09",
  zone = "Interface\\Icons\\INV_Misc_Map_01",
  search = "Interface\\Icons\\INV_Misc_Spyglass_03",
  dungeons = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
}
local TABS = { "journal", "zone", "dungeons", "search" }
local TAB_TITLE = { journal = "Journal", zone = "Zones", dungeons = "Dungeons", search = "Search" }

-- Zones of the book: uiMapID, continent, level range (cities without), faction
-- of start zones and capitals ("A"/"H", hidden for the other faction).
local KALIMDOR, EASTERN, FOREVER = 1414, 1415, 0 -- FOREVER: new zones of Forever (own group)
local ZONES = {
  { 1438, KALIMDOR, 1, 10, "A" }, { 1411, KALIMDOR, 1, 10, "H" }, { 1412, KALIMDOR, 1, 10, "H" },
  { 1439, KALIMDOR, 10, 20 }, { 1413, KALIMDOR, 10, 25 }, { 1442, KALIMDOR, 15, 27 },
  { 1440, KALIMDOR, 18, 30 }, { 1441, KALIMDOR, 25, 35 }, { 1443, KALIMDOR, 30, 40 },
  { 1445, KALIMDOR, 35, 45 }, { 1444, KALIMDOR, 40, 50 }, { 1446, KALIMDOR, 40, 50 },
  { 1447, KALIMDOR, 45, 55 }, { 1448, KALIMDOR, 48, 55 }, { 1449, KALIMDOR, 48, 55 },
  { 1452, KALIMDOR, 53, 60 }, { 1450, KALIMDOR, 55, 60 }, { 1451, KALIMDOR, 55, 60 },
  { 1457, KALIMDOR, nil, nil, "A" }, { 1454, KALIMDOR, nil, nil, "H" }, { 1456, KALIMDOR, nil, nil, "H" },
  { 1429, EASTERN, 1, 10, "A" }, { 1426, EASTERN, 1, 10, "A" }, { 1420, EASTERN, 1, 10, "H" },
  { 1436, EASTERN, 10, 20 }, { 1432, EASTERN, 10, 20 }, { 1421, EASTERN, 10, 20 },
  { 1433, EASTERN, 15, 25 }, { 1431, EASTERN, 18, 30 }, { 1437, EASTERN, 20, 30 },
  { 1424, EASTERN, 20, 30 }, { 1416, EASTERN, 30, 40 }, { 1417, EASTERN, 30, 40 },
  { 1434, EASTERN, 30, 45 }, { 1418, EASTERN, 35, 45 }, { 1435, EASTERN, 35, 45 },
  { 1425, EASTERN, 40, 50 }, { 1427, EASTERN, 43, 50 }, { 1419, EASTERN, 45, 55 },
  { 1428, EASTERN, 50, 58 }, { 1422, EASTERN, 51, 58 }, { 1423, EASTERN, 53, 60 },
  { 1430, EASTERN, 55, 60 },
  { 1453, EASTERN, nil, nil, "A" }, { 1455, EASTERN, nil, nil, "A" }, { 1458, EASTERN, nil, nil, "H" },
  -- new in Forever: Zephras Isle, start zone of the Skyborne (Skywall)
  { 2521, FOREVER, 1, 12 },
}
local ZONE_INFO = {}
for _, z in ipairs(ZONES) do ZONE_INFO[z[1]] = { map = z[1], cont = z[2], min = z[3], max = z[4], faction = z[5] } end
-- Folder of the zone map in Interface\WorldMap (when the client gives no map art layers)
local MAPFILE = {
  [1438] = "Teldrassil", [1411] = "Durotar", [1412] = "Mulgore", [1439] = "Darkshore", [1413] = "Barrens",
  [1442] = "StonetalonMountains", [1440] = "Ashenvale", [1441] = "ThousandNeedles", [1443] = "Desolace",
  [1445] = "Dustwallow", [1444] = "Feralas", [1446] = "Tanaris", [1447] = "Aszhara", [1448] = "Felwood",
  [1449] = "UngoroCrater", [1452] = "Winterspring", [1450] = "Moonglade", [1451] = "Silithus",
  [1457] = "Darnassis", [1454] = "Ogrimmar", [1456] = "ThunderBluff",
  [1429] = "Elwynn", [1426] = "DunMorogh", [1420] = "Tirisfal", [1436] = "Westfall", [1432] = "LochModan",
  [1421] = "Silverpine", [1433] = "Redridge", [1431] = "Duskwood", [1437] = "Wetlands", [1424] = "Hilsbrad",
  [1416] = "Alterac", [1417] = "Arathi", [1434] = "Stranglethorn", [1418] = "Badlands", [1435] = "SwampOfSorrows",
  [1425] = "Hinterlands", [1427] = "SearingGorge", [1419] = "BlastedLands", [1428] = "BurningSteppes",
  [1422] = "WesternPlaguelands", [1423] = "EasternPlaguelands", [1430] = "DeadwindPass",
  [1453] = "Stormwind", [1455] = "Ironforge", [1458] = "Undercity",
}
local CONT_FALLBACK = { [KALIMDOR] = "Kalimdor", [EASTERN] = "Eastern Kingdoms", [FOREVER] = "New in Forever" }

local book
local tab = "journal"
local selZone           -- picked zone; nil: yours (or the one of the open world map)
local zoneSeg = "quests" -- "quests" or "journal"
local jfilter = "all"
local expanded = {}     -- chain key -> true
local contOpen = {}     -- continent -> true/false (nil: open where you are)
local showDone = false
local zFilter = "all"    -- (1.3.4) zone quests: all, log, available, later, done
local zNear = false      -- (1.3.4) zone quests: nearest first
local zoneQuery, query = "", ""
local stats = {}        -- mapID -> { total, done } for the zone list
local lists = {}        -- page key -> virtual list
local P = {}            -- frames of the pages

local Fmt = ns.JournalFmt

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
-- (1.3.4) The book's own colours (the panel and the other windows keep Style.COLORS).
local THEME = {
  background    = { 0.10, 0.11, 0.22 },
  backgroundLow = { 0.15, 0.10, 0.25 },
  header        = { 0.07, 0.08, 0.17 },
  textPrimary   = { 0.96, 0.92, 0.84 },
  textSecondary = { 0.80, 0.76, 0.68 },
  textHint      = { 0.58, 0.57, 0.66 },
  gold          = { 0.86, 0.71, 0.42 },
  goldLight     = { 0.97, 0.87, 0.60 },
  goldDark      = { 0.42, 0.30, 0.14 },
  accent        = { 0.40, 0.68, 0.98 },
  good          = { 0.47, 0.84, 0.44 },
  warning       = { 0.98, 0.80, 0.34 },
  critical      = { 0.93, 0.40, 0.36 },
  divider       = { 0.86, 0.71, 0.42, 0.22 },
  rowHover      = { 1, 1, 1, 0.05 },
  rowActive     = { 0.86, 0.71, 0.42, 0.16 },
  barBackground = { 1, 1, 1, 0.09 },
  card          = { 0.17, 0.21, 0.40 },
  cardLow       = { 0.11, 0.13, 0.28 },
  cardEdge      = { 0.86, 0.71, 0.42, 0.30 },
  violet        = { 0.66, 0.36, 0.95 },
  cyan          = { 0.30, 0.86, 0.95 },
}
for _, c in pairs(THEME) do
  c.hex = string.format("ff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
ns.QUESTBOOK_THEME = THEME -- (tests)

local function RGB(c)
  if type(c) == "string" then c = THEME[c] or C[c] end
  return c or THEME.textPrimary
end

-- Coloured text in the book's colours.
local function Colorize(text, color)
  local c = RGB(color)
  local hex = c.hex or string.format("ff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
  return "|c" .. hex .. tostring(text or "") .. "|r"
end

local function Fill(tex, color, alpha)
  local c = RGB(color)
  if tex.SetColorTexture then
    tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
  else
    tex:SetTexture(WHITE)
    tex:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
  end
end

local function Tex(parent, layer, color, alpha, sub)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
  if color then Fill(t, color, alpha) end
  return t
end

-- A colour gradient on a texture (vertical: c1 at the bottom, c2 at the top); plain fill if the client cannot.
local function Gradient(tex, orientation, c1, a1, c2, a2)
  local x, y = RGB(c1), RGB(c2)
  if tex.SetGradient and CreateColor then
    if not tex:GetTexture() then Fill(tex, { 1, 1, 1 }, 1) end
    local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(x[1], x[2], x[3], a1 or 1), CreateColor(y[1], y[2], y[3], a2 or 1))
    if ok then return end
  end
  Fill(tex, c2, a2)
end

-- (1.3.4) Rounded cards: the client cuts our 64 px texture into nine parts
-- (SetTextureSliceMargins); an older client gets a plain card with thin edges.
local SLICE
local function CanSlice(tex)
  if SLICE == nil then SLICE = type(tex.SetTextureSliceMargins) == "function" end
  return SLICE
end
local function CardTex(parent, layer, file, sub)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  if CanSlice(t) and t:SetTexture(MEDIA .. file) ~= false then
    if not pcall(t.SetTextureSliceMargins, t, 12, 12, 12, 12) then SLICE = false end
    if SLICE and t.SetTextureSliceMode then pcall(t.SetTextureSliceMode, t, 0) end
  end
  return t
end
-- A card behind a line or tile: f.cardFill, f.cardEdge (or four lines), inset from the frame's edges.
local function Card(f, inset, insetY)
  inset, insetY = inset or 0, insetY or 0
  f.cardFill = CardTex(f, "BACKGROUND", "CardFill", 1)
  f.cardFill:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -insetY)
  f.cardFill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, insetY)
  if SLICE then
    f.cardEdge = CardTex(f, "BORDER", "CardBorder", 1)
    f.cardEdge:SetAllPoints(f.cardFill)
  else
    f.cardFill:SetTexture(WHITE)
    f.cardLines = {}
    local fl = f.cardFill
    local function Line(a, b, horiz)
      local t = f:CreateTexture(nil, "BORDER")
      t:SetTexture(WHITE)
      t:SetPoint(a, fl, a) t:SetPoint(b, fl, b)
      if horiz then t:SetHeight(1) else t:SetWidth(1) end
      f.cardLines[#f.cardLines + 1] = t
    end
    Line("TOPLEFT", "TOPRIGHT", true) Line("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Line("TOPLEFT", "BOTTOMLEFT") Line("TOPRIGHT", "BOTTOMRIGHT")
  end
  local function Edge(self, edge, edgeAlpha)
    local e = RGB(edge or "cardEdge")
    local ea = edgeAlpha or e[4] or 1
    if self.cardEdge then self.cardEdge:SetVertexColor(e[1], e[2], e[3], ea) end
    for _, t in ipairs(self.cardLines or {}) do t:SetVertexColor(e[1], e[2], e[3], ea) end
  end
  function f:SetCardLook(fillTop, fillBottom, fillAlpha, edge, edgeAlpha)
    self._look = { fillTop, fillBottom, fillAlpha, edge, edgeAlpha }
    Gradient(self.cardFill, "VERTICAL", fillBottom or "cardLow", fillAlpha or 0.92, fillTop or "card", fillAlpha or 0.92)
    Edge(self, edge, edgeAlpha)
  end
  -- mouse over: a brighter gold edge
  function f:SetCardHover(on)
    local l = self._look or {}
    if on then Edge(self, "goldLight", 0.85) else Edge(self, l[4], l[5]) end
  end
  f:SetCardLook()
  return f
end

local fontPath
local function FontPath()
  if fontPath then return fontPath end
  local obj = _G.GameFontHighlightSmall
  local ok, path = false, nil
  if type(obj) == "table" and type(obj.GetFont) == "function" then ok, path = pcall(obj.GetFont, obj) end
  fontPath = (ok and type(path) == "string" and path) or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  return fontPath
end

local function SetColor(fs, color, alpha)
  local c = RGB(color)
  fs:SetTextColor(c[1], c[2], c[3], alpha or 1)
end

local function Text(parent, size, color, justify, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlightSmall")
  if size and fs.SetFont then pcall(fs.SetFont, fs, FontPath(), size, "") end
  SetColor(fs, color or "textPrimary")
  if justify then fs:SetJustifyH(justify) end
  fs:SetWordWrap(false)
  return fs
end

local function Icon(parent, size, file, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetSize(size, size)
  -- a texture the client does not have: a plain square instead of nothing
  if file and t:SetTexture(file) == false then t:SetTexture(WHITE) end
  return t
end

local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function TextWidth(fs)
  local w = ns.Num(fs.GetStringWidth and fs:GetStringWidth())
  if w and w > 0 then return w end
  return #Plain(fs:GetText()) * 6
end

-- (i18n) A text in a fixed space (Style.FitText): first a little smaller, then
-- cut with "..."; the whole text then shows in the tooltip of its line or tile.
local function Fit(fs, budget, owner)
  local ok = Style.FitText(fs, budget)
  if owner then
    owner._cut = owner._cut or {}
    owner._cut[fs] = (not ok) and Style.FullText(fs) or nil
  end
  return ok
end

local function CutLines(owner)
  if type(owner._cut) ~= "table" then return nil end
  local out = {}
  for _, t in pairs(owner._cut) do out[#out + 1] = t end
  if #out == 0 then return nil end
  table.sort(out)
  return out
end

local function ShowCut(owner)
  local cut = CutLines(owner)
  if not cut then return false end
  local rest = {}
  for i = 2, #cut do rest[#rest + 1] = cut[i] end
  Style.Tooltip(owner, cut[1], rest, nil, "ANCHOR_RIGHT")
  return true
end

-- A plain frame that shows its cut texts on mouse over.
local function CutTip(f)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self) ShowCut(self) end)
  f:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
end

-- Width of a list line: its real width in the game, else what the layout gives it.
local function RowW(f)
  local w = ns.Num(f.GetWidth and f:GetWidth())
  if w and w > 50 then return w end
  return (f._list and f._list.rowW) or (W - 20)
end

local function LevelRGB(level)
  local hex = level and level > 0 and ns.LevelColor and ns.LevelColor(level)
  local r, g, b = tostring(hex or ""):match("|cff(%x%x)(%x%x)(%x%x)")
  if not r then return C.textHint end
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

local function Shift() return ns.True(ns.Value(IsShiftKeyDown)) end

local mapNames = {}
local function MapName(m)
  if not m then return nil end
  local n = mapNames[m]
  if n == nil then
    local info = ns.Value(C_Map.GetMapInfo, m)
    n = type(info) == "table" and type(info.name) == "string" and ns.Usable(info.name) and info.name ~= "" and info.name or false
    if n then mapNames[m] = n end
  end
  return n or nil
end

local function ContinentName(c) return (c ~= FOREVER and MapName(c)) or L[CONT_FALLBACK[c] or "Other"] end

-- Money with the coin icons of the game: 1[gold] 85[silver] 3[copper]
local COIN = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
local function Coins(copper, size)
  copper = ns.Num(copper)
  if not copper or copper <= 0 then return nil end
  local parts = { math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100 }
  local out, icon = {}, ":" .. (size or 0) .. ":" .. (size or 0) .. ":2:0|t"
  for i, n in ipairs(parts) do
    if n > 0 then out[#out + 1] = n .. "|T" .. COIN[i] .. icon end
  end
  return table.concat(out, " ")
end

-- Mouse behaviour of a clickable line: hover, tooltip (fn returns title, lines, hint), click.
local function Clickable(f)
  f:EnableMouse(true)
  f.hover = Tex(f, "BACKGROUND", "rowHover", nil, 1)
  f.hover:SetAllPoints(f)
  f.hover:Hide()
  if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  f:SetScript("OnEnter", function(self)
    if self.onClick or self.tooltip then
      if self.SetCardHover and self.cardFill:IsShown() then self:SetCardHover(true) else self.hover:Show() end
    end
    -- (1.3.4) the detail card is open: it says all of it, no second tooltip for a quest line
    local card = self.questTip and ns.QuestBookDetailID and ns.QuestBookDetailID() ~= nil
    if self.tooltip and not card then
      local ok, title, lines, hint = pcall(self.tooltip, self)
      if ok and title then Style.Tooltip(self, title, lines, hint, "ANCHOR_RIGHT") end
    else
      ShowCut(self)
    end
  end)
  f:SetScript("OnLeave", function(self)
    self.hover:Hide()
    if self.SetCardHover then self:SetCardHover(false) end
    Style.HideTooltip(self)
  end)
  f:SetScript("OnClick", function(self, button)
    if self.onClick then ns.SafeCall("quest book", self.onClick, self, button) end
  end)
end

-- A text button with a soft background (chips, segments).
local function Chip(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(22)
  b.bg = Tex(b, "BACKGROUND", "textPrimary", 0.05)
  b.bg:SetAllPoints(b)
  b.text = Text(b, 11, "textSecondary", "CENTER")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetScript("OnEnter", function(self) if not self.on then Fill(self.bg, "textPrimary", 0.10) end ShowCut(self) end)
  b:SetScript("OnLeave", function(self) if not self.on then Fill(self.bg, "textPrimary", 0.05) end Style.HideTooltip(self) end)
  b:SetScript("OnClick", function(self) if onClick then ns.SafeCall("quest book", onClick, self) end end)
  function b:Set(text, on)
    self.text:SetText(text)
    Style.FitText(self.text, 1e6) -- back to the normal size (Layout may make it smaller)
    if self._cut then self._cut[self.text] = nil end
    self.on = on and true or false
    Fill(self.bg, on and "accent" or "textPrimary", on and 0.20 or 0.05)
    SetColor(self.text, on and "textPrimary" or "textSecondary")
    self:SetWidth(TextWidth(self.text) + 20)
  end
  return b
end

---------------------------------------------------------------------------
-- Virtual list: items { kind, h, ... }; one pool of frames per kind
---------------------------------------------------------------------------
local function NewList(parent, factories, rowW)
  local list = CreateFrame("Frame", nil, parent)
  list.rowW = rowW -- width of a line when the game cannot tell yet (layout constants)
  list.items, list.offset, list.pools, list.used, list.factories = {}, 1, {}, {}, factories
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(self, delta) self:Scroll(-(tonumber(delta) or 0) * 3) end)
  list.track = Tex(list, "ARTWORK", "barBackground")
  list.track:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, 0)
  list.track:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -1, 0)
  list.track:SetWidth(3)
  list.thumb = Tex(list, "OVERLAY", "textHint", 0.9)
  list.thumb:SetWidth(3)
  list:SetScript("OnSizeChanged", function(self) self:Render() end)

  function list:Height()
    local h = ns.Num(self:GetHeight()) or 0
    if h <= 1 then h = 420 end
    return h
  end
  function list:SetItems(items, keep)
    self.items = items or {}
    if not keep then self.offset = 1 end
    self:Render()
  end
  function list:MaxOffset()
    local h, sum = self:Height(), 0
    for i = #self.items, 1, -1 do
      sum = sum + (self.items[i].h or ROW_H)
      if sum > h then return math.min(#self.items, i + 1) end
    end
    return 1
  end
  function list:Scroll(d)
    local o = math.max(1, math.min(self:MaxOffset(), self.offset + d))
    if o ~= self.offset then self.offset = o self:Render() end
  end
  function list:ScrollTo(i)
    self.offset = math.max(1, math.min(self:MaxOffset(), i or 1))
    self:Render()
  end
  function list:Acquire(kind)
    local pool = self.pools[kind]
    if not pool then pool = {} self.pools[kind] = pool end
    for _, r in ipairs(pool) do if not r.inUse then r.inUse = true return r end end
    local r = self.factories[kind].create(self)
    r._list = self
    r.inUse = true
    pool[#pool + 1] = r
    return r
  end
  function list:Render()
    for _, r in ipairs(self.used) do r:Hide() r.inUse = false end
    self.used = {}
    local h, y = self:Height(), 0
    if self.offset > self:MaxOffset() then self.offset = self:MaxOffset() end
    for i = self.offset, #self.items do
      local it = self.items[i]
      local ih = it.h or ROW_H
      if y > 0 and y + ih > h + 0.5 then break end
      local row = self:Acquire(it.kind)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -8, -y)
      row:SetHeight(ih)
      row.item = it
      row:Show()
      ns.SafeCall("quest book row", self.factories[it.kind].render, row, it)
      self.used[#self.used + 1] = row
      y = y + ih
    end
    local total, before = 0, 0
    for i, it in ipairs(self.items) do
      total = total + (it.h or ROW_H)
      if i < self.offset then before = before + (it.h or ROW_H) end
    end
    if total <= h then
      self.thumb:Hide() self.track:Hide()
    else
      local th = math.max(18, h * h / total)
      local pos = (h - th) * math.min(1, before / math.max(1, total - h))
      self.thumb:ClearAllPoints()
      self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -1, -pos)
      self.thumb:SetHeight(th)
      self.thumb:Show() self.track:Show()
    end
  end
  return list
end

local ZoneStats -- below (zones)

---------------------------------------------------------------------------
-- Line kinds
---------------------------------------------------------------------------
-- Section heading: text, count, a thin line, optional right text; clickable.
local HeadKind = {
  create = function(list)
    local f = CreateFrame("Button", nil, list)
    Clickable(f)
    f.text = Text(f, 12, "gold", "LEFT")
    f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 7)
    f.count = Text(f, 11, "textHint", "LEFT")
    f.count:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
    f.right = Text(f, 11, "textHint", "RIGHT")
    f.right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7)
    f.line = Tex(f, "ARTWORK", "divider")
    f.line:SetHeight(1)
    return f
  end,
  render = function(f, it)
    f.text:SetText(it.text or "")
    SetColor(f.text, (it.color == nil or it.color == "textPrimary") and "gold" or it.color)
    f.count:SetText(it.count and tostring(it.count) or "")
    f.right:SetText(it.right or "")
    local rw = RowW(f)
    local rightW = 0
    if it.right and it.right ~= "" then Fit(f.right, rw * 0.45, f) rightW = TextWidth(f.right) + 16 end
    local countW = it.count and (TextWidth(f.count) + 6) or 0
    Fit(f.text, rw - 40 - countW - rightW, f)
    f.line:ClearAllPoints()
    f.line:SetPoint("LEFT", f.count, "RIGHT", 8, 0)
    if it.right and it.right ~= "" then
      f.line:SetPoint("RIGHT", f.right, "LEFT", -8, 0)
    else
      f.line:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    end
    f.onClick, f.tooltip = it.onClick, it.tooltip
    f:EnableMouse(it.onClick ~= nil or it.tooltip ~= nil)
  end,
}

local EmptyKind = {
  create = function(list)
    local f = CreateFrame("Frame", nil, list)
    f.text = Text(f, 12, "textHint", "CENTER")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text:SetWordWrap(true) -- (i18n) a long note wraps instead of running out of the list
    return f
  end,
  render = function(f, it)
    f.text:SetWidth(math.max(100, RowW(f) - 40))
    f.text:SetText(it.text or "")
  end,
}

-- (1.3.4) Thin edges around a region (pills, level boxes).
local function Edges(f, region, color, alpha, layer)
  local c = RGB(color)
  local out = {}
  local function Line(p1, p2, horiz)
    local t = f:CreateTexture(nil, layer or "BORDER")
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], alpha or 1)
    t:SetPoint(p1, region, p1) t:SetPoint(p2, region, p2)
    if horiz then t:SetHeight(1) else t:SetWidth(1) end
    out[#out + 1] = t
  end
  Line("TOPLEFT", "TOPRIGHT", true) Line("BOTTOMLEFT", "BOTTOMRIGHT", true)
  Line("TOPLEFT", "BOTTOMLEFT") Line("TOPRIGHT", "BOTTOMRIGHT")
  function out:SetColor(col, a)
    local cc = RGB(col)
    for _, t in ipairs(self) do t:SetVertexColor(cc[1], cc[2], cc[3], a or 1) end
  end
  return out
end

-- A status pill on the right of a line: filled, framed, short text.
local function NewPill(f)
  f.pillText = Text(f, 11, "textPrimary", "RIGHT", "OVERLAY")
  f.pillText:SetPoint("RIGHT", f, "RIGHT", -18, 0)
  f.pill = Tex(f, "ARTWORK", "accent", 0.30)
  f.pill:SetPoint("TOPLEFT", f.pillText, "TOPLEFT", -9, 5)
  f.pill:SetPoint("BOTTOMRIGHT", f.pillText, "BOTTOMRIGHT", 9, -5)
  f.pillEdge = Edges(f, f.pill, "accent", 0.8, "ARTWORK")
end
local function SetPill(f, text, color, room)
  if text and text ~= "" then
    f.pillText:SetText(text)
    Fit(f.pillText, room or 130, f)
    local c = color or "textSecondary"
    SetColor(f.pillText, c == "textHint" and "textSecondary" or "textPrimary")
    Fill(f.pill, c, c == "textHint" and 0.14 or 0.34)
    f.pillEdge:SetColor(c, c == "textHint" and 0.35 or 0.85)
    f.pillText:Show() f.pill:Show()
    for _, t in ipairs(f.pillEdge) do t:Show() end
    return TextWidth(f.pillText) + 36
  end
  f.pillText:Hide() f.pill:Hide()
  for _, t in ipairs(f.pillEdge) do t:Hide() end
  return 0
end

-- Journal line (1.3.4: a card): a status mark in a round disc, "[6] Title",
-- what happened, zone, time and how long the quest took; XP and money or a
-- status pill on the right. Level-ups as a golden card.
local PILL_KIND = { a = { "accepted", "warning" }, x = { "abandoned", "textHint" }, f = { "failed", "critical" } }
local EntryKind = {
  create = function(list)
    local f = CreateFrame("Button", nil, list)
    Card(f, 4, 3)
    Clickable(f)
    f.active = Tex(f, "BACKGROUND", "rowActive", nil, 2)
    f.active:SetAllPoints(f.cardFill)
    f.disc = Icon(f, 24, CIRCLE, "ARTWORK")
    f.disc:SetPoint("CENTER", f, "LEFT", 28, 0)
    local d = THEME.cardLow
    f.disc:SetVertexColor(d[1] * 0.7, d[2] * 0.7, d[3] * 0.7, 1)
    f.ring = Icon(f, 30, MEDIA .. "BookRing", "ARTWORK")
    f.ring:SetPoint("CENTER", f.disc, "CENTER", 0, 0)
    f.icon = Icon(f, 15, nil, "OVERLAY")
    f.icon:SetPoint("CENTER", f.disc, "CENTER", 0, 0)
    f.title = Text(f, 14, "textPrimary", "LEFT")
    f.sub = Text(f, 11, "textHint", "LEFT")
    f.r1 = Text(f, 14, "warning", "RIGHT")
    f.r1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -9)
    f.r2 = Text(f, 11, "textSecondary", "RIGHT")
    f.r2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 9)
    NewPill(f)
    return f
  end,
  render = function(f, it)
    local e = it.e
    local level = e.k == "l"
    local small = e.k == "o"
    f.icon:SetTexture(ICON[e.k] or ICON.o)
    if f.icon.SetDesaturated then f.icon:SetDesaturated(e.k == "o" or e.k == "x") end
    f.icon:SetAlpha((e.k == "o" or e.k == "x") and 0.6 or 1)
    local disc = small and 18 or 24
    f.disc:SetSize(disc, disc) f.ring:SetSize(disc + 6, disc + 6) f.icon:SetSize(small and 11 or 15, small and 11 or 15)
    if level then
      f:SetCardLook("goldDark", "cardLow", 0.92, "gold", 0.75)
    elseif small then
      f:SetCardLook("cardLow", "cardLow", 0.55, "cardEdge", 0.14)
    else
      f:SetCardLook()
    end
    local title, sub, r1, r2, pill, pillColor
    if level then
      title = Colorize(Fmt.EntryTitle(e), "goldLight")
      local parts = { e.t and Fmt.Clock(e.t) or nil }
      if e.since then parts[#parts + 1] = L["after %s"]:format(Fmt.Span(e.since) or "?") end
      if it.quests and it.quests > 0 then parts[#parts + 1] = L["%d quests on the way"]:format(it.quests) end
      sub = table.concat(parts, "  ·  ")
    else
      local quiet = e.k == "x" or e.k == "o"
      local tag = ns.QuestLevelTag(e.q)
      if quiet then tag = Plain(tag) end
      local name = Fmt.EntryTitle(e)
      if it.part then name = name .. Colorize(("  (%s)"):format(it.part), "textHint") end
      title = quiet and Colorize(tag .. name, "textHint") or (tag .. name)
      local what = Colorize(L[Fmt.KIND_TEXT[e.k] or "done earlier"], Fmt.KIND_COLOR[e.k] or "textHint")
      local parts = { what }
      local zone = e.m and MapName(e.m)
      if zone then parts[#parts + 1] = zone end
      if e.t then parts[#parts + 1] = Fmt.Clock(e.t) end
      if it.took and it.took > 0 then parts[#parts + 1] = L["took %s"]:format(Fmt.Span(it.took) or "?") end
      sub = parts[1] .. Colorize("  ·  " .. table.concat(parts, "  ·  ", 2), "textHint")
      if #parts == 1 then sub = what end
      if e.x then r1 = "+" .. Style.Number(e.x) .. " " .. L["XP"] end
      r2 = Coins(e.g)
      if not r1 and not r2 and PILL_KIND[e.k] then pill, pillColor = L[PILL_KIND[e.k][1]], PILL_KIND[e.k][2] end
      if small then
        local m = ns.QuestStart(e.q)
        sub, r2 = nil, nil
        r1 = m and MapName(m) and Colorize(MapName(m), "textHint") or nil
      end
    end
    f.title:SetText(title)
    f.sub:SetText(sub or "")
    f.r1:ClearAllPoints()
    if small or not r2 then f.r1:SetPoint("RIGHT", f, "RIGHT", -18, 0) else f.r1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -9) end
    if small then f.r1:SetFontObject("GameFontHighlightSmall") end
    f.r1:SetText(r1 or "")
    f.r2:SetText(r2 or "")
    Fit(f.r1, 120, f) Fit(f.r2, 120, f)
    local rightW = math.max(SetPill(f, pill, pillColor), (r1 or r2) and 130 or 0)
    f.title:ClearAllPoints()
    f.sub:ClearAllPoints()
    local left = small and 48 or 54
    Fit(f.title, RowW(f) - left - rightW - 10, f) Fit(f.sub, RowW(f) - left - rightW - 10, f)
    local h = ns.Num(f:GetHeight()) or it.h or ROW_H
    if sub and sub ~= "" then
      local top = math.floor((h - 32) / 2)
      f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top - 1)
      f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -rightW, -top - 1)
      f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top - 18)
      f.sub:SetPoint("TOPRIGHT", f, "TOPRIGHT", -rightW, -top - 18)
    else
      f.title:SetPoint("LEFT", f, "LEFT", left, 0)
      f.title:SetPoint("RIGHT", f, "RIGHT", -rightW, 0)
    end
    local focus = ns.zoneFocus and ns.zoneFocus.questID
    if e.q and (focus == e.q or ns.QuestBookDetailID() == e.q) then f.active:Show() else f.active:Hide() end
    -- (1.3.5) click: the detail card; Shift-click: also arrow and world map
    f.onClick = e.q and function() ns.QuestBookShowQuest(e.q, Shift() and "map" or nil) end or nil
    f.tooltip = Fmt.EntryTooltip(e)
    f.questTip = e.q ~= nil
  end,
}

-- Quest line (1.3.4: a card): level in a framed box, title (with the dots of
-- a chain), what it is about, a framed status pill on the right. Chain parts
-- and the steps before a dungeon quest are indented.
local MAX_DOTS = 12
local QuestKind = {
  create = function(list)
    local f = CreateFrame("Button", nil, list)
    Card(f, 4, 3)
    Clickable(f)
    f.active = Tex(f, "BACKGROUND", "rowActive", nil, 2)
    f.active:SetAllPoints(f.cardFill)
    f.bar = Tex(f, "ARTWORK", "gold")
    f.bar:SetPoint("TOPLEFT", f.cardFill, "TOPLEFT", 0, -4)
    f.bar:SetPoint("BOTTOMLEFT", f.cardFill, "BOTTOMLEFT", 0, 4)
    f.bar:SetWidth(3)
    f.badge = Tex(f, "ARTWORK", "cardLow", 0.95)
    f.badge:SetSize(28, 24)
    f.badgeEdge = Edges(f, f.badge, "gold", 0.55, "ARTWORK")
    f.level = Text(f, 12, "textPrimary", "CENTER")
    f.level:SetPoint("CENTER", f.badge, "CENTER", 0, 0)
    f.title = Text(f, 14, "textPrimary", "LEFT")
    f.sub = Text(f, 11, "textHint", "LEFT")
    NewPill(f)
    f.toggle = Style.IconButton(f, "expand")
    f.toggle:SetSize(18, 18)
    f.toggle:SetOnClick(function() if f.onClick then ns.SafeCall("quest book", f.onClick, f) end end)
    f.dots = {}
    for i = 1, MAX_DOTS do
      local d = Icon(f, 7, CIRCLE, "OVERLAY")
      f.dots[i] = d
    end
    -- (1.3.4) steps before a dungeon quest: a numbered circle on a gold line
    f.vline = Tex(f, "BORDER", "gold", 0.45)
    f.vline:SetWidth(2)
    f.stepDisc = Icon(f, 22, CIRCLE, "ARTWORK")
    local cl = THEME.cardLow
    f.stepDisc:SetVertexColor(cl[1], cl[2], cl[3], 1)
    f.stepRing = Icon(f, 28, MEDIA .. "BookRing", "OVERLAY")
    f.stepRing:SetPoint("CENTER", f.stepDisc, "CENTER", 0, 0)
    f.stepNum = Text(f, 11, "goldLight", "CENTER", "OVERLAY")
    f.stepNum:SetPoint("CENTER", f.stepDisc, "CENTER", 0, 0)
    -- (1.3.4) the dungeon quest itself: a small "Dungeon quest" label over the title
    f.goalLabel = Text(f, 10, "gold", "LEFT")
    return f
  end,
  render = function(f, it)
    local indent = it.indent or 0
    local step = it.step
    f.cardFill:ClearAllPoints()
    f.cardFill:SetPoint("TOPLEFT", f, "TOPLEFT", 4 + indent + (step and 30 or 0), -3)
    f.cardFill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 3)
    if it.goal then f:SetCardLook("card", "cardLow", 0.98, "gold", 0.85)
    elseif indent > 0 or step then f:SetCardLook("cardLow", "cardLow", 0.85, "cardEdge", 0.22)
    else f:SetCardLook() end
    if step then
      f.vline:ClearAllPoints()
      f.vline:SetPoint("TOP", f, "TOPLEFT", 4 + indent + 13, it.firstStep and -math.floor((ns.Num(f:GetHeight()) or ROW_H) / 2) or 0)
      f.vline:SetPoint("BOTTOM", f, "BOTTOMLEFT", 4 + indent + 13, it.lastStep and math.floor((ns.Num(f:GetHeight()) or ROW_H) / 2) or 0)
      f.stepDisc:ClearAllPoints()
      f.stepDisc:SetPoint("CENTER", f, "LEFT", 4 + indent + 14, 0)
      f.stepNum:SetText(tostring(step))
      f.vline:Show() f.stepDisc:Show() f.stepRing:Show() f.stepNum:Show()
      indent = indent + 30
    else
      f.vline:Hide() f.stepDisc:Hide() f.stepRing:Hide() f.stepNum:Hide()
    end
    f.badge:ClearAllPoints()
    f.badge:SetPoint("LEFT", f, "LEFT", 14 + indent, 0)
    local lv = it.level and it.level > 0 and it.level or nil
    f.level:SetText(lv and tostring(lv) or "?")
    local lc = it.quiet and THEME.textHint or LevelRGB(lv)
    f.level:SetTextColor(lc[1], lc[2], lc[3], 1)
    local title = it.title or ""
    if it.goal then title = Colorize(Plain(title), it.quiet and "gold" or "goldLight") elseif it.quiet then title = Colorize(title, "textSecondary") end
    f.title:SetText(title)
    if f.title.SetFont then pcall(f.title.SetFont, f.title, FontPath(), it.goal and 15 or 14, "") end
    f.sub:SetText(it.sub or "")
    f.title:ClearAllPoints()
    f.sub:ClearAllPoints()
    local left = 52 + indent
    if it.goal then
      f.goalLabel:SetText(L["Dungeon quest"])
      f.goalLabel:ClearAllPoints()
      f.goalLabel:SetPoint("TOPLEFT", f, "TOPLEFT", left, -7)
      f.goalLabel:Show()
    else
      f.goalLabel:Hide()
    end
    local h = ns.Num(f:GetHeight()) or it.h or ROW_H
    local pillW = SetPill(f, it.pill, it.pillColor)
    local rightW = math.max(pillW, 40)
    if it.goal then
      f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -20)
      f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", left, -39)
      f.sub:SetPoint("TOPRIGHT", f, "TOPRIGHT", -rightW, -39)
    elseif it.sub and it.sub ~= "" then
      local top = math.floor((h - 32) / 2)
      f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top - 1)
      f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top - 18)
      f.sub:SetPoint("TOPRIGHT", f, "TOPRIGHT", -rightW, -top - 18)
    else
      f.title:SetPoint("LEFT", f, "LEFT", left, 0)
    end
    -- the dots of a chain right after the title
    local n = it.dots and #it.dots or 0
    local room = math.min(380, RowW(f) - left - rightW - n * 10 - (it.chain and 26 or 0))
    Fit(f.title, room, f)
    if it.sub and it.sub ~= "" then Fit(f.sub, RowW(f) - left - rightW, f) end
    local tw = math.min(TextWidth(f.title), room)
    for i, d in ipairs(f.dots) do
      local c = it.dots and it.dots[i]
      if c and i <= n then
        d:ClearAllPoints()
        d:SetPoint("LEFT", f.title, "LEFT", tw + 8 + (i - 1) * 10, 0)
        local rgb = RGB(c)
        d:SetVertexColor(rgb[1], rgb[2], rgb[3], c == "textHint" and 0.45 or 1)
        d:Show()
      else
        d:Hide()
      end
    end
    f.title:SetWidth(tw + 2)
    if it.chain then
      f.toggle:SetKind(it.open and "collapse" or "expand")
      f.toggle:ClearAllPoints()
      f.toggle:SetPoint("LEFT", f.title, "LEFT", tw + 8 + n * 10 + 4, 0)
      f.toggle:Show()
    else
      f.toggle:Hide()
    end
    if it.active then f.active:Show() f.bar:Show() else f.active:Hide() f.bar:Hide() end
    f.onClick, f.tooltip = it.onClick, it.tooltip
    f.questTip = it.questID ~= nil and not it.chain
  end,
}

-- Zone in the list on the left: name, level range, progress bar.
local ZoneKind = {
  create = function(list)
    local f = CreateFrame("Button", nil, list)
    Clickable(f)
    f.sel = Tex(f, "BACKGROUND", "accent", 0.14, 2)
    f.sel:SetAllPoints(f)
    f.selBar = Tex(f, "ARTWORK", "accent")
    f.selBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.selBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.selBar:SetWidth(2)
    f.here = Icon(f, 7, CIRCLE, "OVERLAY")
    f.here:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    f.here:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.name = Text(f, 12, "textPrimary", "LEFT")
    f.range = Text(f, 10, "textHint", "RIGHT")
    f.range:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
    f.track = Tex(f, "ARTWORK", "barBackground")
    f.track:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 7)
    f.track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -52, 7)
    f.track:SetHeight(3)
    f.fill = Tex(f, "OVERLAY", "gold")
    f.fill:SetPoint("TOPLEFT", f.track, "TOPLEFT", 0, 0)
    f.fill:SetPoint("BOTTOMLEFT", f.track, "BOTTOMLEFT", 0, 0)
    Gradient(f.fill, "HORIZONTAL", "goldDark", 1, "goldLight", 1)
    -- (1.3.4) "12/48" next to the bar
    f.num = Text(f, 9, "textHint", "RIGHT")
    f.num:SetPoint("RIGHT", f, "BOTTOMRIGHT", -10, 8)
    return f
  end,
  render = function(f, it)
    f.name:ClearAllPoints()
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", it.here and 24 or 12, -7)
    f.name:SetPoint("RIGHT", f.range, "LEFT", -6, 0)
    f.name:SetText(it.name or "?")
    -- counted only for the zones in sight (cached until a quest is accepted or turned in)
    local s = it.map and ZoneStats(it.map)
    SetColor(f.name, (s and s.total == 0) and "textHint" or (it.selected and "textPrimary" or "textSecondary"))
    f.range:SetText(it.range or "")
    Fit(f.range, 70, f)
    Fit(f.name, RowW(f) - (it.here and 24 or 12) - 16 - TextWidth(f.range), f)
    if it.here then f.here:Show() else f.here:Hide() end
    if it.selected then f.sel:Show() f.selBar:Show() else f.sel:Hide() f.selBar:Hide() end
    if s and s.total > 0 then
      f.track:Show()
      f.num:SetText(("%d/%d"):format(s.done, s.total)) f.num:Show()
      local w = math.max(1, (ns.Num(f:GetWidth()) or (SIDE_W - 30)) - 64)
      local frac = s.done / s.total
      if frac > 0 then f.fill:SetWidth(math.max(1, w * frac)) f.fill:Show() else f.fill:Hide() end
    else
      f.track:Hide() f.fill:Hide() f.num:Hide()
    end
    f.onClick, f.tooltip = it.onClick, it.tooltip
  end,
}

-- (1.3.5) The chosen dungeon in plain words: "3 / 6 ready" large on the left with a gold bar, the sentences
-- (what is ready, what needs quests first, what opens later) on the right.
local DunSumKind = {
  create = function(list)
    local f = CreateFrame("Frame", nil, list)
    Card(f, 4, 4)
    f.big = Text(f, 26, "goldLight", "CENTER")
    f.big:SetPoint("TOP", f, "TOPLEFT", 74, -12)
    f.bigLabel = Text(f, 11, "textSecondary", "CENTER")
    f.bigLabel:SetPoint("TOP", f.big, "BOTTOM", 0, -3)
    f.track = Tex(f, "ARTWORK", "barBackground")
    f.track:SetSize(110, 4)
    f.track:SetPoint("TOP", f.bigLabel, "BOTTOM", 0, -6)
    f.fill = Tex(f, "OVERLAY", "gold")
    f.fill:SetPoint("TOPLEFT", f.track, "TOPLEFT", 0, 0)
    f.fill:SetPoint("BOTTOMLEFT", f.track, "BOTTOMLEFT", 0, 0)
    f.sep = Tex(f, "ARTWORK", "gold", 0.35)
    f.sep:SetWidth(1)
    f.sep:SetPoint("TOPLEFT", f, "TOPLEFT", 146, -12)
    f.sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 146, 12)
    f.fit = Text(f, 12, "good", "LEFT")
    f.fit:SetPoint("TOPLEFT", f, "TOPLEFT", 162, -12)
    f.lines = {}
    for i = 1, 4 do
      local t = Text(f, 13, "textPrimary", "LEFT")
      t:SetPoint("TOPLEFT", f, "TOPLEFT", 162, -12 - 17 * i)
      f.lines[i] = t
    end
    return f
  end,
  render = function(f, it)
    f:SetCardLook("card", "cardLow", 0.97, "gold", 0.7)
    f.big:SetText(("%d / %d"):format(it.ready or 0, math.max(it.open or 0, it.ready or 0)))
    f.bigLabel:SetText((it.open or 0) == 0 and L["all done"] or L["ready"])
    local frac = (it.total or 0) > 0 and ((it.ready or 0) + (it.done or 0)) / it.total or 0
    if frac > 0 then f.fill:SetWidth(math.max(1, 110 * math.min(1, frac))) f.fill:Show() else f.fill:Hide() end
    local room = RowW(f) - 162 - 16
    f.fit:SetText((it.fitText or "") .. ((it.done or 0) > 0 and Colorize("  ·  " .. L["%d of %d done"]:format(it.done, it.total), "textHint") or ""))
    SetColor(f.fit, it.fitColor or "textHint")
    Fit(f.fit, room, f)
    for i, t in ipairs(f.lines) do
      t:SetText(it.lines and it.lines[i] or "")
      Fit(t, room, f)
    end
  end,
}

-- (1.3.5) One line of text under a quest: the way to it in colours, or the colour legend.
local DunPathKind = {
  create = function(list)
    local f = CreateFrame("Frame", nil, list)
    f.text = Text(f, 11, "textSecondary", "LEFT")
    return f
  end,
  render = function(f, it)
    f.text:ClearAllPoints()
    if it.legend then
      f.text:SetPoint("LEFT", f, "LEFT", 14, 0)
      SetColor(f.text, "textHint")
    else
      f.text:SetPoint("LEFT", f, "LEFT", (it.indent or 0) + 4, 2)
      SetColor(f.text, "textSecondary")
    end
    f.text:SetText(it.text or "")
    Fit(f.text, RowW(f) - (it.indent or 0) - 20, f)
  end,
}

-- (1.3.5, Daniel 10.10.: "a small fitting picture of the instance"; "the number is completely off-centre")
-- The round badge of a dungeon: its picture (Dungeons.lua: the game client's own art, nothing shipped),
-- masked round inside the gold ring. Without a picture the level, in a box as large as the circle and
-- centred in it both ways (before, the text only had its CENTER point on the circle).
local function BadgeParts(f, disc, size)
  f.pic = f:CreateTexture(nil, "ARTWORK", nil, 1)
  f.pic:SetSize(size - 2, size - 2)
  f.pic:SetPoint("CENTER", disc, "CENTER", 0, 0)
  if f.CreateMaskTexture then
    local ok, mask = pcall(f.CreateMaskTexture, f)
    if ok and mask then
      pcall(mask.SetTexture, mask, CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(f.pic)
      if f.pic.AddMaskTexture then pcall(f.pic.AddMaskTexture, f.pic, mask) end
      f.picMask = mask
    end
  end
  f.pic:Hide()
  f.level:ClearAllPoints()
  f.level:SetPoint("CENTER", disc, "CENTER", 0, 0)
  if f.level.SetSize then f.level:SetSize(size, size) end
  f.level:SetJustifyH("CENTER")
  if f.level.SetJustifyV then f.level:SetJustifyV("MIDDLE") end
  f.badgeSize = size
end
-- Picture of inst, else levelText. true when the picture shows.
local function SetBadge(f, inst, levelText, quiet)
  local tex, source
  if inst then tex, source = ns.DungeonIcon(inst) end
  local shown = false
  if tex then
    -- (round 8) an icon of the icon set: without its dark frame, so the ring holds only the picture
    if f.pic.SetTexCoord then
      if source == "icon" then f.pic:SetTexCoord(0.08, 0.92, 0.08, 0.92) else f.pic:SetTexCoord(0, 1, 0, 1) end
    end
    local ok, res = pcall(f.pic.SetTexture, f.pic, tex)
    local got = f.pic.GetTexture and f.pic:GetTexture()
    if ok and res ~= false and (res == true or got ~= nil) then shown = true else ns.DungeonIconFailed(inst) end
  end
  if shown then
    if f.pic.SetDesaturated then f.pic:SetDesaturated(quiet and true or false) end
    f.pic:Show()
    f.level:Hide()
  else
    f.pic:Hide()
    f.level:SetText(levelText or "?")
    f.level:Show()
  end
  f.picShown = shown
  return shown
end
ns.QuestBookSetBadge = SetBadge -- (tests)
ns.QuestBookBadgeParts = BadgeParts -- (tests)

-- (1.3.5) A line of the dungeon dropdown: picture (or level) in a gold ring, name, fit, what is ready.
local DunPickKind = {
  create = function(list)
    local f = CreateFrame("Button", nil, list)
    Clickable(f)
    f.sel = Tex(f, "BACKGROUND", "rowActive", nil, 2)
    f.sel:SetAllPoints(f)
    f.disc = Icon(f, 26, CIRCLE, "ARTWORK")
    f.disc:SetPoint("CENTER", f, "LEFT", 22, 0)
    f.ring = Icon(f, 32, MEDIA .. "BookRing", "OVERLAY")
    f.ring:SetPoint("CENTER", f.disc, "CENTER", 0, 0)
    f.level = Text(f, 11, "textPrimary", "CENTER", "OVERLAY")
    BadgeParts(f, f.disc, 26)
    f.name = Text(f, 13, "goldLight", "LEFT")
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", 44, -5)
    f.fit = Text(f, 11, "good", "LEFT")
    f.fit:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
    f.sub = Text(f, 11, "textHint", "LEFT")
    f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 44, -22)
    -- (1.3.5) a tick when all your quests of the dungeon are done
    f.tick = Icon(f, 16, "Interface\\RAIDFRAME\\ReadyCheck-Ready", "ARTWORK")
    f.tick:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    return f
  end,
  render = function(f, it)
    if it.selected then f.sel:Show() else f.sel:Hide() end
    if it.done then f.tick:Show() else f.tick:Hide() end
    f.name:SetAlpha(it.quiet and 0.6 or 1)
    SetBadge(f, it.inst, it.minL and tostring(it.minL) or "?", it.quiet)
    local c = RGB(it.fitColor or "textHint")
    f.disc:SetVertexColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45, 1)
    f.level:SetTextColor(c[1], c[2], c[3], 1)
    f.name:SetText(it.text or "")
    f.fit:SetText(it.fitText or "")
    SetColor(f.fit, it.fitColor or "textHint")
    f.sub:SetText(it.sub or "")
    local room = RowW(f) - 44 - 12 - (it.done and 22 or 0)
    Fit(f.name, room * 0.65, f)
    Fit(f.fit, room - TextWidth(f.name) - 8, f)
    Fit(f.sub, room, f)
    f.onClick, f.tooltip = it.onClick, it.tooltip
  end,
}

local KINDS = { head = HeadKind, empty = EmptyKind, entry = EntryKind, quest = QuestKind, zone = ZoneKind,
  dsum = DunSumKind, dpath = DunPathKind, dpick = DunPickKind }

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
local function PlayerFaction()
  local f = ns.Value(UnitFactionGroup, "player")
  return f == "Horde" and "H" or (f == "Alliance" and "A" or nil)
end

local function ZoneOf(m)
  m = ns.Num(m)
  if not m then return nil end
  return ns.MinimapZoneMap and ns.MinimapZoneMap(m) or m
end

local function HereZone() return ZoneOf(ns.Value(C_Map.GetBestMapForUnit, "player")) end

-- The zone the book shows: the picked one, else the open world map's, else yours.
local function ShownZone()
  if selZone then return selZone end
  return ns.ZoneQuestsMap and ns.ZoneQuestsMap() or HereZone()
end

function ZoneStats(m)
  local s = stats[m]
  if not s then
    local list = ns.ZoneQuestList(m)
    s = { total = #list, done = 0, groups = {} }
    for _, e in ipairs(list) do
      if e.group == "done" then s.done = s.done + 1 end
      s.groups[e.group] = (s.groups[e.group] or 0) + 1
    end
    stats[m] = s
  end
  return s
end

local function RangeText(z)
  if not z then return "" end
  if not z.min then return L["City"] end
  return L["%d to %d"]:format(z.min, z.max or z.min)
end

local function Norm(s) return tostring(s or ""):lower() end

---------------------------------------------------------------------------
-- Building the lists
---------------------------------------------------------------------------
local Refresh

-- Journal: filtered entries with day headings; quests per level-up.
local FILTERS = { "all", "c", "a", "x", "l", "zone" }
local FILTER_TITLE = { all = "All", c = "Completed", a = "Accepted", x = "Abandoned", l = "Levels", zone = "This zone" }

local function Keep(e, filter, here)
  if filter == "all" then return true end
  if filter == "x" then return e.k == "x" or e.k == "f" end
  if filter == "zone" then return e.m ~= nil and ZoneOf(e.m) == here end
  return e.k == filter
end

local oldCache, oldKey
local function OldDoneList()
  local j = ns.JournalStore()
  local n = 0
  if j then for _ in pairs(j.old) do n = n + 1 end end
  local key = n .. ":" .. (j and #j.e or 0)
  if oldCache and oldKey == key then return oldCache end
  local out = {}
  for _, o in ipairs(Fmt.OldDone()) do
    -- only quests this character could do and that have a place (no hidden
    -- flags of the server, no quests of the other faction or old data)
    local learned = ns.db.learned and ns.db.learned[o.q]
    local real = ns.QuestInData(o.q) and ns.QuestReachable(o.q) and ns.QuestStart(o.q) ~= nil
      and not (ns.QuestKnownMissing and ns.QuestKnownMissing(o.q))
    if real or (learned and learned.start) then out[#out + 1] = o end
  end
  oldCache, oldKey = out, key
  return out
end

local function JournalItems()
  local items = {}
  local entries = ns.JournalEntries()
  -- quests completed before each level-up (entries are newest first)
  local count, perLevel = 0, {}
  for i = #entries, 1, -1 do
    local e = entries[i]
    if e.k == "c" then count = count + 1 elseif e.k == "l" then perLevel[e] = count count = 0 end
  end
  local here = HereZone()
  -- (1.3.4) one line per quest: a quest turned in later hides its "accepted"
  -- line, the turned-in line says how long it took (filters "all" and "zone")
  local merge = jfilter == "all" or jfilter == "zone"
  local doneAt, took, hidden = {}, {}, {}
  if merge then
    for _, e in ipairs(entries) do -- newest first
      if e.q and e.k == "c" and not doneAt[e.q] then doneAt[e.q] = e
      elseif e.q and e.k == "a" and doneAt[e.q] and not hidden[e] and not took[doneAt[e.q]] then
        hidden[e] = true
        if e.t and doneAt[e.q].t then took[doneAt[e.q]] = doneAt[e.q].t - e.t end
      end
    end
  end
  -- day totals for the headings: quests, XP, XP per hour (first to last entry of the day)
  local days = {}
  for _, e in ipairs(entries) do
    if e.t then
      local key = Fmt.DayKey(e.t)
      local d = days[key]
      if not d then d = { q = 0, xp = 0 } days[key] = d end
      d.first = math.min(d.first or e.t, e.t)
      d.last = math.max(d.last or e.t, e.t)
      if e.k == "c" then d.q = d.q + 1 d.xp = d.xp + (ns.Num(e.x) or 0) end
    end
  end
  local function DayRight(key)
    local d = days[key]
    if not d or d.q == 0 then return nil end
    local parts = { L["%d quests"]:format(d.q) }
    if d.xp > 0 then
      parts[#parts + 1] = "+" .. Style.Number(d.xp) .. " " .. L["XP"]
      local hours = math.max(0.25, ((d.last or 0) - (d.first or 0)) / 3600)
      parts[#parts + 1] = L["%s XP/h"]:format(Style.Number(math.floor(d.xp / hours)))
    end
    return table.concat(parts, "  ·  ")
  end
  local day
  for _, e in ipairs(entries) do
    if Keep(e, jfilter, here) and not hidden[e] then
      local key = e.t and Fmt.DayKey(e.t) or -1
      if key ~= day then
        day = key
        items[#items + 1] = { kind = "head", h = HEAD_H, text = e.t and Fmt.DayTitle(e.t) or L["Unknown date"], color = "textPrimary",
          right = e.t and DayRight(key) or nil }
      end
      items[#items + 1] = { kind = "entry", h = ROW_H, e = e, quests = perLevel[e], took = took[e] }
    end
  end
  local old = {}
  if jfilter == "all" or jfilter == "c" then old = OldDoneList() end
  if #old > 0 then
    items.oldAt = #items + 1
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Done earlier (no date)"], count = #old,
      tooltip = function() return L["Done earlier (no date)"], { { L["Kept per character. Quests done before the journal have no date."] } } end }
    for _, o in ipairs(old) do items[#items + 1] = { kind = "entry", h = SMALL_H, e = { k = "o", q = o.q, n = o.title } } end
  end
  if #items == 0 then
    items[1] = { kind = "empty", h = 60, text = jfilter == "all" and L["Nothing written yet. Accept or turn in a quest."] or L["Nothing for this filter."] }
  end
  items.old = #old
  return items
end

-- Status of a quest as a short coloured word for the right side.
local function Pill(e)
  if e.group == "log" then return e.text, e.color end
  if e.group == "available" then return e.text, e.color end
  if e.group == "done" then return L["done (turned in)"], "good" end
  return L["later"], "textHint"
end

local function QuestSubText(e)
  if e.group == "later" then return e.text end
  if e.group == "done" then return nil end
  local givers = ns.QuestGiverIDs(e.questID)
  local giver = givers and ns.LocalNpcName(givers[1])
  local learned = ns.db.learned and ns.db.learned[e.questID]
  giver = giver or (learned and learned.start and learned.start.npc)
  return giver and (L["Quest giver"] .. ": " .. giver) or nil
end

-- (1.3) quests only in the older data: a note until Forever confirms them
local function QuestSub(e)
  local sub = QuestSubText(e)
  if e.unconfirmed then
    local note = Colorize(L["not seen in Forever yet"], "warning")
    sub = sub and (sub .. "  ·  " .. note) or note
  end
  return sub
end

local DOT = { done = "good", log = "warning", available = "accent", later = "textHint" }

local function FocusID() return ns.zoneFocus and ns.zoneFocus.questID end

local function QuestItem(e, extra)
  local pill, color = Pill(e)
  local it = { kind = "quest", h = ROW_H, questID = e.questID, level = e.level, title = e.title or ns.QuestTitle(e.questID),
    sub = QuestSub(e), pill = pill, pillColor = color, quiet = e.group == "done" or e.group == "later",
    active = FocusID() == e.questID or ns.QuestBookDetailID() == e.questID, tooltip = ns.ZoneQuestTooltip(e) }
  -- (1.3.5, Daniel 08.10. Merkliste) a click shows the detail card only, the arrow stays where it
  -- was; the card's buttons point the arrow and open the map. Shift-click: all at once.
  it.onClick = function() ns.QuestBookShowQuest(e.questID, Shift() and "map" or nil) end
  if extra then for k, v in pairs(extra) do it[k] = v end end
  return it
end

-- Parts of a chain in order: a part whose previous quest is in the chain comes after it.
local function ChainOrder(parts)
  table.sort(parts, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.questID < b.questID
  end)
  local ids = {}
  for _, p in ipairs(parts) do ids[p.questID] = p end
  local out, placed = {}, {}
  local function Place(p, depth)
    if placed[p] or depth > 20 then return end
    for _, pre in ipairs(ns.QuestPrereqs and ns.QuestPrereqs(p.questID) or {}) do
      local q = ids[pre]
      if q and q ~= p then Place(q, depth + 1) end
    end
    if not placed[p] then placed[p] = true out[#out + 1] = p end
  end
  for _, p in ipairs(parts) do Place(p, 0) end
  return out
end

local function ZoneQuestItems(m)
  local items = {}
  local list = m and ns.ZoneQuestList(m) or {}
  local s = { total = #list, done = 0, groups = {} }
  for _, e in ipairs(list) do
    if e.group == "done" then s.done = s.done + 1 end
    s.groups[e.group] = (s.groups[e.group] or 0) + 1
  end
  if m then stats[m] = s end
  -- one line per title (a chain of quests with the same name)
  local byKey, order = {}, {}
  for _, e in ipairs(list) do
    local k = Norm(e.title) ~= "" and Norm(e.title) or tostring(e.questID)
    local g = byKey[k]
    if not g then g = { key = (m or 0) .. ":" .. k, parts = {}, rep = e } byKey[k] = g order[#order + 1] = g end
    g.parts[#g.parts + 1] = e
  end
  -- (1.3.4) filter by group; nearest first within each group (start of the quest)
  if zFilter ~= "all" then
    local keep = {}
    for _, g in ipairs(order) do if g.rep.group == zFilter then keep[#keep + 1] = g end end
    order = keep
  end
  if zNear and ns.PlayerWorld and ns.DistanceFrom then
    local pc, pn, pw = ns.PlayerWorld()
    local rank = {}
    for i, g in ipairs(order) do
      local sm, sx, sy = ns.QuestStart(g.rep.questID)
      local d = sm and pc and pn and ns.DistanceFrom(pc, pn, pw, { mapID = sm, x = sx / 100, y = sy / 100 })
      g.dist, rank[g] = d, i
    end
    local GR = { log = 1, available = 2, later = 3, done = 4 }
    table.sort(order, function(a, b)
      local ga, gb = GR[a.rep.group] or 5, GR[b.rep.group] or 5
      if ga ~= gb then return ga < gb end
      local da, db = a.dist or 1e9, b.dist or 1e9
      if da ~= db then return da < db end
      return rank[a] < rank[b]
    end)
  end
  local counts = {}
  for _, g in ipairs(order) do counts[g.rep.group] = (counts[g.rep.group] or 0) + 1 end
  local group
  for _, g in ipairs(order) do
    local e = g.rep
    if e.group ~= group then
      group = e.group
      local head = { kind = "head", h = HEAD_H, text = L[ns.ZONE_GROUP_TITLE[group]], count = counts[group] }
      if group == "done" and zFilter ~= "done" then
        head.right = showDone and L["hide"] or L["show"]
        head.onClick = function() showDone = not showDone Refresh() end
      end
      items[#items + 1] = head
    end
    if group ~= "done" or showDone or zFilter == "done" then
      if #g.parts == 1 then
        local it = QuestItem(e)
        if zNear and g.dist then
          local yd = L["%d yards"]:format(math.floor(g.dist + 0.5))
          it.sub = it.sub and (it.sub .. "  ·  " .. yd) or yd
        end
        items[#items + 1] = it
      else
        local parts = ChainOrder(g.parts)
        local done, dots, active = 0, {}, false
        for i, p in ipairs(parts) do
          if p.group == "done" then done = done + 1 end
          dots[i] = DOT[p.group] or "textHint"
          if FocusID() == p.questID then active = true end
        end
        local open = expanded[g.key] and true or false
        local sub = QuestSub(e)
        sub = L["Chain of %d"]:format(#parts) .. (sub and ("  ·  " .. sub) or "")
        local it = QuestItem(e, { title = e.title, sub = sub, dots = dots, chain = true, open = open, active = active and not open })
        it.title = (e.title or "") .. Colorize(("  %d/%d"):format(done, #parts), "textHint")
        it.onClick = function() expanded[g.key] = not expanded[g.key] or nil Refresh() end
        it.tooltip = function()
          local lines = {}
          for i, p in ipairs(parts) do
            lines[#lines + 1] = { L["Part %d"]:format(i), p.text, p.color }
          end
          return e.title, lines, L["Click: show or hide the parts."]
        end
        items[#items + 1] = it
        if open then
          for i, p in ipairs(parts) do
            items[#items + 1] = QuestItem(p, { indent = 22, h = ROW_H, title = L["Part %d of %d"]:format(i, #parts),
              level = p.level })
          end
        end
      end
    end
  end
  if #items == 0 then items[1] = { kind = "empty", h = 60, text = L["No quests known for this zone."] } end
  return items, s
end

local function ZoneJournalItems(m)
  local items = {}
  local day
  for _, e in ipairs(ns.JournalEntries()) do
    if e.m and ZoneOf(e.m) == m then
      local key = e.t and Fmt.DayKey(e.t) or -1
      if key ~= day then
        day = key
        items[#items + 1] = { kind = "head", h = HEAD_H, text = e.t and Fmt.DayTitle(e.t) or L["Unknown date"], color = "textPrimary" }
      end
      items[#items + 1] = { kind = "entry", h = ROW_H, e = e }
    end
  end
  if #items == 0 then items[1] = { kind = "empty", h = 60, text = L["Nothing in your journal for this zone yet."] } end
  return items
end

local function SelectZone(m)
  selZone = m
  zoneSeg = "quests"
  if lists.zone then lists.zone.offset = 1 end
  if tab ~= "zone" then ns.OpenQuestBook("zone") else Refresh() end
end
ns.QuestBookSelectZone = SelectZone

local function ZoneRow(z, shown, here)
  local m = z.map
  return { kind = "zone", h = 34, map = m, name = MapName(m) or ("Map " .. m), range = RangeText(z),
    here = m == here, selected = m == shown,
    onClick = function() SelectZone(m) end,
    tooltip = function()
      local st = ZoneStats(m)
      local lines = {
        { L["Level"], RangeText(z) },
        { L["Quests"], L["%d of %d done"]:format(st.done, st.total) },
      }
      -- (1.3.4) what is left, by group
      for _, g in ipairs({ "log", "available", "later" }) do
        local n = st.groups and st.groups[g]
        if n and n > 0 then lines[#lines + 1] = { L[ns.ZONE_GROUP_TITLE[g]], tostring(n) } end
      end
      return MapName(m) or ("Map " .. m), lines
    end }
end

local function ZoneListItems()
  local items = {}
  local faction = PlayerFaction()
  local here, shown = HereZone(), ShownZone()
  local hereInfo = here and ZONE_INFO[here]
  local q = Norm(zoneQuery):gsub("^%s+", ""):gsub("%s+$", "")
  -- a zone the book does not list (a new Forever zone): first
  if shown and not ZONE_INFO[shown] and #ns.QuestsStartingOnMap(shown) > 0 then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Here"] }
    items[#items + 1] = ZoneRow({ map = shown }, shown, here)
  end
  for _, cont in ipairs({ KALIMDOR, EASTERN, FOREVER }) do
    local rows = {}
    for _, z in ipairs(ZONES) do
      if z[2] == cont and not (z[5] and faction and z[5] ~= faction) then
        local info = ZONE_INFO[z[1]]
        local name = MapName(z[1]) or ""
        if q == "" or Norm(name):find(q, 1, true) then rows[#rows + 1] = info end
      end
    end
    if #rows > 0 then
      local open = contOpen[cont]
      if open == nil then open = (hereInfo and hereInfo.cont == cont) or (not hereInfo and cont == KALIMDOR) end
      if q ~= "" then open = true end
      items[#items + 1] = { kind = "head", h = HEAD_H, text = ContinentName(cont), right = open and "-" or "+",
        onClick = function() contOpen[cont] = not open Refresh() end }
      if open then
        table.sort(rows, function(a, b)
          local am, bm = a.min or 99, b.min or 99
          if am ~= bm then return am < bm end
          return tostring(MapName(a.map)) < tostring(MapName(b.map))
        end)
        for _, z in ipairs(rows) do items[#items + 1] = ZoneRow(z, shown, here) end
      end
    end
  end
  if #items == 0 then items[1] = { kind = "empty", h = 50, text = L["No zone found."] } end
  return items
end

-- Search: zones, journal entries, quests of the data.
local function SearchItems()
  local items = {}
  local q = Norm(query):gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then
    items[1] = { kind = "empty", h = 80, text = L["Type to search your journal, all quests and zones."] }
    return items
  end
  local faction = PlayerFaction()
  local zones = {}
  for _, z in ipairs(ZONES) do
    if not (z[5] and faction and z[5] ~= faction) and Norm(MapName(z[1])):find(q, 1, true) then zones[#zones + 1] = ZONE_INFO[z[1]] end
  end
  if #zones > 0 then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Zones"], count = #zones }
    local here, shown = HereZone(), nil
    for _, z in ipairs(zones) do items[#items + 1] = ZoneRow(z, shown, here) end
  end
  local hits, quests = ns.JournalSearch(query)
  if #hits > 0 then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["In your journal"], count = #hits }
    for _, e in ipairs(hits) do items[#items + 1] = { kind = "entry", h = ROW_H, e = e } end
  end
  -- what you can do first: in the log, available, later, done, not for you;
  -- then by level (unknown last)
  local RANK = { log = 1, available = 2, later = 3, done = 4 }
  for _, r in ipairs(quests) do
    local group, text, color = ns.ZoneQuestStatus(r.q)
    r.group, r.text, r.color = group, text, color
  end
  table.sort(quests, function(a, b)
    local ra, rb = RANK[a.group] or 5, RANK[b.group] or 5
    if ra ~= rb then return ra < rb end
    local la, lb = a.level > 0 and a.level or 999, b.level > 0 and b.level or 999
    if la ~= lb then return la < lb end
    if a.title ~= b.title then return tostring(a.title) < tostring(b.title) end
    return a.q < b.q
  end)
  if #quests > 0 then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Quests"], count = #quests > MAX_QUESTS and (MAX_QUESTS .. "+") or #quests }
    for i = 1, math.min(#quests, MAX_QUESTS) do
      local r = quests[i]
      local group, text, color = r.group, r.text, r.color
      local e = { questID = r.q, group = group or "later", text = text or L["not yet"], color = color or "textHint", level = r.level, title = r.title }
      local it = QuestItem(e)
      local zone = r.m and MapName(r.m)
      it.sub = zone and ((group == "later" and text) and (zone .. "  ·  " .. text) or zone) or it.sub
      if not group then it.pill, it.pillColor = L["not for you"], "textHint" end
      items[#items + 1] = it
    end
  end
  if #items == 0 then items[1] = { kind = "empty", h = 60, text = L["Nothing found."] } end
  return items
end

---------------------------------------------------------------------------
-- (1.3.3) Dungeons: per dungeon its quests for you; under an open quest the
-- quests still to do before it, deepest first (the order you walk them).
---------------------------------------------------------------------------

-- (1.3.4) What to do in a quest in one line: Wowhead's objective sentence, else the
-- objective mobs and items of the data ("Kobold Digger, Riverpaw Miner"); nil if unknown.
function ns.QuestTodo(id)
  local t = ns.QuestText and ns.QuestText(id)
  if t and type(t.o) == "string" and t.o ~= "" then return t.o end
  local objs = ns.ATT_OBJECTIVES and ns.ATT_OBJECTIVES[id]
  if type(objs) ~= "table" then return nil end
  local names, seen = {}, {}
  for _, o in pairs(objs) do
    if type(o) == "table" then
      for _, i in ipairs(type(o[2]) == "table" and o[2] or {}) do
        local n = ns.ItemName(i)
        if n and not seen[n] then seen[n] = true names[#names + 1] = n end
      end
      if #(type(o[2]) == "table" and o[2] or {}) == 0 then
        for _, c in ipairs(type(o[1]) == "table" and o[1] or {}) do
          local n = ns.LocalNpcName(c)
          if n and not seen[n] then seen[n] = true names[#names + 1] = n end
          break
        end
      end
    end
    if #names >= 3 then break end
  end
  return #names > 0 and table.concat(names, ", ") or nil
end

local function QuestEntry(id)
  local group, text, color, unconfirmed = ns.ZoneQuestStatus(id)
  if not group then return nil end
  return { questID = id, group = group, text = text, color = color, unconfirmed = unconfirmed,
    level = ns.QuestLevel(id) or 0, title = ns.QuestTitleWithPart(id) } -- (1.3.4) "(1/2)" where parts share a title
end

local function StartZone(id)
  local m = ns.QuestStart(id)
  return m and MapName(ZoneOf(m) or m) or nil
end

local function WithZone(sub, id)
  local zone = StartZone(id)
  if not zone then return sub end
  return sub and (sub .. "  ·  " .. zone) or zone
end

-- Prerequisites not done yet, the earliest first.
-- (1.3.4) stop: quest IDs with their own line in the list (the other quests
-- of the dungeon). Daniel 08.10.: "Destruction in Deadmines (2/2)" listed the
-- whole chain again under part 1/2; now the chain stops at part 1/2, which
-- stands above with its own steps.
function ns.DungeonQuestChain(id, stop)
  local out, seen = {}, { [id] = true }
  local function Walk(q, depth)
    if depth > 12 then return end
    for _, pre in ipairs(ns.QuestPrereqs(q) or {}) do
      if not seen[pre] then
        seen[pre] = true
        if not ns.IsQuestDone(pre) and not (stop and stop[pre]) then
          Walk(pre, depth + 1)
          local e = QuestEntry(pre)
          if e then out[#out + 1] = e end
        end
      end
    end
  end
  Walk(id, 0)
  return out
end

local DUN_RANK = { log = 1, available = 2, later = 3, done = 4 }
-- (1.3.5, Daniel 10.10.: "a dropdown with the dungeons, then their quests and what each needs first, more than
-- 'later', readable for anyone") one dungeon at a time, chosen at the top; below it in plain words what you can
-- do now, what to do first (numbered, with what it unlocks), what is not yet and why (with the way to it), done.
local dunSel -- instanceID chosen in the dropdown (nil: the one that fits you)

-- (1.3.5) sorted by their level range (Dungeons.lua: the game's, else Data/Dungeon_Levels.lua)
local function DungeonInsts()
  local insts = {}
  for inst in pairs(ns.ATT_DUNGEONS or {}) do
    if #ns.DungeonQuestIDs(inst) > 0 then insts[#insts + 1] = inst end
  end
  local lo, hi = {}, {}
  for _, inst in ipairs(insts) do
    local a, b = ns.DungeonLevelRange(inst)
    lo[inst], hi[inst] = a or 99, b or a or 99
  end
  table.sort(insts, function(a, b)
    if lo[a] ~= lo[b] then return lo[a] < lo[b] end
    if hi[a] ~= hi[b] then return hi[a] < hi[b] end
    return a < b
  end)
  return insts
end

-- Your quests of a dungeon: entries (QuestEntry) and how many are done.
local function DungeonEntries(inst)
  local entries, done = {}, 0
  for _, id in ipairs(ns.DungeonQuestIDs(inst)) do
    local e = QuestEntry(id)
    if e then
      entries[#entries + 1] = e
      if e.group == "done" then done = done + 1 end
    end
  end
  return entries, done
end

-- (1.3.5) In plain words against the dungeon's level range: fits, in n levels (red), below your level
-- (Dungeons.lua, the same words as the entrance pins).
local function LevelsToGo(n) return n == 1 and L["in 1 level"] or L["in %d levels"]:format(n) end
local function FitOf(inst) return ns.DungeonFitText(inst, ns.PlayerLevel() or 1) end
local function RangeOf(inst)
  local lo, hi = ns.DungeonLevelRange(inst)
  if not lo then return nil end
  return L["Level %d-%d"]:format(lo, hi or lo)
end

-- The dungeon shown: the chosen one, else the one you are in, else the first that fits you with quests left,
-- else the next one up, else the first.
local function SelectedDungeon(insts)
  insts = insts or DungeonInsts()
  local have = {}
  for _, inst in ipairs(insts) do have[inst] = true end
  if dunSel and have[dunSel] then return dunSel end
  -- (1.3.5) chosen on the map (an entrance pin): also a dungeon without quests for you
  if dunSel and ns.ATT_DUNGEONS and ns.ATT_DUNGEONS[dunSel] then return dunSel end
  local here = ns.CurrentDungeon and ns.CurrentDungeon()
  if here and have[here] then return here end
  -- (1.3.5) the first one of your level with quests left, else the next one up
  local player = ns.PlayerLevel() or 1
  local nextUp
  for _, inst in ipairs(insts) do
    local entries, done = DungeonEntries(inst)
    local fit = ns.DungeonFit(inst, player)
    if done < #entries then
      if fit == "fits" then return inst end
      if not nextUp and fit == "later" then nextUp = inst end
    end
  end
  return nextUp or insts[1]
end
ns.QuestBookSelectedDungeon = function() return SelectedDungeon() end -- (tests)
function ns.QuestBookSelectDungeon(inst) dunSel = inst if Refresh then Refresh(true) end end

-- A title without what it shares with the one before ("The Defias Brotherhood (2/7)" after (1/7): "(2/7)").
local function ShortAfter(prev, title)
  local base = title:match("^(.-)%s*%(%d+/%d+%)$")
  local pbase = prev and prev:match("^(.-)%s*%(%d+/%d+%)$")
  if base and pbase and base == pbase then return title:match("(%(%d+/%d+%))$") end
  return title
end

-- The way to a dungeon quest, done steps too: "Defias Brotherhood (1/7) » (2/7) » ... » this quest", each step
-- in the colour of its state.
local PATH_COLOR = { done = "good", log = "warning", available = "accent", later = "textHint" }
local function DungeonPath(id)
  local out, seen = {}, { [id] = true }
  local function Walk(q, depth)
    if depth > 12 then return end
    for _, pre in ipairs(ns.QuestPrereqs(q) or {}) do
      if not seen[pre] then
        seen[pre] = true
        Walk(pre, depth + 1)
        local e = QuestEntry(pre)
        if e then out[#out + 1] = e end
      end
    end
  end
  Walk(id, 0)
  if #out == 0 then return nil end
  local parts, prev = {}, nil
  for _, e in ipairs(out) do
    local t = Plain(e.title or ns.QuestTitle(e.questID) or "?")
    parts[#parts + 1] = Colorize(ShortAfter(prev, t), PATH_COLOR[e.group] or "textHint")
    prev = t
  end
  parts[#parts + 1] = Colorize(L["this quest"], "gold")
  return table.concat(parts, Colorize("  »  ", "textHint"))
end
ns.QuestBookDungeonPath = DungeonPath -- (tests)

local function DungeonItems()
  local items = {}
  local insts = DungeonInsts()
  if #insts == 0 then
    items[1] = { kind = "empty", h = 60, text = L["No dungeon quests known for you."] }
    return items
  end
  local inst = SelectedDungeon(insts)
  local entries, done = DungeonEntries(inst)
  local own = {}
  for _, e in ipairs(entries) do own[e.questID] = true end
  table.sort(entries, function(a, b)
    local ra, rb = DUN_RANK[a.group] or 5, DUN_RANK[b.group] or 5
    if ra ~= rb then return ra < rb end
    local la, lb = a.level > 0 and a.level or 999, b.level > 0 and b.level or 999
    if la ~= lb then return la < lb end
    return a.questID < b.questID
  end)
  -- the steps before the dungeon quests: each once, with the dungeon quests it unlocks
  local steps, stepIdx, unlocks = {}, {}, {}
  for _, e in ipairs(entries) do
    if e.group ~= "done" then
      for _, p in ipairs(ns.DungeonQuestChain(e.questID, own)) do
        if not stepIdx[p.questID] then
          steps[#steps + 1] = p
          stepIdx[p.questID] = #steps
          unlocks[p.questID] = {}
        end
        local u = unlocks[p.questID]
        u[#u + 1] = Plain(e.title or ns.QuestTitle(e.questID) or "?")
      end
    end
  end
  local stepOf = {}
  for _, p in ipairs(steps) do
    local n = 1
    for _, pre in ipairs(ns.QuestPrereqs(p.questID) or {}) do if stepOf[pre] then n = math.max(n, stepOf[pre] + 1) end end
    stepOf[p.questID] = n
  end
  local n = { log = 0, available = 0, later = 0 }
  local laterLevel, afterQuest, firstLevel = 0, 0, nil
  for _, e in ipairs(entries) do
    if n[e.group] then n[e.group] = n[e.group] + 1 end
    if e.group == "later" then
      if #ns.DungeonQuestChain(e.questID, own) > 0 then afterQuest = afterQuest + 1
      else
        laterLevel = laterLevel + 1
        local lv = ns.QuestMinLevel and ns.QuestMinLevel(e.questID) or e.level
        if lv and lv > 0 and (not firstLevel or lv < firstLevel) then firstLevel = lv end
      end
    end
  end
  local ready, open = n.log + n.available, #entries - done
  -- the summary in plain words
  local lines = {}
  if #entries == 0 then
    lines[1] = L["No quests of this dungeon for you."]
  elseif open == 0 then
    lines[1] = L["All quests of this dungeon done."]
  else
    if ready == 0 then lines[#lines + 1] = L["Nothing to take right now."]
    elseif ready == 1 then lines[#lines + 1] = L["1 quest is ready (in your log or to take)."]
    else lines[#lines + 1] = L["%d quests are ready (in your log or to take)."]:format(ready) end
    if afterQuest == 1 then lines[#lines + 1] = L["1 needs other quests first: see Do these first."]
    elseif afterQuest > 1 then lines[#lines + 1] = L["%d need other quests first: see Do these first."]:format(afterQuest) end
    if laterLevel == 1 then lines[#lines + 1] = L["1 opens later (from level %d)."]:format(firstLevel or 0)
    elseif laterLevel > 1 then lines[#lines + 1] = L["%d open later (the first from level %d)."]:format(laterLevel, firstLevel or 0) end
  end
  local fitText, fitColor = FitOf(inst)
  items[#items + 1] = { kind = "dsum", h = 34 + 17 * #lines, inst = inst, ready = ready, open = open, done = done,
    total = #entries, lines = lines, fitText = fitText, fitColor = fitColor }
  -- take now: in the log first, then to pick up
  local now = {}
  for _, e in ipairs(entries) do if e.group == "log" or e.group == "available" then now[#now + 1] = e end end
  if #now > 0 then
    items[#items + 1] = { kind = "head", h = 30, text = L["Take now"], color = "good", count = #now }
    for _, e in ipairs(now) do
      local it = QuestItem(e, { goal = true, h = 62 })
      local todo = ns.QuestTodo(e.questID)
      if e.group == "log" then
        it.sub = Colorize(L["In your log"], "warning") .. (todo and ("  ·  " .. todo) or "")
      else
        it.sub = WithZone(QuestSubText(e) or todo, e.questID)
      end
      items[#items + 1] = it
    end
  end
  -- do these first: numbered, each with what it unlocks
  if #steps > 0 then
    items[#items + 1] = { kind = "head", h = 30, text = L["Do these first"], color = "warning", count = #steps }
    for i, p in ipairs(steps) do
      local c = QuestItem(p, { indent = 4, step = stepOf[p.questID], firstStep = i == 1, lastStep = i == #steps })
      local what = L["Unlocks: %s"]:format(table.concat(unlocks[p.questID], ", "))
      if p.group == "later" then
        c.sub = Colorize(p.text or L["not yet"], "textHint") .. "  ·  " .. what
      else
        c.sub = WithZone(what, p.questID)
      end
      items[#items + 1] = c
    end
  end
  -- not yet: why, and the way to it
  local later = {}
  for _, e in ipairs(entries) do if e.group == "later" then later[#later + 1] = e end end
  if #later > 0 then
    items[#items + 1] = { kind = "head", h = 30, text = L["Not yet"], color = "textSecondary", count = #later }
    for _, e in ipairs(later) do
      local it = QuestItem(e, { goal = true, h = 62 })
      local chain = ns.DungeonQuestChain(e.questID, own)
      if #chain > 0 then
        local first = chain[1]
        it.sub = L["Opens after: %s"]:format(Plain(first.title or ns.QuestTitle(first.questID) or "?"))
      else
        it.sub = e.text or L["not yet"]
      end
      items[#items + 1] = it
      local path = DungeonPath(e.questID)
      if path then items[#items + 1] = { kind = "dpath", h = 24, text = path, indent = 52 } end
    end
  end
  if done > 0 then
    items[#items + 1] = { kind = "head", h = 30, text = L["Done"], color = "good", count = done }
    for _, e in ipairs(entries) do
      if e.group == "done" then items[#items + 1] = QuestItem(e, { h = 40 }) end
    end
  end
  items[#items + 1] = { kind = "dpath", h = 30, legend = true,
    text = L["Colours: %s done, %s in your log, %s to take, %s not yet."]:format(Colorize(L["green"], "good"),
      Colorize(L["yellow"], "warning"), Colorize(L["blue"], "accent"), Colorize(L["grey"], "textHint")) }
  return items
end

-- The dropdown's lines, (1.3.5, Daniel 10.10.) in groups by your level: "Your level (n)" (inside the
-- dungeon's range), "Coming up" (each "in n levels" in red), then "Below your level" and "All quests done"
-- in grey. Each line: name, its level range, how many of its quests are done, a tick when all are done.
local DUN_GROUPS = { "fits", "later", "below", "done" }
function ns.QuestBookDungeonChoices()
  local out = {}
  local sel = SelectedDungeon()
  local player = ns.PlayerLevel() or 1
  local groups = { fits = {}, later = {}, below = {}, done = {} }
  for _, inst in ipairs(DungeonInsts()) do
    local entries, done = DungeonEntries(inst)
    local ready = 0
    for _, e in ipairs(entries) do if e.group == "log" or e.group == "available" then ready = ready + 1 end end
    local fit, n = ns.DungeonFit(inst, player)
    local allDone = #entries > 0 and done == #entries
    local key = allDone and "done" or fit or "later"
    local lo = ns.DungeonLevelRange(inst)
    local sub = L["%d of %d quests done"]:format(done, #entries)
    if fit == "later" and not allDone then sub = Colorize(LevelsToGo(n), "critical") .. "  ·  " .. sub
    elseif ready > 0 then sub = sub .. "  ·  " .. L["%d ready"]:format(ready) end
    local quiet = key == "below" or key == "done"
    table.insert(groups[key], { kind = "dpick", h = 40, inst = inst, text = ns.DungeonName(inst), minL = lo,
      fitText = RangeOf(inst), fitColor = quiet and "textHint" or (fit == "later" and "critical" or "good"), selected = inst == sel,
      quiet = quiet, done = allDone, sub = sub, group = key, fit = fit, toGo = n, total = #entries, doneCount = done,
      onClick = function() dunSel = inst if P.dunDrop then P.dunDrop:Hide() end Refresh(true) end })
  end
  local titles = { fits = L["Your level (%d)"]:format(player), later = L["Coming up"], below = L["Below your level"], done = L["All quests done"] }
  for _, key in ipairs(DUN_GROUPS) do
    if #groups[key] > 0 then
      out[#out + 1] = { kind = "head", h = 26, text = titles[key], count = #groups[key],
        color = (key == "below" or key == "done") and "textHint" or (key == "later" and "warning" or "good") }
      for _, it in ipairs(groups[key]) do out[#out + 1] = it end
    end
  end
  return out
end
ns.QuestBookDungeonItems = DungeonItems -- (tests)

-- (1.3.4) Route: the arrow leads from quest giver to quest giver, nearest
-- first; accepting the quest (or any of the route) moves on to the next one.
local route
local function RouteOrder(ids)
  local left = {}
  for _, id in ipairs(ids) do left[#left + 1] = id end
  local out = {}
  local pc, pn, pw
  if ns.PlayerWorld then pc, pn, pw = ns.PlayerWorld() end
  while #left > 0 do
    local best, bestD = 1, nil
    for i, id in ipairs(left) do
      local m, x, y = ns.QuestStart(id)
      local d = m and pc and pn and ns.DistanceFrom(pc, pn, pw, { mapID = m, x = x / 100, y = y / 100 })
      if d and (not bestD or d < bestD) then best, bestD = i, d end
    end
    local id = table.remove(left, best)
    out[#out + 1] = id
    local m, x, y = ns.QuestStart(id)
    if m and ns.WorldPos then
      local c, n, w = ns.WorldPos(m, x / 100, y / 100)
      if c then pc, pn, pw = c, n, w end
    end
  end
  return out
end
local function RouteNext()
  if not route then return end
  while route.i <= #route.ids and (ns.InQuestLog(route.ids[route.i]) or ns.IsQuestDone(route.ids[route.i])) do route.i = route.i + 1 end
  if route.i > #route.ids then
    route = nil
    ns.Print(L["Route done."])
    return
  end
  local id = route.ids[route.i]
  ns.QuestBookShowQuest(id, "arrow") -- the route leads the arrow
  ns.Print(L["Route %d/%d: %s"]:format(route.i, #route.ids, ns.QuestTitle(id)))
end
function ns.QuestBookRoute(ids)
  if type(ids) ~= "table" or #ids == 0 then route = nil return end
  route = { ids = RouteOrder(ids), i = 1 }
  RouteNext()
end
function ns.QuestBookRouteState() return route end
ns.On("QUEST_ACCEPTED", function(_, a, b)
  if not route then return end
  local id = ns.Num(b) or ns.Num(a)
  local hit = false
  for _, r in ipairs(route.ids) do if r == id then hit = true end end
  if hit then ns.After(0.5, RouteNext) end
end)

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function SavePos()
  local p, _, rp, x, y = book:GetPoint()
  if type(p) == "string" then ns.db.questBookPos = { p, rp or p, ns.Num(x) or 0, ns.Num(y) or 0 } end
end

local function ApplyPos()
  book:ClearAllPoints()
  local pos = ns.db.questBookPos
  if type(pos) == "table" and type(pos[1]) == "string" and pcall(book.SetPoint, book, pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0) then return end
  book:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
end

local function Border(f, color, alpha)
  local t = Tex(f, "BORDER", color, alpha); t:SetPoint("TOPLEFT") t:SetPoint("TOPRIGHT") t:SetHeight(1)
  local b = Tex(f, "BORDER", color, alpha); b:SetPoint("BOTTOMLEFT") b:SetPoint("BOTTOMRIGHT") b:SetHeight(1)
  local l = Tex(f, "BORDER", color, alpha); l:SetPoint("TOPLEFT") l:SetPoint("BOTTOMLEFT") l:SetWidth(1)
  local r = Tex(f, "BORDER", color, alpha); r:SetPoint("TOPRIGHT") r:SetPoint("BOTTOMRIGHT") r:SetWidth(1)
end

-- (i18n) avail: room for the whole row; too long texts get smaller, then cut.
local function Layout(chips, gap, avail)
  gap = gap or 6
  if avail then
    local total, n = 0, 0
    for _, c in ipairs(chips) do
      if c:IsShown() then total = total + (ns.Num(c:GetWidth()) or TextWidth(c.text) + 20) n = n + 1 end
    end
    if n > 0 and total + gap * (n - 1) > avail then
      local each = math.floor((avail - gap * (n - 1)) / n) - 20
      for _, c in ipairs(chips) do
        if c:IsShown() then
          Fit(c.text, each, c)
          c:SetWidth(TextWidth(c.text) + 20)
        end
      end
    end
  end
  local prev
  for _, c in ipairs(chips) do
    if c:IsShown() then
      if prev then
        c:ClearAllPoints()
        c:SetPoint("LEFT", prev, "RIGHT", gap or 6, 0)
      end
      prev = c
    end
  end
end

local function EditBox(parent, placeholderText, onChange, budget)
  local box = CreateFrame("Frame", nil, parent)
  box.bg = Tex(box, "BACKGROUND", "textPrimary", 0.06)
  box.bg:SetAllPoints(box)
  Border(box, "textPrimary", 0.08)
  box.icon = Icon(box, 12, "Interface\\Common\\UI-Searchbox-Icon", "ARTWORK")
  box.icon:SetPoint("LEFT", box, "LEFT", 8, 0)
  box.icon:SetVertexColor(C.textHint[1], C.textHint[2], C.textHint[3], 1)
  local edit = CreateFrame("EditBox", nil, box)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(60)
  edit:SetFontObject(ChatFontNormal or "ChatFontNormal")
  edit:SetPoint("TOPLEFT", box, "TOPLEFT", 26, 0)
  edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 0)
  local tc = C.textPrimary
  if edit.SetTextColor then edit:SetTextColor(tc[1], tc[2], tc[3]) end
  box.placeholder = Text(box, 12, "textHint", "LEFT")
  box.placeholder:SetPoint("LEFT", box, "LEFT", 26, 0)
  box.placeholder:SetText(placeholderText)
  if budget then Fit(box.placeholder, budget, box) CutTip(box) end
  local pending = 0
  edit:SetScript("OnTextChanged", ns.Guard("quest book search", function(self)
    local text = tostring(self:GetText() or "")
    if text == "" then box.placeholder:Show() else box.placeholder:Hide() end
    pending = pending + 1
    local mine = pending
    ns.After(0.2, function() if mine == pending then onChange(text) end end)
  end))
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box.edit = edit
  function box:SetText(text)
    text = tostring(text or "")
    if edit.SetText then edit:SetText(text) end
    if text == "" then self.placeholder:Show() else self.placeholder:Hide() end
  end
  return box
end

-- (1.3.4) The lower right corner of a page's list; the detail card takes its room from the right.
local detailOpen = false
local function ListBR(list, rel, relPoint, x, y)
  list._br = { rel, relPoint, x, y }
  list:SetPoint("BOTTOMRIGHT", rel, relPoint, x - (detailOpen and (DETAIL_W + 12) or 0), y)
end
local function ApplyDetailRoom()
  for key, l in pairs(lists) do
    if key ~= "zones" and l._br then
      local a = l._br
      l:SetPoint("BOTTOMRIGHT", a[1], a[2], a[3] - (detailOpen and (DETAIL_W + 12) or 0), a[4])
    end
  end
end

-- Statistic tile: label, value, small text, optional bar.
local function Tile(parent)
  local t = CreateFrame("Frame", nil, parent)
  Card(t, 0, 0)
  t:SetCardLook("card", "cardLow", 0.92, "gold", 0.45)
  t.label = Text(t, 11, "textSecondary", "LEFT")
  t.label:SetPoint("TOPLEFT", t, "TOPLEFT", 12, -9)
  t.value = Text(t, 22, "textPrimary", "LEFT")
  t.value:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 12, 16)
  t.small = Text(t, 11, "textHint", "LEFT")
  t.small:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 8, 2)
  t.track = Tex(t, "ARTWORK", "barBackground")
  t.track:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 12, 8)
  t.track:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -12, 8)
  t.track:SetHeight(6)
  t.fill = Tex(t, "OVERLAY", "accent")
  t.fill:SetPoint("TOPLEFT", t.track, "TOPLEFT", 0, 0)
  t.fill:SetPoint("BOTTOMLEFT", t.track, "BOTTOMLEFT", 0, 0)
  Gradient(t.fill, "HORIZONTAL", "violet", 1, "cyan", 1)
  t.track:Hide() t.fill:Hide()
  CutTip(t)
  return t
end

-- (1.3.4) XP of the last seven days as small bars in a tile (today on the right, in gold).
local function DayBars(t)
  t.bars = {}
  for i = 1, 7 do
    local b = Tex(t, "ARTWORK", "goldDark", 0.9)
    b:SetWidth(7)
    b:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -12 - (7 - i) * 10, 14)
    t.bars[i] = b
  end
  t:SetScript("OnEnter", function(self)
    if not self.days then ShowCut(self) return end
    local lines = {}
    for i = 7, 1, -1 do
      local d = self.days[i]
      lines[#lines + 1] = { d.label, d.xp > 0 and ("+" .. Style.Number(d.xp) .. " " .. L["XP"]) or "0" }
    end
    Style.Tooltip(self, L["Last 7 days"], lines, nil, "ANCHOR_RIGHT")
  end)
end

local function CreateJournalPage(page)
  -- (1.3.4) the map of your zone, round in a gold ring
  local MAPD = JHERO_H - 20
  local jm = CreateFrame("Frame", nil, page)
  jm:SetSize(MAPD, MAPD)
  jm:SetPoint("TOPLEFT", page, "TOPLEFT", 20, -12)
  jm.base = Icon(jm, MAPD, CIRCLE, "BACKGROUND")
  jm.base:SetAllPoints(jm)
  local cl = THEME.cardLow
  jm.base:SetVertexColor(cl[1], cl[2], cl[3], 1)
  jm.tiles = {}
  if jm.CreateMaskTexture then
    local ok, mask = pcall(jm.CreateMaskTexture, jm)
    if ok and mask then
      pcall(mask.SetTexture, mask, CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(jm)
      jm.mask = mask
    end
  end
  local ringF = CreateFrame("Frame", nil, jm)
  ringF:SetAllPoints(jm)
  local rl = ns.Num(jm.GetFrameLevel and jm:GetFrameLevel())
  if rl and ringF.SetFrameLevel then ringF:SetFrameLevel(rl + 3) end
  jm.ring = ringF:CreateTexture(nil, "OVERLAY")
  jm.ring:SetPoint("CENTER", jm, "CENTER", 0, 0)
  jm.ring:SetSize(MAPD + 18, MAPD + 18)
  if jm.ring:SetTexture(MEDIA .. "BookRing") == false then jm.ring:Hide() end
  jm.name = Text(ringF, 11, "goldLight", "CENTER", "OVERLAY")
  jm.name:SetPoint("BOTTOM", jm, "BOTTOM", 0, 18)
  jm:EnableMouse(true)
  jm:SetScript("OnEnter", function(self) if self.m then Style.Tooltip(self, MapName(self.m) or "?", { { L["Click: show this zone"] } }, nil, "ANCHOR_RIGHT") end end)
  jm:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  jm:SetScript("OnMouseUp", function(self) if self.m then SelectZone(self.m) end end)
  P.jmap = jm
  P.tiles = {}
  for i = 1, 4 do P.tiles[i] = Tile(page) end
  DayBars(P.tiles[2])
  page:SetScript("OnSizeChanged", function(self, w)
    w = (ns.Num(w) or W) - 28 - MAPD - 24
    local each = (w - 10) / 2
    local th = (JHERO_H - 10 - 12) / 2
    P.tileW = each
    for i, t in ipairs(P.tiles) do
      t:ClearAllPoints()
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      t:SetPoint("TOPLEFT", self, "TOPLEFT", 20 + MAPD + 24 + col * (each + 10), -12 - row * (th + 10))
      t:SetSize(each, th)
    end
  end)
  P.chips = {}
  for i, key in ipairs(FILTERS) do
    local c = Chip(page, function() jfilter = key Refresh(true) end)
    c.key = key
    if i == 1 then c:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -JHERO_H - 6) end
    P.chips[i] = c
  end
  P.footer = CreateFrame("Frame", nil, page)
  P.footer:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
  P.footer:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
  P.footer:SetHeight(28)
  local fbg = Tex(P.footer, "BACKGROUND")
  fbg:SetAllPoints(P.footer)
  Gradient(fbg, "VERTICAL", "header", 0.85, "header", 0.0)
  CutTip(P.footer)
  P.footLeft = Text(P.footer, 11, "textHint", "LEFT")
  P.footLeft:SetPoint("LEFT", P.footer, "LEFT", 14, 0)
  P.footOld = CreateFrame("Button", nil, P.footer)
  P.footOld:SetPoint("RIGHT", P.footer, "RIGHT", -10, 0)
  P.footOld:SetHeight(22)
  P.footOld.text = Text(P.footOld, 11, "accent", "RIGHT")
  P.footOld.text:SetPoint("RIGHT", P.footOld, "RIGHT", -4, 0)
  P.footOld:SetScript("OnEnter", function(self) ShowCut(self) end)
  P.footOld:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  P.footOld:SetScript("OnClick", function()
    local l = lists.journal
    if l and l.items.oldAt then l:ScrollTo(l.items.oldAt) end
  end)
  local list = NewList(page, KINDS, W - 2 - 10 - 8)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -JHERO_H - 36)
  ListBR(list, P.footer, "TOPRIGHT", -8, 4)
  lists.journal = list
end

local function UpdateTiles()
  local j = ns.JournalStore()
  local today = Fmt.DayKey(Fmt.Now())
  local q, xp, money, lastLevel = 0, 0, 0, nil
  for _, e in ipairs(j and j.e or {}) do
    if e.k == "c" and e.t and Fmt.DayKey(e.t) == today then
      q = q + 1
      xp = xp + (ns.Num(e.x) or 0)
      money = money + (ns.Num(e.g) or 0)
    elseif e.k == "l" and e.t then
      lastLevel = e.t
    end
  end
  -- (1.3.4) XP per day of the last seven days
  local now = Fmt.Now()
  local days, byKey = {}, {}
  for i = 1, now and 7 or 0 do
    local ts = now - (7 - i) * 86400
    local key = Fmt.DayKey(ts)
    days[i] = { key = key, xp = 0, label = Fmt.DayTitle(ts) }
    byKey[key] = days[i]
  end
  for _, e in ipairs(j and j.e or {}) do
    if e.k == "c" and e.t then
      local d = byKey[Fmt.DayKey(e.t)]
      if d then d.xp = d.xp + (ns.Num(e.x) or 0) end
    end
  end
  local t = P.tiles
  local maxXP = 1
  for _, d in ipairs(days) do maxXP = math.max(maxXP, d.xp) end
  if t[2].bars and #days == 7 then
    t[2].days = days
    for i, b in ipairs(t[2].bars) do
      b:SetHeight(math.max(2, 30 * days[i].xp / maxXP))
      local c = i == 7 and THEME.gold or THEME.goldDark
      if b.SetColorTexture then b:SetColorTexture(c[1], c[2], c[3], i == 7 and 1 or 0.8) end
    end
  end
  t[1].label:SetText(L["Today"])
  t[1].value:SetText(tostring(q))
  t[1].small:SetText(L["quests"])
  t[2].label:SetText(L["Experience today"])
  t[2].value:SetText(xp > 0 and ("+" .. Style.Number(xp)) or "0")
  SetColor(t[2].value, xp > 0 and "goldLight" or "textPrimary")
  t[2].small:SetText("")
  t[3].label:SetText(L["Money today"])
  t[3].value:SetText(Coins(money, 16) or "0")
  t[3].small:SetText("")
  local level = ns.PlayerLevel() or 0
  local cur, max = ns.Num(ns.Value(UnitXP, "player")) or 0, ns.Num(ns.Value(UnitXPMax, "player")) or 0
  t[4].label:SetText(L["Level %d to %d"]:format(level, level + 1))
  if max > 0 then
    local frac = math.max(0, math.min(1, cur / max))
    t[4].value:SetText(("%d %%"):format(math.floor(frac * 100)))
    local w = math.max(1, (ns.Num(t[4]:GetWidth()) or 200) - 24)
    t[4].track:Show()
    if frac > 0 then t[4].fill:SetWidth(w * frac) t[4].fill:Show() else t[4].fill:Hide() end
  else
    t[4].value:SetText("-")
    t[4].track:Hide() t[4].fill:Hide()
  end
  local nowT = Fmt.Now()
  local since = lastLevel and nowT and Fmt.Span(nowT - lastLevel)
  t[4].small:SetText(since and L["%s on this level"]:format(since) or "")
  local each = P.tileW or 300
  for i, tile in ipairs(t) do
    local room = each - 24 - (i == 2 and 80 or 0)
    Fit(tile.label, room, tile)
    Fit(tile.value, room, tile)
    Fit(tile.small, room - 8 - TextWidth(tile.value), tile)
  end
end

local function CreateZonePage(page)
  local side = CreateFrame("Frame", nil, page)
  side:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  side:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
  side:SetWidth(SIDE_W)
  Tex(side, "BACKGROUND", { 0, 0, 0 }, 0.22):SetAllPoints(side)
  local edge = Tex(side, "BORDER", "gold", 0.35)
  edge:SetPoint("TOPRIGHT") edge:SetPoint("BOTTOMRIGHT") edge:SetWidth(1)
  P.zoneBox = EditBox(side, L["Find a zone"], function(text) zoneQuery = text Refresh() end, SIDE_W - 20 - 34)
  P.zoneBox:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -10)
  P.zoneBox:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -10)
  P.zoneBox:SetHeight(24)
  local zl = NewList(side, KINDS, SIDE_W + 2 - 8)
  zl:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -40)
  zl:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 2, 6)
  lists.zones = zl

  local main = CreateFrame("Frame", nil, page)
  main:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
  main:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
  -- the zone's own map as a picture behind its name
  local hero = CreateFrame("Frame", nil, main)
  hero:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
  hero:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, 0)
  hero:SetHeight(HERO_H)
  hero.base = Tex(hero, "BACKGROUND", "header")
  hero.base:SetAllPoints(hero)
  hero.canvas = CreateFrame("Frame", nil, hero)
  hero.canvas:SetAllPoints(hero)
  hero.tiles = {}
  hero.shade = CreateFrame("Frame", nil, hero)
  hero.shade:SetAllPoints(hero)
  local lvl = ns.Num(hero.canvas.GetFrameLevel and hero.canvas:GetFrameLevel())
  if lvl and hero.shade.SetFrameLevel then hero.shade:SetFrameLevel(lvl + 2) end
  hero.dark = Tex(hero.shade, "BACKGROUND", { 0, 0, 0 }, 0.35)
  hero.dark:SetAllPoints(hero.shade)
  hero.fade = Tex(hero.shade, "BORDER", { 0, 0, 0 }, 0.5)
  hero.fade:SetPoint("TOPLEFT") hero.fade:SetPoint("BOTTOMLEFT") hero.fade:SetWidth(360)
  if hero.fade.SetGradient and CreateColor then
    pcall(hero.fade.SetGradient, hero.fade, "HORIZONTAL", CreateColor(0, 0, 0, 0.75), CreateColor(0, 0, 0, 0))
  end
  local bottom = Tex(hero.shade, "BORDER", "gold", 0.6)
  bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(1)
  hero.name = Text(hero.shade, 24, "textPrimary", "LEFT")
  hero.name:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 20, 38)
  hero.meta = Text(hero.shade, 12, "textSecondary", "LEFT")
  hero.meta:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 20, 18)
  hero.count = Text(hero.shade, 22, "textPrimary", "RIGHT")
  hero.count:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -20, -24)
  hero.countLabel = Text(hero.shade, 11, "textSecondary", "RIGHT")
  hero.countLabel:SetPoint("TOPRIGHT", hero.count, "BOTTOMRIGHT", 0, -4)
  hero.track = Tex(hero.shade, "ARTWORK", "textPrimary", 0.15)
  hero.track:SetSize(150, 4)
  hero.track:SetPoint("TOPRIGHT", hero.countLabel, "BOTTOMRIGHT", 0, -8)
  hero.fill = Tex(hero.shade, "OVERLAY", "gold")
  hero.fill:SetPoint("TOPLEFT", hero.track, "TOPLEFT", 0, 0)
  hero.fill:SetPoint("BOTTOMLEFT", hero.track, "BOTTOMLEFT", 0, 0)
  CutTip(hero.shade)
  P.hero = hero

  P.segQuests = Chip(main, function() zoneSeg = "quests" lists.zone.offset = 1 Refresh() end)
  P.segQuests:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 14, -8)
  P.segJournal = Chip(main, function() zoneSeg = "journal" lists.zone.offset = 1 Refresh() end)
  P.segHere = Chip(main, function() SelectZone(nil) end)
  P.segHere:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", -14, -8)
  -- (1.3.4) filters and "nearest first" (second row, quests only)
  P.zChips = {}
  for i, key in ipairs({ "all", "log", "available", "later", "done" }) do
    local c = Chip(main, function() zFilter = key lists.zone.offset = 1 Refresh() end)
    c.key = key
    if i == 1 then c:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 14, -36) end
    P.zChips[i] = c
  end
  P.zNear = Chip(main, function() zNear = not zNear Refresh() end)
  P.zNear:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", -14, -36)
  local list = NewList(main, KINDS, W - 2 - SIDE_W - 10 - 8)
  list:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 6, -64)
  ListBR(list, main, "BOTTOMRIGHT", -4, 6)
  lists.zone = list
end

-- The map of the zone, scaled to the width of the picture, middle part shown.
local function ArtFromClient(m)
  local layers = C_Map.GetMapArtLayers and ns.Value(C_Map.GetMapArtLayers, m)
  local textures = C_Map.GetMapArtLayerTextures and ns.Value(C_Map.GetMapArtLayerTextures, m, 1)
  local layer = type(layers) == "table" and layers[1]
  if type(layer) ~= "table" or type(textures) ~= "table" or #textures == 0 then return nil end
  local tw, th = ns.Num(layer.tileWidth), ns.Num(layer.tileHeight)
  local lw, lh = ns.Num(layer.layerWidth), ns.Num(layer.layerHeight)
  if not (tw and th and lw and lh) or tw <= 0 or lw <= 0 then return nil end
  return textures, tw, th, lw, lh
end

-- The classic world map: 12 tiles of 256 pixels, 4 by 3, of which 1002 by 668 count.
local function ArtFromFiles(m)
  local name = MAPFILE[m]
  if not name then return nil end
  local textures = {}
  for i = 1, 12 do textures[i] = "Interface\\WorldMap\\" .. name .. "\\" .. name .. i end
  return textures, 256, 256, 1002, 668
end

-- (1.3.4) Draws the map of a zone into a frame: the banner of the zone tab
-- (full width, middle stripe) and the round map of the journal (covers the
-- square, a circle mask on every piece).
local function DrawMapArt(hero, m, width, HEIGHT, mask)
  for _, t in ipairs(hero.tiles) do t:Hide() end
  hero.artMap = m
  local textures, tw, th, lw, lh = ArtFromClient(m)
  hero.artSource = textures and "client" or nil
  if not textures then
    textures, tw, th, lw, lh = ArtFromFiles(m)
    hero.artSource = textures and "files" or "none"
  end
  if not textures then return false end
  -- (1.3) The middle stripe of the map. Every piece is cut to the band of
  -- the picture itself (texture coordinates), no clipping frame.
  local scale = math.max(width / lw, HEIGHT / lh)
  local shift = ((lh * scale) - HEIGHT) / 2 -- map pixels above the picture
  local shiftX = ((lw * scale) - width) / 2
  local drawn = 0
  -- x, y, w, h in map pixels (y down), u, v: used part of the texture file
  local function Piece(file, x, y, w, h, u, v, sub)
    local X, Y, Wd, Ht = x * scale - shiftX, y * scale - shift, w * scale, h * scale
    local ya, yb = math.max(0, Y), math.min(HEIGHT, Y + Ht)
    local xa, xb = math.max(0, X), math.min(width, X + Wd)
    if yb <= ya or xb <= xa then return end
    drawn = drawn + 1
    local t = hero.tiles[drawn]
    if not t then
      t = hero:CreateTexture(nil, "BACKGROUND", nil, 2)
      hero.tiles[drawn] = t
      if mask and t.AddMaskTexture then pcall(t.AddMaskTexture, t, mask) end
    end
    if t.SetDrawLayer then t:SetDrawLayer("BACKGROUND", sub or 2) end
    if t:SetTexture(file) == false then hero.artSource = (hero.artSource or "") .. " missing" end
    t:SetTexCoord(u * (xa - X) / Wd, u * (xb - X) / Wd, v * (ya - Y) / Ht, v * (yb - Y) / Ht)
    t:SetSize(xb - xa, yb - ya)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", hero, "TOPLEFT", xa, -ya)
    t:Show()
  end
  local cols = math.ceil(lw / tw)
  for i, file in ipairs(textures) do
    local row, col = math.floor((i - 1) / cols), (i - 1) % cols
    Piece(file, col * tw, row * th, tw, th, 1, 1, 2)
  end
  -- the parts of the zone you have explored, as on the world map
  local explored = C_MapExplorationInfo and ns.Value(C_MapExplorationInfo.GetExploredMapTextures, m)
  local areas = 0
  if type(explored) == "table" then
    for _, info in ipairs(explored) do
      local ok = pcall(function()
        if ns.True(info.isShownByMouseOver) then return end
        local w, h = ns.Num(info.textureWidth), ns.Num(info.textureHeight)
        local ox, oy = ns.Num(info.offsetX) or 0, ns.Num(info.offsetY) or 0
        local files = info.fileDataIDs
        if not (w and h and w > 0 and h > 0 and type(files) == "table") then return end
        local wide, tall = math.ceil(w / tw), math.ceil(h / th)
        for jj = 1, tall do
          local ph, fh = th, th
          if jj == tall then
            ph = h % th
            if ph == 0 then ph = th end
            fh = 16
            while fh < ph do fh = fh * 2 end
          end
          for kk = 1, wide do
            local pw, fw = tw, tw
            if kk == wide then
              pw = w % tw
              if pw == 0 then pw = tw end
              fw = 16
              while fw < pw do fw = fw * 2 end
            end
            local file = files[(jj - 1) * wide + kk]
            if file then Piece(file, ox + tw * (kk - 1), oy + th * (jj - 1), pw, ph, pw / fw, ph / fh, 3) end
          end
        end
        areas = areas + 1
      end)
      if not ok then break end
    end
  end
  hero.artDrawn, hero.artExplored = drawn, areas
  return drawn > 0
end

local function UpdateHeroArt(m)
  local width = ns.Num(P.hero:GetWidth()) or 0
  if width <= 1 then width = W - SIDE_W end
  return DrawMapArt(P.hero, m, width, HERO_H)
end

-- The journal's round map: the zone you are in.
local function UpdateJournalMap()
  local jm = P.jmap
  if not jm then return end
  local m = HereZone()
  jm.m = m
  jm.name:SetText(m and MapName(m) or "")
  Fit(jm.name, JHERO_H - 60, jm)
  if m ~= jm.artMap then
    local d = JHERO_H - 20
    if not DrawMapArt(jm, m, d, d, jm.mask) then jm.artMap = m end
  end
end

local function CreateSearchPage(page)
  P.searchBox = EditBox(page, L["Search quest, zone, level or ID"], function(text) query = text Refresh(true) end, W - 2 - 28 - 34)
  P.searchBox:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -12)
  P.searchBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -12)
  P.searchBox:SetHeight(30)
  local list = NewList(page, KINDS, W - 2 - 10 - 8)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -52)
  ListBR(list, page, "BOTTOMRIGHT", -4, 6)
  lists.search = list
end

-- (1.3.5) the dungeon chosen in a dropdown at the top (own frames), the route button beside it
local DUN_BAR_H = 56
local UpdateDungeonBar -- (1.3.5) the mark button updates the bar
local function CreateDungeonPage(page)
  local bar = CreateFrame("Button", nil, page)
  bar:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -8)
  bar:SetSize(470, 46)
  Card(bar, 0, 0)
  Clickable(bar)
  bar.disc = Icon(bar, 30, CIRCLE, "ARTWORK")
  bar.disc:SetPoint("CENTER", bar, "LEFT", 26, 0)
  bar.ring = Icon(bar, 37, MEDIA .. "BookRing", "OVERLAY")
  bar.ring:SetPoint("CENTER", bar.disc, "CENTER", 0, 0)
  bar.level = Text(bar, 12, "textPrimary", "CENTER", "OVERLAY")
  BadgeParts(bar, bar.disc, 30)
  bar.name = Text(bar, 16, "goldLight", "LEFT")
  bar.name:SetPoint("TOPLEFT", bar, "TOPLEFT", 52, -6)
  bar.sub = Text(bar, 11, "textSecondary", "LEFT")
  bar.sub:SetPoint("TOPLEFT", bar, "TOPLEFT", 52, -26)
  bar.caret = Style.IconButton(bar, "expand")
  bar.caret:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
  bar.hint = Text(bar, 11, "textHint", "RIGHT")
  bar.hint:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -30, -8) -- (1.3.5) on the name's line: the second line gets the whole width
  local function Toggle() if P.dunDrop:IsShown() then P.dunDrop:Hide() else P.dunDrop:Show() lists.dunPick:SetItems(ns.QuestBookDungeonChoices()) end end
  bar.onClick = Toggle
  bar.caret:SetOnClick(Toggle)
  P.dunBar = bar
  -- (1.3.5, Daniel 10.10.) "Mark entrance": arrow and a pin on the map and the minimap; again: "Remove mark"
  local markChip = Chip(page, function(self)
    if self.disabled or not self.inst then return end
    ns.ToggleEntranceMark(self.inst)
    if P.dunBar and P.dunBar.inst then UpdateDungeonBar() end
  end)
  markChip:SetPoint("LEFT", bar, "RIGHT", 12, 0)
  local chipEnter = markChip:GetScript("OnEnter")
  markChip:SetScript("OnEnter", function(self)
    if chipEnter then chipEnter(self) end
    if self.tipTitle then Style.Tooltip(self, self.tipTitle, self.tipLines, nil, "ANCHOR_RIGHT") end
  end)
  P.dunMark = markChip
  -- (1.3.5, Daniel 10.10.) "Show on map": the world map on the entrance, its pin pulsing for a moment
  local showChip = Chip(page, function(self)
    if self.disabled or not self.inst then return end
    ns.ShowEntranceOnMap(self.inst)
  end)
  showChip:SetPoint("LEFT", markChip, "RIGHT", 8, 0)
  local showEnter = showChip:GetScript("OnEnter")
  showChip:SetScript("OnEnter", function(self)
    if showEnter then showEnter(self) end
    if self.tipTitle then Style.Tooltip(self, self.tipTitle, self.tipLines, nil, "ANCHOR_RIGHT") end
  end)
  P.dunShow = showChip
  P.dunRoute = Chip(page, function() if P.dunRoute.run then ns.SafeCall("quest book", P.dunRoute.run) end end)
  P.dunRoute:SetPoint("LEFT", showChip, "RIGHT", 8, 0)
  local list = NewList(page, KINDS, W - 2 - 10 - 8)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -8 - DUN_BAR_H)
  ListBR(list, page, "BOTTOMRIGHT", -4, 6)
  lists.dungeons = list
  -- the dropdown: over the list, closes on a choice or a second click
  local drop = CreateFrame("Frame", nil, page)
  drop:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
  drop:SetSize(470, 380)
  local lvl = ns.Num(list.GetFrameLevel and list:GetFrameLevel())
  if lvl and drop.SetFrameLevel then drop:SetFrameLevel(lvl + 20) end
  if drop.EnableMouse then drop:EnableMouse(true) end
  Card(drop, 0, 0)
  drop:SetCardLook("cardLow", "cardLow", 0.99, "gold", 0.8)
  local pick = NewList(drop, KINDS, 470 - 12)
  pick:SetPoint("TOPLEFT", drop, "TOPLEFT", 4, -6)
  pick:SetPoint("BOTTOMRIGHT", drop, "BOTTOMRIGHT", -4, 6)
  lists.dunPick = pick
  drop:Hide()
  P.dunDrop = drop
end

-- the dropdown bar and the route button for the dungeon shown
function UpdateDungeonBar()
  local bar = P.dunBar
  if not bar then return end
  local inst = ns.QuestBookSelectedDungeon()
  if not inst then bar:Hide() P.dunRoute:Hide() if P.dunMark then P.dunMark:Hide() end if P.dunShow then P.dunShow:Hide() end return end
  bar:Show()
  local minL = ns.DungeonLevelRange(inst)
  local entries = {}
  for _, id in ipairs(ns.DungeonQuestIDs(inst)) do entries[#entries + 1] = id end
  SetBadge(bar, inst, minL and tostring(minL) or "?")
  -- (1.3.5) name; the range, how many of your quests are done, how it fits you; the zone of the entrance
  local fitText, fitColor = FitOf(inst)
  fitColor = fitColor or "textHint"
  local c = RGB(fitColor)
  bar.disc:SetVertexColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45, 1)
  bar.level:SetTextColor(c[1], c[2], c[3], 1)
  bar.name:SetText(ns.DungeonName(inst) or "?")
  local mine, done = DungeonEntries(inst)
  local zone = ns.DungeonEntrance and select(1, ns.DungeonEntrance(inst))
  local zname = zone and MapName(ZoneOf(zone) or zone)
  local parts = {}
  if RangeOf(inst) then parts[#parts + 1] = RangeOf(inst) end
  parts[#parts + 1] = L["%d of %d quests done"]:format(done, #mine)
  if fitText then parts[#parts + 1] = Colorize(fitText, fitColor) end
  local base = table.concat(parts, "  ·  ")
  -- the zone of the entrance only where it still fits
  local subW = 470 - 52 - 40
  bar.sub:SetText(zname and (base .. "  ·  " .. zname) or base)
  if zname and TextWidth(bar.sub) > subW then bar.sub:SetText(base) end
  bar.inst, bar.rangeText, bar.doneText = inst, RangeOf(inst), L["%d of %d quests done"]:format(done, #mine)
  bar.hint:SetText(L["Choose a dungeon"])
  Fit(bar.hint, 120, bar)
  Fit(bar.name, 470 - 52 - 30 - 8 - TextWidth(bar.hint), bar)
  Fit(bar.sub, subW, bar)
  -- (1.3.5) the entrance mark of this dungeon: set, remove, or nothing known
  local markChip = P.dunMark
  if markChip then
    local m = ns.EntranceMark and ns.EntranceMark()
    local known = ns.DungeonEntrance(inst) ~= nil
    markChip.inst = inst
    markChip.disabled = not known
    local on = m ~= nil and m.inst == inst
    markChip:Set(on and L["Remove mark"] or L["Mark entrance"], on)
    markChip:SetAlpha(known and 1 or 0.45)
    if known then
      markChip.tipTitle = on and L["Remove mark"] or L["Mark entrance"]
      markChip.tipLines = { L["The arrow points to the entrance, and a mark stands on the world map and the minimap. It goes away when you get there, after 30 minutes, or with a right-click on it."] }
    else
      markChip.tipTitle, markChip.tipLines = L["Mark entrance"], { L["No entrance known for this dungeon."] }
    end
    markChip:Show()
  end
  local showChip = P.dunShow
  if showChip then
    local known = ns.DungeonEntrance(inst) ~= nil
    showChip.inst, showChip.disabled = inst, not known
    showChip:Set(L["Show on map"], false)
    showChip:SetAlpha(known and 1 or 0.45)
    showChip.tipTitle = L["Show on map"]
    showChip.tipLines = { known and L["Opens the world map at the entrance and lets its marker pulse for a moment."] or L["No entrance known for this dungeon."] }
    showChip:Show()
  end
  -- route: the quest givers of what you can take now (dungeon quests and the steps before them)
  local pickIDs, seen = {}, {}
  local own = {}
  for _, id in ipairs(entries) do own[id] = true end
  for _, id in ipairs(entries) do
    local e = QuestEntry(id)
    if e and e.group == "available" and not seen[id] then seen[id] = true pickIDs[#pickIDs + 1] = id end
    if e and e.group ~= "done" then
      for _, p in ipairs(ns.DungeonQuestChain(id, own)) do
        if p.group == "available" and not seen[p.questID] then seen[p.questID] = true pickIDs[#pickIDs + 1] = p.questID end
      end
    end
  end
  if #pickIDs > 0 then
    P.dunRoute:Set(L["Route: pick up %d"]:format(#pickIDs), false)
    P.dunRoute.run = function() ns.QuestBookRoute(pickIDs) end
    P.dunRoute:Show()
  else
    P.dunRoute.run = nil
    P.dunRoute:Hide()
  end
end

---------------------------------------------------------------------------
-- (1.3.4) Detail card: everything about the clicked quest at one glance.
---------------------------------------------------------------------------
local detailID
local PlaceDetail
local function ObjectiveTexts(id)
  local out = {}
  if ns.InQuestLog(id) then
    for _, o in ipairs(ns.ClientObjectives(id) or {}) do
      if type(o) == "table" and type(o.text) == "string" and ns.Usable(o.text) and o.text ~= "" then
        out[#out + 1] = { "- " .. o.text, ns.True(o.finished) and "good" or "textPrimary" }
      end
    end
    if #out > 0 then return out end
  end
  local objs = ns.ATT_OBJECTIVES and ns.ATT_OBJECTIVES[id]
  if type(objs) == "table" then
    local idx = {}
    for k in pairs(objs) do if type(k) == "number" then idx[#idx + 1] = k end end
    table.sort(idx)
    for _, k in ipairs(idx) do
      local o = objs[k]
      local names = {}
      for _, c in ipairs(type(o) == "table" and type(o[1]) == "table" and o[1] or {}) do
        local n = ns.LocalNpcName(c)
        if n then names[#names + 1] = n end
        if #names >= 3 then break end
      end
      local items = {}
      for _, i in ipairs(type(o) == "table" and type(o[2]) == "table" and o[2] or {}) do
        items[#items + 1] = ns.ItemName(i)
        if #items >= 2 then break end
      end
      local text
      if #items > 0 and #names > 0 then text = L["%s from %s"]:format(table.concat(items, ", "), table.concat(names, ", "))
      elseif #items > 0 then text = table.concat(items, ", ")
      elseif #names > 0 then text = table.concat(names, ", ") end
      if text then out[#out + 1] = { "- " .. text, "textPrimary" } end
    end
  end
  return out
end

-- (1.3.5, Daniel 08.10. Merkliste) Where the objectives are: inside the dungeon for a dungeon
-- quest, else the (at most two) maps with the most places of its objectives (data points, spawns,
-- learned and shared spots).
function ns.QuestObjectiveWhere(id)
  local inst = ns.QuestDungeon and ns.QuestDungeon(id)
  if inst then return L["Inside the dungeon: %s"]:format(ns.DungeonName(inst)) end
  local count, order = {}, {}
  local function Count(m)
    m = ns.Num(m)
    if not m then return end
    if not count[m] then count[m] = 0 order[#order + 1] = m end
    count[m] = count[m] + 1
  end
  local objs = ns.ATT_OBJECTIVES and ns.ATT_OBJECTIVES[id]
  for _, o in pairs(type(objs) == "table" and objs or {}) do
    if type(o) == "table" then
      local pts = type(o[3]) == "table" and o[3] or {}
      for i = 1, #pts, 3 do Count(pts[i]) end
      for _, cr in ipairs(type(o[1]) == "table" and o[1] or {}) do
        if ns.EachCreatureSpawn then ns.EachCreatureSpawn(cr, Count) end
      end
    end
  end
  for _, spots in pairs(ns.ObjectiveSpots and ns.ObjectiveSpots(id) or {}) do
    if type(spots) == "table" then for i = 1, #spots, 3 do Count(spots[i]) end end
  end
  if #order == 0 then return nil end
  table.sort(order, function(a, b) if count[a] ~= count[b] then return count[a] > count[b] end return a < b end)
  local names = {}
  for i = 1, math.min(2, #order) do names[#names + 1] = MapName(order[i]) or ("Map " .. order[i]) end
  return L["Where: %s"]:format(table.concat(names, ", "))
end

local function Where(m, x, y)
  if not m then return nil end
  local name = MapName(m) or ("Map " .. m)
  if x and y then return ("%s  %.1f, %.1f"):format(name, x, y) end
  return name
end

-- Title, level, status and the sections { title, { { text, color } } } of a quest.
function ns.QuestBookDetail(id)
  local group, text, color = ns.ZoneQuestStatus(id)
  local d = { questID = id, title = ns.QuestTitleWithPart(id), level = ns.QuestLevel(id), sections = {} }
  if group == "done" then d.pill, d.pillColor = L["done (turned in)"], "good"
  elseif group then d.pill, d.pillColor = text, color
  else d.pill, d.pillColor = L["not for you"], "textHint" end
  local function Section(title, lines) if lines and #lines > 0 then d.sections[#d.sections + 1] = { title = title, lines = lines } end end
  local qt0 = ns.QuestText and ns.QuestText(id)
  -- where to get it
  local givers = ns.QuestGiverIDs(id)
  local giver, src
  if givers then giver, src = ns.LocalNpcName(givers[1]) end
  -- (1.3.5) the English data name only when nothing in the game language is known
  if src == "data" and qt0 and qt0.s then giver = qt0.s end
  local learned = ns.db.learned and ns.db.learned[id]
  giver = giver or (learned and learned.start and learned.start.npc) or (qt0 and qt0.s)
  local m, x, y = ns.QuestStart(id)
  local start = {}
  if giver then start[#start + 1] = { giver, "textPrimary" } end
  if m then start[#start + 1] = { Where(m, x, y), "textSecondary" } end
  -- (1.3.5) from which level it can be taken (the data, or the lowest level it was offered at)
  local minLv = ns.QuestMinLevel(id)
  local offered = learned and ns.Num(learned.offeredAt)
  if offered and offered > 0 and (not minLv or offered < minLv) then minLv = offered end
  if minLv and minLv > 0 then start[#start + 1] = { L["Minimum level: %d"]:format(minLv), "textSecondary" } end
  if ns.IsItemStartQuest and ns.IsItemStartQuest(id) then start[#start + 1] = { L["Starts from an item."], "textSecondary" } end
  Section(L["Quest giver"], start)
  -- what to do
  local qt = ns.QuestText and ns.QuestText(id)
  local todo = {}
  if qt and type(qt.o) == "string" and qt.o ~= "" then todo[1] = { qt.o, "textPrimary" } end
  local own = ObjectiveTexts(id)
  if ns.InQuestLog(id) and #own > 0 then
    for _, l in ipairs(own) do todo[#todo + 1] = l end
  elseif qt and type(qt.r) == "table" and #qt.r > 0 then
    for _, r in ipairs(qt.r) do todo[#todo + 1] = { "- " .. r, "textSecondary" } end
  else
    for _, l in ipairs(own) do todo[#todo + 1] = l end
  end
  if #todo == 0 then todo = { { L["No details known yet."], "textHint" } } end
  local where = ns.QuestObjectiveWhere(id)
  if where then todo[#todo + 1] = { where, "textSecondary" } end
  Section(L["To do"], todo)
  -- where to turn it in
  local fin = ns.QUEST_ENDS and ns.QUEST_ENDS[id]
  local endName, endSrc
  if fin and fin[4] then endName, endSrc = ns.LocalNpcName(fin[4]) end
  if endSrc == "data" and qt0 and qt0.e then endName = qt0.e end
  local endNpc = (learned and learned.finish and learned.finish.npc) or endName or (qt0 and qt0.e)
  local tm, tx, ty = ns.TurnInPoint(id)
  local turnin = {}
  if endNpc then turnin[#turnin + 1] = { endNpc, "textPrimary" } end
  if tm then turnin[#turnin + 1] = { Where(tm, tx and tx * 100, ty and ty * 100), "textSecondary" } end
  Section(L["Turn in"], turnin)
  -- (1.3.5) rewards, as the game tells them for a quest in the log
  local rewards = {}
  for _, r in ipairs(ns.QuestRewardLines and ns.QuestRewardLines(id) or {}) do rewards[#rewards + 1] = { r, "textPrimary" } end
  Section(L["Rewards"], rewards)
  -- chain
  local chain = {}
  for _, pre in ipairs(ns.QuestPrereqs(id) or {}) do
    local done = ns.IsQuestDone(pre)
    chain[#chain + 1] = { L["Before: %s"]:format(ns.QuestTitleWithPart(pre)), done and "good" or "warning" }
  end
  for _, nx in ipairs(ns.FollowUpQuests(id) or {}) do
    chain[#chain + 1] = { L["Then: %s"]:format(ns.QuestTitleWithPart(nx)), "textSecondary" }
    if #chain >= 6 then break end
  end
  Section(L["Chain"], chain)
  local notes = {}
  local inst = ns.QuestDungeon and ns.QuestDungeon(id)
  if inst then notes[#notes + 1] = { L["Dungeon quest: %s"]:format(ns.DungeonName(inst)), "warning" } end
  if ns.QuestFlags(id):find("b", 1, true) then notes[#notes + 1] = { L["Breadcrumb quest"], "textSecondary" } end
  if ns.MissingSkill and ns.MissingSkill(id) then notes[#notes + 1] = { L["profession not learned"], "textHint" } end
  Section(L["Notes"], notes)
  return d
end

local function CreateDetail()
  local pane = CreateFrame("Frame", nil, book)
  Card(pane, 0, 0)
  pane:SetCardLook("card", "cardLow", 0.97, "gold", 0.6)
  pane:EnableMouse(true)
  pane:Hide()
  pane.close = Style.IconButton(pane, "close")
  pane.close:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -8, -8)
  pane.close:SetTooltip(L["Close"])
  pane.close:SetOnClick(function() ns.QuestBookShowQuest(nil) end)
  pane.badge = Tex(pane, "ARTWORK", "cardLow", 0.95)
  pane.badge:SetSize(30, 26)
  pane.badge:SetPoint("TOPLEFT", pane, "TOPLEFT", 14, -14)
  Edges(pane, pane.badge, "gold", 0.6, "ARTWORK")
  pane.level = Text(pane, 13, "textPrimary", "CENTER")
  pane.level:SetPoint("CENTER", pane.badge, "CENTER", 0, 0)
  pane.title = Text(pane, 15, "goldLight", "LEFT")
  pane.title:SetPoint("TOPLEFT", pane, "TOPLEFT", 52, -12)
  pane.title:SetPoint("RIGHT", pane, "RIGHT", -32, 0)
  pane.title:SetWordWrap(true)
  pane.title:SetJustifyV("TOP")
  pane.pillHost = CreateFrame("Frame", nil, pane)
  pane.pillHost:SetSize(DETAIL_W - 60, 24)
  NewPill(pane.pillHost)
  pane.pillHost.pillText:ClearAllPoints()
  pane.pillHost.pillText:SetPoint("LEFT", pane.pillHost, "LEFT", 9, 0)
  pane.texts = {}
  pane.arrow = Chip(pane, function() if detailID then ns.FocusQuest(detailID, false) end end)
  pane.arrow:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 14, 12)
  pane.map = Chip(pane, function() if detailID then ns.FocusQuest(detailID, true) end end)
  pane.map:SetPoint("LEFT", pane.arrow, "RIGHT", 8, 0)
  P.detail = pane
end

local function DetailText(i, size)
  local pane = P.detail
  local fs = pane.texts[i]
  if not fs then
    fs = Text(pane, size or 12, "textPrimary", "LEFT")
    fs:SetWordWrap(true)
    fs:SetJustifyV("TOP")
    pane.texts[i] = fs
  end
  if fs.SetFont then pcall(fs.SetFont, fs, FontPath(), size or 12, "") end
  fs:SetWidth(DETAIL_W - 30)
  fs:Show()
  return fs
end

local function RenderDetail()
  local pane = P.detail
  if not pane then return end
  if not detailID then pane:Hide() return end
  local d = ns.QuestBookDetail(detailID)
  local lv = d.level and d.level > 0 and d.level or nil
  pane.level:SetText(lv and tostring(lv) or "?")
  local lc = LevelRGB(lv)
  pane.level:SetTextColor(lc[1], lc[2], lc[3], 1)
  -- one line if it fits (a little smaller if needed), else two lines; never "(1/" and "2)" apart
  local titleW = DETAIL_W - 52 - 32
  pane.title:SetWordWrap(false)
  pane.title:SetWidth(titleW)
  pane.title:SetText(d.title or "")
  if not Style.FitText(pane.title, titleW) then
    Style.FitText(pane.title, 1e6)
    pane.title:SetWordWrap(true)
    pane.title:SetText(((d.title or ""):gsub(" %((%d+)/(%d+)%)$", "\n(%1/%2)")))
  end
  local th = math.max(18, math.min(40, ns.Num(pane.title:GetStringHeight()) or 18))
  pane.pillHost:ClearAllPoints()
  pane.pillHost:SetPoint("TOPLEFT", pane, "TOPLEFT", 50, -16 - th)
  SetPill(pane.pillHost, d.pill, d.pillColor, DETAIL_W - 90)
  for _, fs in ipairs(pane.texts) do fs:Hide() end
  local y = 16 + th + 34
  local bottom = (ns.Num(pane:GetHeight()) or 400) - 46
  local n = 0
  for _, sec in ipairs(d.sections) do
    if y > bottom - 30 then break end
    n = n + 1
    local head = DetailText(n, 11)
    head:SetText(sec.title)
    SetColor(head, "gold")
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, -y)
    y = y + 17
    for _, line in ipairs(sec.lines) do
      if y > bottom - 16 then break end
      n = n + 1
      local fs = DetailText(n, 12)
      fs:SetText(line[1] or "")
      SetColor(fs, line[2] or "textPrimary")
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", pane, "TOPLEFT", 16, -y)
      -- (1.3.4) wrapped lines: their whole height (before, at most three lines counted and the next one overlapped)
      local lh = ns.Num(fs:GetStringHeight()) or 14
      if lh < 14 then lh = 14 end
      y = y + math.min(160, lh) + 4
    end
    y = y + 8
  end
  pane.arrow:Set(L["Arrow"], false)
  pane.map:Set(L["World map"], false)
  pane:Show()
end

-- Next to the list of the open tab, as high as the list.
PlaceDetail = function()
  if not P.detail then return end
  local l = lists[tab]
  P.detail:ClearAllPoints()
  if l and detailID then
    P.detail:SetPoint("TOPLEFT", l, "TOPRIGHT", 10, 0)
    P.detail:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -16, 16)
  end
  RenderDetail()
end

-- Show a quest in the detail card (nil closes the card). (1.3.5) focus: nil = the card only,
-- "arrow" = also arrow and map mark, "map" = also open the world map there.
function ns.QuestBookShowQuest(id, focus)
  if id and focus then ns.FocusQuest(id, focus == "map") end
  local changed = detailID ~= id
  detailID = id
  local open = id ~= nil
  if open ~= detailOpen then detailOpen = open ApplyDetailRoom() end
  PlaceDetail()
  if changed and not focus and Refresh then Refresh(false) end -- the clicked line stands out
end
function ns.QuestBookDetailID() return detailID end
function ns.QuestBookDetailPane() return P.detail end -- (tests)

local function TabButton(parent, key)
  local b = CreateFrame("Button", nil, parent)
  b.key = key
  b:SetSize(118, HEADER_H - 8)
  -- (1.3.4) a framed tab; the open one brighter with a gold frame
  Card(b, 2, 0)
  b.hover = Tex(b, "BACKGROUND", "rowHover", nil, 3)
  b.hover:SetAllPoints(b.cardFill)
  b.hover:Hide()
  b.icon = Icon(b, 16, TAB_ICON[key], "ARTWORK")
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b.text = Text(b, 13, "textSecondary", "LEFT")
  b.text:SetText(L[TAB_TITLE[key]])
  b.icon:SetPoint("RIGHT", b, "CENTER", -TextWidth(b.text) / 2 + 2, 0)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.mark = Tex(b, "OVERLAY", "goldLight")
  b.mark:SetPoint("TOPLEFT", b.cardFill, "TOPLEFT", 10, -1)
  b.mark:SetPoint("TOPRIGHT", b.cardFill, "TOPRIGHT", -10, -1)
  b.mark:SetHeight(1)
  b:SetScript("OnEnter", function(self) self.hover:Show() ShowCut(self) end)
  b:SetScript("OnLeave", function(self) self.hover:Hide() Style.HideTooltip(self) end)
  b:SetScript("OnClick", function(self) ns.OpenQuestBook(self.key) end)
  return b
end

local function Create()
  book = CreateFrame("Frame", "QuestdonQuestBook", UIParent)
  book:SetSize(W, H)
  book:SetFrameStrata("HIGH")
  book:SetToplevel(true)
  book:SetClampedToScreen(true)
  book:SetMovable(true)
  book:EnableMouse(true)
  book:Hide()
  -- (1.3.4) navy at the top to violet at the bottom, a gold frame, ornaments in the corners
  local bg = Tex(book, "BACKGROUND")
  bg:SetAllPoints(book)
  Gradient(bg, "VERTICAL", "backgroundLow", 0.97, "background", 0.97)
  Border(book, "gold", 0.95)
  local inner = CreateFrame("Frame", nil, book)
  inner:SetPoint("TOPLEFT", book, "TOPLEFT", 3, -3)
  inner:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -3, 3)
  Border(inner, "goldDark", 0.9)
  local inner2 = CreateFrame("Frame", nil, book)
  inner2:SetPoint("TOPLEFT", book, "TOPLEFT", 5, -5)
  inner2:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -5, 5)
  Border(inner2, "gold", 0.35)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "QuestdonQuestBook") end
  book:SetScript("OnHide", function()
    ns.zoneFocus = nil
    if ns.RefreshPins then ns.RefreshPins() end
  end)

  local header = CreateFrame("Frame", nil, book)
  header:SetPoint("TOPLEFT", book, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", book, "TOPRIGHT", -1, -1)
  header:SetHeight(HEADER_H)
  local hbg = Tex(header, "BACKGROUND")
  hbg:SetAllPoints(header)
  Gradient(hbg, "VERTICAL", "background", 0.0, "header", 0.85)
  local hline = Tex(header, "BORDER", "gold", 0.7)
  hline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 0) hline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 0) hline:SetHeight(1)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() book:StartMoving() end)
  header:SetScript("OnDragStop", function() book:StopMovingOrSizing() SavePos() end)
  local title = Text(header, 15, "textPrimary", "LEFT")
  title:SetPoint("LEFT", header, "LEFT", 14, 0)
  title:SetText(Style.Wordmark("Quest", "don"))
  local sub = Text(header, 12, "textSecondary", "LEFT")
  sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
  sub:SetText(L["Quest book"])
  local close = Style.IconButton(header, "close")
  close:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  close:SetTooltip(L["Close"])
  close:SetOnClick(function() book:Hide() end) -- OnHide drops the focus
  -- (1.3.5, Daniel 05.10.) the options right from the book (the window is off for new players)
  -- (round 8b, Daniel 10.10.: "could be a bit bigger and does not sit centred") The gear's glyph fills less
  -- of its box than the X: a larger box (GEAR_SIZE), its centre on the X's centre line, GEAR_GAP between them.
  local gear = Style.IconButton(header, "options")
  gear:SetSize(GEAR_SIZE, GEAR_SIZE)
  local closeW = tonumber(close.GetWidth and close:GetWidth()) or 14
  gear:SetPoint("CENTER", close, "CENTER", -(closeW / 2 + GEAR_GAP + GEAR_SIZE / 2), 0)
  gear:SetTooltip(L["Options"], nil, L["/qd opens them too."])
  gear:SetOnClick(function() if ns.OpenOptions then ns.OpenOptions() end end)
  P.gear = gear
  P.tabs = {}
  local prev = close
  for i = #TABS, 1, -1 do
    local b = TabButton(header, TABS[i])
    if prev == close then b:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -64, 0) else b:SetPoint("BOTTOMRIGHT", prev, "BOTTOMLEFT", -4, 0) end
    P.tabs[TABS[i]] = b
    prev = b
  end
  -- (i18n) tabs as wide as their text needs (at least 118 px); the subtitle gets what is left
  local titleW = TextWidth(title)
  local each = math.floor((W - 2 - 14 - titleW - 10 - 60 - 58) / #TABS) - 50
  local tabsW = 0
  for _, key in ipairs(TABS) do
    local b = P.tabs[key]
    Fit(b.text, each, b)
    local w = math.max(118, TextWidth(b.text) + 50)
    b:SetWidth(w)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("RIGHT", b, "CENTER", -TextWidth(b.text) / 2 + 2, 0)
    tabsW = tabsW + w
  end
  Fit(sub, W - 2 - 14 - titleW - 10 - tabsW - 58 - 16, header)
  header:SetScript("OnEnter", function(self) ShowCut(self) end)
  header:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)

  P.pages = {}
  for _, key in ipairs(TABS) do
    local page = CreateFrame("Frame", nil, book)
    page:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -1, 1)
    page:Hide()
    P.pages[key] = page
  end
  CreateJournalPage(P.pages.journal)
  CreateZonePage(P.pages.zone)
  CreateSearchPage(P.pages.search)
  CreateDungeonPage(P.pages.dungeons)
  CreateDetail()
  -- the ornaments lie on top of everything and take no clicks
  local orn = CreateFrame("Frame", nil, book)
  orn:SetAllPoints(book)
  local lvl = ns.Num(book.GetFrameLevel and book:GetFrameLevel())
  if lvl and orn.SetFrameLevel then orn:SetFrameLevel(lvl + 30) end
  if orn.EnableMouse then orn:EnableMouse(false) end
  local corners = {
    { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
    { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 },
  }
  P.corners = {}
  for i, c in ipairs(corners) do
    local t = orn:CreateTexture(nil, "OVERLAY")
    t:SetSize(44, 44)
    if t:SetTexture(MEDIA .. "BookCorner") == false then t:Hide() end
    t:SetTexCoord(c[2], c[3], c[4], c[5])
    local dx = (c[1]:find("LEFT") and -3) or 3
    local dy = (c[1]:find("TOP") and 3) or -3
    t:SetPoint(c[1], book, c[1], dx, dy)
    P.corners[i] = t
  end

  -- the world map opened, closed or shows another zone: follow it (zone tab,
  -- no zone picked). Our own frame looks twice a second while the book is open.
  local watch, elapsed, last = CreateFrame("Frame", nil, book), 0, nil
  watch:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < 0.5 then return end
    elapsed = 0
    local key = WorldMapFrame and WorldMapFrame:IsShown() and tostring(ns.Value(WorldMapFrame.GetMapID, WorldMapFrame)) or "-"
    if key ~= last then
      last = key
      if tab == "zone" and not selZone then ns.SafeCall("quest book", Refresh) end
    end
  end)
  ApplyPos()
end

---------------------------------------------------------------------------
-- Drawing the tabs
---------------------------------------------------------------------------
local function RenderJournal(reset)
  UpdateTiles()
  UpdateJournalMap()
  local items = JournalItems()
  local c = ns.JournalCounts()
  local n = { all = nil, c = c.c, a = c.a, x = c.x + c.f, l = c.l }
  for _, chip in ipairs(P.chips) do
    local label = L[FILTER_TITLE[chip.key]]
    if n[chip.key] and n[chip.key] > 0 then label = label .. "  " .. n[chip.key] end
    chip:Set(label, chip.key == jfilter)
  end
  Layout(P.chips, 6, W - 2 - 28)
  local dated = c.a + c.c + c.x + c.f + c.l
  P.footLeft:SetText(L["%d entries"]:format(dated))
  local oldW = 0
  if items.old and items.old > 0 then
    P.footOld.text:SetText(L["Done earlier (%d)"]:format(items.old))
    Fit(P.footOld.text, (W - 40) / 2, P.footOld)
    P.footOld:SetWidth(TextWidth(P.footOld.text) + 8)
    P.footOld:Show()
    oldW = TextWidth(P.footOld.text) + 8
  else
    P.footOld:Hide()
  end
  Fit(P.footLeft, W - 2 - 24 - oldW - 30, P.footer)
  lists.journal:SetItems(items, not reset)
end

local function RenderZone(reset)
  local m = ShownZone()
  local here = HereZone()
  lists.zones:SetItems(ZoneListItems(), true)
  local hero = P.hero
  local info = m and ZONE_INFO[m]
  hero.name:SetText(m and (MapName(m) or ("Map " .. m)) or L["Unknown zone"])
  local meta = {}
  if info then meta[#meta + 1] = ContinentName(info.cont) end
  if info and info.min then meta[#meta + 1] = L["Level %s"]:format(RangeText(info)) elseif info then meta[#meta + 1] = L["City"] end
  if m and m == here then meta[#meta + 1] = L["you are here"] end
  hero.meta:SetText(table.concat(meta, "  ·  "))
  if m ~= hero.artMap then
    local ok = UpdateHeroArt(m)
    if not ok then hero.artMap = m end
  end
  local items, s
  if zoneSeg == "journal" then
    items = ZoneJournalItems(m)
    s = m and ZoneStats(m) or { total = 0, done = 0 }
  else
    items, s = ZoneQuestItems(m)
  end
  hero.count:SetText(("%d / %d"):format(s.done, s.total))
  hero.countLabel:SetText(L["quests done"])
  local heroW = W - 2 - SIDE_W
  Fit(hero.countLabel, 150, hero.shade)
  Fit(hero.name, heroW - 40 - 170, hero.shade)
  Fit(hero.meta, heroW - 40 - 170, hero.shade)
  if s.total > 0 and s.done > 0 then
    hero.fill:SetWidth(math.max(1, 150 * s.done / s.total))
    hero.fill:Show()
  else
    hero.fill:Hide()
  end
  local jn = 0
  for _, e in ipairs(ns.JournalEntries()) do if e.m and ZoneOf(e.m) == m then jn = jn + 1 end end
  P.segQuests:Set(L["Quests"] .. "  " .. s.total, zoneSeg == "quests")
  P.segJournal:Set(L["Your journal here"] .. "  " .. jn, zoneSeg == "journal")
  P.segJournal:ClearAllPoints()
  P.segJournal:SetPoint("LEFT", P.segQuests, "RIGHT", 6, 0)
  local hereW = 0
  if selZone and selZone ~= here then
    P.segHere:Set(L["Back to my zone"], false)
    P.segHere:Show()
    hereW = (ns.Num(P.segHere:GetWidth()) or 0) + 12
  else
    P.segHere:Hide()
  end
  Layout({ P.segQuests, P.segJournal }, 6, W - 2 - SIDE_W - 28 - hereW)
  local showChips = zoneSeg == "quests"
  local gc = s.groups or {}
  for _, c in ipairs(P.zChips) do
    local n = c.key == "all" and s.total or (gc[c.key] or 0)
    c:Set(L[c.key == "all" and "All" or ns.ZONE_GROUP_TITLE[c.key]] .. "  " .. n, zFilter == c.key)
    c:SetShown(showChips)
  end
  P.zNear:Set(L["Nearest first"], zNear)
  P.zNear:SetShown(showChips)
  Layout(P.zChips, 6, W - 2 - SIDE_W - 28 - (ns.Num(P.zNear:GetWidth()) or 110) - 12)
  lists.zone:SetItems(items, not reset)
end

local function RenderSearch(reset)
  lists.search:SetItems(SearchItems(), not reset)
end

local function RenderDungeons(reset)
  UpdateDungeonBar()
  if P.dunDrop and P.dunDrop:IsShown() then lists.dunPick:SetItems(ns.QuestBookDungeonChoices(), true) end
  lists.dungeons:SetItems(DungeonItems(), not reset)
end

local lastTab
function Refresh(reset)
  if not book or not book:IsShown() then return end
  for key, b in pairs(P.tabs) do
    local on = key == tab
    SetColor(b.text, on and "goldLight" or "textSecondary")
    if on then b:SetCardLook("card", "cardLow", 0.98, "gold", 0.9) else b:SetCardLook("cardLow", "cardLow", 0.75, "gold", 0.35) end
    if b.icon.SetDesaturated then b.icon:SetDesaturated(not on) end
    b.icon:SetAlpha(on and 1 or 0.6)
    if on then b.mark:Show() else b.mark:Hide() end
  end
  for key, page in pairs(P.pages) do if key == tab then page:Show() else page:Hide() end end
  if tab ~= lastTab then reset = true lastTab = tab end
  ApplyDetailRoom()
  if tab == "journal" then RenderJournal(reset)
  elseif tab == "zone" then RenderZone(reset)
  elseif tab == "dungeons" then RenderDungeons(reset)
  else RenderSearch(reset) end
  if detailID then PlaceDetail() end
end

---------------------------------------------------------------------------
-- API (the names stay those of 1.2.2: Panel.lua, Core.lua, Journal.lua, ZoneQuests.lua)
---------------------------------------------------------------------------
function ns.UpdateZoneQuests(force)
  if not book or not book:IsShown() then return end
  Refresh(false)
end

-- Show the book on a tab (nil: the last one); already open on that tab: stays.
function ns.OpenQuestBook(which)
  if not book then Create() end
  which = which or tab
  local changed = which ~= tab
  tab = which
  if tab == "search" and changed and ns.JournalSearchReset then ns.JournalSearchReset() end
  if not book:IsShown() then
    stats = {}
    book:Show()
  end
  Refresh(changed)
  if tab == "search" and changed and P.searchBox and P.searchBox.edit.SetFocus then P.searchBox.edit:SetFocus() end
end

local function Close()
  book:Hide()
  ns.zoneFocus = nil
  if ns.RefreshPins then ns.RefreshPins() end
end

local function Toggle(which)
  if not book then Create() end
  if book:IsShown() and (which == nil or which == tab) then Close() return end
  ns.OpenQuestBook(which)
end
function ns.ToggleZoneQuests() Toggle("zone") end
function ns.ToggleJournal() Toggle("journal") end
function ns.ToggleQuestBook() Toggle(nil) end
function ns.ZoneQuestsFrame() return book end
function ns.QuestBookTab() return tab end
function ns.QuestBookGear() return P.gear end -- (tests)
function ns.QuestBookDungeonBar() return P.dunBar, P.dunMark, P.dunShow end -- (tests)
function ns.QuestBookZone() return ShownZone() end
-- For /qd diag: where the picture of the zone came from.
function ns.QuestBookArt()
  local h = P.hero
  if not h then return "not built" end
  return ("%s, map %s, %d tiles drawn, %d explored areas, width %s"):format(tostring(h.artSource), tostring(h.artMap), h.artDrawn or 0, h.artExplored or 0, tostring(ns.Num(h:GetWidth())))
end
function ns.QuestBookFilter(key) if key then jfilter = key Refresh(true) end return jfilter end
function ns.QuestBookSegment(key) if key then zoneSeg = key Refresh(true) end return zoneSeg end
function ns.QuestBookZoneFilter(key) if key then zFilter = key Refresh(true) end return zFilter end
function ns.QuestBookNearest(on) if on ~= nil then zNear = on and true or false Refresh(true) end return zNear end
function ns.JournalQuery() return query end
function ns.JournalSetQuery(text)
  if not book then Create() end
  query = tostring(text or "")
  P.searchBox:SetText(query)
  Refresh(true)
end
function ns.QuestBookSetZoneQuery(text)
  if not book then Create() end
  zoneQuery = tostring(text or "")
  P.zoneBox:SetText(zoneQuery)
  Refresh()
end
-- For tests and /qd diag: the lines drawn now in a list ("journal", "zone", "zones", "search").
function ns.QuestBookLines(which)
  local l = lists[which or tab]
  local out = {}
  if not l then return out end
  for _, r in ipairs(l.used) do out[#out + 1] = r end
  return out, l
end
-- Built items of a list (all, not only the visible ones).
function ns.QuestBookItems(which)
  local l = lists[which or tab]
  return l and l.items or {}
end

ns.RegisterRefresh("questbook", function() ns.UpdateZoneQuests() end)
local function Queue() if book and book:IsShown() then ns.QueueRefresh("questbook") end end
local function Changed() stats = {} Queue() end
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("QUEST_TURNED_IN", Changed)
ns.On("QUEST_ACCEPTED", Changed)
ns.On("PLAYER_LEVEL_UP", Changed)
ns.On("PLAYER_XP_UPDATE", Queue)
ns.On("ZONE_CHANGED_NEW_AREA", Queue)
ns.On("QUEST_DATA_LOAD_RESULT", Queue)
