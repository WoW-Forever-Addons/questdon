local _, ns = ...

---------------------------------------------------------------------------
-- (1.3.11, Daniel 23.10.) Pictures in the journal (TAGEBUCH_PLAN.md, Stufe 2).
-- An addon cannot read the game's Screenshots folder, so the helper
-- "Questdon-Album" (a PowerShell script outside the game) copies each
-- screenshot as 1024 x 512 and 256 x 128 pictures into the small addon
-- Questdon_Album (its own folder, LoadOnDemand) and writes its Index.lua:
--   QuestdonAlbumIndex = { v = 1, ext = "jpg", { f = file name, t = time, a = width / height }, ... }
-- Questdon loads it when the journal wants pictures; nothing here runs on a
-- ticker. A screenshot entry of the journal (k = "s") and a picture belong
-- together when their times are at most MATCH_SECS apart. Pictures of other
-- characters (the folder is shared) or from before the journal stay in the
-- album; the player can take one into this character's journal.
---------------------------------------------------------------------------
local ALBUM = "Questdon_Album"
local DIR = "Interface\\AddOns\\Questdon_Album\\shots\\"
local MATCH_SECS = 5
local ASPECT = 16 / 9

local tried
local function Index()
  local t = rawget(_G, "QuestdonAlbumIndex")
  if type(t) == "table" then return t end
  if tried then return nil end
  tried = true
  local load = (C_AddOns and C_AddOns.LoadAddOn) or rawget(_G, "LoadAddOn")
  if type(load) == "function" then pcall(load, ALBUM) end
  t = rawget(_G, "QuestdonAlbumIndex")
  return type(t) == "table" and t or nil
end

-- the pictures of the album, newest first (cached per index table)
local shotsOf, shots
local EMPTY, NONE_E, NONE_S = {}, {}, {} -- shared, never filled
function ns.AlbumShots()
  local idx = Index()
  if not idx then return EMPTY end
  if shotsOf == idx and shots then return shots end
  local ext = (idx.ext == "tga" or idx.ext == "png") and idx.ext or "jpg"
  local out = {}
  for _, s in ipairs(idx) do
    local t = type(s) == "table" and ns.Num(s.t)
    if t and type(s.f) == "string" and s.f:match("^[%w_%-]+$") then
      local a = ns.Num(s.a)
      out[#out + 1] = { f = s.f, t = t, a = (a and a > 0.5 and a < 4) and a or ASPECT, ext = ext }
    end
  end
  table.sort(out, function(x, y) if x.t ~= y.t then return x.t > y.t end return x.f > y.f end)
  shotsOf, shots = idx, out
  return out
end

-- is the album there (the helper has run at least once)?
function ns.AlbumAvailable() return #ns.AlbumShots() > 0 end

-- the picture's file: big (1024 x 512) or small (256 x 128)
function ns.AlbumTexture(shot, small)
  if type(shot) ~= "table" or not shot.f then return nil end
  return DIR .. shot.f .. (small and "_s." or ".") .. (shot.ext or "jpg")
end

-- Texture coordinates that fill a box of w x h with the picture without
-- stretching it (the middle of the picture stays; "cover").
function ns.AlbumCover(shot, w, h)
  local a = type(shot) == "table" and shot.a or ASPECT
  local b = (ns.Num(w) or 1) / math.max(1, ns.Num(h) or 1)
  if b > a then
    local v = a / b
    return 0, 1, (1 - v) / 2, (1 + v) / 2
  end
  local v = b / a
  return (1 - v) / 2, (1 + v) / 2, 0, 1
end

-- Size of the whole picture inside a box of w x h ("contain").
function ns.AlbumFit(shot, w, h)
  local a = type(shot) == "table" and shot.a or ASPECT
  if w / h > a then return h * a, h end
  return w, w / a
end

---------------------------------------------------------------------------
-- Journal entry <-> picture (this character's screenshot entries)
---------------------------------------------------------------------------
local matchKey, byEntry, byShot
local function Match()
  local list = ns.AlbumShots()
  if #list == 0 then return NONE_E, NONE_S end
  local j = ns.JournalStore and ns.JournalStore()
  local last = j and j.e[#j.e]
  local key = tostring(list) .. ":" .. (j and #j.e or 0) .. ":" .. tostring(last and last.t)
  if key == matchKey then return byEntry, byShot end
  byEntry, byShot = {}, {}
  matchKey = key
  if not j then return byEntry, byShot end
  -- oldest first for both, then walk them side by side
  local asc = {}
  for i = #list, 1, -1 do asc[#asc + 1] = list[i] end
  local entries = {}
  for _, e in ipairs(j.e) do if type(e) == "table" and e.k == "s" and ns.Num(e.t) then entries[#entries + 1] = e end end
  table.sort(entries, function(x, y) return x.t < y.t end)
  local start = 1
  for _, e in ipairs(entries) do
    while start <= #asc and asc[start].t < e.t - MATCH_SECS do start = start + 1 end
    local best, bestD
    local i = start
    while i <= #asc and asc[i].t <= e.t + MATCH_SECS do
      local s = asc[i]
      local d = math.abs(s.t - e.t)
      if not byShot[s] and (not bestD or d < bestD) then best, bestD = s, d end
      i = i + 1
    end
    if best then byEntry[e] = best byShot[best] = e end
  end
  return byEntry, byShot
end

-- the picture of a journal entry (or of its window copy), or nil
function ns.AlbumShotFor(e)
  if type(e) ~= "table" then return nil end
  e = type(e.src) == "table" and e.src or e
  if e.k ~= "s" then return nil end
  local be = Match()
  return be[e]
end

-- the journal entry of a picture, or nil (another character's or older)
function ns.AlbumEntryFor(shot)
  local _, bs = Match()
  return shot and bs[shot] or nil
end

-- this character's pictures (with an entry), newest first
function ns.AlbumMine()
  local _, bs = Match()
  local out = {}
  for _, s in ipairs(ns.AlbumShots()) do if bs[s] then out[#out + 1] = s end end
  return out
end

-- Take a picture into this character's journal: a screenshot entry at the
-- picture's time (no zone or level, the game did not tell us), in its place.
function ns.AlbumAdopt(shot)
  if type(shot) ~= "table" or not shot.t then return nil end
  local have = ns.AlbumEntryFor(shot)
  if have then return have end
  local j = ns.JournalStore and ns.JournalStore()
  if not j then return nil end
  local e = { t = shot.t, k = "s", imp = 1 }
  local at = #j.e + 1
  while at > 1 do
    local prev = j.e[at - 1]
    if type(prev) == "table" and ns.Num(prev.t) and prev.t > shot.t then at = at - 1 else break end
  end
  if at == 1 and #j.e >= 5000 then return nil end -- older than all a full journal keeps (MAX_ENTRIES of Journal.lua)
  table.insert(j.e, at, e)
  while #j.e > 5000 do table.remove(j.e, 1) end
  matchKey = nil
  if ns.UpdateZoneQuests then ns.UpdateZoneQuests() end
  return e
end

-- (tests) forget the loaded index and the cache
function ns.AlbumReset() tried, shotsOf, shots, matchKey = nil, nil, nil, nil end

ns.ALBUM_MATCH_SECS = MATCH_SECS
ns.ALBUM_NAME = ALBUM
