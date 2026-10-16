local _, ns = ...
local L = ns.L

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local LAST_BAG = NUM_BAG_SLOTS or 4 -- backpack + 4 bags, reagent bag excluded

---------------------------------------------------------------------------
-- (1.3.8) Another addon already does it: Questdon steps back
---------------------------------------------------------------------------
-- Two addons selling the same junk or looting the same window get in each
-- other's way. Leatrix Plus keeps its switches in LeaPlusDB ("On"), ElvUI in
-- its profile (general.vendorGrays, general.autoRepair); single-purpose addons
-- count as soon as they are loaded. Said once per addon in the chat.
local OTHERS = {
  sellJunk = {
    lea = "AutoSellJunk",
    -- older ElvUI: general.vendorGrays; newer: bags.vendorGrays.enable (review 6, both looked at)
    elv = function(g, db)
      if g.vendorGrays == true then return true end
      local b = type(db.bags) == "table" and db.bags.vendorGrays
      return type(b) == "table" and b.enable == true
    end,
    addons = { "Scrap", "Vendor", "Peddler", "AutoVendor", "Dejunk", "SellJunk" },
  },
  autoRepair = {
    lea = "AutoRepairGear",
    elv = function(g) return type(g.autoRepair) == "string" and g.autoRepair ~= "NONE" end,
    addons = { "AutoRepair" },
  },
  fastLoot = {
    lea = "FasterLooting",
    addons = { "SpeedyAutoLoot", "FasterLoot", "AutoLootPlus" },
  },
}
local OPTION_NAME = { sellJunk = "Sell junk", autoRepair = "Auto repair", fastLoot = "Fast loot" }

local function ElvGeneral()
  if not ns.AddOnLoaded("ElvUI") then return end
  local elv = rawget(_G, "ElvUI")
  local E = type(elv) == "table" and elv[1]
  local db = type(E) == "table" and E.db
  local g = type(db) == "table" and db.general
  return type(g) == "table" and g or nil, db
end

-- Name of the addon that already does this comfort feature, or nil.
function ns.ComfortTakenBy(key)
  local o = OTHERS[key]
  if not o then return end
  local lea = rawget(_G, "LeaPlusDB")
  if type(lea) == "table" and lea[o.lea] == "On" and ns.AddOnLoaded("Leatrix_Plus") then
    return "Leatrix Plus"
  end
  if o.elv then
    local g, db = ElvGeneral()
    if g then
      local ok, yes = pcall(o.elv, g, db)
      if ok and yes then return "ElvUI" end
    end
  end
  for _, name in ipairs(o.addons) do
    if ns.AddOnLoaded(name) then return name end
  end
end

-- true if Questdon does this feature itself (switched on and nobody else does it).
local function Mine(key)
  if not ns.db[key] then return false end
  local other = ns.ComfortTakenBy(key)
  if not other then return true end
  ns.db.comfortLeft = type(ns.db.comfortLeft) == "table" and ns.db.comfortLeft or {}
  if ns.db.comfortLeft[key] ~= other then
    ns.db.comfortLeft[key] = other
    ns.Print(L["%s does this already: Questdon leaves \"%s\" to it."]:format(other, L[OPTION_NAME[key]]))
  end
  return false
end
ns.ComfortMine = Mine -- (tests)

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------
-- quiet: say nothing if the gold is short (junk is still being sold, see below).
-- Returns true if the own gold was not enough.
local function Repair(quiet)
  if not ns.db.autoRepair or not CanMerchantRepair() then return end
  local cost, needed = GetRepairAllCost()
  if not needed or cost <= 0 then return end
  if not Mine("autoRepair") then return end

  local guildAllowed = ns.db.useGuildRepair and IsInGuild()
    and CanGuildBankRepair and CanGuildBankRepair()
  if guildAllowed then
    RepairAllItems(true)
    -- Guild withdraw limit may block it: check and fall back to own gold.
    ns.After(0.5, function()
      local left, stillNeeded = GetRepairAllCost()
      if stillNeeded and left > 0 then
        if GetMoney() >= left then
          RepairAllItems()
          ns.Print(L["Repaired for %s."]:format(ns.Money(left)))
        else
          ns.Print(L["Not enough gold to repair (%s)."]:format(ns.Money(left)))
        end
      else
        ns.Print(L["Repaired for %s (guild bank)."]:format(ns.Money(cost)))
      end
    end)
    return
  end

  if GetMoney() >= cost then
    RepairAllItems()
    ns.Print(L["Repaired for %s."]:format(ns.Money(cost)))
  else
    if not quiet then ns.Print(L["Not enough gold to repair (%s)."]:format(ns.Money(cost))) end
    return true
  end
end

---------------------------------------------------------------------------
-- Sell junk (one item per tick to stay friendly to the server)
---------------------------------------------------------------------------
local ticker

local function CollectJunk()
  local list, total = {}, 0
  for bag = 0, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.quality == POOR and not info.hasNoValue and not info.isLocked then
        local price = ns.GetSellPrice(info.itemID) or 0
        local value = price * (info.stackCount or 1)
        total = total + value
        list[#list + 1] = { bag = bag, slot = slot, value = value, itemID = info.itemID }
      end
    end
  end
  return list, total
end

-- (1.3.5, Daniel 10.10.) The slot may hold something else by the time its turn comes (items
-- moved or looted while selling): sell only when the same grey item is still there.
local function StillJunk(entry)
  local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
  return type(info) == "table" and info.itemID == entry.itemID and info.quality == POOR
    and not info.hasNoValue and not info.isLocked
end
ns.JunkStillThere = StillJunk -- (tests)

-- after: runs once all junk is sold while the merchant is still open.
local function SellJunk(list, after)
  if ticker then ticker:Cancel() ticker = nil end
  if #list == 0 then return end

  local i, earned, sold = 0, 0, 0
  ticker = ns.NewTicker(0.15, function(t)
    i = i + 1
    local entry = list[i]
    while entry and not StillJunk(entry) do i = i + 1 entry = list[i] end -- changed slots are left alone
    if not entry or not (MerchantFrame and MerchantFrame:IsShown()) then
      t:Cancel()
      ticker = nil
      if sold > 0 then
        ns.Print(L["Sold %d junk items for %s."]:format(sold, ns.Money(earned)))
      end
      if after and not entry then
        -- give the server a moment to book the money
        ns.After(0.5, function()
          if MerchantFrame and MerchantFrame:IsShown() then after() end
        end)
      end
      return
    end
    C_Container.UseContainerItem(entry.bag, entry.slot)
    earned = earned + entry.value
    sold = sold + 1
  end, #list + 1)
end

local retryRepair = false
ns.On("PLAYER_MONEY", function()
  if retryRepair and MerchantFrame and MerchantFrame:IsShown() and not Repair(true) then retryRepair = false end
end)
ns.On("MERCHANT_SHOW", function()
  if ns.IsPaused() then return end
  local junk = ns.db.sellJunk and CollectJunk() or {}
  local otherSells = #junk > 0 and not Mine("sellJunk")
  if otherSells then junk = {} end
  -- Gold short for the repair? Sell the junk first, then try again.
  local short = Repair(#junk > 0 or otherSells)
  SellJunk(junk, short and function() Repair() end or nil)
  -- (review 6) another addon sells the junk: the repair again as its money comes in
  retryRepair = (short and otherSells) and true or false
end)

ns.On("MERCHANT_CLOSED", function()
  retryRepair = false
  if ticker then ticker:Cancel() ticker = nil end
end)

---------------------------------------------------------------------------
-- Fast loot
---------------------------------------------------------------------------
-- (1.1) Items the game asks about before looting (bind on pickup, quest items
-- such as "Nibbled-On Book") are left to Blizzard's own auto loot: when an
-- addon loots them, the confirmation runs inside the addon's call and taints
-- Blizzard's UI (Edit Mode, party frames, action bars in combat: "secret value
-- while execution tainted by Questdon"). Then the whole window is left to the
-- game. Unknown answers (item not cached yet, secret value) count as "asks".
local BIND_ON_PICKUP, BIND_QUEST = 1, 4
local lootStats = { windows = 0, fast = 0, leftToGame = 0 }
function ns.FastLootStats() return lootStats end

local function NeedsConfirm(slot)
  local slotType = ns.Num(ns.Value(GetLootSlotType, slot))
  if slotType and slotType ~= 1 then return false end -- money, currency
  if type(GetLootSlotInfo) ~= "function" then return true end
  local ok, _, _, _, _, _, locked, isQuestItem, questID = pcall(GetLootSlotInfo, slot)
  if not ok then return true end
  if locked ~= nil and (not ns.Usable(locked) or locked == true) then return true end
  if isQuestItem ~= nil and (not ns.Usable(isQuestItem) or isQuestItem == true) then return true end
  if questID ~= nil and (not ns.Usable(questID) or (ns.Num(questID) or 0) > 0) then return true end
  local link = ns.Value(GetLootSlotLink, slot)
  if type(link) ~= "string" then return true end
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if type(info) ~= "function" then return true end
  local got, bind = false, nil
  local r = { pcall(info, link) }
  if r[1] then got, bind = r[2] ~= nil, r[15] end
  if not got then return true end -- not cached: cannot tell
  bind = ns.Num(bind)
  if not bind then return true end
  return bind == BIND_ON_PICKUP or bind == BIND_QUEST
end
ns.LootSlotNeedsConfirm = NeedsConfirm

ns.On("LOOT_READY", function()
  if not ns.db.fastLoot then return end
  -- Same rule as Blizzard auto loot: CVar xor the auto loot modifier key.
  if GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then return end
  if not Mine("fastLoot") then return end
  lootStats.windows = lootStats.windows + 1
  local n = ns.Num(ns.Value(GetNumLootItems)) or 0
  for i = 1, n do
    if NeedsConfirm(i) then
      lootStats.leftToGame = lootStats.leftToGame + 1
      return -- the game loots this window itself
    end
  end
  for i = n, 1, -1 do
    LootSlot(i)
  end
  lootStats.fast = lootStats.fast + 1
end)
