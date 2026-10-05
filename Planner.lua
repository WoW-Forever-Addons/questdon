local _, ns = ...
local L = ns.L

-- Classic XP needed per level (1-59). Used only for levels after the current one,
-- and only if the current level matches the client (Forever could change the curve).
local XP_TABLE = {
  400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
  8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
  25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
  50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
  95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
  153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

local function MaxLevel()
  local max = ns.Num(ns.Value(GetMaxLevelForPlayerExpansion)) or ns.Num(ns.Value(GetMaxPlayerLevel))
  return (max and max > 0) and max or 60
end

-- Unknown level (secret value): not at max, the XP functions then hide themselves.
function ns.AtMaxLevel()
  local level = ns.PlayerLevel()
  return level ~= nil and level >= MaxLevel()
end

-- XP of all completed quests in the log. Returns xp, count, unknownCount.
function ns.CompletedQuestXP()
  local xp, count, unknown = 0, 0, 0
  for _, info in ipairs(ns.QuestLogEntries()) do
    if ns.IsQuestComplete(info.questID) then
      count = count + 1
      local reward = ns.Num(ns.Value(GetQuestLogRewardXP, info.questID))
      if reward then xp = xp + reward else unknown = unknown + 1 end
    end
  end
  return xp, count, unknown
end

-- Level and progress after gaining `gain` XP.
-- Returns newLevel, fraction (0..1) into that level, exact (false if the curve had to be guessed).
-- Returns nil while the client hides the XP values (secret values).
function ns.LevelAfter(gain)
  local level, cur, max = ns.PlayerLevel(), ns.Num(ns.Value(UnitXP, "player")), ns.Num(ns.Value(UnitXPMax, "player"))
  if not (level and cur and max) or max <= 0 then return nil end
  gain = gain or 0
  local exact = XP_TABLE[level] == max
  local total = cur + gain
  if total < max then return level, total / max, true end
  if not exact then return level + 1, nil, false end
  total = total - max
  level = level + 1
  while level < MaxLevel() and XP_TABLE[level] and total >= XP_TABLE[level] do
    total = total - XP_TABLE[level]
    level = level + 1
  end
  if level >= MaxLevel() then return MaxLevel(), 0, true end
  return level, total / XP_TABLE[level], true
end

---------------------------------------------------------------------------
-- XP per hour (this session)
---------------------------------------------------------------------------
local session = { start = nil, gained = 0, lastXP = nil, lastMax = nil, lastLevel = nil }

-- Only plain numbers are kept: secret values (Midnight rules) are skipped.
local function Snapshot()
  local xp, max, level = ns.Num(ns.Value(UnitXP, "player")), ns.Num(ns.Value(UnitXPMax, "player")), ns.PlayerLevel()
  if xp and max and level then
    session.lastXP, session.lastMax, session.lastLevel = xp, max, level
  else
    session.lastXP, session.lastMax, session.lastLevel = nil, nil, nil
  end
end

ns.On("PLAYER_ENTERING_WORLD", function()
  if not session.lastXP then Snapshot() end
end)

ns.On("PLAYER_XP_UPDATE", function()
  local xp, level = ns.Num(ns.Value(UnitXP, "player")), ns.PlayerLevel()
  if session.lastXP and xp and level then
    local delta
    if level > session.lastLevel then
      delta = (session.lastMax - session.lastXP) + xp
    else
      delta = xp - session.lastXP
    end
    if delta > 0 then
      session.start = session.start or GetTime()
      session.gained = session.gained + delta
    end
  end
  Snapshot()
end)
ns.On("PLAYER_LEVEL_UP", function() ns.After(0.5, Snapshot) end)

-- (1.2) The session survives /reload and a quick relog (up to 15 minutes):
-- saved per character at logout, picked up again at login.
local KEEP_SECS = 900
local function Wall() return ns.Num(ns.Value(time)) end
ns.On("PLAYER_LOGOUT", function()
  local c, now, wall = ns.charDB, ns.Num(ns.Value(GetTime)), Wall()
  if not (c and now and wall) then return end
  if session.start then
    c.xpSession = { elapsed = now - session.start, gained = session.gained, savedAt = wall }
  else
    c.xpSession = nil
  end
end)
ns.OnInit(function()
  local c = ns.charDB
  local saved = c and type(c.xpSession) == "table" and c.xpSession
  if c then c.xpSession = nil end
  local wall, now = Wall(), ns.Num(ns.Value(GetTime))
  if not (saved and wall and now) then return end
  local age = wall - (tonumber(saved.savedAt) or 0)
  local elapsed, gained = tonumber(saved.elapsed), tonumber(saved.gained)
  if age >= 0 and age <= KEEP_SECS and elapsed and elapsed > 0 and gained and gained > 0 then
    -- the time away counts as session time (XP per hour stays honest)
    session.start, session.gained = now - elapsed - age, gained
  end
end)

function ns.XPPerHour()
  if not session.start then return nil end
  local elapsed = (ns.Num(ns.Value(GetTime)) or session.start) - session.start
  if elapsed < 120 then return nil end
  return session.gained / (elapsed / 3600)
end

function ns.ResetXPSession()
  session.start, session.gained = nil, 0
  Snapshot()
end

function ns.PrintPlanner()
  if ns.AtMaxLevel() then ns.Print(L["Maximum level reached: no XP forecast."]) return end
  local xp, count = ns.CompletedQuestXP()
  local level, fraction = ns.LevelAfter(xp)
  ns.Print(L["%d finished quests: +%s XP"]:format(count, BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp))
  if not level then return end
  if fraction then
    ns.Print(L["After turning in: level %d (%d%%)"]:format(level, fraction * 100))
  else
    ns.Print(L["After turning in: at least level %d"]:format(level))
  end
end
