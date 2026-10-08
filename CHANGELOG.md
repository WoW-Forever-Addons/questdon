# Changes

## 1.3.4

- **New direction arrow:** a golden compass needle that shines brighter and glows as you get close, a golden seal that pulses gently when you have arrived, and the target on a dark blue plaque with a thin golden line, like the quest book. The distance stands out in gold.
- **Minimap button:** left click opens the quest book, right click a small menu with the most used switches (quest markers, quest mobs, arrow, auto accept and turn in, XP bar, window) and all options. Mouse over shows what the window showed: quests here, dungeon quests and your quest log. Drag it around the minimap. The Questdon window is now off for new players; switch it on in the menu. A new button in the window's title bar sends it to the minimap.
- **New look for the quest book:** a gold frame with ornaments, framed tabs, every line as a card, your zone's map round in a gold ring and the day's numbers as cards.
- **Quest details:** click a quest in the quest book and a card on the right shows everything at one glance: quest giver and place, what to do, where to turn it in, the quests before and after it, plus buttons for the arrow and the world map.
- **Dungeon quests step by step:** each dungeon quest stands out as the goal, with what to do inside. Below it the quests to do first, numbered in the order you walk them on a gold line (quests you can do side by side share a number), each with what to do and where. The texts come from Wowhead in English and German; quest givers now have their names.
- **Dungeons tab:** every dungeon as a card with how well it fits your level, what is in your log, what you can pick up and where. "Route" leads the arrow from quest giver to quest giver, nearest first, and moves on when you accept a quest.
- **Zones tab:** filter the quests of a zone (available, in your log, later, done) and sort them by distance. The zone list shows "12/48" next to each bar.
- **Journal:** accepting and turning in a quest is one line now, with how long it took. Each day shows its quests, XP and XP per hour, and a small chart shows your XP of the last seven days.
- **No second "!" on the minimap:** the game marks every quest giver near you on the minimap itself. Questdon now leaves those to the game (within about 80 yards), so the two "!" no longer sit on top of each other. Farther away Questdon draws as before. Option "No second ! or ? where the game shows one", on by default.
- **Profession quests:** quests that need a profession, such as "Camping 101: Tailoring", now show their "!" once you have learned that profession. Before, Questdon left them out completely. In the quest book they say "profession not learned" until then.
- **Dungeon chains:** a quest in two parts, such as "Destruction in Deadmines", no longer lists its whole chain twice. The second part only points to the first, a step shared by two quests stands under the first one, and parts with the same name show "(1/2)" and "(2/2)".
- **Optional objectives:** the arrow no longer leads to an optional objective such as "listen to ..." while the real objective is still open. On the map and minimap optional objectives are dimmed, and nameplates get no mark for them.
- **Bugged (Zephras Isle):** the Skyhoppers now show their spawn points.
- **The Missing Scholar (Zephras Isle):** the unconscious scholar is marked inside the cave, no longer at the quest giver in front of it.
- **Quest data:** the newest All The Things data with seven new Wetlands quests and corrections for Zephras Isle. On top, about 250 Forever quests from Wowhead that All The Things does not have yet: class quests of all classes, and quests in Desolace, Duskwood, the Wetlands, Stranglethorn Vale, Shen'dralas and more. And the turn-in places of more than 700 quests from Wowhead's Forever quest pages (the Alliance zones up to level 30 and Zephras Isle), so the arrow and the map know where to hand them in.
- **New dungeon City of Dalaran** (coming in a later beta update): its quests for both factions, with the quest givers in Stormwind, Undercity, Hillsbrad and Silverpine, and the quest that leads there. Also new: "Seeking Caitlin" for the Excavation Site, "Past Due" for the Scarlet Monastery and the shaman quest "Elemental Aid" for Razorfen Kraul.
- **Zone progress:** quests with a version for every start zone, such as "Camping 101", no longer count as done in zones you never visited.

## 1.3.3

- **Shorter quest tooltips:** on the world map and minimap the level stands in the title, "[6] Al'Aketh Assassins", in its difficulty colour. Below only what helps: quest giver, chain, dungeon, group, and a small "not confirmed yet" where only the data knows the quest. Hold Shift for where the data comes from.
- **Quest book, new tab "Dungeons":** every dungeon with its quests for you, sorted by level. Under each quest you see what to do first, with quest giver and zone, so you can pick up the whole chain before you go in.
- **Learned in the game:** more turn-ins, follow-up quests and objective spots from players' exports are bundled (Zephras Isle, Teldrassil, Elwynn Forest, Dun Morogh, Westfall, Redridge Mountains, Tirisfal Glades and more).
- **Export:** after sending an export, click "Mark as sent": the next `/qd export` only shows what is new or changed. `/qd export all` still shows everything, now also the list of quests the server doesn't know. The note to export before you log out is gone, the game keeps what Questdon learned.
- **Zephras Isle:** spawn points for the quest mobs and objects of the Skyborne start zone, and its quest givers' turn-ins.
- **Overlapping markers:** where quest givers stand close together, as on Zephras Isle, their "!" no longer cover each other on the world map and the minimap. They become one marker that lists all quests; zoomed in, they come apart again. And where the game draws its own "!", Questdon no longer puts a second one right next to it.
- **Window buttons:** the gear and the other buttons in the Questdon window can be clicked again when an action bar addon such as Bartender4 sits underneath.
- **Action bar addons:** with Bartender4, ElvUI or Dominos the ornament and the clickable reputation bar only show while the game's own bars are on screen, and they fade along with them.
- **QuestdonNet channel:** it no longer takes /1 from General. Questdon waits for the game's channels and moves its own channel behind them.

## 1.3.2

- **Blizzard's XP bar hidden:** while the Questdon XP bar is shown, the game's own XP bar is hidden (option, on by default). Your action bars stay where they are.
- **Ornament in its place:** an ornate band joins the two ends of the action bar where the game's XP bar was (option, on by default).
- **Clickable reputation bar:** a faction you track in the reputation list shows in Questdon's own bar in the same look; a click opens the reputation list (option, on by default).
- **Translations:** French, Spanish (Spain and Latin America), Brazilian Portuguese, Russian, Korean and Traditional Chinese.
- **Texts that fit:** long texts in the quest book shrink a little or are shortened, with the full text in the tooltip, so no language breaks the layout.

## 1.3.1

- **Minimap:** the quest objective dots have a dark ring, so they stay visible on green ground.

## 1.3.0

- **Quest book:** a new large window with three tabs. Open it with the button at the bottom of the Questdon window, /qd journal, /qd zone or /qd search.
  - **Journal:** your own quest diary per character. Accepted, turned in (with XP and money), abandoned and failed quests and your level-ups, with date and time. Today's quests, XP and money at the top, filters, and the quests you did before as "done earlier".
  - **Zones:** pick any zone of Kalimdor, the Eastern Kingdoms and Zephras Isle. Its map with the parts you explored, your progress and all its quests. Quests of a chain with the same name are one line that opens. Quests of the higher zones that are only in the older data are listed with a note until Forever confirms them.
  - **Search:** your journal, every quest and every zone by name, level or quest ID.
- **No second ? on the map:** where the game marks the turn-in of a finished quest itself, Questdon draws no learned turn-in point.

## 1.2.2

- **Spawn points for the Horde start zones:** Durotar (with the Valley of Trials), Mulgore (with Red Cloud Mesa), Tirisfal Glades (with Deathknell) and The Barrens now bring every spawn point of quest mobs and quest objects from the Wowhead Forever quest maps too. Together with 1.2.1 this covers both factions up to roughly level 30.
- **Spawn points up to level 60:** Desolace, Thousand Needles, Dustwallow Marsh, Alterac Mountains, Stranglethorn Vale, Swamp of Sorrows, Badlands, Feralas, Tanaris, The Hinterlands, Searing Gorge, Azshara, Blasted Lands, Un'Goro Crater, Felwood, Burning Steppes, Western and Eastern Plaguelands, Winterspring and Silithus too. Every leveling zone of Kalimdor and the Eastern Kingdoms now has them.
- **Learned in the game:** turn-ins, follow-up quests and objective spots from players' /qd export are bundled (for example, "Kobold Camp Cleanup" only shows after "A Threat Within", and "The Adventurer" in Tirisfal only after the start zone chain).
- **New Forever mobs and quests:** new Forever variants that drop quest items (Vile Fin in Tirisfal, Razormane and Oasis Snapjaws in The Barrens and more) count as quest mobs, and the new Forsaken paladin quests show their targets.

## 1.2.1

- **Spawn points for 14 zones:** every spawn point of quest mobs and quest objects from the Wowhead Forever quest maps, for Elwynn Forest (with Northshire), Dun Morogh (with Coldridge Valley), Teldrassil (with Shadowglen), Westfall, Loch Modan, Darkshore, Redridge Mountains, Wetlands, Duskwood, Ashenvale, Silverpine Forest, Hillsbrad Foothills, Arathi Highlands and Stonetalon Mountains. That is roughly level 1 to 30, mostly the Alliance side; the Horde quests of these zones are included. The Horde start zones and The Barrens follow in a later version.
- **New Forever quests and mobs:** the new Forever quests of these zones get their spawn points too, and new Forever mobs that also drop quest items (for example Dragonmaw in the Wetlands, Witherbark in Arathi) now count as quest mobs: icon, tooltip and spawn points.

## 1.2.0

- **Quests of the zone:** a new window lists every quest of the zone: in your log, available, later (with the reason) and done. Click one: the arrow points there and the map marks it. `/qd zone` or the new list button in the title bar.
- **More spawn points:** quest mobs show all their spawn points for the first quests (Elwynn, Westfall, Redridge and more), and Questdon now also learns where quest mobs are when they come close to you, shared with other players.
- **Title bar:** a gear button opens the options.
- **Back to your corpse:** after you release your spirit, the arrow leads to your corpse.
- **Learns new quest mobs:** mobs that gave credit for a quest without mob data (many new Forever quests) now get quest icons, tooltips and learned spots too.
- **XP only once:** while the XP bar is shown, the window leaves out its experience lines; the bar now also shows where in the level you land after turning in.

## 1.1.0

- **Learn together:** Questdon now shares what it learns with other Questdon players (only numbers, no names): your guild and group, and everyone else through a hidden channel. Turn-ins and objective spots that enough players reported show up for everyone. Both on by default, each with its own option.
- **Learns more while you play:** quest chains, quests that start at objects or from items, which mob, object or item counts for an objective, and where quest items drop.
- **Much more quest data:** many new Forever quests with start, turn-in and objectives for both factions, plus an updated quest database.
- **Quests that are not there:** when a quest giver never offers a quest, Questdon hides it for all your characters. For quest givers without a dialog, Alt-click the ! or target the NPC and type /qd nothere.
- **Nearest quest:** now off by default and, when on, only points to confirmed quests close to you.

## 1.0.0

First release on CurseForge.
