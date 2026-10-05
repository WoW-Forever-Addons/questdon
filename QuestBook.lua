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
--   Search   journal, all quests and zones by name, level or quest ID.
--
-- Long lists are drawn as a window onto the list (mouse wheel), only the
-- visible lines exist as frames. Our own frames only; nothing of Blizzard's
-- is hooked. Escape closes the book.
---------------------------------------------------------------------------
local W, H = 920, 600
local HEADER_H = 34
local SIDE_W = 232
local HERO_H = 116
local ROW_H, HEAD_H, SMALL_H = 36, 26, 26
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
}
local TABS = { "journal", "zone", "search" }
local TAB_TITLE = { journal = "Journal", zone = "Zones", search = "Search" }

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
local zoneQuery, query = "", ""
local stats = {}        -- mapID -> { total, done } for the zone list
local lists = {}        -- page key -> virtual list
local P = {}            -- frames of the pages

local Fmt = ns.JournalFmt

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function RGB(c)
  if type(c) == "string" then c = C[c] end
  return c or C.textPrimary
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
    if self.onClick or self.tooltip then self.hover:Show() end
    if self.tooltip then
      local ok, title, lines, hint = pcall(self.tooltip, self)
      if ok and title then Style.Tooltip(self, title, lines, hint, "ANCHOR_RIGHT") end
    end
  end)
  f:SetScript("OnLeave", function(self)
    self.hover:Hide()
    Style.HideTooltip(self)
  end)
  f:SetScript("OnClick", function(self, button)
    if self.onClick then ns.SafeCall("quest book", self.onClick, self, button) end
  end)
end

---------------------------------------------------------------------------
-- Virtual list: items { kind, h, ... }; one pool of frames per kind
---------------------------------------------------------------------------
local function NewList(parent, factories)
  local list = CreateFrame("Frame", nil, parent)
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
    f.text = Text(f, 11, "textSecondary", "LEFT")
    f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 6)
    f.count = Text(f, 11, "textHint", "LEFT")
    f.count:SetPoint("LEFT", f.text, "RIGHT", 6, 0)
    f.right = Text(f, 11, "textHint", "RIGHT")
    f.right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 6)
    f.line = Tex(f, "ARTWORK", "divider")
    f.line:SetHeight(1)
    return f
  end,
  render = function(f, it)
    f.text:SetText(it.text or "")
    SetColor(f.text, it.color or "textSecondary")
    f.count:SetText(it.count and tostring(it.count) or "")
    f.right:SetText(it.right or "")
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
    return f
  end,
  render = function(f, it) f.text:SetText(it.text or "") end,
}

-- Journal line: time, a mark on the time line, title and what happened,
-- XP and money on the right. Level-ups as a golden band.
local EntryKind = {
  create = function(list)
    local f = CreateFrame("Button", nil, list)
    f.band = Tex(f, "BACKGROUND", "warning", 0.10)
    f.band:SetPoint("TOPLEFT", f, "TOPLEFT", 66, -3)
    f.band:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 3)
    f.stripe = Tex(f, "ARTWORK", "warning")
    f.stripe:SetPoint("TOPLEFT", f.band, "TOPLEFT", 0, 0)
    f.stripe:SetPoint("BOTTOMLEFT", f.band, "BOTTOMLEFT", 0, 0)
    f.stripe:SetWidth(2)
    Clickable(f)
    f.active = Tex(f, "BACKGROUND", "rowActive", nil, 2)
    f.active:SetAllPoints(f)
    f.time = Text(f, 11, "textHint", "LEFT")
    f.time:SetPoint("LEFT", f, "LEFT", 10, 0)
    f.line = Tex(f, "BORDER", "textPrimary", 0.10)
    f.line:SetWidth(1)
    f.line:SetPoint("TOP", f, "TOPLEFT", 56, 0)
    f.line:SetPoint("BOTTOM", f, "BOTTOMLEFT", 56, 0)
    f.disc = Icon(f, 20, CIRCLE, "ARTWORK")
    f.disc:SetPoint("CENTER", f, "LEFT", 56, 0)
    f.disc:SetVertexColor(C.background[1], C.background[2], C.background[3], 1)
    f.icon = Icon(f, 15, nil, "OVERLAY")
    f.icon:SetPoint("CENTER", f.disc, "CENTER", 0, 0)
    f.title = Text(f, 13, "textPrimary", "LEFT")
    f.sub = Text(f, 11, "textHint", "LEFT")
    f.r1 = Text(f, 12, "warning", "RIGHT")
    f.r1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -5)
    f.r2 = Text(f, 11, "textHint", "RIGHT")
    f.r2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 5)
    return f
  end,
  render = function(f, it)
    local e = it.e
    local level = e.k == "l"
    f.time:SetText(e.t and Fmt.Clock(e.t) or "")
    f.icon:SetTexture(ICON[e.k] or ICON.o)
    if f.icon.SetDesaturated then f.icon:SetDesaturated(e.k == "o" or e.k == "x") end
    f.icon:SetAlpha((e.k == "o" or e.k == "x") and 0.6 or 1)
    if level then f.band:Show() f.stripe:Show() else f.band:Hide() f.stripe:Hide() end
    local title, sub, r1, r2
    if level then
      title = Style.Colorize(Fmt.EntryTitle(e), "warning")
      local parts = {}
      if e.since then parts[#parts + 1] = L["after %s"]:format(Fmt.Span(e.since) or "?") end
      if it.quests and it.quests > 0 then parts[#parts + 1] = L["%d quests on the way"]:format(it.quests) end
      sub = table.concat(parts, "  ·  ")
    else
      local quiet = e.k == "x" or e.k == "o"
      local tag = ns.QuestLevelTag(e.q)
      if quiet then tag = Plain(tag) end
      local name = Fmt.EntryTitle(e)
      if it.part then name = name .. Style.Colorize(("  (%s)"):format(it.part), "textHint") end
      title = quiet and Style.Colorize(tag .. name, "textHint") or (tag .. name)
      local what = Style.Colorize(L[Fmt.KIND_TEXT[e.k] or "done earlier"], Fmt.KIND_COLOR[e.k] or "textHint")
      local zone = e.m and MapName(e.m)
      sub = zone and (what .. Style.Colorize("  ·  " .. zone, "textHint")) or what
      if e.x then r1 = "+" .. Style.Number(e.x) .. " " .. L["XP"] end
      r2 = Coins(e.g)
      if e.k == "o" then
        local m = ns.QuestStart(e.q)
        sub, r2 = nil, nil
        r1 = m and MapName(m) and Style.Colorize(MapName(m), "textHint") or nil
      end
    end
    f.title:SetText(title)
    f.sub:SetText(sub or "")
    f.r1:ClearAllPoints()
    if e.k == "o" then f.r1:SetPoint("RIGHT", f, "RIGHT", -10, 0) else f.r1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -5) end
    f.r1:SetText(r1 or "")
    f.r2:SetText(r2 or "")
    f.title:ClearAllPoints()
    f.sub:ClearAllPoints()
    local left = level and 76 or 72
    local h = ns.Num(f:GetHeight()) or it.h or ROW_H
    if sub and sub ~= "" then
      local top = math.floor((h - 30) / 2)
      f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top - 1)
      f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -110, -top - 1)
      f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top - 17)
      f.sub:SetPoint("TOPRIGHT", f, "TOPRIGHT", -110, -top - 17)
    else
      f.title:SetPoint("LEFT", f, "LEFT", left, 0)
      f.title:SetPoint("RIGHT", f, "RIGHT", -110, 0)
    end
    local focus = ns.zoneFocus and ns.zoneFocus.questID
    if e.q and focus == e.q then f.active:Show() else f.active:Hide() end
    f.onClick = e.q and function() ns.FocusQuest(e.q, Shift()) end or nil
    f.tooltip = Fmt.EntryTooltip(e)
  end,
}

-- Quest line: level badge, title (with the dots of a chain), what it is
-- about, a coloured status on the right. Chain parts are indented.
local MAX_DOTS = 12
local QuestKind = {
  create = function(list)
    local f = CreateFrame("Button", nil, list)
    Clickable(f)
    f.active = Tex(f, "BACKGROUND", "rowActive", nil, 2)
    f.active:SetAllPoints(f)
    f.bar = Tex(f, "ARTWORK", "accent")
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.bar:SetWidth(2)
    f.badge = Tex(f, "ARTWORK", "textPrimary", 0.07)
    f.badge:SetSize(28, 18)
    f.level = Text(f, 11, "textPrimary", "CENTER")
    f.level:SetPoint("CENTER", f.badge, "CENTER", 0, 0)
    f.title = Text(f, 13, "textPrimary", "LEFT")
    f.sub = Text(f, 11, "textHint", "LEFT")
    f.pillText = Text(f, 11, "textPrimary", "RIGHT")
    f.pillText:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.pill = Tex(f, "ARTWORK", "accent", 0.16)
    f.pill:SetPoint("TOPLEFT", f.pillText, "TOPLEFT", -8, 4)
    f.pill:SetPoint("BOTTOMRIGHT", f.pillText, "BOTTOMRIGHT", 8, -4)
    f.toggle = Style.IconButton(f, "expand")
    f.toggle:SetSize(18, 18)
    f.toggle:SetOnClick(function() if f.onClick then ns.SafeCall("quest book", f.onClick, f) end end)
    f.dots = {}
    for i = 1, MAX_DOTS do
      local d = Icon(f, 7, CIRCLE, "OVERLAY")
      f.dots[i] = d
    end
    return f
  end,
  render = function(f, it)
    local indent = it.indent or 0
    f.badge:ClearAllPoints()
    f.badge:SetPoint("LEFT", f, "LEFT", 10 + indent, 0)
    local lv = it.level and it.level > 0 and it.level or nil
    f.level:SetText(lv and tostring(lv) or "?")
    local lc = it.quiet and C.textHint or LevelRGB(lv)
    f.level:SetTextColor(lc[1], lc[2], lc[3], 1)
    f.title:SetText(it.quiet and Style.Colorize(it.title or "", "textHint") or (it.title or ""))
    f.sub:SetText(it.sub or "")
    f.title:ClearAllPoints()
    f.sub:ClearAllPoints()
    local left = 48 + indent
    local h = ns.Num(f:GetHeight()) or it.h or ROW_H
    if it.sub and it.sub ~= "" then
      -- both lines hang from the top edge (two points at one height each)
      local top = math.floor((h - 30) / 2)
      f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top - 1)
      f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", left, -top - 17)
      f.sub:SetPoint("TOPRIGHT", f, "TOPRIGHT", -150, -top - 17)
    else
      f.title:SetPoint("LEFT", f, "LEFT", left, 0)
    end
    -- the dots of a chain right after the title
    local n = it.dots and #it.dots or 0
    local tw = math.min(TextWidth(f.title), 330)
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
    -- status on the right
    if it.pill and it.pill ~= "" then
      f.pillText:SetText(it.pill)
      SetColor(f.pillText, it.pillColor or "textSecondary")
      Fill(f.pill, it.pillColor or "textSecondary", it.pillColor == "textHint" and 0.08 or 0.16)
      f.pillText:Show() f.pill:Show()
    else
      f.pillText:Hide() f.pill:Hide()
    end
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
    f.track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 7)
    f.track:SetHeight(3)
    f.fill = Tex(f, "OVERLAY", "good")
    f.fill:SetPoint("TOPLEFT", f.track, "TOPLEFT", 0, 0)
    f.fill:SetPoint("BOTTOMLEFT", f.track, "BOTTOMLEFT", 0, 0)
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
    if it.here then f.here:Show() else f.here:Hide() end
    if it.selected then f.sel:Show() f.selBar:Show() else f.sel:Hide() f.selBar:Hide() end
    if s and s.total > 0 then
      f.track:Show()
      local w = math.max(1, (ns.Num(f:GetWidth()) or (SIDE_W - 30)) - 22)
      local frac = s.done / s.total
      if frac > 0 then f.fill:SetWidth(math.max(1, w * frac)) f.fill:Show() else f.fill:Hide() end
    else
      f.track:Hide() f.fill:Hide()
    end
    f.onClick, f.tooltip = it.onClick, it.tooltip
  end,
}

local KINDS = { head = HeadKind, empty = EmptyKind, entry = EntryKind, quest = QuestKind, zone = ZoneKind }

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
    s = { total = #list, done = 0 }
    for _, e in ipairs(list) do if e.group == "done" then s.done = s.done + 1 end end
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
  local day
  for _, e in ipairs(entries) do
    if Keep(e, jfilter, here) then
      local key = e.t and Fmt.DayKey(e.t) or -1
      if key ~= day then
        day = key
        items[#items + 1] = { kind = "head", h = HEAD_H, text = e.t and Fmt.DayTitle(e.t) or L["Unknown date"], color = "textPrimary" }
      end
      items[#items + 1] = { kind = "entry", h = ROW_H, e = e, quests = perLevel[e] }
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
  if e.group == "done" then return L["done"], "good" end
  return L["later"], "textHint"
end

local function QuestSubText(e)
  if e.group == "later" then return e.text end
  if e.group == "done" then return nil end
  local givers = ns.QuestGiverIDs(e.questID)
  local giver = givers and ns.CreatureName(givers[1])
  local learned = ns.db.learned and ns.db.learned[e.questID]
  giver = giver or (learned and learned.start and learned.start.npc)
  return giver and (L["Quest giver"] .. ": " .. giver) or nil
end

-- (1.3) quests only in the older data: a note until Forever confirms them
local function QuestSub(e)
  local sub = QuestSubText(e)
  if e.unconfirmed then
    local note = Style.Colorize(L["not seen in Forever yet"], "warning")
    sub = sub and (sub .. "  ·  " .. note) or note
  end
  return sub
end

local DOT = { done = "good", log = "warning", available = "accent", later = "textHint" }

local function FocusID() return ns.zoneFocus and ns.zoneFocus.questID end

local function QuestItem(e, extra)
  local pill, color = Pill(e)
  local it = { kind = "quest", h = ROW_H, level = e.level, title = e.title or ns.QuestTitle(e.questID),
    sub = QuestSub(e), pill = pill, pillColor = color, quiet = e.group == "done" or e.group == "later",
    active = FocusID() == e.questID, tooltip = ns.ZoneQuestTooltip(e) }
  it.onClick = function() ns.FocusQuest(e.questID, Shift()) end
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
  local s = { total = #list, done = 0 }
  for _, e in ipairs(list) do if e.group == "done" then s.done = s.done + 1 end end
  if m then stats[m] = s end
  -- one line per title (a chain of quests with the same name)
  local byKey, order = {}, {}
  for _, e in ipairs(list) do
    local k = Norm(e.title) ~= "" and Norm(e.title) or tostring(e.questID)
    local g = byKey[k]
    if not g then g = { key = (m or 0) .. ":" .. k, parts = {}, rep = e } byKey[k] = g order[#order + 1] = g end
    g.parts[#g.parts + 1] = e
  end
  local counts = {}
  for _, g in ipairs(order) do counts[g.rep.group] = (counts[g.rep.group] or 0) + 1 end
  local group
  for _, g in ipairs(order) do
    local e = g.rep
    if e.group ~= group then
      group = e.group
      local head = { kind = "head", h = HEAD_H, text = L[ns.ZONE_GROUP_TITLE[group]], count = counts[group] }
      if group == "done" then
        head.right = showDone and L["hide"] or L["show"]
        head.onClick = function() showDone = not showDone Refresh() end
      end
      items[#items + 1] = head
    end
    if group ~= "done" or showDone then
      if #g.parts == 1 then
        items[#items + 1] = QuestItem(e)
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
        it.title = (e.title or "") .. Style.Colorize(("  %d/%d"):format(done, #parts), "textHint")
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
      return MapName(m) or ("Map " .. m), {
        { L["Level"], RangeText(z) },
        { L["Quests"], L["%d of %d done"]:format(st.done, st.total) },
      }
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

-- A text button with a soft background (chips, segments).
local function Chip(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(22)
  b.bg = Tex(b, "BACKGROUND", "textPrimary", 0.05)
  b.bg:SetAllPoints(b)
  b.text = Text(b, 11, "textSecondary", "CENTER")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetScript("OnEnter", function(self) if not self.on then Fill(self.bg, "textPrimary", 0.10) end end)
  b:SetScript("OnLeave", function(self) if not self.on then Fill(self.bg, "textPrimary", 0.05) end end)
  b:SetScript("OnClick", function(self) if onClick then ns.SafeCall("quest book", onClick, self) end end)
  function b:Set(text, on)
    self.text:SetText(text)
    self.on = on and true or false
    Fill(self.bg, on and "accent" or "textPrimary", on and 0.20 or 0.05)
    SetColor(self.text, on and "textPrimary" or "textSecondary")
    self:SetWidth(TextWidth(self.text) + 20)
  end
  return b
end

local function Layout(chips, gap)
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

local function EditBox(parent, placeholderText, onChange)
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

-- Statistic tile: label, value, small text, optional bar.
local function Tile(parent)
  local t = CreateFrame("Frame", nil, parent)
  t.bg = Tex(t, "BACKGROUND", "textPrimary", 0.04)
  t.bg:SetAllPoints(t)
  Border(t, "textPrimary", 0.06)
  t.label = Text(t, 10, "textHint", "LEFT")
  t.label:SetPoint("TOPLEFT", t, "TOPLEFT", 10, -8)
  t.value = Text(t, 18, "textPrimary", "LEFT")
  t.value:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 10, 9)
  t.small = Text(t, 11, "textHint", "LEFT")
  t.small:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 6, 1)
  t.track = Tex(t, "ARTWORK", "barBackground")
  t.track:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 10, 5)
  t.track:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -10, 5)
  t.track:SetHeight(3)
  t.fill = Tex(t, "OVERLAY", "accent")
  t.fill:SetPoint("TOPLEFT", t.track, "TOPLEFT", 0, 0)
  t.fill:SetPoint("BOTTOMLEFT", t.track, "BOTTOMLEFT", 0, 0)
  t.track:Hide() t.fill:Hide()
  return t
end

local function CreateJournalPage(page)
  P.tiles = {}
  for i = 1, 4 do P.tiles[i] = Tile(page) end
  page:SetScript("OnSizeChanged", function(self, w)
    w = (ns.Num(w) or W) - 28
    local each = (w - 3 * 8) / 4
    for i, t in ipairs(P.tiles) do
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self, "TOPLEFT", 14 + (i - 1) * (each + 8), -12)
      t:SetSize(each, 58)
    end
  end)
  P.chips = {}
  for i, key in ipairs(FILTERS) do
    local c = Chip(page, function() jfilter = key Refresh(true) end)
    c.key = key
    if i == 1 then c:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -80) end
    P.chips[i] = c
  end
  P.footer = CreateFrame("Frame", nil, page)
  P.footer:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
  P.footer:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
  P.footer:SetHeight(28)
  Tex(P.footer, "BACKGROUND", "header"):SetAllPoints(P.footer)
  P.footLeft = Text(P.footer, 11, "textHint", "LEFT")
  P.footLeft:SetPoint("LEFT", P.footer, "LEFT", 14, 0)
  P.footOld = CreateFrame("Button", nil, P.footer)
  P.footOld:SetPoint("RIGHT", P.footer, "RIGHT", -10, 0)
  P.footOld:SetHeight(22)
  P.footOld.text = Text(P.footOld, 11, "accent", "RIGHT")
  P.footOld.text:SetPoint("RIGHT", P.footOld, "RIGHT", -4, 0)
  P.footOld:SetScript("OnClick", function()
    local l = lists.journal
    if l and l.items.oldAt then l:ScrollTo(l.items.oldAt) end
  end)
  local list = NewList(page, KINDS)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -110)
  list:SetPoint("BOTTOMRIGHT", P.footer, "TOPRIGHT", -4, 4)
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
  local t = P.tiles
  t[1].label:SetText(L["Today"])
  t[1].value:SetText(tostring(q))
  t[1].small:SetText(L["quests"])
  t[2].label:SetText(L["Experience today"])
  t[2].value:SetText(xp > 0 and ("+" .. Style.Number(xp)) or "0")
  SetColor(t[2].value, xp > 0 and "warning" or "textPrimary")
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
    local w = math.max(1, (ns.Num(t[4]:GetWidth()) or 200) - 20)
    t[4].track:Show()
    if frac > 0 then t[4].fill:SetWidth(w * frac) t[4].fill:Show() else t[4].fill:Hide() end
  else
    t[4].value:SetText("-")
    t[4].track:Hide() t[4].fill:Hide()
  end
  local since = lastLevel and Fmt.Span(Fmt.Now() - lastLevel)
  t[4].small:SetText(since and L["%s on this level"]:format(since) or "")
end

local function CreateZonePage(page)
  local side = CreateFrame("Frame", nil, page)
  side:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  side:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
  side:SetWidth(SIDE_W)
  Tex(side, "BACKGROUND", { 0, 0, 0 }, 0.22):SetAllPoints(side)
  local edge = Tex(side, "BORDER", "divider")
  edge:SetPoint("TOPRIGHT") edge:SetPoint("BOTTOMRIGHT") edge:SetWidth(1)
  P.zoneBox = EditBox(side, L["Find a zone"], function(text) zoneQuery = text Refresh() end)
  P.zoneBox:SetPoint("TOPLEFT", side, "TOPLEFT", 10, -10)
  P.zoneBox:SetPoint("TOPRIGHT", side, "TOPRIGHT", -10, -10)
  P.zoneBox:SetHeight(24)
  local zl = NewList(side, KINDS)
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
  local bottom = Tex(hero.shade, "BORDER", "divider")
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
  hero.fill = Tex(hero.shade, "OVERLAY", "good")
  hero.fill:SetPoint("TOPLEFT", hero.track, "TOPLEFT", 0, 0)
  hero.fill:SetPoint("BOTTOMLEFT", hero.track, "BOTTOMLEFT", 0, 0)
  P.hero = hero

  P.segQuests = Chip(main, function() zoneSeg = "quests" lists.zone.offset = 1 Refresh() end)
  P.segQuests:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 14, -8)
  P.segJournal = Chip(main, function() zoneSeg = "journal" lists.zone.offset = 1 Refresh() end)
  P.segHere = Chip(main, function() SelectZone(nil) end)
  P.segHere:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", -14, -8)
  local list = NewList(main, KINDS)
  list:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 6, -38)
  list:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -4, 6)
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

local function UpdateHeroArt(m)
  local hero = P.hero
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
  local width = ns.Num(hero:GetWidth()) or 0
  if width <= 1 then width = W - SIDE_W end
  local scale = width / lw
  local shift = ((lh * scale) - HERO_H) / 2 -- map pixels above the picture
  local drawn = 0
  -- x, y, w, h in map pixels (y down), u, v: used part of the texture file
  local function Piece(file, x, y, w, h, u, v, sub)
    local X, Y, Wd, Ht = x * scale, y * scale - shift, w * scale, h * scale
    local ya, yb = math.max(0, Y), math.min(HERO_H, Y + Ht)
    local xa, xb = math.max(0, X), math.min(width, X + Wd)
    if yb <= ya or xb <= xa then return end
    drawn = drawn + 1
    local t = hero.tiles[drawn]
    if not t then t = hero:CreateTexture(nil, "BACKGROUND", nil, 2) hero.tiles[drawn] = t end
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

local function CreateSearchPage(page)
  P.searchBox = EditBox(page, L["Search quest, zone, level or ID"], function(text) query = text Refresh(true) end)
  P.searchBox:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -12)
  P.searchBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -12)
  P.searchBox:SetHeight(30)
  local list = NewList(page, KINDS)
  list:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -52)
  list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 6)
  lists.search = list
end

local function TabButton(parent, key)
  local b = CreateFrame("Button", nil, parent)
  b.key = key
  b:SetSize(118, HEADER_H)
  b.hover = Tex(b, "BACKGROUND", "rowHover")
  b.hover:SetAllPoints(b)
  b.hover:Hide()
  b.icon = Icon(b, 16, TAB_ICON[key], "ARTWORK")
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b.text = Text(b, 13, "textSecondary", "LEFT")
  b.text:SetText(L[TAB_TITLE[key]])
  b.icon:SetPoint("RIGHT", b, "CENTER", -TextWidth(b.text) / 2 + 2, 0)
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.mark = Tex(b, "OVERLAY", "accent")
  b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 14, 0)
  b.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -14, 0)
  b.mark:SetHeight(2)
  b:SetScript("OnEnter", function(self) self.hover:Show() end)
  b:SetScript("OnLeave", function(self) self.hover:Hide() end)
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
  Tex(book, "BACKGROUND", "background", 0.97):SetAllPoints(book)
  Border(book, "textPrimary", 0.10)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "QuestdonQuestBook") end
  book:SetScript("OnHide", function()
    ns.zoneFocus = nil
    if ns.RefreshPins then ns.RefreshPins() end
  end)

  local header = CreateFrame("Frame", nil, book)
  header:SetPoint("TOPLEFT", book, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", book, "TOPRIGHT", -1, -1)
  header:SetHeight(HEADER_H)
  Tex(header, "BACKGROUND", "header"):SetAllPoints(header)
  local hline = Tex(header, "BORDER", "divider")
  hline:SetPoint("BOTTOMLEFT") hline:SetPoint("BOTTOMRIGHT") hline:SetHeight(1)
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
  P.tabs = {}
  local prev = close
  for i = #TABS, 1, -1 do
    local b = TabButton(header, TABS[i])
    b:SetPoint("RIGHT", prev, "LEFT", prev == close and -14 or 0, 0)
    P.tabs[TABS[i]] = b
    prev = b
  end

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
  local items = JournalItems()
  local c = ns.JournalCounts()
  local n = { all = nil, c = c.c, a = c.a, x = c.x + c.f, l = c.l }
  for _, chip in ipairs(P.chips) do
    local label = L[FILTER_TITLE[chip.key]]
    if n[chip.key] and n[chip.key] > 0 then label = label .. "  " .. n[chip.key] end
    chip:Set(label, chip.key == jfilter)
  end
  Layout(P.chips)
  local dated = c.a + c.c + c.x + c.f + c.l
  P.footLeft:SetText(L["%d entries"]:format(dated))
  if items.old and items.old > 0 then
    P.footOld.text:SetText(L["Done earlier (%d)"]:format(items.old))
    P.footOld:SetWidth(TextWidth(P.footOld.text) + 8)
    P.footOld:Show()
  else
    P.footOld:Hide()
  end
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
  if selZone and selZone ~= here then
    P.segHere:Set(L["Back to my zone"], false)
    P.segHere:Show()
  else
    P.segHere:Hide()
  end
  lists.zone:SetItems(items, not reset)
end

local function RenderSearch(reset)
  lists.search:SetItems(SearchItems(), not reset)
end

local lastTab
function Refresh(reset)
  if not book or not book:IsShown() then return end
  for key, b in pairs(P.tabs) do
    local on = key == tab
    SetColor(b.text, on and "textPrimary" or "textSecondary")
    if b.icon.SetDesaturated then b.icon:SetDesaturated(not on) end
    b.icon:SetAlpha(on and 1 or 0.6)
    if on then b.mark:Show() else b.mark:Hide() end
  end
  for key, page in pairs(P.pages) do if key == tab then page:Show() else page:Hide() end end
  if tab ~= lastTab then reset = true lastTab = tab end
  if tab == "journal" then RenderJournal(reset)
  elseif tab == "zone" then RenderZone(reset)
  else RenderSearch(reset) end
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
function ns.QuestBookZone() return ShownZone() end
-- For /qd diag: where the picture of the zone came from.
function ns.QuestBookArt()
  local h = P.hero
  if not h then return "not built" end
  return ("%s, map %s, %d tiles drawn, %d explored areas, width %s"):format(tostring(h.artSource), tostring(h.artMap), h.artDrawn or 0, h.artExplored or 0, tostring(ns.Num(h:GetWidth())))
end
function ns.QuestBookFilter(key) if key then jfilter = key Refresh(true) end return jfilter end
function ns.QuestBookSegment(key) if key then zoneSeg = key Refresh(true) end return zoneSeg end
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
