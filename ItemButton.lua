local _, ns = ...
local L = ns.L

BINDING_HEADER_QUESTDON = "Questdon"
_G["BINDING_NAME_CLICK QuestdonItemButton:LeftButton"] = L["Use quest item"]
_G["BINDING_NAME_CLICK QuestdonTargetButton:LeftButton"] = L["Target a quest mob"]

local LAST_BAG = NUM_BAG_SLOTS or 4
local button
local pendingRefresh = false

---------------------------------------------------------------------------
-- Find the item to show
---------------------------------------------------------------------------
-- Usable item of a quest in the log: the super-tracked quest's, else the first.
local function FromQuestLog()
  if not (C_QuestLog and GetQuestLogSpecialItemInfo) then return end
  local tracked = C_SuperTrack and ns.Num(ns.Value(C_SuperTrack.GetSuperTrackedQuestID))
  local first
  for i = 1, ns.Num(ns.Value(C_QuestLog.GetNumQuestLogEntries)) or 0 do
    local info = ns.Value(C_QuestLog.GetInfo, i)
    local questID = type(info) == "table" and not ns.True(info.isHeader) and ns.Num(info.questID)
    if questID then
      -- (1.0) a finished quest (ready for turn-in) needs its item no more, whatever the game's
      -- "show when complete" flag says
      local ok, link = pcall(GetQuestLogSpecialItemInfo, i)
      if ok and link and ns.Usable(link) and not ns.IsQuestComplete(questID) then
        local id = ns.GetItemID(link)
        if id and questID == tracked then return id, first end
        first = first or id
      end
    end
  end
  return nil, first
end

-- (1.3.5, Daniel 09.10.) An item in the bags that starts a quest (a looted book, a letter): one
-- click (or the key) opens the quest and auto accept takes it.
-- (1.3.5, Daniel 10.10.) Only when the quest can be taken now (level, previous quests; a quest the
-- data does not know cannot be checked and is offered), and not again in this session once its
-- offer was closed without taking it. It comes after the tracked quest's own item.
local declined = {} -- [questID] = true: offer closed without taking it (this session)
local offerShown    -- questID of the quest dialog that is open
local function StarterAllowed(qid)
  if declined[qid] then return false end
  if ns.QuestInData and not ns.QuestInData(qid) then return true end
  return ns.CanTakeQuest(qid) and true or false
end
local function StarterItem()
  if not (C_Container and C_Container.GetContainerItemQuestInfo) then return end
  for bag = 0, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local q = C_Container.GetContainerItemQuestInfo(bag, slot)
      local qid = q and ns.Num(q.questID)
      if qid and not ns.True(q.isActive) and not ns.IsQuestDone(qid) and not ns.InQuestLog(qid) and StarterAllowed(qid) then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and ns.Num(info.itemID) then return info.itemID, qid end
      end
    end
  end
end
ns.StarterItem = StarterItem -- (tests)

-- Classic style quests: usable quest items sitting in the bags.
local function FromBags()
  if not (C_Container and C_Container.GetContainerItemQuestInfo) then return end
  for bag = 0, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local q = C_Container.GetContainerItemQuestInfo(bag, slot)
      if q and (q.isQuestItem or q.questID) then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and ns.Num(info.itemID) and C_Item and ns.Value(C_Item.GetItemSpell, info.itemID)
          and not (ns.ItemQuestsFinished and ns.ItemQuestsFinished(info.itemID)) then
          return info.itemID
        end
      end
    end
  end
end

-- 1.15: the tracked quest's own item comes first, also an item from the bags
-- that an open "use it at a place" objective of that quest needs.
-- (1.3.5, Daniel 10.10.) then an item that starts a quest you can take, then the rest.
local function FindQuestItem()
  local tracked, first = FromQuestLog()
  if tracked then return tracked end
  local use = ns.TrackedUseItem and ns.TrackedUseItem()
  if use and C_Item and ns.Value(C_Item.GetItemSpell, use) then return use end
  local starter = StarterItem()
  if starter then return starter end
  return first or FromBags()
end
ns.FindQuestItem = FindQuestItem -- (tests)

-- The quest dialog closed: was the quest taken? If not, its starter item leaves the button.
ns.On("QUEST_DETAIL", function()
  local id = ns.Num(ns.Value(GetQuestID))
  offerShown = id and id > 0 and id or nil
end)
ns.On("QUEST_ACCEPTED", function() offerShown = nil end)
ns.On("QUEST_FINISHED", function()
  local id = offerShown
  offerShown = nil
  if not id then return end
  ns.After(1, function()
    if not ns.InQuestLog(id) and not ns.IsQuestDone(id) then
      declined[id] = true
      ns.QueueRefresh("itembutton")
    end
  end)
end)
function ns.StarterDeclined(questID) return declined[questID] == true end -- (tests)

---------------------------------------------------------------------------
-- Button (secure, so attributes only change out of combat)
---------------------------------------------------------------------------
local function SavePosition()
  local point, _, relPoint, x, y = button:GetPoint(1)
  ns.db.buttonPos = { point, relPoint, x, y }
end

local function ApplyPosition()
  button:ClearAllPoints()
  local p = ns.db.buttonPos
  if p then
    button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    button:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  end
end

local function UpdateCooldown()
  if not (button and button.itemID) then return end
  local start, duration = C_Container.GetItemCooldown(button.itemID)
  -- SetCooldown accepts secret values, so no arithmetic here.
  if start then button.cooldown:SetCooldown(start, duration) end
end

local function CreateButton()
  button = CreateFrame("Button", "QuestdonItemButton", UIParent, "SecureActionButtonTemplate")
  button:SetSize(36, 36)
  button:SetMovable(true)
  button:SetClampedToScreen(true)
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:RegisterForDrag("LeftButton")
  button:Hide()

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetAllPoints()
  button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  -- (1.19) family frame: dark flat backing one step outside the icon and a
  -- 1 px line, instead of the old action slot ring
  button.plate = ns.Look.Plate(button, 2)
  button.plate:SetAlpha(ns.Style.DEFAULT_ALPHA)
  button.border = button.plate.border[1]

  button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  button.count:SetPoint("BOTTOMRIGHT", -2, 2)

  button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  button.cooldown:SetAllPoints()

  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

  button:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
  end)
  button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  button:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    -- Blizzard's item tooltip, then the family hint line last
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    local h = ns.Style.COLORS.textHint
    GameTooltip:AddLine(L["Click: use. Shift-drag to move."], h[1], h[2], h[3], true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function(self) ns.Style.HideTooltip(self) end)

  ApplyPosition()
end

local function Refresh()
  if not button then return end
  if InCombatLockdown() then pendingRefresh = true return end
  pendingRefresh = false

  local itemID = ns.Active("questItemButton") and FindQuestItem() or nil
  if not itemID then
    button.itemID = nil
    button:SetAttribute("type", nil)
    button:Hide()
    return
  end

  button.itemID = itemID
  button:SetScale(ns.db.itemButtonScale or 1)
  button:SetAttribute("type", "item")
  button:SetAttribute("item", "item:" .. itemID)
  button.icon:SetTexture(C_Item.GetItemIconByID(itemID))
  local count = ns.Num(ns.Value(C_Item.GetItemCount, itemID))
  button.count:SetText(count and count > 1 and count or "")
  UpdateCooldown()
  button:Show()
  -- (1.3.5) the button shows a quest starter for the first time: the small notice above it
  if ns.db.starterNotice ~= false and ns.StarterNotice then
    local starter, questID = StarterItem()
    if starter == itemID then ns.StarterNotice(starter, questID) end
  end
end

---------------------------------------------------------------------------
-- (1.3.5, Daniel 10.10.: "a small notice in the form of Questdon's quest book: a nice frame above the quest
-- item button, not too big, discreet but still eye-catching") A looted item that starts a quest (the
-- Nibbled-On Book) gets a small note the first time it is on the button this session: its icon and name,
-- "Starts a quest: <quest>", how to open it. Own frame in the quest book's colours (navy, gold lines, the
-- book's corners), above the button (or under the game's messages at the top when the button is not
-- shown). It fades in with the gold rim pulsing for PULSE seconds, stays SHOW seconds and fades out; it
-- goes at once when the quest dialog opens or the quest is taken, when the item leaves the bags, or on a
-- click (the click only closes it: using the item needs the secure button). Never in combat or during a
-- loading screen: it waits. A quiet sound with the option "Sound when done", a chat line too.
---------------------------------------------------------------------------
local NOTICE_W, NOTICE_PAD, ICON_SIZE = 300, 10, 28
local FADE_IN, PULSE, SHOW, FADE_OUT = 0.25, 1.5, 8, 0.6
local NOTICE_SOUND = { "IG_QUEST_LIST_OPEN", "IG_MAINMENU_OPTION_CHECKBOX_ON" }
local MEDIA = "Interface\\AddOns\\Questdon\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local notice
local noticed = {}      -- [itemID] = true: shown this session
local pendingNotice     -- { itemID, questID } waiting for the end of combat or a loading screen
local loading = false
local noticeStats = { shown = 0, sounds = 0, waited = 0 }
function ns.StarterNoticeStats() return noticeStats end

local function Tinted(tex, c, a)
  tex:SetTexture(WHITE)
  tex:SetVertexColor(c[1], c[2], c[3], a or 1)
  return tex
end

local function CreateNotice()
  local B = ns.Style.BOOK
  local f = CreateFrame("Button", "QuestdonStarterNotice", UIParent)
  f:SetSize(NOTICE_W, 70)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:Hide()
  -- navy at the top to violet at the bottom, like the quest book
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetTexture(WHITE)
  f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  if f.bg.SetGradient and CreateColor then
    pcall(f.bg.SetGradient, f.bg, "VERTICAL", CreateColor(B.backgroundLow[1], B.backgroundLow[2], B.backgroundLow[3], 0.96),
      CreateColor(B.background[1], B.background[2], B.background[3], 0.96))
  else
    f.bg:SetVertexColor(B.background[1], B.background[2], B.background[3], 0.96)
  end
  -- the rim: a gold line outside, a dark and a faint gold line inside (the pulse lights the outer one)
  f.rim = CreateFrame("Frame", nil, f)
  f.rim:SetAllPoints(f)
  local lines = {}
  for _, e in ipairs({ { 0, B.gold, 0.95, true }, { 2, B.goldDark, 0.9 }, { 4, B.gold, 0.35 } }) do
    local inset, col, a, outer = e[1], e[2], e[3], e[4]
    for i = 1, 4 do
      local t = Tinted((outer and f.rim or f):CreateTexture(nil, "BORDER"), col, a)
      if i == 1 then t:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset) t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset) t:SetHeight(1)
      elseif i == 2 then t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset) t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset) t:SetHeight(1)
      elseif i == 3 then t:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset) t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset) t:SetWidth(1)
      else t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset) t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset) t:SetWidth(1) end
      lines[#lines + 1] = t
    end
  end
  -- a soft gold glow around the frame while it pulses (our own glow art)
  f.glow = f.rim:CreateTexture(nil, "BACKGROUND")
  f.glow:SetTexture(MEDIA .. "ArrowSealGlow")
  f.glow:SetPoint("TOPLEFT", f, "TOPLEFT", -14, 14)
  f.glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 14, -14)
  if f.glow.SetBlendMode then pcall(f.glow.SetBlendMode, f.glow, "ADD") end
  f.glow:SetVertexColor(B.gold[1], B.gold[2], B.gold[3], 1)
  f.glow:SetAlpha(0)
  -- the book's corner ornaments, small
  f.corners = {}
  for i, c in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
    local t = f.rim:CreateTexture(nil, "OVERLAY")
    t:SetSize(16, 16)
    if t:SetTexture(MEDIA .. "BookCorner") == false then t:Hide() end
    if t.SetTexCoord then t:SetTexCoord(c[2], c[3], c[4], c[5]) end
    t:SetPoint(c[1], f, c[1], c[1]:find("LEFT") and -2 or 2, c[1]:find("TOP") and 2 or -2)
    f.corners[i] = t
  end
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(ICON_SIZE, ICON_SIZE)
  f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", NOTICE_PAD + 2, -NOTICE_PAD - 2)
  if f.icon.SetTexCoord then f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  local textX = NOTICE_PAD + 2 + ICON_SIZE + 8
  f.textW = NOTICE_W - textX - NOTICE_PAD - 4
  local function Line(size, color, y)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local obj, ok, path = _G.GameFontHighlightSmall, false, nil
    if type(obj) == "table" and type(obj.GetFont) == "function" then ok, path = pcall(obj.GetFont, obj) end
    if fs.SetFont and ok and type(path) == "string" then pcall(fs.SetFont, fs, path, size, "") end
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", textX, y)
    fs:SetWidth(f.textW)
    return fs
  end
  f.name = Line(13, B.goldLight, -NOTICE_PAD - 1)
  f.quest = Line(12, B.textPrimary, -NOTICE_PAD - 19)
  f.hint = Line(11, B.textHint, -NOTICE_PAD - 37)
  f:SetHeight(NOTICE_PAD * 2 + 50)
  f:SetScript("OnClick", function(self) ns.HideStarterNotice("click") end) -- closes only; the item needs the secure button
  -- one clock for fade in, pulse, stay and fade out; runs only while the notice is shown
  f:SetScript("OnUpdate", function(self, dt)
    self.t = (self.t or 0) + (tonumber(dt) or 0)
    local t = self.t
    if t < FADE_IN then self:SetAlpha(t / FADE_IN) else self:SetAlpha(1) end
    if t < PULSE then
      self.glow:SetAlpha(0.35 + 0.35 * math.sin(t / PULSE * math.pi * 3) ^ 2)
    elseif self.glowOn then
      self.glowOn = false
      self.glow:SetAlpha(0)
    end
    if t >= FADE_IN + SHOW then
      local out = (t - FADE_IN - SHOW) / FADE_OUT
      if out >= 1 then ns.HideStarterNotice("time") return end
      self:SetAlpha(1 - out)
    end
  end)
  notice = f
  return f
end

-- Where it goes: right above the quest item button (wherever it was moved), else under the game's
-- messages at the top of the screen.
local function PlaceNotice(f)
  f:ClearAllPoints()
  if button and button:IsShown() then
    f:SetPoint("BOTTOM", button, "TOP", 0, 8)
    f.anchor = "button"
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -190)
    f.anchor = "top"
  end
end

local function ItemText(itemID)
  local name, _, quality = ns.GetItemInfo(itemID)
  if type(name) ~= "string" or name == "" then name = ns.ItemName(itemID) end
  local c = type(ITEM_QUALITY_COLORS) == "table" and ITEM_QUALITY_COLORS[ns.Num(quality) or 1]
  local hex = type(c) == "table" and type(c.hex) == "string" and c.hex or nil
  if hex then return hex .. name .. "|r", name end
  return name, name
end

local function QuestName(questID)
  local title = questID and ns.Value(C_QuestLog.GetTitleForQuestID, questID)
  if type(title) == "string" and title ~= "" then return title end
  return questID and ns.DataQuestName and ns.DataQuestName(questID) or nil
end

local function HintText()
  local key = type(GetBindingKey) == "function" and ns.Value(GetBindingKey, "CLICK QuestdonItemButton:LeftButton")
  if type(key) == "string" and key ~= "" then
    local text = type(GetBindingText) == "function" and ns.Value(GetBindingText, key) or key
    return L["Click the quest button or press %s"]:format(type(text) == "string" and text or key)
  end
  return L["Click the quest button"]
end

local function Show(itemID, questID)
  local f = notice or CreateNotice()
  local colored = ItemText(itemID)
  local title = QuestName(questID)
  f.itemID, f.questID = itemID, questID
  f.icon:SetTexture(C_Item and C_Item.GetItemIconByID and ns.Value(C_Item.GetItemIconByID, itemID) or 134400)
  f.name:SetText(colored)
  f.quest:SetText(title and L["Starts a quest: %s"]:format(title) or L["Starts a quest"])
  f.hint:SetText(HintText())
  -- long names: a little smaller, then cut with "..." (never wider than the note)
  for _, fs in ipairs({ f.name, f.quest, f.hint }) do ns.Style.FitText(fs, f.textW) end
  PlaceNotice(f)
  f.t, f.glowOn = 0, true
  f:SetAlpha(0)
  f.glow:SetAlpha(0.35)
  f:Show()
  noticed[itemID] = true
  noticeStats.shown = noticeStats.shown + 1
  if ns.db.notifySound ~= false and PlaySound and SOUNDKIT then
    for _, k in ipairs(NOTICE_SOUND) do
      if SOUNDKIT[k] then pcall(PlaySound, SOUNDKIT[k]) noticeStats.sounds = noticeStats.sounds + 1 break end
    end
  end
  ns.Print(title and L["%s starts a quest: %s"]:format(colored, title) or L["%s starts a quest."]:format(colored))
end

-- The button shows a quest starter (Refresh): the note, once per item and session; in combat or during
-- a loading screen it waits.
function ns.StarterNotice(itemID, questID)
  if not itemID or noticed[itemID] or ns.db.starterNotice == false then return false end
  if loading or ns.True(ns.Value(InCombatLockdown)) then
    if not (pendingNotice and pendingNotice[1] == itemID) then noticeStats.waited = noticeStats.waited + 1 end
    pendingNotice = { itemID, questID }
    return false
  end
  pendingNotice = nil
  Show(itemID, questID)
  return true
end

function ns.HideStarterNotice(reason)
  pendingNotice = nil
  if notice and notice:IsShown() then
    notice:Hide()
    noticeStats.lastHidden = reason
    return true
  end
  return false
end
function ns.StarterNoticeFrame() return notice end -- (tests)
function ns.ResetStarterNotices() noticed, pendingNotice = {}, nil end -- (tests)

local function ShowPending()
  if not pendingNotice or loading or ns.True(ns.Value(InCombatLockdown)) then return end
  local p = pendingNotice
  pendingNotice = nil
  -- still in the bags and still a starter?
  if (ns.Num(ns.Value(C_Item and C_Item.GetItemCount, p[1])) or 0) > 0 then ns.StarterNotice(p[1], p[2]) end
end
ns.On("PLAYER_REGEN_ENABLED", function() ns.After(0.5, ShowPending) end)
ns.On("LOADING_SCREEN_ENABLED", function() loading = true end)
ns.On("LOADING_SCREEN_DISABLED", function() loading = false ns.After(1, ShowPending) end)
-- the quest dialog opens or the quest is taken: the note has done its job
ns.On("QUEST_DETAIL", function() ns.HideStarterNotice("dialog") end)
ns.On("QUEST_ACCEPTED", function() ns.HideStarterNotice("accepted") end)
-- the item left the bags (used, sold, destroyed)
ns.On("BAG_UPDATE_DELAYED", function()
  local id = notice and notice:IsShown() and notice.itemID or (pendingNotice and pendingNotice[1])
  if id and (ns.Num(ns.Value(C_Item and C_Item.GetItemCount, id)) or 0) == 0 then ns.HideStarterNotice("gone") end
end)

-- Many events fire in bursts: bundle them into one refresh. (1.23) Batched
-- with the quest displays (Core.lua): the quest log is read once.
ns.RegisterRefresh("itembutton", Refresh)
local function QueueRefresh() ns.QueueRefresh("itembutton") end
ns.RefreshItemButton = QueueRefresh

function ns.ResetButtonPosition()
  ns.db.buttonPos = nil
  if button and not InCombatLockdown() then ApplyPosition() end
  ns.Print(L["Button position reset."])
end

ns.OnInit(CreateButton)
ns.On("PLAYER_ENTERING_WORLD", QueueRefresh)
ns.On("QUEST_LOG_UPDATE", QueueRefresh)
ns.On("BAG_UPDATE_DELAYED", QueueRefresh)
ns.On("SUPER_TRACKING_CHANGED", QueueRefresh)
ns.On("BAG_UPDATE_COOLDOWN", UpdateCooldown)
ns.On("PLAYER_REGEN_ENABLED", function()
  if pendingRefresh then Refresh() end
end)
