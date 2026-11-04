local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- (1.3) The quest book: one large window with four tabs.
--
--   Zones    every zone of Kalimdor, the Eastern Kingdoms and the new Forever zones (Zephras Isle) on the left
--            (level range, your progress, a filter box); the picked zone on
--            the right with a picture of its map, "23 / 72 done", its
--            quests (ZoneQuests.lua) or your journal entries there. Quests
--            of a chain with the same name are one line ("2/6") that opens.
--   Dungeons (1.3.3, Daniel 08.10.) every dungeon with its quests for you,
--            sorted by level; under each open quest the quests still to do
--            before it ("First: ..."), with quest giver and zone.
--   Journal  the personal diary (Journal.lua): today's numbers at the top
--            (quests, XP, money, progress of the level), filters, then a
--            time line, newest first, with a mark per event; level-ups as a
--            golden band; at the end the quests done before the journal.
--   Search   journal, all quests and zones by name, level or quest ID.
--
-- Long lists are drawn as a window onto the list (mouse wheel), only the
-- visible lines exist as frames. Our own frames only; nothing of Blizzard's
-- is hooked. Escape closes the book.
---------------------------------------------------------------------------
-- (1.3.4) Daniel 08.10.: a detail card for the clicked quest, dungeons as "ready" cards with a route to the quest givers,
-- zone filters and sorting by distance, and a shorter journal (accepted and turned in in one line, day totals, the last
-- seven days).
-- (02.11.2026, StyleKit 2 step 4, Daniel: the book follows draft 4, docs/layout_2026-11-01/questdon_mockup_v4.html) built
-- from the shared blocks of the Don style (DonCore Kit): Kit.Window (720x420 to 1300x900, place and size in
-- ns.db.questBook), the zones as a Sidebar of ZoneRows, a Hero with the zone's map, ChipBars, Lists, four Tiles on the
-- journal, the dungeons as index cards (Kit.Card) with their prerequisites a click away, the focus card (Kit.Detail) on the
-- right with the chain as a path from left to right (Chain.lua). Every text one line, cut with "..." and the whole text
-- in the tooltip; under 960 px the focus card goes over the list, under 800 px the zone list becomes an icon rail. What
-- only Questdon draws (the zone map, the round map of the journal, the dungeon pictures) uses the kit's colours and helpers.
local Kit = LibStub("DonCore-1.0"):Get("Kit", 3)
local KC, KS = Kit.C, Kit.SIZE
local ROW_H, HEAD_H, SMALL_H = 36, 28, 28 -- (draft 4) quest and journal lines, group heads, small lines
local HERO_H = 76
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
  -- (1.3.11) moments; loot and professions show the item's and the profession's own icon
  s = MEDIA .. "JournalCamera",
  d = "Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_8",
  i = MEDIA .. "JournalGate",
  z = MEDIA .. "qd_explore",
  r = MEDIA .. "qd_loot",
  h = "Interface\\Icons\\INV_Misc_Rune_01",
  p = MEDIA .. "qd_object",
  u = MEDIA .. "JournalBanner",
}
local QUALITY_HEX = { [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80" }
local FULL_ICON = { r = true, p = true, h = true } -- square game icons: cut the edge, a little larger
local function EntryIcon(e)
  local tex
  if e.k == "r" and e.it then
    tex = ns.Value(C_Item and C_Item.GetItemIconByID, e.it) or ns.Value(GetItemIcon, e.it)
  elseif e.k == "p" and e.sp then
    tex = ns.Value(C_Spell and C_Spell.GetSpellTexture, e.sp) or ns.Value(GetSpellTexture, e.sp)
  end
  return tex or ICON[e.k] or ICON.o
end
local TAB_ICON = {
  journal = "Interface\\Icons\\INV_Misc_Book_09",
  zone = "Interface\\Icons\\INV_Misc_Map_01",
  search = "Interface\\Icons\\INV_Misc_Spyglass_03",
  dungeons = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
}
local TABS = { "zone", "dungeons", "journal", "search" } -- (draft 4) the order of the tabs
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
local tab = "zone" -- (02.11.2026, Daniel) the book starts on Zones, the first tab of draft 4
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
local MOMENT = Fmt.MOMENT or {} -- (1.3.11) the journal's moments (screenshots, deaths, dungeons ...)
local Pic = {} -- (1.3.11) pictures of the album: photo buttons, tiles, the big view (below)
local J3 = {} -- (1.3.11 Stufe 3) chapters, the review, the journal as text (below)
local UI = { w = 976, h = 566, cw = 976, mode = "full", dunView = "grid" } -- (02.11.2026) state of the window and its parts

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
-- (1.3.4) The book's own colours (the panel and the other windows keep Style.COLORS).
-- (28.10.2026, Questdon review: "a colour does not mean the same everywhere") the book's colours come from the kit's
-- Style.BOOK, the colours with a meaning (accent, good, warning, critical) from Style.COLORS, as in every other window;
-- only what the book alone draws stays here
local function Copy(c) return { c[1], c[2], c[3], c[4], hex = c.hex } end
local THEME = {
  divider       = { 0.86, 0.71, 0.42, 0.22 },
  barBackground = { 1, 1, 1, 0.09 },
  cardEdge      = { 0.86, 0.71, 0.42, 0.30 },
  violet        = { 0.66, 0.36, 0.95 },
  cyan          = { 0.30, 0.86, 0.95 },
}
for k, c in pairs(ns.Style.BOOK) do THEME[k] = Copy(c) end
for _, k in ipairs({ "accent", "good", "warning", "critical" }) do THEME[k] = Copy(ns.Style.COLORS[k]) end
for _, c in pairs(THEME) do
  c.hex = c.hex or string.format("ff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
ns.QUESTBOOK_THEME = THEME -- (tests)

local function RGB(c)
  if type(c) == "string" then c = THEME[c] or Style.COLORS[c] end
  return c or THEME.textPrimary
end

-- Coloured text in the book's colours.
local function Colorize(text, color)
  local c = RGB(color)
  local hex = c.hex or string.format("ff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
  return "|c" .. hex .. tostring(text or "") .. "|r"
end

local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

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

-- (02.11.2026) the book's colour names (THEME, Style.COLORS) as the kit's: status marks, texts, heads
UI.TONE = { good = "green", warning = "yellow", accent = "blue", critical = "red", textHint = "quiet",
  textSecondary = "muted", textPrimary = "txGold", gold = "txGold", goldLight = "txGold" }
UI.MARK = { log = "yellow", available = "blue", later = "grey", done = "green" } -- a quest's mark by its group
UI.FIT = { good = "green", critical = "red", textHint = "grey" } -- a dungeon's fit (Dungeons.lua) as a status
UI.WHOLE, UI.CUT = { 0, 1, 0, 1 }, { 0.08, 0.92, 0.08, 0.92 }
-- (02.11.2026, Daniel: "ein zweiter click auf die quest in der liste, sollte das geöffnete fenster rechts wieder
-- schließen") a click on the quest whose card is open closes the card; Shift-click always shows it (with arrow and map)
function UI.ToggleQuest(id)
  if not Shift() and UI.detailID == id and UI.detailEntry == nil then ns.QuestBookShowQuest(nil) return end
  ns.QuestBookShowQuest(id, Shift() and "map" or nil)
end
function UI.ToggleEntry(src)
  if UI.detailEntry ~= nil and UI.detailEntry == src then ns.QuestBookShowQuest(nil) return end
  ns.QuestBookShowEntry(src)
end
UI.TREE_STEP, UI.TREE_MAX = 24, 3 -- (02.11.2026) a follow-up quest under its prerequisite: 24 px per level, at most 3 levels
function UI.Tone(c) if c == nil then return nil end return UI.TONE[c] or c end
function UI.Shown(f, on) if on then f:Show() else f:Hide() end end

-- A tooltip of a line: its item's tooltip function, the book's colour names as the kit's. (1.3.4) The detail card is
-- open: it says all of it, no second tooltip for a quest line.
function UI.TipOf(row)
  local it = row.item
  local fn = it and it.tooltip
  if type(fn) ~= "function" then return nil end
  if row.questTip and UI.detailID ~= nil then return nil end
  local title, lines, hint = fn(row)
  if type(lines) == "table" then
    local out = {}
    for i, l in ipairs(lines) do
      if type(l) == "table" and type(l[3]) == "string" then out[i] = { l[1], l[2], UI.Tone(l[3]) } else out[i] = l end
    end
    lines = out
  end
  return title, lines, hint
end

-- Two letters for a zone in the icon rail: the first letters of its words ("Westfall" WE, "Dun Morogh" DM)
function UI.Short(name)
  local out = {}
  for w in tostring(name or ""):gmatch("[^%s%-']+") do
    local ch = w:match("^[%z\1-\127\194-\244][\128-\191]*")
    if ch and #out < 2 and not ch:match("^%l") then out[#out + 1] = ch end
  end
  if #out < 2 then
    local w = tostring(name or ""):match("^[^%s]+") or ""
    local a, b = w:match("^([%z\1-\127\194-\244][\128-\191]*)([%z\1-\127\194-\244][\128-\191]*)")
    out = { a or "", b or "" }
  end
  return Kit.Upper(table.concat(out))
end

-- Something typed: once it rests for 0.2 s
UI.typing = {}
function UI.Later(key, fn)
  local n = (UI.typing[key] or 0) + 1
  UI.typing[key] = n
  ns.After(0.2, function() if UI.typing[key] == n then ns.SafeCall("quest book", fn) end end)
end

local ZoneStats -- below (zones)

-- (1.3.11) a moment's line: what, where, when; a dungeon visit's time and bosses on the right
local function NoteTail(e) return e.note and Colorize("  ·  " .. e.note, "goldLight") or "" end
local function MomentRow(e)
  local title = Fmt.EntryTitle(e)
  if e.k == "r" and QUALITY_HEX[e.iq] then title = "|c" .. QUALITY_HEX[e.iq] .. title .. "|r"
  elseif e.k == "s" and e.note then title = Colorize(e.note, "goldLight") end
  local what = Colorize(L[Fmt.KIND_TEXT[e.k] or "?"], Fmt.KIND_COLOR[e.k] or "textHint")
  local parts = {}
  local zone = e.m and MapName(e.m)
  local place = (e.z and zone and (e.z .. ", " .. zone)) or e.z or zone
  if e.k ~= "z" and place then parts[#parts + 1] = place end
  if e.t then parts[#parts + 1] = Fmt.Clock(e.t) end
  if e.k == "d" and e.tg then parts[#parts + 1] = L["against %s"]:format(e.tg) end
  if e.k == "s" and e.auto == "l" then parts[#parts + 1] = L["at the level-up"] end
  local sub = what .. (#parts > 0 and Colorize("  ·  " .. table.concat(parts, "  ·  "), "textHint") or "")
  if e.k ~= "s" then sub = sub .. NoteTail(e) end
  local r1, r2
  if e.k == "i" then
    local open = ns.JournalRunOpen and ns.JournalRunOpen(e)
    local now = Fmt.Now()
    local d = (open and e.t and now and (now - e.t)) or e.d
    r1 = open and L["still inside"] or (d and Fmt.Span(d)) or nil
    if type(e.b) == "table" and #e.b > 0 then r2 = L["%d bosses"]:format(#e.b) end
  end
  return title, sub, r1, r2
end

-- (1.3.11) a moment on the map: the arrow to its spot, the world map there if asked
local function EntryToMap(e, openMap)
  if type(e) ~= "table" then return end
  if not MOMENT[e.k] and e.q then ns.FocusQuest(e.q, openMap) return end
  local m = e.pm or e.m
  if m and e.px and e.py and ns.SetArrowTarget then ns.SetArrowTarget(m, e.px, e.py, Fmt.EntryTitle(e)) end
  if openMap and m and OpenWorldMap and not ns.True(ns.Value(InCombatLockdown)) then pcall(OpenWorldMap, m) end
end
ns.QuestBookEntryToMap = EntryToMap -- (tests)

---------------------------------------------------------------------------
-- Line kinds: Kit.List kinds built from the kit's blocks. A line's item is its data (the builders below); a kind's row
-- writes what the kit's row shows (status, colours, the right column) into it and keeps the click, tooltip and "active"
-- logic of the line.
---------------------------------------------------------------------------
UI.KINDS = {}

-- Section heading (a group): gold capitals, count and a short text on the right; clickable ones fold (+/-)
UI.KINDS.head = { h = HEAD_H, make = function(list)
  local r = Kit.GroupHeader(list)
  local base = r.SetItem
  function r:SetItem(it, index, l)
    it.static = it.onClick == nil
    it.tooltipFn = it.tooltip and UI.TipOf or nil
    base(self, it, index, l)
    Kit.TextColor(self.text, UI.Tone(it.color) or KC.txGold)
    if l and l.rail then self.text:SetText("") self.arrow:SetText("") self.count:SetText("") end -- the icon rail: a divider
    self.onClick = it.onClick
  end
  return r
end }

-- A quiet line in the middle (nothing found, nothing yet)
UI.KINDS.empty = { h = 60, make = function(list)
  local f = CreateFrame("Frame", nil, list)
  f.text = Kit.Text(f, "row", KC.quiet, "CENTER")
  f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
  function f:SetItem(it) self.item = it self.text:SetText(it.text or "") self:Layout(self._w or self:GetWidth()) end
  function f:Layout(w) Kit.Fit(self.text, math.max(40, (tonumber(w) or 0) - 2 * KS.pad)) end
  f._cutTexts = { f.text }
  Kit.Stateful(f)
  return f
end }

-- Quest line: level badge in Blizzard's quest colours, title, a line below, the 3 px mark in the colour of its group
-- (yellow in the log, blue available, grey later, green done); a pill only when it is ready to turn in. A chain: its
-- parts as dots and "3/6" on the right, a click opens the parts (indented, a mark "1", "2" ...); a step before a dungeon
-- quest: its number as the mark.
function UI.QuestView(it)
  local lv = tonumber(it.level)
  if not (lv and lv > 0) then it.level, it.levelStatus = "?", "trivial" end
  it.status = UI.MARK[it.group] or "grey"
  it.done = it.group == "done" or nil
  it.pill = (it.group == "log" and it.stateColor == "good" and it.stateText) and { it.stateText, "ready" } or nil
  if it.step then it.chain = tostring(it.step) end
  it.tooltipFn = UI.TipOf
end
UI.KINDS.quest = { h = ROW_H, make = function(list)
  local r = Kit.ListRow(list)
  local base = r.SetItem
  function r:SetItem(it, index, l)
    UI.QuestView(it)
    self.questTip = it.questID ~= nil and not it.isChain
    self.tooltip = it.tooltip
    base(self, it, index, l)
    self.onClick = it.onClick
  end
  return r
end }

-- Journal line: the event's icon, "[6] Title", what happened, zone, time and how long the quest took; XP and money on
-- the right; level-ups with a gold mark; a screenshot's picture on the right when the album has it.
function UI.EntryView(it)
  local e = it.e
  local level, small = e.k == "l", e.k == "o"
  it.icon = EntryIcon(e)
  it.iconCoords = FULL_ICON[e.k] and UI.CUT or UI.WHOLE
  local title, sub, r1, r2
  if level then
    title = Colorize(Fmt.EntryTitle(e), "goldLight")
    local parts = { e.t and Fmt.Clock(e.t) or nil }
    if e.since then parts[#parts + 1] = L["after %s"]:format(Fmt.Span(e.since) or "?") end
    if it.quests and it.quests > 0 then parts[#parts + 1] = L["%d quests on the way"]:format(it.quests) end
    sub = table.concat(parts, "  ·  ") .. NoteTail(e)
  elseif MOMENT[e.k] then
    title, sub, r1, r2 = MomentRow(e)
  else
    local quiet = e.k == "x" or e.k == "o"
    local tag = ns.QuestLevelTag(e.q)
    if quiet then tag = Plain(tag) end
    local name = Fmt.EntryTitle(e)
    if it.part then name = name .. Colorize(("  (%s)"):format(it.part), "textHint") end
    title = tag .. name
    local what = Colorize(L[Fmt.KIND_TEXT[e.k] or "done earlier"], Fmt.KIND_COLOR[e.k] or "textHint")
    local parts = { what }
    local zone = e.m and MapName(e.m)
    if zone then parts[#parts + 1] = zone end
    if e.t then parts[#parts + 1] = Fmt.Clock(e.t) end
    if it.took and it.took > 0 then parts[#parts + 1] = L["took %s"]:format(Fmt.Span(it.took) or "?") end
    sub = #parts == 1 and what or (parts[1] .. Colorize("  ·  " .. table.concat(parts, "  ·  ", 2), "textHint"))
    sub = sub .. NoteTail(e)
    if e.x then r1 = "+" .. Style.Number(e.x) .. " " .. L["XP"] end
    r2 = Coins(e.g)
    if small then
      local m = ns.QuestStart(e.q)
      sub, r2 = nil, nil
      r1 = m and MapName(m) or nil
    end
  end
  if r2 and not r1 then r1, r2 = r2, nil end
  it.title, it.sub, it.right, it.right2 = title, sub, r1, r2
  it.rightColor = e.x and "txGold" or "muted"
  it.markColor = level and KC.goldBright or UI.Tone(Fmt.KIND_COLOR[e.k] or "textHint")
  it.done = (e.k == "x" or e.k == "o") or nil
  it.shot = e.k == "s" and ns.AlbumShotFor and ns.AlbumShotFor(e) or nil
  -- the line of the card's entry, else the quest of the card or the focus
  local focus = ns.zoneFocus and ns.zoneFocus.questID
  local src = type(e.src) == "table" and e.src or e
  local shown = UI.detailEntry
  it.active = ((shown ~= nil and shown == src) or (e.q and not MOMENT[e.k] and not shown and (focus == e.q or UI.detailID == e.q))) or nil
  -- (1.3.5) click: the detail card; Shift-click: also arrow and world map
  -- (1.3.11) moments: their own card with the note, Shift-click arrow and world map;
  -- right-click on a quest or a level-up: the card with your note
  if MOMENT[e.k] then
    it.onClick = function()
      if Shift() then EntryToMap(src, true) end
      UI.ToggleEntry(src)
    end
  elseif e.q then
    it.onClick = function(_, button)
      if button == "RightButton" and e.k ~= "o" then UI.ToggleEntry(src) return end
      UI.ToggleQuest(e.q)
    end
  elseif level then
    it.onClick = function() UI.ToggleEntry(src) end
  else
    it.onClick = nil
  end
  it.tooltip = Fmt.EntryTooltip(e)
  it.tooltipFn = UI.TipOf
end
UI.KINDS.entry = { h = ROW_H, make = function(list)
  local r = Kit.ListRow(list)
  r.photo = Pic.Button(r) -- (1.3.11) a screenshot's picture on the right
  local base = r.SetItem
  function r:SetItem(it, index, l)
    UI.EntryView(it)
    self.tooltip, self.questTip = it.tooltip, it.e.q ~= nil
    if it.shot then
      local ph = math.max(16, (it.h or ROW_H) - 8)
      local pw = math.floor(ph * 16 / 9 + 0.5)
      it.rightWidth = pw + (it.right and 48 or 0)
      Pic.Set(self.photo, it.shot, pw, ph)
      self.photo:ClearAllPoints()
      self.photo:SetPoint("RIGHT", self, "RIGHT", -KS.pad - (it.right and 48 or 0), 0)
    else
      it.rightWidth = nil
      Pic.Set(self.photo, nil)
    end
    base(self, it, index, l)
    self.onClick = it.onClick
  end
  return r
end }

-- Zone in the list on the left: name, level range, progress bar and "12/48", a blue dot where you are; in the icon rail
-- two letters. (Counted only for the zones in sight, cached until a quest is accepted or turned in.)
UI.KINDS.zone = { h = 36, make = function(list)
  local r = Kit.ZoneRow(list)
  local base = r.SetItem
  function r:SetItem(it, index, l)
    local s = it.map and ZoneStats(it.map)
    it.text = it.name or "?"
    it.progress = (s and s.total > 0) and { s.done, s.total } or nil
    it.quiet = (s and s.total == 0) or nil
    it.short = UI.Short(it.text)
    it.tooltipFn = UI.TipOf
    base(self, it, index, l)
    self._selected = it.selected or nil
    Kit.Refresh(self)
    self.onClick = it.onClick
  end
  return r
end }

-- (1.3.5) The chosen dungeon in plain words: "3 / 6" large on the left with "ready" and a bar, the sentences (what is
-- ready, what needs quests first, what opens later) on the right.
UI.KINDS.dsum = { h = 84, make = function(list)
  local f = CreateFrame("Frame", nil, list)
  f.bg = Kit.Fill(f, KC.card)
  f.bd = Kit.Border(f, KC.divider)
  f.big = Kit.Text(f, "hero", KC.txGold, "CENTER")
  f.big:SetPoint("TOP", f, "TOPLEFT", 70, -12)
  f.label = Kit.Text(f, "sub", KC.muted, "CENTER")
  f.label:SetPoint("TOP", f, "TOPLEFT", 70, -38)
  f.bar = Kit.ProgressBar(f)
  f.bar:SetHeight(4)
  f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -56)
  f.sep = Kit.Tex(f, "ARTWORK", KC.divider)
  f.sep:SetWidth(1)
  f.sep:SetPoint("TOPLEFT", f, "TOPLEFT", 140, -10)
  f.sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 140, 10)
  f.fit = Kit.Text(f, "sub", KC.green)
  f.fit:SetPoint("TOPLEFT", f, "TOPLEFT", 154, -10)
  f.lines = {}
  for i = 1, 4 do
    local t = Kit.Text(f, "row", KC.body)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 154, -10 - 18 * i)
    f.lines[i] = t
  end
  function f:SetItem(it)
    self.item = it
    self.big:SetText(ns.Fraction(it.ready or 0, math.max(it.open or 0, it.ready or 0)))
    self.label:SetText((it.open or 0) == 0 and L["all done"] or L["ready"])
    local frac = (it.total or 0) > 0 and ((it.ready or 0) + (it.done or 0)) / it.total or 0
    self.bar:Layout(100)
    self.bar:SetValue(math.min(1, frac))
    self.fit:SetText((it.fitText or "") .. ((it.done or 0) > 0 and Colorize("  ·  " .. L["%d of %d done"]:format(it.done, it.total), "textHint") or ""))
    Kit.TextColor(self.fit, UI.FIT[it.fitColor] or "quiet")
    for i, t in ipairs(self.lines) do t:SetText(it.lines and it.lines[i] or "") end
    self:Layout(self._w or self:GetWidth())
  end
  function f:Layout(w)
    local room = math.max(20, (tonumber(w) or 0) - 154 - KS.pad)
    Kit.Fit(self.fit, room)
    for _, t in ipairs(self.lines) do Kit.Fit(t, room) end
  end
  f._cutTexts = { f.fit, f.lines[1], f.lines[2], f.lines[3], f.lines[4] }
  Kit.Stateful(f)
  return f
end }

-- (1.3.5) One line of text under a quest: the way to it in colours, or the colour legend.
UI.KINDS.dpath = { h = 24, make = function(list)
  local f = CreateFrame("Frame", nil, list)
  f.text = Kit.Text(f, "sub", KC.muted)
  function f:SetItem(it)
    self.item = it
    self.text:ClearAllPoints()
    self.text:SetPoint("LEFT", self, "LEFT", it.legend and KS.pad or (KS.markBar + 8 + KS.indent), 0)
    Kit.TextColor(self.text, it.legend and KC.quiet or KC.muted)
    self.text:SetText(it.text or "")
    self:Layout(self._w or self:GetWidth())
  end
  function f:Layout(w)
    local it = self.item or {}
    Kit.Fit(self.text, math.max(20, (tonumber(w) or 0) - (it.legend and KS.pad or (KS.markBar + 8 + KS.indent)) - KS.pad))
  end
  f._cutTexts = { f.text }
  Kit.Stateful(f)
  return f
end }

-- (1.3.5, Daniel 10.10.: "a small fitting picture of the instance"; "the number is completely off-centre")
-- The round badge of a dungeon: its picture (Dungeons.lua: the game client's own art, nothing shipped),
-- masked round inside its disc. Without a picture the level, in a box as large as the circle and
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
-- (02.11.2026) the badge in a frame of its own (the head of the prerequisites, an index card): a disc, the level, the picture
function UI.Badge(f, size)
  if f.disc then return f end
  f.disc = f:CreateTexture(nil, "ARTWORK")
  f.disc:SetSize(size, size)
  f.disc:SetPoint("CENTER", f, "CENTER", 0, 0)
  if f.disc:SetTexture(CIRCLE) == false then f.disc:SetTexture(WHITE) end
  f.level = Kit.Text(f, "badge", KC.title, "CENTER")
  BadgeParts(f, f.disc, size)
  return f
end
-- Picture of inst, else the level, the disc in the colour of its fit
function UI.SetBadge(f, inst, levelText, fitColor, quiet)
  SetBadge(f, inst, levelText, quiet)
  local c = Kit.Color(UI.FIT[fitColor] or "grey")
  f.disc:SetVertexColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45, 1)
  f.level:SetTextColor(c[1], c[2], c[3], 1)
end

-- (1.3.11) A picture of the album (Questdon-Album) in a thin gold frame; a
-- click opens the big view, which pages through this character's pictures.
function Pic.Button(parent)
  local b = CreateFrame("Button", nil, parent)
  b.pic = b:CreateTexture(nil, "ARTWORK")
  b.pic:SetAllPoints(b)
  b.edge = Kit.Border(b, KC.goldMuted, 0, "OVERLAY")
  b:SetScript("OnEnter", function(self)
    self.edge:SetColor(KC.goldBright)
    Kit.Tooltip(self, L["Picture"], { L["Click: open the picture."] })
  end)
  b:SetScript("OnLeave", function(self) self.edge:SetColor(KC.goldMuted) Kit.HideTooltip(self) end)
  b:SetScript("OnClick", function(self)
    if self.shot then ns.SafeCall("quest book", Pic.Open, ns.AlbumMine(), self.shot) end
  end)
  b:Hide()
  return b
end
function Pic.Set(b, shot, w, h)
  b.shot = shot
  if not shot then b:Hide() return end
  b:SetSize(w, h)
  b.pic:SetTexture(ns.AlbumTexture(shot, w <= 256))
  b.pic:SetTexCoord(ns.AlbumCover(shot, w, h))
  b:Show()
end

-- (1.3.11) A row of the album: pictures as tiles, the time and zone on the
-- picture, the tooltip of its journal entry; a click opens the big view (it
-- pages through the same pictures as the section).
Pic.GAP = 8
function Pic.Tip(shot)
  local e = ns.AlbumEntryFor(shot)
  if e then
    local title, lines = Fmt.EntryTooltip(e)()
    return title, lines, L["Click: open the picture."]
  end
  return L["Picture"], { { L["Date"], Fmt.DayTitle(shot.t) .. "  " .. Fmt.Clock(shot.t) },
    { L["Not in this journal"], nil, "textHint" } }, L["Click: open the picture."]
end
function Pic.NewTile(row)
  local t = CreateFrame("Button", nil, row)
  t.pic = t:CreateTexture(nil, "BORDER")
  t.pic:SetAllPoints(t)
  t.shade = Kit.Tex(t, "ARTWORK", KC.window)
  t.shade:SetAlpha(0.75)
  t.shade:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
  t.shade:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
  t.shade:SetHeight(22)
  t.caption = Kit.Text(t, "sub", KC.title)
  t.caption:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 6, 5)
  t.edge = Kit.Border(t, KC.goldMuted, 0, "OVERLAY")
  if t.RegisterForClicks then t:RegisterForClicks("LeftButtonUp") end
  t:SetScript("OnEnter", function(self)
    self.edge:SetColor(KC.goldBright)
    if self.tooltip then
      local title, lines, hint = UI.TipOf({ item = { tooltip = self.tooltip } })
      if title then Kit.Tooltip(self, title, lines, hint) end
    end
  end)
  t:SetScript("OnLeave", function(self) self.edge:SetColor(self.mine and KC.goldMuted or KC.divider) Kit.HideTooltip(self) end)
  t:SetScript("OnClick", function(self) if self.onClick then ns.SafeCall("quest book", self.onClick, self) end end)
  return t
end
UI.KINDS.shots = { make = function(list)
  local f = CreateFrame("Frame", nil, list)
  f.tiles = {}
  function f:SetItem(it) self.item = it self:Layout(self._w or self:GetWidth()) end
  function f:Layout(w)
    local it = self.item
    if not it then return end
    w = tonumber(w) or 0
    local n = it.cols or 4
    local tw = math.max(20, math.floor((w - 2 * KS.gap - (n - 1) * Pic.GAP) / n))
    local th = math.max(20, (it.h or 100) - Pic.GAP)
    for i = 1, math.max(n, #self.tiles) do
      local shot = it.shots[i]
      local t = self.tiles[i]
      if shot and not t then t = Pic.NewTile(self) self.tiles[i] = t end
      if t and shot then
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self, "TOPLEFT", KS.gap + (i - 1) * (tw + Pic.GAP), 0)
        t:SetSize(tw, th)
        t.pic:SetTexture(ns.AlbumTexture(shot, tw <= 256))
        t.pic:SetTexCoord(ns.AlbumCover(shot, tw, th))
        local e = ns.AlbumEntryFor(shot)
        t.mine = e ~= nil
        t.pic:SetAlpha(t.mine and 1 or 0.8)
        t.edge:SetColor(t.mine and KC.goldMuted or KC.divider)
        local parts = { Fmt.Clock(shot.t) }
        local zone = e and e.m and MapName(e.m)
        if e and e.note then parts[#parts + 1] = Colorize(e.note, "goldLight") elseif zone then parts[#parts + 1] = zone end
        t.caption:SetText(table.concat(parts, "  ·  "))
        Kit.Fit(t.caption, tw - 12)
        t.onClick = function() Pic.Open(it.set, shot) end
        t.tooltip = function() return Pic.Tip(shot) end
        t:Show()
      elseif t then
        t:Hide()
      end
    end
  end
  return f
end }

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

local function Norm(s) return ns.FoldCase(s) end -- (review 5) "ärger" finds "Ärger", "кобольды" "Кобольды"

---------------------------------------------------------------------------
-- Building the lists
---------------------------------------------------------------------------
local Refresh

-- Journal: filtered entries with day headings; quests per level-up.
local FILTERS = { "all", "chap", "c", "a", "x", "l", "m", "p", "zone", "recap" }
local FILTER_TITLE = { all = "All", c = "Completed", a = "Accepted", x = "Abandoned", l = "Levels", m = "Moments", p = "Pictures", zone = "This zone",
  chap = "Chapters", recap = "Review" } -- (Stufe 3)

local function Keep(e, filter, here)
  if filter == "all" then return true end
  if filter == "x" then return e.k == "x" or e.k == "f" end
  if filter == "zone" then return e.m ~= nil and ZoneOf(e.m) == here end
  if filter == "m" then return MOMENT[e.k] == true end
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

-- (1.3.11) The album (filter "Pictures"): this character's pictures by day,
-- then the other pictures of the folder (other characters, before the journal).
function Pic.Items()
  local items = {}
  local l = lists.journal
  local rw = (l and ns.Num(l:GetWidth()) or 0) - 18
  if rw < 200 then rw = 940 end
  local cols = rw >= 860 and 5 or (rw >= 560 and 4 or 3)
  local tw = (rw - (cols - 1) * Pic.GAP) / cols
  local h = math.floor(tw * 9 / 16 + 0.5) + Pic.GAP
  local mine, other = {}, {}
  local all = ns.AlbumShots()
  for _, s in ipairs(all) do
    if ns.AlbumEntryFor(s) then mine[#mine + 1] = s else other[#other + 1] = s end
  end
  local function Add(set)
    local perDay = {}
    for _, s in ipairs(set) do
      local key = Fmt.DayKey(s.t)
      local d = perDay[key] or { n = 0 }
      perDay[key] = d
      d.n = d.n + 1
      local e = ns.AlbumEntryFor(s)
      local lv = e and ns.Num(e.l)
      if lv then d.lo = math.min(d.lo or lv, lv) d.hi = math.max(d.hi or lv, lv) end
    end
    local day, row
    for _, s in ipairs(set) do
      local key = Fmt.DayKey(s.t)
      if key ~= day then
        day = key
        local d = perDay[key]
        local right = d.lo and (d.lo == d.hi and L["Level %d"]:format(d.lo) or L["Level %d to %d"]:format(d.lo, d.hi)) or nil
        items[#items + 1] = { kind = "head", h = HEAD_H, text = Fmt.DayTitle(s.t), color = "textPrimary", count = d.n, right = right }
        row = nil
      end
      if not row or #row.shots >= cols then
        row = { kind = "shots", h = h, shots = {}, cols = cols, set = set }
        items[#items + 1] = row
      end
      row.shots[#row.shots + 1] = s
    end
  end
  Add(mine)
  if #other > 0 then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Not in this journal"], count = #other, color = "accent",
      tooltip = function() return L["Not in this journal"], { { L["Pictures of other characters or from before the journal. Open one to add it to this journal."] } } end }
    Add(other)
  end
  if #items == 0 then
    items[1] = { kind = "empty", h = 60, text = L["No pictures yet. Run the Questdon-Album helper, then type /reload."] }
  end
  items.pictures = #all
  items.old = 0
  return items
end

---------------------------------------------------------------------------
-- (1.3.11) The big picture view: one picture of the album as large as it
-- fits, arrows and the mouse wheel page through the same set, a line with
-- date, place, level and target, the quest you followed below, the note as
-- its title. A picture without a journal entry can be added to this
-- character's journal; one with an entry opens its card. Escape closes it.
-- (02.11.2026) in the Don style: the kit's colours, texts and buttons.
---------------------------------------------------------------------------
Pic.W, Pic.H = 980, 640
function Pic.Create()
  local v = CreateFrame("Frame", "QuestdonAlbumView", UIParent)
  v:SetSize(Pic.W, Pic.H)
  v:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  if v.SetFrameStrata then v:SetFrameStrata("DIALOG") end
  if v.SetToplevel then v:SetToplevel(true) end
  if v.SetClampedToScreen then v:SetClampedToScreen(true) end
  Kit.Fill(v, KC.window)
  Kit.Border(v, KC.outer, 0)
  Kit.Border(v, KC.gold, 1)
  v:EnableMouse(true)
  v:SetMovable(true)
  v:RegisterForDrag("LeftButton")
  v:SetScript("OnDragStart", function(self) self:StartMoving() end)
  v:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  v:EnableMouseWheel(true)
  v:SetScript("OnMouseWheel", function(self, delta)
    local i = self.i - (ns.Num(delta) or 0)
    if self.set[i] then self.i = i Pic.Show() end
  end)
  v.title = Kit.Text(v, "title", KC.hero)
  v.title:SetPoint("TOPLEFT", v, "TOPLEFT", 20, -16)
  v.count = Kit.Text(v, "sub", KC.muted, "RIGHT")
  v.count:SetPoint("TOPRIGHT", v, "TOPRIGHT", -46, -19)
  v.close = Kit.IconButton(v, "close", { tooltip = L["Close"], onClick = function() v:Hide() end })
  v.close:SetPoint("TOPRIGHT", v, "TOPRIGHT", -12, -12)
  v.stage = Kit.Tex(v, "BORDER", KC.input)
  v.stage:SetPoint("TOPLEFT", v, "TOPLEFT", 16, -44)
  v.stage:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -16, 76)
  v.pic = v:CreateTexture(nil, "ARTWORK")
  v.pic:SetPoint("CENTER", v.stage, "CENTER", 0, 0)
  v.prev = Kit.IconButton(v, "back", { tooltip = L["Newer picture"], onClick = function() if v.set[v.i - 1] then v.i = v.i - 1 Pic.Show() end end })
  v.prev:SetPoint("LEFT", v.stage, "LEFT", 10, 0)
  v.next = Kit.IconButton(v, "forward", { tooltip = L["Older picture"], onClick = function() if v.set[v.i + 1] then v.i = v.i + 1 Pic.Show() end end })
  v.next:SetPoint("RIGHT", v.stage, "RIGHT", -10, 0)
  v.info = Kit.Text(v, "row", KC.body)
  v.info:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 20, 50)
  v.quest = Kit.Text(v, "sub", KC.muted)
  v.quest:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 20, 30)
  v.entry = Kit.Button(v, L["Show in the journal"], { small = true, onClick = function()
    local e = v.shot and ns.AlbumEntryFor(v.shot)
    if not e then return end
    if ns.OpenQuestBook then ns.OpenQuestBook("journal") end
    ns.QuestBookShowEntry(e)
  end })
  v.entry:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -16, 14)
  v.map = Kit.Button(v, L["World map"], { small = true, onClick = function()
    local e = v.shot and ns.AlbumEntryFor(v.shot)
    if e then EntryToMap(e, true) end
  end })
  v.map:SetPoint("RIGHT", v.entry, "LEFT", -KS.gap, 0)
  v.adopt = Kit.Button(v, L["Add to this journal"], { small = true, kind = "primary", onClick = function()
    if not v.shot then return end
    ns.AlbumAdopt(v.shot)
    if Refresh then Refresh(true) end
    Pic.Show()
  end })
  v.adopt:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -16, 14)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "QuestdonAlbumView") end
  v:Hide()
  return v
end

function Pic.Show()
  local v = Pic.viewer
  local shot = v.set[v.i]
  v.shot = shot
  if not shot then v:Hide() return end
  local boxW = Pic.W - 32
  local boxH = Pic.H - 44 - 76
  local w, h = ns.AlbumFit(shot, boxW, boxH)
  v.pic:SetSize(w, h)
  v.pic:SetTexture(ns.AlbumTexture(shot, false))
  v.pic:SetTexCoord(0, 1, 0, 1)
  local e = ns.AlbumEntryFor(shot)
  v.title:SetText(e and e.note or L["Picture"])
  Kit.Fit(v.title, Pic.W - 160)
  v.count:SetText(ns.Fraction(v.i, #v.set))
  local parts = { Fmt.DayTitle(shot.t) .. "  " .. Fmt.Clock(shot.t) }
  if e then
    local zone = e.m and MapName(e.m)
    local place = (e.z and zone and (e.z .. ", " .. zone)) or e.z or zone
    if place then parts[#parts + 1] = place end
    if e.l then parts[#parts + 1] = L["Level %d"]:format(e.l) end
    if e.tg then parts[#parts + 1] = L["Target"] .. ": " .. e.tg end
    if e.pt then parts[#parts + 1] = L["Group"] .. ": " .. e.pt end
  else
    parts[#parts + 1] = Colorize(L["Not in this journal"], "textHint")
  end
  v.info:SetText(table.concat(parts, "  ·  "))
  Kit.Fit(v.info, Pic.W - 40)
  local rq = e and e.rq
  v.quest:SetText(rq and (L["Quest"] .. ": " .. (ns.QuestTitle(rq) or ("#" .. tostring(rq)))) or "")
  Kit.Fit(v.quest, Pic.W - 360)
  if v.set[v.i - 1] then v.prev:Show() else v.prev:Hide() end
  if v.set[v.i + 1] then v.next:Show() else v.next:Hide() end
  if e then
    v.adopt:Hide()
    v.entry:Show()
    if (e.pm or e.m) and e.px and e.py then v.map:Show() else v.map:Hide() end
  else
    v.entry:Hide() v.map:Hide()
    v.adopt:Show()
  end
end

-- Open the big view on a picture of a set (newest first).
function Pic.Open(set, shot)
  if type(set) ~= "table" or #set == 0 then return end
  Pic.viewer = Pic.viewer or Pic.Create()
  Pic.viewer.set = set
  Pic.viewer.i = 1
  for i, s in ipairs(set) do if s == shot then Pic.viewer.i = i break end end
  Pic.viewer:Show()
  Pic.Show()
end
ns.QuestBookOpenPicture = Pic.Open -- (tests)
function ns.QuestBookViewer() return Pic.viewer end -- (tests)

---------------------------------------------------------------------------
-- (1.3.11 Stufe 3, Daniel 23.10.) Chapters, the review and the journal as
-- text (the numbers come from Chronicle.lua). New line kinds: "card" (a
-- chapter, a record, a character), "bar" (played time of a level) and
-- "nums" (numbers in a row).
---------------------------------------------------------------------------
J3.open = {} -- chapter key -> true/false (nil: only the newest chapter is open)
J3.CHAPTER_H, J3.FACT_H, J3.BAR_H, J3.NUMS_H = 44, 36, 24, 52 -- (draft 4)
J3.MAX_TEXT = 600 -- lines of the text to copy
J3.PLUS, J3.MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"

-- one line per quest: "accepted" lines hidden behind the turn-in, how long each quest took, quests per level-up
function J3.Merge(entries, merge)
  local count, perLevel = 0, {}
  for i = #entries, 1, -1 do
    local e = entries[i]
    if e.k == "c" then count = count + 1 elseif e.k == "l" then perLevel[e] = count count = 0 end
  end
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
  return hidden, took, perLevel
end

function J3.ShortDate(t)
  local d = t and ns.Value(date, "*t", t)
  if type(d) ~= "table" then return "?" end
  return (L["{mon} {d}"]:gsub("{mon}", L[({ "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December" })[d.month] or "?"]):gsub("{d}", tostring(d.day)))
end

function J3.Levels(lo, hi)
  if not lo then return nil end
  if not hi or lo == hi then return L["Level %d"]:format(lo) end
  return L["Level %d to %d"]:format(lo, hi)
end

function J3.Played(s, exact)
  local t = Fmt.Span(s) or "?"
  return exact and t or ("~" .. t)
end

-- A card line (a chapter, a record, a character): icon, title, a line below, two values on the right; chapters with a
-- gold mark.
UI.KINDS.card = { h = 36, make = function(list)
  local r = Kit.ListRow(list)
  local base = r.SetItem
  function r:SetItem(it, index, l)
    it.iconCoords = it.coords or UI.WHOLE
    it.right, it.right2 = it.r1, it.r2
    it.rightColor = "txGold"
    it.rightWidth = math.max(KS.colRight, math.floor((tonumber(self._w) or 400) * 0.3))
    it.markColor = it.chap and KC.goldBright or nil
    it.tooltipFn = it.tooltip and UI.TipOf or nil
    base(self, it, index, l)
    self.onClick = it.onClick
  end
  return r
end }

-- Played time of a level as a bar: "Level 12", the bar, "1:12 h".
UI.KINDS.bar = { h = 24, make = function(list)
  local f = CreateFrame("Button", nil, list)
  f.label = Kit.Text(f, "sub", KC.muted)
  f.label:SetPoint("LEFT", f, "LEFT", KS.pad + 8, 0)
  f.bar = Kit.ProgressBar(f)
  f.value = Kit.Text(f, "sub", KC.body, "RIGHT")
  f.value:SetPoint("RIGHT", f, "RIGHT", -KS.pad, 0)
  function f:SetItem(it)
    self.item = it
    self.label:SetText(it.label or "")
    self.value:SetText(it.value or "")
    Kit.TextColor(self.label, it.now and KC.blue or KC.muted)
    self.bar:SetColor(it.now and "blue" or (it.exact and KC.goldBright or KC.gold))
    self._tipFn = it.tooltip and UI.TipOf or nil
    self:Layout(self._w or self:GetWidth())
  end
  function f:Layout(w)
    w = tonumber(w) or 0
    Kit.Fit(self.label, 112) Kit.Fit(self.value, 76)
    self.bar:ClearAllPoints()
    self.bar:SetPoint("LEFT", self, "LEFT", KS.pad + 8 + 120, 0)
    self.bar:Layout(math.max(10, w - (KS.pad + 8 + 120) - 80 - KS.pad))
    self.bar:SetValue(ns.Num(self.item and self.item.frac) or 0)
  end
  f._cutTexts = { f.label, f.value }
  Kit.Stateful(f, function(self, st) self.label:SetAlpha(st == "hover" and 1 or 0.9) end)
  return f
end }

-- Numbers in a row: big value, small label below.
UI.KINDS.nums = { h = 52, make = function(list)
  local f = CreateFrame("Frame", nil, list)
  f.bg = Kit.Fill(f, KC.card)
  f.bd = Kit.Border(f, KC.divider)
  f.cells = {}
  for i = 1, 6 do f.cells[i] = { value = Kit.Text(f, "hero", KC.hero, "CENTER"), label = Kit.Text(f, "sub", KC.muted, "CENTER") } end
  function f:SetItem(it) self.item = it self:Layout(self._w or self:GetWidth()) end
  function f:Layout(w)
    local it = self.item
    if not it then return end
    local n = math.max(1, #it.cells)
    local each = ((tonumber(w) or 0) - 16) / n
    local cut = {}
    for i, c in ipairs(self.cells) do
      local d = it.cells[i]
      if d then
        c.value:ClearAllPoints()
        c.value:SetPoint("TOP", self, "TOPLEFT", 8 + each * (i - 0.5), -8)
        c.label:ClearAllPoints()
        c.label:SetPoint("TOP", self, "TOPLEFT", 8 + each * (i - 0.5), -32)
        c.value:SetText(tostring(d[1] or ""))
        c.label:SetText(d[2] or "")
        Kit.TextColor(c.value, UI.Tone(d[3]) or KC.hero)
        Kit.Fit(c.value, math.max(10, each - 10)) Kit.Fit(c.label, math.max(10, each - 10))
        c.value:Show() c.label:Show()
        cut[#cut + 1] = c.value cut[#cut + 1] = c.label
      else
        c.value:Hide() c.label:Hide()
      end
    end
    self._cutTexts = cut
  end
  Kit.Stateful(f)
  return f
end }

-- Chapters (filter "Chapters"): a card per chapter, newest first; the open ones list their lines.
function J3.ChapterTip(ch)
  return function()
    local lines = {}
    local lv = J3.Levels(ch.l1, ch.l2)
    if lv then lines[#lines + 1] = { L["Your level"], lv } end
    lines[#lines + 1] = { L["From"], Fmt.DayTitle(ch.t1) .. "  " .. Fmt.Clock(ch.t1) }
    lines[#lines + 1] = { L["To"], Fmt.DayTitle(ch.t2) .. "  " .. Fmt.Clock(ch.t2) }
    lines[#lines + 1] = { L["Played time"], J3.Played(ch.time, ch.exact) }
    lines[#lines + 1] = { L["Completed"], tostring(ch.q), "good" }
    if ch.a > 0 then lines[#lines + 1] = { L["Accepted"], tostring(ch.a) } end
    if ch.xp > 0 then lines[#lines + 1] = { L["Experience"], "+" .. Style.Number(ch.xp), "warning" } end
    if ch.g > 0 then lines[#lines + 1] = { L["Money"], Fmt.Money(ch.g) or "" } end
    if ch.i > 0 then lines[#lines + 1] = { L["Dungeon visits"], tostring(ch.i) } end
    if ch.d > 0 then lines[#lines + 1] = { L["Deaths"], tostring(ch.d), "critical" } end
    if ch.s > 0 then lines[#lines + 1] = { L["Pictures"], tostring(ch.s) } end
    if #ch.mates > 0 then lines[#lines + 1] = { L["Quested with"], J3.Mates(ch.mates, 3), "goldLight" } end
    if not ch.exact then lines[#lines + 1] = { L["Without the played clock (older entries): pauses count as at most 20 minutes."], nil, "textHint" } end
    return ns.JournalChapterTitle(ch), lines, L["Click: open or close the chapter."]
  end
end

function J3.Mates(list, max)
  local out = {}
  for i = 1, math.min(#list, max or #list) do out[#out + 1] = list[i].n end
  return table.concat(out, ", ")
end

function J3.ChapterItems()
  local items = {}
  local chapters = ns.JournalChapters()
  if #chapters == 0 then
    items[1] = { kind = "empty", h = 60, text = L["No chapters yet. A chapter begins with three quests in a zone."] }
    return items
  end
  local entries = ns.JournalEntries()
  local hidden, took, perLevel = J3.Merge(entries, true)
  local where, lines = {}, {}
  for i, ch in ipairs(chapters) do for _, e in ipairs(ch.e) do where[e] = i end end
  for _, e in ipairs(entries) do -- newest first
    local i = where[e.src]
    if i and not hidden[e] then lines[i] = lines[i] or {} table.insert(lines[i], e) end
  end
  for i, ch in ipairs(chapters) do
    local open = J3.open[ch.key]
    if open == nil then open = i == 1 end
    local sub = {}
    sub[#sub + 1] = J3.Levels(ch.l1, ch.l2)
    local d1, d2 = J3.ShortDate(ch.t1), J3.ShortDate(ch.t2)
    sub[#sub + 1] = d1 == d2 and d1 or L["%s to %s"]:format(d1, d2)
    if #ch.mates > 0 then sub[#sub + 1] = L["with %s"]:format(J3.Mates(ch.mates, 2)) end
    local r2 = { J3.Played(ch.time, ch.exact) }
    if ch.s > 0 then r2[#r2 + 1] = L["%d pictures"]:format(ch.s) end
    if ch.d > 0 then r2[#r2 + 1] = L["%d deaths"]:format(ch.d) end
    local key = ch.key
    items[#items + 1] = { kind = "card", h = J3.CHAPTER_H, chap = ch, open = open,
      icon = open and J3.MINUS or J3.PLUS, iconSize = 16,
      title = Colorize(ns.JournalChapterTitle(ch), "goldLight"), sub = table.concat(sub, "  ·  "),
      r1 = L["%d quests"]:format(ch.q), r2 = table.concat(r2, "  ·  "),
      onClick = function() J3.open[key] = not open Refresh() end, tooltip = J3.ChapterTip(ch) }
    if open then
      for _, e in ipairs(lines[i] or {}) do
        items[#items + 1] = { kind = "entry", h = ROW_H, e = e, quests = perLevel[e], took = took[e] }
      end
    end
  end
  return items
end

-- The review (filter "Review").
function J3.QuestFact(rec, what)
  local e = rec.e
  local zone = e.m and MapName(e.m)
  local sub = { what }
  if zone then sub[#sub + 1] = zone end
  sub[#sub + 1] = J3.ShortDate(e.t)
  return { kind = "card", h = J3.FACT_H, icon = ICON.c, title = ns.QuestLevelTag(e.q) .. (Fmt.EntryTitle(e) or "?"),
    sub = table.concat(sub, "  ·  "), r1 = Fmt.Span(rec.s) or "?", r2 = rec.played and L["played"] or L["on the clock"],
    onClick = function() UI.ToggleQuest(e.q) end, tooltip = Fmt.EntryTooltip(e) }
end

function J3.CharCard(c)
  local cc = type(RAID_CLASS_COLORS) == "table" and c.c and RAID_CLASS_COLORS[c.c]
  local name = c.n
  if type(cc) == "table" and type(cc.colorStr) == "string" then name = "|c" .. cc.colorStr .. name .. "|r" end
  local coords = type(CLASS_ICON_TCOORDS) == "table" and c.c and CLASS_ICON_TCOORDS[c.c]
  local sub = {}
  local who = table.concat({ c.ra or "", c.cn or "" }, " "):gsub("^ ", ""):gsub(" $", "")
  if who ~= "" then sub[#sub + 1] = who end
  local zone = c.m and MapName(c.m)
  if zone then sub[#sub + 1] = zone end
  if c.r and not c.me then sub[#sub + 1] = c.r end
  local now = Fmt.Now()
  local when = c.me and Colorize(L["playing now"], "good") or (c.t and now and L["%s ago"]:format(Fmt.Span(math.max(60, now - c.t)) or "?")) or ""
  local key, me = c.key, c.me
  return { kind = "card", h = J3.FACT_H, icon = coords and "Interface\\TargetingFrame\\UI-Classes-Circles" or nil,
    coords = type(coords) == "table" and coords or nil, iconSize = 22,
    title = name, sub = table.concat(sub, "  ·  "),
    r1 = c.l and L["Level %d"]:format(c.l) or "", r2 = L["%d quests"]:format(c.q or 0) .. "  ·  " .. when,
    onClick = function(_, button)
      -- (28.10.2026, Questdon review: deleting without a question) a second right-click within 5 seconds
      if button == "RightButton" and not me and ns.Confirm("forget:" .. tostring(key),
          L["Right-click again within 5 seconds to take %s off the list."]:format(tostring(name)))
        and ns.JournalForgetCharacter(key) then Refresh() end
    end,
    tooltip = function()
      local lines = {}
      if c.r then lines[#lines + 1] = { L["Realm"], c.r } end
      if c.l then lines[#lines + 1] = { L["Your level"], tostring(c.l) } end
      if who ~= "" then lines[#lines + 1] = { L["Character"], who } end
      if zone then lines[#lines + 1] = { L["Zone"], zone } end
      lines[#lines + 1] = { L["Quests done"], tostring(c.q or 0) }
      if c.g then lines[#lines + 1] = { L["Money"], Fmt.Money(c.g) or "0" } end
      if c.t then lines[#lines + 1] = { L["Last played"], Fmt.DayTitle(c.t) .. "  " .. Fmt.Clock(c.t) } end
      return c.n, lines, (not me) and L["Right-click: off the list (a character that no longer exists)."] or nil
    end }
end

function J3.RecapItems()
  local items = {}
  local r = ns.JournalRecap()
  local tot = r.totals
  local played = ns.JournalPlayed and ns.JournalPlayed() or 0
  items[#items + 1] = { kind = "head", h = HEAD_H, text = L["In numbers"], right = played > 0 and L["%s played"]:format(Fmt.Span(played) or "?") or nil,
    tooltip = function() return L["In numbers"], { { L["Everything in this journal. Questdon counts played time since version 1.3.11."] } } end }
  items[#items + 1] = { kind = "nums", h = J3.NUMS_H, cells = {
    { tot.q, L["quests"], "good" }, { "+" .. Style.Number(tot.xp), L["experience"], "goldLight" },
    { Coins(tot.g, 14) or "0", L["money"] }, { tot.days, L["days"] } } }
  items[#items + 1] = { kind = "nums", h = J3.NUMS_H, cells = {
    { tot.zones, L["zones"] }, { tot.i, L["dungeon visits"] }, { tot.d, L["deaths"], tot.d > 0 and "critical" or nil },
    { tot.s, L["pictures"] }, { tot.r, L["rare loot"] } } }
  if r.longest or r.best then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Records"] }
    if r.longest then items[#items + 1] = J3.QuestFact(r.longest, L["Longest quest"]) end
    if r.fastest and r.fastest ~= r.longest then items[#items + 1] = J3.QuestFact(r.fastest, L["Fastest quest"]) end
    if r.best then
      items[#items + 1] = { kind = "card", h = J3.FACT_H, icon = ICON.l, title = Fmt.DayTitle(r.best.t), sub = L["Best day"],
        r1 = "+" .. Style.Number(r.best.xp) .. " " .. L["XP"], r2 = L["%d quests"]:format(r.best.q) }
    end
  end
  if r.week then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["A week ago"], right = Fmt.DayTitle(r.week.t) }
    local zones, seen = {}, {}
    for _, e in ipairs(r.weekEntries) do
      local z = e.m and ZoneOf(e.m)
      local name = z and MapName(z)
      if name and not seen[name] and #zones < 3 then seen[name] = true zones[#zones + 1] = name end
    end
    items[#items + 1] = { kind = "card", h = J3.FACT_H, icon = TAB_ICON.journal, iconSize = 22, coords = { 0.08, 0.92, 0.08, 0.92 },
      title = table.concat(zones, ", "), sub = L["%d quests"]:format(r.week.q) .. (r.week.xp > 0 and ("  ·  +" .. Style.Number(r.week.xp) .. " " .. L["XP"]) or "") }
    local shown = 0
    for i = #r.weekEntries, 1, -1 do
      local e = r.weekEntries[i]
      if e.k ~= "a" and shown < 8 then shown = shown + 1 items[#items + 1] = { kind = "entry", h = ROW_H, e = e } end
    end
  end
  if #r.mates > 0 then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Quested with"], count = #r.mates }
    for _, m in ipairs(r.mates) do
      items[#items + 1] = { kind = "card", h = J3.FACT_H - 8, title = m.n, sub = L["Quests turned in together"], r1 = tostring(m.c) }
    end
  end
  local chars = ns.JournalCharacters()
  if #chars > 0 then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Your characters"], count = #chars }
    for _, c in ipairs(chars) do items[#items + 1] = J3.CharCard(c) end
  end
  -- played time per level, the level you are on first
  local levels = {}
  for _, v in ipairs(r.levels) do levels[#levels + 1] = v end
  local nowS, nowExact = ns.JournalLevelPlayed()
  local level = ns.PlayerLevel()
  if nowS and level then levels[#levels + 1] = { l = level, s = nowS, exact = nowExact, now = true } end
  if #levels > 0 then
    local max = 60
    for _, v in ipairs(levels) do max = math.max(max, v.s) end
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Played time per level"],
      tooltip = function() return L["Played time per level"], { { L["Without the played clock (older entries): pauses count as at most 20 minutes."] } } end }
    for i = #levels, 1, -1 do
      local v = levels[i]
      local label = L["Level %d"]:format(v.l)
      if v.now then label = label .. "  " .. L["(now)"] end
      items[#items + 1] = { kind = "bar", h = J3.BAR_H, label = label, value = J3.Played(v.s, v.exact), frac = v.s / max, now = v.now, exact = v.exact,
        tooltip = function()
          local lines = { { L["Played time"], J3.Played(v.s, v.exact) } }
          if v.t then lines[#lines + 1] = { L["Reached the next level"], Fmt.DayTitle(v.t) .. "  " .. Fmt.Clock(v.t) } end
          if not v.exact then lines[#lines + 1] = { L["Without the played clock (older entries): pauses count as at most 20 minutes."], nil, "textHint" } end
          return L["Level %d"]:format(v.l), lines
        end }
    end
  end
  if #items <= 3 and tot.q == 0 then
    items[#items + 1] = { kind = "empty", h = 60, text = L["Nothing to look back on yet. Turn in a few quests."] }
  end
  return items
end

-- The journal as text to copy: what the list shows now, for Discord or a forum.
function J3.Plain(s)
  s = tostring(s or "")
  s = s:gsub("|T[^|]*GoldIcon[^|]*|t", "g"):gsub("|T[^|]*SilverIcon[^|]*|t", "s"):gsub("|T[^|]*CopperIcon[^|]*|t", "c")
  s = s:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("%s%s+", "  "):gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

function J3.EntryText(it)
  local e = it.e
  local P = J3.Plain
  if e.k == "o" then return "- " .. P(Fmt.EntryTitle(e) or ("#" .. tostring(e.q))) .. " (" .. L["done earlier"] .. ")" end
  local title = Fmt.EntryTitle(e) or "?"
  if e.q and not MOMENT[e.k] then title = ns.QuestLevelTag(e.q) .. title end
  local parts = {}
  if e.k ~= "l" then parts[#parts + 1] = L[Fmt.KIND_TEXT[e.k] or "?"] end
  local zone = e.m and MapName(e.m)
  local place = (e.z and zone and (e.z .. ", " .. zone)) or e.z or zone
  if place and e.k ~= "z" and e.k ~= "l" then parts[#parts + 1] = place end
  if it.took and it.took > 0 then parts[#parts + 1] = L["took %s"]:format(Fmt.Span(it.took) or "?") end
  if e.k == "l" then
    if e.since then parts[#parts + 1] = L["after %s"]:format(Fmt.Span(e.since) or "?") end
    if it.quests and it.quests > 0 then parts[#parts + 1] = L["%d quests on the way"]:format(it.quests) end
  end
  if e.x then parts[#parts + 1] = "+" .. Style.Number(e.x) .. " " .. L["XP"] end
  local money = Coins(e.g)
  if money then parts[#parts + 1] = money end
  if e.k == "d" and e.tg then parts[#parts + 1] = L["against %s"]:format(e.tg) end
  if e.k == "i" and e.d then parts[#parts + 1] = Fmt.Span(e.d) end
  if e.k == "i" and type(e.b) == "table" and #e.b > 0 then parts[#parts + 1] = table.concat(e.b, ", ") end
  if e.pt then parts[#parts + 1] = L["with %s"]:format(e.pt) end
  local shot = e.k == "s" and ns.AlbumShotFor and ns.AlbumShotFor(e) or nil
  if shot then parts[#parts + 1] = L["picture %s"]:format(shot.f) end
  if e.note then parts[#parts + 1] = '"' .. e.note .. '"' end
  local line = "- " .. (e.t and (Fmt.Clock(e.t) .. " ") or "") .. title
  if #parts > 0 then line = line .. " · " .. table.concat(parts, " · ") end
  return P(line)
end

function J3.Text(items)
  items = items or (lists.journal and lists.journal.items) or {}
  local P = J3.Plain
  local cls
  if type(UnitClass) == "function" then
    local ok, c = pcall(UnitClass, "player")
    if ok and type(c) == "string" and ns.Usable(c) then cls = c end
  end
  local name = ns.Value(UnitName, "player") or "?"
  local out = { "**" .. L["Questdon journal of %s, level %d"]:format(name, ns.PlayerLevel() or 0) .. (cls and (" " .. cls) or "") .. "**",
    L[FILTER_TITLE[jfilter] or "All"] .. ", " .. Fmt.DayTitle(Fmt.Now()) }
  for i, it in ipairs(items) do
    if #out >= J3.MAX_TEXT then
      out[#out + 1] = L["(%d more lines left out)"]:format(#items - i + 1)
      break
    end
    local k = it.kind
    if k == "head" then
      local line = "**" .. P(it.text) .. "**"
      if it.count then line = line .. " (" .. it.count .. ")" end
      if it.right and it.right ~= "" then line = line .. "  " .. P(it.right) end
      out[#out + 1] = ""
      out[#out + 1] = line
    elseif k == "entry" then
      out[#out + 1] = J3.EntryText(it)
    elseif k == "card" then
      local parts = { P(it.title) }
      for _, v in ipairs({ it.sub, it.r1, it.r2 }) do if v and P(v) ~= "" then parts[#parts + 1] = P(v) end end
      if it.chap then
        out[#out + 1] = ""
        out[#out + 1] = "**" .. table.concat(parts, " · ") .. "**"
      else
        out[#out + 1] = "- " .. table.concat(parts, " · ")
      end
    elseif k == "bar" then
      out[#out + 1] = "- " .. P(it.label) .. ": " .. P(it.value)
    elseif k == "nums" then
      local parts = {}
      for _, c in ipairs(it.cells) do parts[#parts + 1] = P(c[1]) .. " " .. P(c[2]) end
      out[#out + 1] = table.concat(parts, " · ")
    elseif k == "shots" then
      for _, s in ipairs(it.shots or {}) do out[#out + 1] = "- " .. Fmt.Clock(s.t) .. " " .. L["picture %s"]:format(s.f) end
    elseif k == "empty" then
      out[#out + 1] = P(it.text)
    end
  end
  return table.concat(out, "\n")
end

function J3.Export()
  return ns.ShowText(L["Journal as text"], L["Ctrl+C copies it. The text follows the list as it is now (filter, open chapters)."], J3.Text())
end
ns.QuestBookJournalText = function() return J3.Text() end -- (tests)

local function JournalItems()
  if jfilter == "p" then return Pic.Items() end
  if jfilter == "chap" then return J3.ChapterItems() end
  if jfilter == "recap" then return J3.RecapItems() end
  local items = {}
  local entries = ns.JournalEntries()
  local here = HereZone()
  -- quests completed before each level-up; (1.3.4) one line per quest: a quest
  -- turned in later hides its "accepted" line, the turned-in line says how long
  -- it took (filters "all" and "zone")
  local hidden, took, perLevel = J3.Merge(entries, jfilter == "all" or jfilter == "zone")
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
  return giver and (L["Quest giver"] .. L[": "] .. giver) or nil
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

local DOT = { done = "green", log = "yellow", available = "blue", later = "grey" } -- (draft 4) the kit's status colours

local function FocusID() return ns.zoneFocus and ns.zoneFocus.questID end

local function QuestItem(e, extra)
  local stateText, stateColor = Pill(e)
  local it = { kind = "quest", h = ROW_H, questID = e.questID, level = e.level, title = e.title or ns.QuestTitle(e.questID),
    sub = QuestSub(e), group = e.group, stateText = stateText, stateColor = stateColor, quiet = e.group == "done" or e.group == "later",
    active = FocusID() == e.questID or ns.QuestBookDetailID() == e.questID, tooltip = ns.ZoneQuestTooltip(e) }
  -- (1.3.5, Daniel 08.10. Merkliste) a click shows the detail card only, the arrow stays where it
  -- was; the card's buttons point the arrow and open the map. Shift-click: all at once.
  it.onClick = function() UI.ToggleQuest(e.questID) end
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
  -- (02.11.2026, Daniel: "quests eingerückt unter den vorquests") a quest whose prerequisite stands in the list too goes
  -- right under it, indented (one step per level, at most UI.TREE_MAX), with a mark "2", "3" ("2a", "2b" when one quest
  -- opens several). Its own status keeps its colour; the section is the one of the first quest of the line. Only a shown
  -- prerequisite counts: under a folded "done" section or outside the filter the quest stands on its own.
  local function Shown(g) return g.rep.group ~= "done" or showDone or zFilter == "done" end
  local byID = {}
  for _, g in ipairs(order) do for _, p in ipairs(g.parts) do byID[p.questID] = g end end
  local parentOf, kids = {}, {}
  for _, g in ipairs(order) do
    if Shown(g) then
      local first = #g.parts > 1 and ChainOrder(g.parts)[1] or g.rep
      for _, pre in ipairs(ns.QuestPrereqs and ns.QuestPrereqs(first.questID) or {}) do
        local pg = byID[pre]
        if pg and pg ~= g and Shown(pg) then
          -- no circle: the prerequisite must not hang below this quest already
          local up, loop = pg, false
          for _ = 1, 50 do up = parentOf[up] if not up then break end if up == g then loop = true break end end
          if not loop then parentOf[g] = pg kids[pg] = kids[pg] or {} table.insert(kids[pg], g) break end
        end
      end
    end
  end
  local counts = {}
  local function CountIn(g, grp) counts[grp] = (counts[grp] or 0) + 1 for _, k in ipairs(kids[g] or {}) do CountIn(k, grp) end end
  for _, g in ipairs(order) do if not parentOf[g] then CountIn(g, g.rep.group) end end
  local function Emit(g, depth, mark)
    local e = g.rep
    local indent = depth > 0 and math.min(depth, UI.TREE_MAX) * UI.TREE_STEP or nil
    if #g.parts == 1 then
      local it = QuestItem(e, { indent = indent, mark = mark })
      if zNear and g.dist and depth == 0 then
        local yd = L["%d yards"]:format(math.floor(g.dist + 0.5))
        it.sub = it.sub and (it.sub .. "  ·  " .. yd) or yd
      end
      items[#items + 1] = it
    else
      local parts = ChainOrder(g.parts)
      local done, dots, active = 0, {}, false
      for i, p in ipairs(parts) do
        if p.group == "done" then done = done + 1 end
        dots[i] = DOT[p.group] or "grey"
        if FocusID() == p.questID then active = true end
      end
      local open = expanded[g.key] and true or false
      local sub = QuestSub(e)
      sub = L["Chain of %d"]:format(#parts) .. (sub and ("  ·  " .. sub) or "")
      -- (draft 4) one line: the parts as dots and "3/6" on the right
      local it = QuestItem(e, { title = e.title, sub = sub, dots = dots, isChain = true, open = open, active = active and not open,
        right = ns.Fraction(done, #parts), indent = indent, mark = mark })
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
        -- (02.11.2026, Daniel: "part 1 und 2 sind ja schon erledigt, kann man das besser kennzeichnen?") a done part: a
        -- green tick in its mark and "Completed" in green beside the title ("vielleicht auch einfach daneben?")
        for i, p in ipairs(parts) do
          local done = p.group == "done"
          local title = L["Part %d of %d"]:format(i, #parts)
          if done then title = title .. "  " .. Colorize(L["Completed"], "good") end
          items[#items + 1] = QuestItem(p, { indent = (indent or 0) + KS.indent, chain = tostring(i), title = title,
            level = p.level, part = true, chainDone = done or nil })
        end
      end
    end
    local list2 = kids[g] or {}
    for i, k in ipairs(list2) do
      local n = tostring(depth + 2)
      Emit(k, depth + 1, #list2 > 1 and (n .. string.char(96 + math.min(i, 26))) or n)
    end
  end
  local group
  for _, g in ipairs(order) do
    if not parentOf[g] then
      local e = g.rep
      if e.group ~= group then
        group = e.group
        local head = { kind = "head", h = HEAD_H, text = L[ns.ZONE_GROUP_TITLE[group]], count = counts[group] }
        if group == "done" and zFilter ~= "done" then
          head.right = showDone and L["hide"] or L["show"]
          head.collapsed = not showDone
          head.onClick = function() showDone = not showDone Refresh() end
        end
        items[#items + 1] = head
      end
      if Shown(g) then Emit(g, 0, kids[g] and "1" or nil) end
    end
  end
  if #items == 0 then items[1] = { kind = "empty", h = 60, text = L["No quests known for this zone."] } end
  -- (02.11.2026, draft 4) the chain of the open card's quest is a path in the card now, no line under its row
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
  if lists.zone then lists.zone.offset = 0 end
  -- (02.11.2026, Daniel: "shift+klick auf eine quest in der liste öffnet das questbuch nicht") the book starts on Zones now:
  -- a closed book is opened here too, not only drawn again
  if tab ~= "zone" or not (book and book:IsShown()) then ns.OpenQuestBook("zone") else Refresh() end
end
ns.QuestBookSelectZone = SelectZone

local function ZoneRow(z, shown, here)
  local m = z.map
  return { kind = "zone", h = 36, map = m, name = MapName(m) or L["Map %d"]:format(m), range = RangeText(z),
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
      return MapName(m) or L["Map %d"]:format(m), lines
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
      items[#items + 1] = { kind = "head", h = HEAD_H, text = ContinentName(cont), collapsed = not open,
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
      if not group then it.stateText, it.stateColor, it.right = L["not for you"], "textHint", L["not for you"] end
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

-- (1.3.4) What to do in a quest in one line: the data's objective sentence, else the
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
-- (02.11.2026, draft 4) a dungeon chosen: its prerequisites; nil: back to the index cards
function ns.QuestBookSelectDungeon(inst) dunSel = inst UI.dunView = inst and "pre" or "grid" if Refresh then Refresh(true) end end

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
  items[#items + 1] = { kind = "dsum", h = math.max(78, 30 + 18 * #lines), inst = inst, ready = ready, open = open, done = done,
    total = #entries, lines = lines, fitText = fitText, fitColor = fitColor }
  -- take now: in the log first, then to pick up
  local now = {}
  for _, e in ipairs(entries) do if e.group == "log" or e.group == "available" then now[#now + 1] = e end end
  if #now > 0 then
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Take now"], color = "good", count = #now }
    for _, e in ipairs(now) do
      local it = QuestItem(e, { goal = true })
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
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Do these first"], color = "warning", count = #steps }
    for i, p in ipairs(steps) do
      local c = QuestItem(p, { step = stepOf[p.questID], firstStep = i == 1, lastStep = i == #steps })
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
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Not yet"], color = "textSecondary", count = #later }
    for _, e in ipairs(later) do
      local it = QuestItem(e, { goal = true })
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
    items[#items + 1] = { kind = "head", h = HEAD_H, text = L["Done"], color = "good", count = done }
    for _, e in ipairs(entries) do
      if e.group == "done" then items[#items + 1] = QuestItem(e) end
    end
  end
  items[#items + 1] = { kind = "dpath", h = 24, legend = true,
    text = L["Colours: %s done, %s in your log, %s to take, %s not yet."]:format(Colorize(L["green"], "good"),
      Colorize(L["yellow"], "warning"), Colorize(L["blue"], "accent"), Colorize(L["grey"], "textHint")) }
  return items
end

-- The dungeons to choose, (1.3.5, Daniel 10.10.) in groups by your level: "Your level (n)" (inside the
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
    table.insert(groups[key], { kind = "dpick", h = 40, inst = inst, text = ns.DungeonName(inst), minL = lo, ready = ready,
      fitText = RangeOf(inst), fitColor = quiet and "textHint" or (fit == "later" and "critical" or "good"), selected = inst == sel,
      quiet = quiet, done = allDone, sub = sub, group = key, fit = fit, toGo = n, total = #entries, doneCount = done,
      onClick = function() dunSel = inst UI.dunView = "pre" Refresh(true) end }) -- (draft 4) its card: the prerequisites
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
  ns.Print(L["Route %s: %s"]:format(ns.Fraction(route.i, #route.ids), ns.QuestTitle(id)))
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
-- Frames (02.11.2026, draft 4): the window, its pages and the focus card
---------------------------------------------------------------------------
UI.DETAIL_MIN, UI.DETAIL_MAX = 320, 380
UI.JMAP = 52 -- the journal's round map in the first tile
UI.DUN_BAR_H = 48

-- (02.11.2026) the window's place and size in ns.db.questBook; the old place (ns.db.questBookPos) moves over once
function UI.Store()
  local st = type(ns.db.questBook) == "table" and ns.db.questBook or {}
  ns.db.questBook = st
  local old = ns.db.questBookPos
  if type(old) == "table" and type(old[1]) == "string" and not st.point then
    st.point, st.relPoint, st.x, st.y = old[1], old[2] or old[1], tonumber(old[3]) or 0, tonumber(old[4]) or 0
  end
  ns.db.questBookPos = nil
  return st
end

function UI.DetailOpen() return UI.detailID ~= nil or UI.detailEntry ~= nil end

-- Zones: the zone list on the left (an icon rail under 800 px), the hero with the zone's map, the chips, the quests.
function UI.CreateZonePage(page)
  P.side = Kit.Sidebar(page, { search = L["Find a zone"], kinds = UI.KINDS,
    onSearch = function(text) zoneQuery = text Refresh() end })
  P.side:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  P.zoneBox = P.side.search
  lists.zones = P.side.list
  P.zoneMain = CreateFrame("Frame", nil, page)
  P.hero = Kit.Hero(P.zoneMain, { height = HERO_H, column = 150 })
  P.hero:SetPoint("TOPLEFT", P.zoneMain, "TOPLEFT", 0, 0)
  P.hero.art.tiles = {}
  -- the segments (quests of the zone or your journal there, back to your zone) and the filters with their counts
  P.seg = Kit.ChipBar(P.zoneMain, { onChange = function(key)
    if key == "here" then SelectZone(nil) return end
    zoneSeg = key
    Refresh(true)
  end })
  P.seg:Add("quests", L["Quests"])
  P.seg:Add("journal", L["Your journal here"])
  P.seg:Add("here", L["Back to my zone"])
  P.zChips = Kit.ChipBar(P.zoneMain, { onChange = function(key)
    if key == "near" then zNear = not zNear else zFilter = key end
    Refresh(true)
  end })
  for _, key in ipairs({ "all", "log", "available", "later", "done" }) do
    P.zChips:Add(key, L[key == "all" and "All" or ns.ZONE_GROUP_TITLE[key]])
  end
  P.zChips:Add("near", L["Nearest first"])
  lists.zone = Kit.List(P.zoneMain, { kinds = UI.KINDS })
end

-- the two chip bars on one line: the segments as wide as they need (at most half), the filters scroll in the rest
function UI.ZoneChips()
  local mw = UI.zoneW or 600
  local y = HERO_H + KS.gap
  local segW = math.min(P.seg:ContentWidth(), math.floor(mw * 0.5))
  P.seg:ClearAllPoints()
  P.seg:SetPoint("TOPLEFT", P.zoneMain, "TOPLEFT", KS.gap, -y)
  P.seg:Layout(math.max(1, segW))
  P.zChips:ClearAllPoints()
  P.zChips:SetPoint("TOPLEFT", P.zoneMain, "TOPLEFT", segW + 3 * KS.gap, -y)
  P.zChips:Layout(math.max(1, mw - segW - 4 * KS.gap))
end

function UI.LayoutZone(w, h, mode)
  P.side:Layout(h, mode == "rail")
  local sw = P.side:Width()
  local mw = w - sw
  UI.zoneW = mw
  P.zoneMain:ClearAllPoints()
  P.zoneMain:SetPoint("TOPLEFT", P.pages.zone, "TOPLEFT", sw, 0)
  P.zoneMain:SetSize(mw, h)
  P.hero:Layout(mw)
  UI.ZoneChips()
  local y = HERO_H + KS.gap + KS.chip + KS.gap
  lists.zone:ClearAllPoints()
  lists.zone:SetPoint("TOPLEFT", P.zoneMain, "TOPLEFT", 0, -y)
  lists.zone:Resize(mw, math.max(1, h - y))
  if UI.heroMap then UI.HeroArt(UI.heroMap) end
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

-- (1.3.12) the map art of a zone for the postcard (Postcard.lua): client tiles, else the classic files
ns.MapArt = function(m)
  local a, b, c, d, e = ArtFromClient(m)
  if a then return a, b, c, d, e end
  return ArtFromFiles(m)
end

-- (1.3.4) Draws the map of a zone into a frame: the banner of the zone tab
-- (full width, middle stripe) and the round map of the journal (covers the
-- square, a circle mask on every piece).
local function DrawMapArt(hero, m, width, HEIGHT, mask)
  for _, t in ipairs(hero.tiles) do t:Hide() end
  hero.artMap = m
  hero.geo = nil
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
  hero.geo = { lw = lw, lh = lh, scale = scale, sx = shiftX, sy = shift, w = width, h = HEIGHT } -- (1.3.11) spots on it
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

-- The zone's map behind the hero (full width, middle stripe); again when the zone or the width changes
function UI.HeroArt(m)
  UI.heroMap = m
  local a = P.hero and P.hero.art
  if not a then return end
  local w = math.floor(tonumber(P.hero._w) or 0)
  if w <= 1 then w = 756 end
  if m == a.artMap and w == a.artW then return end
  a.artW = w
  if not DrawMapArt(a, m, w, HERO_H) then a.artMap = m end
end

-- Journal: four tiles (today with the round map of your zone, experience with the last seven days, money, the level),
-- the filters, the time line; the footer counts and copies.
function UI.CreateJournalPage(page)
  P.tiles = {
    Kit.Tile(page, { art = UI.JMAP, onClick = function() if P.jmap and P.jmap.m then SelectZone(P.jmap.m) end end }),
    Kit.Tile(page, { side = 64 }),
    Kit.Tile(page),
    Kit.Tile(page),
  }
  P.tiles[1]._tipFn = function(t)
    local m = P.jmap and P.jmap.m
    if not m then return nil end
    local lines = {} -- the tile's cut texts whole
    for _, fs in ipairs(t._cutTexts or {}) do lines[#lines + 1] = Kit.FullText(fs) end
    return MapName(m) or L["Map %d"]:format(m), lines, L["Click: show this zone"]
  end
  P.cols = Kit.Columns(P.tiles[2].side, 7)
  P.cols:SetPoint("BOTTOMLEFT", P.tiles[2].side, "BOTTOMLEFT", 0, 0)
  -- (1.3.4) the map of your zone, round, in a gold ring
  local D = UI.JMAP
  local jm = CreateFrame("Frame", nil, P.tiles[1].art)
  jm:SetSize(D, D)
  jm:SetPoint("CENTER", P.tiles[1].art, "CENTER", 0, 0)
  jm.ringTex = jm:CreateTexture(nil, "BACKGROUND", nil, 0)
  jm.ringTex:SetSize(D + 4, D + 4)
  jm.ringTex:SetPoint("CENTER", jm, "CENTER", 0, 0)
  jm.ringTex:SetTexture(CIRCLE)
  Kit.SetColor(jm.ringTex, KC.gold)
  jm.base = jm:CreateTexture(nil, "BACKGROUND", nil, 1)
  jm.base:SetAllPoints(jm)
  jm.base:SetTexture(CIRCLE)
  Kit.SetColor(jm.base, KC.input)
  jm.tiles = {}
  if jm.CreateMaskTexture then
    local ok, mask = pcall(jm.CreateMaskTexture, jm)
    if ok and mask then
      pcall(mask.SetTexture, mask, CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(jm)
      jm.mask = mask
    end
  end
  jm.ringF = CreateFrame("Frame", nil, jm)
  jm.ringF:SetAllPoints(jm)
  P.jmap = jm
  P.jchips = Kit.ChipBar(page, { onChange = function(key) jfilter = key Refresh(true) end })
  for _, key in ipairs(FILTERS) do P.jchips:Add(key, L[FILTER_TITLE[key]]) end
  P.chips = P.jchips.chips
  lists.journal = Kit.List(page, { kinds = UI.KINDS })
end

function UI.LayoutJournal(w, h)
  local each = math.floor((w - 5 * KS.gap) / 4)
  for i, t in ipairs(P.tiles) do
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", P.pages.journal, "TOPLEFT", KS.gap + (i - 1) * (each + KS.gap), -KS.gap)
    t:Layout(each)
  end
  P.cols:Layout(P.tiles[2].sideW, 30)
  local y = KS.gap + 72 + KS.gap
  P.jchips:ClearAllPoints()
  P.jchips:SetPoint("TOPLEFT", P.pages.journal, "TOPLEFT", KS.gap, -y)
  P.jchips:Layout(math.max(1, w - 2 * KS.gap))
  y = y + KS.chip + KS.gap
  lists.journal:ClearAllPoints()
  lists.journal:SetPoint("TOPLEFT", P.pages.journal, "TOPLEFT", 0, -y)
  lists.journal:Resize(w, math.max(1, h - y))
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
  local values, labels, byKey = {}, {}, {}
  for i = 1, now and 7 or 0 do
    local ts = now - (7 - i) * 86400
    byKey[Fmt.DayKey(ts)] = i
    values[i], labels[i] = 0, Fmt.DayTitle(ts)
  end
  for _, e in ipairs(j and j.e or {}) do
    if e.k == "c" and e.t then
      local i = byKey[Fmt.DayKey(e.t)]
      if i then values[i] = values[i] + (ns.Num(e.x) or 0) end
    end
  end
  local t = P.tiles
  local here = HereZone()
  t[1]:SetData(L["Today"], q .. " " .. L["quests"], here and MapName(here) or "")
  t[2]:SetData(L["Experience today"], xp > 0 and ("+" .. Style.Number(xp)) or "0", L["Last 7 days"], xp > 0 and KC.txGold or nil)
  P.cols:SetValues(values, labels)
  t[3]:SetData(L["Money today"], Coins(money, 16) or "0", "")
  local level = ns.PlayerLevel() or 0
  local cur, max = ns.Num(ns.Value(UnitXP, "player")) or 0, ns.Num(ns.Value(UnitXPMax, "player")) or 0
  -- (Stufe 3) played time on this level when Questdon's clock knows it, else the time since the level-up
  local nowT = Fmt.Now()
  local playedS, playedExact = ns.JournalLevelPlayed()
  local since = (playedS and J3.Played(playedS, playedExact)) or (lastLevel and nowT and Fmt.Span(nowT - lastLevel))
  local frac = max > 0 and math.max(0, math.min(1, cur / max)) or nil
  t[4]:SetData(L["Level %d to %d"]:format(level, level + 1), frac and ("%d %%"):format(math.floor(frac * 100)) or "-",
    since and L["%s on this level"]:format(since) or "")
  t[4]:SetProgress(frac, "blue")
end

-- The journal's round map: the zone you are in. (1.3.11) A clicked moment
-- (P.jpick) shows its zone with a gold dot on the spot instead.
local function UpdateJournalMap()
  local jm = P.jmap
  if not jm then return end
  local pick = P.jpick
  local m = pick and pick.m or HereZone()
  jm.m = m
  if m ~= jm.artMap then
    if not DrawMapArt(jm, m, UI.JMAP, UI.JMAP, jm.mask) then jm.artMap = m end
  end
  if not jm.pinOut then
    jm.pinOut = jm.ringF:CreateTexture(nil, "OVERLAY")
    jm.pinOut:SetSize(9, 9)
    jm.pinOut:SetTexture(CIRCLE)
    Kit.SetColor(jm.pinOut, KC.outer)
    jm.pinIn = jm.ringF:CreateTexture(nil, "OVERLAY", nil, 2)
    jm.pinIn:SetSize(5, 5)
    jm.pinIn:SetTexture(CIRCLE)
    Kit.SetColor(jm.pinIn, KC.goldBright)
  end
  local g = jm.geo
  local shown = false
  if pick and g and m == jm.artMap then
    local X = pick.x * g.lw * g.scale - g.sx
    local Y = pick.y * g.lh * g.scale - g.sy
    local r = g.w / 2
    if (X - r) ^ 2 + (Y - r) ^ 2 <= (r - 4) ^ 2 then
      for _, tx in ipairs({ jm.pinOut, jm.pinIn }) do
        tx:ClearAllPoints()
        tx:SetPoint("CENTER", jm, "TOPLEFT", X, -Y)
        tx:Show()
      end
      shown = true
    end
  end
  if not shown then jm.pinOut:Hide() jm.pinIn:Hide() end
  jm.pinShown = shown -- (tests)
end

-- Search: the box, a reset, the list.
function UI.CreateSearchPage(page)
  P.searchBox = Kit.SearchBox(page, { placeholder = L["Search quest, zone, level or ID"],
    onChange = function(text) UI.Later("search", function() query = text Refresh(true) end) end })
  P.searchBox:SetPoint("TOPLEFT", page, "TOPLEFT", KS.gap, -KS.gap)
  P.searchReset = Kit.Button(page, L["Reset"], { onClick = function()
    query = ""
    P.searchBox:SetText("")
    if ns.JournalSearchReset then ns.JournalSearchReset() end
    Refresh(true)
  end })
  P.searchReset:SetPoint("TOPRIGHT", page, "TOPRIGHT", -KS.gap, -KS.gap)
  lists.search = Kit.List(page, { kinds = UI.KINDS })
end

function UI.LayoutSearch(w, h)
  local rw = math.min(P.searchReset.natural or 96, 140)
  P.searchReset:Layout(rw)
  P.searchBox:Layout(math.max(80, w - 3 * KS.gap - rw))
  local y = KS.gap + KS.button + KS.gap
  lists.search:ClearAllPoints()
  lists.search:SetPoint("TOPLEFT", P.pages.search, "TOPLEFT", 0, -y)
  lists.search:Resize(w, math.max(1, h - y))
end

-- Dungeons: (draft 4) every dungeon as an index card in a grid; a click on "Prerequisites" shows that dungeon's quests
-- and what each needs first (the list of 1.3.5) under a head with the way back, the entrance mark, the map and the route.
local UpdateDungeonBar -- (1.3.5) the mark button updates the head
function UI.CreateDungeonPage(page)
  lists.dungrid = Kit.List(page, { kinds = UI.KINDS })
  local bar = CreateFrame("Frame", nil, page)
  bar:SetHeight(UI.DUN_BAR_H)
  Kit.Fill(bar, KC.card)
  bar.lineB = Kit.Tex(bar, "ARTWORK", KC.divider)
  bar.lineB:SetPoint("BOTTOMLEFT") bar.lineB:SetPoint("BOTTOMRIGHT") bar.lineB:SetHeight(1)
  -- back to the cards (and from the cards to the dungeon shown)
  bar.onClick = function() UI.dunView = UI.dunView == "grid" and "pre" or "grid" Refresh(true) end
  bar.back = Kit.IconButton(bar, "back", { tooltip = L["Choose a dungeon"], onClick = function() bar.onClick(bar) end })
  bar.back:SetPoint("LEFT", bar, "LEFT", KS.pad, 0)
  bar.badge = CreateFrame("Frame", nil, bar)
  bar.badge:SetSize(30, 30)
  bar.badge:SetPoint("LEFT", bar, "LEFT", KS.pad + 24 + KS.gap, 0)
  bar.disc = bar:CreateTexture(nil, "ARTWORK")
  bar.disc:SetSize(30, 30)
  bar.disc:SetPoint("CENTER", bar.badge, "CENTER", 0, 0)
  if bar.disc:SetTexture(CIRCLE) == false then bar.disc:SetTexture(WHITE) end
  bar.level = Kit.Text(bar, "badge", KC.title, "CENTER")
  BadgeParts(bar, bar.disc, 30)
  bar.name = Kit.Text(bar, "title", KC.hero)
  bar.name:SetPoint("TOPLEFT", bar, "TOPLEFT", KS.pad + 24 + KS.gap + 30 + KS.gap, -8)
  bar.sub = Kit.Text(bar, "sub", KC.muted)
  bar.sub:SetPoint("TOPLEFT", bar, "TOPLEFT", KS.pad + 24 + KS.gap + 30 + KS.gap, -27)
  bar._cutTexts = { bar.name, bar.sub }
  Kit.Stateful(bar)
  P.dunBar = bar
  -- (1.3.5, Daniel 10.10.) "Mark entrance": arrow and a pin on the map and the minimap; again: "Remove mark"
  P.dunMark = Kit.Button(bar, L["Mark entrance"], { small = true, onClick = function(self)
    if not self.inst then return end
    ns.ToggleEntranceMark(self.inst)
    UpdateDungeonBar()
  end })
  -- (1.3.5, Daniel 10.10.) "Show on map": the world map on the entrance, its pin pulsing for a moment
  P.dunShow = Kit.Button(bar, L["Show on map"], { small = true, onClick = function(self)
    if self.inst then ns.ShowEntranceOnMap(self.inst) end
  end })
  P.dunShow:SetPoint("LEFT", P.dunMark, "RIGHT", KS.unit, 0)
  P.dunRoute = Kit.Button(bar, "", { small = true, kind = "primary", onClick = function()
    if P.dunRoute.run then ns.SafeCall("quest book", P.dunRoute.run) end
  end })
  P.dunRoute:SetPoint("LEFT", P.dunShow, "RIGHT", KS.unit, 0)
  lists.dungeons = Kit.List(page, { kinds = UI.KINDS })
end

-- the head of the prerequisites: the buttons on the right as wide as they need (together at most 55 % of the width), the
-- name and its line in what is left
function UI.DunBarLayout(w)
  local bar = P.dunBar
  bar:SetWidth(w)
  local btns = { P.dunMark, P.dunShow }
  if P.dunRoute:IsShown() then btns[3] = P.dunRoute end
  local need = 0
  for i, b in ipairs(btns) do need = need + (b.natural or 80) + (i > 1 and KS.unit or 0) end
  local room = math.floor(w * 0.55)
  local scale = need > room and room / need or 1
  local total = 0
  for i, b in ipairs(btns) do
    local bw = math.floor((b.natural or 80) * scale)
    b:Layout(bw)
    total = total + bw + (i > 1 and KS.unit or 0)
  end
  P.dunMark:ClearAllPoints()
  P.dunMark:SetPoint("LEFT", bar, "LEFT", w - KS.pad - total, 0)
  local tx = KS.pad + 24 + KS.gap + 30 + KS.gap
  local textW = math.max(20, w - KS.pad - total - KS.gap - tx)
  Kit.Fit(bar.name, textW)
  Kit.Fit(bar.sub, textW)
end

function UI.LayoutDungeons(w, h)
  local grid = UI.dunView == "grid"
  UI.Shown(lists.dungrid, grid)
  UI.Shown(P.dunBar, not grid)
  UI.Shown(lists.dungeons, not grid)
  lists.dungrid:ClearAllPoints()
  lists.dungrid:SetPoint("TOPLEFT", P.pages.dungeons, "TOPLEFT", 0, -KS.gap)
  lists.dungrid:Resize(w, math.max(1, h - KS.gap))
  P.dunBar:ClearAllPoints()
  P.dunBar:SetPoint("TOPLEFT", P.pages.dungeons, "TOPLEFT", 0, 0)
  UI.DunBarLayout(w)
  lists.dungeons:ClearAllPoints()
  lists.dungeons:SetPoint("TOPLEFT", P.pages.dungeons, "TOPLEFT", 0, -UI.DUN_BAR_H)
  lists.dungeons:Resize(w, math.max(1, h - UI.DUN_BAR_H))
end

-- the head and the route button for the dungeon shown
function UpdateDungeonBar()
  local bar = P.dunBar
  if not bar then return end
  local inst = ns.QuestBookSelectedDungeon()
  if not inst then bar.inst = nil P.dunRoute:Hide() return end
  local minL = ns.DungeonLevelRange(inst)
  local entries = {}
  for _, id in ipairs(ns.DungeonQuestIDs(inst)) do entries[#entries + 1] = id end
  -- (1.3.5) name; the range, how many of your quests are done, how it fits you; the zone of the entrance
  local fitText, fitColor = FitOf(inst)
  UI.SetBadge(bar, inst, minL and tostring(minL) or "?", fitColor)
  bar.name:SetText(Kit.Upper(ns.DungeonName(inst) or "?"))
  local mine, done = DungeonEntries(inst)
  local zone = ns.DungeonEntrance and select(1, ns.DungeonEntrance(inst))
  local zname = zone and MapName(ZoneOf(zone) or zone)
  local parts = {}
  if RangeOf(inst) then parts[#parts + 1] = RangeOf(inst) end
  parts[#parts + 1] = L["%d of %d quests done"]:format(done, #mine)
  if fitText then parts[#parts + 1] = Colorize(fitText, fitColor or "textHint") end
  if zname then parts[#parts + 1] = zname end
  bar.sub:SetText(table.concat(parts, "  ·  "))
  bar.inst, bar.rangeText, bar.doneText = inst, RangeOf(inst), L["%d of %d quests done"]:format(done, #mine)
  -- (1.3.5) the entrance mark of this dungeon: set, remove, or nothing known
  local known = ns.DungeonEntrance(inst) ~= nil
  local mk = P.dunMark
  local m = ns.EntranceMark and ns.EntranceMark()
  local on = m ~= nil and m.inst == inst
  mk.inst = inst
  mk:SetText(on and L["Remove mark"] or L["Mark entrance"])
  mk:SetSelected(on)
  mk:SetDisabled(not known)
  if known then
    mk.tipTitle = on and L["Remove mark"] or L["Mark entrance"]
    mk.tipLines = { L["The arrow points to the entrance, and a mark stands on the world map and the minimap. It goes away when you get there, after 30 minutes, or with a right-click on it."] }
  else
    mk.tipTitle, mk.tipLines = L["Mark entrance"], { L["No entrance known for this dungeon."] }
  end
  mk:SetTooltip(mk.tipTitle, mk.tipLines)
  local sh = P.dunShow
  sh.inst = inst
  sh:SetText(L["Show on map"])
  sh:SetDisabled(not known)
  sh.tipTitle = L["Show on map"]
  sh.tipLines = { known and L["Opens the world map at the entrance and lets its pin pulse for a moment."] or L["No entrance known for this dungeon."] }
  sh:SetTooltip(sh.tipTitle, sh.tipLines)
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
    P.dunRoute:SetText(L["Route: pick up %d"]:format(#pickIDs))
    P.dunRoute.run = function() ns.QuestBookRoute(pickIDs) end
    P.dunRoute:Show()
  else
    P.dunRoute.run = nil
    P.dunRoute:Hide()
  end
  UI.DunBarLayout(UI.cw or 976)
end

-- (02.11.2026) an index card of a dungeon: picture or level, name, "Level 17-26 · Zone", a ring with the quests ready
-- (all done: done), a line how it fits you, the entrance mark and its prerequisites
function UI.CardArt(card, d)
  UI.Badge(card.art, 30)
  UI.SetBadge(card.art, d.inst, d.minL and tostring(d.minL) or "?", d.fitColor, d.quiet)
end
function UI.CardData(c)
  local inst = c.inst
  local known = ns.DungeonEntrance(inst) ~= nil
  local mark = ns.EntranceMark and ns.EntranceMark()
  local on = mark ~= nil and mark.inst == inst
  local zone = ns.DungeonEntrance and select(1, ns.DungeonEntrance(inst))
  local zname = zone and MapName(ZoneOf(zone) or zone)
  local sub = c.fitText or ""
  if zname then sub = sub ~= "" and (sub .. "  ·  " .. zname) or zname end
  local markText = on and L["Remove mark"] or L["Mark entrance"]
  return { inst = inst, minL = c.minL, quiet = c.quiet, fitColor = c.fitColor, title = c.text, sub = sub,
    ring = { c.done and c.total or (c.ready or 0), c.total or 0 }, status = c.sub, statusColor = c.done and "green" or UI.FIT[c.fitColor] or "grey",
    selected = c.selected, art = UI.CardArt,
    buttons = {
      { text = markText, disabled = not known, onClick = function() ns.ToggleEntranceMark(inst) Refresh() end,
        tooltip = { markText, { known and L["The arrow points to the entrance, and a mark stands on the world map and the minimap. It goes away when you get there, after 30 minutes, or with a right-click on it."] or L["No entrance known for this dungeon."] } } },
      { text = L["Prerequisites (%s)"]:format(ns.Fraction(c.ready or 0, c.total or 0)), kind = "primary", onClick = c.onClick },
    } }
end
-- the grid: the groups of the choices (your level, coming up, below, all done) as heads, the cards in rows
function UI.GridItems(cols)
  local items, row = {}, nil
  for _, c in ipairs(ns.QuestBookDungeonChoices()) do
    if c.kind == "head" then
      items[#items + 1] = { kind = "head", h = HEAD_H, text = c.text, count = c.count, color = c.color }
      row = nil
    else
      if not row or #row.cards >= cols then
        row = { kind = "cards", cols = cols, cards = {} }
        items[#items + 1] = row
      end
      row.cards[#row.cards + 1] = UI.CardData(c)
    end
  end
  if #items == 0 then items[1] = { kind = "empty", h = 60, text = L["No dungeon quests known for you."] } end
  return items
end

---------------------------------------------------------------------------
-- (1.3.4) Detail card: everything about the clicked quest at one glance.
-- (02.11.2026) Kit.Detail: docked on the right at full width, over the list under 960 px.
---------------------------------------------------------------------------
local function ObjectiveTexts(id)
  local out = {}
  if ns.InQuestLog(id) then
    local list = ns.ClientObjectives(id) or {}
    for _, o in ipairs(list.game or list) do -- (23.10.) in the game's order
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
  for i = 1, math.min(2, #order) do names[#names + 1] = MapName(order[i]) or L["Map %d"]:format(order[i]) end
  return L["Where: %s"]:format(table.concat(names, ", "))
end

local function Where(m, x, y)
  if not m then return nil end
  local name = MapName(m) or L["Map %d"]:format(m)
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
  -- (30.10.2026, Daniel's picture: German client, the objective sentence in English) our data's English sentence only
  -- in an English client; the game's own objectives follow below
  local loc = ns.Value(GetLocale)
  local english = loc ~= "enUS" and loc ~= "enGB" and ns.LooksEnglish and qt and ns.LooksEnglish(qt.o)
  if qt and type(qt.o) == "string" and qt.o ~= "" and not english then todo[1] = { qt.o, "textPrimary" } end
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
  -- chain: (30.10.2026, L3Hummus) a diagram (Chain.lua) where the quest has a chain of 2 parts or more
  local chain = {}
  local graph = ns.ChainGraph and ns.ChainGraph(id)
  if graph then
    d.sections[#d.sections + 1] = { title = L["Chain"], chain = id,
      lines = { { L["Part %d of %d"]:format(graph.layerOf[id], #graph.layers), "textPrimary" } } }
    chain = nil
  end
  for _, pre in ipairs(chain and ns.QuestPrereqs(id) or {}) do
    local done = ns.IsQuestDone(pre)
    chain[#chain + 1] = { L["Before: %s"]:format(ns.QuestTitleWithPart(pre)), done and "good" or "warning" }
  end
  for _, nx in ipairs(chain and ns.FollowUpQuests(id) or {}) do
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

-- the card's buttons: Arrow, World map and (with Leveldon) Report; pane.arrow / .map / .report name them, a button not
-- shown names a hidden one
UI.ACTION = {
  arrow = { text = L["Arrow"], onClick = function()
    if UI.detailEntry then EntryToMap(UI.detailEntry, false) elseif UI.detailID then ns.FocusQuest(UI.detailID, false) end
  end },
  map = { text = L["World map"], onClick = function()
    if UI.detailEntry then EntryToMap(UI.detailEntry, true) elseif UI.detailID then ns.FocusQuest(UI.detailID, true) end
  end },
  -- (1.3.6, Daniel 11.10.) with Leveldon: report this quest (quest giver not there, route, a remark)
  report = { text = L["Report"], onClick = function()
    local api = rawget(_G, "LeveldonAPI")
    if UI.detailID and type(api) == "table" and type(api.Report) == "function" then
      api.Report({ quest = UI.detailID, title = ns.QuestTitle(UI.detailID) })
    end
  end },
}
function UI.Actions(keys)
  local d = P.detail
  local spec, used = {}, {}
  for i, k in ipairs(keys) do spec[i] = UI.ACTION[k] used[k] = true end
  d:SetActions(spec)
  for i, k in ipairs(keys) do d[k] = d.actions[i] end
  local spare = #keys
  for _, k in ipairs({ "arrow", "map", "report" }) do
    if not used[k] then spare = spare + 1 d[k] = d.actions[spare] end
  end
end

function UI.CreateDetail()
  local d = Kit.Detail(book.body, { onClose = function() ns.QuestBookShowQuest(nil) end })
  d:Hide()
  if d.SetFrameLevel and book.body.GetFrameLevel then pcall(d.SetFrameLevel, d, (tonumber(book.body:GetFrameLevel()) or 1) + 30) end
  P.detail = d
  UI.Actions({ "arrow", "map", "report" }) -- all three made once
  d.photo = Pic.Button(d) -- (1.3.11) a screenshot's picture, as wide as the card
  -- (1.3.11) a journal entry: the player's note, saved while typing
  d.noteBox = Kit.SearchBox(d, { placeholder = L["Write a note for this entry"], onChange = function(text)
    UI.Later("note", function()
      if d.noteFor then
        ns.JournalSetNote(d.noteFor, text)
        if Refresh then Refresh(false) end
      end
    end)
  end })
  pcall(d.noteBox.SetMaxLetters, d.noteBox, ns.JOURNAL_NOTE_LETTERS or 200)
  d.noteBox:Hide()
  -- the chain of the quest as a path (Chain.lua); a click on a box that sums up parts shows the whole chain
  P.chainPath = ns.ChainPath and ns.ChainPath(d)
  if P.chainPath then
    P.chainPath.frame:Hide()
    P.chainPath.summaryHint = L["Click: show the whole chain."]
    -- (02.11.2026, Daniel: "man kann nicht mehr auf 4 klicken um zurück zu kommen") the boxes before and after page through
    -- the chain; another quest in the card starts at its own part again
    P.chainPath.onSummary = function(box)
      local id = UI.detailID
      if UI.CH.fullFor ~= id then UI.CH.shift = 0 end
      UI.CH.shift, UI.CH.fullFor = (UI.CH.shift or 0) + ((box and box.dir) or 0), id
      UI.RenderDetail()
    end
  end
end

-- the width inside the card (Kit.Detail's lines)
function UI.DetailInner() return math.max(40, (tonumber(P.detail and P.detail._w) or 320) - 2 * KS.pad - 6) end

-- a line of a section: "Kobold Vermin slain: 3/8" as a progress bar, a long sentence as a paragraph
function UI.DetailLine(d, line)
  local text, color = tostring(line[1] or ""), UI.Tone(line[2]) or "body"
  local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)$")
  if name and tonumber(need) and tonumber(need) > 0 then
    have, need = tonumber(have), tonumber(need)
    d:Progress(name, have, need, have >= need)
  elseif #Plain(text) > 70 and not text:find("^%- ") then
    d:Para(text, color)
  else
    d:Line(text, color)
  end
end

-- yards to where the quest starts, nil when unknown
function UI.Yards(id)
  if not (ns.PlayerWorld and ns.DistanceFrom) then return nil end
  local ok, d = pcall(function()
    local m, x, y = ns.QuestStart(id)
    if not (m and x and y) then return nil end
    local pc, pn, pw = ns.PlayerWorld()
    if not (pc and pn) then return nil end
    return ns.DistanceFrom(pc, pn, pw, { mapID = m, x = x / 100, y = y / 100 })
  end)
  return ok and tonumber(d) and math.floor(d + 0.5) or nil
end

UI.CH = { shift = 0, fullFor = nil } -- (02.11.2026) how far the chain in the card was paged (boxes before / after)
function UI.RenderDetail()
  local d = P.detail
  if not d then return end
  if UI.detailEntry then return UI.RenderEntryDetail() end
  if not UI.detailID then
    if ns.PostcardHide then ns.PostcardHide(d) end
    Pic.Set(d.photo, nil)
    d.noteBox:Hide()
    d:Hide()
    return
  end
  local id = UI.detailID
  local q = ns.QuestBookDetail(id)
  local group = ns.ZoneQuestStatus(id)
  local lv = q.level and q.level > 0 and q.level or nil
  local meta = {}
  local yd = UI.Yards(id)
  if yd then meta[#meta + 1] = L["%d yards"]:format(yd) end
  if not (group == "log" and q.pillColor == "good") then meta[#meta + 1] = q.pill end
  d:SetHead({ level = lv or "?", levelStatus = not lv and "trivial" or nil, title = q.title or "",
    meta = table.concat(meta, "  ·  "), pill = (group == "log" and q.pillColor == "good") and { q.pill, "ready" } or nil })
  local api = rawget(_G, "LeveldonAPI")
  UI.Actions((type(api) == "table" and type(api.Report) == "function") and { "arrow", "map", "report" } or { "arrow", "map" })
  if ns.PostcardHide then ns.PostcardHide(d) end
  Pic.Set(d.photo, nil)
  d.noteBox:Hide()
  d.noteFor = nil
  d:Begin()
  for _, sec in ipairs(q.sections) do
    if sec.chain and P.chainPath then
      d:Section(sec.title, sec.lines[1] and sec.lines[1][1])
      local h = ns.ChainPathDraw(P.chainPath, sec.chain, UI.DetailInner(), { shift = UI.CH.fullFor == sec.chain and UI.CH.shift or 0 })
      if h > 0 then d:Block(P.chainPath.frame, h) end
    else
      d:Section(sec.title)
      for _, line in ipairs(sec.lines) do UI.DetailLine(d, line) end
    end
  end
  d:End()
  d:Show()
end

-- (1.3.11) A journal entry in the card: what, when and where, what the moment
-- knows, and the player's note (saved while typing).
function UI.RenderEntryDetail()
  local d, e = P.detail, UI.detailEntry
  local title = Fmt.EntryTitle(e)
  if e.k == "r" and QUALITY_HEX[e.iq] then title = "|c" .. QUALITY_HEX[e.iq] .. title .. "|r" end
  local kind = e.k == "l" and "level-up" or (Fmt.KIND_TEXT[e.k] or "done earlier")
  d:SetHead({ icon = EntryIcon(e), title = title, meta = Colorize(L[kind], Fmt.KIND_COLOR[e.k] or "textHint") })
  local where = (e.pm or e.m) and e.px and e.py
  local quest = e.q and not MOMENT[e.k]
  local acts = {}
  if where or quest then acts[#acts + 1] = "arrow" end
  if where or quest or e.m then acts[#acts + 1] = "map" end
  UI.Actions(acts)
  d:Begin()
  -- (1.3.11) the screenshot's picture, as wide as the card; (1.3.12) without one the postcard (map, character, target,
  -- time of day)
  local w = UI.DetailInner()
  local ph = math.floor(w * 9 / 16 + 0.5)
  local shot = e.k == "s" and ns.AlbumShotFor and ns.AlbumShotFor(e) or nil
  if shot then
    Pic.Set(d.photo, shot, w, ph)
    d:Block(d.photo, ph)
  else
    Pic.Set(d.photo, nil)
  end
  if e.k == "s" and not shot and ns.PostcardFor then
    local card = ns.PostcardFor(d)
    ns.PostcardShow(card, e, w, ph)
    d:Block(card, ph)
  elseif ns.PostcardHide then
    ns.PostcardHide(d)
  end
  d:Section(L["When and where"])
  if e.t then d:Line(L["Date"], "muted", Fmt.DayTitle(e.t) .. "  " .. Fmt.Clock(e.t), "body") end
  local zone = e.m and MapName(e.m)
  if zone then d:Line(L["Zone"], "muted", zone, "body") end
  if e.l and e.k ~= "l" then d:Line(L["Your level"], "muted", tostring(e.l), "body") end
  if e.k == "c" and e.x then d:Line(L["Experience"], "muted", "+" .. Style.Number(e.x), "txGold") end
  local story = ns.JournalStory and ns.JournalStory(e) -- (1.3.12) what the quest giver told at the turn-in
  if story then
    d:Section(L["Story"])
    d:Para(story, "muted")
  end
  if MOMENT[e.k] then
    local more = Fmt.MomentLines(e, {})
    if #more > 0 then
      d:Section(L["Moment"])
      for _, l in ipairs(more) do d:Line(l[1], "muted", l[2], UI.Tone(l[3]) or "body") end
    end
  end
  d:Section(L["Your note"])
  d:Block(d.noteBox, KS.button)
  if d.noteFor ~= e then
    d.noteFor = e
    d.noteBox:SetText(e.note or "")
  end
  d:End()
  d:Show()
end

-- Place everything for the width of the window: the open tab's page (narrower while the card is docked on the right),
-- the card docked or over the list.
function UI.Place()
  if not P.pages then return end
  local w, h, mode = UI.w, UI.h, UI.mode
  local full = mode == "full"
  local open = UI.DetailOpen()
  local dw = math.max(UI.DETAIL_MIN, math.min(UI.DETAIL_MAX, math.floor(w * 0.36)))
  local cw = (full and open) and (w - dw) or w
  UI.cw = cw
  for _, page in pairs(P.pages) do page:SetSize(cw, h) end
  if tab == "zone" then UI.LayoutZone(cw, h, mode)
  elseif tab == "journal" then UI.LayoutJournal(cw, h)
  elseif tab == "dungeons" then UI.LayoutDungeons(cw, h)
  else UI.LayoutSearch(cw, h) end
  local d = P.detail
  d:ClearAllPoints()
  if full then
    d.docked = true
    d:SetPoint("TOPLEFT", book.body, "TOPLEFT", cw, 0)
    d:Layout(dw, h)
  else
    d.docked = false
    local ow = math.min(dw, w - KS.rail - 2 * KS.gap)
    d:SetPoint("TOPRIGHT", book.body, "TOPRIGHT", -KS.gap, -KS.gap)
    d:Layout(ow, h - 2 * KS.gap)
  end
  UI.RenderDetail() -- (closed: hides the card, its postcard and picture)
  -- the grid's columns and the album's tiles follow the width
  local cols = full and 3 or 2 -- (the window 960 px and wider)
  if tab == "dungeons" and cols ~= UI.gridCols and Refresh then UI.gridCols = cols Refresh(false) end
  if tab == "journal" and jfilter == "p" and UI.albumW ~= cw and Refresh then UI.albumW = cw Refresh(false) end
end

-- The footer: on the journal the entries, "Done earlier (n)" and "Copy as text"
function UI.CreateFooter()
  local f = book.footer
  P.footer = f
  P.footText = Kit.Button(f, L["Copy as text"], { small = true, onClick = function() ns.SafeCall("quest book", J3.Export) end,
    tooltip = L["Journal as text"], tooltipLines = { L["What the list shows, as text to copy (Discord, forums)."] } })
  P.footText:SetPoint("RIGHT", f, "RIGHT", -KS.pad - 16, 0)
  P.footOld = Kit.Button(f, "", { small = true, onClick = function()
    local l = lists.journal
    if l and l.items.oldAt then l:ScrollTo(l.items.oldAt, true) end
  end })
  P.footOld:SetPoint("RIGHT", P.footText, "LEFT", -KS.gap, 0)
end

function UI.Footer()
  if not P.footText then return end
  local journal = tab == "journal"
  local room = (UI.w or 976) - 2 * KS.pad - 16
  if journal then
    P.footText:Show()
    room = room - (P.footText.natural or 100) - KS.gap
    local old = UI.oldCount or 0
    if old > 0 then
      P.footOld:SetText(L["Done earlier (%d)"]:format(old))
      P.footOld:Layout(math.min(P.footOld.natural or 120, math.floor(room / 2)))
      P.footOld:Show()
      room = room - (tonumber(P.footOld:GetWidth()) or 120) - KS.gap
    else
      P.footOld:Hide()
    end
    book:SetStatus(UI.footStatus or "")
  else
    -- (02.11.2026, Daniel: "kurze Zahl je Reiter") the other tabs: a short count in the footer
    P.footText:Hide() P.footOld:Hide()
    local text = ""
    if tab == "zone" then
      local m = ShownZone()
      local s = m and ZoneStats(m)
      if s and s.total > 0 then text = L["%d of %d quests done"]:format(s.done, s.total) end
    elseif tab == "dungeons" then
      local inst = UI.dunView == "pre" and ns.QuestBookSelectedDungeon()
      if inst then
        local mine, done = DungeonEntries(inst)
        text = L["%d of %d quests done"]:format(done, #mine)
      else
        local n = 0
        for _, c in ipairs(ns.QuestBookDungeonChoices()) do if c.kind ~= "head" then n = n + 1 end end
        text = L["%d dungeons with quests for you"]:format(n)
      end
    elseif tab == "search" and query and query ~= "" then
      local n = 0
      for _, it in ipairs(lists.search and lists.search.items or {}) do
        if it.kind == "quest" or it.kind == "entry" or it.kind == "zone" then n = n + 1 end
      end
      text = L["%d found"]:format(n)
    end
    book:SetStatus(text)
  end
  if book.status then Kit.Fit(book.status, math.max(20, room)) end
end

local function Create()
  book = Kit.Window("QuestdonQuestBook", { title = "Questdon", subtitle = L["Quest book"], logo = TAB_ICON.zone,
    options = "Questdon", hint = L["/qd opens them too."], footer = true, store = UI.Store(), width = 980, height = 640,
    onLayout = function(_, w, h, mode) UI.w, UI.h, UI.mode = w, h, mode UI.Place() UI.Footer() end,
    onTab = function(key) ns.OpenQuestBook(key) end })
  book:Hide()
  book:SetScript("OnHide", function()
    ns.zoneFocus = nil
    if ns.RefreshPins then ns.RefreshPins() end
  end)
  for _, key in ipairs(TABS) do book:AddTab(key, L[TAB_TITLE[key]]) end
  P.gear = book.gear
  P.pages = {}
  for _, key in ipairs(TABS) do
    local page = CreateFrame("Frame", nil, book.body)
    page:SetPoint("TOPLEFT", book.body, "TOPLEFT", 0, 0)
    page:Hide()
    P.pages[key] = page
  end
  UI.CreateZonePage(P.pages.zone)
  UI.CreateJournalPage(P.pages.journal)
  UI.CreateSearchPage(P.pages.search)
  UI.CreateDungeonPage(P.pages.dungeons)
  UI.CreateDetail()
  UI.CreateFooter()
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
  book:Layout()
end

---------------------------------------------------------------------------
-- Drawing the tabs
---------------------------------------------------------------------------
local function RenderJournal(reset)
  UpdateTiles()
  UpdateJournalMap()
  local items = JournalItems()
  local c = ns.JournalCounts()
  local n = { all = nil, c = c.c, a = c.a, x = c.x + c.f, l = c.l, m = c.m, p = #ns.AlbumShots(), chap = #ns.JournalChapters() }
  for _, chip in ipairs(P.jchips.chips) do
    local label = L[FILTER_TITLE[chip.key]]
    if n[chip.key] and n[chip.key] > 0 then label = label .. "  " .. n[chip.key] end
    chip:SetText(label)
    -- (1.3.11) "Pictures" only with the album (the helper Questdon-Album)
    if chip.key == "p" then if n.p > 0 or jfilter == "p" then chip:Show() else chip:Hide() end end
  end
  P.jchips.active = { [jfilter] = true }
  P.jchips:Paint()
  P.jchips:Place()
  local dated = c.a + c.c + c.x + c.f + c.l + (c.m or 0)
  UI.footStatus = jfilter == "p" and L["%d pictures"]:format(n.p) or L["%d entries"]:format(dated)
  UI.oldCount = items.old or 0
  lists.journal:SetItems(items, reset)
end

local function RenderZone(reset)
  local m = ShownZone()
  local here = HereZone()
  lists.zones:SetItems(ZoneListItems())
  local info = m and ZONE_INFO[m]
  local kick = {}
  if info then kick[#kick + 1] = ContinentName(info.cont) end
  if info and info.min then kick[#kick + 1] = L["Level %s"]:format(RangeText(info)) elseif info then kick[#kick + 1] = L["City"] end
  if m and m == here then kick[#kick + 1] = L["you are here"] end
  local items, s
  if zoneSeg == "journal" then
    items = ZoneJournalItems(m)
    s = m and ZoneStats(m) or { total = 0, done = 0 }
  else
    items, s = ZoneQuestItems(m)
  end
  P.hero:SetData({ kicker = table.concat(kick, "  ·  "), title = m and (MapName(m) or L["Map %d"]:format(m)) or L["Unknown zone"],
    value = ns.Fraction(s.done, s.total), label = L["quests done"], progress = s.total > 0 and s.done / s.total or nil })
  UI.HeroArt(m)
  local jn = 0
  for _, e in ipairs(ns.JournalEntries()) do if e.m and ZoneOf(e.m) == m then jn = jn + 1 end end
  P.seg:Chip("quests"):SetText(L["Quests"] .. "  " .. s.total)
  P.seg:Chip("journal"):SetText(L["Your journal here"] .. "  " .. jn)
  UI.Shown(P.seg:Chip("here"), selZone ~= nil and selZone ~= here)
  P.seg.active = { [zoneSeg] = true }
  P.seg:Paint()
  local gc = s.groups or {}
  for _, c in ipairs(P.zChips.chips) do
    if c.key ~= "near" then
      local n = c.key == "all" and s.total or (gc[c.key] or 0)
      c:SetText(L[c.key == "all" and "All" or ns.ZONE_GROUP_TITLE[c.key]] .. "  " .. n)
    end
  end
  UI.Shown(P.zChips, zoneSeg == "quests")
  P.zChips.active = { [zFilter] = true, near = zNear or nil }
  P.zChips:Paint()
  UI.ZoneChips()
  lists.zone:SetItems(items, reset)
end

local function RenderSearch(reset)
  lists.search:SetItems(SearchItems(), reset)
end

local function RenderDungeons(reset)
  UpdateDungeonBar()
  UI.gridCols = UI.mode == "full" and 3 or 2
  lists.dungrid:SetItems(UI.GridItems(UI.gridCols), reset)
  lists.dungeons:SetItems(DungeonItems(), reset)
  UI.LayoutDungeons(UI.cw, UI.h)
end

function Refresh(reset)
  if not book or not book:IsShown() then return end
  for _, t in ipairs(book.tabs) do t:SetSelected(t.key == tab) end
  for key, page in pairs(P.pages) do if key == tab then page:Show() else page:Hide() end end
  if tab ~= UI.lastTab then reset = true UI.lastTab = tab UI.Place() end
  if tab == "journal" then RenderJournal(reset)
  elseif tab == "zone" then RenderZone(reset)
  elseif tab == "dungeons" then RenderDungeons(reset)
  else RenderSearch(reset) end
  UI.Footer()
  if UI.DetailOpen() then UI.RenderDetail() end
end

---------------------------------------------------------------------------
-- API (the names stay those of 1.2.2: Panel.lua, Core.lua, Journal.lua, ZoneQuests.lua)
---------------------------------------------------------------------------
-- Show a quest in the detail card (nil closes the card). (1.3.5) focus: nil = the card only,
-- "arrow" = also arrow and map mark, "map" = also open the world map there.
function ns.QuestBookShowQuest(id, focus)
  if id and focus then ns.FocusQuest(id, focus == "map") end
  local changed = UI.detailID ~= id or UI.detailEntry ~= nil
  local wasOpen = UI.DetailOpen()
  UI.detailID = id
  UI.detailEntry = nil
  P.jpick = nil
  if P.detail then
    if wasOpen ~= UI.DetailOpen() then UI.Place() else UI.RenderDetail() end
  end
  if changed and not focus and Refresh then Refresh(false) end -- the clicked line stands out
end
function ns.QuestBookDetailID() return UI.detailID end

-- (30.10.2026, Daniel: "mit Shift-Links-Klick die Quest im Quest-Buch im Zonenbereich aufgemacht") the book on the zone
-- of the quest (where it starts, else the zone shown), with the quest's card and its chain
function ns.QuestBookOpenQuest(id)
  id = ns.Num(id)
  if not id then return end
  local m = ns.QuestStart(id)
  local zone = m and (ZoneOf(m) or m)
  if zone then SelectZone(zone) else ns.OpenQuestBook("zone") end
  ns.QuestBookShowQuest(id)
  -- its row in sight
  local list = lists.zone
  for i, it in ipairs(list and list.items or {}) do
    if it.kind == "quest" and it.questID == id then list:ScrollTo(math.max(1, i - 1), true) break end
  end
end
function ns.QuestBookZoneList() return lists.zone end -- (tests)

-- (1.3.11) Show a journal entry in the card (nil closes it); a moment with a
-- spot in its zone also shows that spot on the journal's round map.
function ns.QuestBookShowEntry(e)
  if type(e) ~= "table" then return ns.QuestBookShowQuest(nil) end
  e = type(e.src) == "table" and e.src or e
  local wasOpen = UI.DetailOpen()
  UI.detailEntry, UI.detailID = e, nil
  P.jpick = MOMENT[e.k] and e.m and e.px and e.py and not e.pm and { m = ZoneOf(e.m) or e.m, x = e.px, y = e.py } or nil
  if P.detail then
    if not wasOpen then UI.Place() else UI.RenderDetail() end
  end
  if Refresh then Refresh(false) end
end
function ns.QuestBookDetailEntry() return UI.detailEntry end
function ns.QuestBookMapPick() return P.jpick, P.jmap and P.jmap.pinShown end -- (tests)
function ns.QuestBookDetailPane() return P.detail end -- (tests)

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
  -- (02.11.2026, Daniel: "... oder wenn man oben auf reiter dungeons journal oder search geht") another tab closes the card
  if changed and (UI.detailID ~= nil or UI.detailEntry ~= nil) then
    UI.detailID, UI.detailEntry, P.jpick = nil, nil, nil
    if P.detail then UI.Place() end
  end
  if tab == "search" and changed and ns.JournalSearchReset then ns.JournalSearchReset() end
  if tab == "dungeons" and changed then UI.dunView = "grid" end -- (draft 4) the tab opens on the index cards
  if not book:IsShown() then
    stats = {}
    book:Show()
  end
  Refresh(changed)
  if tab == "search" and changed and P.searchBox and P.searchBox.SetFocus then pcall(P.searchBox.SetFocus, P.searchBox) end
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
-- (02.11.2026, tests) the dungeons tab: "grid" (index cards) or "pre" (the prerequisites of the dungeon shown)
function ns.QuestBookDungeonView(view) if view then UI.dunView = view if Refresh then Refresh(true) end end return UI.dunView end
function ns.QuestBookUI() return UI, P end -- (02.11.2026, tests) the window's state and parts
function ns.QuestBookZone() return ShownZone() end
-- For /qd diag: where the picture of the zone came from.
function ns.QuestBookArt()
  local h = P.hero and P.hero.art
  if not h then return "not built" end
  return ("%s, map %s, %d tiles drawn, %d explored areas, width %s"):format(tostring(h.artSource), tostring(h.artMap), h.artDrawn or 0, h.artExplored or 0, tostring(h.artW))
end
function ns.QuestBookFilter(key) if key then jfilter = key Refresh(true) end return jfilter end
function ns.QuestBookChips() return P.chips end -- (1.3.11, tests)
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
-- For tests and /qd diag: the lines drawn now in a list ("journal", "zone", "zones", "search", "dungeons", "dungrid").
function ns.QuestBookLines(which)
  local l = lists[which or tab]
  local out = {}
  if not l then return out end
  for _, r in ipairs(l:Rows()) do out[#out + 1] = r end
  return out, l
end
-- (Stufe 3, tests) the text of the footer button "Copy as text"
function ns.QuestBookFooterText() return P.footText and P.footText.text:GetText() end
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
