local addonName, ns = ...
local L = ns.L
-- (31.10.2026, DONCORE_PLAN.md) the kit and the Blizzard options come from DonCore (Libs\DonCore\Style.lua, Settings.lua).
-- An own kit (ForAddon): Look.lua sets onError for Questdon's error log without touching the other addons' kit.
ns.Style = LibStub("DonCore-1.0"):Get("Style", 4):ForAddon()
LibStub("DonCore-1.0"):Get("Settings", 1):Attach(addonName, ns)
ns.HOST = addonName -- (L3) the addon the engine of DonData serves (ns.Version, exports)

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
        QuestdonDB.nextQuestHint, QuestdonDB.nextConfirmedOnly, QuestdonDB.nextHintV10 = false, true, true
      end
      -- (1.3.6, Daniel 12.10.: "we are at the stage where Questie no longer needs priority") off once for everybody;
      -- who wants it back switches it on again (page "Questie")
      if not QuestdonDB.questieV136 then
        QuestdonDB.questieFirst, QuestdonDB.questieV136 = false, true
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
      -- (28.10.2026, Daniel: "Sachen vorgeben, weil wir sind die Entwickler") the options no longer in the window: once to
      -- the value we chose (Options.lua ns.FIXED_OPTIONS)
      if ns.ApplyFixedOptions then ns.ApplyFixedOptions(QuestdonDB) end
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
ns.HELP = L["Commands: /qd (options), /qd list (quest list), /qd arrow, /qd xpbar, /qd next, /qd xp, /qd dungeons, /qd zone (quests of the zone), /qd journal (quest journal), /qd search [text], /qd group, /qd questie, /qd export, /qd diag (diagnostics), /qd missing (nonexistent quests), /qd xpcheck (XP sources), /qd nettest (channel test), /qd nothere (targeted NPC has no quest: hide it; undo, list), /qd why [quest ID] (why no !), /qd reset (reset button position)"]
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
  elseif msg == "questie" then
    if ns.PrintQuestieStatus then ns.PrintQuestieStatus() end
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
  elseif msg == "xpcheck" or msg == "xpcheck reset" then
    if ns.OpenXPCheck then ns.OpenXPCheck(msg == "xpcheck reset" and "reset" or nil) end
  elseif msg == "dungeonlevels" then
    -- (1.3.5) the level ranges of the data and the game, and the entrances, to check the data
    if ns.OpenDungeonLevels then ns.OpenDungeonLevels() end
  elseif msg == "dungeons" or msg == "dungeon" then
    if ns.OpenDungeons then ns.OpenDungeons() end
  elseif msg == "group" or msg == "party" then
    if ns.PrintParty then ns.PrintParty() end
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
  elseif msg == "nettest" then
    if ns.NetTest then ns.NetTest() end
  elseif msg == "help" then
    ns.Print(ns.HELP)
  else
    -- (1.3.5) a typo no longer opens the options without a word
    ns.Print(L["Unknown command: %s"]:format(raw))
    ns.Print(ns.HELP)
  end
end)
