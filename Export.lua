local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Community export: what Questdon learned while playing, as compact text the
-- player can paste into a GitHub issue (form "Quest data") so it can be merged
-- into the shipped data.
--
--   QDX2 <version> <locale> <date> <new|all>
--   S <questID> <mapID> <x> <y> <npcID or 0> <A|H|->   quest start at an NPC, faction
--   G <questID> <mapID> <x> <y> <objectID> <A|H|->      (1.0.1) start at an object
--   I <questID> <itemID or 0> <A|H|->                   (1.0.1) start from an item
--   T <questID> <mapID> <x> <y> <npcID or 0>           turn-in
--   O <questID> <objIndex> <mapID> <x> <y>             objective spot
--   F <questID> <previousQuestID> <2|1>                (1.0.1) offered right after
--                                                      turning in the previous
--                                                      quest at the same giver
--                                                      (2 sure, 1 maybe)
--   K <questID> <objIndex> <c|o|i> <id> <count>        (1.0.1) what gave credit:
--                                                      creature, object or item
--   D <itemID> <c|o> <id> <count> <mapID> <x> <y>      (1.0.1) a quest item dropped
--                                                      from that creature or object
--   A <questID> <level>                                (1.0.1) lowest player level
--                                                      the quest was offered at
--   X <questID>                                        the server does not know
--                                                      this quest (1.13, Exists.lua)
--   # comments (count, truncation)
--
-- Coordinates 0-100 with one decimal. Only numbers: no character, realm,
-- guild, NPC or quest names. "new" leaves out what the bundled data has
-- already (starts at the same spot, objective spots near its points,
-- known prerequisites, credit sources and levels); turn-ins, drops, item
-- starts and X lines are always included (the data has none of them).
---------------------------------------------------------------------------
local MAX_LINES = 3000
local SAME_SPOT = 2   -- start: ATT within 2 map units = the same
local NEAR_ATT = 3    -- objective spot: within 3 map units of an ATT point = known
local ISSUE_URL = "github.com/WoW-Forever-Addons/questdon/issues"

local Q = ns.ATT_QUESTS or {}
local OBJ = ns.ATT_OBJECTIVES or {}
local NPC = ns.ATT_CREATURES or {}

local function Int(v)
  return type(v) == "number" and v >= 0 and v == math.floor(v) and v < 2 ^ 31
end

local function Coord(v)
  return type(v) == "number" and v >= 0 and v <= 1
end

local function Fmt(v) return ("%.1f"):format(v * 100) end

local function Place(p)
  if type(p) ~= "table" or not Int(p.map) or p.map == 0 or not (Coord(p.x) and Coord(p.y)) then return nil end
  return p.map, p.x, p.y, Int(p.npcID) and p.npcID or 0
end

local function Pos(m, x, y)
  return Int(m) and m > 0 and Coord(x) and Coord(y)
end

local function Has(list, v)
  if type(list) == "number" then return list == v end
  for _, x in ipairs(type(list) == "table" and list or {}) do
    if x == v then return true end
  end
  return false
end

-- (1.0.1) Data knows this credit source already (creature or item of the objective)?
local function CreditKnown(questID, index, kind, id)
  local o = OBJ[questID] and OBJ[questID][index]
  if not o then return false end
  if kind == "c" then return Has(o[1], id) end
  if kind == "i" then return Has(o[2], id) end
  return false
end

local function Near(x1, y1, x2, y2, limit)
  return math.abs(x1 - x2) <= limit and math.abs(y1 - y2) <= limit
end

-- Does ATT already have this start? (same map, about the same spot)
local function StartKnown(questID, map, x, y)
  local q = Q[questID]
  return q and q[1] == map and q[2] and q[3] and Near(q[2], q[3], x * 100, y * 100, SAME_SPOT) or false
end

-- Is this objective spot close to an ATT objective point or creature spawn?
local function SpotKnown(questID, index, map, x, y)
  local o = OBJ[questID] and OBJ[questID][index]
  if not o then return false end
  x, y = x * 100, y * 100
  local pts = o[3] or {}
  for i = 1, #pts, 3 do
    if pts[i] == map and Near(pts[i + 1], pts[i + 2], x, y, NEAR_ATT) then return true end
  end
  for _, cr in ipairs(o[1] or {}) do
    local spawns = NPC[cr]
    if spawns then
      for i = 2, #spawns, 3 do
        if spawns[i] == map and Near(spawns[i + 1], spawns[i + 2], x, y, NEAR_ATT) then return true end
      end
    end
  end
  return false
end

local function SortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do
    if Int(k) and k > 0 then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

local function Locale()
  local l = ns.Value(GetLocale)
  return type(l) == "string" and l:match("^%a%a%a%a$") or "enUS"
end
ns.Locale = Locale

-- Today as YYYY-MM-DD (0000-00-00 if the client has no date()).
function ns.Today()
  local d = ns.Value(date, "%Y-%m-%d")
  return type(d) == "string" and d:match("^%d%d%d%d%-%d%d%-%d%d$") or "0000-00-00"
end

-- (1.0.1) The export records (lines without header), also what Questdon
-- shares with guild and group (Exchange.lua). all: without comparing with the data.
function ns.ExportRecords(all)
  local records = {}
  local learned = ns.db.learned or {}
  local learnedObj = ns.db.learnedObj or {}
  local quests = {}
  for _, id in ipairs(SortedKeys(learned)) do quests[id] = true end
  for _, id in ipairs(SortedKeys(learnedObj)) do quests[id] = true end

  local credits = type(ns.db.learnedCredit) == "table" and ns.db.learnedCredit or {}
  for _, id in ipairs(SortedKeys(credits)) do quests[id] = true end

  for _, id in ipairs(SortedKeys(quests)) do
    local e = learned[id]
    if type(e) == "table" then
      local fac = e.faction == "Alliance" and "A" or e.faction == "Horde" and "H" or "-"
      local st = e.start
      if type(st) == "table" and st.item then
        -- (1.0.1) item start: the item, not the spot (wherever it was used)
        if Int(st.itemID) or all or not Q[id] then
          records[#records + 1] = ("I %d %d %s"):format(id, Int(st.itemID) and st.itemID or 0, fac)
        end
      elseif type(st) == "table" then
        local map, x, y, npcID = Place(st)
        if map and (all or not StartKnown(id, map, x, y)) then
          if npcID == 0 and Int(st.objID) and st.objID > 0 then
            records[#records + 1] = ("G %d %d %s %s %d %s"):format(id, map, Fmt(x), Fmt(y), st.objID, fac)
          else
            records[#records + 1] = ("S %d %d %s %s %d %s"):format(id, map, Fmt(x), Fmt(y), npcID, fac)
          end
        end
      end
      local map, x, y, npcID = Place(e.finish)
      if map then
        records[#records + 1] = ("T %d %d %s %s %d"):format(id, map, Fmt(x), Fmt(y), npcID)
      end
      -- (1.0.1) follow-ups
      if type(e.after) == "table" then
        for _, prev in ipairs(SortedKeys(e.after)) do
          local v = e.after[prev]
          if (v == 1 or v == 2) and (all or not (Q[id] and Has(Q[id][6], prev))) then
            records[#records + 1] = ("F %d %d %d"):format(id, prev, v)
          end
        end
      end
      -- (1.0.1) lowest level offered: when the data has no level or a higher one
      local at = e.offeredAt
      if Int(at) and at > 0 and at < 1000 then
        local lv = Q[id] and Q[id][5]
        if all or not (type(lv) == "number") or at < lv then
          records[#records + 1] = ("A %d %d"):format(id, at)
        end
      end
    end
    local objs = learnedObj[id]
    if type(objs) == "table" then
      for _, index in ipairs(SortedKeys(objs)) do
        local spots = objs[index]
        if type(spots) == "table" then
          for i = 1, #spots - 2, 3 do
            local m, sx, sy = spots[i], spots[i + 1], spots[i + 2]
            if Int(m) and m > 0 and Coord(sx) and Coord(sy) and (all or not SpotKnown(id, index, m, sx, sy)) then
              records[#records + 1] = ("O %d %d %d %s %s"):format(id, index, m, Fmt(sx), Fmt(sy))
            end
          end
        end
      end
    end
    -- (1.0.1) credit sources
    local cr = credits[id]
    if type(cr) == "table" then
      for _, index in ipairs(SortedKeys(cr)) do
        local c = cr[index]
        if type(c) == "table" then
          for _, kind in ipairs({ "c", "o", "i" }) do
            for _, sid in ipairs(SortedKeys(c[kind])) do
              local n = c[kind][sid]
              if Int(n) and n > 0 and (all or not CreditKnown(id, index, kind, sid)) then
                records[#records + 1] = ("K %d %d %s %d %d"):format(id, index, kind, sid, n)
              end
            end
          end
        end
      end
    end
  end

  -- (1.0.1) quest items: where they dropped, which item starts which quest
  local drops = type(ns.db.learnedDrops) == "table" and ns.db.learnedDrops or {}
  for _, itemID in ipairs(SortedKeys(drops)) do
    local d = drops[itemID]
    if type(d) == "table" then
      local keys = {}
      for key in pairs(d) do
        if type(key) == "string" and key:match("^[co]%d+$") then keys[#keys + 1] = key end
      end
      table.sort(keys)
      for _, key in ipairs(keys) do
        local v = d[key]
        if type(v) == "table" and Int(v[1]) and v[1] > 0 and Pos(v[2], v[3], v[4]) then
          records[#records + 1] = ("D %d %s %s %d %d %s %s"):format(itemID, key:sub(1, 1), key:sub(2), v[1], v[2], Fmt(v[3]), Fmt(v[4]))
        end
      end
    end
  end
  local starts = type(ns.db.learnedItemStarts) == "table" and ns.db.learnedItemStarts or {}
  for _, itemID in ipairs(SortedKeys(starts)) do
    local q = starts[itemID]
    if Int(q) and q > 0 then records[#records + 1] = ("I %d %d -"):format(q, itemID) end
  end

  -- quests the server answered with "does not exist"
  for _, id in ipairs(ns.MissingQuestIDs and ns.MissingQuestIDs() or {}) do
    if Int(id) and id > 0 then records[#records + 1] = ("X %d"):format(id) end
  end

  return records
end

-- Returns text, number of records, truncated (number of records left out).
-- all: everything learned, without comparing with ATT.
function ns.BuildExport(all)
  local records = ns.ExportRecords(all)
  local lines = { ("QDX2 %s %s %s %s"):format(ns.Version(), Locale(), ns.Today(), all and "all" or "new") }
  local n = math.min(#records, MAX_LINES)
  for i = 1, n do lines[#lines + 1] = records[i] end
  local truncated = #records - n
  if truncated > 0 then lines[#lines + 1] = ("# truncated %d"):format(truncated) end
  lines[#lines + 1] = ("# records %d"):format(n)
  return table.concat(lines, "\n"), n, truncated
end

---------------------------------------------------------------------------
-- Window: read-only, multi-line edit box to copy from. Shared by the export,
-- the diagnostics, the dungeon list, the XP sources and the missing quests
-- (ns.ShowText).
--
-- (1.20) A real Style.Panel (kit version 2): wordmark title in the header
-- bar (drag there), the kit's close button, the note as a kit row in the
-- secondary colour and the text area as Style.Content of fixed height (a
-- quiet well with the scroll frame and the edit box inside). Position, lock
-- and size live for the session only, as before.
-- (1.24) No Blizzard template: Forever's client may not have
-- UIPanelScrollFrameTemplate (and its scroll bar runs Blizzard code). The
-- scroll frame is our own: mouse wheel, the text cursor stays in view, and a
-- thin bar on the right shows where you are. The close button is the kit's.
---------------------------------------------------------------------------
local frame, edit, content, noteRow
local text
local winState = { alpha = 0.95 } -- session only (not saved), a bit darker than panels
ns.windowParts = {} -- what the text window has (for /qd diag)

local W, BOX_H = 560, 340
local SCROLLBAR = 8 -- room for our thin position bar right of the scroll frame
local WHEEL_STEP = 3 -- lines per mouse wheel step

local function Num(v) return ns.Num(v) or 0 end

-- Scroll to offset (clamped to the scroll range).
local function ScrollTo(scroll, offset)
  local range = Num(scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange())
  if offset > range then offset = range end
  if offset < 0 then offset = 0 end
  scroll:SetVerticalScroll(offset)
  if scroll.qdUpdateBar then scroll.qdUpdateBar() end
end
ns.TextWindowScrollTo = function(offset) if frame and frame.scroll then ScrollTo(frame.scroll, offset) end end

local function Create()
  local Style, Look = ns.Style, ns.Look
  frame = Style.Panel("QuestdonExportFrame", UIParent, {
    title = Style.Wordmark("Quest", "don"),
    width = W,
    close = true,
    closeTooltip = { L["Close"], nil, L["Esc also closes the window."] },
    strata = "DIALOG",
    get = function(key) return winState[key] end,
    set = function(key, value) if key ~= "shown" then winState[key] = value end end,
    defaultPoint = { "CENTER", "CENTER", 0, 0 },
    onClose = function(p) p:Hide() end,
  })
  frame:EnableMouse(true) -- the window catches clicks instead of the world behind it
  frame.header = frame._header
  frame.close = frame:GetButton("close")
  ns.windowParts.closeButton = frame.close ~= nil

  noteRow = Style.Row(frame)

  -- the well: own frame with a quiet background, scroll frame and edit box inside
  local well = CreateFrame("Frame", nil, frame)
  well:EnableMouse(false)
  local wbg = well:CreateTexture(nil, "BACKGROUND", nil, 2)
  wbg:SetTexture("Interface\\Buttons\\WHITE8x8")
  wbg:SetAllPoints(well)
  Look.Tint(wbg, "barBackground")
  local pad = Style.SPACING.padX / 2

  local scroll = CreateFrame("ScrollFrame", nil, well) -- (1.24) no template
  ns.windowParts.scrollFrame = true
  scroll:SetPoint("TOPLEFT", well, "TOPLEFT", pad, -pad)
  scroll:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -SCROLLBAR - pad, pad)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", ns.Guard("text window", function(self, delta)
    local lineH
    if ChatFontNormal and ChatFontNormal.GetFont then
      local ok, _, size = pcall(ChatFontNormal.GetFont, ChatFontNormal)
      lineH = ok and ns.Num(size) or nil
    end
    local step = (lineH or 14) * WHEEL_STEP
    ScrollTo(self, Num(self:GetVerticalScroll()) - (ns.Num(delta) or 0) * step)
  end))

  -- thin position bar (our own textures, no slider template)
  local track = well:CreateTexture(nil, "ARTWORK")
  track:SetTexture("Interface\\Buttons\\WHITE8x8")
  track:SetPoint("TOPRIGHT", well, "TOPRIGHT", -pad / 2, -pad)
  track:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -pad / 2, pad)
  track:SetWidth(SCROLLBAR / 2)
  if track.SetVertexColor then track:SetVertexColor(1, 1, 1, 0.06) end
  local thumb = well:CreateTexture(nil, "OVERLAY")
  thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
  thumb:SetWidth(SCROLLBAR / 2)
  local ac = Style.COLORS.accent or { 0.25, 0.66, 0.96 }
  if thumb.SetVertexColor then thumb:SetVertexColor(ac[1], ac[2], ac[3], 0.6) end
  scroll.qdUpdateBar = function()
    local range = Num(scroll:GetVerticalScrollRange())
    local viewH = Num(scroll:GetHeight())
    if range <= 0 or viewH <= 0 then thumb:Hide() track:Hide() return end
    track:Show() thumb:Show()
    local h = math.max(16, viewH * viewH / (viewH + range))
    local y = (viewH - h) * Num(scroll:GetVerticalScroll()) / range
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", well, "TOPRIGHT", -pad / 2, -pad - y)
  end
  scroll:SetScript("OnScrollRangeChanged", ns.Guard("text window", function(self) ScrollTo(self, Num(self:GetVerticalScroll())) end))
  ns.windowParts.wheel = true

  edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(0)
  edit:SetFontObject(ChatFontNormal or "ChatFontNormal")
  edit:SetWidth(W - 2 * Style.SPACING.padX - 2 * pad - SCROLLBAR)
  local tc = Style.COLORS.textPrimary
  if edit.SetTextColor then edit:SetTextColor(tc[1], tc[2], tc[3]) end
  scroll:SetScrollChild(edit)
  -- Read-only: typing puts the text back and selects it again.
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput and text then self:SetText(text) self:HighlightText() end
  end)
  edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  -- (1.24) keep the text cursor in view (own code instead of Blizzard's
  -- ScrollingEdit helpers): y is the cursor's offset from the top (negative)
  edit:SetScript("OnCursorChanged", ns.Guard("text window", function(_, _, y, _, h)
    local top, height = -(ns.Num(y) or 0), ns.Num(h) or 0
    local offset, view = Num(scroll:GetVerticalScroll()), Num(scroll:GetHeight())
    if top < offset then
      ScrollTo(scroll, top)
    elseif view > 0 and top + height > offset + view then
      ScrollTo(scroll, top + height - view)
    end
  end))
  -- own panel: keep the kit's OnHide (stops a drag) and clear the focus too
  local kitOnHide = frame:GetScript("OnHide")
  frame:SetScript("OnHide", function(self)
    if kitOnHide then kitOnHide(self) end
    edit:ClearFocus()
  end)

  content = Style.Content(frame, well, BOX_H, { gapBefore = Style.SPACING.section })
  frame.well, frame.scroll, frame.edit, frame.content, frame.thumb = well, scroll, edit, content, thumb
  ns.windowParts.built = true

  -- Esc closes the window (list of frame names Blizzard hides on Esc).
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "QuestdonExportFrame") end
  frame:Hide()
end

-- For the tests: the text in the window.
function ns.ShowTextBody() return text end

-- Shows text to copy: heading, note above the box, the text itself.
-- If the window cannot be built on this client, the text goes to the chat.
function ns.ShowText(heading, note, body)
  if frame == nil and not pcall(Create) then frame = false end
  if not (frame and edit) then
    ns.Print(heading)
    for line in (body .. "\n"):gmatch("(.-)\n") do print(line) end
    return body
  end
  text = body
  frame:SetTitle(ns.Style.Wordmark("Quest", "don") .. ": " .. heading)
  noteRow:SetText(note or "", "textSecondary")
  edit:SetText(body)
  frame:Show()
  ScrollTo(frame.scroll, 0) -- (1.24) a new text starts at the top
  ns.Style.Relayout(frame)
  edit:SetFocus()
  edit:HighlightText()
  return body
end

function ns.OpenExport(all)
  local body, count, truncated = ns.BuildExport(all)
  local note
  if count == 0 then
    note = all and L["Nothing learned yet. Play a while with \"Learn quest locations\" switched on."]
      or L["Nothing new: everything Questdon learned is already in its data. /qd export all shows everything."]
  else
    note = L["%d entries. Ctrl+A selects all, Ctrl+C copies. Paste it into a new issue at %s (form \"Quest data\")."]:format(count, ISSUE_URL)
    if truncated > 0 then note = note .. " " .. L["Truncated: %d more entries left out."]:format(truncated) end
  end
  note = note .. " " .. L["Only numbers: no character, realm or guild names."]
  -- (1.0.1) the Forever beta does not load saved addon data: what is learned lasts one session
  if count > 0 then note = note .. " " .. L["Export before you log out: the beta forgets learned data at relog."] end
  return ns.ShowText(L["Export learned data"], note, body)
end
