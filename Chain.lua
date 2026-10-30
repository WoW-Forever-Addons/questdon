local _, ns = ...
local L = ns.L
local Style = ns.Style

-- (30.10.2026, L3Hummus on CurseForge, Daniel's draft) Quest chains as a diagram: boxes from top to bottom, a fork as
-- columns that join again ("needs 4a and 4b"), in the "Chain" section of the quest book's detail card (the whole chain,
-- long ones shortened). Daniel after the first look: no window next to the quest list; Shift-click a quest there opens
-- the book on its zone with this diagram.

local WHITE = "Interface\\Buttons\\WHITE8x8"
local C = Style.COLORS
local MAX_SIDE = 30 -- quests before and after the selected one at most (a hub of a zone would take everything)

---------------------------------------------------------------------------
-- The chain of a quest
---------------------------------------------------------------------------
-- A quest of the chain this character can do (or did): other factions, races and classes stay out; a breadcrumb
-- only when it is done, in the log or the selected quest (it is a way into the chain, not a part of it).
local function Keep(id, sel)
  if id == sel or ns.IsQuestDone(id) or ns.InQuestLog(id) then return true end
  if not ns.QuestReachable(id) then return false end
  if ns.QuestKnownMissing and ns.QuestKnownMissing(id) then return false end
  return not ns.QuestFlags(id):find("b", 1, true)
end

local function Prereqs(id, sel)
  local out = {}
  for _, p in ipairs(ns.QuestPrereqs(id) or {}) do if p ~= id and Keep(p, sel) then out[#out + 1] = p end end
  return out
end

local function FollowUps(id, sel)
  local out = {}
  for _, f in ipairs(ns.FollowUpQuests(id) or {}) do if f ~= id and Keep(f, sel) then out[#out + 1] = f end end
  return out
end

-- The chain of a quest: everything before it, everything after it and the other quests a later part needs.
-- { sel, layers = { { id, ... }, ... }, layerOf = { [id] = n }, pre = { [id] = { ids in the chain } }, title }
-- nil for a quest in no chain (fewer than 2 parts).
function ns.ChainGraph(questID)
  questID = ns.Num(questID)
  if not questID or not ns.QuestInData(questID) then return nil end
  local set, n = { [questID] = true }, 1
  -- before: the quests it needs, and theirs
  local todo, count = { questID }, 0
  while #todo > 0 and count < MAX_SIDE do
    local id = table.remove(todo, 1)
    for _, p in ipairs(Prereqs(id, questID)) do
      if not set[p] and count < MAX_SIDE then set[p], n, count = true, n + 1, count + 1 todo[#todo + 1] = p end
    end
  end
  -- after: the follow-ups, and the other quests they need (one step back, so a join shows both ways)
  todo, count = { questID }, 0
  local after = { [questID] = true }
  while #todo > 0 and count < MAX_SIDE do
    local id = table.remove(todo, 1)
    for _, f in ipairs(FollowUps(id, questID)) do
      if not after[f] and count < MAX_SIDE then
        after[f], count = true, count + 1
        if not set[f] then set[f], n = true, n + 1 end
        todo[#todo + 1] = f
        for _, p in ipairs(Prereqs(f, questID)) do if not set[p] then set[p], n = true, n + 1 end end
      end
    end
  end
  if n < 2 then return nil end
  -- the quests each one needs within the chain; the layer is one more than the deepest of them
  local pre, layerOf = {}, {}
  for id in pairs(set) do
    local list = {}
    for _, p in ipairs(Prereqs(id, questID)) do if set[p] then list[#list + 1] = p end end
    pre[id] = list
  end
  local function Layer(id, depth)
    if layerOf[id] then return layerOf[id] end
    if depth > 60 then return 1 end
    layerOf[id] = 1 -- a loop in the data ends here
    local deepest = 0
    for _, p in ipairs(pre[id]) do
      local l = Layer(p, depth + 1)
      if l > deepest then deepest = l end
    end
    layerOf[id] = deepest + 1
    return deepest + 1
  end
  local layers = {}
  for id in pairs(set) do
    local l = Layer(id, 0)
    layers[l] = layers[l] or {}
    table.insert(layers[l], id)
  end
  -- quests that only lead into the chain from aside (a join's other way) stand next to the quest they lead to
  local onPath = { [questID] = true }
  for id in pairs(set) do
    if after[id] then onPath[id] = true end
  end
  local stack = { questID }
  while #stack > 0 do
    local id = table.remove(stack)
    for _, p in ipairs(pre[id]) do if not onPath[p] then onPath[p] = true stack[#stack + 1] = p end end
  end
  local g = { sel = questID, layers = {}, layerOf = layerOf, pre = pre }
  for i = 1, #layers do
    local list = layers[i] or {}
    table.sort(list, function(a, b)
      if (a == questID) ~= (b == questID) then return a == questID end
      if (onPath[a] or false) ~= (onPath[b] or false) then return onPath[a] or false end
      local la, lb = ns.QuestLevel(a) or 0, ns.QuestLevel(b) or 0
      if la ~= lb then return la < lb end
      return a < b
    end)
    if #list > 0 then g.layers[#g.layers + 1] = list end
  end
  if #g.layers < 2 then return nil end
  -- empty layers cannot happen (a layer is one more than an existing one), but renumber to be sure
  for i, list in ipairs(g.layers) do for _, id in ipairs(list) do layerOf[id] = i end end
  local last = g.layers[#g.layers][1]
  g.title = ns.QuestTitle(last) or ns.QuestTitle(questID)
  return g
end

-- Label of a part: its layer, with a letter where the layer has several quests ("4a").
local function Label(g, id)
  local l = g.layerOf[id]
  local list = g.layers[l]
  if #list == 1 then return tostring(l) end
  for i, x in ipairs(list) do if x == id then return l .. string.char(96 + math.min(i, 26)) end end
  return tostring(l)
end

-- done, cur (the selected quest), next (in the log, can be taken, or all it needs is done), later
local function State(g, id)
  if id == g.sel then return "cur" end
  if ns.IsQuestDone(id) then return "done" end
  if ns.InQuestLog(id) then return "next" end
  for _, p in ipairs(g.pre[id]) do if not ns.IsQuestDone(p) and p ~= g.sel then return "later" end end
  return "next"
end
ns.ChainState = State -- (tests)

-- Quest giver and place of a quest ("Gryan · Westfall"), nil when nothing is known.
local function GiverAndPlace(id)
  local givers = ns.QuestGiverIDs(id)
  local giver = givers and ns.LocalNpcName(givers[1])
  local learned = ns.db.learned and ns.db.learned[id]
  giver = giver or (learned and learned.start and learned.start.npc)
  if not giver then
    local qt = ns.QuestText and ns.QuestText(id)
    giver = qt and qt.s
  end
  local m = ns.QuestStart(id)
  local zone = m and ns.ZoneOfMap and ns.ZoneOfMap(m) or m
  local info = zone and ns.Value(C_Map.GetMapInfo, zone)
  local place = type(info) == "table" and type(info.name) == "string" and ns.Usable(info.name) and info.name ~= "" and info.name or nil
  if giver and place then return giver .. " · " .. place end
  return giver or place
end

---------------------------------------------------------------------------
-- Rows of the diagram
---------------------------------------------------------------------------
-- A row: { { id = questID } or { summary = "done"|"more", count = n }, ... }.
-- Every layer; more than 8 layers: the done ones before the one before the current in one box, after the current one
-- three layers, the rest in one box. full: every layer (the reader clicked a summary box).
local function Rows(g, full, cols)
  local cur = g.layerOf[g.sel]
  local rows = {}
  local function Layer(i)
    local list = g.layers[i]
    local row = {}
    if #list > cols then
      -- the selected quest and the ones in the log first, the rest in a box
      local shown = {}
      for _, id in ipairs(list) do if #shown < cols - 1 and (id == g.sel or ns.InQuestLog(id)) then shown[#shown + 1] = id end end
      for _, id in ipairs(list) do
        if #shown >= cols - 1 then break end
        local dup = false
        for _, s in ipairs(shown) do if s == id then dup = true end end
        if not dup then shown[#shown + 1] = id end
      end
      for _, id in ipairs(shown) do row[#row + 1] = { id = id } end
      row[#row + 1] = { summary = "others", count = #list - #shown }
      return row
    end
    for _, id in ipairs(list) do row[#row + 1] = { id = id } end
    return row
  end
  local first, last = 1, #g.layers
  if not full and #g.layers > 8 then
    first, last = math.max(1, cur - 1), math.min(#g.layers, cur + 3)
  end
  if first > 1 then
    local done = 0
    for i = 1, first - 1 do
      local all = true
      for _, id in ipairs(g.layers[i]) do if not ns.IsQuestDone(id) then all = false end end
      if all then done = done + 1 end
    end
    rows[#rows + 1] = { { summary = done == first - 1 and "done" or "before", count = first - 1 } }
  end
  for i = first, last do rows[#rows + 1] = Layer(i) end
  if last < #g.layers then rows[#rows + 1] = { { summary = "more", count = #g.layers - last } } end
  return rows
end
ns.ChainRows = Rows -- (tests)

---------------------------------------------------------------------------
-- Drawing (pooled boxes and lines on one parent)
---------------------------------------------------------------------------
local SIZE = { font = 12, sub = 11, pad = 6, gap = 10, line = 14, colGap = 8, mid = 0.78 }
-- fill, fill alpha, edge, edge alpha, text
local LOOK = {
  done = { C.good, 0.16, C.good, 0.55, C.good },
  cur = { C.warning, 0.20, C.warning, 0.95, C.warning },
  next = { C.header, 0.95, C.border, 0.30, C.textPrimary },
  later = { C.background, 0.70, C.border, 0.12, C.textHint },
}

local function Flat(parent, layer)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(WHITE)
  return t
end

local function Paint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or 1) end

local function FontSize(fs, size)
  local obj = _G.GameFontHighlightSmall
  local ok, path = false, nil
  if type(obj) == "table" and type(obj.GetFont) == "function" then ok, path = pcall(obj.GetFont, obj) end
  path = (ok and type(path) == "string" and path) or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  if fs.SetFont then pcall(fs.SetFont, fs, path, size, "") end
end

local function BoxEnter(self)
  local d = self.diagram
  for _, e in ipairs(self.edges) do Paint(e, C.textPrimary, 0.7) end
  if self.questID then
    local _, text, color = ns.ZoneQuestStatus(self.questID)
    local tip = ns.ZoneQuestTooltip({ questID = self.questID, text = text or L["unknown"], color = color })
    local title, lines = tip()
    Style.Tooltip(self, title, lines, L["Click: open in the quest book."], "auto")
  elseif self.summaryTip then
    Style.Tooltip(self, self.summaryTip, nil, d.summaryHint, "auto")
  end
end

local function BoxLeave(self)
  local lk = LOOK[self.state] or LOOK.next
  for _, e in ipairs(self.edges) do Paint(e, lk[3], lk[4]) end
  Style.HideTooltip(self)
end

local function BoxClick(self)
  local d = self.diagram
  if self.questID then
    ns.QuestBookOpenQuest(self.questID)
  elseif d.onSummary then
    d.onSummary(self)
  end
end

local function NewBox(d)
  local b = CreateFrame("Button", nil, d.parent)
  b.diagram = d
  b.fill = Flat(b, "BACKGROUND")
  b.fill:SetAllPoints(b)
  b.edges = {}
  for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = Flat(b, "BORDER")
    e:SetPoint(p[1], b, p[1]) e:SetPoint(p[2], b, p[2])
    if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
    b.edges[i] = e
  end
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetJustifyH("CENTER")
  b.text:SetWordWrap(true)
  b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.sub:SetJustifyH("CENTER")
  b.sub:SetWordWrap(true)
  b:SetScript("OnEnter", BoxEnter)
  b:SetScript("OnLeave", BoxLeave)
  b:SetScript("OnClick", BoxClick)
  return b
end

-- A diagram on a parent frame.
function ns.ChainDiagram(parent)
  return { parent = parent, size = SIZE, boxes = {}, lines = {}, nb = 0, nl = 0 }
end

local function Line(d, x, y, w, h)
  d.nl = d.nl + 1
  local t = d.lines[d.nl]
  if not t then t = Flat(d.parent, "ARTWORK") d.lines[d.nl] = t end
  Paint(t, C.textHint, 0.8)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", d.parent, "TOPLEFT", x, -y)
  t:SetSize(math.max(1, w), math.max(1, h))
  t:Show()
end

local function SummaryText(it)
  if it.summary == "done" then return "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t " .. L["%d done"]:format(it.count), "done" end
  if it.summary == "before" then return L["%d before"]:format(it.count), "next" end
  if it.summary == "others" then return L["%d more quests"]:format(it.count), "later" end
  return L["%d more parts"]:format(it.count), "later"
end

-- Draws the chain of questID at (x, y) of the parent, width w. opts.full, opts.maxH.
-- Returns the height used (0: no chain, nothing drawn), and the graph.
function ns.ChainDraw(d, questID, x, y, w, opts)
  opts = opts or {}
  d.nb, d.nl = 0, 0
  local g = ns.ChainGraph(questID)
  local used = 0
  if g then
    local s = d.size
    local rows = Rows(g, opts.full, 3)
    local top = y
    local prevCenters, prevBottom
    for ri, row in ipairs(rows) do
      local n = #row
      local bw = n == 1 and math.floor(w * s.mid) or math.floor((w - (n - 1) * s.colGap) / n)
      local left = n == 1 and x + math.floor((w - bw) / 2) or x
      -- boxes of this row: text first, the height of the tallest
      local made, rowH = {}, 0
      for ci, it in ipairs(row) do
        d.nb = d.nb + 1
        local b = d.boxes[d.nb]
        if not b then b = NewBox(d) d.boxes[d.nb] = b end
        FontSize(b.text, s.font)
        FontSize(b.sub, s.sub)
        b.text:SetWidth(bw - 2 * s.pad)
        b.sub:SetWidth(bw - 2 * s.pad)
        local state, main, sub
        if it.id then
          state = State(g, it.id)
          local label = Label(g, it.id)
          local title = ns.QuestTitle(it.id) or ("#" .. it.id)
          main = label .. " · " .. title
          if state == "cur" then sub = L["You are here"]
          elseif state == "next" then sub = GiverAndPlace(it.id) end
          local need = g.pre[it.id]
          if #need >= 2 and g.layerOf[it.id] > 1 then
            local names = {}
            for _, p in ipairs(need) do names[#names + 1] = Label(g, p) end
            local list = #names == 2 and L["%s and %s"]:format(names[1], names[2]) or table.concat(names, ", ")
            local text = L["needs %s"]:format(list)
            sub = sub and (sub .. "\n" .. text) or text
          end
          b.questID, b.summaryTip = it.id, nil
        else
          main, state = SummaryText(it)
          sub = nil
          b.questID = nil
          b.summaryTip = it.summary == "more" and L["%d more parts"]:format(it.count) or main
        end
        b.state = state
        local lk = LOOK[state] or LOOK.next
        Paint(b.fill, lk[1], lk[2])
        for _, e in ipairs(b.edges) do Paint(e, lk[3], lk[4]) end
        b.text:SetText(main)
        b.text:SetTextColor(lk[5][1], lk[5][2], lk[5][3], 1)
        if sub then
          b.sub:SetText(sub)
          local sc = state == "later" and C.textHint or C.textSecondary
          b.sub:SetTextColor(sc[1], sc[2], sc[3], 1)
          b.sub:Show()
        else
          b.sub:SetText("")
          b.sub:Hide()
        end
        local th = ns.Num(b.text:GetStringHeight()) or s.line
        if th < s.line then th = s.line end
        local sh = sub and (ns.Num(b.sub:GetStringHeight()) or s.line) or 0
        if sub and sh < s.line - 2 then sh = s.line - 2 end
        local h = math.floor(th + sh + 2 * s.pad + (sub and 2 or 0) + 0.5)
        if h > rowH then rowH = h end
        made[ci] = b
      end
      local rowTop = ri == 1 and top or (prevBottom + s.gap)
      if opts.maxH and rowTop + rowH - y > opts.maxH then
        d.nb = d.nb - n -- does not fit: this row and the rest stay out
        break
      end
      local centers = {}
      for ci, b in ipairs(made) do
        local bx = left + (ci - 1) * (bw + s.colGap)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", d.parent, "TOPLEFT", bx, -rowTop)
        b:SetSize(bw, rowH)
        b.text:ClearAllPoints()
        b.text:SetPoint("TOP", b, "TOP", 0, -s.pad)
        b.sub:ClearAllPoints()
        b.sub:SetPoint("TOP", b.text, "BOTTOM", 0, -2)
        b:Show()
        centers[ci] = bx + math.floor(bw / 2)
      end
      -- lines from the row above: straight down, or over a bar where the rows fork or join
      if prevCenters then
        local gy = prevBottom
        if #prevCenters == 1 and #centers == 1 then
          Line(d, centers[1], gy, 2, s.gap)
        else
          local half = math.floor(s.gap / 2)
          local lo, hi = 1e9, -1e9
          for _, c in ipairs(prevCenters) do Line(d, c, gy, 2, half) lo, hi = math.min(lo, c), math.max(hi, c) end
          for _, c in ipairs(centers) do Line(d, c, gy + half, 2, s.gap - half) lo, hi = math.min(lo, c), math.max(hi, c) end
          if hi > lo then Line(d, lo, gy + half, hi - lo + 2, 2) end
        end
      end
      prevCenters, prevBottom = centers, rowTop + rowH
      used = prevBottom - y
    end
  end
  for i = d.nb + 1, #d.boxes do d.boxes[i]:Hide() d.boxes[i].questID = nil end
  for i = d.nl + 1, #d.lines do d.lines[i]:Hide() end
  return used, g
end

-- Hides everything a diagram drew.
function ns.ChainClear(d)
  d.nb, d.nl = 0, 0
  for _, b in ipairs(d.boxes) do b:Hide() b.questID = nil end
  for _, t in ipairs(d.lines) do t:Hide() end
end
