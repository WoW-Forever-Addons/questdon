local _, ns = ...
local L = ns.L
local Style = ns.Style

---------------------------------------------------------------------------
-- Panel (1.19: built with the family kit Style.lua). A dark, flat window with
-- the wordmark in the header bar (drag there, collapse, close). Lines are kit
-- rows: label on the left in the secondary colour, value on the right. Rows
-- grow with their wrapped text, the kit stacks them and sizes the window.
-- Sections ("Experience", "Quests", "Group", "Clean up") get a header only
-- when more than one of them has something to show.
--
-- (1.17) Refreshes from the ticker and events skip the rebuild when the
-- content signature is unchanged; only the mouse actions get new closures.
--
-- (1.20) Collapsed, the most useful line stays visible (kit v2
-- SetKeepWhenCollapsed): next quest, else a nearly full quest log, else the
-- XP of finished quests. The collapse state is saved as before (panelCollapsed).
---------------------------------------------------------------------------
local DEFAULT_WIDTH, MAX_WIDTH = 300, 500
local MAX_TOOLTIP = 30
local SECTIONS = { "xp", "quests", "group", "cleanup" }
local SECTION_TITLE = { xp = "Experience", quests = "Quests", group = "Group", cleanup = "Clean up" }
local panel
local confirmID, confirmUntil -- two-step abandon
local destroyID, destroyUntil -- (1.0) two-step destroy of an unneeded quest item
local built = {} -- rows of the last build, same order as the content
local lastSig

local function PanelWidth()
  local w = tonumber(ns.db and ns.db.panelWidth) or DEFAULT_WIDTH
  if w ~= w then w = DEFAULT_WIDTH end
  return math.max(Style.SPACING.minWidth, math.min(MAX_WIDTH, math.floor(w + 0.5)))
end

-- Kit keys -> saved variables (names kept from earlier versions)
local KEYS = {
  pos = "panelPos", locked = "panelLocked", scale = "panelScale", alpha = "panelAlpha",
  collapsed = "panelCollapsed", combatFade = "panelCombatFade", shown = "showPanel",
}
local function Get(key) local k = KEYS[key]; return k and ns.db and ns.db[k] end
local function Set(key, value) local k = KEYS[key]; if k and ns.db then ns.db[k] = value end end

-- (1.22) "[?]" for a quest without a known level (never guessed)
local function LevelTag(questID)
  return ns.QuestLevelTag(questID)
end

local function Hours(h)
  return ("%d:%02d h"):format(math.floor(h), math.floor(h % 1 * 60))
end

local function Abandon()
  local grey = ns.GreyQuests()
  local first = grey[1]
  if not first then return end
  if confirmID == first.questID and confirmUntil and GetTime() < confirmUntil then
    if ns.AbandonQuest(first.questID) then
      ns.Print(L["Abandoned: %s"]:format(first.title or first.questID))
    end
    confirmID = nil
  else
    confirmID, confirmUntil = first.questID, GetTime() + 4
  end
  ns.UpdatePanel()
end

-- (1.0) Destroys the first unneeded quest item: two clicks within 4 seconds.
local function FirstSure(orphans)
  for _, o in ipairs(orphans) do if o.sure then return o end end
end

local function DestroyItem()
  local first = FirstSure(ns.OrphanQuestItems())
  if not first then return end
  if destroyID == first.itemID and destroyUntil and GetTime() < destroyUntil then
    if ns.DestroyQuestItem(first.itemID) then
      ns.Print(L["Destroyed: %s"]:format(first.link or first.itemID))
    end
    destroyID = nil
  else
    destroyID, destroyUntil = first.itemID, GetTime() + 4
  end
  ns.UpdatePanel()
end

local function ItemName(o)
  return o.link and o.link:match("%[(.-)%]") or ("item:" .. tostring(o.itemID))
end

local function ConfirmActive(grey)
  local first = grey and grey[1]
  return first and confirmID == first.questID and confirmUntil and GetTime() < confirmUntil and true or false
end

---------------------------------------------------------------------------
-- Content: { section, label, value, valueColor, text, textColor, main,
--            tooltip = fn() -> title, lines, hint, onClick, kind }
---------------------------------------------------------------------------
local function BuildLines()
  local out = {}
  local function Add(e) out[#out + 1] = e return e end

  -- Experience (1.2: only while the XP bar is off; the bar shows the same
  -- numbers, the window would repeat them with a different XP/h refresh)
  if not ns.AtMaxLevel() and not ns.db.xpBar then
    local xp, count, unknown = ns.CompletedQuestXP()
    Add({ section = "xp", kind = "finished", label = L["Finished quests (%d)"]:format(count),
      value = L["+%s XP"]:format(Style.Number(xp)) .. (unknown > 0 and Style.Colorize(" ?", "textHint") or ""),
      valueColor = count > 0 and "warning" or nil })
    if count > 0 then
      local level, fraction = ns.LevelAfter(xp)
      if not level then
        -- XP values hidden by the client: no forecast
      elseif fraction then
        Add({ section = "xp", label = L["After turning in"], value = L["Level %d (%s)"]:format(level, Style.Percent(fraction)), valueColor = "good" })
      else
        Add({ section = "xp", label = L["After turning in"], value = L["at least level %d"]:format(level), valueColor = "good" })
      end
    end
    local rested = ns.Num(ns.Value(GetXPExhaustion))
    if rested and rested > 0 then
      Add({ section = "xp", label = L["Rested"], value = L["%s XP"]:format(Style.Number(rested)), valueColor = "accent" })
    end
    local xph = ns.XPPerHour()
    local cur, max = ns.Num(ns.Value(UnitXP, "player")), ns.Num(ns.Value(UnitXPMax, "player"))
    if xph and xph > 0 and cur and max then
      Add({ section = "xp", label = L["XP per hour"], value = Style.Number(math.floor(xph)) })
      Add({ section = "xp", label = L["Time to next level"], value = Hours(math.max(0, max - cur) / xph) })
    end
  end

  -- Quests
  local mapID = ns.Num(ns.Value(C_Map.GetBestMapForUnit, "player"))
  local available
  if mapID and ns.AvailableQuestsOnMap and (ns.db.availablePins or ns.db.nextQuestHint) then
    available = ns.AvailableQuestsOnMap(mapID)
  end

  if ns.db.nextQuestHint and available and ns.NearestAvailableQuest then
    local n = ns.NearestAvailableQuest(available, mapID)
    if n then
      -- (1.25) while you work in the area of your tracked quest's objective,
      -- the next quest stays a quiet line: hint colour, and not the line kept
      -- when the window is collapsed
      local quiet = ns.ArrowInArea and ns.ArrowInArea() or false
      Add({ section = "quests", kind = "next", quiet = quiet or nil,
        text = Style.Colorize(L["Nearest quest"] .. ": ", "textSecondary") .. LevelTag(n.questID) .. ns.QuestTitle(n.questID),
        value = L["%d yards"]:format(n.dist), valueColor = quiet and "textHint" or nil,
        tooltip = function()
          local lv = ns.QuestLevel(n.questID)
          local lines = {}
          if lv then lines[#lines + 1] = { L["Level"], lv } else lines[#lines + 1] = { L["Level"], L["unknown"], "textHint" } end
          lines[#lines + 1] = { L["Distance"], L["%d yards"]:format(n.dist) }
          -- (1.24) who says it is available: the game, the quest giver or only the data
          local src = ns.AvailabilitySource and ns.AvailabilitySource(n.questID)
          if src and ns.AVAILABLE_SHORT then
            lines[#lines + 1] = { L["Available"], ns.AVAILABLE_SHORT[src], src == "database" and "textHint" or "good" }
          end
          return ns.QuestTitle(n.questID), lines, ns.QuestPinHint and ns.QuestPinHint({ questID = n.questID }) or L["Click: point the arrow here"]
        end,
        onClick = function()
          -- (1.1) Alt-click: "no quest here" (NotHere.lua)
          if ns.True(ns.Value(IsAltKeyDown)) and ns.ReportNotHere then
            ns.ReportNotHere({ n.questID })
            return
          end
          if ns.SetArrowTarget then
            ns.db.arrow = true
            if ns.ApplyArrow then ns.ApplyArrow() end
            ns.SetArrowTarget(n.mapID, n.x, n.y, ns.QuestTitle(n.questID))
          end
        end,
      })
    end
  end

  if ns.db.availablePins and available and #available > 0 then
    Add({ section = "quests", label = L["Available quests here"], value = Style.Number(#available),
      tooltip = function()
        local lines = {}
        for i = 1, math.min(#available, MAX_TOOLTIP) do
          lines[#lines + 1] = LevelTag(available[i].questID) .. ns.QuestTitle(available[i].questID)
        end
        return L["Available quests here"], lines, L["Shown as ! on the world map."]
      end })
  end

  -- (1.18) dungeon quests: in the log and to pick up, per dungeon in the tooltip
  if ns.db.dungeonQuests and ns.DungeonOverview then
    local overview = ns.DungeonOverview()
    if #overview > 0 then
      local inLog, toTake = ns.DungeonCounts(overview)
      Add({ section = "quests", kind = "dungeons", label = L["Dungeon quests"],
        value = L["%d in log, %d to pick up"]:format(inLog, toTake),
        tooltip = function()
          local lines, n = {}, 0
          for _, l in ipairs(ns.DungeonTooltipLines(overview)) do
            if n >= MAX_TOOLTIP then lines[#lines + 1] = L["... more with /qd dungeons"] break end
            n = n + 1
            if l.header then
              lines[#lines + 1] = { header = l.text } -- (1.20) kit v2 sub-heading
            else
              -- (1.20) own fields: a title with ": " no longer splits wrongly
              lines[#lines + 1] = { "  " .. (l.title or l.text), l.state or "", l.inLog and "good" or "warning" }
            end
          end
          return L["Dungeon quests"], lines,
            toTake > 0 and L["Click: point the arrow to the nearest quest giver"] or nil
        end,
        onClick = function() if ns.PointToDungeonQuest then ns.PointToDungeonQuest() end end,
      })
    end
  end

  -- (1.16) Quest log slots: only as an extra line, or alone when nearly full.
  local n, max = ns.QuestLogCount()
  local slots
  if max then
    local color = n >= max and "critical" or (n >= max - 3 and "warning") or nil
    slots = { section = "quests", kind = "slots", label = L["Quests in log"], value = ("%d/%d"):format(n, max), valueColor = color, nearlyFull = n >= max - 3 }
  end

  -- (1.18) group progress (members with Questdon)
  if ns.db.partyProgress and ns.PartyMemberCount and ns.PartyMemberCount() > 0 then
    local po = ns.PartyOverview()
    Add({ section = "group", kind = "group", label = L["Group progress"],
      value = L["%d shared, %d to pick up"]:format(#po.shared, #po.takeable),
      tooltip = function()
        local lines, count = {}, 0
        for _, id in ipairs(po.shared) do
          if count >= MAX_TOOLTIP then break end
          count = count + 1
          lines[#lines + 1] = { header = ns.QuestTitle(id) } -- (1.20) kit v2 sub-heading
          lines[#lines + 1] = { "  " .. L["You"], ns.IsQuestComplete(id) and L["done"] or ns.QuestProgressText(id) or L["in log"],
            ns.IsQuestComplete(id) and "good" or "textPrimary" }
          for _, p in ipairs(ns.PartyProgress(id)) do
            lines[#lines + 1] = { "  " .. p.name, ns.PartyStateText(p), p.complete and "good" or (p.failed and "critical") or "textPrimary" }
          end
        end
        if #po.takeable > 0 then
          lines[#lines + 1] = { header = L["Your group has, you can pick up:"] }
          for i = 1, math.min(#po.takeable, MAX_TOOLTIP) do
            local id = po.takeable[i]
            lines[#lines + 1] = { "  " .. ns.QuestTitle(id), table.concat(ns.PartyMembersWithQuest(id), ", ") }
          end
        end
        return L["Group progress"], lines, nil
      end,
    })
  end

  -- Clean up
  local grey = ns.GreyQuests()
  if #grey > 0 then
    Add({ section = "cleanup", label = L["Grey quests"], value = Style.Number(#grey), valueColor = "warning",
      tooltip = function()
        local lines = {}
        for i = 1, math.min(#grey, MAX_TOOLTIP) do
          lines[#lines + 1] = ("[%d] %s"):format(grey[i].level or 0, grey[i].title or grey[i].questID)
        end
        return L["Grey quests"], lines, L["No XP left for your level."]
      end })
  end

  local orphans = ns.OrphanQuestItems()
  if #orphans > 0 then
    Add({ section = "cleanup", label = L["Quest items without quest"], value = Style.Number(#orphans), valueColor = "warning",
      tooltip = function()
        local lines = {}
        for i = 1, math.min(#orphans, MAX_TOOLTIP) do
          local line = orphans[i].link or ("item:" .. orphans[i].itemID)
          -- (1.0) the quest the data knows the item from
          if orphans[i].quest then line = line .. "  " .. orphans[i].quest end
          if not orphans[i].sure then line = line .. "  ?" end
          lines[#lines + 1] = line
        end
        return L["Probably no longer needed"], lines, nil
      end })
  end

  -- abandon: an action row, two clicks within 4 seconds, never in combat
  if #grey > 0 and not InCombatLockdown() then
    local first = grey[1]
    local confirm = ConfirmActive(grey)
    Add({ section = "cleanup", kind = "abandon",
      text = confirm and L["Click again: abandon %s"]:format(first.title or first.questID)
        or (L["Abandon grey quest"] .. ": " .. tostring(first.title or first.questID)),
      textColor = confirm and "critical" or "accent",
      tooltip = function()
        return L["Abandon grey quest"], { { tostring(first.title or first.questID), ("[%d]"):format(first.level or 0) } },
          L["Click twice within 4 seconds to abandon."]
      end,
      onClick = ns.Guard("panel", Abandon),
    })
  end

  -- (1.0) destroy an unneeded quest item: an action row, two clicks within 4 seconds, never in combat
  local sureItem = FirstSure(orphans)
  if sureItem and not InCombatLockdown() then
    local first = sureItem
    local confirm = destroyID == first.itemID and destroyUntil and GetTime() < destroyUntil
    Add({ section = "cleanup", kind = "destroy",
      text = confirm and L["Click again: destroy %s"]:format(ItemName(first))
        or (L["Destroy unneeded quest item"] .. ": " .. ItemName(first)),
      textColor = confirm and "critical" or "accent",
      tooltip = function()
        return L["Destroy unneeded quest item"], { { first.link or ItemName(first), first.quest or "" } },
          L["Click twice within 4 seconds to destroy. This cannot be undone."]
      end,
      onClick = ns.Guard("panel", DestroyItem),
    })
  end

  if slots and (#out > 0 or slots.nearlyFull) then
    -- after the other quest lines, before group and clean up
    local at = #out + 1
    for i, e in ipairs(out) do
      if e.section == "group" or e.section == "cleanup" then at = i break end
    end
    table.insert(out, at, slots)
  end
  return out, grey
end
ns.PanelContent = BuildLines

---------------------------------------------------------------------------
-- Signature (1.17): everything that changes what the panel shows
---------------------------------------------------------------------------
local function PanelSignature(content, grey)
  local parts = { tostring(PanelWidth()), InCombatLockdown() and "c" or "" }
  for _, e in ipairs(content) do
    parts[#parts + 1] = table.concat({ tostring(e.section), tostring(e.label or ""), tostring(e.text or ""),
      tostring(e.value or ""), tostring(e.valueColor or ""), tostring(e.textColor or ""),
      e.tooltip and "T" or "", e.onClick and "C" or "" }, "\2")
  end
  local first = grey and grey[1]
  parts[#parts + 1] = first and (tostring(first.questID) .. ":" .. tostring(first.title)) or "-"
  parts[#parts + 1] = ConfirmActive(grey) and "confirm" or ""
  return table.concat(parts, "\1")
end
local panelStats = { layouts = 0, skipped = 0 }
function ns.PanelStats() return panelStats end

local function SectionCount(content)
  local seen, n = {}, 0
  for _, e in ipairs(content) do
    if not seen[e.section] then seen[e.section] = true n = n + 1 end
  end
  return n
end

-- (1.20) The line that stays visible when the window is collapsed: the next
-- quest, else a nearly full quest log, else the XP of finished quests.
local function KeepEntry(content)
  local best, rank
  for _, e in ipairs(content) do
    local r = (e.kind == "next" and not e.quiet and 1) or (e.kind == "slots" and e.nearlyFull and 2) or (e.kind == "finished" and 3) or nil
    if r and (not rank or r < rank) then best, rank = e, r end
  end
  return best
end
ns.PanelKeepEntry = KeepEntry

-- Collapsing would hide nothing when the kept line is all there is: the
-- button is disabled then (kit v2), but stays usable to expand again.
local function UpdateCollapseButton()
  local collapse = panel and panel:GetButton("collapse")
  if collapse then collapse:SetEnabled(not panel._qdOnlyKept or panel:IsCollapsed()) end
end

-- (1.3) A clear button for the quest book at the bottom of the window
-- (option "bookButton"); the small icon in the title bar only when it is off.
local bookButton
local function BookButton()
  if bookButton then return bookButton end
  local C = Style.COLORS
  local b = CreateFrame("Button", nil, UIParent)
  b:SetHeight(24)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints(b)
  local function Bg(a) if b.bg.SetColorTexture then b.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], a) end end
  Bg(0.14)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT", b, "LEFT", 6, 0)
  b.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetText(Style.Colorize(L["Quest book"], "accent"))
  b.hint = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.hint:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.hint:SetText(L["Journal, zones, search"])
  b:SetScript("OnEnter", function(self)
    Bg(0.26)
    Style.Tooltip(self, L["Quest book"], nil, L["Your journal, the quests of the zone and a search over all quests. /qd journal, /qd zone"], "auto")
  end)
  b:SetScript("OnLeave", function(self) Bg(0.14) Style.HideTooltip(self) end)
  b:SetScript("OnClick", function() if ns.ToggleQuestBook then ns.ToggleQuestBook() end end)
  bookButton = b
  return b
end
ns.PanelBookButton = function() return bookButton end

local function Build(content)
  panel:ClearRows()
  built = {}
  local keep = KeepEntry(content)
  panel._qdOnlyKept = keep ~= nil and #content == 1
  UpdateCollapseButton()
  local headers = SectionCount(content) > 1
  for _, section in ipairs(SECTIONS) do
    local first = true
    for _, e in ipairs(content) do
      if e.section == section then
        if first and headers then Style.Header(panel, L[SECTION_TITLE[section]]) end
        first = false
        local row = Style.Row(panel)
        if e.label then
          Style.KeyValue(row, e.label, e.value, e.valueColor)
        else
          row:SetText(e.text, e.textColor or "textPrimary")
          if e.value then row:SetValue(e.value, e.valueColor) end
        end
        row:SetTooltip(e.tooltip)
        row:SetOnClick(e.onClick)
        if e == keep then row:SetKeepWhenCollapsed(true) end
        row._qdEntry = e
        built[#built + 1] = row
      end
    end
  end
  -- the small icon in the title bar only when the big button is off
  local icon = panel:GetButton("zone")
  if ns.db.bookButton ~= false then
    Style.Content(panel, BookButton(), 24, { gapBefore = 6 })
    if icon then icon:Hide() end
  else
    if bookButton then bookButton:Hide() end
    if icon then icon:Show() end
  end
end

local function PanelScale()
  return ns.Look.Clamp(ns.db.panelScale, Style.SCALE_MIN, Style.SCALE_MAX, 1)
end

-- Settings from the saved variables, without saving them again.
local function ApplyLook()
  panel._width = PanelWidth()
  panel:SetLocked(ns.db.panelLocked, true)
  if panel._scale ~= PanelScale() then panel:SetPanelScale(PanelScale(), true) end
  if panel._bgAlpha ~= ns.db.panelAlpha then panel:SetBackgroundAlpha(ns.db.panelAlpha, true) end
  panel._combatFade = ns.db.panelCombatFade and true or false
end

-- mode "ifChanged" (1.17, ticker and events): skip the rebuild when the
-- content signature is the same; only the mouse actions get the new closures.
function ns.UpdatePanel(mode)
  if not panel then return end
  if not ns.db.showPanel then lastSig = nil panel:Hide() return end
  local content, grey = BuildLines()
  if #content == 0 then
    lastSig = nil
    panel:ClearRows()
    built = {}
    panel:Hide()
    return
  end
  local sig = PanelSignature(content, grey)
  if mode == "ifChanged" and lastSig and panel:IsShown() and sig == lastSig and #built == #content then
    local byOrder = {}
    for _, section in ipairs(SECTIONS) do
      for _, e in ipairs(content) do if e.section == section then byOrder[#byOrder + 1] = e end end
    end
    for i, row in ipairs(built) do
      local e = byOrder[i]
      row:SetTooltip(e.tooltip)
      row:SetOnClick(e.onClick)
      row._qdEntry = e
    end
    panelStats.skipped = panelStats.skipped + 1
    return
  end
  ApplyLook()
  Build(content)
  if not panel:IsShown() then panel:FadeIn() end
  Style.Relayout(panel)
  panelStats.layouts = panelStats.layouts + 1
  lastSig = sig
end

-- Options (Appearance page)
function ns.ApplyPanelLook()
  if not panel then return end
  panel:SetLocked(ns.db.panelLocked, true)
  panel:SetPanelScale(PanelScale(), true)
  panel:SetBackgroundAlpha(ns.db.panelAlpha, true)
  Style.CombatFade(panel, ns.db.panelCombatFade)
  panel:SetPanelWidth(PanelWidth())
  lastSig = nil
  ns.UpdatePanel()
end

function ns.ResetPanelPosition()
  if panel then panel:ResetPosition() else ns.db.panelPos = nil end
end

-- Kept for older callers: the kit relayouts by itself.
function ns.QueuePanelRelayout() if panel then Style.RequestRelayout(panel) end end

-- For tests and /qd diag: shown rows in order (kit rows; headers left out).
-- line: label and value as one plain string.
function ns.PanelRows()
  local out = {}
  for i, row in ipairs(built) do
    if row._inUse and row:IsShown() then
      local t, v = row.text:GetText() or "", row.value:GetText() or ""
      out[#out + 1] = { index = i, row = row, text = row.text, value = row.value, entry = row._qdEntry,
        line = v ~= "" and (t .. " " .. v) or t }
    end
  end
  return out
end
function ns.PanelFrame() return panel end

function ns.TogglePanel()
  if not panel then return end
  ns.db.showPanel = not ns.db.showPanel
  ns.UpdatePanel()
  if ns.db.showPanel and not panel:IsShown() then
    ns.Print(L["The panel is on, but has nothing to show right now."])
  end
end

-- (1.2) icon of the zone quest list button: added to this addon's copy of the
-- kit's icon table (Style.lua itself stays the shared file)
Style.ICONS.qdZoneList = Style.ICONS.qdZoneList or {
  atlas = { "questlog-icon-ticksquare", "questlog-icon-checkmark-yellow" },
  file = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
}

local function Create()
  panel = Style.Panel("QuestdonPanel", UIParent, {
    title = Style.Wordmark("Quest", "don"),
    width = PanelWidth(),
    close = true, collapse = true,
    closeTooltip = L["Hide window"],
    -- (1.2) options and the quest list of the zone, right in the title bar
    buttons = {
      { key = "options", kind = "options", tooltip = { L["Options"], nil, L["/qd opens them too."] },
        onClick = function() if ns.OpenOptions then ns.OpenOptions() end end },
      { key = "zone", kind = "qdZoneList", tooltip = { L["Quest book"], nil, L["Your journal, the quests of the zone and a search over all quests. /qd journal, /qd zone"] },
        onClick = function() if ns.ToggleQuestBook then ns.ToggleQuestBook() end end },
    },
    collapseTooltip = { L["Collapse or expand"], nil, L["Collapsed, one line stays: the next quest, a nearly full quest log or the XP of finished quests."] },
    get = Get, set = Set,
    defaultPoint = { "TOPRIGHT", "TOPRIGHT", -240, -220 },
    onCollapse = function() UpdateCollapseButton() end,
    onClose = function(p)
      ns.db.showPanel = false
      lastSig = nil
      p:FadeOut()
    end,
  })
end

-- (1.23) Batched with the other quest displays (Core.lua, 0.5 s).
ns.RegisterRefresh("panel", function() ns.UpdatePanel("ifChanged") end)
local function Queue() ns.QueueRefresh("panel") end

ns.OnInit(function()
  Create()
  ns.NewTicker(5, function() ns.UpdatePanel("ifChanged") end) -- XP/h and confirmation timeout
  -- once more after the first frame, when the fonts have their real size
  ns.After(0, function() ns.UpdatePanel() end)
end)
ns.On("PLAYER_ENTERING_WORLD", Queue)
ns.On("ZONE_CHANGED_NEW_AREA", Queue) -- (1.23) "available quests here" and the next quest belong to the zone
ns.On("QUEST_LOG_UPDATE", Queue)
ns.On("PLAYER_XP_UPDATE", Queue)
ns.On("BAG_UPDATE_DELAYED", Queue)
ns.On("PLAYER_REGEN_ENABLED", Queue)
ns.On("PLAYER_REGEN_DISABLED", Queue) -- abandon row hides in combat
