local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- (1.3.6, Daniel 12.10.: "hide Blizzard's quest list as Leveldon does, and a slim version of the
-- Leveldon window for Questdon, with the arrow built in") Our own quest list:
--   * on top the quest you picked, as a card: its objectives (blocks for counts), where to turn
--     it in, and a compass that is the arrow (the separate arrow then draws nothing, Arrow.lua
--     "ghost": it keeps working for the area, the way around and the dots on the map)
--   * below, two ways to list the quest log (title bar button):
--       "near"  finished quests first (to turn in), then the others by distance, each with a
--               small needle and the distance; new quests close by
--       "zones" like Blizzard's list: the log's zone headings, every objective with its count;
--               a second button sorts them by level instead
--   * at the bottom your level, and the XP the finished quests bring as a green part of the bar
-- Click a quest: it becomes the picked one (the game's super track, the compass follows it).
-- Shift-click, or the book button: the whole quest to read (QuestText window below).
-- Blizzard's quest tracker is made invisible and click-through while our list is on (alpha 0,
-- mouse off, no hooks, never in combat), as Leveldon does it.
-- Opacity: the window's background up to fully gone with its frame (options, Shift + mouse wheel
-- over the title bar).
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
local NEEDLE = MEDIA .. "ArrowNeedle"
local NEAR_NEW = 250   -- yards: "new quests close by"
local MAX_OBJ = 4      -- objective lines on the card
local COMPASS = 58
local panel, card
local rows = {}        -- needle rows of the last build: { row = , target = }
local lastSig
local lastShown = 0   -- quests the list showed at the last build (the handle starts from there)
local grip
local MIN_W, MAX_W, ROW, MAX_LINES = 240, 600, 30, 30
local function TrackerWidth() return math.max(MIN_W, math.min(MAX_W, tonumber((ns.db or {}).trackerWidth) or 300)) end
local B = Style.BOOK or {}

local function DB() return ns.db or {} end

-- (1.3.6) a guide (Leveldon) shows the compass in its window, while that window is shown
function ns.GuideActive()
  if not ns.guideCompass then return false end
  local g = ns.guideFrame
  if type(g) == "table" and g.IsShown and not g:IsShown() then return false end
  return true
end

function ns.TrackerOn() return DB().tracker ~= false end
-- the compass in our window (the arrow keeps working for it, Arrow.lua Runs); (1.3.7) also while the list is
-- folded: the card with the compass stays
function ns.TrackerCompassActive()
  local db = DB()
  return not ns.GuideActive() and db.tracker ~= false and db.trackerCompass ~= false and panel ~= nil and panel:IsShown() or false
end

---------------------------------------------------------------------------
-- Blizzard's quest tracker (as in Leveldon 0.1.6)
---------------------------------------------------------------------------
local TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local blizzHidden, blizzMouse
local function BlizzTracker()
  for _, n in ipairs(TRACKERS) do
    local f = rawget(_G, n)
    if type(f) == "table" and type(f.SetAlpha) == "function" then return f end
  end
end
local function ApplyBlizzTracker()
  local f = BlizzTracker()
  if not f then return end
  if ns.True(ns.Value(InCombatLockdown)) then return end
  local db = DB()
  local hide = db.tracker ~= false and db.trackerHideBlizz ~= false and panel ~= nil and panel:IsShown()
  if hide then
    local a = ns.Num(ns.Value(f.GetAlpha, f))
    if blizzHidden ~= f or (a and a > 0) then
      if blizzHidden ~= f then blizzMouse = ns.Value(f.IsMouseEnabled, f) end
      pcall(f.SetAlpha, f, 0)
      if type(f.EnableMouse) == "function" then pcall(f.EnableMouse, f, false) end
      blizzHidden = f
    end
  elseif blizzHidden then
    local h = blizzHidden
    blizzHidden = nil
    pcall(h.SetAlpha, h, 1)
    if type(h.EnableMouse) == "function" then pcall(h.EnableMouse, h, blizzMouse ~= false) end
  end
end
ns.ApplyBlizzTracker = ApplyBlizzTracker
function ns.BlizzTrackerHidden() return blizzHidden ~= nil end -- (tests)

---------------------------------------------------------------------------
-- The quest log with its zone headings, and what we need per quest
---------------------------------------------------------------------------
local function LogWithZones()
  local out, zone = {}, nil
  if not C_QuestLog then return out end
  for i = 1, ns.Num(ns.Value(C_QuestLog.GetNumQuestLogEntries)) or 0 do
    local info = ns.Value(C_QuestLog.GetInfo, i)
    if type(info) == "table" then
      if ns.True(info.isHeader) then
        zone = type(info.title) == "string" and ns.Usable(info.title) and info.title or zone
      elseif not ns.True(info.isHidden) and (ns.Num(info.questID) or 0) > 0 then
        out[#out + 1] = { questID = info.questID, zone = zone, index = i }
      end
    end
  end
  return out
end

local function Objectives(id)
  local out = {}
  for _, o in ipairs(ns.ClientObjectives(id) or {}) do
    if type(o) == "table" and type(o.text) == "string" and ns.Usable(o.text) and o.text ~= "" then
      out[#out + 1] = { text = o.text, done = ns.True(o.finished), have = ns.Num(o.numFulfilled), need = ns.Num(o.numRequired) }
    end
  end
  return out
end

local function TurnInName(id)
  local learned = DB().learned and DB().learned[id]
  if learned and learned.finish and learned.finish.npc then return learned.finish.npc end
  local fin = ns.QUEST_ENDS and ns.QUEST_ENDS[id]
  local name = fin and fin[4] and ns.LocalNpcName and ns.LocalNpcName(fin[4])
  if name then return name end
  local qt = ns.QuestText and ns.QuestText(id)
  return qt and qt.e or nil
end

local function Short(o)
  if not o then return "" end
  return o.text
end

-- one entry per quest: title, level, state, the first open objective, distance and direction target
local function Entries()
  local list = {}
  local pc, pn, pw
  if ns.PlayerWorld then pc, pn, pw = ns.PlayerWorld() end
  for _, e in ipairs(LogWithZones()) do
    local id = e.questID
    e.title = ns.QuestTitle(id)
    e.level = ns.GameQuestLevel(id) or ns.QuestLevel(id)
    e.complete = ns.IsQuestComplete(id) and true or false
    -- (1.3.7, a player on Discord: "how do I remove low level quests from the quest panel?") grey quests go to the
    -- bottom, folded into one line
    e.grey = not e.complete and ns.IsGreyQuestInfo and ns.IsGreyQuestInfo({ questID = id, level = e.level }) and true or false
    e.failed = ns.IsQuestFailed and ns.IsQuestFailed(id) or false
    e.objs = Objectives(id)
    local open
    for _, o in ipairs(e.objs) do if not o.done then open = open or o end end
    e.open = open
    local p = ns.QuestNearestPoint and ns.QuestNearestPoint(id)
    if p and pc then
      e.target = { mapID = p.mapID, x = p.x, y = p.y }
      e.dist = ns.DistanceFrom(pc, pn, pw, e.target)
    end
    list[#list + 1] = e
  end
  return list
end
ns.TrackerEntries = Entries -- (tests)

-- the picked quest: the arrow's quest, else the game's super-tracked quest, else the nearest
local function FocusID(list)
  local t = ns.ArrowTarget and ns.ArrowTarget()
  if type(t) == "table" and t.questID and ns.InQuestLog(t.questID) then return t.questID end
  local id = C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  if id and id > 0 and ns.InQuestLog(id) then return id end
  local best
  for _, e in ipairs(list) do
    if e.dist and (not best or e.dist < best.dist) then best = e end
  end
  return best and best.questID or (list[1] and list[1].questID)
end
ns.TrackerFocusID = function() return FocusID(Entries()) end -- (tests)

local function Pick(id)
  if not id then return end
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, id) end
  if ns.ClearArrow then ns.ClearArrow() end
  if ns.UpdateArrowTarget then ns.UpdateArrowTarget() end
  lastSig = nil
  if ns.QueueRefresh then ns.QueueRefresh("tracker") end
end
ns.TrackerPick = Pick

local function Yards(d)
  if not d then return "" end
  return L["%d yards"]:format(math.floor(d + 0.5))
end

---------------------------------------------------------------------------
-- The card on top: title, objectives with blocks, turn-in, compass
---------------------------------------------------------------------------
local function Font(parent, size, color, justify)
  local fs = ns.Look and ns.Look.Font and ns.Look.Font(parent, "GameFontHighlightSmall", color) or parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if size and fs.SetFont then pcall(function() local p = fs:GetFont() if p then fs:SetFont(p, size, "") end end) end
  if justify then fs:SetJustifyH(justify) end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end
local function Color(fs, c, a)
  if type(c) == "table" and fs and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3], a or 1) end
end

local function Tex(parent, layer, color, alpha)
  local t = parent:CreateTexture(nil, layer)
  t:SetTexture("Interface\\Buttons\\WHITE8x8")
  if type(color) == "table" then t:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1) end
  return t
end

local GOLD, GOLD_L, CREAM, HINT = B.gold or { 0.86, 0.71, 0.42 }, B.goldLight or { 0.97, 0.87, 0.60 },
  B.textPrimary or { 0.96, 0.92, 0.84 }, B.textHint or { 0.58, 0.57, 0.66 }
local SECOND = B.textSecondary or { 0.80, 0.76, 0.68 }
local GREEN = { 0.40, 0.85, 0.45 }

local function CreateCard()
  local f = CreateFrame("Button", nil, UIParent)
  f:SetSize(280, 80)
  f.bg = Tex(f, "BACKGROUND", { 0.96, 0.78, 0.26 }, 0.08)
  f.bg:SetAllPoints()
  f.edge = {}
  for i = 1, 4 do f.edge[i] = Tex(f, "BORDER", GOLD, 0.45) end
  f.edge[1]:SetPoint("TOPLEFT") f.edge[1]:SetPoint("TOPRIGHT") f.edge[1]:SetHeight(1)
  f.edge[2]:SetPoint("BOTTOMLEFT") f.edge[2]:SetPoint("BOTTOMRIGHT") f.edge[2]:SetHeight(1)
  f.edge[3]:SetPoint("TOPLEFT") f.edge[3]:SetPoint("BOTTOMLEFT") f.edge[3]:SetWidth(1)
  f.edge[4]:SetPoint("TOPRIGHT") f.edge[4]:SetPoint("BOTTOMRIGHT") f.edge[4]:SetWidth(1)
  f.compass = ns.NewCompass(f, COMPASS)
  f.compass:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  f.dist = Font(f, 12, GOLD_L, "CENTER")
  f.dist:SetPoint("TOP", f.compass, "BOTTOM", 0, -1)
  f.dist:SetWidth(COMPASS + 18)
  -- (Daniel 12.10.: "In the obj..." cut off) two lines under the compass
  if f.dist.SetWordWrap then f.dist:SetWordWrap(true) end
  if f.dist.SetMaxLines then f.dist:SetMaxLines(2) end
  f.label = Font(f, 10, GOLD, "LEFT")
  f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
  f.title = Font(f, 13, CREAM, "LEFT")
  f.title:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -2)
  f.lines, f.pips = {}, {}
  f:RegisterForClicks("LeftButtonUp")
  f:SetScript("OnClick", function(self)
    if self.questID and IsShiftKeyDown and IsShiftKeyDown() then ns.ShowQuestText(self.questID) end
  end)
  f:SetScript("OnEnter", function(self)
    if not self.questID then return end
    Style.Tooltip(self, ns.QuestTitle(self.questID), { { L["Distance"], f.dist:GetText() or "" } },
      L["Shift-click: read the whole quest."])
  end)
  f:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  -- the compass follows the arrow 20 times a second
  local elapsed = 0
  f:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed < 0.05 then return end
    elapsed = 0
    ns.SafeCall("trackerCompass", function() ns.TrackerCompassTick() end)
  end)
  return f
end

local function Line(i)
  local fs = card.lines[i]
  if not fs then fs = Font(card, 11, SECOND, "LEFT") card.lines[i] = fs end
  fs:Show()
  return fs
end
local npip = 0
local function Pip()
  npip = npip + 1
  local i = npip
  local t = card.pips[i]
  if not t then t = Tex(card, "ARTWORK", GOLD, 1) card.pips[i] = t end
  t:Show()
  return t
end

function ns.TrackerCompassTick()
  if not card then return end
  local st = ns.ArrowState and ns.ArrowState() or {}
  local facing = ns.Num(ns.Value(GetPlayerFacing))
  local arrived = st.seal and true or false
  card.compass:Arrived(arrived)
  if st.needle and st.angle and facing then
    -- (Daniel 12.10.) towards the quest target itself (the way around: the dots on the minimap); else the
    -- arrow's angle, which is -(bearing + facing)
    local bearing = type(st.bearing) == "number" and st.bearing or (-st.angle - facing)
    card.compass:Point(bearing, facing, st.nearness)
  else
    card.compass:Point(nil, facing)
  end
  local text = st.distText or ""
  -- "240 yards, the way around": the distance on the card, the rest as a hint below the title
  card.dist:SetText(st.t and (text:match("^[%d%.,]+%s*%S*") or text) or "")
  if st.distColor and st.distColor ~= "textSecondary" and ns.Look and ns.Look.SetColor then
    ns.Look.SetColor(card.dist, st.distColor)
  else
    Color(card.dist, GOLD_L)
  end
  local way = st.t and text:match("^[%d%.,]+%s*%S*,%s*(.+)$") or nil
  if card.way then card.way:SetText(way or "") end
end

-- Lays the card out for one quest and returns its height.
local function FillCard(e, width)
  card.questID = e and e.questID
  for _, fs in ipairs(card.lines) do fs:Hide() end
  for _, t in ipairs(card.pips) do t:Hide() end
  npip = 0
  -- (1.3.7, Daniel 13.10.: "switch the option off and the compass in the list should be gone") the compass only
  -- with "Compass in the quest list"
  local withCompass = DB().trackerCompass ~= false
  if withCompass then card.compass:Show() card.dist:Show() else card.compass:Hide() card.dist:Hide() end
  local textW = withCompass and (width - COMPASS - 24) or (width - 16)
  card:SetWidth(width)
  if not e then
    card.label:SetText(L["Quest log empty"])
    card.title:SetText("")
    return COMPASS + 38
  end
  card.label:SetText((ns.QuestLevelTag(e.questID) or "") .. (e.complete and L["Ready to turn in"] or L["Picked"]))
  card.title:SetWidth(textW)
  card.title:SetText(e.title or "")
  if Style.FitText then Style.FitText(card.title, textW) end
  local y = 6 + 12 + 2 + 16 + 4
  local n = 0
  local shown = 0
  for _, o in ipairs(e.objs) do
    if shown >= MAX_OBJ then break end
    shown = shown + 1
    n = n + 1
    local fs = Line(n)
    fs:SetWidth(textW)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -y)
    fs:SetText(o.text)
    Color(fs, o.done and GREEN or SECOND)
    if Style.FitText then Style.FitText(fs, textW) end
    y = y + 14
    -- blocks for small counts (the game's x/y), a thin bar for big ones
    if o.need and o.need > 1 and not o.done then
      local have = math.max(0, math.min(o.need, o.have or 0))
      if o.need <= 12 then
        local gap = 2
        local w = (textW - gap * (o.need - 1)) / o.need
        for k = 1, o.need do
          local t = Pip()
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", card, "TOPLEFT", 8 + (k - 1) * (w + gap), -y)
          t:SetSize(math.max(1, w), 5)
          if k <= have then t:SetVertexColor(GOLD_L[1], GOLD_L[2], GOLD_L[3], 1) else t:SetVertexColor(1, 1, 1, 0.12) end
        end
      else
        local back = Pip()
        back:ClearAllPoints() back:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -y) back:SetSize(textW, 5)
        back:SetVertexColor(1, 1, 1, 0.12)
        if have > 0 then
          local fill = Pip()
          fill:ClearAllPoints() fill:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -y) fill:SetSize(math.max(1, textW * have / o.need), 5)
          fill:SetVertexColor(GOLD_L[1], GOLD_L[2], GOLD_L[3], 1)
        end
      end
      y = y + 8
    end
  end
  if e.complete or #e.objs == 0 then
    local who = TurnInName(e.questID)
    if who then
      n = n + 1
      local fs = Line(n)
      fs:SetWidth(textW)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -y)
      fs:SetText(L["Turn in: %s"]:format(who))
      Color(fs, e.complete and GREEN or HINT)
      y = y + 14
    end
  end
  -- the way around / first to the way in (from the arrow)
  if not card.way then card.way = Font(card, 10, { 0.96, 0.84, 0.48 }, "LEFT") end
  card.way:SetWidth(textW)
  card.way:ClearAllPoints()
  card.way:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -y)
  y = y + 13
  return math.max(y + 4, withCompass and (COMPASS + 38) or 0)
end

---------------------------------------------------------------------------
-- The whole quest to read (also for Leveldon: QuestdonAPI.ShowQuestText)
---------------------------------------------------------------------------
-- (1.3.6) the game's texts are saved when a quest giver shows them (QUEST_DETAIL, QUEST_PROGRESS,
-- QUEST_COMPLETE): readable later, also for quests not in the log
local function SaveText(field, fn)
  local id = ns.Num(ns.Value(GetQuestID))
  if not id or id == 0 then return end
  local text = ns.Value(fn)
  if type(text) ~= "string" or text == "" then return end
  local db = DB()
  db.questTexts = db.questTexts or {}
  local t = db.questTexts[id] or {}
  t[field] = text
  db.questTexts[id] = t
end
ns.On("QUEST_DETAIL", function()
  SaveText("d", GetQuestText)
  SaveText("o", GetObjectiveText)
end)
ns.On("QUEST_PROGRESS", function() SaveText("p", GetProgressText) end)
ns.On("QUEST_COMPLETE", function() SaveText("c", GetRewardText) end)

-- the description and objective text of a quest in the log, from the game
local function LogText(id)
  if not (C_QuestLog and ns.InQuestLog(id)) then return nil end
  local old = C_QuestLog.GetSelectedQuest and ns.Num(ns.Value(C_QuestLog.GetSelectedQuest))
  if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, id) end
  local ok, desc, obj = pcall(GetQuestLogQuestText)
  if old and C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, old) end
  if not ok then return nil end
  desc = type(desc) == "string" and ns.Usable(desc) and desc ~= "" and desc or nil
  obj = type(obj) == "string" and ns.Usable(obj) and obj ~= "" and obj or nil
  if not (desc or obj) then return nil end
  return { d = desc, o = obj }
end

local reader
-- (Daniel 12.10.: "very small writing") the reader at 120 % like the list unless you changed it (Ctrl + wheel)
local function ReaderGet(key)
  local t = DB().readerPanel
  local v = type(t) == "table" and t[key] or nil
  if v == nil and key == "scale" then return 1.2 end
  return v
end
local function ReaderSet(key, v) local db = DB() if type(db.readerPanel) ~= "table" then db.readerPanel = {} end db.readerPanel[key] = v end

function ns.QuestTextParts(id)
  local game = LogText(id)
  local saved = DB().questTexts and DB().questTexts[id] or nil
  local data = ns.QuestText and ns.QuestText(id) or nil
  return {
    description = (game and game.d) or (saved and saved.d) or nil,
    objective = (game and game.o) or (saved and saved.o) or (data and data.o) or nil,
    progress = saved and saved.p or nil,
    completion = saved and saved.c or nil,
  }
end

function ns.ShowQuestText(id)
  id = ns.Num(id)
  if not id then return end
  -- (Daniel 12.10.: "pressing it again should close the window") the same quest again: the reader closes
  if reader and reader._questID == id and reader:IsShown() then
    reader._questID = nil
    reader:FadeOut()
    return reader
  end
  if not reader then
    reader = Style.Panel("QuestdonQuestText", UIParent, {
      look = "book", media = MEDIA,
      title = Style.Wordmark("Quest", "don"), width = 400, close = true,
      get = ReaderGet, set = ReaderSet,
      defaultPoint = { "CENTER", "CENTER", 0, 60 },
      onClose = function(p) p._questID = nil p:FadeOut() end,
    })
    if reader._header and reader._header.EnableMouseWheel then
      reader._header:EnableMouseWheel(true)
      reader._header:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then reader:SetPanelScale((reader._scale or 1) + (delta > 0 and 0.05 or -0.05)) end
      end)
    end
  end
  reader:ClearRows()
  local parts = ns.QuestTextParts(id)
  Style.Header(reader, (ns.QuestLevelTag(id) or "") .. (ns.QuestTitle(id) or ""))
  local any = false
  if parts.description then
    Style.Row(reader):SetText(parts.description, B.textPrimary or "textPrimary")
    any = true
  end
  if parts.objective then
    Style.Header(reader, L["To do"]):SetGapBefore(6)
    Style.Row(reader):SetText(parts.objective, B.textPrimary or "textPrimary")
    any = true
  end
  local objs = ns.InQuestLog(id) and Objectives(id) or {}
  for _, o in ipairs(objs) do
    Style.Row(reader):SetText("- " .. o.text, o.done and "good" or (B.textSecondary or "textSecondary")):SetIndent(8)
  end
  if parts.progress then
    Style.Header(reader, L["Progress"]):SetGapBefore(6)
    Style.Row(reader):SetText(parts.progress, B.textSecondary or "textSecondary")
  end
  if parts.completion then
    Style.Header(reader, L["Completion"]):SetGapBefore(6)
    Style.Row(reader):SetText(parts.completion, B.textSecondary or "textSecondary")
  end
  local rewards = ns.QuestRewardLines and ns.QuestRewardLines(id) or {}
  if #rewards > 0 then
    Style.Header(reader, L["Rewards"]):SetGapBefore(6)
    for _, r in ipairs(rewards) do Style.Row(reader):SetText(r, B.textPrimary or "textPrimary") end
  end
  if not any then
    Style.Row(reader):SetText(L["The game shows the whole text at the quest giver. Questdon keeps it from then on."], B.textHint or "textHint"):SetGapBefore(6)
  end
  reader._questID = id
  reader:Relayout()
  reader:FadeIn()
  return reader
end
ns.QuestTextFrame = function() return reader end -- (tests)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local KEYS = { pos = "trackerPos", collapsed = "trackerCollapsed", scale = "trackerScale", alpha = "trackerAlpha",
  combatFade = "trackerCombatFade", shown = "trackerShown", locked = "trackerLocked" }
local function Get(key) local k = KEYS[key] return k and DB()[k] end
local function Set(key, value) local k = KEYS[key] if k and ns.db then ns.db[k] = value end end

Style.ICONS.qdRead = Style.ICONS.qdRead or {
  atlas = { "Campaign-QuestLog-LoreBook", "questlog-questtypeicon-lore" }, file = "Interface\\Icons\\INV_Misc_Book_09" }

local function Mode() return ns.db.trackerMode == "zones" and "zones" or "near" end

-- (1.3.7, Daniel 13.10.: "right-click: a small menu with abandon quest, hide quest and show hidden quests")
-- Hidden quests are kept per character (QuestdonCharDB.hiddenQuests) and listed folded at the bottom.
local function Hidden()
  local c = ns.charDB
  if type(c) ~= "table" then return {} end
  if type(c.hiddenQuests) ~= "table" then c.hiddenQuests = {} end
  return c.hiddenQuests
end
ns.TrackerHidden = Hidden -- (tests)
local qmenu, qcatcher, armed
local function HideQuestMenu()
  armed = nil
  if qmenu then qmenu:Hide() end
  if qcatcher then qcatcher:Hide() end
end
-- what a menu entry does; "abandon" asks once (the entry turns red), the second click abandons
local function QuestMenuAction(e, what)
  if what == "abandon" then
    if armed ~= e.questID then armed = e.questID return false end
    HideQuestMenu()
    if ns.AbandonQuest then ns.AbandonQuest(e.questID) end
    return true
  elseif what == "hide" then
    Hidden()[e.questID] = not Hidden()[e.questID] or nil
  elseif what == "showhidden" then
    ns.db.trackerHiddenOpen = not ns.db.trackerHiddenOpen or nil
  end
  HideQuestMenu()
  ns.UpdateTracker(true)
  return true
end
ns.TrackerQuestMenuAction = QuestMenuAction -- (tests)
local function HiddenCount()
  local n = 0
  for id in pairs(Hidden()) do if ns.InQuestLog(id) then n = n + 1 else Hidden()[id] = nil end end
  return n
end
local function MenuRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(22)
  r.hover = r:CreateTexture(nil, "BACKGROUND")
  r.hover:SetAllPoints(r)
  r.hover:SetColorTexture(1, 1, 1, 0.07)
  r.hover:Hide()
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.text:SetJustifyH("LEFT")
  r:SetScript("OnEnter", function(self) self.hover:Show() end)
  r:SetScript("OnLeave", function(self) self.hover:Hide() end)
  return r
end
local function ShowQuestMenu(e)
  if not qmenu then
    qcatcher = CreateFrame("Button", nil, UIParent)
    qcatcher:SetAllPoints(UIParent)
    qcatcher:SetFrameStrata("DIALOG")
    qcatcher:RegisterForClicks("AnyUp")
    qcatcher:SetScript("OnClick", HideQuestMenu)
    qmenu = CreateFrame("Frame", "QuestdonQuestMenu", UIParent)
    qmenu:SetFrameStrata("DIALOG")
    local lvl = ns.Num(qcatcher.GetFrameLevel and qcatcher:GetFrameLevel())
    if lvl and qmenu.SetFrameLevel then qmenu:SetFrameLevel(lvl + 10) end
    qmenu:SetWidth(220)
    qmenu:EnableMouse(true)
    qmenu:SetClampedToScreen(true)
    local bg = qmenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(qmenu)
    bg:SetColorTexture(0.10, 0.11, 0.22, 0.97)
    qmenu.title = qmenu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qmenu.title:SetPoint("TOPLEFT", qmenu, "TOPLEFT", 10, -8)
    qmenu.title:SetPoint("RIGHT", qmenu, "RIGHT", -10, 0)
    qmenu.title:SetJustifyH("LEFT")
    qmenu.rows = { MenuRow(qmenu), MenuRow(qmenu), MenuRow(qmenu) }
    for k, r in ipairs(qmenu.rows) do
      r:SetPoint("TOPLEFT", qmenu, "TOPLEFT", 4, -8 - 20 - (k - 1) * 22)
      r:SetPoint("TOPRIGHT", qmenu, "TOPRIGHT", -4, -8 - 20 - (k - 1) * 22)
    end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "QuestdonQuestMenu") end
    qmenu:SetScript("OnHide", function() armed = nil if qcatcher then qcatcher:Hide() end end)
  end
  armed = nil
  qmenu.title:SetText(e.title or tostring(e.questID))
  local hid = Hidden()[e.questID]
  local n = HiddenCount()
  local items = {
    { "abandon", L["Abandon quest"] },
    { "hide", hid and L["Show this quest again"] or L["Hide quest"] },
  }
  if n > 0 then items[#items + 1] = { "showhidden", ns.db.trackerHiddenOpen and L["Fold hidden quests"] or L["Show hidden quests (%d)"]:format(n) } end
  for k, r in ipairs(qmenu.rows) do
    local it = items[k]
    if it then
      r.text:SetText(it[2])
      r.text:SetTextColor(1, 1, 1)
      r:SetScript("OnClick", function(self)
        if QuestMenuAction(e, it[1]) == false then
          self.text:SetText(L["Click again to abandon"])
          self.text:SetTextColor(1, 0.35, 0.3)
        end
      end)
      r:Show()
    else
      r:Hide()
    end
  end
  qmenu:SetHeight(8 + 20 + #items * 22 + 8)
  local x, y = 0, 0
  if GetCursorPosition then x, y = GetCursorPosition() end
  local sc = ns.Num(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  qmenu:ClearAllPoints()
  qmenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / sc - 8, (y or 0) / sc + 8)
  qcatcher:Show()
  qmenu:Show()
end
ns.TrackerQuestMenu = ShowQuestMenu -- (tests)

local function RowFor(e, focusID)
  local row = Style.Row(panel)
  local title = (ns.QuestLevelTag(e.questID) or "") .. (e.title or "")
  local sub
  if e.failed then sub = Style.Colorize(L["Failed"], "critical")
  elseif e.complete then
    local who = TurnInName(e.questID)
    sub = Style.Colorize(who and L["Turn in: %s"]:format(who) or L["Ready to turn in"], "good")
  elseif e.open then sub = Style.Colorize(Short(e.open), B.textHint or "textHint") end
  row:SetText(sub and (title .. "\n" .. sub) or title, e.complete and { 0.62, 0.92, 0.62 } or (B.textPrimary or "textPrimary"))
  if e.questID == focusID then row:SetActive(true) end
  row:SetOnClick(function(_, button)
    if button == "RightButton" then ShowQuestMenu(e) return end
    if IsShiftKeyDown and IsShiftKeyDown() then ns.ShowQuestText(e.questID) return end
    Pick(e.questID)
  end)
  row:SetTooltip(function()
    local lines = {}
    for _, o in ipairs(e.objs) do lines[#lines + 1] = (o.done and "|cff66cc73" or "") .. o.text .. (o.done and "|r" or "") end
    if e.dist then lines[#lines + 1] = { L["Distance"], Yards(e.dist) } end
    return e.title, lines, L["Click: pick it (compass). Shift-click: read the whole quest."] .. " " .. L["Right-click: abandon or hide."]
  end)
  return row
end

local function NeedleRow(row, e)
  row:SetValue(Yards(e.dist), B.goldLight or "accent")
  if e.target then
    row:SetIcon(NEEDLE)
    rows[#rows + 1] = { row = row, target = e.target }
  end
end

local function NewNearby()
  local mapID = ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  if not (mapID and ns.AvailableQuestsOnMap and ns.PlayerWorld) then return 0 end
  local pc, pn, pw = ns.PlayerWorld()
  if not pc then return 0 end
  local n, best = 0, nil
  local target = { mapID = mapID }
  for _, a in ipairs(ns.AvailableQuestsOnMap(mapID) or {}) do
    if not a.dimmed and a.x and a.y then
      target.x, target.y = a.x, a.y
      local d = ns.DistanceFrom(pc, pn, pw, target)
      if d and d <= NEAR_NEW then
        n = n + 1
        if not best or d < best then best = d end
      end
    end
  end
  return n, best
end

-- (1.3.8, Daniel 13.10.: the old Questdon window goes; what only it had comes to the bottom of the list) quests in
-- the log, quest items without their quest (two clicks destroy the first sure one), the group's progress
local destroyID, destroyUntil
local function FirstSure(orphans) for _, o in ipairs(orphans) do if o.sure then return o end end end
local function ItemName(o) return o.link and o.link:match("%[(.-)%]") or ("item:" .. tostring(o.itemID)) end
local function DestroyClick()
  if InCombatLockdown and InCombatLockdown() then return end
  local first = FirstSure(ns.OrphanQuestItems and ns.OrphanQuestItems() or {})
  if not first then return end
  local now = GetTime and GetTime() or 0
  if destroyID == first.itemID and destroyUntil and now < destroyUntil then
    destroyID = nil
    if ns.DestroyQuestItem and ns.DestroyQuestItem(first.itemID) then ns.Print(L["Destroyed: %s"]:format(first.link or first.itemID)) end
  else
    destroyID, destroyUntil = first.itemID, now + 4
    if ns.After then ns.After(4.1, function() ns.UpdateTracker(true) end) end
  end
  ns.UpdateTracker(true)
end
ns.TrackerDestroyClick = DestroyClick -- (tests)
local function ExtrasSig()
  local n, max if ns.QuestLogCount then n, max = ns.QuestLogCount() end
  local orphans = ns.OrphanQuestItems and ns.OrphanQuestItems() or {}
  local first = FirstSure(orphans)
  local g = ""
  if ns.db.partyProgress and ns.PartyMemberCount and ns.PartyMemberCount() > 0 and ns.PartyOverview then
    local po = ns.PartyOverview()
    g = #po.shared .. "/" .. #po.takeable
  end
  return table.concat({ tostring(n), tostring(max), #orphans, first and first.itemID or "", tostring(destroyID), g }, ":")
end
local function Extras()
  local hint = B.textHint or "textHint"
  local n, max if ns.QuestLogCount then n, max = ns.QuestLogCount() end
  if max then
    Style.Row(panel):SetText(L["Quests in log"], hint):SetGapBefore(6)
      :SetValue(("%d/%d"):format(n, max), n >= max and "critical" or (n >= max - 3 and "warning") or hint)
  end
  local orphans = ns.OrphanQuestItems and ns.OrphanQuestItems() or {}
  if #orphans > 0 then
    local first = FirstSure(orphans)
    local confirm = first and destroyID == first.itemID and destroyUntil and GetTime() < destroyUntil
    local row = Style.Row(panel)
    if first and not (InCombatLockdown and InCombatLockdown()) then
      row:SetText(confirm and L["Click again: destroy %s"]:format(ItemName(first)) or (L["Destroy unneeded quest item"] .. ": " .. ItemName(first)),
        confirm and "critical" or "accent")
      row:SetOnClick(ns.Guard and ns.Guard("tracker", DestroyClick) or DestroyClick)
    else
      row:SetText(L["Quest items without quest"], hint)
    end
    row:SetValue(tostring(#orphans), "warning")
    row:SetTooltip(function()
      local lines = {}
      for i = 1, math.min(#orphans, 30) do
        local line = orphans[i].link or ("item:" .. orphans[i].itemID)
        if orphans[i].quest then line = line .. "  " .. orphans[i].quest end
        if not orphans[i].sure then line = line .. "  ?" end
        lines[#lines + 1] = line
      end
      return L["Probably no longer needed"], lines, first and L["Click twice within 4 seconds to destroy. This cannot be undone."] or nil
    end)
  end
  if ns.db.partyProgress and ns.PartyMemberCount and ns.PartyMemberCount() > 0 and ns.PartyOverview then
    local po = ns.PartyOverview()
    Style.Row(panel):SetText(L["Group progress"], hint)
      :SetValue(L["%d shared, %d to pick up"]:format(#po.shared, #po.takeable))
      :SetTooltip(function()
        local lines, count = {}, 0
        for _, id in ipairs(po.shared) do
          if count >= 30 then break end
          count = count + 1
          lines[#lines + 1] = { header = ns.QuestTitle(id) }
          lines[#lines + 1] = { "  " .. L["You"], ns.IsQuestComplete(id) and L["done"] or ns.QuestProgressText(id) or L["in log"],
            ns.IsQuestComplete(id) and "good" or "textPrimary" }
          for _, p in ipairs(ns.PartyProgress(id)) do
            lines[#lines + 1] = { "  " .. p.name, ns.PartyStateText(p), p.complete and "good" or (p.failed and "critical") or "textPrimary" }
          end
        end
        if #po.takeable > 0 then
          lines[#lines + 1] = { header = L["Your group has, you can pick up:"] }
          for i = 1, math.min(#po.takeable, 30) do
            local id = po.takeable[i]
            lines[#lines + 1] = { "  " .. ns.QuestTitle(id), table.concat(ns.PartyMembersWithQuest(id), ", ") }
          end
        end
        return L["Group progress"], lines, nil
      end)
  end
end

local function Footer()
  -- (1.3.7, Daniel 13.10.: "only with Questdon's XP bar off") the bar shows the same
  if ns.db.xpBar then return end
  local level = ns.PlayerLevel()
  local xp, max = ns.Num(ns.Value(UnitXP, "player")), ns.Num(ns.Value(UnitXPMax, "player"))
  local gain = ns.CompletedQuestXP and ns.CompletedQuestXP() or 0
  local row = Style.Row(panel):SetText(level and L["Level %d"]:format(level) or "", B.textHint or "textHint"):SetGapBefore(6)
  if gain and gain > 0 then row:SetValue(L["+%s XP on turn-in"]:format(Style.Number(gain)), "good") end
  if xp and max and max > 0 then
    Style.Bar(row, { height = 4, segments = {
      { key = "xp", color = { 0.58, 0.40, 0.92 }, value = xp / max },
      { key = "gain", color = "good", alpha = 0.6, value = math.min(1, (gain or 0) / max) } } })
  end
end

-- (Daniel 12.10.: "the choice up top is not very clear": two small icons, one of them a dark square) three
-- tabs in words under the title: Nearby, By zone, By level. The one you are in is gold and underlined.
local tabs
local TAB_H = 18
local function TabActive(key)
  if key == "near" then return Mode() == "near" end
  if key == "zones" then return Mode() == "zones" and not ns.db.trackerSortLevel end
  return Mode() == "zones" and ns.db.trackerSortLevel and true or false
end
local function TabColors()
  for _, b in ipairs(tabs and tabs.b or {}) do
    local on = TabActive(b.key)
    b.on = on
    Color(b.fs, on and GOLD_L or (b.hover and CREAM or HINT))
    if on then b.line:Show() else b.line:Hide() end
  end
end
local function Tabs()
  if not tabs then
    tabs = CreateFrame("Frame", nil, UIParent)
    tabs:SetHeight(TAB_H)
    tabs.b = {}
    local defs = { { "near", L["Nearby"] }, { "zones", L["By zone"] }, { "level", L["By level"] } }
    for i, d in ipairs(defs) do
      local b = CreateFrame("Button", nil, tabs)
      b.key = d[1]
      b.fs = Font(b, 11, HINT, "CENTER")
      b.fs:SetPoint("CENTER", b, "CENTER", 0, 1)
      b.fs:SetText(d[2])
      b._w = math.floor((ns.Num(ns.Value(b.fs.GetStringWidth, b.fs)) or 60) + 14)
      b:SetSize(b._w, TAB_H)
      b.line = Tex(b, "ARTWORK", GOLD, 0.9)
      b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 0)
      b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 0)
      b.line:SetHeight(1)
      b:SetScript("OnEnter", function(self) self.hover = true TabColors() end)
      b:SetScript("OnLeave", function(self) self.hover = nil TabColors() end)
      b:SetScript("OnClick", function(self)
        if self.key == "near" then ns.db.trackerMode = "near"
        else ns.db.trackerMode, ns.db.trackerSortLevel = "zones", self.key == "level" end
        ns.UpdateTracker(true)
      end)
      tabs.b[i] = b
    end
  end
  -- (Daniel 12.10.: "the tabs in the middle of the window, also when the width changes") centred on each build
  local width = (panel and panel._width or 300) - 16
  tabs:SetWidth(width)
  local total, gap = 0, 6
  for i, b in ipairs(tabs.b) do total = total + b._w + (i > 1 and gap or 0) end
  local x = math.max(0, math.floor((width - total) / 2))
  for _, b in ipairs(tabs.b) do
    b:ClearAllPoints()
    b:SetPoint("LEFT", tabs, "LEFT", x, 0)
    x = x + b._w + gap
  end
  TabColors()
  return tabs
end
ns.TrackerTabs = function() return tabs end -- (tests)

local function Build()
  if not panel then return end
  local list = Entries()
  local focusID = FocusID(list)
  local focus
  for _, e in ipairs(list) do if e.questID == focusID then focus = e end end
  -- rebuild only when something we show changed (distances in steps of 10 yards)
  local sig = { Mode(), tostring(ns.db.trackerSortLevel), tostring(focusID), tostring(ns.GuideActive()),
    tostring(ns.db.trackerLines), tostring(panel._width), tostring(ns.db.trackerGreyOpen), tostring(ns.db.trackerHideGrey), tostring(ns.db.trackerHiddenOpen), tostring(ns.db.xpBar), ExtrasSig() }
  for _, e in ipairs(list) do
    sig[#sig + 1] = e.questID .. (e.complete and "c" or "") .. (e.failed and "f" or "") .. (e.grey and "g" or "") .. (Hidden()[e.questID] and "h" or "") .. (e.dist and math.floor(e.dist / 10) or "-")
    for _, o in ipairs(e.objs) do sig[#sig + 1] = (o.have or "") .. (o.done and "d" or "") end
  end
  local n, best = NewNearby()
  sig[#sig + 1] = n .. ":" .. (best and math.floor(best / 10) or "")
  sig[#sig + 1] = tostring(ns.Num(ns.Value(UnitXP, "player")))
  sig = table.concat(sig, "|")
  if sig == lastSig then return end
  lastSig = sig
  for k in pairs(rows) do rows[k] = nil end
  panel:ClearRows()
  local width = (panel._width or 300) - 16
  -- (Daniel 12.10.: make the window bigger or smaller) how many quests the list shows (the handle, down and up)
  local left = tonumber(ns.db.trackerLines) or math.huge
  local more = 0
  local function Take()
    if left > 0 then left = left - 1 return true end
    more = more + 1
    return false
  end
  Style.Content(panel, Tabs(), TAB_H)
  -- (1.3.6) with a guide's compass (Leveldon) the guide shows the way: no card of our own, all quests listed
  if not ns.GuideActive() then
    local h = FillCard(focus, width)
    local holder = Style.Content(panel, card, h)
    if holder and holder.SetKeepWhenCollapsed then holder:SetKeepWhenCollapsed(true) end
  else
    card.questID = focusID
  end
  local greys, hiddenQ, rest = {}, {}, {}
  local hid = Hidden()
  for _, e in ipairs(list) do
    local free = e.questID ~= focusID or ns.GuideActive()
    if hid[e.questID] and free then hiddenQ[#hiddenQ + 1] = e
    elseif e.grey and free then greys[#greys + 1] = e
    else rest[#rest + 1] = e end
  end
  list = rest
  -- the folded line of grey quests at the bottom (click: show or hide them)
  local function Greys()
    if #greys == 0 or ns.db.trackerHideGrey then return end
    local open = ns.db.trackerGreyOpen
    Style.Row(panel):SetText(L["Grey quests"] .. " (" .. #greys .. ")", B.textHint or "textHint")
      :SetValue(open and "-" or "+", B.textHint or "textHint"):SetGapBefore(4)
      :SetOnClick(function() ns.db.trackerGreyOpen = not ns.db.trackerGreyOpen or nil ns.UpdateTracker(true) end)
      :SetTooltip(function() return L["Grey quests"], { L["No XP left for your level."] }, L["Click: show or hide them."] end)
    if open then
      table.sort(greys, function(a, b) return (a.level or 0) < (b.level or 0) end)
      for _, e in ipairs(greys) do RowFor(e, focusID):SetIndent(12) end
    end
  end
  -- the quests you hid (right-click menu), folded the same way
  local function HiddenLine()
    if #hiddenQ == 0 then return end
    local open = ns.db.trackerHiddenOpen
    Style.Row(panel):SetText(L["Hidden quests"] .. " (" .. #hiddenQ .. ")", B.textHint or "textHint")
      :SetValue(open and "-" or "+", B.textHint or "textHint"):SetGapBefore(4)
      :SetOnClick(function() ns.db.trackerHiddenOpen = not ns.db.trackerHiddenOpen or nil ns.UpdateTracker(true) end)
      :SetTooltip(function() return L["Hidden quests"], nil, L["Click: show or hide them."] end)
    if open then
      for _, e in ipairs(hiddenQ) do RowFor(e, focusID):SetIndent(12) end
    end
  end
  if Mode() == "near" then
    local done, others = {}, {}
    for _, e in ipairs(list) do
      if e.questID ~= focusID or ns.GuideActive() then
        if e.complete then done[#done + 1] = e else others[#others + 1] = e end
      end
    end
    local function ByDist(a, b)
      if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
      if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
      return (a.title or "") < (b.title or "")
    end
    table.sort(done, ByDist)
    table.sort(others, ByDist)
    local function Group(head, list2)
      local headed = false
      for _, e in ipairs(list2) do
        if Take() then
          if not headed then Style.Header(panel, head) headed = true end
          NeedleRow(RowFor(e, focusID), e)
        end
      end
    end
    Group(L["Ready to turn in"], done)
    Group(L["Nearby"], others)
    if more > 0 then Style.Row(panel):SetText(L["+%d more quests"]:format(more), B.textHint or "textHint") end
    Greys()
    HiddenLine()
    if n > 0 then
      Style.Row(panel):SetText(n == 1 and L["1 new quest nearby"] or L["%d new quests nearby"]:format(n), { 0.96, 0.78, 0.26 })
        :SetValue(Yards(best), B.goldLight or "accent"):SetIcon("Interface\\GossipFrame\\AvailableQuestIcon"):SetGapBefore(4)
    end
  else
    local shown = {}
    for _, e in ipairs(list) do if e.questID ~= focusID or ns.GuideActive() then shown[#shown + 1] = e end end
    if ns.db.trackerSortLevel then
      table.sort(shown, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return (a.title or "") < (b.title or "")
      end)
    end
    local zone
    for _, e in ipairs(shown) do
     if Take() then
      if not ns.db.trackerSortLevel and e.zone ~= zone then
        zone = e.zone
        Style.Header(panel, zone or L["Other"])
      end
      local row = Style.Row(panel)
      row:SetText((ns.QuestLevelTag(e.questID) or "") .. (e.title or ""), e.complete and { 0.62, 0.92, 0.62 } or (B.textPrimary or "textPrimary"))
      row:SetOnClick(function(_, button)
        if button == "RightButton" then ShowQuestMenu(e) return end
        if IsShiftKeyDown and IsShiftKeyDown() then ns.ShowQuestText(e.questID) return end
        Pick(e.questID)
      end)
      if e.complete then
        local who = TurnInName(e.questID)
        Style.Row(panel):SetText(who and L["Turn in: %s"]:format(who) or L["Ready to turn in"], "good"):SetIndent(12)
      else
        for _, o in ipairs(e.objs) do
          Style.Row(panel):SetText(o.text, o.done and "good" or (B.textSecondary or "textSecondary")):SetIndent(12)
        end
      end
     end
    end
    if more > 0 then Style.Row(panel):SetText(L["+%d more quests"]:format(more), B.textHint or "textHint") end
    Greys()
    HiddenLine()
  end
  lastShown = (tonumber(ns.db.trackerLines) or math.huge) - left
  if lastShown == math.huge or lastShown ~= lastShown then lastShown = 0 end
  Extras()
  Footer()
  panel:Relayout()
end

-- the small needles of the rows (5 times a second, no rebuild)
local function TurnNeedles()
  if not panel or not panel:IsShown() then return end
  local facing = ns.Num(ns.Value(GetPlayerFacing))
  if not facing then return end
  if not ns.PlayerWorld then return end
  local pc, pn, pw = ns.PlayerWorld() -- (all three: "a and f()" would keep only the first)
  if not pc then return end
  for _, r in ipairs(rows) do
    local _, bearing = ns.DistanceFrom(pc, pn, pw, r.target)
    if bearing and r.row.icon and r.row.icon.SetRotation then pcall(r.row.icon.SetRotation, r.row.icon, -(bearing + facing)) end
  end
end
ns.TrackerTurnNeedles = TurnNeedles -- (tests)

-- (1.3.6, Daniel 12.10.: both windows open at once, "dock it") With a guide window (Leveldon, QuestdonAPI.SetGuideFrame)
-- our list hangs right under it, as wide as it, and moves with it; it is not dragged on its own then. Without
-- the guide window it goes back to its own place and width.
local docked = false
local function Dock()
  if not panel then return end
  local g = ns.guideFrame
  local want = ns.db.trackerDock ~= false and type(g) == "table" and g.IsShown and g:IsShown() or false
  if want then
    local gs = ns.Num(ns.Value(g.GetEffectiveScale, g)) or 1
    local ts = ns.Num(ns.Value(panel.GetEffectiveScale, panel)) or 1
    local w = math.floor((ns.Num(g._width) or 300) * gs / ts + 0.5)
    if w > 0 and panel._width ~= w then panel:SetPanelWidth(w) lastSig = nil end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -3)
    if not docked then docked = true panel:SetLocked(true, true) end
    if grip then grip:Hide() end
  elseif docked then
    docked = false
    panel:ApplySettings()
    panel:SetPanelWidth(TrackerWidth())
    lastSig = nil
  end
  if grip and not docked then grip:Show() end
end
ns.TrackerDock = Dock
function ns.ResetTrackerPosition() if panel then panel:ResetPosition() Dock() end end
function ns.TrackerDocked() return docked end -- (tests)

function ns.UpdateTracker(force)
  if not panel then return end
  if force then lastSig = nil end
  if DB().tracker == false then
    if panel:IsShown() then panel:FadeOut() end
    ApplyBlizzTracker()
    if ns.ApplyArrowLook then ns.ApplyArrowLook() end
    return
  end
  Dock()
  Build()
  if not panel:IsShown() and DB().trackerShown ~= false then
    panel:FadeIn()
    if ns.ApplyArrowLook then ns.ApplyArrowLook() end -- (1.3.7) the arrow runs for the list's compass
  end
  ApplyBlizzTracker()
end

function ns.ToggleTracker()
  local db = DB()
  db.tracker = db.tracker == false
  if db.tracker then db.trackerShown = true end
  ns.UpdateTracker(true)
  ns.Print(db.tracker and L["Quest list on."] or L["Quest list off: Blizzard's quest tracker is back."])
end
function ns.TrackerFrame() return panel end

-- (1.3.6) Shift + mouse wheel over the title bar: the background's opacity, down to nothing
local function WheelAlpha(_, delta)
  if not panel then return end
  -- Ctrl + mouse wheel: text size (the whole window, 60 to 160 %, saved as trackerScale)
  if IsControlKeyDown and IsControlKeyDown() then
    panel:SetPanelScale((panel._scale or 1) + (delta > 0 and 0.05 or -0.05))
    lastSig = nil
    Dock()
    return
  end
  if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
  local a = tonumber(DB().trackerAlpha) or Style.DEFAULT_ALPHA
  a = math.max(0, math.min(1, a + (delta > 0 and 0.1 or -0.1)))
  panel:SetBackgroundAlpha(a)
end

-- (Daniel 12.10.: "only Questdon open, no way to make the window bigger or smaller") The handle at the
-- bottom right, as in Leveldon: right and left the width (240 to 600), down and up how many quests the
-- list shows (all when dragged past the last). Ctrl + mouse wheel: text size. Docked under Leveldon the
-- handle is gone (the width is Leveldon's then).
local function Cursor()
  local x, y = GetCursorPosition()
  local sc = ns.Num(ns.Value(panel.GetEffectiveScale, panel)) or 1
  return (tonumber(x) or 0) / sc, (tonumber(y) or 0) / sc
end
local function ApplySize(w, lines, total)
  w = math.max(MIN_W, math.min(MAX_W, math.floor((tonumber(w) or 300) + 0.5)))
  ns.db.trackerWidth = w
  if lines then
    lines = math.max(1, math.min(MAX_LINES, math.floor(lines)))
    if total and lines >= total then lines = nil end -- past the last: all of them
  end
  ns.db.trackerLines = lines
  if panel._width ~= w then panel:SetPanelWidth(w) end
  lastSig = nil
  Build()
end
ns.TrackerApplySize = ApplySize -- (tests)

function ns.TrackerAttachGrip()
  if grip or not panel then return grip end
  grip = CreateFrame("Button", "QuestdonTrackerGrip", panel)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
  if grip.SetFrameLevel and panel.GetFrameLevel then grip:SetFrameLevel((panel:GetFrameLevel() or 60) + 30) end
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:EnableMouse(true)
  if grip.EnableMouseWheel then grip:EnableMouseWheel(true) end
  grip:SetScript("OnMouseWheel", WheelAlpha)
  grip:SetScript("OnEnter", function(self)
    Style.Tooltip(self, L["Window size"], { L["Drag: width (right, left) and how many quests (down, up)."],
      L["Ctrl + mouse wheel: text size."], L["Shift + mouse wheel: background opacity."] })
  end)
  grip:SetScript("OnLeave", function(self) if Style.HideTooltip then Style.HideTooltip(self) end end)
  grip:SetScript("OnMouseDown", function(self)
    if docked then return end
    -- the top left corner stays where it is while the size changes
    local l, t = panel:GetLeft(), panel:GetTop()
    if l and t then
      panel:ClearAllPoints()
      panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
      ns.db.trackerPos = { "TOPLEFT", "BOTTOMLEFT", math.floor(l + 0.5), math.floor(t + 0.5) }
    end
    local x, y = Cursor()
    local total = #Entries()
    self._drag = { x = x, y = y, w = panel._width or TrackerWidth(), lines = tonumber(ns.db.trackerLines) or lastShown, total = total }
    self:SetScript("OnUpdate", function()
      local d = self._drag
      if not d then return end
      local cx, cy = Cursor()
      local w = math.floor(d.w + (cx - d.x) + 0.5)
      local lines = d.lines + math.floor((d.y - cy) / ROW + 0.5)
      w = math.max(MIN_W, math.min(MAX_W, w))
      local cur = tonumber(ns.db.trackerLines) or d.total
      local want = (lines >= d.total) and d.total or math.max(1, lines)
      if w ~= panel._width or want ~= cur then ApplySize(w, lines, d.total) end
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    self._drag = nil
  end)
  if docked then grip:Hide() end
  return grip
end

local function Create()
  card = CreateCard()
  panel = Style.Panel("QuestdonTracker", UIParent, {
    look = "book", media = MEDIA,
    title = Style.Wordmark("Quest", "don"), width = TrackerWidth(),
    close = true, collapse = true,
    closeTooltip = L["Hide the quest list (/qd list brings it back)"],
    buttons = {
      -- (Daniel 12.10.: "a button up top for the options too")
      { key = "options", kind = "options", tooltip = { L["Options"] }, onClick = function() if ns.OpenOptions then ns.OpenOptions() end end },
      { key = "read", kind = "qdRead", tooltip = { L["Read the whole quest"], nil, L["Shift-click a quest does it too."] },
        onClick = function() local id = card and card.questID if id then ns.ShowQuestText(id) end end },
      -- (1.3.8) the quest book button of the old window
      { key = "book", kind = "qdZoneList", tooltip = { L["Quest book"], nil, L["Your journal, the quests of the zone and a search over all quests. /qd journal, /qd zone"] },
        onClick = function() if ns.ToggleQuestBook then ns.ToggleQuestBook() end end },
    },
    get = Get, set = Set,
    defaultPoint = { "TOPRIGHT", "TOPRIGHT", -60, -240 },
    onCollapse = function()
      lastSig = nil
      if ns.ApplyArrowLook then ns.ApplyArrowLook() end
      ns.QueueRefresh("tracker")
    end,
    onClose = function(p)
      ns.db.trackerShown = false
      p:FadeOut()
      ns.After(0.3, function() ApplyBlizzTracker() if ns.ApplyArrowLook then ns.ApplyArrowLook() end end)
    end,
  })
  if panel._header and panel._header.EnableMouseWheel then
    panel._header:EnableMouseWheel(true)
    panel._header:SetScript("OnMouseWheel", WheelAlpha)
  end
  ns.TrackerAttachGrip()
  ns.UpdateTracker(true)
end

ns.RegisterRefresh("tracker", function() ns.UpdateTracker() end)
local function Queue() ns.QueueRefresh("tracker") end

ns.OnInit(function()
  Create()
  ns.NewTicker(1, function() ns.UpdateTracker() end)     -- distances
  ns.NewTicker(0.2, function() ns.SafeCall("trackerNeedles", TurnNeedles) end)
  ns.NewTicker(0.5, function() ns.SafeCall("trackerBlizz", ApplyBlizzTracker) end) -- the game shows it again
  ns.After(0, function() ns.UpdateTracker(true) end)
end)
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("SUPER_TRACKING_CHANGED", Queue)
ns.On("ZONE_CHANGED_NEW_AREA", Queue)
ns.On("PLAYER_ENTERING_WORLD", Queue)
ns.On("PLAYER_XP_UPDATE", Queue)
ns.On("BAG_UPDATE_DELAYED", Queue) -- (1.3.8) quest items without quest
ns.On("GROUP_ROSTER_UPDATE", Queue) -- (1.3.8) group progress
ns.On("PLAYER_REGEN_ENABLED", function() ApplyBlizzTracker() end)
