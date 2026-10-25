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
local W, CARD_W, CARD_H, PIC_W, PIC_H = 720, 212, 214, 196, 98
local frame, cards, switchRows = nil, {}, {}

-- the three map styles: the option values each one sets
-- (17.10., Daniel: "with the game's map picked the game's areas were gone anyway; three choices: the game's own
-- without anything of ours, the new one with symbols, the one with dots")
-- (18.10., Daniel: "only the game's map" without Questdon's turn-in "?" too) learnPins is that "?"
local ON_MAP = { availablePins = true, objectivePins = true, walkLines = true, dungeonPins = true, dungeonPinsMinimap = true, learnPins = true }
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
      objectiveIcons = false, objectiveAreas = false, hideGamePOIs = false } },
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

local function Refresh()
  local cur = ns.SetupStyle()
  for _, c in ipairs(cards) do
    local on = c.style.key == cur
    c.ring:SetShown(on)
    c.title:SetTextColor(on and 1 or 0.92, on and 0.82 or 0.92, on and 0 or 0.92)
  end
  for _, r in ipairs(switchRows) do
    local on = ns.db[r.item.key] and true or false
    if r.item.dataOnly then on = ns.DataOnly() end
    r:SetValue(on and L["on"] or L["off"], on and "good" or "textHint")
  end
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
  dungeonPins = false, dungeonPinsMinimap = false, learnPins = false, hideGamePOIs = false, unitTooltips = false,
  -- windows: quest list, arrow, XP bar, quest item and target buttons
  tracker = false, arrow = false, arrowNext = false, pathDots = false, arrowCorpse = false, xpBar = false,
  ownRepBar = false, questItemButton = false, targetButton = false, exportBlizzardWaypoint = false, exportTomTom = false,
  -- automation, hints and sounds
  autoAccept = false, autoTurnIn = false, autoPickBest = false, highlightBest = false, suggestReward = false,
  chainHint = false, shareQuests = false, dungeonHint = false, notifySound = false, notifyText = false,
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
  Refresh()
end
ns.SetupToggle = ToggleSwitch -- (tests)

local function Card(parent, style, x)
  local c = CreateFrame("Button", nil, parent)
  c.style = style
  c:SetSize(CARD_W, CARD_H)
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
  local bg = c:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  bg:SetAllPoints(c)
  bg:SetVertexColor(1, 1, 1, 0.05)
  c.hover = c:CreateTexture(nil, "BACKGROUND", nil, 1)
  c.hover:SetTexture("Interface\\Buttons\\WHITE8x8")
  c.hover:SetAllPoints(c)
  c.hover:SetVertexColor(1, 1, 1, 0.06)
  c.hover:Hide()
  -- the chosen card: a frame in the accent colour
  c.ring = CreateFrame("Frame", nil, c)
  c.ring:SetAllPoints(c)
  local ac = ns.Style.COLORS.accent or { 0.25, 0.66, 0.96 }
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
      { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
    local t = c.ring:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8x8")
    t:SetVertexColor(ac[1], ac[2], ac[3], 1)
    t:SetPoint(side[1], c.ring, side[1], 0, 0)
    t:SetPoint(side[2], c.ring, side[2], 0, 0)
    if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
  end
  c.ring:Hide()
  c.pic = c:CreateTexture(nil, "ARTWORK")
  c.pic:SetSize(PIC_W, PIC_H)
  c.pic:SetPoint("TOP", c, "TOP", 0, -8)
  c.pic:SetTexture(MEDIA .. style.pic)
  if c.pic.SetTexCoord then c.pic:SetTexCoord(0, 1, 0, 1) end
  c.title = ns.Look.Font(c, "GameFontNormal", "textPrimary")
  c.title:SetPoint("TOPLEFT", c.pic, "BOTTOMLEFT", 0, -8)
  c.title:SetText(L[style.title])
  c.text = ns.Look.Font(c, "GameFontHighlightSmall", "textSecondary")
  c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
  c.text:SetWidth(PIC_W)
  c.text:SetJustifyH("LEFT")
  if c.text.SetWordWrap then c.text:SetWordWrap(true) end
  c.text:SetText(L[style.text])
  c:SetScript("OnEnter", function(self) self.hover:Show() end)
  c:SetScript("OnLeave", function(self) self.hover:Hide() end)
  c:SetScript("OnClick", ns.Guard("setup", function(self) ns.ApplySetupStyle(self.style.key) end))
  return c
end

local function Create()
  local Style = ns.Style
  frame = Style.Panel("QuestdonSetup", UIParent, {
    title = Style.Wordmark("Quest", "don"),
    width = W,
    close = true,
    closeTooltip = { L["Close"], nil, L["Esc also closes the window."] },
    strata = "DIALOG",
    get = function() return nil end,
    set = function() end,
    defaultPoint = { "CENTER", "CENTER", 0, 40 },
    onClose = function(p) p:Hide() end,
  })
  frame:EnableMouse(true)
  local intro = Style.Row(frame)
  intro:SetText(L["Welcome! How should Questdon show your quests on the world map?"], "textPrimary")
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetSize(W - 2 * Style.SPACING.padX, CARD_H)
  local gap = (W - 2 * Style.SPACING.padX - #STYLES * CARD_W) / (#STYLES - 1)
  for i, st in ipairs(STYLES) do cards[i] = Card(holder, st, (i - 1) * (CARD_W + gap)) end
  Style.Content(frame, holder, CARD_H, { gapBefore = Style.SPACING.section })
  Style.Header(frame, L["Also useful"])
  for _, item in ipairs(SWITCHES) do
    local r = Style.Row(frame)
    r.item = item
    r:SetText(L[item.name], "textPrimary")
    r:SetOnClick(ns.Guard("setup", function(self) ToggleSwitch(self.item) end))
    switchRows[#switchRows + 1] = r
  end
  local done = Style.Row(frame)
  done:SetGapBefore(Style.SPACING.section)
  done:SetText(L["Done"], "accent")
  done:SetValue(L["Everything can be changed later with /qd."], "textHint")
  done:SetOnClick(ns.Guard("setup", function() frame:Hide() end))
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "QuestdonSetup") end
  frame:Hide()
end

function ns.OpenSetup()
  if InCombatLockdown() then ns.Print(L["Options cannot be opened in combat."]) return end
  if not frame then Create() end
  ns.db.setupVersion = SETUP_VERSION
  Refresh()
  frame:Show()
  if ns.Style.Relayout then ns.Style.Relayout(frame) end
end
function ns.SetupFrame() return frame end -- (tests)

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
