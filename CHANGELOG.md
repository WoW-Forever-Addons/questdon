# Changes

## 1.3.12

- **Update note:** new files, so restart the game after updating (a /reload is not enough).
- **Arrow:** dungeon quests point to the entrance while you are outside; event and explore quests point to their place instead of the quest giver (Forever and Classic Era, for example the Fargodeep Mine).
- **Pin size:** Options can now scale the quest pins on the world map and the minimap (25 to 200 %).
- **Sizes for large screens:** on WQHD and 4K screens the XP bar and the quest list text start at 100 % and 90 % instead of 145 % and 120 % (only while you still use the defaults; your own values stay).
- **Options window:** headers are no longer cut off ("- W...", "Qu...").
- **Gathering places for the shared data:** when you gather herbs, mine ore, skin a creature or fish, Questdon notes the place, the node or creature and what you got, and shares it with the other learned data (option "Learn quest data"). Nothing new is shown in the game yet; the finds help the shipped data grow.
- **Complete quest lists:** Questdon notes which quests each character has completed, and /qd scan asks the server which quest IDs exist (in the background, a few hours, /qd scan status). Both help us find quests that are still missing in the data. Nothing new is shown in the game.
- **Data:** All The Things and ForeverDB updated (Forever build 70532); ForeverDB is now credited in the README.

## 1.3.11

- **Update note:** new files, so restart the game after updating (a /reload is not enough).
- **Now also for WoW Classic Era (and Hardcore):** the same download works in Classic Era with its own quest data from CMaNGOS classic-db on Era's maps. Sharing on Era uses its own channel, so Era and Forever data never mix.
- **Moments in the journal:** besides quests the journal now keeps the moments of your adventure: a screenshot (with place, quest and group; a click shows a card with a map dot and a note field), a death, a dungeon visit with its bosses, a new zone, rare loot or better, a new home inn and a new reputation rank. The filter "Moments" shows only them; options under Comfort > More settings.
- **Chapters and recap:** the filter "Chapters" sums up your time in each zone as a card (quests, levels, play time, deaths, who you played with); a click opens it. "Review" shows your numbers and records, the last week, your characters and a bar of play time per level. "Copy as text" at the bottom right gives the journal as text to paste, for example into Discord.
- **Only collect and share:** one switch turns off everything Questdon shows and does by itself (map markers, quest list, arrow, XP bar, tooltips, automation) and keeps learning and sharing on, so you help the quest data without seeing Questdon. A second click brings your settings back exactly as they were. In the start window, the minimap menu, Options > Sharing and data, or /qd collect.
- **Arrow and compass:** while Leveldon shows the compass in its window, Questdon's arrow and the list's compass stay aside. The rows "Show window" (direction arrow) and "Compass in the quest list" now say "Leveldon" instead of "on" then, and the explanation on the right tells how to see them again.
- **Arrow without plate:** Options > Quest list and arrow > "No background and frame" under Direction arrow hides the plate and frame behind the arrow's text, as for the quest list. This is now the default, and with this update the quest list and the arrow both go see-through once for everybody (switch the frame back on in the same place). The tab now has headers "Quest list" and "Direction arrow", so you can tell at a glance which option belongs to which.
- **For Leveldon:** the API has ArrowMode/SetArrowMode (arrow on, list compass off, the values before are kept) and ArrowPlain/SetArrowPlain, used by Leveldon's new option "Arrow instead of the compass".
- **Quest list on a key:** Key Bindings > AddOns > Questdon > "Show or hide the quest list".
- **Postcards for screenshots:** a screenshot in the journal now shows a picture made by the game itself, no helper needed: the map around the spot with a gold dot, your character in the gear you wore, the creature you had targeted, and a tint for the time of day.
- **The story:** the card of a quest you turned in shows what the quest giver told you at the turn-in (shortened; option "Story in the journal", on).
- **Quest levels and turn-ins:** levels the game showed in our players' quest logs are now part of the data, so colours and the grey folding follow them for quests outside your log too; more levels and turn-in places for quests that are new or changed in Forever.
- **Lighter:** the quest list and the minimap no longer rebuild on every quest log event when nothing they show changed, and zooming the world map back to a zoom step you saw before reuses its symbols.
- **Small fixes:** the line under Leveldon's target is no longer cut off in the objective area, the compass is never empty (the next objective also when it is further than 400 yards), a breadcrumb hint names the quest it leads to, and a pin's tooltip says "Chain: step 2 of 3".
- **Walking NPCs:** routes that players saw an NPC walk are marked as confirmed; an NPC seen far away from its route loses the doubtful route.

## 1.3.10

- **Symbols over the right mobs and items:** when the game lists a quest's goals in another order than Questdon's data (Slimy Menace and An Enticing Offer after a Forever update), Questdon now matches them by the names of the mobs and items, so what you still need gets its symbol and finished goals lose theirs. What Questdon had learned for these two quests in the wrong order is dropped once. Questdon also remembers the order it saw, and while a quest's order is unclear it learns nothing for it rather than something wrong.

- **Lighter while questing:** a kill or a loot no longer makes the quest list, the walking routes, the quest item check and the sounds work everything out again; counts and XP are written into the list in place, the arrow no longer makes new garbage at every frame while it follows a guide like Leveldon, and the world map no longer draws its pins anew while it is closed or when nothing on it changed. Fewer small stutters while you quest.

- **Better data from your play:** with "Learn quest locations" on, Questdon also notes what an NPC is when you use it (vendor, trainer, innkeeper, flight master, spirit healer) and adds it to /qd export, so Forever's new zones get their trainers and inns.

- **Open data only:** Questdon's quest data now comes only from open sources: All The Things, the open Classic database CMaNGOS (positions converted to Forever's maps with the client's own map frames), ForeverDB and what Questdon players record. Quest texts before you take a quest are in English; once a quest is in your log the game shows its own text in your language.

- **Fold sections of the quest list:** click a section header (Ready to turn in, Nearby, a zone) to fold it; folded sections move to the bottom with their header and the number of quests, a second click opens them again.

## 1.3.9

- **Questdon's own options window:** all options in tabs (Map, Quest list and arrow, Accept and turn in, XP bar, Comfort, Sharing and data, Help), each with a short explanation and an example picture, and a search over all of them. Open it with /qd, the cog in the quest list or the minimap button's menu.
- **First start:** a small window lets you pick how the map looks (Questdon's symbols, Questdon's dots or only the game's own map) and switch the arrow, the quest list, auto accept and a see-through quest list on or off. /qd setup brings it back.
- **Symbols on the map:** quest mobs, loot, objects to click, places to explore and items to use get their own symbols; spots close together are one symbol over a soft area in the quest's colour. Questdon can hide the game's own quest markers so the map is not drawn twice.
- **Walking quest NPCs:** NPCs who walk a route (for example quest givers on patrol) show their path as a red dotted line on the map and minimap. Questdon players' sightings confirm the routes; doubtful ones are left out.
- **See-through quest list:** for new players the list shows without background and frame, with outlined text that stays readable over any ground; one switch (start window or options) brings the frame back. Folded, the list says how many more quests it holds.
- **Play times for better data:** Questdon measures how long quests take in their objective area, how often quest items drop, how long flights take and which quests get abandoned, and shares these numbers like the other learned data (option "Share play times", only numbers, no names). They make the quest data and Leveldon's routes better.
- **Much lighter:** Questdon makes far less new memory while you stand and walk (quest list, arrow, minimap, sightings and the calls of other addons like Leveldon), which means fewer small stutters. /qd mem shows each part with its calls a second.
- **Fixes:** quest mob dots no longer go missing on the world map when many quests share a zone (northern Tirisfal murlocs), the game's markers come back at once when you switch their hiding off, the size handle no longer covers the X of the folded list, places learned right after a loading screen no longer land on the continent map, and "only the game's map" leaves the turn-in ? to the game as well.
- **Quest data:** chain fixes (warrior letters, Forever's own steps, quests that are one of two choices) and the newest places learned by players.

## 1.3.8

- **Smoother:** far less work in the background. The quest list no longer rebuilds all quest points every second, unchanged map and minimap dots are reused, the quest log is read again only when it changes, the player's position is read without making new tables, and in a fight Questdon updates at most once a second. This removes the small stutters some players had with 1.3.7. /qd mem measures how much memory the quest addons take and which part of Questdon makes new memory.
- **Breadcrumb warning:** when a breadcrumb you have not done leads to a quest, Questdon says so and leaves that quest to you instead of accepting it, because taking it makes the breadcrumb and its XP disappear. Breadcrumbs also leave the map once their quest is taken.
- **Objects and mobs apart:** objects to click (crates, plants, chests) are diamonds on the map and minimap, mobs stay round dots, and the arrow says "click the objects" when you are there. Where a quest item is used, the pin shows the item's icon.
- **Easier to read maps:** mouse over a dot and the other quests' dots step back; a dot you stand on fades so you see the mob itself.
- **The arrow leads to the mobs:** far away it leads to a group of spawns instead of a lone one that is a little nearer.
- **Quest item button:** a small watch shows that the button changes once the fight is over, the button shows charges and dims while you are far from where the item is used.
- **Other addons:** selling junk, repairing and fast loot are left to Leatrix Plus, ElvUI or a vendor or loot addon that already does them (Questdon says so once). With Geardon, rewards that are an upgrade for you are marked before you take the quest.
- **Quest log headings:** quests under a heading you collapsed in the game's quest log stay in Questdon's list and on the map.
- **Search:** the quest book search finds "ärger" in "Ärger" and Cyrillic words in any case.
- **A reward for your class:** a green frame marks the reward players of your class pick most often. Until enough of them have picked, it marks the one with the right armor and stats for your class, if it beats what you wear. The gold coin for the highest vendor price stays. What you pick yourself is shared anonymously (quest, class and item only).
- **Quest givers where they really stand:** where players take or hand in a quest somewhere else than the data says, Questdon now shows that place (for example Shhh! We're Hunting Kobolds in Northshire). Plus the newest places, follow-ups and objectives learned while playing.
- **Quest list under Leveldon:** docked under Leveldon's window, the handle at the bottom right sets how many quests the list shows; the width stays Leveldon's. Plus new ways over the hills in Elwynn Forest for the arrow.
- **Group quests marked:** elite and other group quests say (Group) behind their name in the quest list, in the colour of their level.
- **Timed quests:** the quest list shows the time left of a timed quest.
- **No gold paid by Questdon:** also when the game opens the reward window right away, a quest with a gold cost is left to you.
- **Undead start:** the arrow leads straight to Marla's grave (Death Knell's valley and Solliden Farmstead were taken for mountains), the ? of a quest handed in at a quest giver is no longer hidden under that giver's !, Discipline shows the Deathguards to punish, Fields of Grief all pumpkin patches and Scavenging Deathknell the equipment boxes.
- **Fixes:** the quest item button no longer gets stuck when you drag it into a fight, the turn-in ? stays when Questie is installed but switched off, a failed quest's item leaves the button, and a quest you accept in a fight is shared with your group afterwards.
- **Quest data:** many prerequisites, quest givers, levels and race and class rules corrected (warlock quests for every warlock race, hint quests no longer required).
- **Newest quest data:** ATT's latest Forever data with new quests in Teldrassil, Darkshore, the Barrens and Duskwood, and the Mulgore chains linked in the right order.

## 1.3.7

- **The old Questdon window is gone:** the quest list does its job now. At its bottom: quests in the log (yellow when nearly full), quest items no quest needs any more (click twice to destroy the first one) and your group's quest progress. The quest book button sits in the list's title bar, /qd panel switches the quest list. Dungeon quests: the minimap button, the quest book or /qd dungeons.
- **One ! on the minimap:** where the game marks a quest giver, Questdon draws no second ! or ?, now in the whole minimap view and not only close by.
- **Compass and arrow:** the quest list's compass and the separate direction arrow are two switches now. By default the list shows the compass and the arrow window is off; switch the list's compass off and the arrow comes back, or switch both on.
- **Grey quests in the quest list:** quests that give no XP for your level are folded into one line at the bottom; click it to show or hide them, or hide them completely with the option "Hide grey quests". Right-click a quest for a small menu: abandon it, hide it from the list, or show the quests you hid.
- **More known ways for the arrow:** the ways Questdon players walked, your own and the shared ones, now come with the data, so the way around mountains is known in more places.
- **Quest data:** more quest chains, turn-ins and objective places learned while playing, also from other Questdon players. Disrupt the Attacks (Barrens) shows for every Horde player from level 9; it waited for Journey to the Crossroads before, which is only a hint quest. The class sigils in Shadowglen show right after The Balance of Nature (1/2).

## 1.3.6

- **Update note:** new files, so restart the game after updating (a /reload is not enough).
- **Your own quest list:** Questdon's window replaces Blizzard's quest tracker. On top the quest you picked, with its objectives as small blocks and a compass that takes the place of the arrow. Below your other quests, finished ones first and the rest by distance with a small needle each, or by zone (also by level) like Blizzard's list. Click a quest to pick it. Three tabs on top switch between nearby, by zone and by level. A handle at the bottom right sets the width and how many quests it shows, Ctrl + mouse wheel the text size. The background can be made lighter down to no background at all. /qd list switches back to Blizzard's tracker.
- **Quest levels as the game shows them:** Questdon's lists and markers show the level from your quest log (the quest's own level), where they showed the level you may take it at before.
- **No more doubled ! and ? on nameplates:** quest givers and turn-ins keep only the game's own ! and ?. Questdon's pins over the mobs of your open objectives stay.
- **Read the whole quest:** Shift-click a quest (or the book button) and read its whole text, objectives and rewards; click again to close it. Texts of quest givers are kept, so you can read them again later.
- **Every dungeon entrance:** all 27 dungeons and raids now have their entrance on the map, also Uldaman, Blackrock Mountain, Dire Maul, Stratholme, Naxxramas, both Ahn'Qiraj raids, the Hall of Thanes, the Ruins of Lordaeron and the City of Dalaran. Where there are two ways in (Uldaman, Stratholme, Blackrock Mountain), both are marked and "Mark entrance" takes the nearer one. The Deadmines, Shadowfang Keep, Gnomeregan, Maraudon and the Wailing Caverns now show the spot where you walk in.
- **Entrances learned by players:** when you walk into a dungeon, Questdon notes the way in and shares it like other learned data. A way in nobody knew yet appears on the map once players confirmed it.
- **Markers where the NPCs stand:** quest givers, turn-ins and quest mobs now sit on Forever's maps of Mulgore, the Eastern Plaguelands, Stormwind and Redridge. Before, they were off by up to a tenth of the map in the Plaguelands and by up to 150 yards in Stormwind. Everywhere else markers sat a few yards too far to the top left; that is fixed too.
- **About 400 more quests:** classic quests that were missing, among them the Western Plaguelands, Maraudon, Scholomance, Zul'Gurub and other level 55 to 60 quests, and class quests for druids, priests and warlocks. They count as not confirmed until the game shows them.
- **Traditional Chinese:** what to do in a quest, for about 1,900 quests, NPC names come from the game.
- **Dungeon quests:** about 20 quests that belong to a dungeon (Uldaman, Stratholme, Dire Maul and others) now show in its list.
- **Turn-ins in the NPC tooltip:** mouse over an NPC and see which of your quests you hand in there, a yellow ? when finished, a grey one when not yet.
- **Ways around mountains:** where a way is known, the arrow leads around mountains and cliffs (down the ramp instead of over the edge) and says "the way around". Questdon notes where you walk and shares it like other learned data, so the ways of other Questdon players help too. The mountains of Mulgore, Elwynn Forest, Duskwood, Ashenvale, Tirisfal Glades, Teldrassil, Darkshore, Dun Morogh, Loch Modan, Westfall, Redridge Mountains, Wetlands, Hillsbrad Foothills and Zephras Isle come checked on the map. Elsewhere the arrow points straight until ways are known. A target deep in a cave or inside a building sends you to its way in first ("first to the way in"), then along the tunnels; Questdon learns the ways in where you walk. The way also shows as dots on the world map and the minimap (option "Show the way as dots").
- **New hover cards on the map:** mouse over a quest marker on the world map or the minimap and a small card in the quest book look shows the quest: the level as a coloured badge, a stripe in the marker's colour (gold: take, green: turn in, the quest's colour: objective, blue: dungeon) and only the lines that matter.
- **NPCs that walk around:** where you met a quest NPC at places far apart, its map pin says so, so you look nearby instead of at one spot.
- **Quest data:** turn-in places of about 350 more quests (also at objects like cauldrons and graves), about 50 more quest starts, spawn points of more quest mobs, and for about 30 quests that only name an item, who drops it or where it lies. About 20 quests now know the quest that comes before them. Newest All The Things data with more Wetlands and Mulgore quests. Turn-ins at an NPC who stands in several zones now point to the one in your quest's zone (Call of Earth for shamans, Grom'gol in Stranglethorn).

## 1.3.5

- **Update note:** new files, so restart the game after updating (a /reload is not enough).
- **Dungeons by your level:** the Dungeons tab sorts every dungeon by you ("Your level", "Coming up", done), with its level range, its picture and how many of its quests you have done. Below: what to take now, what to do first and what is not yet and why. "Mark entrance" leads the arrow there, "Show on map" opens the map at the entrance.
- **Dungeon entrances on the map:** every dungeon and raid with a known entrance shows on the world map, and on the minimap when you are close. Click: the dungeon in the quest book. Right-click: mark it for the arrow.
- **Quest mobs on the minimap:** every spawn point of your quest mobs and objects around you. Where a field has many dots, close ones are bundled into one slightly larger dot that lists its quests, on the minimap and the world map. Option "Thin out dense objective dots".
- **Quest mobs stand out:** a pin in the quest's colour with a golden rim above the nameplate of a mob you need.
- **Quest items that start a quest:** a looted book or letter that starts a quest now shows on the quest item button once you can take that quest, with a small note above it the first time. One click opens the quest.
- **Arrow moves on by itself:** after a turn-in, or once you arrived, the arrow points to the next quest to turn in or a nearby open objective.
- **Quest details for about 4,800 quests in every language:** what to do, who gives and takes the quest, where the objectives are, from which level, and the rewards. NPC names show in your game language.
- **"?" where you turn in,** also for quests you never turned in before.
- **Repeatable quests:** no longer turned in automatically and hidden on the map (option to show them).
- **Shared quest data reaches players who were offline:** what Questdon shares goes out again once a day.
- **Quest data:** turn-in places of about 2,800 more quests, about 70 corrected quest starts and about 500 more quest mobs with their spawn points.

## 1.3.4

- **New direction arrow:** a golden compass needle that shines brighter and glows as you get close, a golden seal that pulses gently when you have arrived, and the target on a dark blue plaque with a thin golden line, like the quest book. The distance stands out in gold.
- **Minimap button:** left click opens the quest book, right click a small menu with the most used switches (quest markers, quest mobs, arrow, auto accept and turn in, XP bar, window) and all options. Mouse over shows what the window showed: quests here, dungeon quests and your quest log. Drag it around the minimap. The Questdon window is now off for new players; switch it on in the menu. A new button in the window's title bar sends it to the minimap.
- **New look for the quest book:** a gold frame with ornaments, framed tabs, every line as a card, your zone's map round in a gold ring and the day's numbers as cards.
- **Quest details:** click a quest in the quest book and a card on the right shows everything at one glance: quest giver and place, what to do, where to turn it in, the quests before and after it, plus buttons for the arrow and the world map.
- **Dungeon quests step by step:** each dungeon quest stands out as the goal, with what to do inside. Below it the quests to do first, numbered in the order you walk them on a gold line (quests you can do side by side share a number), each with what to do and where. Quest givers now have their names.
- **Dungeons tab:** every dungeon as a card with how well it fits your level, what is in your log, what you can pick up and where. "Route" leads the arrow from quest giver to quest giver, nearest first, and moves on when you accept a quest.
- **Zones tab:** filter the quests of a zone (available, in your log, later, done) and sort them by distance. The zone list shows "12/48" next to each bar.
- **Journal:** accepting and turning in a quest is one line now, with how long it took. Each day shows its quests, XP and XP per hour, and a small chart shows your XP of the last seven days.
- **No second "!" on the minimap:** the game marks every quest giver near you on the minimap itself. Questdon now leaves those to the game (within about 80 yards), so the two "!" no longer sit on top of each other. Farther away Questdon draws as before. Option "No second ! or ? where the game shows one", on by default.
- **Profession quests:** quests that need a profession, such as "Camping 101: Tailoring", now show their "!" once you have learned that profession. Before, Questdon left them out completely. In the quest book they say "profession not learned" until then.
- **Dungeon chains:** a quest in two parts, such as "Destruction in Deadmines", no longer lists its whole chain twice. The second part only points to the first, a step shared by two quests stands under the first one, and parts with the same name show "(1/2)" and "(2/2)".
- **Optional objectives:** the arrow no longer leads to an optional objective such as "listen to ..." while the real objective is still open. On the map and minimap optional objectives are dimmed, and nameplates get no mark for them.
- **Bugged (Zephras Isle):** the Skyhoppers now show their spawn points.
- **The Missing Scholar (Zephras Isle):** the unconscious scholar is marked inside the cave, no longer at the quest giver in front of it.
- **Quest data:** the newest All The Things data with seven new Wetlands quests and corrections for Zephras Isle. On top, about 250 Forever quests that All The Things does not have yet: class quests of all classes, and quests in Desolace, Duskwood, the Wetlands, Stranglethorn Vale, Shen'dralas and more. And the turn-in places of more than 700 quests's Forever quest pages (the Alliance zones up to level 30 and Zephras Isle), so the arrow and the map know where to hand them in.
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

- **Spawn points for the Horde start zones:** Durotar (with the Valley of Trials), Mulgore (with Red Cloud Mesa), Tirisfal Glades (with Deathknell) and The Barrens now bring every spawn point of quest mobs and quest objects too. Together with 1.2.1 this covers both factions up to roughly level 30.
- **Spawn points up to level 60:** Desolace, Thousand Needles, Dustwallow Marsh, Alterac Mountains, Stranglethorn Vale, Swamp of Sorrows, Badlands, Feralas, Tanaris, The Hinterlands, Searing Gorge, Azshara, Blasted Lands, Un'Goro Crater, Felwood, Burning Steppes, Western and Eastern Plaguelands, Winterspring and Silithus too. Every leveling zone of Kalimdor and the Eastern Kingdoms now has them.
- **Learned in the game:** turn-ins, follow-up quests and objective spots from players' /qd export are bundled (for example, "Kobold Camp Cleanup" only shows after "A Threat Within", and "The Adventurer" in Tirisfal only after the start zone chain).
- **New Forever mobs and quests:** new Forever variants that drop quest items (Vile Fin in Tirisfal, Razormane and Oasis Snapjaws in The Barrens and more) count as quest mobs, and the new Forsaken paladin quests show their targets.

## 1.2.1

- **Spawn points for 14 zones:** every spawn point of quest mobs and quest objects, for Elwynn Forest (with Northshire), Dun Morogh (with Coldridge Valley), Teldrassil (with Shadowglen), Westfall, Loch Modan, Darkshore, Redridge Mountains, Wetlands, Duskwood, Ashenvale, Silverpine Forest, Hillsbrad Foothills, Arathi Highlands and Stonetalon Mountains. That is roughly level 1 to 30, mostly the Alliance side; the Horde quests of these zones are included. The Horde start zones and The Barrens follow in a later version.
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
