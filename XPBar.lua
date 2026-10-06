local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Long XP bar (top centre by default), 1.19 in the family look: a dark flat
-- strip with a kit bar inside. Segments: accent = current XP, warning colour =
-- XP of finished quests in the log, accent at low alpha = rested XP. Nine
-- quiet ticks like Blizzard's ten segments. Text below in the kit colours.
---------------------------------------------------------------------------
local Style = ns.Style
local Look = ns.Look
local PAD = 2
local QUEST_ALPHA, REST_ALPHA = 0.85, 0.35
local bar

local function Fmt(n) return Style.Number(math.floor((n or 0) + 0.5)) end
local function Hours(h) return L["%d:%02d h"]:format(math.floor(h), math.floor(h % 1 * 60)) end

local function Scale()
  return Look.Clamp(ns.db.xpBarScale, Style.SCALE_MIN, Style.SCALE_MAX, 1.45)
end

local function SavePosition()
  local point, _, relPoint, x, y = bar:GetPoint(1)
  if point then ns.db.xpBarPos = { point, relPoint or point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
end

local function DefaultPosition()
  bar:ClearAllPoints()
  bar:SetPoint("TOP", UIParent, "TOP", 0, -24)
end

local function ApplyPosition()
  local p = ns.db.xpBarPos
  bar:ClearAllPoints()
  if type(p) == "table" and type(p[1]) == "string" and pcall(bar.SetPoint, bar, p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0) then return end
  DefaultPosition()
end

function ns.ResetXPBarPosition()
  ns.db.xpBarPos = nil
  if bar then DefaultPosition() end
end

-- Numbers shown on the bar and in its tooltip.
function ns.XPBarData()
  local cur, max, current = ns.Num(ns.Value(UnitXP, "player")), ns.Num(ns.Value(UnitXPMax, "player")), ns.PlayerLevel()
  if not (cur and max and current) or max <= 0 then return nil end
  local questXP, questCount = ns.CompletedQuestXP()
  local rested = ns.Num(ns.Value(GetXPExhaustion)) or 0
  local level, fraction = ns.LevelAfter(questXP)
  level = level or current
  local xph = ns.XPPerHour()
  local hours = xph and xph > 0 and (max - cur) / xph or nil
  return {
    level = current, cur = cur, max = max, pct = cur / max,
    questXP = questXP, questCount = questCount, rested = rested,
    levelAfter = level, fractionAfter = fraction, xph = xph, hours = hours,
  }
end

local SEP = Style.Colorize("  \194\183  ", "textHint")

local function Text(d)
  local parts = { L["Level %d"]:format(d.level) .. Style.Colorize(L[": "], "textSecondary")
    .. Fmt(d.cur) .. Style.Colorize(" / ", "textSecondary") .. Fmt(d.max) .. " " .. Style.Colorize("(" .. Style.Percent(d.pct) .. ")", "textSecondary") }
  if d.questXP > 0 then
    local after = d.levelAfter > d.level and L[" -> level %d"]:format(d.levelAfter) or ""
    -- (1.2) where in that level you land, like the window showed it before
    if d.fractionAfter then after = after .. " (" .. Style.Percent(d.fractionAfter) .. ")" end
    parts[#parts + 1] = Style.Colorize(L["Quests +%s"]:format(Fmt(d.questXP)) .. after, "warning")
  end
  if d.rested > 0 then
    parts[#parts + 1] = Style.Colorize(L["Rested %s"]:format(Fmt(d.rested)), "accent")
  end
  if d.xph then parts[#parts + 1] = L["%s XP/h"]:format(Fmt(d.xph)) end
  if d.hours then parts[#parts + 1] = L["Level in %s"]:format(Hours(d.hours)) end
  return table.concat(parts, SEP)
end
ns.XPBarText = Text

-- Ticks at tenths of the inner bar, in the background colour (quiet).
-- (1.23) only when the width or the pixel size changed (UpdateXPBar runs
-- after every XP and quest log batch).
local tickW, tickPx
local function PlaceTicks(width)
  local px = Look.Pixel(bar)
  if width == tickW and px == tickPx then return end
  tickW, tickPx = width, px
  local inner = (tonumber(width) or 0) - 2 * PAD
  for i, tick in ipairs(bar.ticks) do
    tick:ClearAllPoints()
    if inner > 0 then
      tick:SetPoint("TOPLEFT", bar.inner, "TOPLEFT", inner * i / 10, 0)
      tick:SetPoint("BOTTOMLEFT", bar.inner, "BOTTOMLEFT", inner * i / 10, 0)
      tick:SetWidth(px)
      tick:Show()
    else
      tick:Hide()
    end
  end
end

local function Update()
  if not bar then return end
  local db = ns.db
  if not db.xpBar or ns.AtMaxLevel() then bar:Hide() return end
  local d = ns.XPBarData()
  if not d then bar:Hide() return end

  local w = Look.Clamp(db.xpBarWidth, 200, 1600, 600)
  local h = Look.Clamp(db.xpBarHeight, 6, 40, 14)
  bar:SetSize(w, h)
  bar:SetScale(Scale())
  bar.plate:SetAlpha(db.xpBarAlpha)
  bar.locked = db.xpBarLocked and true or false
  if not bar:IsShown() then bar:Show() end

  bar.inner:SetValues({ xp = d.pct, quest = d.questXP / d.max, rest = d.rested / d.max })
  PlaceTicks(w)
  if d.cur + d.questXP >= d.max then bar.overflow:Show() else bar.overflow:Hide() end

  if db.xpBarText then
    bar.text:SetText(Text(d))
    bar.text:Show()
  else
    bar.text:Hide()
  end
end

-- Tooltip in the family structure: title, key/value lines, hint last.
function ns.XPBarTooltip()
  local d = ns.XPBarData()
  if not d then return nil end
  local lines = {
    { L["Experience"], ("%s / %s"):format(Fmt(d.cur), Fmt(d.max)) },
    { L["Progress"], Style.Percent(d.pct) },
    { L["Still needed"], Fmt(d.max - d.cur) },
    { L["Finished quests (%d)"]:format(d.questCount), "+" .. Fmt(d.questXP), "warning" },
  }
  if d.fractionAfter then
    lines[#lines + 1] = { L["After turning in"], L["Level %d (%s)"]:format(d.levelAfter, Style.Percent(d.fractionAfter)), "good" }
  end
  lines[#lines + 1] = { L["Rested"], Fmt(d.rested), "accent" }
  lines[#lines + 1] = { L["XP per hour"], d.xph and Fmt(d.xph) or "-" }
  if d.hours then lines[#lines + 1] = { L["Time to next level"], Hours(d.hours) } end
  local hint = not ns.db.xpBarLocked and L["Drag to move. Lock it in the options."] or nil
  return L["Level %d"]:format(d.level), lines, hint
end

local function OnEnter(self)
  local title, lines, hint = ns.XPBarTooltip()
  if title then Style.Tooltip(self, title, lines, hint, "ANCHOR_BOTTOM") end
end

local function Create()
  bar = CreateFrame("Frame", "QuestdonXPBar", UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:SetClampedToScreen(true)
  bar:SetMovable(true)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function(self) if not ns.db.xpBarLocked then self:StartMoving() end end)
  bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
  bar:SetScript("OnEnter", ns.Guard("xp bar", OnEnter))
  bar:SetScript("OnLeave", function(self) Style.HideTooltip(self) end)
  bar:SetScript("OnSizeChanged", function(self, w) PlaceTicks(w) end)
  ApplyPosition()

  -- dark strip (no border of its own: the kit bar inside has the 1 px line)
  bar.plate = Look.Plate(bar)
  for _, t in ipairs(bar.plate.border) do t:Hide() end
  bar.plate.SetAlpha = function(plate, alpha)
    alpha = Look.Clamp(alpha, 0, 1, Style.DEFAULT_ALPHA)
    plate.alpha = alpha
    Look.Tint(plate.bg, "background", alpha)
  end

  bar.inner = Style.Bar(bar, { segments = {
    { key = "xp", color = "accent" },
    { key = "quest", color = "warning", alpha = QUEST_ALPHA },
    { key = "rest", color = "accent", alpha = REST_ALPHA },
  } })
  bar.inner:ClearAllPoints()
  bar.inner:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -PAD)
  bar.inner:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -PAD, PAD)

  bar.ticks = {}
  for i = 1, 9 do
    local tick = bar.inner:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface\\Buttons\\WHITE8x8")
    Look.Tint(tick, "background", 0.55)
    bar.ticks[i] = tick
  end

  bar.overflow = Look.Font(bar.inner, "GameFontNormalSmall", "warning")
  bar.overflow:SetPoint("RIGHT", bar.inner, "RIGHT", -4, 0)
  bar.overflow:SetText(">>")
  bar.overflow:Hide()

  bar.text = Look.Font(bar, "GameFontHighlightSmall", "textPrimary")
  bar.text:SetPoint("TOP", bar, "BOTTOM", 0, -4)

  bar:Hide()
  Style.CombatFade(bar, ns.db.xpBarCombatFade) -- (1.20) kit v2 for own frames
end

---------------------------------------------------------------------------
-- (1.3.2) Blizzard's own XP bar is hidden while ours is shown (option, on by default).
-- Only the alpha (and mouse) of the game's XP bar frames is changed, plus the frame texture
-- and dividers of the container that shows it. No hooks, no fields written into Blizzard's
-- tables, and which bar Blizzard shows and where the action bars sit stays Blizzard's own
-- code (that layout is protected; changing it from an addon would taint it). So the action
-- bars do not move; a tracked reputation bar stays visible.
-- Blizzard swaps bars between its two containers with a 0.5 s fade, so a light check every
-- half second follows it. The check compares the real alpha, so whatever sets the game's
-- bar visible again (fades, layout changes) is caught on the next pass.
---------------------------------------------------------------------------
local hiddenBy = setmetatable({}, { __mode = "k" }) -- Blizzard frame -> true while we hid it
local blizzHidden = false

local function XPIndex()
  local info = rawget(_G, "StatusTrackingBarInfo")
  local e = type(info) == "table" and type(info.BarsEnum) == "table" and info.BarsEnum.Experience
  return type(e) == "number" and e or 4
end

local function Alpha(frame)
  if type(frame.GetAlpha) ~= "function" then return nil end
  local ok, a = pcall(frame.GetAlpha, frame)
  return ok and a or nil
end

local function Fade(frame, hidden, mouse)
  if type(frame) ~= "table" then return end
  if hidden then
    local a = Alpha(frame)
    if not hiddenBy[frame] or (a and a > 0) then
      hiddenBy[frame] = true
      if frame.SetAlpha then pcall(frame.SetAlpha, frame, 0) end
      if mouse and frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
    end
  elseif hiddenBy[frame] then
    hiddenBy[frame] = nil
    if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
    if mouse and frame.EnableMouse then pcall(frame.EnableMouse, frame, true) end
  end
end

local function Dividers(c, hidden)
  local pool = c.HorizontalDividersPool
  if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
  local ok, iter, state, start = pcall(pool.EnumerateActive, pool)
  if ok and type(iter) == "function" then
    for d in iter, state, start do Fade(d, hidden) end
  end
end

-- true while the game's XP bar is hidden by Questdon (for /qd diag and the tests)
function ns.BlizzardXPHidden() return blizzHidden end

---------------------------------------------------------------------------
-- (1.3.2) The free place and the tracked reputation (Daniel 06.10.):
-- * Ornament (option, on by default): an ornate band (Alliance vehicle bar art) fills the
--   place of the hidden XP bar and joins the two end pieces. Own frame, strata LOW, so the
--   game's gryphons cover its ends.
-- * Own reputation bar (option, on by default): while a faction is tracked in the reputation
--   list, the game's reputation bar is made invisible like its XP bar (alpha and mouse only)
--   and Questdon's own bar sits exactly on it: the game's bar art, the tracked faction, and a
--   click opens the reputation list. Frame texture and dividers of that container stay.
-- Both are own frames, only anchored to the game's frames; nothing is set on those.
---------------------------------------------------------------------------
local rep
local REP_COLORS = { "Red", "Red", "Orange", "Yellow", "Green", "Green", "Green", "Green" }

local function RepIndex()
  local info = rawget(_G, "StatusTrackingBarInfo")
  local e = type(info) == "table" and type(info.BarsEnum) == "table" and info.BarsEnum.Reputation
  return type(e) == "number" and e or 1
end

-- One faction as a plain table, from the modern or the classic API.
local function FactionData(id)
  if type(id) ~= "number" or id <= 0 then return nil end
  local C = rawget(_G, "C_Reputation")
  if type(C) == "table" and type(C.GetFactionDataByID) == "function" then
    local ok, d = pcall(C.GetFactionDataByID, id)
    if ok and type(d) == "table" and type(d.name) == "string" and d.name ~= "" then
      return { id = id, name = d.name, reaction = d.reaction or 4, low = d.currentReactionThreshold or 0,
        high = d.nextReactionThreshold or 1, value = d.currentStanding or 0, header = d.isHeader and not d.isHeaderWithRep }
    end
  end
  local get = rawget(_G, "GetFactionInfoByID")
  if type(get) == "function" then
    local ok, name, _, standing, low, high, value, _, _, isHeader, _, hasRep = pcall(get, id)
    if ok and type(name) == "string" and name ~= "" then
      return { id = id, name = name, reaction = standing or 4, low = low or 0, high = high or 1, value = value or 0,
        header = isHeader and not hasRep }
    end
  end
  return nil
end

local function WatchedID()
  local C = rawget(_G, "C_Reputation")
  if type(C) == "table" and type(C.GetWatchedFactionData) == "function" then
    local ok, d = pcall(C.GetWatchedFactionData)
    return ok and type(d) == "table" and d.name and d.name ~= "" and d.factionID or nil
  end
  local get = rawget(_G, "GetWatchedFactionInfo")
  if type(get) == "function" then
    local ok, name, _, _, _, _, id = pcall(get)
    return ok and name and id or nil
  end
  return nil
end

local function RepText(d)
  local standing = rawget(_G, "FACTION_STANDING_LABEL" .. tostring(d.reaction)) or ""
  local span = d.high - d.low
  if d.reaction >= #REP_COLORS or span <= 0 then return d.name .. L[": "] .. standing end
  return d.name .. L[": "] .. standing .. "  " .. Fmt(d.value - d.low) .. " / " .. Fmt(span)
end

local function RepEnter(self)
  local d = FactionData(self.factionID)
  if not d then return end
  self.label:SetText(RepText(d))
  self.label:Show()
  Style.Tooltip(self, d.name, { RepText(d) }, L["Click: open the reputation list"], "ANCHOR_TOP")
end

local function RepClick()
  if InCombatLockdown and InCombatLockdown() then return end
  local toggle = rawget(_G, "ToggleCharacter")
  if type(toggle) == "function" then pcall(toggle, "ReputationFrame") end
end

local function CreateRep()
  rep = CreateFrame("Frame", "QuestdonRepBar", UIParent)
  rep:SetFrameStrata("LOW")
  rep:EnableMouse(true)
  rep.bg = rep:CreateTexture(nil, "BACKGROUND")
  rep.bg:SetAllPoints(rep)
  if not pcall(rep.bg.SetAtlas, rep.bg, "UI-HUD-ExperienceBar-Background") then
    rep.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    rep.bg:SetVertexColor(0, 0, 0, 0.6)
  end
  rep.fill = rep:CreateTexture(nil, "ARTWORK")
  rep.fill:SetPoint("TOPLEFT", rep, "TOPLEFT", 0, 0)
  rep.fill:SetPoint("BOTTOMLEFT", rep, "BOTTOMLEFT", 0, 0)
  rep.label = Look.Font(rep, "GameFontHighlightSmall", "textPrimary", "OVERLAY")
  rep.label:SetPoint("CENTER", rep, "CENTER", 0, 1)
  rep.label:Hide()
  rep:SetScript("OnEnter", ns.Guard("rep bar", RepEnter))
  rep:SetScript("OnLeave", function(self) self.label:Hide() Style.HideTooltip(self) end)
  rep:SetScript("OnMouseUp", ns.Guard("rep bar", RepClick))
  rep:SetScript("OnSizeChanged", function(self) self.fillDirty = true end)
  rep:Hide()
end

-- Shows faction `id` over the hidden game bar `target`, or hides it (target nil).
local function ShowRep(target, id)
  if not target then
    if rep then rep:Hide() end
    return false
  end
  local d = FactionData(id)
  if not d then
    if rep then rep:Hide() end
    return false
  end
  if not rep then CreateRep() end
  local anchor = type(target.StatusBar) == "table" and target.StatusBar or target
  if rep.anchor ~= anchor then
    rep:ClearAllPoints()
    rep:SetAllPoints(anchor)
    rep.anchor = anchor
  end
  local level = type(target.GetFrameLevel) == "function" and select(2, pcall(target.GetFrameLevel, target))
  if type(level) == "number" then rep:SetFrameLevel(level + 1) end
  if rep.factionID ~= d.id or rep.reaction ~= d.reaction then
    rep.factionID, rep.reaction = d.id, d.reaction
    local color = REP_COLORS[d.reaction] or "Green"
    local ok, set = pcall(rep.fill.SetAtlas, rep.fill, "UI-HUD-ExperienceBar-Fill-Reputation-Faction-" .. color)
    if not ok or set == false then
      local c = type(FACTION_BAR_COLORS) == "table" and FACTION_BAR_COLORS[d.reaction] or { r = 0, g = 0.6, b = 0.1 }
      rep.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
      rep.fill:SetVertexColor(c.r, c.g, c.b)
    end
  end
  local span = d.high - d.low
  local frac = (d.reaction >= #REP_COLORS or span <= 0) and 1 or math.min(1, math.max(0, (d.value - d.low) / span))
  local w = rep:GetWidth() or 0
  if frac <= 0 or w <= 0 then rep.fill:Hide() else rep.fill:SetWidth(w * frac) rep.fill:Show() end
  if rep.label:IsShown() then rep.label:SetText(RepText(d)) end
  rep:Show()
  return true
end

local art
-- Daniel 06.10.: the ornate copper band of the Alliance vehicle bar (its top border, the part
-- the game itself tiles as "_Border"). If the client lacks that file, the action bar's own
-- divider art is used instead.
local ART_FILE = "Interface\\PlayerActionBarAlt\\ALLIANCE"
local ART_TOP, ART_BOTTOM = 0.001953125, 0.07226563

local function CreateArt()
  art = CreateFrame("Frame", "QuestdonXPPlaceArt", UIParent)
  art:SetFrameStrata("LOW")
  local band = art:CreateTexture(nil, "ARTWORK")
  local ok, set = pcall(band.SetTexture, band, ART_FILE, true, false)
  if ok and set ~= false then
    band:SetTexCoord(0, 1, ART_TOP, ART_BOTTOM)
    if band.SetHorizTile then band:SetHorizTile(true) end
    band:SetAllPoints(art)
    art.band = band
    art:Hide()
    return
  end
  band:Hide()
  local function Piece(atlas)
    local t = art:CreateTexture(nil, "ARTWORK")
    local ok2, set2 = pcall(t.SetAtlas, t, atlas, false)
    if not ok2 or set2 == false then
      t:SetTexture("Interface\\Buttons\\WHITE8x8")
      t:SetVertexColor(0.45, 0.36, 0.2, 0.9)
    end
    return t
  end
  art.left = Piece("UI-HUD-ActionBar-Frame-Divider-Threeslice-EdgeLeft")
  art.right = Piece("UI-HUD-ActionBar-Frame-Divider-Threeslice-EdgeRight")
  art.center = Piece("_UI-HUD-ActionBar-Frame-Divider-Threeslice-Center")
  if art.center.SetHorizTile then art.center:SetHorizTile(true) end
  art.left:SetPoint("TOPLEFT") art.left:SetPoint("BOTTOMLEFT") art.left:SetWidth(12)
  art.right:SetPoint("TOPRIGHT") art.right:SetPoint("BOTTOMRIGHT") art.right:SetWidth(12)
  art.center:SetPoint("TOPLEFT", art.left, "TOPRIGHT")
  art.center:SetPoint("BOTTOMRIGHT", art.right, "BOTTOMLEFT")
  art:Hide()
end

-- Shows the strip over the game's container `c` (the one that holds the hidden XP bar), or hides it.
local function ShowArt(c)
  if not c then
    if art then art:Hide() end
    return false
  end
  if not art then CreateArt() end
  if art.anchor ~= c then
    art:ClearAllPoints()
    -- the band is a little taller than the game's bar, like a trim between the two rows
    local pad = art.band and 1.5 or -1.5
    art:SetPoint("TOPLEFT", c, "TOPLEFT", 0, pad)
    art:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, -pad)
    art.anchor = c
  end
  art:Show()
  return true
end

-- (for /qd diag and the tests)
function ns.RepBarState()
  return rep and rep:IsShown() and rep.factionID or nil, nil, rep
end
function ns.XPPlaceArtShown() return art and art:IsShown() and true or false, art end

-- The container that shows bar `index` and is on screen, and that bar.
local function Holder(mgr, index)
  for _, c in ipairs(mgr.barContainers) do
    local shown = type(c) == "table" and c.shownBarIndex == index
      and (type(c.IsShown) ~= "function" or c:IsShown())
    if shown and type(c.bars) == "table" and type(c.bars[index]) == "table" then return c, c.bars[index] end
  end
  return nil
end

function ns.ApplyBlizzardXP()
  local mgr = rawget(_G, "StatusTrackingBarManager")
  if type(mgr) ~= "table" or type(mgr.barContainers) ~= "table" then
    blizzHidden = false
    ShowRep(nil)
    ShowArt(nil)
    return
  end
  local xp, ri = XPIndex(), RepIndex()
  local hide = ns.db and ns.db.xpBar and ns.db.hideBlizzardXP ~= false and bar and bar:IsShown() and true or false
  local xpHolder = hide and Holder(mgr, xp) or nil
  ShowArt(xpHolder and ns.db.artInXPPlace ~= false and xpHolder or nil)
  -- the tracked faction in our own bar, on the game's reputation bar
  local watched = hide and ns.db.ownRepBar ~= false and WatchedID() or nil
  local repHolder, repBar
  if watched then repHolder, repBar = Holder(mgr, ri) end
  local ours = ShowRep(repBar, watched)
  for _, c in ipairs(mgr.barContainers) do
    if type(c) == "table" then
      local bars = type(c.bars) == "table" and c.bars or {}
      -- the XP bar of every container (Blizzard moves it between them)
      Fade(bars[xp], hide, true)
      -- the game's reputation bar where ours sits on it
      Fade(bars[ri], ours and c == repHolder, true)
      -- frame and dividers only where the XP bar is the shown one
      local here = hide and c.shownBarIndex == xp
      Fade(c.BarFrameTexture, here)
      Dividers(c, here)
    end
  end
  blizzHidden = hide
end

function ns.UpdateXPBar()
  Update()
  ns.ApplyBlizzardXP()
end

-- Options (Appearance page)
function ns.ApplyXPBarLook()
  if not bar then return end
  Style.CombatFade(bar, ns.db.xpBarCombatFade)
  ns.UpdateXPBar()
end

function ns.ToggleXPBar()
  ns.db.xpBar = not ns.db.xpBar
  ns.UpdateXPBar()
  if ns.UpdatePanel then ns.UpdatePanel() end -- (1.2) the window shows the XP lines while the bar is off
end

-- (1.23) Batched with the other quest displays (Core.lua, 0.5 s).
ns.RegisterRefresh("xpbar", function() ns.UpdateXPBar() end)
local function Queue() ns.QueueRefresh("xpbar") end

ns.OnInit(function()
  Create()
  ns.NewTicker(10, ns.UpdateXPBar) -- XP/h changes over time
  ns.NewTicker(0.5, function() if blizzHidden or (ns.db.hideBlizzardXP ~= false and bar and bar:IsShown()) then ns.ApplyBlizzardXP() end end)
end)
ns.On("UPDATE_FACTION", Queue)
ns.On("PLAYER_ENTERING_WORLD", Queue)
ns.On("PLAYER_XP_UPDATE", Queue)
ns.On("PLAYER_LEVEL_UP", Queue)
ns.On("UPDATE_EXHAUSTION", Queue)
ns.On("QUEST_LOG_UPDATE", Queue)
