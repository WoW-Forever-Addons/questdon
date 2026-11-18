local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (17.10., Daniel: "an onboarding for Questdon: a window at the start where you choose whether you want Blizzard's
-- map or ours, with example pictures") Shown once per account (setupVersion), after the first login with this
-- version, out of combat; /qd setup and the button in the options open it again. Two cards to click (Questdon's map:
-- symbols, groups and areas, the game's markers hidden; the game's map: its markers and areas stay, Questdon adds
-- dots), four switches for what new players look for, "Done". Nothing changes before a card or a switch is clicked.
---------------------------------------------------------------------------
local SETUP_VERSION = 1
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
-- (18.11.2026, Daniel for the UI launch: "ein Auswahlfenster fuer Questdons Questlist fuer alle ... gekoppelt mit PIN
-- Auswahlfenster fuer ganz ganz neue nutzer. fuer die alten nutzer nur die Questlist auswahl"; gewaehlt: alle einmal neu,
-- ein Fenster mit zwei Schritten, seine Bildschirmfotos als Vorschau) The start window has two steps now: 1 the map
-- style and switches, "Next", 2 the look of the quest list, "Back" and "Done". Players who saw the start window before
-- get only the look window (below). LOOK_ASK 2 asks everybody once more, also who answered in 1.7.0.
local LOOK_ASK = 2
local BuildLookCards, LookRefresh -- (below, used by both windows)
-- (12.11.2026, Daniel: "Das Anfangsfenster zur Auswahl sieht noch aus, wie die ersten Fenster von Questdon") both
-- windows of this file are DonCore Kit dialogs now (Kit.Dialog, Kit.Tile as the cards to click, Kit.OptionRow with
-- Kit.Toggle, Kit.Button), like the options and the quest book; nothing of the old Style panel is left here
local DonKit = LibStub("DonCore-1.0"):Get("Kit", 16)
local Kit = DonKit
local W, CARD_H, GAP = 880, 250, 8 -- (18.11.2026) 880 like the look window: both steps in one window
local frame, cards, switchRows = nil, {}, {}

-- (16.11.2026, Blizzard look as in Luredon 1.7.0) both dialogs take their blocks from Kit: DonCore's Kit, or with the
-- option blizzLook the game's own frame, buttons and switches (ns.LookKit, DonCore Blizz). A built dialog keeps its
-- blocks; one that fails to build in the game's look is hidden and built again with the Kit (diag line "dialog look").
local dialogLook = "not built yet"
local function BuildDialog(name, build, forget)
  local kit, blizz = DonKit, false
  if ns.LookKit then kit, blizz = ns.LookKit() end
  Kit = kit or DonKit
  if not blizz then dialogLook = "kit" return build(name) end
  local ok, err = pcall(build, name .. "Blizz")
  if ok then dialogLook = "blizzard" return end
  forget()
  Kit, dialogLook = DonKit, "kit (error: " .. tostring(err) .. ")"
  if ns.RecordError then ns.RecordError("dialog blizz look", err) end
  build(name)
end
function ns.DialogLook() return dialogLook end

-- a card to click (Kit.Tile: card colours, gold edge, selected state): an optional picture (2:1), a title, a text on
-- several lines. c:Place(w) lays it out.
local function ChoiceCard(parent, title, text, height, pic, onClick)
  local c = Kit.Tile(parent, { height = height, onClick = onClick })
  if pic then
    c.pic = c:CreateTexture(nil, "ARTWORK")
    c.pic:SetTexture(pic)
    if c.pic.SetTexCoord then c.pic:SetTexCoord(0, 1, 0, 1) end
  end
  c.title = Kit.Text(c, "row", Kit.C.title)
  c.title:SetText(title)
  c.text = Kit.Text(c, "sub", Kit.C.muted)
  if c.text.SetWordWrap then c.text:SetWordWrap(true) end
  if c.text.SetMaxLines then c.text:SetMaxLines(8) end
  if c.text.SetJustifyV then c.text:SetJustifyV("TOP") end
  c.text:SetText(text)
  function c:Place(w)
    self:Layout(w)
    local y = 10
    -- (12.11.2026) a drawn picture (the list look's preview): c.draw(card, width, y) lays it out and returns its height
    if self.draw then y = y + self.draw(self, w - 16, y) + 8 end
    if self.pic then
      local pw = w - 16
      self.pic:ClearAllPoints()
      self.pic:SetPoint("TOP", self, "TOP", 0, -y)
      self.pic:SetSize(pw, math.floor(pw / 2))
      y = y + math.floor(pw / 2) + 8
    end
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", 10, -y)
    Kit.Fit(self.title, w - 20)
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self, "TOPLEFT", 10, -(y + 18))
    self.text:SetWidth(w - 20)
  end
  return c
end

-- the three map styles: the option values each one sets
-- (17.10., Daniel: "with the game's map picked the game's areas were gone anyway; three choices: the game's own
-- without anything of ours, the new one with symbols, the one with dots")
-- (18.10., Daniel: "only the game's map" without Questdon's turn-in "?" too) learnPins is that "?"
local ON_MAP = { availablePins = true, objectivePins = true, walkLines = true, dungeonPins = true, dungeonPinsMinimap = true, learnPins = true,
  servicePins = true }
local function With(base, extra)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(extra) do t[k] = v end
  return t
end
local STYLES = {
  { key = "questdon", pic = "setup_questdon", title = "Questdon's symbols",
    text = "Symbols for quest mobs, loot and objects, close spots as one symbol with an area in the quest's colour. The game's round objective markers and blue areas are hidden; its ? and ! stay.",
    values = With(ON_MAP, { objectiveIcons = true, objectiveAreas = true, hideGamePOIs = true }) },
  { key = "dots", pic = "setup_blizzard", title = "Questdon's dots",
    text = "The game's own quest markers and blue areas stay. Questdon adds what the game does not show: available quests, turn-ins and quest mobs as small dots.",
    values = With(ON_MAP, { objectiveIcons = false, objectiveAreas = false, hideGamePOIs = false }) },
  { key = "game", pic = "setup_game", title = "Only the game's map",
    text = "Only the game's own quest markers and blue areas. Questdon draws nothing on the map and minimap; the quest list, the arrow and everything else stay.",
    values = { availablePins = false, objectivePins = false, walkLines = false, dungeonPins = false, dungeonPinsMinimap = false, learnPins = false,
      servicePins = false, objectiveIcons = false, objectiveAreas = false, hideGamePOIs = false } },
}
ns.SETUP_STYLES = STYLES -- (tests)

local SWITCHES = {
  { key = "arrow", name = "Direction arrow" },
  { key = "tracker", name = "Questdon's quest list" },
  { key = "autoAccept", also = "autoTurnIn", name = "Auto accept and turn in" },
  -- (18.10., Daniel: "a switch for the quest window see-through or not, see-through by default")
  { key = "trackerPlain", name = "Quest list see-through (no background and frame)" },
  -- (25.10.) everything off but learning and sharing (SetDataOnly)
  { key = "dataOnly", dataOnly = true, name = "Only collect and share data" },
}

-- which style the current settings are (nil: neither, the player mixed them)
function ns.SetupStyle()
  for _, s in ipairs(STYLES) do
    local same = true
    for k, v in pairs(s.values) do if (ns.db[k] and true or false) ~= v then same = false break end end
    if same then return s.key end
  end
  return nil
end

local StepButtons -- (below)
local function Refresh()
  local cur = ns.SetupStyle()
  for _, c in ipairs(cards) do c:SetSelected(c.style.key == cur) end
  for _, r in ipairs(switchRows) do r.control:Update() end
  if frame and frame.step == 1 and StepButtons then StepButtons() end -- the list switched off or on: "Done" or "Next"
end

function ns.ApplySetupStyle(key)
  for _, s in ipairs(STYLES) do
    if s.key == key then
      for k, v in pairs(s.values) do ns.db[k] = v end
      ns.db.setupStyle = key
      for k in pairs(s.values) do if ns.OptionChanged then ns.OptionChanged(k) end end
    end
  end
  if frame then Refresh() end
end

---------------------------------------------------------------------------
-- (25.10., Daniel: "can players only collect and share data?") One switch: everything Questdon shows or does by
-- itself goes off, learning and sharing stay on. The values before are kept (db.dataOnlyPrev) and come back with
-- the second click, so nobody has to find thirty options again. The minimap button stays as the way back.
---------------------------------------------------------------------------
local DATA_ONLY = {
  -- learning and sharing on
  learnQuests = true, shareLearned = true, shareChannel = true, shareTimes = true, minimapButton = true,
  -- map, minimap, nameplates, tooltips
  availablePins = false, objectivePins = false, walkLines = false, minimapPins = false, nameplateIcons = false,
  dungeonPins = false, dungeonPinsMinimap = false, learnPins = false, hideGamePOIs = false, unitTooltips = false, servicePins = false,
  -- windows: quest list, arrow, XP bar, quest item and target buttons
  tracker = false, arrow = false, arrowNext = false, pathDots = false, arrowCorpse = false, xpBar = false,
  ownRepBar = false, questItemButton = false, trackerItemButtons = false, targetButton = false, exportTomTom = false,
  -- automation, hints and sounds
  autoAccept = false, autoTurnIn = false, skipVendorGossip = false, highlightBest = false, suggestReward = false,
  chainHint = false, shareQuests = false, partyAnnounce = false, dungeonHint = false, notifySound = false, notifyText = false,
  sellJunk = false, autoRepair = false, fastLoot = false, journalShots = false, journalLevelShot = false,
}
ns.DATA_ONLY = DATA_ONLY -- (tests)

function ns.DataOnly() return ns.db and type(ns.db.dataOnlyPrev) == "table" or false end

-- on: true collect only, false settings back, nil the other way round
function ns.SetDataOnly(on)
  local db = ns.db
  if not db then return end
  if on == nil then on = not ns.DataOnly() end
  if on == ns.DataOnly() then return end
  local changed, restore = {}, nil
  if on then
    local prev = {}
    for k, v in pairs(DATA_ONLY) do
      prev[k] = db[k] == nil and "nil" or db[k]
      if db[k] ~= v then db[k] = v changed[#changed + 1] = k end
    end
    db.dataOnlyPrev = prev
    db.arrowAuto = nil
  else
    restore = db.dataOnlyPrev
    for k, v in pairs(db.dataOnlyPrev) do
      if v == "nil" then v = nil end
      if DATA_ONLY[k] ~= nil and db[k] ~= v then db[k] = v changed[#changed + 1] = k end
    end
    db.dataOnlyPrev = nil
    if db.tracker ~= false then db.trackerShown = true end
  end
  table.sort(changed)
  if ns.OptionChanged then for _, k in ipairs(changed) do ns.OptionChanged(k) end end
  -- the list's switch moves the arrow by itself (SyncArrowWithList): the player's own arrow value wins, and with
  -- collecting only the arrow stays off although the list is gone
  if on then db.arrow, db.arrowAuto = false, nil end
  if restore and restore.arrow ~= nil then
    if restore.arrow == "nil" then db.arrow = nil else db.arrow = restore.arrow end
  end
  if ns.RefreshMinimapButton then ns.SafeCall("data only", ns.RefreshMinimapButton) end
  if ns.UpdateXPBar then ns.SafeCall("data only", ns.UpdateXPBar) end
  if ns.ApplyArrow then ns.SafeCall("data only", ns.ApplyArrow) end
  if ns.UpdateTracker then ns.SafeCall("data only", ns.UpdateTracker, true) end
  if ns.RefreshPins then ns.SafeCall("data only", ns.RefreshPins) end
  ns.Print(on and L["Questdon only collects and shares data now. /qd collect brings your settings back."]
    or L["Your Questdon settings are back."])
  if frame then Refresh() end
end

local function ToggleSwitch(item)
  if item.dataOnly then ns.SetDataOnly() Refresh() return end
  local v = not ns.db[item.key]
  ns.db[item.key] = v
  if item.also then ns.db[item.also] = v end
  if ns.OptionChanged then
    ns.OptionChanged(item.key)
    if item.also then ns.OptionChanged(item.also) end
  end
  -- (12.11.2026) the options show this switch as the choice "Look of the quest list" now (trackerLook): applied here
  if item.key == "trackerPlain" and ns.ApplyTrackerChrome then ns.ApplyTrackerChrome() end
  Refresh()
end
ns.SetupToggle = ToggleSwitch -- (tests)

-- the hint left of a dialog's buttons
local function FootHint(d, text)
  local fs = Kit.Text(d, "sub", Kit.C.quiet)
  fs:SetText(text)
  fs:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 18)
  Kit.Fit(fs, math.max(40, d:BodyWidth() - 140))
  return fs
end

-- (18.11.2026) the list is on and shown: then the start window has its second step (the look of the list)
local function ListOn()
  return ns.db and ns.db.tracker ~= false and not ns.DataOnly()
end
local stepCards = {} -- the look cards of step 2
local ShowStep
StepButtons = function()
  if not frame then return end
  local hide = function(d) d:Hide() end
  if frame.step == 2 then
    frame:SetButtons({ { text = L["Back"], kind = "secondary", onClick = function() ShowStep(1) end },
      { text = L["Done"], kind = "primary", onClick = hide } })
  elseif ListOn() then
    frame:SetButtons({ { text = L["Next"], kind = "primary", onClick = function() ShowStep(2) end } })
  else
    frame:SetButtons({ { text = L["Done"], kind = "primary", onClick = hide } })
  end
  frame:SetBodySize(frame.bw, frame.bodyH)
end
ShowStep = function(step)
  if not frame then return end
  if step == 2 and not ListOn() then step = 1 end
  frame.step = step
  if step == 1 then frame.page1:Show() frame.page2:Hide() else frame.page1:Hide() frame.page2:Show() end
  if frame.SetTitle then frame:SetTitle("Questdon  " .. string.format(L["Step %d of %d"], step, 2)) end
  if step == 2 then
    ns.db.listLookAsked = LOOK_ASK
    for _, c in ipairs(stepCards) do if c._w and c.redraw then c.redraw(c, c._w) end end
    if LookRefresh then LookRefresh() end
  end
  StepButtons()
  if frame.hint then
    frame.hint:SetText(step == 1 and L["Everything can be changed later with /qd."] or L["You find this later under /qd, tab Look."])
  end
end
ns.SetupShowStep = function(step) if ShowStep then ShowStep(step) end end -- (tests)

local function Create(name)
  frame = Kit.Dialog(name, { title = "Questdon", width = W, height = 300,
    onClose = function() if ns.ListLookMaybe then ns.After(0.5, ns.ListLookMaybe) end end })
  frame:SetButtons({ { text = L["Next"], kind = "primary", onClick = function(d) d:Hide() end } })
  local body, bw = frame.body, frame:BodyWidth()
  frame.bw = bw
  -- step 1: the map style and the switches
  local p1 = CreateFrame("Frame", nil, body)
  p1:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  frame.page1 = p1
  local intro = Kit.Text(p1, "row", Kit.C.title)
  intro:SetPoint("TOPLEFT", p1, "TOPLEFT", 0, 0)
  intro:SetText(L["Welcome! How should Questdon show your quests on the world map?"])
  Kit.Fit(intro, bw)
  local y = 26
  local cw = math.floor((bw - (#STYLES - 1) * GAP) / #STYLES)
  -- the picture is 2:1 over the card's width, the text keeps the room it had in the narrower window
  local ch = math.max(CARD_H, 10 + math.floor((cw - 16) / 2) + 8 + 18 + 106)
  for i, st in ipairs(STYLES) do
    local c = ChoiceCard(p1, L[st.title], L[st.text], ch, MEDIA .. st.pic, ns.Guard("setup", function() ns.ApplySetupStyle(st.key) end))
    c.style = st
    c:SetPoint("TOPLEFT", p1, "TOPLEFT", (i - 1) * (cw + GAP), -y)
    c:Place(cw)
    cards[i] = c
  end
  y = y + ch + 14
  local head = Kit.Text(p1, "sub", Kit.C.muted)
  head:SetPoint("TOPLEFT", p1, "TOPLEFT", 0, -y)
  head:SetText(Kit.Upper(L["Also useful"]))
  y = y + 20
  for _, item in ipairs(SWITCHES) do
    local toggle = Kit.Toggle(p1, {
      get = function()
        if item.dataOnly then return ns.DataOnly() end
        return ns.db[item.key] and true or false
      end,
      set = ns.Guard("setup", function() ToggleSwitch(item) end) })
    local r = Kit.OptionRow(p1, { label = L[item.name], control = toggle })
    r.item = item
    r:SetPoint("TOPLEFT", p1, "TOPLEFT", 0, -y)
    r:Layout(bw)
    y = y + (r:GetHeight() or 36)
    switchRows[#switchRows + 1] = r
  end
  local h1 = y + 4
  -- step 2: the look of the quest list, the same cards as the look window; centred in the same height, so the
  -- window and its buttons do not jump between the steps
  local p2 = CreateFrame("Frame", nil, body)
  local h2 = BuildLookCards(p2, bw, L["How should your quest list look?"], stepCards)
  local h = math.max(h1, h2)
  p1:SetSize(bw, h1)
  p2:SetSize(bw, h2)
  p2:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -math.floor((h - h2) / 2))
  frame.page2, frame.lookCards, frame.bodyH = p2, stepCards, h
  frame:SetBodySize(bw, h)
  frame.hint = FootHint(frame, L["Everything can be changed later with /qd."])
end

function ns.OpenSetup()
  if InCombatLockdown() then ns.Print(L["Options cannot be opened in combat."]) return end
  if not frame then BuildDialog("QuestdonSetup", Create, ns.ForgetSetupFrames) end
  ns.db.setupVersion = SETUP_VERSION
  -- (18.11.2026) with the list on, its look is asked in step 2 of this window: the look window does not come as well
  if ListOn() then ns.db.listLookAsked = LOOK_ASK end
  ShowStep(1)
  Refresh()
  frame:Show()
end
function ns.SetupFrame() return frame end -- (tests)
function ns.SetupParts() return cards, switchRows end -- (tests)
-- (16.11.2026) the start window built again (other look, or a build that failed half-way)
function ns.ForgetSetupFrames()
  if frame and frame.Hide then pcall(frame.Hide, frame) end
  frame = nil
  wipe(cards) wipe(switchRows) wipe(stepCards)
end

-- once per account, a few seconds after the first login with this version (not in combat: then after it)
local pending = false
local function Maybe()
  if not ns.db or (tonumber(ns.db.setupVersion) or 0) >= SETUP_VERSION then return end
  if InCombatLockdown() then pending = true return end
  pending = false
  ns.OpenSetup()
end
ns.On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
  if isLogin or isReload or isLogin == nil then ns.After(4, Maybe) end
end)
ns.On("PLAYER_REGEN_ENABLED", function() if pending then ns.After(1, Maybe) end end)
ns.SetupMaybe = Maybe -- (tests)

---------------------------------------------------------------------------
-- (12.11.2026, Daniel: "Zum Start der neuen Liste gerne ein Auswahlfeld, welche Liste man nehmen moechte, danach in den
-- Optionen"; gewaehlt: everybody once, a small window of its own) Which look the quest list shall have: Don, Don without
-- background, like the game (Tracker.lua ns.SetTrackerLook). Shown once per account (listLookAsked), after the start
-- window, out of combat, only while the list is on. A click changes the real list at once. (18.11.2026) Each card shows
-- Daniel's screenshot of the list in that look; LOOK_ASK 2 asks again, new players get it as step 2 of the start window.
---------------------------------------------------------------------------
-- (18.11.2026) pic: Daniel's screenshot of the real list in this look (Media/listlook_*.tga, 512x512, the top of the list
-- cut square); a look without pic gets the drawn preview below
-- (18.11.2026) in the order and with the names of the options (Tracker.lua ns.LOOK_ORDER): look is the saved number
local LOOKS = {
  { look = 1, title = "Questdon", pic = "listlook_don", text = "Questdon's own window with background and frame." },
  { look = 2, title = "Questdon, transparent", pic = "listlook_don_plain", text = "The same without background and frame: only text, compass and buttons." },
  { look = 4, title = "Blizzard", pic = "listlook_game_box", text = "Reads like the game's own quest list, on the game's dark box with its frame." }, -- (17.11.2026)
  { look = 3, title = "Blizzard, transparent", pic = "listlook_game", text = "The same without background and frame: plain text in the game's colours, the objectives under each quest." },
}
ns.LIST_LOOKS = LOOKS -- (tests)
local lookFrame, lookCards = nil, {}
-- (12.11.2026, Daniel: "iteriere ... das neue setup fenster der quesliste das wirkt noch so lieblos") three cards side by
-- side like the start window, each with a small quest list drawn in its look (two quests of your own log, over a strip of
-- "game world", so the see-through looks show what they are), the chosen one marked
-- (12.11.2026, Daniel's picture: "sieht jetzt nicht so gut aus") the band of "ground" cut through the text, the list sat
-- small in a corner, the mark hung loose: now one soft gradient as the world, the list fills the picture with three
-- quests, the mark sits in the picture's corner and the cards are as high as their content
local LOOK_W, LOOK_H, PREVIEW_H = 880, 272, 190 -- (17.11.2026) 880 for four cards; (18.11.2026) square pictures
local WORLD_TOP, WORLD_BOTTOM = { 0.20, 0.27, 0.31 }, { 0.09, 0.11, 0.10 }
local N_SAMPLES = 3
local DOTS = { { 0.25, 0.66, 0.96 }, { 0.96, 0.62, 0.20 } }
local GAME_GOLD, GAME_OPEN, GAME_DONE = { 1, 0.82, 0 }, { 0.8, 0.8, 0.8 }, { 0.5, 0.5, 0.5 }

-- Two quests to show: from the quest log, else two every client knows.
local function Samples()
  local out = {}
  for _, info in ipairs(ns.QuestLogEntries and ns.QuestLogEntries() or {}) do
    if #out >= N_SAMPLES then break end
    local title = type(info.title) == "string" and ns.Usable(info.title) and info.title ~= "" and info.title
    if title then
      local line, done
      for _, o in ipairs(ns.ClientObjectives and ns.ClientObjectives(info.questID) or {}) do
        if type(o) == "table" and type(o.text) == "string" and ns.Usable(o.text) and o.text ~= "" then
          line, done = o.text, ns.True(o.finished)
          break
        end
      end
      out[#out + 1] = { title = title, line = line, done = done }
    end
  end
  for _, spare in ipairs({ { id = 33, line = "5/8" }, { id = 7, line = "8/8", done = true }, { id = 15, line = "0/1" } }) do
    if #out < N_SAMPLES then out[#out + 1] = { title = ns.QuestTitle(spare.id), line = spare.line, done = spare.done } end
  end
  return out
end
ns.ListLookSamples = Samples -- (tests)

local function GameText(parent, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetTextColor(color[1], color[2], color[3], 1)
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
  return fs
end

-- The preview of look i (1 Don, 2 Don without background, 3 like the game) on a card; returns the card's draw function.
local function Preview(card, look)
  local pv = CreateFrame("Frame", nil, card)
  pv.look = look
  -- (18.11.2026) Daniel's screenshot of the list in this look
  local pic
  for _, l in ipairs(LOOKS) do if l.look == look then pic = l.pic end end
  if pic then
    Kit.Fill(pv, { 0, 0, 0, 1 })
    pv.shot = pv:CreateTexture(nil, "ARTWORK")
    pv.shot:SetTexture(MEDIA .. pic)
    pv.shot:SetPoint("TOPLEFT", pv, "TOPLEFT", 1, -1)
    pv.shot:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -1, 1)
    Kit.Border(pv, Kit.C.divider)
    card.preview = pv
    return function(self, w, top)
      pv:ClearAllPoints()
      pv:SetPoint("TOP", self, "TOP", 0, -top)
      pv:SetSize(w, PREVIEW_H)
      return PREVIEW_H
    end
  end
  -- the game world behind the list: one soft gradient, lighter on top
  pv.bg = Kit.Tex(pv, "BACKGROUND", WORLD_BOTTOM)
  pv.bg:SetAllPoints(pv)
  if pv.bg.SetGradient and type(CreateColor) == "function" then
    pcall(pv.bg.SetVertexColor, pv.bg, 1, 1, 1, 1)
    pcall(pv.bg.SetGradient, pv.bg, "VERTICAL", CreateColor(WORLD_BOTTOM[1], WORLD_BOTTOM[2], WORLD_BOTTOM[3], 1),
      CreateColor(WORLD_TOP[1], WORLD_TOP[2], WORLD_TOP[3], 1))
  end
  Kit.Border(pv, Kit.C.divider)
  -- the list itself fills the picture: a panel with head for "Don", only its texts for the other two
  pv.list = CreateFrame("Frame", nil, pv)
  if look == 1 then
    Kit.Fill(pv.list, Kit.C.window)
    Kit.Border(pv.list, Kit.C.gold)
    pv.headBg = Kit.Tex(pv.list, "BORDER", Kit.C.panel)
    pv.headBg:SetPoint("TOPLEFT", 1, -1) pv.headBg:SetPoint("TOPRIGHT", -1, -1)
    pv.headBg:SetHeight(18)
  end
  if look == 4 then -- (17.11.2026) the game look on the game's dark box with its frame
    Kit.Fill(pv.list, { 0.03, 0.03, 0.03, 0.85 })
    Kit.Border(pv.list, { 0.6, 0.55, 0.45 })
  end
  if look >= 3 then
    pv.head = GameText(pv.list, GAME_GOLD)
    pv.head:SetText(type(QUESTS_LABEL) == "string" and QUESTS_LABEL or L["Quests"])
  else
    pv.head = Kit.Text(pv.list, "sub", Kit.C.goldBright)
    pv.head:SetText("Questdon")
  end
  pv.rows = {}
  for i = 1, N_SAMPLES do
    local r = {}
    if look >= 3 then
      r.title = GameText(pv.list, GAME_GOLD)
      r.line = GameText(pv.list, GAME_OPEN)
    else
      r.dot = Kit.Tex(pv.list, "ARTWORK", DOTS[(i - 1) % #DOTS + 1])
      r.dot:SetSize(6, 6)
      r.title = Kit.Text(pv.list, "sub", Kit.C.title)
      r.line = Kit.Text(pv.list, "sub", Kit.C.muted)
    end
    pv.rows[i] = r
  end
  card.preview = pv
  return function(self, w, top)
    pv:ClearAllPoints()
    pv:SetPoint("TOP", self, "TOP", 0, -top)
    pv:SetSize(w, PREVIEW_H)
    local lw = w - 16
    pv.list:ClearAllPoints()
    pv.list:SetPoint("TOPLEFT", pv, "TOPLEFT", 8, -8)
    pv.list:SetSize(lw, PREVIEW_H - 16)
    local pad = 8
    pv.head:ClearAllPoints()
    pv.head:SetPoint("TOPLEFT", pv.list, "TOPLEFT", pad, -4)
    Kit.Fit(pv.head, lw - 2 * pad)
    local samples = Samples()
    local y = 24
    for i, r in ipairs(pv.rows) do
      local q = samples[i] or {}
      local x = pad
      if r.dot then
        r.dot:ClearAllPoints()
        r.dot:SetPoint("TOPLEFT", pv.list, "TOPLEFT", pad, -(y + 4))
        x = pad + 11
      end
      r.title:ClearAllPoints()
      r.title:SetPoint("TOPLEFT", pv.list, "TOPLEFT", x, -y)
      r.title:SetText(q.title or "")
      Kit.Fit(r.title, lw - x - pad)
      r.line:ClearAllPoints()
      r.line:SetPoint("TOPLEFT", pv.list, "TOPLEFT", x + (look >= 3 and 4 or 0), -(y + 13))
      r.line:SetText(q.line and ((look >= 3 and "- " or "") .. q.line) or "")
      if look >= 3 then
        local c = q.done and GAME_DONE or GAME_OPEN
        r.line:SetTextColor(c[1], c[2], c[3], 1)
      else
        Kit.TextColor(r.line, q.done and Kit.C.green or Kit.C.muted)
      end
      Kit.Fit(r.line, lw - x - pad - (look >= 3 and 4 or 0))
      y = y + 34
    end
    return PREVIEW_H
  end
end

LookRefresh = function()
  local cur = ns.TrackerLook and ns.TrackerLook() or 1
  for _, list in ipairs({ lookCards, stepCards }) do
    for _, c in ipairs(list) do
      c:SetSelected(c.look == cur)
      if c.mark then if c.look == cur then c.mark:Show() else c.mark:Hide() end end
    end
  end
end
-- lays a card out
local function LookPlace(c, w)
  c:Place(w)
  Kit.Fit(c.title, w - 20)
end
-- (18.11.2026) the four look cards with intro on parent (the look window, or step 2 of the start window) into list;
-- returns the height
BuildLookCards = function(parent, bw, introText, list)
  local intro = Kit.Text(parent, "row", Kit.C.title)
  intro:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  intro:SetText(introText)
  Kit.Fit(intro, bw)
  local sub = Kit.Text(parent, "sub", Kit.C.muted)
  sub:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -20)
  sub:SetText(L["Click one: the quest list changes at once, so you can compare."])
  Kit.Fit(sub, bw)
  local y = 44
  local cw = math.floor((bw - (#LOOKS - 1) * GAP) / #LOOKS)
  for i, look in ipairs(LOOKS) do
    local pick = ns.Guard("setup", function() if ns.SetTrackerLook then ns.SetTrackerLook(look.look) end LookRefresh() end)
    local c = ChoiceCard(parent, L[look.title], L[look.text], LOOK_H, nil, pick)
    c.pick, c.redraw, c.look = pick, LookPlace, look.look
    c.draw = Preview(c, look.look)
    -- the chosen look says so in its corner
    c.mark = Kit.Pill(c, L["Picked"], "ready")
    c.mark:SetPoint("BOTTOMRIGHT", c.preview, "BOTTOMRIGHT", -6, 6) -- in the picture's corner
    if c.mark.SetFrameLevel and c.preview.GetFrameLevel then c.mark:SetFrameLevel((c.preview:GetFrameLevel() or 1) + 5) end
    c.mark:Hide()
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", (i - 1) * (cw + GAP), -y)
    LookPlace(c, cw)
    list[i] = c
  end
  return y + LOOK_H + GAP
end
local function LookCreate(name)
  lookFrame = Kit.Dialog(name, { title = "Questdon", width = LOOK_W, height = 300 })
  lookFrame:SetButtons({ { text = L["Done"], kind = "primary", onClick = function(d) d:Hide() end } })
  local body, bw = lookFrame.body, lookFrame:BodyWidth()
  local y = BuildLookCards(body, bw, L["New: how should your quest list look?"], lookCards)
  lookFrame.cards = lookCards -- (tests)
  lookFrame:SetBodySize(bw, y)
  lookFrame.hint = FootHint(lookFrame, L["You find this later under /qd, tab Look."])
end
function ns.OpenListLook()
  if InCombatLockdown() then ns.Print(L["Options cannot be opened in combat."]) return end
  if not lookFrame then BuildDialog("QuestdonListLook", LookCreate, ns.ForgetListLookFrames) end
  ns.db.listLookAsked = LOOK_ASK
  for _, c in ipairs(lookCards) do if c._w then LookPlace(c, c._w) end end -- the previews with the log as it is now
  LookRefresh()
  lookFrame:Show()
end
function ns.ListLookFrame() return lookFrame end -- (tests)
function ns.ForgetListLookFrames()
  if lookFrame and lookFrame.Hide then pcall(lookFrame.Hide, lookFrame) end
  lookFrame = nil
  wipe(lookCards)
end
-- (16.11.2026) the option blizzLook changed: the dialogs are built in the other look when they open next (an open one
-- keeps its look until it is closed and opened again)
function ns.DialogsReset()
  if not (frame and frame:IsShown()) then ns.ForgetSetupFrames() end
  if not (lookFrame and lookFrame:IsShown()) then ns.ForgetListLookFrames() end
  if ns.WayBoxReset then ns.WayBoxReset() end
end
local lookPending = false
local function MaybeLook()
  local db = ns.db
  if not db or (tonumber(db.listLookAsked) or 0) >= LOOK_ASK then return end
  if db.tracker == false then return end -- the list is off: asked when it is on at a later login
  -- the start window first: this one comes when that is done and gone
  if (tonumber(db.setupVersion) or 0) < SETUP_VERSION or (frame and frame:IsShown()) then lookPending = true return end
  if InCombatLockdown() then lookPending = true return end
  lookPending = false
  ns.OpenListLook()
end
ns.ListLookMaybe = MaybeLook -- (tests)
ns.On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
  if isLogin or isReload or isLogin == nil then ns.After(6, MaybeLook) end
end)
ns.On("PLAYER_REGEN_ENABLED", function() if lookPending then ns.After(2, MaybeLook) end end)
