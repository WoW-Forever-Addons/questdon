local _, ns = ...

---------------------------------------------------------------------------
-- (30.10.2026, DONCORE_PLAN.md "DonData") The quest data lives in the addon DonData ("## Dependencies: DonData",
-- the game loads it first). Its tables are taken over into Questdon's ns here, where the Data\ files stood in the
-- toc, so every module reads ns.ATT_QUESTS, ns.SPAWNS, ns.QUEST_TEXTS ... as before. Same tables, no copy: what
-- Questdon learns while playing goes into them as it did into its own.
---------------------------------------------------------------------------
local NEED = 3 -- DonData.version this Questdon was built for (versions are only added to, see DonData.lua; 2: the engine, 3: the dungeons)

local D = DonData
if type(D) == "table" and type(D.tables) == "table" and (tonumber(D.version) or 0) >= NEED then
  for k, v in pairs(D.tables) do
    if ns[k] == nil then ns[k] = v end
  end
  ns.DONDATA_VERSION = D.version
  -- a Forever DonData on Classic Era (or the other way round) gives the wrong maps: say so once
  -- (31.10.2026, Kritikrunde) compared with the client itself: ns.ERA comes from DonData's own Engine/Classic.lua since
  -- the namespace is one (Link.lua), so ns.ERA against D.era always agreed. Interface 11xxx is Classic Era, 16xxx WoW
  -- Forever; any other client (tests, a new flavor) is not judged
  local okB, _, _, _, toc = pcall(GetBuildInfo)
  toc = okB and tonumber(toc) or nil
  local clientEra
  if toc and toc >= 11000 and toc < 12000 then clientEra = true elseif toc and toc >= 16000 and toc < 17000 then clientEra = false end
  if clientEra ~= nil and clientEra ~= (D.era and true or false) then ns.DONDATA_WRONG_GAME = true end
else
  ns.DONDATA_MISSING = true
end

if ns.DONDATA_MISSING or ns.DONDATA_WRONG_GAME then
  ns.On("PLAYER_LOGIN", function()
    ns.Print(ns.DONDATA_MISSING and "the addon DonData (Questdon's quest data) is missing or too old: please install or update it."
      or "DonData is not the version for this game (WoW Forever or Classic Era): please install the right one.")
  end)
end
