local addonName, ns = ...
local L = ns.L
-- (31.10.2026, DONCORE_PLAN.md) the kit and the Blizzard options come from DonCore (Libs\DonCore\Style.lua, Settings.lua).
-- An own kit (ForAddon): Look.lua sets onError for Questdon's error log without touching the other addons' kit.
ns.Style = LibStub("DonCore-1.0"):Get("Style", 6):ForAddon() -- (02.11.2026) minor 6: the Don look of the quest list
LibStub("DonCore-1.0"):Get("Settings", 1):Attach(addonName, ns)
ns.HOST = addonName -- (L3) the addon the engine of DonData serves (ns.Version, exports)

-- (16.11.2026, Daniel: "Sollte Standart sein", Blizzard look for all Don addons as in Luredon 1.7.0) Questdon's windows
-- (quest book, dialogs, text window): DonCore's Kit, or with the option blizzLook (on by default) the same blocks from
-- the game's own templates (DonCore module Blizz). Second value true when it is the game's; without the client's
-- templates (Classic Era, an older client) quietly the Kit. The quest list keeps its own look (trackerLook).
if type(ns.defaults) == "table" and ns.defaults.blizzLook == nil then ns.defaults.blizzLook = true end
-- (17.11.2026) the look of the quest list as one number for the dropdown in the game's settings (Tracker.lua
-- ns.TrackerLook; set from trackerPlain/trackerGame/trackerGameBox at every start)
if type(ns.defaults) == "table" and ns.defaults.trackerLook == nil then ns.defaults.trackerLook = 1 end
function ns.LookKit()
  local Core = LibStub("DonCore-1.0")
  local Kit = Core:Get("Kit", 16)
  if not (ns.db and ns.db.blizzLook) then return Kit, false end
  local Bz = Core:Get("Blizz", 5)
  local kit = Bz and Bz.Kit()
  if kit then return kit, true, Bz end
  return Kit, false
end

-- (05.11.2026, as Guildon b8dc89d9, Daniel's /gn names on WoW Forever) Forever has surnames
-- (C_PlayerInfo.ShouldDisplaySurname() true): UnitName and UnitFullName give the surname where other clients give the
-- realm ("Mae", "Wipeborn"); the roster and the senders of addon messages say "Ratloff Ashbloom" (no realm), and a
-- whisper needs that whole name. There the name is "<first> <surname>", the realm comes from GetNormalizedRealmName,
-- never from the second value of UnitName or UnitFullName.
-- (05.11.2026, Siyo) with the surnames hidden in the game's options ShouldDisplaySurname() is false, yet UnitFullName still
-- gives the surname in the realm's place and the senders still say "Siyo Fren": the surname became the realm. So a client
-- that knows the function counts as one with surnames also when the second value of UnitFullName is not the own realm;
-- its realm never comes from there (ns.MyRealmKey).
function ns.SurnameClient()
  local P = C_PlayerInfo
  return type(P) == "table" and type(P.ShouldDisplaySurname) == "function"
end
local function SurnameRealmKey(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  local v = a
  if fn == UnitFullName then v = b end
  if not ok or type(v) ~= "string" or v == "" or (issecretvalue and issecretvalue(v)) then return nil end
  return (v:gsub("[%s%-]", ""))
end
function ns.Surnames()
  if not ns.SurnameClient() then return false end
  local ok, v = pcall(C_PlayerInfo.ShouldDisplaySurname)
  if ok and v == true then return true end
  local second = SurnameRealmKey(UnitFullName, "player")
  local norm, plain = SurnameRealmKey(GetNormalizedRealmName), SurnameRealmKey(GetRealmName)
  if not second or not (norm or plain) then return false end
  return second ~= norm and second ~= plain
end
-- name and realm of a unit as chat and addon messages know it: on Forever ("Mae Wipeborn", nil), elsewhere
-- (name, realm or nil); nil for anything unreadable
function ns.UnitNameRealm(unit)
  local ok, n, r = pcall(UnitName, unit)
  if not ok or type(n) ~= "string" then return nil end
  if issecretvalue and (issecretvalue(n) or (r ~= nil and issecretvalue(r))) then return nil end
  if n == "" then return nil end
  if type(r) ~= "string" or r == "" then r = nil end
  if ns.Surnames() then return r and (n .. " " .. r) or n, nil end
  return n, r
end
-- the own realm for "Name-Realm" (no spaces): on Forever GetNormalizedRealmName, elsewhere UnitFullName's realm first
function ns.MyRealmKey()
  local r
  if not ns.SurnameClient() then
    local ok, _, rr = pcall(UnitFullName, "player")
    if ok and type(rr) == "string" and rr ~= "" then r = rr end
  end
  for _, fn in ipairs({ GetNormalizedRealmName, GetRealmName }) do
    if not r and type(fn) == "function" then
      local ok, v = pcall(fn)
      if ok and type(v) == "string" and v ~= "" then r = v end
    end
  end
  return r and (r:gsub("[%s%-]", "")) or "?"
end

---------------------------------------------------------------------------
-- (30.10.2026, DONCORE_PLAN.md "DonData Lese-Engine" L3) Questdon's part of the old Core.lua: its saved variables and
-- the slash command. The rest (defaults, errors, scopes, refresh, events, quest log, helpers) is DonData/Engine/Core.lua,
-- loaded before Questdon in the same namespace. At ADDON_LOADED Questdon hands its settings to the engine (ns.Start).
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if event ~= "ADDON_LOADED" or ... ~= addonName then return end
    if QuestdonDB == nil and type(QuestKompassDB) == "table" then QuestdonDB = QuestKompassDB end -- data from QuestKompass
    QuestKompassDB = nil
    QuestdonDB = QuestdonDB or {}
    -- (18.11.2026) a new install: nothing saved yet (the look of the quest list starts as "Blizzard, transparent")
    local freshInstall = next(QuestdonDB) == nil
    -- (30.10.2026, DONCORE_PLAN.md "DonData Lese-Engine" L2) what Questdon learns is kept in DonData (DonDataDB, Store.lua):
    -- once taken over from QuestdonDB; ns.db is a view, learned keys there, the settings here. Without DonData as before.
    local learnKeys = type(ns.LEARN_KEYS) == "table" and ns.StoreView and ns.MoveLearned and ns.LEARN_KEYS or nil
    if type(QuestdonCharDB) ~= "table" then QuestdonCharDB = {} end
    if learnKeys then ns.MoveLearned(QuestdonDB, QuestdonCharDB) end
    for k, v in pairs(ns.defaults) do
      if QuestdonDB[k] == nil and not (learnKeys and learnKeys[k]) then
        QuestdonDB[k] = type(v) == "table" and {} or v
      end
    end
    ns.db = learnKeys and ns.StoreView(QuestdonDB, ns.ldb, learnKeys) or QuestdonDB
    -- (31.10.2026, Kritikrunde) the one-time upgrades below never stop the start: an error in one of them used to skip
    -- ns.Start, and the engine then started alone at login on throwaway defaults (the settings looked reset)
    ns.SafeCall("settings upgrade", function()
      -- (1.24) "Quests without a level count as low level" is replaced by "Show
      -- quests without a level on the map" (default off). Both values of the
      -- old option end up hiding unconfirmed quests without a level by default.
      QuestdonDB.noLevelIsLow = nil
      -- (1.0) "Nearest quest" is off by default now and only uses confirmed quests
      -- nearby: it sent players far away to quests the data knew but the game
      -- did not offer, while the game's own ! were closer.
      if not QuestdonDB.nextHintV10 then
        QuestdonDB.nextConfirmedOnly, QuestdonDB.nextHintV10 = true, true
      end
      -- (1.3.7, Daniel 13.10.: "by default the compass in the list and the arrow off") once: with the list and its
      -- compass on, the separate arrow window goes off (switch it on again for both at once)
      -- (1.3.8, Daniel 13.10.: "the old window can go completely") its lines are at the bottom of the quest list now
      if not QuestdonDB.arrowV137 then
        -- (Questdon review 5) not when the list was closed: then the arrow is the only way shown
        if QuestdonDB.tracker ~= false and QuestdonDB.trackerCompass ~= false and QuestdonDB.trackerShown ~= false then QuestdonDB.arrow = false end
        QuestdonDB.arrowV137 = true
      end
      -- (30.10.2026, Daniel: by default only the arrow shows the way, the compass goes into the quest list only when
      -- chosen in the options) once: who still shows the way with the list's compass only (the old default)
      -- gets the arrow window instead; "Arrow" and "Both" stay as chosen
      -- (30.10.2026, Daniel: "Meldung wenn Quest fertig kann standard aus") once for everybody; who wants it switches it on
      if not QuestdonDB.notifyTextV1313 then
        QuestdonDB.notifyText, QuestdonDB.notifyTextV1313 = false, true
      end
      if not QuestdonDB.arrowV1313 then
        if QuestdonDB.trackerCompass ~= false and not (QuestdonDB.arrow and not QuestdonDB.arrowAuto) then
          QuestdonDB.trackerCompass, QuestdonDB.arrow, QuestdonDB.arrowAuto = false, true, nil
        end
        QuestdonDB.arrowV1313 = true
      end
      -- (1.3.11, Daniel 25.10.: "no background and no frame shall be the default for Questdon and Leveldon, also with the
      -- arrow") once for everybody: the quest list and the arrow see-through; who wants the frame switches it on again
      if not QuestdonDB.plainV1311 then
        QuestdonDB.trackerPlain, QuestdonDB.arrowPlain, QuestdonDB.plainV1311 = true, true, true
      end
      -- (18.11.2026, Daniel for the UI launch: "Blizzard transparent" ab Werk fuer ganz neue Spieler) only a new install;
      -- who has settings keeps their look
      if freshInstall then QuestdonDB.trackerPlain, QuestdonDB.trackerGame = true, true end
      -- (17.11.2026) the dropdown's number follows the switches the look really uses
      QuestdonDB.trackerLook = QuestdonDB.trackerPlain == true and (QuestdonDB.trackerGame == true
        and (QuestdonDB.trackerGameBox == true and 4 or 3) or 2) or 1
      -- (04.11.2026, Era-Test, Daniel: "questdon die einstellungen für die größe als standart") pin sizes 60 % on the
      -- world map and 85 % on the minimap by default; the old default 100 % was written into the saved settings at the
      -- first start, so once: who still has exactly 100 % gets the new size, a size moved on the slider stays
      -- (12.11.2026, Daniel on the laptop: "pin sizes und schrift auf 100% als standard bei neuinstallation") the default
      -- is 100 % again, so this step moves nobody any more: who got 60 % and 85 % then keeps them, a new install and
      -- settings that never ran it stay at 100 %
      if not QuestdonDB.pinScaleV0411 then QuestdonDB.pinScaleV0411 = true end
      -- (28.10.2026, Daniel: "Sachen vorgeben, weil wir sind die Entwickler") the options no longer in the window: once to
      -- the value we chose (Options.lua ns.FIXED_OPTIONS)
      if ns.ApplyFixedOptions then ns.ApplyFixedOptions(QuestdonDB) end
      -- (10.11.2026, Daniel: better without packing more in) the developer tools /qd xpcheck and /qd nettest left the
      -- addon: what they stored goes too
      QuestdonDB.xpcheck, QuestdonDB.netTest = nil, nil
      -- (10.11.2026, Daniel: "Questie has priority" fixed off) the switch and its mark go
      QuestdonDB.questieFirst, QuestdonDB.questieV136 = nil, nil
      -- and what nothing reads any more: the old "nearest quest" switch, the automatic reward pick, the Blizzard map pin
      QuestdonDB.nextQuestHint, QuestdonDB.autoPickBest, QuestdonDB.exportBlizzardWaypoint = nil, nil, nil
      QuestdonDB.clusterPins, QuestdonDB.upcomingLevels = nil, nil -- "Merge markers" and the quests of the next levels
    end)
    -- (1.24) per character: what quest givers offered (Offers.lua)
    if type(QuestdonCharDB) ~= "table" then QuestdonCharDB = {} end
    ns.charDB = learnKeys and ns.StoreView(QuestdonCharDB, ns.lcharDB, ns.CHAR_KEYS) or QuestdonCharDB
    -- (Questdon review 5) once with 1.3.8: list, compass and arrow agree (a closed list or a compass off: the arrow);
    -- later an arrow switched off by hand stays off
    if ns.SyncArrowData and not QuestdonDB.arrowSyncV138 then
      ns.SafeCall("arrow sync", ns.SyncArrowData, QuestdonDB)
      QuestdonDB.arrowSyncV138 = true
    end
    frame:UnregisterEvent("ADDON_LOADED")
    ns.Start(ns.db, ns.charDB)
end)

SLASH_QUESTDON1 = "/qd"
SLASH_QUESTDON2 = "/questdon"
ns.HELP = L["Commands: /qd (options), /qd list (quest list), /qd arrow, /qd xpbar, /qd next, /qd xp, /qd dungeons, /qd zone (quests of the zone), /qd journal (quest journal), /qd search [text], /qd group, /qd export, /qd diag (diagnostics), /qd missing (nonexistent quests), /qd nothere (targeted NPC has no quest: hide it; undo, list), /qd why [quest ID] (why no !), /qd reset (reset button position)"]
SlashCmdList.QUESTDON = ns.Guard("slash", function(msg)
  local raw = strtrim and strtrim(msg or "") or (msg or "")
  msg = raw:lower()
  -- (1.3.5, Daniel 10.10.) /qd search <text>: the search with that text
  local text = raw:match("^[Ss][Uu][Cc][Hh][Ee]%s+(.+)$") or raw:match("^[Ss][Ee][Aa][Rr][Cc][Hh]%s+(.+)$")
  if text then
    if ns.OpenQuestBook then ns.OpenQuestBook("search") end
    if ns.JournalSetQuery then ns.JournalSetQuery(text) end
    return
  end
  -- (10.11.2026) /qd way ...: the waypoint (Way.lua; "/way" itself only without TomTom)
  if msg == "way" or msg:match("^way%s") then
    if ns.WayCommand then ns.WayCommand(raw:sub(4)) end
    return
  end
  if msg == "" or msg == "options" or msg == "config" then
    if ns.OpenOptions then ns.OpenOptions() end
  elseif msg == "reset" then
    if ns.ResetButtonPosition then ns.ResetButtonPosition() end
  elseif msg == "setup" then
    if ns.OpenSetup then ns.OpenSetup() end -- (17.10.) the map style and first steps window
  elseif msg == "panel" then
    -- (1.3.8) the old window is gone: its lines are at the bottom of the quest list
    if ns.ToggleTracker then ns.ToggleTracker() end
  elseif msg == "collect" or msg == "sammeln" then
    if ns.SetDataOnly then ns.SetDataOnly() end -- (25.10.) only learning and sharing on, again: settings back
  elseif msg == "xpbar" then
    if ns.ToggleXPBar then ns.ToggleXPBar() end
  elseif msg == "next" then
    if ns.PointToNextQuest then ns.PointToNextQuest() end
  elseif msg == "arrow" then
    if ns.ToggleArrow then ns.ToggleArrow() end
  elseif msg == "list" then
    if ns.ToggleTracker then ns.ToggleTracker() end
  elseif msg == "list reset" then
    if ns.RescueTracker then ns.RescueTracker() end -- (06.11.2026) the list back on screen
  elseif msg == "xp" then
    if ns.PrintPlanner then ns.PrintPlanner() end
  elseif msg == "export" or msg == "export all" then
    if ns.OpenExport then ns.OpenExport(msg == "export all") end
  elseif msg == "scan" or msg:match("^scan%s") then
    -- (1.3.12) which quest IDs the server knows (Scan.lua)
    if ns.ScanCommand then ns.ScanCommand(msg:match("^scan%s+(%S+)") or "") end
  elseif msg == "missing" then
    if ns.OpenMissing then ns.OpenMissing() end
  elseif msg == "mapsizes" then
    -- (1.3.4) map rectangles and flight points for the level guide (saved at /reload)
    if ns.DumpMapSizes then
      local n, k = ns.DumpMapSizes()
      print(("|cff3fa9f5Questdon|r: %d maps, %d flight points stored. /reload saves them."):format(n, k))
    end
  elseif msg:match("^npcname") then
    -- (1.3.5) test: an NPC's name from every source (does the tooltip way work in this client?)
    local id = tonumber(msg:match("^npcname%s+(%d+)$") or "")
    local r = id and ns.NpcNameReport and ns.NpcNameReport(id)
    if not r then
      print("|cff3fa9f5Questdon|r: /qd npcname <NPC ID>, e.g. /qd npcname 823")
    else
      local function S(v) return v and ('"' .. v .. '"') or "-" end
      print(("|cff3fa9f5Questdon|r: NPC %d: %s (from %s)"):format(r.id, S(r.name), r.source or "-"))
      print(("  game tooltip: %s%s, learned: %s, shipped: %s, data: %s"):format(S(r.game), r.gameBroken and " (tooltip way not available)" or "",
        S(r.learned), S(r.shipped), S(r.data)))
      if not r.game and not r.gameBroken then print("  The client may ask the server first: try again in a few seconds.") end
    end
  elseif msg:match("^why%s+%d+$") then
    -- (1.3.6) why a quest has no "!" (QuestData.lua ns.WhyQuest)
    for _, l in ipairs(ns.WhyQuest(tonumber(msg:match("(%d+)$")))) do print("|cffffd100Questdon|r " .. l) end
  elseif msg == "mem" or msg:match("^mem%s+%d+$") then
    if ns.MemoryCheck then ns.MemoryCheck(tonumber(msg:match("(%d+)$"))) end
  elseif msg == "diag" then
    if ns.OpenDiag then ns.OpenDiag() end
  elseif msg == "dungeonlevels" then
    -- (1.3.5) the level ranges of the data and the game, and the entrances, to check the data
    if ns.OpenDungeonLevels then ns.OpenDungeonLevels() end
  elseif msg == "dungeons" or msg == "dungeon" then
    -- (04.11.2026, Era-Test, Daniel: "das scheint noch im alten stil") the quest book on its "dungeons" tab
    if ns.OpenQuestBook then ns.OpenQuestBook("dungeons") elseif ns.OpenDungeons then ns.OpenDungeons() end
  elseif msg == "group raw" then
    -- (12.11.2026) the game's own lines about the group's quest progress, to check Party.lua's reading
    if ns.PartyRaw then ns.PartyRaw() end
  elseif msg == "group" or msg == "party" then
    if ns.PrintParty then ns.PrintParty() end
  elseif msg == "look" then
    -- (12.11.2026) the window with the three looks of the quest list (Setup.lua), any time
    if ns.OpenListLook then ns.OpenListLook() end
  elseif msg == "announce test" then
    -- (12.11.2026) shows the party chat lines of the quests in your log in your own chat, nothing is sent
    if ns.AnnounceTest then ns.AnnounceTest() end
  elseif msg == "announce" then
    -- (12.11.2026) the line for the group when a quest is ready, on and off (Announce.lua)
    if ns.ToggleAnnounce then ns.ToggleAnnounce() end
  elseif msg == "nothere" then
    if ns.ReportTarget then ns.ReportTarget() end
  elseif msg == "nothere undo" then
    if ns.UndoNotHere then ns.UndoNotHere() end
  elseif msg == "nothere list" then
    if ns.PrintNotHere then ns.PrintNotHere() end
  elseif msg == "zone" or msg == "quests" then
    if ns.ToggleZoneQuests then ns.ToggleZoneQuests() end
  elseif msg == "journal" or msg == "tagebuch" then
    if ns.ToggleJournal then ns.ToggleJournal() end
  elseif msg == "search" or msg == "suche" then
    if ns.OpenQuestBook then ns.OpenQuestBook("search") end
  elseif msg == "help" then
    ns.Print(ns.HELP)
  else
    -- (1.3.5) a typo no longer opens the options without a word
    ns.Print(L["Unknown command: %s"]:format(raw))
    ns.Print(ns.HELP)
  end
end)

-- (24.11.2026, Ruckler Runde 4, DonMonitor report from the laptop after round 3: "ticker Tracker.lua [nearby]" up to
-- 31 ms, "refresh minimap [minimap base]" up to 26 ms, "ticker Arrow.lua" 21 ms) one small runner for work in slices:
-- body(pause) runs in a coroutine; pause() (the engine calls it every few entries, Questdon between its steps) gives
-- the frame back once the slice used SLICE_MS, the next slice runs in the next frame (ns.After 0). At its end
-- done(result) runs in the frame of the last slice. A job of the same name started anew drops the one on the way.
-- Where the game has no clock for it (tests) ns.SliceJob returns false and the caller works directly as before.
-- pause only outside every pcall (tools/yieldcheck.lua); a pause called outside its job does nothing.
local SJ = { MS = 4, jobs = {}, stats = { started = 0, done = 0, slices = 0 } }
ns.SliceJobs = SJ -- (tests, /qd diag)
function ns.SliceCan()
  return type(debugprofilestop) == "function" and C_Timer ~= nil and C_Timer.After ~= nil and type(coroutine) == "table"
end
local function SliceStep(j)
  if SJ.jobs[j.name] ~= j then return end -- dropped meanwhile
  j.t0 = debugprofilestop()
  local ok, r = coroutine.resume(j.co, j.pause)
  if SJ.jobs[j.name] ~= j then return end
  if debugprofilestop() - j.t0 >= 8 and type(rawget(_G, "DonMonitorDB")) == "table" then ns.slowDetail = j.name end
  if not ok then SJ.jobs[j.name] = nil error(r, 0) end
  if coroutine.status(j.co) ~= "dead" then ns.After(0, j.step) return end
  SJ.jobs[j.name] = nil
  SJ.stats.done = SJ.stats.done + 1
  if j.done then j.done(r) end
end
-- name: one job of a name at a time (also the slow log's detail); first: "now" runs the first slice in this frame,
-- else in the next one
function ns.SliceJob(name, body, done, first)
  if not ns.SliceCan() then return false end
  local j = { name = name, slices = 0, done = done }
  j.co = coroutine.create(body)
  j.pause = function()
    if coroutine.running() ~= j.co then return end
    if debugprofilestop() - j.t0 >= SJ.MS then
      j.slices = j.slices + 1
      SJ.stats.slices = SJ.stats.slices + 1
      coroutine.yield()
    end
  end
  j.step = function() SliceStep(j) end
  SJ.jobs[name] = j
  SJ.stats.started = SJ.stats.started + 1
  if first == "now" then SliceStep(j) else ns.After(0, j.step) end
  return true
end
function ns.SliceJobOn(name) return SJ.jobs[name] ~= nil end
function ns.SliceJobDrop(name) SJ.jobs[name] = nil end
