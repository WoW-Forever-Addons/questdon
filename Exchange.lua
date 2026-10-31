local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- (1.0.1) Sharing learned quest data with guild and group.
--
-- Every Questdon sends only its OWN observations: the lines of /qd export
-- (Export.lua, ns.ExportRecords) that the bundled data does not have yet.
-- Others keep them apart from their own learning (QuestdonDB.shared) and use
-- a fact only once two different players reported it. Nothing is passed on:
-- what a client only knows from others it never sends, so "two reporters"
-- really are two players and there are no echo loops.
--
--   message  "D2:<seq>:<account token>:<line>;<line>;..."  (at most MAX_MSG
--            characters; "D1:<seq>:..." from Questdon before 1.1 is still read)
--   lines    S G I T O F K D A X N E W R P H as in Export.lua, only numbers (E: 1.3.6 dungeon entrances, W: 1.3.6 walked
--            cells, R: 1.3.8 reward picks); (1.3.9) Q L J B: play times, drop rates, flights, abandons (Timing.lua),
--            measurements, not facts: kept line by line (ns.StoreSample), each own line sent SAMPLE_SENDS times,
--            at most SAMPLES_PER_HOUR an hour, before the facts (their budget is the same)
--
-- Sending: option shareLearned (on), to the guild and the own group (not to
-- the group when all members are in the guild: the guild message reaches
-- them), at most MAX_PER_FLUSH messages every FLUSH_GAP seconds and
-- MAX_PER_HOUR per hour, never in a chat lockdown or combat. What was sent is
-- remembered (QuestdonDB.shareSent: key -> line); counters are sent again only
-- at the next step (1, 5, 25, 100); facts KNOWN others already reported the
-- same way and spots beyond SPOTS_PER_OBJECTIVE per objective are not sent.
-- (1.3.5) Daniel 09.10.: nothing is kept for players who are offline, so an
-- own fact goes out again after RESEND (QuestdonDB.shareSentAt: key -> time),
-- oldest first and only with the budget new facts leave. Receivers count
-- reporters, so the same fact from the same player again changes nothing.
-- At most FACTS_PER_HOUR facts an hour, below PER_SENDER of the receivers.
-- Receiving is always on (decision 2026-10-04: everybody may use shared data).
-- (1.1) Also through the open channel "QuestdonNet" (option shareChannel, on):
-- every Questdon player, so facts from there need three reporters unless two
-- came through guild or group.
--
-- Checks on receipt: (1.3.5) only guild, group and the channel, exact line shapes, number ranges, own echoes ignored,
-- at most PER_SENDER facts per sender and hour, at most MAX_SHARED facts.
-- Reporters are kept as a 24 bit checksum of "Name-Realm" (to count them),
-- never shown or exported. Shared data never overrides own learning or the
-- game; it ranks before the bundled data where it is used (turn-ins,
-- objective spots).
--
-- (31.10.2026, docs/LEISTUNG_PRUEFUNG_2026-10-31.md A5) Each fact is ONE string in QuestdonDB.shared (DonDataDB.shared),
-- not four tables (635 byte a fact before, Daniel's file 23.10.: 8509 facts 5.3 MB):
--   "<t> <c>|<variant>|<variant>..."   t time of the last change, c highest count (0: none)
--   variant "<n>,<o>,<m>,<x>,<y>,<id>,<f>,<v>,<reporters>"   n reporters, o of them through the open channel, an empty
--           field is not there; reporters separated by spaces, one that came through the open channel ends in "*"
-- Older saved tables ({ t, c, v = { { m, x, y, id, f, v, n, o, r = { [reporter] = true or "o" } } } }) are turned into
-- strings once per session (Migrate, sharedVersion 3: an older Questdon wipes the table instead of misreading it).
-- At most MAX_SHARED facts; Prune keeps the most reported, then the own faction's quests, then the newest (a count per
-- rank, no sort of all facts). A variant with MAX_REPORTERS reporters takes no more reports. The open channel gives at
-- most RECV_PER_SEC lines a second (more are dropped and counted as limited). The sent lists (shareSent, shareSentAt,
-- exportSent: about 0.4 MB in Daniel's file) stay as they are: their lines average 16 characters, a checksum saves
-- little, and they only grow with the own facts.
---------------------------------------------------------------------------
-- (25.10.2026, CLASSIC_ERA_PLAN.md) Classic Era has its own prefix and channel: Era data never mixes with Forever data
local PREFIX = ns.ERA and "QdShareEra" or "QdShare"
ns.EXCHANGE_PREFIX = PREFIX
local FLUSH_GAP = 60        -- seconds between two sends
local MAX_PER_FLUSH = 5     -- messages per send
local MAX_PER_HOUR = 30     -- messages per hour (a long backlog is spread out)
local SPOTS_PER_OBJECTIVE = 10 -- objective spots sent per objective (1.2: was 5, sightings add more)
local KNOWN = 3             -- others who reported a fact the same way: no need to send it
local MAX_MSG = 240         -- characters per message (limit 255)
local MAX_SHARED = 8000     -- facts kept ((A5) was 20000: about 12 MB in the old format)
local MAX_VARIANTS = 3      -- differing reports per fact
local MAX_REPORTERS = 5     -- reporters kept per variant ((A5) was 8; CONFIRM_NOT_HERE needs 5)
local RECV_PER_SEC = 20     -- (A5) lines a second taken from the open channel
local T_REFRESH = 86400     -- (A5) a report that changes nothing renews the fact's time once a day
local PER_SENDER = 200      -- facts per sender and hour
local CONFIRM = 2           -- reporters needed before a fact is used
local RESEND = 86400        -- (1.3.5) an own fact goes out again after a day
local FACTS_PER_HOUR = 190  -- (1.3.5) facts sent per hour (receivers take PER_SENDER)
local SAMPLES_PER_HOUR = 60 -- (1.3.9) of those at most this many play time lines (Timing.lua)
-- (1.1) The open channel: every Questdon player (option shareChannel, on).
-- Anybody can join a channel, so a fact needs CONFIRM_OPEN reporters when
-- not CONFIRM of them came through guild or group. If the first name is
-- taken (a password, a ban), the next one is tried.
local CHANNEL_NAMES = ns.ERA and { "QuestdonEra", "QuestdonEra2", "QuestdonEra3" }
  or { "QuestdonNet", "QuestdonNet2", "QuestdonNet3" }
ns.EXCHANGE_CHANNELS = CHANNEL_NAMES
local CONFIRM_OPEN = 3
-- (1.3.5, Daniel 10.10.) Only the ways Questdon itself sends on count: guild and group are
-- trusted, the channel is open; anything else (a whisper) is ignored. Before, every chat type
-- but the channel counted as trusted, so two characters whispering could confirm a fact.
local TRUSTED_WAYS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true,
  PARTY_LEADER = true, RAID_LEADER = true, INSTANCE_CHAT_LEADER = true }
-- (1.3.5) "the quest giver never offers it" hides a quest: two trusted reporters or CONFIRM_NOT_HERE in all
local CONFIRM_NOT_HERE = 5
local JOIN_DELAY, JOIN_CHECK = 10, 3 -- seconds after login; seconds until a join is checked
local JOIN_WAIT_MAX = 90    -- (1.3.3) seconds to wait for the game's own channels before joining anyway
local SENDS_PER_FLUSH = 9   -- addon messages per prefix: 10 at once, then 1 per second
local NEAR = 2              -- map units: two spots this close are the same

local stats = { saved = 0, sentMsgs = 0, sentFacts = 0, resentFacts = 0, recvMsgs = 0, recvLines = 0, bad = 0, own = 0, limited = 0, blocked = 0, pruned = 0,
  recvChannel = 0, otherWay = 0 }
ns.shareStats = stats
local registered = false
local seq = 0
local senders = {}          -- [hash] = { t = window start, n = facts }
local version = 0           -- changes whenever shared data changes (caches)

local function Now() return ns.Num(ns.Value(GetTime)) or 0 end
local function Clock() return ns.Num(ns.Value(time)) or Now() end

local Migrate -- (A5) below: older saved facts into the compact strings, once per session
local migrated = nil -- the shared table that was migrated
local function DB()
  local db = ns.db
  if type(db.shared) ~= "table" then db.shared = {} end
  if type(db.shareSent) ~= "table" then db.shareSent = {} end
  if type(db.shareSentAt) ~= "table" then db.shareSentAt = {} end -- (1.3.5)
  -- (1.1) shared data of the test builds counted the own echo as a player: start clean once
  -- (A5) 3: the compact strings (an older Questdon wipes them: it only knows 2)
  if db.sharedVersion ~= 2 and db.sharedVersion ~= 3 then
    wipe(db.shared)
    db.sharedVersion = 2
  end
  if migrated ~= db.shared then
    migrated = db.shared
    Migrate(db)
  end
  return db
end

-- (1.1) Account token: 8 hex digits, made once per account and kept in the
-- saved data. Messages carry it ("D2:<seq>:<token>:..."), so one account
-- counts as ONE reporter whatever character sends, and the own echo is
-- recognised even when the client spells the own name differently (Daniel's
-- group test 04.10.: the own echo counted as a second player). A sender name
-- may use one token per session; older clients send "D1" (reporter = name).
local tokenOf = {}
local function MyToken()
  local db = DB()
  local t = db.shareToken
  if type(t) ~= "string" or not t:match("^%x%x%x%x%x%x%x%x$") then
    t = ("%04x%04x"):format(math.random(0, 65535), math.random(0, 65535))
    db.shareToken = t
  end
  return t
end


local function Locked()
  local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn)
  if not ok or v == nil then return false end
  return not ns.Usable(v) or v == true
end

-- 24 bit checksum of a name (counting reporters; not reversible on its own,
-- but not anonymous either: never shown, never exported).
local function Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777216 end
  return ("%06x"):format(h)
end

local myName
local function MyFullName()
  if myName then return myName end
  local name, realm
  if type(UnitFullName) == "function" then
    local ok, n, r = pcall(UnitFullName, "player")
    if ok then name, realm = n, r end
  end
  if not (type(name) == "string" and ns.Usable(name)) then return nil end
  if not (type(realm) == "string" and ns.Usable(realm) and realm ~= "") then
    realm = ns.Value(GetNormalizedRealmName) or ns.Value(GetRealmName)
    realm = type(realm) == "string" and realm:gsub("%s", "") or nil
  end
  if realm and realm ~= "" then myName = name .. "-" .. realm end
  return myName or name
end

local function FullSender(sender)
  if type(sender) ~= "string" or not ns.Usable(sender) or sender == "" then return nil end
  if sender:find("-", 1, true) then return sender end
  local me = MyFullName()
  local realm = me and me:match("%-(.+)$")
  return realm and (sender .. "-" .. realm) or sender
end

---------------------------------------------------------------------------
-- Lines: shape check, key (what the fact is about), value, count
---------------------------------------------------------------------------
local function Int(v, hi) v = tonumber(v) return v and v >= 0 and v < hi and v == math.floor(v) and v or nil end
local function Pos(v) v = tonumber(v) return v and v >= 0 and v <= 100 and v or nil end

-- Returns key, value, count, kind (or nil for a bad line).
-- value: what has to agree between reporters; positions are compared loosely.
local PARSE = {
  S = function(l, nov)
    local q, m, x, y, npc, f = l:match("^S (%d+) (%d+) (%d+%.%d) (%d+%.%d) (%d+) ([AH%-])$")
    if not (Int(q, 1e6) and Int(m, 1e5) and Pos(x) and Pos(y) and Int(npc, 1e7)) then return nil end
    return "S " .. q, nov or { m = tonumber(m), x = tonumber(x), y = tonumber(y), id = tonumber(npc), f = f }
  end,
  G = function(l, nov)
    local q, m, x, y, obj, f = l:match("^G (%d+) (%d+) (%d+%.%d) (%d+%.%d) (%d+) ([AH%-])$")
    if not (Int(q, 1e6) and Int(m, 1e5) and Pos(x) and Pos(y) and Int(obj, 1e7)) then return nil end
    return "G " .. q, nov or { m = tonumber(m), x = tonumber(x), y = tonumber(y), id = tonumber(obj), f = f }
  end,
  T = function(l, nov)
    local q, m, x, y, npc = l:match("^T (%d+) (%d+) (%d+%.%d) (%d+%.%d) (%d+)$")
    if not (Int(q, 1e6) and Int(m, 1e5) and Pos(x) and Pos(y) and Int(npc, 1e7)) then return nil end
    return "T " .. q, nov or { m = tonumber(m), x = tonumber(x), y = tonumber(y), id = tonumber(npc) }
  end,
  I = function(l, nov)
    local q, item, f = l:match("^I (%d+) (%d+) ([AH%-])$")
    if not (Int(q, 1e6) and Int(item, 1e7)) then return nil end
    return "I " .. q, nov or { v = item }
  end,
  O = function(l, nov)
    local q, i, m, x, y = l:match("^O (%d+) (%d+) (%d+) (%d+%.%d) (%d+%.%d)$")
    if not (Int(q, 1e6) and Int(i, 21) and tonumber(i) >= 1 and Int(m, 1e5) and Pos(x) and Pos(y)) then return nil end
    -- one fact per spot: a grid of NEAR map units
    return ("O %s %s %s %d %d"):format(q, i, m, math.floor(tonumber(x) / NEAR), math.floor(tonumber(y) / NEAR)),
      nov or { m = tonumber(m), x = tonumber(x), y = tonumber(y) }
  end,
  F = function(l, nov)
    local q, prev, v = l:match("^F (%d+) (%d+) ([12])$")
    if not (Int(q, 1e6) and Int(prev, 1e6)) then return nil end
    return ("F %s %s"):format(q, prev), nov or { v = "1" }, tonumber(v)
  end,
  K = function(l, nov)
    local q, i, kind, id, n = l:match("^K (%d+) (%d+) ([coi]) (%d+) (%d+)$")
    if not (Int(q, 1e6) and Int(i, 21) and tonumber(i) >= 1 and Int(id, 1e7) and Int(n, 1e4)) then return nil end
    return ("K %s %s %s %s"):format(q, i, kind, id), nov or { v = "1" }, tonumber(n)
  end,
  D = function(l, nov)
    local item, kind, id, n, m, x, y = l:match("^D (%d+) ([co]) (%d+) (%d+) (%d+) (%d+%.%d) (%d+%.%d)$")
    if not (Int(item, 1e7) and Int(id, 1e7) and Int(n, 1e4) and Int(m, 1e5) and Pos(x) and Pos(y)) then return nil end
    return ("D %s %s %s"):format(item, kind, id), nov or { v = "1" }, tonumber(n)
  end,
  A = function(l, nov)
    local q, lv = l:match("^A (%d+) (%d+)$")
    if not (Int(q, 1e6) and Int(lv, 100) and tonumber(lv) >= 1) then return nil end
    return "A " .. q, nov or { v = lv }
  end,
  X = function(l, nov)
    local q = l:match("^X (%d+)$")
    if not Int(q, 1e6) then return nil end
    return "X " .. q, nov or { v = "1" }
  end,
  -- (1.3.6) a dungeon's way in (Entrances.lua): one fact per dungeon and zone map; reports within NEAR
  -- map units agree, a second way in on the same map is another variant (Uldaman, Stratholme)
  E = function(l, nov)
    local inst, m, x, y = l:match("^E (%d+) (%d+) (%d+%.%d) (%d+%.%d)$")
    if not (Int(inst, 1e6) and Int(m, 1e5) and Pos(x) and Pos(y)) then return nil end
    return ("E %s %s"):format(inst, m), nov or { m = tonumber(m), x = tonumber(x), y = tonumber(y) }
  end,
  -- (1.3.6) a block of walked cells (Paths.lua): stored apart (ns.StoreWalk), cell by cell
  W = function(l, nov)
    local m, b, mask = l:match("^W (%d+) (%d+) (%x+)$")
    if not (Int(m, 1e5) and Int(b, 100) and mask and #mask == 25) then return nil end
    return ("W %s %s"):format(m, b), nov or { v = mask:lower() }
  end,
  -- (1.3.8) the reward a player of a class (and talent tree) picked by hand (Rewards.lua): one fact per
  -- quest, class, tree and item, so the reporters of a fact are the players who picked that item
  R = function(l, nov)
    local q, c, t, item = l:match("^R (%d+) (%d+) ([0-3]) (%d+)$")
    if not (Int(q, 1e6) and Int(c, 20) and tonumber(c) >= 1 and Int(item, 1e7)) then return nil end
    return ("R %s %s %s %s"):format(q, c, t, item), nov or { v = "1" }
  end,
  -- (17.10.) where a walking NPC was seen (Walks.lua): one fact per NPC, map and NEAR grid cell, like the
  -- objective spots; confirmed points tell whether the NPC's route is right
  P = function(l, nov)
    local npc, m, x, y = l:match("^P (%d+) (%d+) (%d+%.%d) (%d+%.%d)$")
    if not (Int(npc, 1e7) and Int(m, 1e5) and Pos(x) and Pos(y)) then return nil end
    return ("P %s %s %d %d"):format(npc, m, math.floor(tonumber(x) / NEAR), math.floor(tonumber(y) / NEAR)),
      nov or { m = tonumber(m), x = tonumber(x), y = tonumber(y) }
  end,
  -- (27.10.2026) a gathering find (Gather.lua): one fact per kind, source, item, map and NEAR grid cell, the count
  -- is how often (Daniel: herbs, ore, leather, fish for our data; fish later for Luredon)
  H = function(l, nov)
    local k, s, id, m, x, y, item, n = l:match("^H ([hmsf]) ([oc%-]) (%d+) (%d+) (%d+%.%d) (%d+%.%d) (%d+) (%d+)$")
    if not (k and Int(id, 1e7) and Int(m, 1e5) and Pos(x) and Pos(y) and Int(item, 1e7) and Int(n, 1e4)) then return nil end
    if (s == "-") ~= (tonumber(id) == 0) then return nil end
    return ("H %s %s%s %s %s %d %d"):format(k, s, id, item, m, math.floor(tonumber(x) / NEAR), math.floor(tonumber(y) / NEAR)),
      nov or { m = tonumber(m), x = tonumber(x), y = tonumber(y) }, tonumber(n)
  end,
  -- (1.1) the quest giver never offers this quest (NotHere.lua)
  N = function(l, nov)
    local q, npc = l:match("^N (%d+) (%d+) [ma]$")
    if not (Int(q, 1e6) and Int(npc, 1e7)) then return nil end
    return "N " .. q, nov or { v = "1" }
  end,
}

-- (1.3.9) play time lines (Timing.lua): exact shapes and ranges; returns the line or nil
local SAMPLE = {
  Q = function(l)
    local q, lv, c, s, d, g, p, ld, xp, cu = l:match("^Q (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) ([01]) (%d+) (%d+)$")
    return Int(q, 1e6) and Int(lv, 100) and Int(c, 20) and Int(s, 86400) and Int(d, 100) and Int(g, 41) and Int(p, 50)
      and Int(xp, 1e6) and Int(cu, 1e7) and l or nil
  end,
  L = function(l)
    local item, cr, n, got = l:match("^L (%d+) (%d+) (%d+) (%d+)$")
    return Int(item, 1e7) and Int(cr, 1e7) and Int(n, 1e4) and Int(got, 1e4) and tonumber(got) <= tonumber(n) * 20 and l or nil
  end,
  J = function(l)
    local m1, x1, y1, m2, x2, y2, s = l:match("^J (%d+) (%d+%.%d) (%d+%.%d) (%d+) (%d+%.%d) (%d+%.%d) (%d+)$")
    return Int(m1, 1e5) and Pos(x1) and Pos(y1) and Int(m2, 1e5) and Pos(x2) and Pos(y2) and Int(s, 1801)
      and tonumber(s) >= 10 and l or nil
  end,
  B = function(l)
    local q, lv = l:match("^B (%d+) (%d+)$")
    return Int(q, 1e6) and Int(lv, 100) and l or nil
  end,
}
function ns.ParseSampleLine(line)
  if type(line) ~= "string" or #line > 80 then return nil end
  local p = SAMPLE[line:sub(1, 1)]
  return p and p(line) or nil
end

-- nov: (23.10.) no value table (true in its place), for the send list that only needs key and count
function ns.ParseShareLine(line, nov)
  if type(line) ~= "string" or #line > 80 then return nil end
  local p = PARSE[line:sub(1, 1)]
  if not p then return nil end
  return p(line, nov)
end
local Parse = ns.ParseShareLine

-- Two reports agree: same value, positions within NEAR map units on the same map.
local function Same(a, b)
  if a.v ~= b.v or a.id ~= b.id or a.f ~= b.f then return false end
  if a.m or b.m then
    if a.m ~= b.m then return false end
    if math.abs((a.x or 0) - (b.x or 0)) > NEAR or math.abs((a.y or 0) - (b.y or 0)) > NEAR then return false end
  end
  return true
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

---------------------------------------------------------------------------
-- Storing what others reported
---------------------------------------------------------------------------
local sharedCount
local function SharedCount()
  if not sharedCount then sharedCount = Count(DB().shared) end
  return sharedCount
end

-- (A5) The compact strings (format at the top). Decode gives the old shape: { t, c, v = { { m, x, y, id, f, v, n, o,
-- r = { [reporter] = true or "o" } } } }; an old table is returned as it is.
local function Field(v)
  if v == nil then return "" end
  v = tostring(v)
  if v:find("[,|%s]") then return nil end
  return v
end
local function EncodeVariant(v)
  if type(v) ~= "table" then return nil end
  local reps = {}
  for rep, how in pairs(type(v.r) == "table" and v.r or {}) do
    if type(rep) == "string" and rep:match("^%w+$") then reps[#reps + 1] = how == "o" and (rep .. "*") or rep end
  end
  table.sort(reps)
  local n = ns.Num(v.n) or #reps
  local m, x, y, id, f, val = Field(v.m), Field(v.x), Field(v.y), Field(v.id), Field(v.f), Field(v.v)
  if not (m and x and y and id and f and val) then return nil end
  return ("%d,%d,%s,%s,%s,%s,%s,%s,%s"):format(math.floor(n), math.floor(ns.Num(v.o) or 0), m, x, y, id, f, val,
    table.concat(reps, " "))
end
local function Encode(e)
  local parts = { ("%d %d"):format(math.floor(ns.Num(e.t) or 0), math.floor(ns.Num(e.c) or 0)) }
  for _, v in ipairs(type(e.v) == "table" and e.v or {}) do
    local s = EncodeVariant(v)
    if s then parts[#parts + 1] = s end
  end
  if #parts == 1 then return nil end
  return table.concat(parts, "|")
end
-- noReps: without the reporters (Best: only the values and counts are read)
local function DecodeVariant(s, noReps)
  local n, o, m, x, y, id, f, val, reps = s:match("^(%d+),(%d*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.*)$")
  if not n then return nil end
  local v = { n = tonumber(n), o = tonumber(o) or 0, m = tonumber(m), x = tonumber(x), y = tonumber(y), id = tonumber(id),
    f = f ~= "" and f or nil, v = val ~= "" and val or nil }
  if not noReps then
    local r = {}
    for rep in reps:gmatch("%S+") do
      if rep:sub(-1) == "*" then r[rep:sub(1, -2)] = "o" else r[rep] = true end
    end
    v.r = r
  end
  return v
end
local function Decode(e)
  if type(e) == "table" then return type(e.v) == "table" and e or nil end
  if type(e) ~= "string" then return nil end
  local t, c, rest = e:match("^(%d+) (%d+)(.*)$")
  if not t then return nil end
  c = tonumber(c)
  local out = { t = tonumber(t), c = c > 0 and c or nil, v = {} }
  for vs in rest:gmatch("|([^|]+)") do
    local v = DecodeVariant(vs)
    if v then out.v[#out.v + 1] = v end
  end
  return out
end
-- (tests, tools) a fact in the old shape (a copy for a string; changing it changes nothing)
function ns.SharedEntry(key)
  local e = ns.db and type(ns.db.shared) == "table" and ns.db.shared[key]
  if type(e) == "table" then return e end
  return Decode(e)
end

-- Make room: facts with fewer reporters go first, then (A5) quests this character's faction can never do, then the
-- oldest (by day). (A5) No sort of all facts: they are counted per rank, the ranks (a few hundred) sorted, and one more
-- pass removes everything below the cut (and part of the cut's rank).
local QUEST_KEYS = { S = true, G = true, T = true, I = true, O = true, F = true, K = true, A = true, X = true, N = true, R = true }
local function Rank(key, e, reach)
  local best, t = 0, 0
  if type(e) == "string" then
    t = tonumber(e:match("^(%d+)")) or 0
    for n in e:gmatch("|(%d+),") do
      n = tonumber(n)
      if n > best then best = n end
    end
  elseif type(e) == "table" then
    for _, v in ipairs(type(e.v) == "table" and e.v or {}) do best = math.max(best, type(v) == "table" and ns.Num(v.n) or 0) end
    t = ns.Num(e.t) or 0
  end
  best = math.min(best, 9)
  local side = 1
  if reach and type(key) == "string" and QUEST_KEYS[key:sub(1, 1)] then
    local q = tonumber(key:match("^%a (%d+)"))
    if q then
      local ok, can = pcall(reach, q)
      if ok and can == false then side = 0 end
    end
  end
  return (best * 2 + side) * 100000 + math.floor(t / 86400) % 100000
end

local placeQ, pruneGen = {}, 0 -- (16.10.) see Changed below
local spotCache, spotVersion, spotStale = nil, -1, {}
-- (Questdon review 4) places (objective spots, turn-ins, starts) have their own version: a reward pick or a
-- level fact from the open channel rebuilt every quest's points and re-scanned all shared facts
-- ((A5) declared before Prune now: Prune counted up a global of that name and stopped with an error at the limit)
local placeVersion = 0
local bestMemo, bestMemoN, memoSize = {}, {}, 0 -- (A5) Best of a fact string (SharedTurnIn, SharedNotHere)
local function Forget() bestMemo, bestMemoN, memoSize = {}, {}, 0 end
ns.SharedForget = Forget -- (measurements)

local function PruneTo(target)
  local shared = DB().shared
  local reach = ns.QuestReachable
  local hist, total = {}, 0
  for key, e in pairs(shared) do
    local r = Rank(key, e, reach)
    hist[r] = (hist[r] or 0) + 1
    total = total + 1
  end
  local remove = total - target
  if remove > 0 then
    local ranks = {}
    for r in pairs(hist) do ranks[#ranks + 1] = r end
    table.sort(ranks)
    local cut, part, acc = math.huge, 0, 0
    for _, r in ipairs(ranks) do
      if acc + hist[r] <= remove then acc = acc + hist[r] else cut, part = r, remove - acc break end
    end
    local removed = 0
    for key, e in pairs(shared) do
      local r = Rank(key, e, reach)
      if r < cut or (r == cut and part > 0) then
        if r == cut then part = part - 1 end
        shared[key] = nil
        removed = removed + 1
      end
    end
    stats.pruned = stats.pruned + removed
    pruneGen, placeVersion, spotCache = pruneGen + 1, placeVersion + 1, nil -- every quest anew
    Forget()
  end
  sharedCount = nil
end
local function Prune() PruneTo(math.floor(MAX_SHARED * 0.9)) end
ns.SharedPruneTo = PruneTo -- (measurements)

-- (A5) once per session (and for every new shared table): old tables into strings and down to MAX_SHARED. Returns how
-- many entries changed.
function Migrate(db)
  local shared, n = db.shared, 0
  for key, e in pairs(shared) do
    if type(e) ~= "string" then
      shared[key] = type(key) == "string" and type(e) == "table" and Encode(e) or nil
      n = n + 1
    end
  end
  db.sharedVersion = 3
  sharedCount = nil
  if SharedCount() > MAX_SHARED then Prune() end
  Forget()
  return n
end
function ns.SharedMigrate()
  local db = ns.db
  if type(db.shared) ~= "table" then return 0 end
  migrated = db.shared
  return Migrate(db)
end

-- (16.10. late, Daniel's /qd mem: "API ObjectivePoints" 188 KB a second) with the open channel busy, every new
-- reporter of any place made every quest's places count as changed (the arrow's, the API's, the map's): each quest
-- has its own version now, and only its shared spots are looked up again.
local function Changed(key)
  version = version + 1
  if type(key) == "string" and key:match("^[OTS] ") then
    placeVersion = placeVersion + 1
    local q = tonumber(key:match("^[OTS] (%d+)"))
    if q then
      placeQ[q] = (placeQ[q] or 0) + 1
      if key:sub(1, 1) == "O" then spotStale[q] = true end
    end
  end
end
-- questID: that quest's places (any change of the shared data when nil)
function ns.SharedPlacesVersion(questID)
  if questID == nil then return placeVersion end
  return pruneGen * 1000000 + (placeQ[questID] or 0)
end

local function Store(key, value, count, reporter, open)
  local shared = DB().shared
  local e = Decode(shared[key])
  local new = not e
  if new then
    if SharedCount() >= MAX_SHARED then Prune() end
    e = { v = {} }
  end
  local clock = Clock()
  local changed = false
  if count and count > (ns.Num(e.c) or 0) then e.c = math.min(count, 9999) changed = true end
  -- (1.1) reporters through the open channel are kept as "o" (o = how many)
  local found = false
  for _, v in ipairs(e.v) do
    if Same(v, value) then
      found = true
      v.r = type(v.r) == "table" and v.r or {}
      v.n = ns.Num(v.n) or 0
      local had = v.r[reporter]
      -- (A5) a variant with MAX_REPORTERS reporters takes no more reports
      if not had and v.n < MAX_REPORTERS then
        v.r[reporter] = open and "o" or true
        v.n = v.n + 1
        if open then v.o = (ns.Num(v.o) or 0) + 1 end
        Changed(key)
        changed = true
      elseif had == "o" and not open then
        v.r[reporter] = true -- the same player through guild or group
        v.o = math.max((ns.Num(v.o) or 1) - 1, 0)
        Changed(key)
        changed = true
      end
      break
    end
  end
  if not found and #e.v < MAX_VARIANTS then
    value.r, value.n = { [reporter] = open and "o" or true }, 1
    if open then value.o = 1 end
    e.v[#e.v + 1] = value
    Changed(key)
    changed = true
  end
  -- (A5) nothing new: the string stays (its time is renewed once a day, for Prune)
  if not changed and type(shared[key]) == "string" and clock - (ns.Num(e.t) or 0) < T_REFRESH then return end
  e.t = clock
  local s = Encode(e)
  if s then
    shared[key] = s
    if new then sharedCount = (sharedCount or 0) + 1 end
  end
end

-- The variant most players reported, if CONFIRM or more did through guild
-- or group, or CONFIRM_OPEN or more in all (1.1: open channel).
-- needOpen: reporters needed in all when fewer than CONFIRM came through guild or group.
local function Confirmed(v, needOpen)
  local n = ns.Num(v.n) or 0
  local trusted = n - (ns.Num(v.o) or 0)
  return trusted >= CONFIRM or n >= (needOpen or CONFIRM_OPEN)
end
-- (A5) memo: SharedTurnIn and SharedNotHere ask for the same facts again and again (a string is its own key: a
-- changed fact is another string). The variant returned is read only.
local function Best(e, needOpen, memo)
  if type(e) == "string" then
    local cache = memo and (needOpen and bestMemoN or bestMemo)
    if cache then
      local hit = cache[e]
      if hit ~= nil then return hit or nil end
    end
    local best, bestN
    local need = needOpen or CONFIRM_OPEN
    for vs in e:gmatch("|([^|]+)") do
      local n, o = vs:match("^(%d+),(%d*),")
      n, o = tonumber(n), tonumber(o) or 0
      if n and (n - o >= CONFIRM or n >= need) and (not bestN or n > bestN) then best, bestN = vs, n end
    end
    local v = best and DecodeVariant(best, true) or false
    if cache then
      if memoSize >= 2000 then Forget() cache = needOpen and bestMemoN or bestMemo end
      cache[e] = v
      memoSize = memoSize + 1
    end
    return v or nil
  end
  if type(e) ~= "table" or type(e.v) ~= "table" then return nil end
  local best
  for _, v in ipairs(e.v) do
    if type(v) == "table" and Confirmed(v, needOpen) and (not best or v.n > best.n) then best = v end
  end
  return best
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Allowed(reporter, lines)
  local now = Now()
  local s = senders[reporter]
  if not s or now - s.t > 3600 then s = { t = now, n = 0 } senders[reporter] = s end
  if s.n >= PER_SENDER then return false end
  s.n = s.n + lines
  return true
end

local recvAt, recvLines = 0, 0 -- (A5) the open channel's lines in the current second
local function OnMessage(_, prefix, text, chatType, sender)
  if prefix ~= PREFIX then return end
  -- (1.3.5) guild and group are trusted, the channel is open, every other way is ignored
  local open = chatType == "CHANNEL" -- (1.1) anybody can be in the channel
  if not open and not (type(chatType) == "string" and TRUSTED_WAYS[chatType]) then stats.otherWay = stats.otherWay + 1 return end
  if type(text) ~= "string" or not ns.Usable(text) or #text > 255 then return end
  -- (A5) at most RECV_PER_SEC lines a second from the open channel (thousands of players send there): the rest is
  -- dropped before anything is read
  if open then
    local now = Now()
    if now - recvAt >= 1 or now < recvAt then recvAt, recvLines = now, 0 end
    if recvLines >= RECV_PER_SEC then stats.limited = stats.limited + 1 stats.flood = (stats.flood or 0) + 1 return end
  end
  local full = FullSender(sender)
  if not full then return end
  if full == MyFullName() then stats.own = stats.own + 1 return end
  local reporter
  local token, payload = text:match("^D2:%d+:(%x%x%x%x%x%x%x%x):(.+)$")
  if token then
    if token == MyToken() then stats.own = stats.own + 1 return end
    if tokenOf[full] and tokenOf[full] ~= token then stats.bad = stats.bad + 1 return end
    tokenOf[full] = token
    reporter = "a" .. token
  else
    payload = text:match("^D1:%d+:(.+)$") -- Questdon before 1.1
    reporter = Hash(full)
  end
  if not payload then stats.bad = stats.bad + 1 return end
  stats.recvMsgs = stats.recvMsgs + 1
  if open then stats.recvChannel = stats.recvChannel + 1 end
  local lines = {}
  for line in payload:gmatch("[^;]+") do lines[#lines + 1] = line end
  if open then recvLines = recvLines + #lines end
  if not Allowed(reporter, #lines) then stats.limited = stats.limited + #lines return end
  for _, line in ipairs(lines) do
    local key, value, count
    local sample = SAMPLE[line:sub(1, 1)] and ns.ParseSampleLine(line)
    if not sample then key, value, count = Parse(line) end
    if sample then
      -- (1.3.9) a measurement: kept with its reporter (a resend of the same line counts once)
      if ns.StoreSample and ns.StoreSample(line, reporter) and ns.timingStats then ns.timingStats.received = ns.timingStats.received + 1 end
      stats.recvLines = stats.recvLines + 1
    elseif key and line:sub(1, 1) == "W" then
      -- (1.3.6) walked cells: counted cell by cell (Paths.lua)
      local m, b = key:match("^W (%d+) (%d+)$")
      if ns.StoreWalk then ns.StoreWalk(tonumber(m), tonumber(b), value.v, reporter, open) end
      stats.recvLines = stats.recvLines + 1
    elseif key then
      Store(key, value, count, reporter, open)
      stats.recvLines = stats.recvLines + 1
    else
      stats.bad = stats.bad + 1
    end
  end
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- Counters are sent again only at the next step.
-- Counters are sent again only at the next step (1, 5, 25, 100): the count only
-- weighs a source, its existence is what matters.
local STEPS = { 100, 25, 5, 1 }
local function Step(n)
  n = n or 0
  for _, s in ipairs(STEPS) do if n >= s then return s end end
  return 1
end

local function Signature(line, value, count)
  if count then return "c" .. Step(count) end
  return line
end

-- Everybody in the group is in the guild too: the guild message reaches them already.
local function GroupInGuild()
  if type(UnitIsInMyGuild) ~= "function" then return false end
  local raid = ns.True(ns.Value(IsInRaid))
  local n = ns.Num(ns.Value(GetNumGroupMembers)) or 0
  if n <= 1 then return false end
  for i = 1, raid and n or math.min(n - 1, 4) do
    local unit = (raid and "raid" or "party") .. i
    if ns.True(ns.Value(UnitExists, unit)) and not ns.True(ns.Value(UnitIsUnit, unit, "player"))
        and not ns.True(ns.Value(UnitIsInMyGuild, unit)) then
      return false
    end
  end
  return true
end

---------------------------------------------------------------------------
-- (1.1) The open channel. Joined as a temporary channel (the client leaves
-- it at logout). Questdon never touches the chat windows (that would taint
-- Blizzard's chat code): addon messages are invisible anyway; the client
-- may show one "joined channel" line and lists the channel in /chatlist.
---------------------------------------------------------------------------
local chan = { name = nil, index = 1, pending = nil, at = 0, state = "off", joins = 0, since = nil, moves = 0 }

local function ChannelID(name)
  if type(GetChannelName) ~= "function" or not name then return nil end
  local ok, id = pcall(GetChannelName, name)
  id = ok and ns.Num(id) or nil
  return id and id > 0 and id or nil
end

local function ChannelWanted()
  return ns.db and ns.db.shareChannel and ns.db.shareLearned and ns.db.learnQuests and true or false
end

-- (1.3.3) Daniel 06.10.: QuestdonNet must not take /1 from General. The channel only joins
-- once the game's own channels are there (or after JOIN_WAIT_MAX), and if it still sits in
-- front of one of them, it is moved behind the last one, as the chat settings do when a
-- player drags a channel (C_ChatInfo.SwapChatChannelsByChannelIndex, never in combat).
local function IsOurs(name)
  if type(name) ~= "string" then return false end
  for _, n in ipairs(CHANNEL_NAMES) do
    if name == n or name:lower() == n:lower() then return true end
  end
  return false
end

-- Highest slot of a channel that is not ours, and how many there are.
local function OtherChannels()
  if type(GetChannelList) ~= "function" then return 0, 0 end
  local list = { pcall(GetChannelList) }
  if not list[1] then return 0, 0 end
  local top, count = 0, 0
  for i = 2, #list, 3 do
    local id, name = ns.Num(list[i]), list[i + 1]
    if id and not IsOurs(name) then
      count = count + 1
      if id > top then top = id end
    end
  end
  return top, count
end

local function MoveBehindOthers(id)
  local top = OtherChannels()
  if not id or top <= id or chan.moves >= 3 then return false end
  if Locked() or ns.True(ns.Value(InCombatLockdown)) then return false end
  local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
  if type(swap) ~= "function" then return false end
  chan.moves = chan.moves + 1
  for i = id, top - 1 do
    if not pcall(swap, i, i + 1) then return false end
  end
  return true
end
ns.ShareChannelMoveBehind = MoveBehindOthers -- (tests)

-- Called by the ticker and after login: join, check a join, try the next name.
function ns.ShareChannelTick()
  if not ChannelWanted() then
    chan.state = "off"
    return nil
  end
  if chan.name and ChannelID(chan.name) then
    chan.state = "joined"
    MoveBehindOthers(ChannelID(chan.name))
    return chan.name
  end
  -- already in one of the names (e.g. after /reload)
  for i, name in ipairs(CHANNEL_NAMES) do
    if ChannelID(name) then
      chan.name, chan.index, chan.pending, chan.state = name, i, nil, "joined"
      MoveBehindOthers(ChannelID(name))
      return name
    end
  end
  chan.name = nil
  local now = Now()
  chan.since = chan.since or now
  -- the game's own channels first (General stays /1)
  if not chan.pending and select(2, OtherChannels()) == 0 and now - chan.since < JOIN_WAIT_MAX then
    chan.state = "waiting"
    return nil
  end
  if chan.pending then
    if now - chan.at < JOIN_CHECK then return nil end
    chan.pending = nil
    chan.index = chan.index + 1 -- not in it after the wait: next name
  end
  local name = CHANNEL_NAMES[chan.index]
  if not name then chan.state = "failed" return nil end
  if Locked() or ns.True(ns.Value(InCombatLockdown)) then return nil end
  local join = JoinTemporaryChannel or JoinChannelByName
  if type(join) ~= "function" then chan.state = "no API" return nil end
  if pcall(join, name) then
    chan.pending, chan.at, chan.state = name, now, "joining"
    chan.joins = chan.joins + 1
  else
    chan.index = chan.index + 1
  end
  return nil
end

-- Option switched off: leave the channel (on: join with the next tick).
function ns.ApplyShareChannel()
  if not ChannelWanted() then
    local name = chan.name
    if name and ChannelID(name) and type(LeaveChannelByName) == "function" then pcall(LeaveChannelByName, name) end
    chan.name, chan.pending, chan.index, chan.state = nil, nil, 1, "off"
  else
    chan.index = 1
    ns.ShareChannelTick()
  end
end

-- (1.3.6) for Leveldon's route sharing (QuestdonAPI.ShareChannelID): the channel number while joined
function ns.ShareChannelID()
  if chan.state ~= "joined" or not chan.name then return nil end
  return ChannelID(chan.name)
end

function ns.ShareChannelState()
  local id = chan.name and ChannelID(chan.name)
  return chan.state, chan.name, id, chan.joins
end

-- Where to send: { {chatType, target}, ... }
local function Channels()
  local list = {}
  local guild = ns.True(ns.Value(IsInGuild))
  if guild then list[#list + 1] = { "GUILD" } end
  if ns.True(ns.Value(IsInGroup)) and not (guild and GroupInGuild()) then
    local instance = LE_PARTY_CATEGORY_INSTANCE and ns.True(ns.Value(IsInGroup, LE_PARTY_CATEGORY_INSTANCE))
    list[#list + 1] = { instance and "INSTANCE_CHAT" or (ns.True(ns.Value(IsInRaid)) and "RAID" or "PARTY") }
  end
  local id = ChannelWanted() and chan.name and ChannelID(chan.name)
  if id then list[#list + 1] = { "CHANNEL", tostring(id) } end
  return list
end

local function Register()
  if registered then return true end
  if not (C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function") then return false end
  local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  local code = ok and ns.Num(result)
  registered = ok and (result == true or result == nil or code == 0 or code == 1) or false
  return registered
end

local function SendTo(msg, channels)
  local any = false
  for _, ch in ipairs(channels) do
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch[1], ch[2])
    if ok and (result == nil or result == true or result == 0) then any = true else stats.blocked = stats.blocked + 1 end
  end
  return any
end

-- What to send: { {key, sig, line, again}, ... }: first what is new, then
-- (1.3.5) what was sent RESEND or longer ago, the oldest first. Left out (and
-- marked as sent): facts three or more others already reported the same way,
-- and objective spots beyond SPOTS_PER_OBJECTIVE per objective.
-- (16.10. late, Daniel's /qd mem: "share" 38 KB a second while walking, all export lines made anew every minute)
-- A fingerprint of what the export reads (counts, numbers and string lengths, no new tables): when it is the same as
-- at the last flush, that flush had nothing to send and no own fact is due to go out again yet, nothing is built.
local function Walk(t, depth, acc)
  for k, v in pairs(t) do
    acc[1] = acc[1] + 1
    local tv = type(v)
    if tv == "number" then acc[2] = (acc[2] + v * 7 + acc[1]) % 1000000007
    elseif tv == "string" then acc[2] = (acc[2] + #v * 13 + acc[1]) % 1000000007
    elseif tv == "boolean" then acc[2] = (acc[2] + (v and 3 or 5)) % 1000000007
    elseif tv == "table" and depth < 6 then Walk(v, depth + 1, acc) end
    if type(k) == "number" then acc[2] = (acc[2] + k * 11) % 1000000007 end
  end
end
-- (23.10., /qd mem round 2: share about 1.4 MB at once with 8224 shared facts) without "shared" and "shareSent":
-- others' facts come in every minute and made each quiet minute build all export lines again, though they only
-- decide what is left out as known. Returns the fingerprint and the part of the own facts (without sampleOut).
local FP_OWN = { "learned", "learnedObj", "learnedCredit", "learnedDrops", "learnedItemStarts", "rewardPicks", "learnedGather" }
local fpAcc = { 0, 0 }
local function ExportFingerprint()
  fpAcc[1], fpAcc[2] = 0, 0
  for _, key in ipairs(FP_OWN) do
    local t = ns.db[key]
    if type(t) == "table" then Walk(t, 1, fpAcc) end
    fpAcc[1] = fpAcc[1] + 1000003
  end
  local own = fpAcc[1] * 1000000007 + fpAcc[2]
  if type(ns.db.sampleOut) == "table" then Walk(ns.db.sampleOut, 1, fpAcc) end
  return fpAcc[1] * 1000000007 + fpAcc[2], own
end
local quiet = { fp = nil, nextDue = nil } -- the last flush that had nothing to send
ns.ShareQuietState = function() return quiet end -- (tests)
local nextDueSeen
local function Pending()
  local db = DB()
  local sent, at, shared = db.shareSent, db.shareSentAt, db.shared
  local list, again, spots = {}, {}, {}
  local due = Clock() - RESEND
  nextDueSeen = nil
  for _, line in ipairs(ns.ExportRecords and ns.ExportRecords(false) or {}) do
    local key, _, count = Parse(line, true) -- (23.10.) no value table per line
    if key then
      local sig = Signature(line, nil, count)
      local skip = false
      if line:sub(1, 1) == "O" then
        local obj = line:match("^O (%d+ %d+) ")
        spots[obj] = (spots[obj] or 0) + 1
        skip = spots[obj] > SPOTS_PER_OBJECTIVE
      end
      if not skip then
        local best = Best(shared[key])
        local known = false
        if best and best.n >= KNOWN then
          local _, value = Parse(line)
          known = value and Same(best, value) or false
        end
        if sent[key] ~= sig then
          if known then
            sent[key] = sig -- known well enough already
            stats.saved = stats.saved + 1
          else
            list[#list + 1] = { key, sig, line }
          end
        elseif not known then
          -- sent before 1.3.5 (no time): due at once
          local t = ns.Num(at[key]) or 0
          if t <= due then again[#again + 1] = { key, sig, line, t }
          elseif not nextDueSeen or t + RESEND < nextDueSeen then nextDueSeen = t + RESEND end
        end
      end
    end
  end
  table.sort(again, function(a, b) if a[4] ~= b[4] then return a[4] < b[4] end return a[1] < b[1] end)
  for _, e in ipairs(again) do list[#list + 1] = e end
  return list
end

-- (23.10., /qd mem round 2) The list of what is due is kept from one send to the next: a few thousand own facts
-- go out at FACTS_PER_HOUR over hours, and every minute built all export lines again (4.5 MB a send with 7500
-- facts in the bench). Built anew when it is used up, when the own facts changed and the list is REBUILD_GAP
-- seconds old, and after BACKLOG_AGE (play time lines, walked cells, facts due again).
local REBUILD_GAP = 600
local BACKLOG_AGE = 3600
local backlog = { list = nil, pos = 1, fp = nil, at = 0 }
ns.ShareBacklog = function() return backlog end -- (tests)

-- Messages sent within the last hour (session).
local sentTimes = {}
local function HourBudget()
  local now = Now()
  while sentTimes[1] and now - sentTimes[1] > 3600 do table.remove(sentTimes, 1) end
  return MAX_PER_HOUR - #sentTimes
end

-- (1.3.5) Facts sent within the last hour (session): { {t, n}, ... }.
local factTimes = {}
local function FactBudget()
  local now, n = Now(), 0
  while factTimes[1] and now - factTimes[1][1] > 3600 do table.remove(factTimes, 1) end
  for _, e in ipairs(factTimes) do n = n + e[2] end
  return FACTS_PER_HOUR - n
end

-- (1.3.9) play time lines sent within the last hour (session)
local sampleTimes = {}
local function SampleBudget()
  local now = Now()
  while sampleTimes[1] and now - sampleTimes[1] > 3600 do table.remove(sampleTimes, 1) end
  return SAMPLES_PER_HOUR - #sampleTimes
end

function ns.ShareFlush()
  if not (ns.db and ns.db.shareLearned and ns.db.learnQuests) then return 0 end
  if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return 0 end
  if Locked() or ns.True(ns.Value(InCombatLockdown)) then stats.blocked = stats.blocked + 1 return 0 end
  local channels = Channels()
  if #channels == 0 or not Register() then return 0 end
  -- (1.1) every message goes to each way: stay within the client's burst
  local budget = math.min(MAX_PER_FLUSH, HourBudget(), math.floor(SENDS_PER_FLUSH / #channels))
  local facts = FactBudget()
  if budget <= 0 or facts <= 0 then return 0 end
  local fp, own = ExportFingerprint()
  if quiet.fp == fp and (not quiet.nextDue or Clock() < quiet.nextDue) then
    stats.quiet = (stats.quiet or 0) + 1
    return 0
  end
  local age = Now() - backlog.at
  if not (backlog.list and backlog.pos <= #backlog.list and age >= 0 and age < BACKLOG_AGE
      and (backlog.fp == own or age < REBUILD_GAP)) then
    local list = Pending()
    backlog.list, backlog.pos, backlog.fp, backlog.at = list, 1, own, Now()
    stats.built = (stats.built or 0) + 1
    if #list == 0 then quiet.fp, quiet.nextDue = fp, nextDueSeen else quiet.fp, quiet.nextDue = nil, nil end
  end
  -- (1.3.9) play time lines first, within their own hour budget (Timing.lua keeps when each was sent)
  local samples = ns.db.shareTimes ~= false and ns.SamplesDue and ns.SamplesDue(math.min(SampleBudget(), facts)) or {}
  local smp = {}
  for _, e in ipairs(samples) do smp[#smp + 1] = { nil, nil, e[1], sample = e } end
  -- the items to send: the play time lines, then the kept list from where the last send stopped
  local list, base, nS = backlog.list, backlog.pos - 1, #smp
  local total = nS + #list - base
  local function Item(k) if k <= nS then return smp[k] end return list[base + k - nS] end
  -- own play time lines waiting to go out again hours later: the quiet skip ends when the next one is due
  local sd = quiet.fp and ns.SamplesNextDue and ns.SamplesNextDue()
  if sd and (not quiet.nextDue or sd < quiet.nextDue) then quiet.nextDue = sd end
  local sent, at = DB().shareSent, DB().shareSentAt
  local msgs, i, done = 0, 1, 1
  while i <= total and msgs < budget and facts > 0 do
    seq = (seq + 1) % 1000
    local head = ("D2:%d:%s:"):format(seq, MyToken())
    local parts, used, size = {}, {}, #head
    while i <= total and #parts < facts and size + #Item(i)[3] + (#parts > 0 and 1 or 0) <= MAX_MSG do
      local item = Item(i)
      parts[#parts + 1] = item[3]
      used[#used + 1] = item
      size = size + #item[3] + (#parts > 1 and 1 or 0)
      i = i + 1
    end
    if #parts == 0 then i = i + 1 done = i -- a line that never fits (cannot happen with export lines)
    elseif SendTo(head .. table.concat(parts, ";"), channels) then
      done = i
      msgs = msgs + 1
      sentTimes[#sentTimes + 1] = Now()
      factTimes[#factTimes + 1] = { Now(), #used }
      facts = facts - #used
      stats.sentMsgs = stats.sentMsgs + 1
      stats.sentFacts = stats.sentFacts + #used
      local clock = Clock()
      for _, p in ipairs(used) do
        if p.sample then
          if ns.SampleSent then ns.SampleSent(p.sample) end
          sampleTimes[#sampleTimes + 1] = Now()
        else
          sent[p[1]] = p[2]
          at[p[1]] = clock
          if p[4] then stats.resentFacts = stats.resentFacts + 1 end
        end
      end
    else
      break
    end
  end
  -- what went out (or never fits) is done; a refused message stays for the next send
  backlog.pos = base + 1 + math.max(0, done - 1 - nS)
  return msgs
end

---------------------------------------------------------------------------
-- Using shared data
---------------------------------------------------------------------------
-- Turn-in point others reported: map, x, y (0-1), reporters, (1.3.5) the NPC's creature ID (0 = unknown).
function ns.SharedTurnIn(questID)
  local v = Best(ns.db and ns.db.shared and ns.db.shared["T " .. tostring(questID)], nil, true)
  if v and v.m and v.x and v.y then return v.m, v.x / 100, v.y / 100, v.n, v.id end
end

-- Objective spots others reported (confirmed): { [index] = { map, x, y, ... } (0-1) }
local function SpotsOfKey(list, key, e)
  local q, i
  if type(key) == "string" then q, i = key:match("^O (%d+) (%d+) ") end
  if not q then return end
  local v = Best(e)
  -- (16.10.) spots on a continent (sent before 1.3.9) are left out
  if v and v.m and not (ns.IsZoneMap and not ns.IsZoneMap(v.m)) then
    q, i = tonumber(q), tonumber(i)
    list[q] = list[q] or {}
    local l = list[q][i] or {}
    list[q][i] = l
    l[#l + 1] = v.m
    l[#l + 1] = v.x / 100
    l[#l + 1] = v.y / 100
  end
end
function ns.SharedSpots(questID)
  if not spotCache then
    spotCache, spotStale = {}, {}
    for key, e in pairs(ns.db and ns.db.shared or {}) do SpotsOfKey(spotCache, key, e) end
  elseif questID and spotStale[questID] then
    -- (16.10.) only this quest's spots again
    spotStale[questID] = nil
    spotCache[questID] = nil
    local prefix = "O " .. questID .. " "
    for key, e in pairs(ns.db and ns.db.shared or {}) do
      if type(key) == "string" and key:sub(1, #prefix) == prefix then SpotsOfKey(spotCache, key, e) end
    end
  end
  return spotCache[questID]
end

-- Own spots plus shared ones for a quest: { [index] = flat spots } or nil.
local mergedSpots = {} -- [questID] = { own =, shared =, sv =, pv =, merged = } (16.10.: the same table while unchanged)
function ns.ObjectiveSpots(questID)
  local own = (ns.db.learnedObj or {})[questID]
  local shared = ns.SharedSpots(questID)
  if not shared then return own end
  local sv = ns.QuestSpotVersion and ns.QuestSpotVersion(questID) or 0
  local pv = ns.SharedPlacesVersion(questID)
  local m = mergedSpots[questID]
  if m and m.own == own and m.shared == shared and m.sv == sv and m.pv == pv then return m.merged end
  local merged = {}
  mergedSpots[questID] = { own = own, shared = shared, sv = sv, pv = pv, merged = merged }
  for index, spots in pairs(own or {}) do merged[index] = spots end
  for index, spots in pairs(shared) do
    if merged[index] then
      local copy = {}
      for k = 1, #merged[index] do copy[k] = merged[index][k] end
      for k = 1, #spots do copy[#copy + 1] = spots[k] end
      merged[index] = copy
    else
      merged[index] = spots
    end
  end
  return merged
end

-- (17.10.) Points where others saw a walking NPC on a map (confirmed facts): { {x, y}, ... } (0-1)
-- (read once per change of the shared facts: the facts are many, the walking NPCs few)
local walkSeenCache, walkSeenVer = nil, nil
local NONE = {}
function ns.SharedWalkSeen(npc, mapID)
  if not walkSeenCache or walkSeenVer ~= version then
    walkSeenCache, walkSeenVer = {}, version
    for key, e in pairs(ns.db and ns.db.shared or {}) do
      if type(key) == "string" and key:sub(1, 2) == "P " then
        local n, m = key:match("^P (%d+) (%d+) ")
        local v = Best(e)
        if n and v and v.x and v.y then
          local k = n .. ":" .. m
          local l = walkSeenCache[k] or {}
          l[#l + 1] = { v.x / 100, v.y / 100 }
          walkSeenCache[k] = l
        end
      end
    end
  end
  return walkSeenCache[npc .. ":" .. mapID] or NONE
end

-- (1.1) Two or more other players found that the quest giver never offers it.
-- (1.3.5) Two through guild or group, or CONFIRM_NOT_HERE in all: it hides a quest.
function ns.SharedNotHere(questID)
  return Best(ns.db and ns.db.shared and ns.db.shared["N " .. tostring(questID)], CONFIRM_NOT_HERE, true) ~= nil
end
function ns.SharedNotHereCount()
  local n = 0
  for key, e in pairs(ns.db and ns.db.shared or {}) do
    if type(key) == "string" and key:sub(1, 2) == "N " and Best(e, CONFIRM_NOT_HERE) then
      local id = tonumber(key:sub(3))
      local hidden, why = ns.NeverOffered(id)
      if hidden and why == "shared" then n = n + 1 end
    end
  end
  return n
end

-- (1.3.6) Entrances of a dungeon others confirmed: { { map, x, y (0-1), reporters }, ... }
local entrCache, entrVersion = nil, -1
function ns.SharedEntrances(inst)
  if entrVersion ~= version or not entrCache then
    entrCache, entrVersion = {}, version
    for key, e in pairs(ns.db and ns.db.shared or {}) do
      local id = type(key) == "string" and tonumber(key:match("^E (%d+) "))
      e = id and Decode(e) -- (A5)
      if id and type(e) == "table" and type(e.v) == "table" then
        for _, v in ipairs(e.v) do -- every confirmed way in, not only the most reported one
          if type(v) == "table" and v.m and Confirmed(v) then
            entrCache[id] = entrCache[id] or {}
            table.insert(entrCache[id], { v.m, v.x / 100, v.y / 100, v.n })
          end
        end
      end
    end
  end
  return entrCache[inst] or {}
end

function ns.SharedVersion() return version end

-- (1.3.8) players of a class who picked each reward of a quest (all talent trees): { [itemID] = players }
function ns.SharedRewardPicks(questID, class)
  local out = {}
  local pre = ("R %d %d "):format(tonumber(questID) or 0, tonumber(class) or 0)
  for key, e in pairs(ns.db and ns.db.shared or {}) do
    e = type(key) == "string" and key:sub(1, #pre) == pre and Decode(e) -- (A5)
    if e and type(e.v) == "table" then
      local item = tonumber(key:match(" (%d+)$"))
      local n = 0
      for _, v in ipairs(e.v) do n = n + (ns.Num(v.n) or 0) end
      if item then out[item] = (out[item] or 0) + n end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Diagnostics, reset
---------------------------------------------------------------------------
function ns.ShareDiag()
  local shared = ns.db and ns.db.shared or {}
  local facts, confirmed = 0, 0
  for _, e in pairs(shared) do
    facts = facts + 1
    if Best(e) then confirmed = confirmed + 1 end
  end
  local state, name, id, joins = ns.ShareChannelState()
  return ("%s, channel %s%s, sent %d facts in %d messages (again %d, left out as known %d), received %d lines in %d messages (via channel %d; bad %d, limited %d, own %d, other ways %d), blocked %d, shared %d facts (confirmed %d), pruned %d"):format(
    ns.db and ns.db.shareLearned and "on" or "off", tostring(state), name and (" " .. name .. " #" .. tostring(id or "?") .. ", joins " .. joins) or "",
    stats.sentFacts, stats.sentMsgs, stats.resentFacts, stats.saved, stats.recvLines, stats.recvMsgs, stats.recvChannel,
    stats.bad, stats.limited, stats.own, stats.otherWay, stats.blocked, facts, confirmed, stats.pruned)
end

function ns.ResetShared()
  local db = DB()
  wipe(db.shared)
  sharedCount, version, placeVersion = 0, version + 1, placeVersion + 1
  pruneGen, spotCache = pruneGen + 1, nil -- (16.10.) every quest's places anew
  Forget() -- (A5)
  -- (23.10.) learned data deleted (Options.lua calls this): the kept send list goes too
  backlog.list, backlog.pos, backlog.fp, backlog.at = nil, 1, nil, 0
  quiet.fp, quiet.nextDue = nil, nil
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.On("CHAT_MSG_ADDON", OnMessage)

local ticker
ns.OnInit(function()
  Register()
  -- every FLUSH_GAP seconds for the whole session (C_Timer.NewTicker repeats)
  if not ticker and C_Timer and type(C_Timer.NewTicker) == "function" then
    ticker = C_Timer.NewTicker(FLUSH_GAP, function()
      ns.SafeCall("share channel", ns.ShareChannelTick)
      ns.SafeCall("share", ns.ShareFlush)
    end)
  end
  -- (1.1) the open channel: shortly after login, then the join is checked
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(JOIN_DELAY, function() ns.SafeCall("share channel", ns.ShareChannelTick) end)
    C_Timer.After(JOIN_DELAY + JOIN_CHECK + 1, function() ns.SafeCall("share channel", ns.ShareChannelTick) end)
  end
end)
