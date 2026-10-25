local _, ns = ...

---------------------------------------------------------------------------
-- (22.10.2026, Daniel: "innkeepers and flight masters are best tracked by Questdon, Questdon is the base for
-- Leveldon") What an NPC is, noted when its window opens: the service NPCs of Forever's new zones (trainers, inns,
-- flight masters) are in no open source, so Questdon players fill them in, like the quest places.
--   v vendor (vr: also repairs), t:<CLASS> your class trainer, p profession trainer, f flight master,
--   i innkeeper (you made the inn your home), s spirit healer, b banker, a auctioneer, st stable master
-- Account wide, only with "Learn quest locations" on:
--   QuestdonDB.npcRoles[npcID] = { r = { [role] = count }, m = uiMapID, x = 0-1, y = 0-1 }   (the last place)
-- Exported as "V npc role map x y" (/qd export, Export.lua); the data build makes titles of them
-- (tools/open/build_leveldon_inputs.py) for Leveldon's train, bind and flight steps.
-- Events only, no hooks.
---------------------------------------------------------------------------
local MAX_NPCS = 3000
-- PLAYER_INTERACTION_MANAGER_FRAME_SHOW: Enum.PlayerInteractionType (client 1.60.1) -> role. Merchants and trainers
-- come from their own events (MERCHANT_SHOW, TRAINER_SHOW): those tell more (repairs, class or profession)
local INTERACTION_ROLE = { [6] = "f", [8] = "b", [18] = "s", [19] = "s", [20] = "i", [21] = "a", [22] = "st" }
ns.NPC_ROLE_BY_INTERACTION = INTERACTION_ROLE -- (tests)

local function Value(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
end

local function NpcID()
  local guid = Value(UnitGUID, "npc")
  return guid ~= nil and ns.CreatureIDFromGUID and ns.CreatureIDFromGUID(guid) or nil
end

local function Count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Notes a role of the NPC you talk to. Returns true when something was written.
function ns.NoteNpcRole(role)
  local db = ns.db
  if not (db and db.learnQuests ~= false and type(role) == "string" and role ~= "") then return false end
  local id = NpcID()
  if not id then return false end
  db.npcRoles = type(db.npcRoles) == "table" and db.npcRoles or {}
  local e = db.npcRoles[id]
  if type(e) ~= "table" then
    if Count(db.npcRoles) >= MAX_NPCS then return false end
    e = { r = {} }
    db.npcRoles[id] = e
  end
  e.r = type(e.r) == "table" and e.r or {}
  e.r[role] = math.min((tonumber(e.r[role]) or 0) + 1, 999)
  local m, x, y
  if ns.PlayerPosition then m, x, y = ns.PlayerPosition() end
  if m and x and y then
    e.m, e.x, e.y = m, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000
  end
  return true
end

local function OnMerchant()
  ns.NoteNpcRole(Value(CanMerchantRepair) and "vr" or "v")
end
---------------------------------------------------------------------------
-- (23.10.2026, Daniel: the Camping 101 hand-in differs per profession and zone, "can we read it while playing?")
-- Which professions a profession trainer teaches, noted as "p:<Token>" next to "p". The trainer's service names
-- are matched against the names of the professions' rank spells (QuestData.lua ns.SKILL_SPELLS), so it works in
-- every client language. Tokens are English letters only (the export line allows letters and colons).
---------------------------------------------------------------------------
local PROFESSION_TOKEN = {
  [129] = "FirstAid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
  [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
  [356] = "Fishing", [393] = "Skinning",
}
ns.PROFESSION_TOKEN = PROFESSION_TOKEN

local function SpellName(id)
  local n = C_Spell and Value(C_Spell.GetSpellName, id)
  if type(n) ~= "string" then n = Value(GetSpellInfo, id) end
  return type(n) == "string" and n ~= "" and n or nil
end

local tokenByName -- spell name -> token, built once (the names do not change in a session)
local function TokenByName()
  if tokenByName then return tokenByName end
  local byName, count = {}, 0
  for line, spells in pairs(ns.SKILL_SPELLS or {}) do
    local token = PROFESSION_TOKEN[line]
    if token then
      for _, id in ipairs(spells) do
        local name = SpellName(id)
        if name and not byName[name] then byName[name] = token count = count + 1 end
      end
    end
  end
  if count > 0 then tokenByName = byName end -- names not loaded yet: try again next time
  return byName
end
ns.TokenByNameReset = function() tokenByName = nil end -- (tests)

-- The sorted tokens of the professions the open trainer window teaches (empty: none or not readable).
function ns.TrainerProfessions()
  local out = {}
  local n = tonumber(Value(GetNumTrainerServices)) or 0
  if n <= 0 then return out end
  local byName = TokenByName()
  local seen = {}
  for i = 1, math.min(n, 200) do
    local name = Value(GetTrainerServiceInfo, i)
    local token = type(name) == "string" and byName[name]
    if token and not seen[token] then
      seen[token] = true
      out[#out + 1] = token
    end
  end
  table.sort(out)
  return out
end

local noted = {} -- tokens noted since this trainer window opened (TRAINER_SHOW and TRAINER_UPDATE both read it)
local function NoteProfessions()
  for _, token in ipairs(ns.TrainerProfessions()) do
    if not noted[token] then
      noted[token] = true
      ns.NoteNpcRole("p:" .. token)
    end
  end
end

local function OnTrainer()
  noted = {}
  if Value(IsTradeskillTrainer) then
    ns.NoteNpcRole("p")
    NoteProfessions()
  else
    local _, cls = Value(UnitClass, "player")
    if type(cls) == "string" and cls ~= "" then ns.NoteNpcRole("t:" .. cls) end
  end
end
local function OnInteraction(kind)
  local role = INTERACTION_ROLE[tonumber(kind) or -1]
  if role then ns.NoteNpcRole(role) end
end

ns.On("MERCHANT_SHOW", function() ns.SafeCall("npc role", OnMerchant) end)
ns.On("TRAINER_SHOW", function() ns.SafeCall("npc role", OnTrainer) end)
-- the service list may arrive after TRAINER_SHOW: read it again while the window is open
ns.On("TRAINER_UPDATE", function()
  if Value(IsTradeskillTrainer) then ns.SafeCall("npc role", NoteProfessions) end
end)
ns.On("TRAINER_CLOSED", function() noted = {} end)
ns.On("TAXIMAP_OPENED", function() ns.SafeCall("npc role", ns.NoteNpcRole, "f") end)
ns.On("CONFIRM_BINDER", function() ns.SafeCall("npc role", ns.NoteNpcRole, "i") end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) ns.SafeCall("npc role", OnInteraction, kind) end)

-- Export lines "V npc role map x y" (percent, one decimal), every role of every NPC noted.
function ns.NpcRoleRecords()
  local out = {}
  local roles = type(ns.db and ns.db.npcRoles) == "table" and ns.db.npcRoles or {}
  local ids = {}
  for id in pairs(roles) do if type(id) == "number" then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local e = roles[id]
    if type(e) == "table" and type(e.r) == "table" and type(e.m) == "number" and type(e.x) == "number" and type(e.y) == "number" then
      local list = {}
      for role in pairs(e.r) do if type(role) == "string" and role:match("^[%a:]+$") then list[#list + 1] = role end end
      table.sort(list)
      for _, role in ipairs(list) do
        out[#out + 1] = ("V %d %s %d %.1f %.1f"):format(id, role, e.m, e.x * 100, e.y * 100)
      end
    end
  end
  return out
end
