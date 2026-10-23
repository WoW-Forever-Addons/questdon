local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- /qd xpcheck: where does the XP come from? Checks Forever's XP rules in the
-- game (dungeon mob XP, dungeon quest XP, food buffs, rested XP outdoors).
--
-- Only events, no per-frame work:
--   PLAYER_XP_UPDATE          measured gain (UnitXP delta, level-ups included)
--   CHAT_MSG_COMBAT_XP_GAIN   kill XP with rested bonus / group bonus (a chat
--                             event, not the combat log), parsed with the
--                             client's own COMBATLOG_XPGAIN_* format strings
--   QUEST_TURNED_IN           quest XP (questID, xpReward)
--   CHAT_MSG_SYSTEM / UI_INFO_MESSAGE   exploration XP (ERR_ZONE_EXPLORED_XP)
--   UPDATE_EXHAUSTION, PLAYER_UPDATE_RESTING   rested XP growth
-- What is left of the measured gain is "unassigned".
--
-- Stored account wide in QuestdonDB.xpcheck, capped. Only numbers: no mob,
-- zone, instance, quest, character or realm names. Secret values (Midnight
-- rules) skip the sample.
---------------------------------------------------------------------------
local MAX_KILLS, MAX_QUESTS, MAX_EXPLORE, MAX_REST = 300, 200, 50, 100
local MAX_AURA_IDS, MAX_AURAS_PER_KILL, MAX_AURA_SCAN = 60, 12, 40
local LINK_WINDOW = 1.5 -- seconds: chat line and XP bar change belong together

local DUNGEON_TAG = (Enum and Enum.QuestTag and ns.Num(Enum.QuestTag.Dungeon)) or 81

---------------------------------------------------------------------------
-- Client format strings -> Lua patterns
---------------------------------------------------------------------------
-- Roles per format argument (in argument order, positional %1$s respected):
--   name (dropped, never stored), xp, rest (signed rested bonus/penalty text),
--   label (dropped), group (+ bonus), raid (- penalty)
local FORMATS = {}
do
  local function Add(global, kind, roles) FORMATS[#FORMATS + 1] = { global = global, kind = kind, roles = roles } end
  Add("COMBATLOG_XPGAIN_FIRSTPERSON", "kill", { "name", "xp" })
  Add("COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "kill", { "name", "xp", "group" })
  Add("COMBATLOG_XPGAIN_FIRSTPERSON_RAID", "kill", { "name", "xp", "raid" })
  for _, n in ipairs({ 1, 2, 4, 5 }) do
    Add("COMBATLOG_XPGAIN_EXHAUSTION" .. n, "kill", { "name", "xp", "rest", "label" })
    Add("COMBATLOG_XPGAIN_EXHAUSTION" .. n .. "_GROUP", "kill", { "name", "xp", "rest", "label", "group" })
    Add("COMBATLOG_XPGAIN_EXHAUSTION" .. n .. "_RAID", "kill", { "name", "xp", "rest", "label", "raid" })
  end
  Add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", "unnamed", { "xp" })
  Add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP", "unnamed", { "xp", "group" })
  Add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID", "unnamed", { "xp", "raid" })
  Add("COMBATLOG_XPGAIN_QUEST", "unnamed", { "xp", "rest", "label" })
end
local EXPLORE = { global = "ERR_ZONE_EXPLORED_XP", kind = "explore", roles = { "name", "xp" } }

-- "%s dies, you gain %d experience." -> "^(.-) dies, you gain ([%-%+]?[%d%.,]+) experience%.$"
-- Returns pattern and the argument index of every capture, or nil.
local function ToPattern(fmt)
  if type(fmt) ~= "string" or not ns.Usable(fmt) or fmt == "" then return nil end
  local out, args, auto, i = { "^" }, {}, 0, 1
  while i <= #fmt do
    local c = fmt:sub(i, i)
    if c == "%" then
      local pos, conv, e = fmt:match("^%%(%d+)%$[%-%d%.]*([sdif])()", i)
      if not conv then conv, e = fmt:match("^%%[%-%d%.]*([sdif])()", i) end
      if conv then
        if pos then pos = tonumber(pos) else auto = auto + 1 pos = auto end
        args[#args + 1] = pos
        out[#out + 1] = conv == "s" and "(.-)" or "([%-%+]?[%d%.,]+)"
        i = e
      elseif fmt:sub(i + 1, i + 1) == "%" then
        out[#out + 1] = "%%"
        i = i + 2
      else
        return nil -- unknown conversion
      end
    else
      out[#out + 1] = c:find("[%^%$%(%)%.%[%]%*%+%-%?]") and ("%" .. c) or c
      i = i + 1
    end
  end
  out[#out + 1] = "$"
  return table.concat(out), args
end

local function ToNumber(s)
  if type(s) ~= "string" then return nil end
  local neg = s:find("^%s*%-") ~= nil
  local n = tonumber((s:gsub("[^%d]", "")))
  if not n then return nil end
  return neg and -n or n
end

-- Builds the parsers once from the client's global strings (missing ones are skipped).
local parsers, formatState
local function Compile(def)
  local ok, fmt = pcall(function() return _G[def.global] end)
  if not ok or fmt == nil then return nil, "missing" end
  local pattern, args = ToPattern(fmt)
  if not pattern then return nil, "unreadable" end
  local max = 0
  for _, a in ipairs(args) do if a > max then max = a end end
  if max ~= #def.roles then return nil, "mismatch" end
  return { global = def.global, kind = def.kind, roles = def.roles, pattern = pattern, args = args, len = #pattern }
end

local function Parsers()
  if parsers then return parsers end
  parsers, formatState = { chat = {} }, {}
  for _, def in ipairs(FORMATS) do
    local p, why = Compile(def)
    formatState[def.global] = p and "ok" or why
    if p then parsers.chat[#parsers.chat + 1] = p end
  end
  -- most specific (longest) first
  table.sort(parsers.chat, function(a, b) return a.len > b.len end)
  local p, why = Compile(EXPLORE)
  formatState[EXPLORE.global] = p and "ok" or why
  parsers.explore = p
  return parsers
end

-- Parses msg with one parser: table of role -> number (names dropped), or nil.
local function Parse(p, msg)
  local caps = { msg:match(p.pattern) }
  if #caps == 0 then return nil end
  local r = {}
  for k, argIndex in ipairs(p.args) do
    local role = p.roles[argIndex]
    if role == "xp" or role == "rest" or role == "group" or role == "raid" then
      r[role] = ToNumber(caps[k])
    end
  end
  if not r.xp or r.xp < 0 then return nil end
  return r
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local TOTAL_KEYS = { "delta", "kill", "killN", "rest", "group", "raid", "quest", "questN", "explore", "exploreN",
  "unnamed", "unnamedN", "restGain", "restGainResting", "secret" }

local function NewTotals()
  local t = {}
  for _, k in ipairs(TOTAL_KEYS) do t[k] = 0 end
  return t
end

local session = { tot = NewTotals(), formats = {}, killLink = { same = 0, diff = 0 }, questLink = { same = 0, diff = 0 } }

local function NewStore()
  return { v = 1, since = ns.Today and ns.Today() or "?", tot = NewTotals(), kills = {}, quests = {}, explores = {},
    rest = {}, auras = {}, auraCount = 0 }
end

local function Store()
  local s = ns.db and ns.db.xpcheck
  if type(s) ~= "table" or s.v ~= 1 then
    s = NewStore()
    if ns.db then ns.db.xpcheck = s end
  end
  for _, k in ipairs(TOTAL_KEYS) do if type(s.tot[k]) ~= "number" then s.tot[k] = 0 end end
  return s
end

local function Add(key, v)
  if not v or v == 0 then return end
  session.tot[key] = session.tot[key] + v
  local tot = Store().tot
  tot[key] = tot[key] + v
end

local function Push(list, item, cap)
  list[#list + 1] = item
  while #list > cap do table.remove(list, 1) end
end

---------------------------------------------------------------------------
-- Context
---------------------------------------------------------------------------
-- 0 open world, 1 dungeon, 2 raid, 3 other instance (battleground, scenario ...)
local function Place()
  if type(IsInInstance) ~= "function" then return 0, 0 end
  local ok, inInstance, kind = pcall(IsInInstance)
  if not ok or not ns.Usable(inInstance) or not inInstance then return 0, 0 end
  local place = 3
  if ns.Usable(kind) then
    if kind == "party" then place = 1 elseif kind == "raid" then place = 2 end
  end
  local map = 0
  if type(GetInstanceInfo) == "function" then
    local ok2, id = pcall(function() return select(8, GetInstanceInfo()) end)
    map = ok2 and ns.Num(id) or 0
  end
  return place, map
end

local function GroupSize()
  local n = ns.Num(ns.Value(GetNumGroupMembers)) or 0
  return n > 0 and n or 1
end

-- Rested pool: a number (nil from the client = 0), or nil if unknown or secret.
local function ReadPool()
  if type(GetXPExhaustion) ~= "function" then return nil end
  local ok, v = pcall(GetXPExhaustion)
  if not ok then return nil end
  if v == nil then return 0 end
  return ns.Num(v)
end

local function RestedPool() return ReadPool() or 0 end

local function ZoneMap()
  return ns.Num(ns.Value(C_Map and C_Map.GetBestMapForUnit, "player")) or 0
end

-- spellIDs of all helpful auras on the player (readable ones only, capped).
local function AuraIDs()
  local get = C_UnitAuras and (C_UnitAuras.GetAuraDataByIndex or C_UnitAuras.GetBuffDataByIndex)
  if type(get) ~= "function" then return nil end
  local ids, seen = {}, {}
  for i = 1, MAX_AURA_SCAN do
    local ok, aura = pcall(get, "player", i, "HELPFUL")
    if not ok or type(aura) ~= "table" then break end
    local id = ns.Num(aura.spellId)
    if id and id > 0 and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

-- Counts the auras of one kill (the counter keeps at most MAX_AURA_IDS spellIDs).
-- Returns the tracked ones as "id,id" for the kill sample.
local function CountAuras(ids, xp)
  if not ids or #ids == 0 then return nil end
  local s = Store()
  local kept = {}
  for _, id in ipairs(ids) do
    local c = s.auras[id]
    if not c and s.auraCount < MAX_AURA_IDS then
      c = { n = 0, x = 0 }
      s.auras[id] = c
      s.auraCount = s.auraCount + 1
    end
    if c then
      c.n, c.x = c.n + 1, c.x + xp
      if #kept < MAX_AURAS_PER_KILL then kept[#kept + 1] = id end
    end
  end
  return #kept > 0 and table.concat(kept, ",") or nil
end

---------------------------------------------------------------------------
-- Measured gain (UnitXP delta) and the link to the chat line / quest event
---------------------------------------------------------------------------
local last = {}          -- xp, max, level of the last reading
local lastDelta          -- { value, time, used }
local pendingKill, pendingQuest -- { value, time, sample }

local lastPool, lastPoolTime, lastResting -- rested pool and resting flag at the last reading

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end

local function Snapshot()
  local xp, max, level = ns.Num(ns.Value(UnitXP, "player")), ns.Num(ns.Value(UnitXPMax, "player")), ns.PlayerLevel()
  if xp and max and level then
    last.xp, last.max, last.level = xp, max, level
  else
    last.xp, last.max, last.level = nil, nil, nil
  end
end

local function Compare(link, observed, reported)
  if observed == reported then link.same = link.same + 1 else link.diff = link.diff + 1 end
end

-- A chat line or quest event and an XP bar change within LINK_WINDOW belong together.
local function LinkDelta(kind, value, sample)
  local now = Now()
  if lastDelta and not lastDelta.used and now - lastDelta.time <= LINK_WINDOW then
    lastDelta.used = true
    Compare(kind == "quest" and session.questLink or session.killLink, lastDelta.value, value)
    if sample then sample.obs = lastDelta.value end
    return
  end
  local p = { value = value, time = now, sample = sample }
  if kind == "quest" then pendingQuest = p else pendingKill = p end
end

local function OnXPUpdate(_, unit)
  if unit and unit ~= "player" then return end
  local xp, level = ns.Num(ns.Value(UnitXP, "player")), ns.PlayerLevel()
  if not (xp and level) then
    Add("secret", 1)
    Snapshot()
    return
  end
  if last.xp and last.level then
    local delta
    if level > last.level then
      delta = (last.max - last.xp) + xp -- XP to finish the old level plus XP into the new one
    elseif level == last.level then
      delta = xp - last.xp
    end
    -- kills use up rested XP: follow the pool without counting it as growth
    local pool = ReadPool()
    if pool then lastPool = pool end
    if delta and delta > 0 then
      Add("delta", delta)
      local now = Now()
      local p = (pendingQuest and now - pendingQuest.time <= LINK_WINDOW and pendingQuest)
        or (pendingKill and now - pendingKill.time <= LINK_WINDOW and pendingKill)
      if p then
        Compare(p == pendingQuest and session.questLink or session.killLink, delta, p.value)
        if p.sample then p.sample.obs = delta end
        if p == pendingQuest then pendingQuest = nil else pendingKill = nil end
        lastDelta = nil
      else
        lastDelta = { value = delta, time = now }
      end
    end
  end
  Snapshot()
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
local function OnChatXP(_, msg)
  if type(msg) ~= "string" or not ns.Usable(msg) then Add("secret", 1) return end
  for _, p in ipairs(Parsers().chat) do
    local r = Parse(p, msg)
    if r then
      session.formats[p.global] = (session.formats[p.global] or 0) + 1
      local rest, group, raid = r.rest or 0, r.group or 0, r.raid or 0
      if p.kind == "unnamed" then
        Add("unnamed", r.xp)
        Add("unnamedN", 1)
        return
      end
      Add("kill", r.xp)
      Add("killN", 1)
      Add("rest", rest)
      Add("group", group)
      Add("raid", raid)
      local level = ns.PlayerLevel()
      if not level then Add("secret", 1) return end
      local place, map = Place()
      local base = r.xp - rest - group + raid
      local sample = {
        x = r.xp, b = base, l = level, p = place, m = map, g = GroupSize(),
        r = rest ~= 0 and rest or nil, gb = group ~= 0 and group or nil, rp = raid ~= 0 and raid or nil,
        rs = RestedPool() > 0 and 1 or 0,
      }
      sample.a = CountAuras(AuraIDs(), base)
      Push(Store().kills, sample, MAX_KILLS)
      LinkDelta("kill", r.xp, sample)
      return
    end
  end
end

local lastExplore -- dedupe CHAT_MSG_SYSTEM and UI_INFO_MESSAGE of the same discovery
local function OnExplore(msg)
  if type(msg) ~= "string" or not ns.Usable(msg) then return end
  local p = Parsers().explore
  if not p then return end
  local r = Parse(p, msg)
  if not r then return end
  local now = Now()
  if lastExplore and lastExplore.xp == r.xp and now - lastExplore.time <= 2 then return end
  lastExplore = { xp = r.xp, time = now }
  Add("explore", r.xp)
  Add("exploreN", 1)
  local place = Place()
  Push(Store().explores, { x = r.xp, l = ns.PlayerLevel() or 0, p = place }, MAX_EXPLORE)
end

-- Quest tag from the client (tagID only, no names). Cached while the quest is in the log.
local tagCache = {}
local function QuestTag(questID)
  if tagCache[questID] ~= nil then return tagCache[questID] or nil end
  local tag
  local info = ns.Value(C_QuestLog and C_QuestLog.GetQuestTagInfo, questID)
  if type(info) == "table" then tag = ns.Num(info.tagID) end
  if not tag then
    local t = ns.Num(ns.Value(C_QuestLog and C_QuestLog.GetQuestType, questID))
    if t and t > 0 then tag = t end
  end
  if not tag then tag = ns.Num(ns.Value(GetQuestTagInfo, questID)) end
  if tag then tagCache[questID] = tag end
  return tag
end

local function CacheTag(questID)
  questID = ns.Num(questID)
  if questID and questID > 0 then QuestTag(questID) end
end

local function OnQuestTurnedIn(_, questID, xpReward)
  questID, xpReward = ns.Num(questID), ns.Num(xpReward)
  if not (questID and xpReward) then Add("secret", 1) return end
  if xpReward <= 0 then return end -- no XP (max level, repeatable without XP)
  Add("quest", xpReward)
  Add("questN", 1)
  local place, map = Place()
  local tag = QuestTag(questID)
  local q = ns.ATT_QUESTS and ns.ATT_QUESTS[questID]
  local sample = {
    q = questID, x = xpReward, l = ns.PlayerLevel() or 0, p = place, m = map, t = tag,
    ql = q and ns.Num(q[5]) or nil,
    -- (1.18) also quests the data files under a dungeon (most are turned in outside)
    d = (tag == DUNGEON_TAG or place == 1 or (ns.QuestDungeon and ns.QuestDungeon(questID))) and 1 or 0,
  }
  Push(Store().quests, sample, MAX_QUESTS)
  tagCache[questID] = nil
  LinkDelta("quest", xpReward, sample)
end

-- Rested XP: growth of the pool, with resting flag, place and zone map.
local function OnExhaustion()
  local pool = ReadPool()
  if not pool then return end -- secret or missing
  local now = Now()
  if lastPool and pool > lastPool then
    local resting = ns.True(ns.Value(IsResting)) and 1 or 0
    local place = Place()
    local gain = pool - lastPool
    Add("restGain", gain)
    if resting == 1 then Add("restGainResting", gain) end
    Push(Store().rest, { k = "gain", d = gain, s = math.floor(now - (lastPoolTime or now)), r = resting, p = place,
      m = ZoneMap(), l = ns.PlayerLevel() or 0 }, MAX_REST)
  end
  lastPool, lastPoolTime = pool, now
end

local function OnResting()
  local resting = ns.Value(IsResting)
  if resting == nil then return end
  resting = resting == true
  if resting and lastResting == false then
    local place = Place()
    Push(Store().rest, { k = "on", p = place, m = ZoneMap(), l = ns.PlayerLevel() or 0 }, MAX_REST)
  end
  lastResting = resting
end

ns.On("PLAYER_ENTERING_WORLD", function()
  Snapshot()
  lastPool, lastPoolTime = ReadPool(), Now()
  local r = ns.Value(IsResting)
  if r ~= nil then lastResting = r == true end
end)
ns.On("PLAYER_XP_UPDATE", OnXPUpdate)
ns.On("PLAYER_LEVEL_UP", function() ns.After(0.5, function() if not last.xp then Snapshot() end end) end)
ns.On("CHAT_MSG_COMBAT_XP_GAIN", OnChatXP)
ns.On("CHAT_MSG_SYSTEM", function(_, msg) OnExplore(msg) end)
ns.On("UI_INFO_MESSAGE", function(_, _, msg) OnExplore(msg) end)
ns.On("QUEST_TURNED_IN", OnQuestTurnedIn)
ns.On("QUEST_ACCEPTED", function(_, questID) CacheTag(questID) end)
ns.On("QUEST_COMPLETE", function() CacheTag(ns.Value(GetQuestID)) end)
ns.On("UPDATE_EXHAUSTION", OnExhaustion)
ns.On("PLAYER_UPDATE_RESTING", OnResting)

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local function Avg(sum, n) return n > 0 and sum / n or 0 end
local function R2(v) return ("%.2f"):format(v) end
local function Int(v) return ("%d"):format(math.floor(v + 0.5)) end

-- Buckets samples by player level: [level] = { [bucket] = { n, sum } }
local function ByLevel(list, bucketOf, valueOf)
  local t, levels = {}, {}
  for _, s in ipairs(list) do
    local b = bucketOf(s)
    if b and s.l and s.l > 0 then
      if not t[s.l] then t[s.l] = {} levels[#levels + 1] = s.l end
      local c = t[s.l][b] or { n = 0, sum = 0 }
      c.n, c.sum = c.n + 1, c.sum + valueOf(s)
      t[s.l][b] = c
    end
  end
  table.sort(levels)
  return t, levels
end

-- Weighted ratio a/b over the levels that have both (weight = smaller sample count).
local function Ratio(t, levels, a, b)
  local wa, wb, n = 0, 0, 0
  for _, lv in ipairs(levels) do
    local ca, cb = t[lv][a], t[lv][b]
    if ca and cb and ca.n > 0 and cb.n > 0 and cb.sum > 0 then
      local w = math.min(ca.n, cb.n)
      wa, wb, n = wa + w * Avg(ca.sum, ca.n), wb + w * Avg(cb.sum, cb.n), n + 1
    end
  end
  if n == 0 or wb == 0 then return nil end
  return wa / wb, n
end

local function Cell(c)
  if not c then return "-" end
  return ("%s (n %d)"):format(Int(Avg(c.sum, c.n)), c.n)
end

-- Kill XP with and without one aura, same level and same place type.
local function AuraRatio(kills, id)
  local key = "," .. id .. ","
  local buckets = {}
  for _, s in ipairs(kills) do
    local k = s.l .. ":" .. (s.p or 0)
    local c = buckets[k] or { wn = 0, ws = 0, on = 0, os = 0 }
    if s.a and ("," .. s.a .. ","):find(key, 1, true) then c.wn, c.ws = c.wn + 1, c.ws + s.b else c.on, c.os = c.on + 1, c.os + s.b end
    buckets[k] = c
  end
  local wa, wb, nw, no = 0, 0, 0, 0
  for _, c in pairs(buckets) do
    if c.wn > 0 and c.on > 0 and c.os > 0 then
      local w = math.min(c.wn, c.on)
      wa, wb = wa + w * c.ws / c.wn, wb + w * c.os / c.on
      nw, no = nw + c.wn, no + c.on
    end
  end
  if wb == 0 then return nil end
  return wa / wb, nw, no
end

function ns.BuildXPCheck()
  Parsers()
  local s = Store()
  local st, at = session.tot, s.tot
  local out = { "Questdon XP check" }
  out[#out + 1] = ("version %s, locale %s, level %s, since %s"):format(ns.Version(), ns.Locale and ns.Locale() or "?",
    tostring(ns.PlayerLevel() or "?"), tostring(s.since))

  out[#out + 1] = "# Totals (session | all time)"
  local function Line(label, a, b) out[#out + 1] = ("%s: %s | %s"):format(label, a, b) end
  local function Other(t) return t.delta - t.kill - t.quest - t.explore - t.unnamed end
  Line("measured gain", Int(st.delta), Int(at.delta))
  Line("kills", ("%d XP in %d"):format(st.kill, st.killN), ("%d XP in %d"):format(at.kill, at.killN))
  Line("  rested bonus", Int(st.rest), Int(at.rest))
  Line("  group bonus / raid penalty", ("%d / %d"):format(st.group, st.raid), ("%d / %d"):format(at.group, at.raid))
  Line("quests", ("%d XP in %d"):format(st.quest, st.questN), ("%d XP in %d"):format(at.quest, at.questN))
  Line("exploration", ("%d XP in %d"):format(st.explore, st.exploreN), ("%d XP in %d"):format(at.explore, at.exploreN))
  Line("other chat XP", ("%d XP in %d"):format(st.unnamed, st.unnamedN), ("%d XP in %d"):format(at.unnamed, at.unnamedN))
  Line("unassigned", Int(Other(st)), Int(Other(at)))
  Line("skipped (secret values)", Int(st.secret), Int(at.secret))
  out[#out + 1] = ("chat vs bar (session): kills same %d, differ %d; quests same %d, differ %d"):format(
    session.killLink.same, session.killLink.diff, session.questLink.same, session.questLink.diff)

  -- kills
  local kills = s.kills
  out[#out + 1] = ("# Kill XP without rested/group bonus per player level (last %d kills)"):format(#kills)
  local kt, klv = ByLevel(kills, function(k) return (k.p or 0) == 0 and "w" or (k.p == 1 and "d" or nil) end,
    function(k) return k.b or k.x end)
  out[#out + 1] = "level: open world | dungeon | ratio"
  if #klv == 0 then out[#out + 1] = "no kills yet" end
  for _, lv in ipairs(klv) do
    local w, d = kt[lv].w, kt[lv].d
    local ratio = (w and d and w.sum > 0) and R2(Avg(d.sum, d.n) / Avg(w.sum, w.n)) or "-"
    out[#out + 1] = ("L%d: %s | %s | %s"):format(lv, Cell(w), Cell(d), ratio)
  end
  local killRatio, killLevels = Ratio(kt, klv, "d", "w")

  -- quests
  local quests = s.quests
  out[#out + 1] = ("# Quest XP per player level (last %d turn-ins)"):format(#quests)
  local qt, qlv = ByLevel(quests, function(q) return q.d == 1 and "d" or "n" end, function(q) return q.x end)
  out[#out + 1] = "level: normal | dungeon | ratio"
  if #qlv == 0 then out[#out + 1] = "no quests yet" end
  for _, lv in ipairs(qlv) do
    local n, d = qt[lv].n, qt[lv].d
    local ratio = (n and d and n.sum > 0) and R2(Avg(d.sum, d.n) / Avg(n.sum, n.n)) or "-"
    out[#out + 1] = ("L%d: %s | %s | %s"):format(lv, Cell(n), Cell(d), ratio)
  end
  local questRatio, questLevels = Ratio(qt, qlv, "d", "n")
  local tags, tagOrder, withLevel, dungeonIDs = {}, {}, 0, {}
  for _, q in ipairs(quests) do
    local t = q.t and tostring(q.t) or "none"
    if not tags[t] then tags[t] = 0 tagOrder[#tagOrder + 1] = t end
    tags[t] = tags[t] + 1
    if q.ql then withLevel = withLevel + 1 end
    if q.d == 1 and #dungeonIDs < 10 then dungeonIDs[#dungeonIDs + 1] = ("%d:%d"):format(q.q, q.x) end
  end
  table.sort(tagOrder)
  local tagText = {}
  for _, t in ipairs(tagOrder) do tagText[#tagText + 1] = ("%s x%d"):format(t, tags[t]) end
  out[#out + 1] = "quest tags: " .. (#tagText > 0 and table.concat(tagText, ", ") or "none")
    .. (" (dungeon = tag %d or turned in inside a dungeon)"):format(DUNGEON_TAG)
  out[#out + 1] = ("ATT level known: %d of %d"):format(withLevel, #quests)
  if #dungeonIDs > 0 then out[#out + 1] = "dungeon quests (id:xp): " .. table.concat(dungeonIDs, " ") end

  -- auras
  out[#out + 1] = "# Auras during kills (spellID: XP with/without, same level and place)"
  local candidates = {}
  for id, c in pairs(s.auras) do candidates[#candidates + 1] = { id = id, n = c.n } end
  table.sort(candidates, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.id < b.id end)
  local shown = 0
  for _, c in ipairs(candidates) do
    if shown >= 5 then break end
    local ratio, nw, no = AuraRatio(kills, c.id)
    if ratio then
      shown = shown + 1
      out[#out + 1] = ("%d: %sx (with %d, without %d)"):format(c.id, R2(ratio), nw, no)
    end
  end
  if shown == 0 then out[#out + 1] = "no comparison yet (needs kills with and without the same aura)" end
  out[#out + 1] = ("aura IDs tracked: %d of %d"):format(s.auraCount or 0, MAX_AURA_IDS)

  -- rested
  out[#out + 1] = "# Rested XP growth"
  local gainR, gainW, nR, nW, secs, ons, onMaps, gainMaps = 0, 0, 0, 0, 0, 0, {}, {}
  for _, r in ipairs(s.rest) do
    if r.k == "gain" then
      if r.r == 1 then gainR, nR, secs = gainR + r.d, nR + 1, secs + (r.s or 0) else gainW, nW = gainW + r.d, nW + 1 end
      local key = ("%d%s%s"):format(r.m or 0, r.p and r.p > 0 and "i" or "", r.r == 1 and "" or " not resting")
      gainMaps[key] = (gainMaps[key] or 0) + 1
    elseif r.k == "on" then
      ons = ons + 1
      local key = ("%d%s"):format(r.m or 0, r.p and r.p > 0 and "i" or "")
      onMaps[key] = (onMaps[key] or 0) + 1
    end
  end
  local function MapList(t)
    local keys = {}
    for k, n in pairs(t) do keys[#keys + 1] = { k = k, n = n } end
    table.sort(keys, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.k < b.k end)
    local parts = {}
    for i = 1, math.min(5, #keys) do parts[#parts + 1] = ("%s x%d"):format(keys[i].k, keys[i].n) end
    return #parts > 0 and table.concat(parts, ", ") or "none"
  end
  out[#out + 1] = ("while resting: +%d in %d steps%s"):format(gainR, nR,
    secs > 0 and (", about %d per hour"):format(math.floor(gainR / secs * 3600 + 0.5)) or "")
  out[#out + 1] = ("while not resting: +%d in %d steps"):format(gainW, nW)
  out[#out + 1] = "growth at zone map: " .. MapList(gainMaps)
  out[#out + 1] = ("resting started %d times at zone map: %s"):format(ons, MapList(onMaps))
  out[#out + 1] = "(map IDs: i = inside an instance)"

  -- exploration
  local ex = s.explores
  if #ex > 0 then
    local parts = {}
    for i = math.max(1, #ex - 9), #ex do parts[#parts + 1] = ("L%d:%d"):format(ex[i].l, ex[i].x) end
    out[#out + 1] = "# Exploration (level:xp, last 10)"
    out[#out + 1] = table.concat(parts, " ")
  end

  -- claims
  out[#out + 1] = "# Forever claims"
  out[#out + 1] = killRatio and ("dungeon mob XP about -75%%: dungeon/open world %s over %d levels (claim 0.25)"):format(R2(killRatio), killLevels)
    or "dungeon mob XP about -75%: not enough data (kills in and outside dungeons at the same level)"
  out[#out + 1] = questRatio and ("dungeon quest XP (extra XP halved in beta 2026-10-01): dungeon/normal %s over %d levels"):format(R2(questRatio), questLevels)
    or "dungeon quest XP (extra XP halved in beta 2026-10-01): not enough data (normal and dungeon quests at the same level)"
  out[#out + 1] = "food +5% XP: see auras (a food buff about 1.05x)"
  out[#out + 1] = ("rested XP outdoors (campfire): growth while not resting %d, resting started outside towns: see zone maps"):format(gainW)

  -- formats
  out[#out + 1] = "# Client strings"
  local ok, missing, used = 0, {}, {}
  for _, def in ipairs(FORMATS) do
    if formatState[def.global] == "ok" then ok = ok + 1 else missing[#missing + 1] = def.global:gsub("^COMBATLOG_XPGAIN_", "") .. " " .. formatState[def.global] end
    if session.formats[def.global] then used[#used + 1] = ("%s x%d"):format(def.global:gsub("^COMBATLOG_XPGAIN_", ""), session.formats[def.global]) end
  end
  out[#out + 1] = ("COMBATLOG_XPGAIN_*: %d of %d usable"):format(ok, #FORMATS)
  out[#out + 1] = "not usable: " .. (#missing > 0 and table.concat(missing, ", ") or "none")
  out[#out + 1] = "matched (session): " .. (#used > 0 and table.concat(used, ", ") or "none")
  out[#out + 1] = "ERR_ZONE_EXPLORED_XP: " .. tostring(formatState[EXPLORE.global])
  return table.concat(out, "\n")
end

function ns.ResetXPCheck()
  if ns.db then ns.db.xpcheck = NewStore() end
  session.tot, session.formats = NewTotals(), {}
  session.killLink, session.questLink = { same = 0, diff = 0 }, { same = 0, diff = 0 }
  pendingKill, pendingQuest, lastDelta = nil, nil, nil
end

function ns.OpenXPCheck(arg)
  if arg == "reset" then
    ns.ResetXPCheck()
    ns.Print(L["XP sources reset."])
    return
  end
  return ns.ShowText(L["XP sources"], L["Where your XP came from, to check Forever's XP rules. Ctrl+A selects all, Ctrl+C copies."]
    .. " " .. L["Only numbers: no character, realm or guild names."], ns.BuildXPCheck())
end

ns.OnInit(function() Store() end)
