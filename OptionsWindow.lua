local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (17.10., Daniel: "a Questdon options window: everything easy to find, several tabs and example pictures for the UI
-- parts, instead of the cog and /qd options going to Blizzard's settings"; "clear enough for the least experienced
-- player") Questdon's own options window. The options themselves stay in Options.lua (ns.OPTION_PAGES: name, tip,
-- kind, onChange, parent); here they are sorted into tabs. Each tab shows its main switches with their explanation
-- right under the name (no tooltip needed), the rarely used ones folded under "More settings", a picture of what the
-- tab changes on the right, a search over all options at the top and "Reset this tab" at the bottom. Blizzard's
-- settings only keep a button that opens this window.
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
-- (17.10., Daniel's pictures: "too much text, the style should be the quest book's") the quest book's look (its gold
-- framed navy window, cards and pills); the list shows only names and switches, the explanation of the option under
-- the mouse stands on the right
local W, H, HEADER_H, NAV_W, PREV_W, PAD, ROW_H = 900, 600, 42, 190, 270, 14, 40
local LIST_W = W - NAV_W - PREV_W - 4 * PAD
local TAB_ICONS = { map = "Interface\\Icons\\INV_Misc_Map_01", list = "Interface\\Icons\\INV_Misc_Note_01",
  accept = "Interface\\Icons\\INV_Letter_15", xp = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
  comfort = "Interface\\Icons\\INV_Misc_Bag_08", share = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  help = "Interface\\Icons\\INV_Misc_QuestionMark" }

-- the tabs: main switches first, the rest under "More settings"; buttons by their name; "tools" from the tool list
local TABS = {
  { key = "map", title = "Map", pic = "setup_questdon",
    text = "What Questdon shows on the world map and the minimap: quests you can pick up, the mobs and places of your quests, dungeon entrances.",
    -- (17.10., Daniel: "shouldn't map style be at the top under Map?") the start window's three map styles, first
    top = { "Map style and first steps" },
    -- (28.10.2026, Daniel: "die Optionen einfach teilweise zu viel ... Sollten wir einfach Sachen vorgeben") 89 switches
    -- down to 52, the hidden ones from 54 to 29; what we decide as developers is in ns.FIXED_OPTIONS (Options.lua)
    main = { "availablePins", "objectivePins", "objectiveIcons", "learnPins", "minimapPins", "dungeonPins", "servicePins" },
    more = { "showLowLevel", "lowLevelRange", "objectivePinsTrackedOnly", "objectiveAreas", "hideGamePOIs", "walkLines",
      "nameplateIcons", "dungeonPinsMinimap", "mapPinScale", "minimapPinScale", "minimapButton" } },
  { key = "list", title = "Quest list and arrow", pic = "opt_list",
    text = "Your quests in Questdon's list with a compass, and the arrow that leads you to the next objective.",
    -- (25.10., Daniel: "you cannot tell at first sight which option is for the list and which for the arrow") headers
    main = { "header:Quest list", "tracker",
      "header:Direction arrow", "wayMode", "arrowNext" },
    more = { "header:Quest list", "trackerPlain", "trackerHideGrey", "trackerScale",
      "header:Direction arrow", "arrowPlain", "arrowLocked", "arrowScale", "button:arrow",
      "header:Targeting and waypoints", "targetButton", "exportTomTom" } },
  { key = "accept", title = "Accept and turn in", pic = "opt_accept",
    text = "Quests taken and turned in for you, the reward that suits you marked, a sound when something is done.",
    main = { "autoAccept", "autoTurnIn", "suggestReward", "notifySound", "notifyText" },
    more = { "skipTrivial", "shareQuests", "unitTooltips", "questieFirst" } },
  { key = "xp", title = "XP bar", pic = "opt_xp",
    text = "Questdon's experience bar: XP, rested XP, finished quests, XP per hour and the time to the next level.",
    main = { "xpBar", "xpBarText", "hideBlizzardXP" },
    more = { "xpBarLocked", "xpBarScale", "xpBarWidth", "button:xp" } },
  { key = "comfort", title = "Comfort", pic = "opt_comfort",
    text = "Small helpers: sell junk and repair at a merchant, fast loot, a button for quest items, and the journal.",
    main = { "sellJunk", "autoRepair", "fastLoot", "questItemButton" },
    more = { "useGuildRepair", "journalShots", "journalMoments", "journalLevelShot" } },
  { key = "share", title = "Sharing and data", pic = "opt_share",
    text = "What Questdon learns while you play and shares with other Questdon players (only quest and map numbers, never names).",
    top = { "Only collect and share data" }, -- (25.10.) Setup.lua ns.SetDataOnly
    -- (28.10.2026, Daniel: "Für Questdon und uns ist das Sammeln immens wichtig ... ab Werk an ist ein Muss") on by default
    main = { "learnQuests", "shareLearned", "shareChannel" },
    tools = { "Export learned data", "Quests hidden as not offered", "Delete learned quest data" } },
  { key = "help", title = "Help", pic = "opt_help",
    text = "Positions, reports for bug reports and the dungeon quests as text.",
    status = true,
    tools = { "Reset positions", "Reset XP session", "Diagnostics", "Dungeon quests" } },
}
ns.OPTION_TABS = TABS -- (tests)

-- a slider's value as text: its own format, else percent (as Blizzard's settings showed it)
function ns.OptionValueText(item, v)
  if item.format then return item.format(v) end
  return ("%d%%"):format(v * 100 + 0.5)
end
---------------------------------------------------------------------------
-- (17.10., Daniel: "Leveldon's options in Questdon's look") one window per source: Questdon's own, and the one an
-- addon opens through QuestdonAPI.NewOptionsWindow (Leveldon). src = { frameName, wordmark, media, tabs, pages(),
-- tools(), db(), default(key), changed(key), T(text), status(), help(), buttonKey(section) }
---------------------------------------------------------------------------
local function NewWindow(src)
local Render, Preview
local frame, nav, child, scroll, preview, search
local rows, used = {}, 0
local current, showMore, hovered = "map", {}, nil
local K -- ns.BookKit (QuestBook.lua)
local TABS = src.tabs
local T = src.T or function(s) return L[s] end   -- the source's own texts (Leveldon translates its options itself)
local function DB() return src.db() or {} end

-- the options of Options.lua by key, the page buttons by the section they stand in
local items, buttons, tools
local function Index()
  if items then return end
  items, buttons, tools = {}, {}, {}
  for _, page in ipairs(src.pages() or {}) do
    local section
    for _, item in ipairs(page.items or {}) do
      if item.header then section = item.header end
      if item.key then items[item.key] = item end
      if item.kind == "button" and not item.key and src.buttonKey then
        buttons[src.buttonKey(section)] = item
      end
    end
  end
  for _, t in ipairs(src.tools and src.tools() or {}) do tools[t[1]] = t end
end
local function Item(key) Index() return items[key] end

local function Default(key) return src.default(key) end
local function ParentOff(item) return item.parent and not DB()[item.parent] end

---------------------------------------------------------------------------
-- rows: cards (options, tools), headings, plain text; one pool, made as needed
---------------------------------------------------------------------------
local function SmallButton(parent, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 22)
  K.Card(b, 0, 0)
  b.text = K.Text(b, 14, "textPrimary", "CENTER")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetText(label)
  b:SetScript("OnEnter", function(self) self:SetCardHover(true) end)
  b:SetScript("OnLeave", function(self) self:SetCardHover(false) end)
  return b
end
local function NewRow()
  local r = CreateFrame("Button", nil, child)
  r:SetWidth(LIST_W)
  K.Card(r, 2, 2)
  K.Clickable(r)
  r.name = K.Text(r, 13, "textPrimary", "LEFT")
  r.note = K.Text(r, 11, "textHint", "LEFT")
  r.long = K.Text(r, 12, "textSecondary", "LEFT")
  if r.long.SetWordWrap then r.long:SetWordWrap(true) end
  r.line = K.Tex(r, "BORDER", "divider")
  r.line:SetHeight(1)
  K.NewPill(r)
  r.minus, r.plus = SmallButton(r, "-"), SmallButton(r, "+")
  r.value = K.Text(r, 13, "textPrimary", "CENTER")
  r.btn = CreateFrame("Button", nil, r)
  r.btn:SetSize(118, 24)
  K.Card(r.btn, 0, 0)
  r.btn:SetCardLook("accent", "accent", 0.30, "accent", 0.8)
  r.btn.text = K.Text(r.btn, 12, "textPrimary", "CENTER")
  r.btn.text:SetPoint("CENTER", r.btn, "CENTER", 0, 0)
  r.btn:SetScript("OnEnter", function(self) self:SetCardHover(true) end)
  r.btn:SetScript("OnLeave", function(self) self:SetCardLook("accent", "accent", 0.30, "accent", 0.8) end)
  -- the explanation on the right while the mouse is on the row
  local enter, leave = r:GetScript("OnEnter"), r:GetScript("OnLeave")
  r:SetScript("OnEnter", function(self) if enter then enter(self) end if self.item then hovered = self.item Preview() end end)
  r:SetScript("OnLeave", function(self) if leave then leave(self) end end)
  return r
end

local y = 0
local function Take(card)
  used = used + 1
  local r = rows[used]
  if not r then r = NewRow() rows[used] = r end
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
  r.name:ClearAllPoints() r.note:ClearAllPoints() r.long:ClearAllPoints()
  r.name:SetText("") r.note:SetText("") r.long:SetText("")
  r.name:Show() r.note:Hide() r.long:Hide() r.line:Hide()
  K.SetPill(r, nil)
  r.minus:Hide() r.plus:Hide() r.value:Hide() r.btn:Hide()
  r.cardFill:SetShown(card)
  if r.cardEdge then r.cardEdge:SetShown(card) end
  for _, t in ipairs(r.cardLines or {}) do t:SetShown(card) end
  r.onClick, r.item, r.optKey = nil, nil, nil
  r:SetAlpha(1)
  r:Show()
  return r
end
local function Place(r, h) r:SetHeight(h) y = y + h end
local function Height(fs) return (fs.GetStringHeight and ns.Num(fs:GetStringHeight())) or 12 end

local function HeaderRow(text, color)
  local r = Take(false)
  r.name:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 6, 8)
  r.name:SetText(text)
  K.SetColor(r.name, color or "gold")
  -- (26.10., Daniel: "- W..." and "Qu..." cut) the rows come from a pool: an option's name left its narrow width
  -- (Fit) on the row, and a long heading on that row was cut with "...". Fit resets size and width first.
  K.Fit(r.name, LIST_W - 12, r)
  r.line:Show()
  r.line:ClearAllPoints()
  r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 6, 3)
  r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -6, 3)
  Place(r, 30)
  return r
end
local function TextRow(text, color)
  local r = Take(false)
  r.name:Hide()
  r.long:Show()
  r.long:SetWidth(LIST_W - 12)
  r.long:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -4)
  r.long:SetText(text)
  K.SetColor(r.long, color or "textSecondary")
  Place(r, Height(r.long) + 10)
  return r
end

-- an option: one card with its name and the switch (a pill "on"/"off"), the value with - and +, or a button
local function OptionRow(key, indent)
  local item = key:sub(1, 7) == "button:" and buttons[key] or items[key]
  if not item then return end
  local r = Take(true)
  r.item, r.optKey = item, key
  local x = 14 + (indent and 22 or 0)
  r.cardFill:ClearAllPoints()
  r.cardFill:SetPoint("TOPLEFT", r, "TOPLEFT", (indent and 22 or 0) + 2, -2)
  r.cardFill:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -2, 2)
  K.SetColor(r.name, "textPrimary")
  r.name:SetPoint("LEFT", r, "LEFT", x, 0)
  r.name:SetText(T(item.name))
  local blocker = item.blockedBy and item.blockedBy()
  local off = ParentOff(item) or blocker
  local room = LIST_W - x - 20
  if item.kind == "slider" then
    local v = tonumber(DB()[key]) or tonumber(Default(key)) or item.min or 0
    local lo, hi, step = item.min or 0, item.max or 1, item.step or 0.05
    r.plus:Show() r.minus:Show() r.value:Show()
    r.plus:ClearAllPoints() r.minus:ClearAllPoints() r.value:ClearAllPoints()
    r.plus:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    r.value:SetPoint("RIGHT", r.plus, "LEFT", -6, 0)
    r.value:SetWidth(52)
    r.value:SetText(ns.OptionValueText(item, v))
    r.minus:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    local function Set(nv)
      if ParentOff(item) then return end
      nv = math.max(lo, math.min(hi, math.floor((nv - lo) / step + 0.5) * step + lo))
      DB()[key] = nv
      if src.changed then src.changed(key) end
      Render()
    end
    r.minus:SetScript("OnClick", ns.Guard("options", function() Set(v - step) end))
    r.plus:SetScript("OnClick", ns.Guard("options", function() Set(v + step) end))
    room = room - 130
  elseif item.kind == "choice" then
    -- (29.10.2026, round 6) one of a few values: the pill shows it, a click moves on to the next
    local i = item.get and item.get() or 1
    local why = item.status and item.status()
    room = room - K.SetPill(r, why or T(item.choices[i]), why and "warning" or "good", 130)
    if not off then
      r.onClick = function()
        item.set(i % #item.choices + 1)
        Render()
      end
    end
  elseif item.kind == "button" then
    r.btn:Show() r.btn:ClearAllPoints()
    r.btn:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    r.btn.text:SetText(item.button and T(item.button) or L["Open"])
    r.btn:SetScript("OnClick", ns.Guard("options", function() if item.onClick then item.onClick() end Render() end))
    room = room - 130
  else
    local on = DB()[key] and true or false
    -- (25.10.) item.status: a short word instead of "on" while something else does the job (Leveldon's compass)
    local why = on and item.status and item.status()
    room = room - K.SetPill(r, why or (on and L["on"] or L["off"]), why and "warning" or (on and "good" or "textHint"), 80)
    if not off then
      r.onClick = function()
        DB()[key] = not DB()[key]
        if src.changed then src.changed(key) end
        Render()
      end
    end
  end
  K.Fit(r.name, room, r)
  if off then r:SetAlpha(0.45) end
  Place(r, ROW_H)
  return r
end

local function ToolRow(name)
  local t = tools[name]
  if not t then return end
  local r = Take(true)
  r.item = { name = t[1], tip = t[4] }
  K.SetColor(r.name, "textPrimary")
  r.name:SetPoint("LEFT", r, "LEFT", 14, 0)
  r.name:SetText(T(t[1]))
  r.btn:Show() r.btn:ClearAllPoints()
  r.btn:SetPoint("RIGHT", r, "RIGHT", -10, 0)
  r.btn.text:SetText(T(t[2]))
  r.btn:SetScript("OnClick", ns.Guard("options", function() t[3]() Render() end))
  K.Fit(r.name, LIST_W - 160, r)
  Place(r, ROW_H)
  return r
end

-- an option and the ones that hang on it (parent) right under it, indented
-- a tab's list may hold "header:<text>" entries between the keys: they are not settings
local function CountKeys(list)
  local n = 0
  for _, k in ipairs(list) do if k:sub(1, 7) ~= "header:" then n = n + 1 end end
  return n
end
local function Options(keys)
  local inList, done, kids = {}, {}, {}
  for _, k in ipairs(keys) do inList[k] = true end
  for _, k in ipairs(keys) do
    local it = items[k]
    if it and it.parent and inList[it.parent] then
      kids[it.parent] = kids[it.parent] or {}
      table.insert(kids[it.parent], k)
    end
  end
  for _, k in ipairs(keys) do
    local it = items[k]
    if k:sub(1, 7) == "header:" then
      -- (25.10., Daniel: "you cannot tell at first sight which option is for the list and which for the arrow")
      HeaderRow(T(k:sub(8)))
    elseif not done[k] and not (it and it.parent and inList[it.parent]) then
      done[k] = true
      OptionRow(k)
      for _, c in ipairs(kids[k] or {}) do if not done[c] then done[c] = true OptionRow(c, true) end end
    end
  end
end

---------------------------------------------------------------------------
-- the list of the current tab, or the search results
---------------------------------------------------------------------------
local function Matches(item, q)
  local function Has(s) return s and T(s) and T(s):lower():find(q, 1, true) ~= nil end
  return Has(item.name) or Has(item.tip)
end
local function TabOf(key) for _, t in ipairs(TABS) do if t.key == key then return t end end end
local query = ""

Render = function()
  if not frame then return end
  Index()
  used, y = 0, 0
  local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if q ~= "" then
    local n = 0
    for _, tab in ipairs(TABS) do
      local hits, th = {}, {}
      for _, list in ipairs({ tab.main or {}, tab.more or {} }) do
        for _, k in ipairs(list) do local it = items[k] or buttons[k] if it and Matches(it, q) then hits[#hits + 1] = k end end
      end
      for _, name in ipairs(tab.top or {}) do local t = tools[name] if t and Matches({ name = t[1], tip = t[4] }, q) then th[#th + 1] = name end end
      for _, name in ipairs(tab.tools or {}) do local t = tools[name] if t and Matches({ name = t[1], tip = t[4] }, q) then th[#th + 1] = name end end
      if #hits + #th > 0 then
        HeaderRow(T(tab.title))
        for _, k in ipairs(hits) do OptionRow(k) end
        for _, name in ipairs(th) do ToolRow(name) end
        n = n + #hits + #th
      end
    end
    if n == 0 then TextRow(L["Nothing found. Try another word."], "textHint") end
  else
    local tab = TabOf(current) or TABS[1]
    if tab.status and src.status then
      HeaderRow(L["Status"])
      for _, line in ipairs(src.status()) do TextRow(line, "textPrimary") end
    end
    for _, name in ipairs(tab.top or {}) do ToolRow(name) end
    if tab.main then Options(tab.main) end
    if tab.more and #tab.more > 0 then
      local r = HeaderRow((showMore[tab.key] and "- " or "+ ") .. L["More settings"] .. (" (%d)"):format(CountKeys(tab.more)), "accent")
      r.onClick = function() showMore[tab.key] = not showMore[tab.key] Render() end
      if showMore[tab.key] then Options(tab.more) end
    end
    if tab.tools then
      HeaderRow(L["Tools"])
      for _, name in ipairs(tab.tools) do ToolRow(name) end
    end
    if tab.status then
      HeaderRow(L["Commands"])
      TextRow(src.help and src.help() or "", "textSecondary")
    end
    if tab.main then
      local r = HeaderRow(L["Reset this tab"], "textHint")
      r.line:Hide()
      r.onClick = function()
        if ns.Confirm(src.frameName .. ":tab:" .. tab.key, L["Click again within 5 seconds to put this tab's settings back to their defaults."]) then
          for _, list in ipairs({ tab.main or {}, tab.more or {} }) do
            for _, k in ipairs(list) do
              if items[k] and items[k].key then DB()[k] = Default(k) if src.changed then src.changed(k) end end
            end
          end
          Render()
        end
      end
    end
  end
  for i = used + 1, #rows do rows[i]:Hide() end
  child:SetHeight(math.max(1, y))
  for _, b in ipairs(nav or {}) do
    local on = b.tab.key == current and q == ""
    b.mark:SetShown(on)
    if on then b:SetCardLook("card", "cardLow", 0.95, "gold", 0.9) else b:SetCardLook(nil, nil, 0.6) end
    K.SetColor(b.text, on and "goldLight" or "textSecondary")
  end
  Preview()
  if scroll and scroll.qdUpdateBar then scroll.qdUpdateBar() end
end

Preview = function()
  if not preview then return end
  local tab = TabOf(current) or TABS[1]
  local it = hovered
  preview.pic:SetTexture(src.media .. ((it and it.pic) or tab.pic))
  preview.title:SetText(it and T(it.name) or T(tab.title))
  local text = it and it.tip and T(it.tip) or T(tab.text)
  if it and it.blockedBy and it.blockedBy() then
    text = L["%s already does this, so it is off here."]:format(it.blockedBy()) .. "\n\n" .. text
  elseif it and it.status and DB()[it.key] and it.status() then
    text = L["%s shows the compass now, so the arrow and the list's compass stay aside. Close its window or switch off its compass to see them."]:format(it.status()) .. "\n\n" .. text
  elseif it and ParentOff(it) then
    local p = items[it.parent]
    text = L["Needs: %s"]:format(p and T(p.name) or it.parent) .. "\n\n" .. text
  end
  preview.text:SetText(text)
end

---------------------------------------------------------------------------
-- the window (the quest book's look)
---------------------------------------------------------------------------
local function NavButton(parent, tab, i)
  local b = CreateFrame("Button", nil, parent)
  b.tab = tab
  b:SetSize(NAV_W, 40)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -(HEADER_H + PAD + (i - 1) * 44))
  K.Card(b, 0, 0)
  b.icon = K.Icon(b, 22, tab.icon or TAB_ICONS[tab.key], "ARTWORK")
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b.icon:SetPoint("LEFT", b, "LEFT", 10, 0)
  b.text = K.Text(b, 13, "textSecondary", "LEFT")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
  b.text:SetText(T(tab.title))
  K.Fit(b.text, NAV_W - 50, b)
  b.mark = K.Tex(b, "OVERLAY", "goldLight")
  b.mark:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -8)
  b.mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 8)
  b.mark:SetWidth(2)
  b:SetScript("OnEnter", function(self) self:SetCardHover(true) end)
  b:SetScript("OnLeave", function() Render() end)
  b:SetScript("OnClick", ns.Guard("options", function(self)
    current, hovered, query = self.tab.key, nil, ""
    if search then search:SetText("") if search.edit then search.edit:ClearFocus() end end
    if scroll then scroll:SetVerticalScroll(0) end
    Render()
  end))
  return b
end

local function Create()
  K = ns.BookKit
  frame = CreateFrame("Frame", src.frameName, UIParent)
  frame:SetSize(W, H)
  frame:SetFrameStrata("HIGH")
  if frame.SetToplevel then frame:SetToplevel(true) end
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
  local bg = K.Tex(frame, "BACKGROUND")
  bg:SetAllPoints(frame)
  K.Gradient(bg, "VERTICAL", "backgroundLow", 0.97, "background", 0.97)
  K.Border(frame, "gold", 0.95)
  local inner = CreateFrame("Frame", nil, frame)
  inner:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
  inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
  K.Border(inner, "goldDark", 0.9)
  -- header: title, drag, close
  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:SetHeight(HEADER_H)
  local hbg = K.Tex(header, "BACKGROUND")
  hbg:SetAllPoints(header)
  K.Gradient(hbg, "VERTICAL", "background", 0.0, "header", 0.85)
  local hline = K.Tex(header, "BORDER", "gold", 0.7)
  hline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 0) hline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 0) hline:SetHeight(1)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() frame:StartMoving() end)
  header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  local title = K.Text(header, 15, "textPrimary", "LEFT")
  title:SetPoint("LEFT", header, "LEFT", 14, 0)
  title:SetText(src.wordmark)
  local sub = K.Text(header, 12, "textSecondary", "LEFT")
  sub:SetPoint("LEFT", title, "RIGHT", 10, 0)
  sub:SetText(L["Options"])
  local close = ns.Style.IconButton(header, "close")
  close:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  close:SetTooltip(L["Close"])
  close:SetOnClick(function() frame:Hide() end)
  -- search in the header
  search = K.EditBox(header, L["Search all options"], function(text) query = text or "" hovered = nil Render() end, 200)
  search:SetSize(260, 24)
  search:SetPoint("RIGHT", close, "LEFT", -18, 0)

  nav = {}
  for i, tab in ipairs(TABS) do nav[i] = NavButton(frame, tab, i) end

  -- the list
  scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + NAV_W + PAD, -(HEADER_H + PAD))
  scroll:SetSize(LIST_W, H - HEADER_H - 2 * PAD)
  if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
  scroll:EnableMouseWheel(true)
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(LIST_W, 1)
  scroll:SetScrollChild(child)
  local thumb = K.Tex(frame, "OVERLAY", "gold", 0.6)
  thumb:SetWidth(3)
  scroll.qdUpdateBar = function()
    local range = ns.Num(scroll:GetVerticalScrollRange()) or 0
    local viewH = ns.Num(scroll:GetHeight()) or 0
    if range <= 0 or viewH <= 0 then thumb:Hide() return end
    thumb:Show()
    local h = math.max(16, viewH * viewH / (viewH + range))
    local pos = (viewH - h) * (ns.Num(scroll:GetVerticalScroll()) or 0) / range
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -pos)
  end
  scroll:SetScript("OnMouseWheel", ns.Guard("options", function(self, delta)
    local range = ns.Num(self:GetVerticalScrollRange()) or 0
    local v = (ns.Num(self:GetVerticalScroll()) or 0) - (ns.Num(delta) or 0) * 60
    self:SetVerticalScroll(math.max(0, math.min(range, v)))
    self.qdUpdateBar()
  end))
  scroll:SetScript("OnScrollRangeChanged", function(self) self.qdUpdateBar() end)

  -- the picture and the explanation on the right, a card
  preview = CreateFrame("Frame", nil, frame)
  preview:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(HEADER_H + PAD))
  preview:SetSize(PREV_W, H - HEADER_H - 2 * PAD)
  K.Card(preview, 0, 0)
  preview.pic = preview:CreateTexture(nil, "ARTWORK")
  preview.pic:SetSize(PREV_W - 24, (PREV_W - 24) / 2)
  preview.pic:SetPoint("TOP", preview, "TOP", 0, -12)
  preview.title = K.Text(preview, 15, "goldLight", "LEFT")
  preview.title:SetPoint("TOPLEFT", preview.pic, "BOTTOMLEFT", 0, -14)
  preview.title:SetWidth(PREV_W - 24)
  if preview.title.SetWordWrap then preview.title:SetWordWrap(true) end
  preview.text = K.Text(preview, 12, "textSecondary", "LEFT")
  preview.text:SetPoint("TOPLEFT", preview.title, "BOTTOMLEFT", 0, -10)
  preview.text:SetWidth(PREV_W - 24)
  if preview.text.SetWordWrap then preview.text:SetWordWrap(true) end
  if preview.text.SetJustifyV then preview.text:SetJustifyV("TOP") end

  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, src.frameName) end
  frame:Hide()
end

-- tab: optional tab key to open on
local function Open(tab)
  if not frame then Create() end
  if tab and TabOf(tab) then current = tab end
  hovered = nil
  frame:Show()
  if frame.Raise then frame:Raise() end
  Render()
end
local function Toggle()
  if frame and frame:IsShown() then frame:Hide() else Open() end
end
return {
  Open = Open, Toggle = Toggle, Render = Render, Preview = Preview, Item = Item,
  Frame = function() return frame end,
  Rows = function() local out = {} for i = 1, used do out[i] = rows[i] end return out end,
  Search = function(text) query = text or "" Render() end,
}
end

-- Questdon's own window (Options.lua's pages and tools, ns.db)
local QD = NewWindow({
  frameName = "QuestdonOptions", wordmark = ns.Style.Wordmark("Quest", "don"), media = MEDIA, tabs = TABS,
  pages = function() return ns.OPTION_PAGES end, tools = function() return ns.OPTION_TOOLS end,
  db = function() return ns.db end, default = function(key) return ns.defaults and ns.defaults[key] end,
  changed = function(key) if ns.OptionChanged then ns.OptionChanged(key) end end,
  T = function(s) return L[s] end,
  status = function() return ns.OptionStatus and ns.OptionStatus() or {} end, help = function() return ns.HELP end,
  buttonKey = function(section) return (section == "XP bar") and "button:xp" or "button:arrow" end,
})
ns.NewOptionsWindow = NewWindow
function ns.OptionItem(key) return QD.Item(key) end
function ns.RenderOptions() return QD.Render() end
function ns.RefreshOptionsPreview() return QD.Preview() end
function ns.OpenOptionsWindow(tab) return QD.Open(tab) end
function ns.ToggleOptionsWindow() return QD.Toggle() end
function ns.OptionsWindowFrame() return QD.Frame() end -- (tests)
function ns.OptionsWindowRows() return QD.Rows() end -- (tests)
function ns.OptionsSearch(text) return QD.Search(text) end -- (tests)
