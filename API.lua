local _, ns = ...

---------------------------------------------------------------------------
-- Read-only interface for other addons (e.g. a guide addon).
-- Versioned: add functions, never change existing ones. Bump VERSION only
-- when something is added; other addons check QuestdonAPI.version.
--   1: the first set
--   2: (1.3.5) CanTakeQuestLater (Leveldon, 09.10.), DungeonLevelRange, Dungeons, DungeonsForLevel
--      (Geardon, 10.10.)
---------------------------------------------------------------------------
-- (30.10.2026, DONCORE_PLAN.md "DonData Lese-Engine" L4) the reading part (GetQuest ... TurnInNpc) is DonData's
-- DonDataAPI now (DonData/Engine/API.lua); QuestdonAPI hands those functions on unchanged (READ below), so addons
-- written against QuestdonAPI keep working. Here stay the dungeons, the group, the arrow, the compass and the windows.
local VERSION = 2

local API = { version = VERSION }

-- (1.18) Dungeon of a quest: instanceID (ATT), localized name, uiMapID of the
-- dungeon, minimum level of the dungeon; nil when the quest is no dungeon quest.
function API.QuestDungeon(questID)
  local inst = ns.QuestDungeon(questID)
  if not inst then return nil end
  local d = ns.ATT_DUNGEONS and ns.ATT_DUNGEONS[inst] or {}
  return inst, ns.DungeonName(inst), d[2], d[6]
end

-- (API 2, 1.3.5, Geardon 10.10.) Level range of a dungeon (ATT instance ID): min, max, source ("game" = the
-- client's Group Finder, "data" = Questdon's table); nil when unknown.
function API.DungeonLevelRange(inst)
  local lo, hi, source = ns.DungeonLevelRange(inst)
  if not lo then return nil end
  return lo, hi or lo, source
end

-- (API 2) Every dungeon and raid of the data with a level range:
-- { { inst, name (localized), min, max, source, raid (true for 60-60 raids), entranceMap, entranceX, entranceY (0-1, nil if
-- unknown) }, ... } sorted by min, max, inst.
function API.Dungeons()
  local list = {}
  for inst in pairs(ns.ATT_DUNGEONS or {}) do
    local lo, hi, source = ns.DungeonLevelRange(inst)
    if lo then
      local m, x, y = ns.DungeonEntrance(inst)
      list[#list + 1] = { inst = inst, name = ns.DungeonName(inst), min = lo, max = hi or lo, source = source,
        raid = (lo >= 60 and (hi or lo) >= 60) or nil, entranceMap = m, entranceX = x, entranceY = y }
    end
  end
  table.sort(list, function(a, b)
    if a.min ~= b.min then return a.min < b.min end
    if a.max ~= b.max then return a.max < b.max end
    return a.inst < b.inst
  end)
  return list
end

-- (API 2) The dungeons whose range holds level (default: the player's), same entries as Dungeons().
function API.DungeonsForLevel(level)
  level = tonumber(level) or ns.PlayerLevel()
  local out = {}
  if not level then return out end
  for _, d in ipairs(API.Dungeons()) do
    if level >= d.min and level <= d.max then out[#out + 1] = d end
  end
  return out
end

-- (1.18) Quest progress of group members who use Questdon (party of up to five):
-- { { name, complete, failed, objectives = { {fulfilled, required}, ... } }, ... },
-- empty when nobody in the group has the quest or the option is off.
function API.PartyProgress(questID)
  return ns.PartyProgress and ns.PartyProgress(questID) or {}
end

-- Arrow: point it at a target { mapID, x, y (0-1), label } or nil to release it.
-- (1.3.6) { ..., area = true, questID, points = { { mapID, x, y }, ... } }: the quest's objective places; in
-- their area (or with its mobs in sight) the needle gives way to "In the objective area", as for Questdon's own.
function API.SetArrowTarget(target)
  if ns.SetExternalArrowTarget then ns.SetExternalArrowTarget(target) end
end

-- (1.3.6, Daniel 12.10.: "the arrow built into the window") For a guide window with its own compass:
--   API.NewCompass(parent, size)        Questdon's compass (ring, rose, golden needle): c:Point(bearing, facing,
--                                       nearness), c:Arrived(on)
--   API.ArrowState()                    what the arrow shows now: angle (its needle's rotation), needle, nearness,
--                                       seal (arrived), label, distText, distColor, dist, bearing (to the target
--                                       itself, radians clockwise from north; the needle may follow a way around)
--   API.SetGuideCompass(on)             the guide's window shows the compass: Questdon's arrow draws nothing and its
--                                       quest list leaves out its own card (the quests stay listed)
--   API.ShowQuestText(questID)          the whole quest to read (description, objectives, rewards)
function API.NewCompass(parent, size) return ns.NewCompass and ns.NewCompass(parent, size) or nil end
-- (16.10. late, /qd mem "API ArrowState" 12 KB a second: a guide window asks many times a second) one answer table,
-- filled anew at each call: read it right away, do not keep it
local arrowAnswer = {}
function API.ArrowState()
  local st = ns.ArrowState and ns.ArrowState() or {}
  local r = arrowAnswer
  r.angle, r.needle, r.nearness, r.seal, r.label = st.angle, st.needle, st.nearness, st.seal, st.label
  r.distText, r.distColor, r.dist, r.hasTarget, r.bearing = st.distText, st.distColor, st.dist, st.t ~= nil, st.bearing
  -- (Questdon review 5) the distance and the way apart ("240 yards" / "the way around"), as Questdon's card has
  -- them; nil when the text is not "N yards, ..." (in the objective area, arrived, other zone)
  r.distShort, r.distWay = st.distShort, st.distWay
  return r
end
function API.SetGuideCompass(on)
  ns.guideCompass = on and true or nil
  if ns.QueueRefresh then ns.QueueRefresh("tracker") end
end
-- (25.10., Daniel: "for Leveldon an option Arrow instead of the compass in the list") Leveldon's switch: the single direction
-- arrow leads, without the guide's compass and without the list's. The values before are kept (db.arrowModePrev) and
-- come back with the second call. ArrowMode() is read from the settings themselves, so it stays right when the player
-- changes them by hand.
--   API.ArrowMode(), API.SetArrowMode(on)   arrow window on, the list's compass off
--   API.ArrowPlain(), API.SetArrowPlain(on) the arrow without plate and frame (option arrowPlain)
function API.ArrowMode()
  local db = ns.db
  return db ~= nil and db.arrow == true and db.trackerCompass == false
end
function API.SetArrowMode(on)
  local db = ns.db
  if not db then return false end
  on = on and true or false
  if on == API.ArrowMode() then return true end
  local function Changed(key) if ns.OptionChanged then ns.OptionChanged(key) end end
  if on then
    db.arrowModePrev = { compass = db.trackerCompass ~= false, arrow = db.arrow and true or false }
    db.trackerCompass, db.arrow, db.arrowAuto = false, true, nil
    Changed("trackerCompass")
    db.arrow, db.arrowAuto = true, nil
  else
    local p = db.arrowModePrev
    db.arrowModePrev = nil
    db.trackerCompass = p == nil or p.compass
    Changed("trackerCompass")
    db.arrow, db.arrowAuto = (p ~= nil and p.arrow) or false, nil
    if db.trackerCompass == false then db.arrow = true end -- no compass and no arrow would show no way at all
  end
  if ns.ApplyArrow then ns.SafeCall("arrow mode", ns.ApplyArrow) end
  if ns.UpdateTracker then ns.SafeCall("arrow mode", ns.UpdateTracker, true) end
  if ns.RefreshSettingsUI then ns.SafeCall("arrow mode", ns.RefreshSettingsUI) end
  return true
end
function API.ArrowPlain() return ns.db ~= nil and ns.db.arrowPlain == true end
function API.SetArrowPlain(on)
  if not ns.db then return false end
  ns.db.arrowPlain = on and true or false
  if ns.OptionChanged then ns.OptionChanged("arrowPlain") end
  return true
end
-- (1.3.6) the guide's window: Questdon's quest list docks right under it (same width, moves with it); nil undocks
function API.SetGuideFrame(frame)
  if ns.guideFrame == frame then return end
  ns.guideFrame = frame
  if ns.TrackerDock then ns.TrackerDock() end
  if ns.QueueRefresh then ns.QueueRefresh("tracker") end
end
-- (1.3.6) A guide that draws its own mark over a nameplate claims it: fn(unit) true means Questdon draws
-- nothing on that nameplate. RefreshPlate(unit): the guide's mark came or went.
-- (1.3.6) the number of Questdon's open channel (QuestdonNet) while joined, else nil: Leveldon shares how its
-- routes go there (its own addon prefix)
function API.ShareChannelID() return ns.ShareChannelID and ns.ShareChannelID() or nil end
function API.SetPlateClaim(fn) ns.plateClaim = type(fn) == "function" and fn or nil end
function API.RefreshPlate(unit) if ns.NameplateApply then pcall(ns.NameplateApply, unit) end end
function API.ShowQuestText(questID) if ns.ShowQuestText then return ns.ShowQuestText(questID) ~= nil end return false end

-- (17.10., Daniel: "Leveldon's options menu in Questdon's look") an options window like Questdon's own for another
-- addon: spec = { frameName, wordmark, media (path of its pictures, ending in \\), tabs (as OptionsWindow.lua's:
-- key, title, text, pic, icon, main, more, tools), pages() (as Options.lua's: items with key, name, tip, kind,
-- parent, min/max/step, onClick), tools() ({ name, button, fn, tip }), db() (the saved table), default(key),
-- changed(key), T(text) (the addon's translation) }. Returns { Open(tab), Toggle(), Render(), Frame() } or nil.
function API.NewOptionsWindow(spec)
  if type(spec) ~= "table" or not ns.NewOptionsWindow or type(spec.pages) ~= "function" or type(spec.db) ~= "function" then return nil end
  spec.default = spec.default or function() return nil end
  local w = ns.NewOptionsWindow(spec)
  return { Open = w.Open, Toggle = w.Toggle, Render = w.Render, Frame = w.Frame }
end

-- (17.10.) every API function in a scope of its own (Core.lua ns.ScopeCall)
for k, f in pairs(API) do
  if type(f) == "function" then API[k] = function(...) return ns.ScopeCall(f, ...) end end
end
-- (L4) the reading part from DonDataAPI (already in a scope of its own there)
local READ = { "GetQuest", "QuestTitle", "CanTakeQuest", "CanTakeQuestLater", "NotOfferedLevel", "IsQuestDone", "InQuestLog",
  "QuestNpcWalks", "IsQuestComplete", "CreatureName", "QuestExists", "QuestStart", "BreadcrumbTargets", "ObjectivePoints",
  "QuestPOI", "ObjectiveHint", "ItemName", "TurnInPoint", "DistanceTo", "PlayerPosition", "ObjectiveCreatures", "TurnInNpc" }
local D = ns.DonDataAPI
for _, k in ipairs(READ) do API[k] = D and D[k] end

QuestdonAPI = API
QuestKompassAPI = API -- old name, kept for addons written against it
