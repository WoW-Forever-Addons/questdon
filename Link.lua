local _, ns = ...

---------------------------------------------------------------------------
-- (30.10.2026, DONCORE_PLAN.md "DonData Lese-Engine" L1) One namespace for Questdon and DonData. This is the first own file
-- of the toc (the DonCore files before it do not touch ns), so Questdon's ns is still empty here: it becomes a shell whose reads and writes all go to DonData's ns
-- (DonData.ns, DonData version 2). Every Questdon file reads and writes ns.X as before, the values live in DonData, and
-- the reading engine can move file by file into DonData without code changes on either side.
-- Without DonData (or an older one) ns stays Questdon's own table; DataLink.lua then says DonData is missing.
---------------------------------------------------------------------------
local D = DonData
-- (31.10.2026) 3: the dungeons' data part moved into the engine too (DonData/Engine/Dungeons.lua); with DonData 2 Questdon's
-- Dungeons.lua would miss it, so that counts as too old (like DataLink.lua's NEED)
local NEED = 3
if type(D) == "table" and (tonumber(D.version) or 0) >= NEED and type(D.ns) == "table" and next(ns) == nil then
  setmetatable(ns, { __index = D.ns, __newindex = D.ns })
elseif next(ns) == nil then
  -- (31.10.2026, Kritikrunde) DonData missing or older than NEED (Questdon updated, DonData not): the engine is not there,
  -- so every ns.X Questdon reads is a harmless stand-in (indexing and calling it gives itself, pairs over it nothing)
  -- instead of a flood of errors; QuestdonDB is left untouched. One chat line says what is missing.
  local hole
  hole = setmetatable({}, {
    __index = function() return hole end,
    __call = function() return hole end,
    __concat = function(a, b) return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "") end,
    __tostring = function() return "" end,
  })
  rawset(ns, "DONDATA_MISSING", true)
  setmetatable(ns, { __index = function() return hole end })
  if type(CreateFrame) == "function" then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
      print("|cff3fa9f5Questdon|r: the addon DonData (Questdon's quest data) is missing or too old: please install or update it.")
    end)
  end
end
