local _, ns = ...
local L = ns.L
local Style = ns.Style

-- (30.10.2026, L3Hummus on CurseForge, Daniel's draft) Quest chains: the graph of a quest's chain (before, after, forks
-- that join again, "needs 4a and 4b"). Daniel after the first look: no window next to the quest list; Shift-click a quest
-- there opens the book on its zone with the chain. (02.11.2026, draft 4) drawn as a path from left to right in the
-- "Chain" section of the quest's focus card (below).

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
-- (02.11.2026, StyleKit 2 step 4, draft 4) The chain as a path from left to right in the quest's focus card: a box per
-- part, a fork as boxes stacked in one column ("4a" over "4b"), lines between the columns; done / current / next /
-- later in the status colours of the Don style (Kit.STATUS), the current part with a bright edge. A click on a box opens
-- that quest in the quest book, the mouse over it shows the quest's tooltip; a box that sums up parts shows the whole
-- chain. The old diagram (boxes from top to bottom under the quest's line in the zone list) is gone with it.
---------------------------------------------------------------------------
local Kit = LibStub("DonCore-1.0"):Get("Kit", 3)
local PATH = { boxH = 36, gapX = 10, gapY = 4, minW = 52, maxW = 150 }
ns.CHAIN_PATH = PATH -- (tests)
local STATUS_OF = { done = "done", cur = "current", next = "next", later = "later" }

local function BoxPaint(b, hover)
  local st = Kit.STATUS[STATUS_OF[b.state] or "later"] or Kit.STATUS.grey
  Kit.SetColor(b.bg, st.bg)
  b.bd:SetColor((hover or b.state == "cur") and Kit.C.goldBright or st.bd)
  Kit.TextColor(b.label, b.state == "cur" and Kit.C.hero or st.fg)
  Kit.TextColor(b.title, b.state == "later" and Kit.C.muted or Kit.C.title)
end

local function BoxEnter(self)
  BoxPaint(self, true)
  if self.questID then
    local _, text, color = ns.ZoneQuestStatus(self.questID)
    local tip = ns.ZoneQuestTooltip({ questID = self.questID, text = text or L["unknown"], color = color })
    local title, lines = tip()
    local all = {}
    for _, l in ipairs(type(lines) == "table" and lines or {}) do all[#all + 1] = l end
    if self.hint then all[#all + 1] = { self.hint, nil, "textSecondary" } end
    if self.needs then all[#all + 1] = { self.needs, nil, "textHint" } end
    Style.Tooltip(self, title, all, L["Click: open in the quest book."], "auto")
  elseif self.summaryTip then
    local hint = self.dir == 1 and L["Click: show the next parts."] or self.dir == -1 and L["Click: show the parts before."] or self.path.summaryHint
    Style.Tooltip(self, self.summaryTip, nil, hint, "auto")
  end
end

local function BoxLeave(self)
  BoxPaint(self, false)
  Style.HideTooltip(self)
end

local function BoxClick(self)
  if self.questID then
    ns.QuestBookOpenQuest(self.questID)
  elseif self.path.onSummary then
    self.path.onSummary(self)
  end
end

local function NewBox(p)
  local b = CreateFrame("Button", nil, p.frame)
  b.path = p
  b.bg = Kit.Fill(b, Kit.C.card)
  b.bd = Kit.Border(b, Kit.C.divider)
  b.label = Kit.Text(b, "mono", Kit.C.txGold)
  b.label:SetPoint("TOPLEFT", 6, -5)
  b.title = Kit.Text(b, "sub", Kit.C.title)
  b.title:SetPoint("TOPLEFT", 6, -19)
  b:SetScript("OnEnter", BoxEnter)
  b:SetScript("OnLeave", BoxLeave)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  b:SetScript("OnClick", BoxClick)
  return b
end

-- A path on its own frame (made once, drawn again and again); p.frame goes into the card (Kit.Detail:Block).
function ns.ChainPath(parent)
  local f = CreateFrame("Frame", nil, parent)
  local p = { frame = f, boxes = {}, lines = {}, nb = 0, nl = 0 }
  f.path = p
  function f:Layout(w) self:SetWidth(w) end
  return p
end

local function Line(p, x, y, w, h)
  p.nl = p.nl + 1
  local t = p.lines[p.nl]
  if not t then t = Kit.Tex(p.frame, "ARTWORK", Kit.C.mid) p.lines[p.nl] = t end
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", p.frame, "TOPLEFT", x, -y)
  t:SetSize(math.max(1, w), math.max(1, h))
  t:Show()
end

local function SummaryText(it)
  if it.summary == "done" then return L["%d done"]:format(it.count), "done" end
  if it.summary == "before" then return L["%d before"]:format(it.count), "next" end
  if it.summary == "others" then return L["%d more quests"]:format(it.count), "later" end
  return L["%d more parts"]:format(it.count), "later"
end

-- The columns that fit into width w: the chain's layers (Rows, a fork stacked up to three), a long chain as a window
-- around the current part with a box for the parts before and one for the parts after it.
-- (02.11.2026, Daniel: "man kann nicht mehr auf 4 klicken um zurück zu kommen ... 1 more parts funktioniert auch nicht")
-- shift moves the window by whole steps of columns: a click on the box before goes back, the box after forward. Every
-- layer counts (Rows with full), the window alone shortens. Returns the columns and the step (columns per window).
local function Columns(g, full, w, shift)
  local cols = Rows(g, true, 3)
  local maxCols = math.max(3, math.floor((w + PATH.gapX) / (PATH.minW + PATH.gapX)))
  local n = #cols
  if n <= maxCols then return cols, n end
  local ci = 1
  for i, col in ipairs(cols) do for _, it in ipairs(col) do if it.id == g.sel then ci = i end end end
  local keep = maxCols - 2
  -- the part before the current one too when there is room for three
  local start = math.max(1, math.min(ci - (keep >= 3 and 1 or 0), n - keep + 1)) + (tonumber(shift) or 0) * keep
  local stop
  if start <= 1 then start, stop = 1, maxCols - 1
  elseif start + keep - 1 >= n then start, stop = n - (maxCols - 1) + 1, n
  else stop = start + keep - 1 end
  local function Count(from, to)
    local layers, done = 0, true
    for i = from, to do
      local first = cols[i][1]
      if first.summary then
        layers = layers + (first.count or 0)
        if first.summary ~= "done" then done = false end
      else
        layers = layers + 1
        for _, it in ipairs(cols[i]) do if it.id and not ns.IsQuestDone(it.id) then done = false end end
      end
    end
    return layers, done
  end
  local out = {}
  if start > 1 then
    local layers, done = Count(1, start - 1)
    out[1] = { { summary = done and "done" or "before", count = layers, dir = -1 } }
  end
  for i = start, stop do out[#out + 1] = cols[i] end
  if stop < n then out[#out + 1] = { { summary = "more", count = (Count(stop + 1, n)), dir = 1 } } end
  return out, keep
end
ns.ChainColumns = Columns -- (tests)

-- Draws the chain of questID across width w. opts.full: every part. Returns the height used (0: no chain, nothing
-- drawn) and the graph.
function ns.ChainPathDraw(p, questID, w, opts)
  opts = opts or {}
  p.nb, p.nl = 0, 0
  w = math.max(PATH.minW, tonumber(w) or 300)
  local g = ns.ChainGraph(questID)
  local used = 0
  if g then
    local cols, step = Columns(g, opts.full, w, opts.shift)
    local k = #cols
    local bw = math.min(PATH.maxW, math.floor((w - (k - 1) * PATH.gapX) / k))
    local tallest = 1
    for _, col in ipairs(cols) do tallest = math.max(tallest, #col) end
    local H = tallest * PATH.boxH + (tallest - 1) * PATH.gapY
    local half = math.floor(PATH.gapX / 2)
    for ci, col in ipairs(cols) do
      local x = (ci - 1) * (bw + PATH.gapX)
      local colH = #col * PATH.boxH + (#col - 1) * PATH.gapY
      local y0 = math.floor((H - colH) / 2)
      local centers = {}
      for ri, it in ipairs(col) do
        p.nb = p.nb + 1
        local b = p.boxes[p.nb]
        if not b then b = NewBox(p) p.boxes[p.nb] = b end
        local y = y0 + (ri - 1) * (PATH.boxH + PATH.gapY)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", p.frame, "TOPLEFT", x, -y)
        b:SetSize(bw, PATH.boxH)
        b.needs, b.hint = nil, nil
        if it.id then
          b.state = State(g, it.id)
          b.questID, b.summaryTip = it.id, nil
          b.mark = Label(g, it.id)
          b.label:SetText(b.state == "cur" and (b.mark .. "  ·  " .. L["You are here"]) or b.mark)
          b.title:SetText(ns.QuestTitle(it.id) or ("#" .. it.id))
          if b.state == "cur" then b.hint = L["You are here"] elseif b.state == "next" then b.hint = GiverAndPlace(it.id) end
          local need = g.pre[it.id]
          if #need >= 2 and g.layerOf[it.id] > 1 then
            local names = {}
            for _, q in ipairs(need) do names[#names + 1] = Label(g, q) end
            local list = #names == 2 and L["%s and %s"]:format(names[1], names[2]) or table.concat(names, ", ")
            b.needs = L["needs %s"]:format(list)
          end
        else
          local text, state = SummaryText(it)
          b.state, b.questID, b.mark = state, nil, nil
          b.dir, b.step = it.dir, step -- (02.11.2026) a click pages back or forward
          b.summaryTip = it.summary == "more" and L["%d more parts"]:format(it.count) or text
          b.label:SetText(it.summary == "done" and "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t" or "...")
          b.title:SetText(text)
        end
        Kit.Fit(b.label, bw - 12)
        Kit.Fit(b.title, bw - 12)
        BoxPaint(b, false)
        b:Show()
        centers[ri] = y + math.floor(PATH.boxH / 2)
      end
      -- a fork or a join: a bar beside the stacked boxes, a short line to each of them
      if #col > 1 then
        local top, bottom = centers[1], centers[#centers]
        if ci > 1 then
          Line(p, x - half, top, 2, bottom - top + 2)
          for _, c in ipairs(centers) do Line(p, x - half, c, half, 2) end
        end
        if ci < k then
          Line(p, x + bw + half - 2, top, 2, bottom - top + 2)
          for _, c in ipairs(centers) do Line(p, x + bw, c, half, 2) end
        end
      end
      -- to the next column, at the middle of the path
      if ci < k then
        local from = x + bw + (#col > 1 and half or 0)
        local to = x + bw + PATH.gapX - (#cols[ci + 1] > 1 and half or 0)
        if to > from then Line(p, from, math.floor(H / 2), to - from, 2) end
      end
    end
    used = H
    p.frame:SetHeight(H)
  end
  for i = p.nb + 1, #p.boxes do p.boxes[i]:Hide() p.boxes[i].questID = nil end
  for i = p.nl + 1, #p.lines do p.lines[i]:Hide() end
  return used, g
end

-- Hides everything a path drew.
function ns.ChainClear(p)
  p.nb, p.nl = 0, 0
  for _, b in ipairs(p.boxes) do b:Hide() b.questID = nil end
  for _, t in ipairs(p.lines) do t:Hide() end
end
