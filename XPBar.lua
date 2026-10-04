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
local function Hours(h) return ("%d:%02d h"):format(math.floor(h), math.floor(h % 1 * 60)) end

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
  local parts = { L["Level %d"]:format(d.level) .. Style.Colorize(": ", "textSecondary")
    .. Fmt(d.cur) .. Style.Colorize(" / ", "textSecondary") .. Fmt(d.max) .. " " .. Style.Colorize("(" .. Style.Percent(d.pct) .. ")", "textSecondary") }
  if d.questXP > 0 then
    local after = d.levelAfter > d.level and L[" -> level %d"]:format(d.levelAfter) or ""
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

function ns.UpdateXPBar()
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

-- Options (Appearance page)
function ns.ApplyXPBarLook()
  if not bar then return end
  Style.CombatFade(bar, ns.db.xpBarCombatFade)
  ns.UpdateXPBar()
end

function ns.ToggleXPBar()
  ns.db.xpBar = not ns.db.xpBar
  ns.UpdateXPBar()
end

-- (1.23) Batched with the other quest displays (Core.lua, 0.5 s).
ns.RegisterRefresh("xpbar", function() ns.UpdateXPBar() end)
local function Queue() ns.QueueRefresh("xpbar") end

ns.OnInit(function()
  Create()
  ns.NewTicker(10, ns.UpdateXPBar) -- XP/h changes over time
end)
ns.On("PLAYER_ENTERING_WORLD", Queue)
ns.On("PLAYER_XP_UPDATE", Queue)
ns.On("PLAYER_LEVEL_UP", Queue)
ns.On("UPDATE_EXHAUSTION", Queue)
ns.On("QUEST_LOG_UPDATE", Queue)
