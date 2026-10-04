local _, ns = ...
local L = ns.L

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local LAST_BAG = NUM_BAG_SLOTS or 4 -- backpack + 4 bags, reagent bag excluded

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------
-- quiet: say nothing if the gold is short (junk is still being sold, see below).
-- Returns true if the own gold was not enough.
local function Repair(quiet)
  if not ns.db.autoRepair or not CanMerchantRepair() then return end
  local cost, needed = GetRepairAllCost()
  if not needed or cost <= 0 then return end

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
        list[#list + 1] = { bag = bag, slot = slot, value = value }
      end
    end
  end
  return list, total
end

-- after: runs once all junk is sold while the merchant is still open.
local function SellJunk(list, after)
  if ticker then ticker:Cancel() ticker = nil end
  if #list == 0 then return end

  local i, earned = 0, 0
  ticker = ns.NewTicker(0.15, function(t)
    i = i + 1
    local entry = list[i]
    if not entry or not (MerchantFrame and MerchantFrame:IsShown()) then
      t:Cancel()
      ticker = nil
      if i > 1 then
        ns.Print(L["Sold %d junk items for %s."]:format(i - 1, ns.Money(earned)))
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
  end, #list + 1)
end

ns.On("MERCHANT_SHOW", function()
  if ns.IsPaused() then return end
  local junk = ns.db.sellJunk and CollectJunk() or {}
  -- Gold short for the repair? Sell the junk first, then try again.
  local short = Repair(#junk > 0)
  SellJunk(junk, short and function() Repair() end or nil)
end)

ns.On("MERCHANT_CLOSED", function()
  if ticker then ticker:Cancel() ticker = nil end
end)

---------------------------------------------------------------------------
-- Fast loot
---------------------------------------------------------------------------
ns.On("LOOT_READY", function()
  if not ns.db.fastLoot then return end
  -- Same rule as Blizzard auto loot: CVar xor the auto loot modifier key.
  if GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then return end
  for i = GetNumLootItems(), 1, -1 do
    LootSlot(i)
  end
end)
