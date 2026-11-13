-- Levelling route: 29-31 Mulgore + Thousand Needles (Excavation Site -> RFK), Horde. Written 12 Nov 2026 (Gaz & Claude),
-- our own text - no RestedXP paid content. Quest/NPC/object ids and every coordinate come from the Questie Forever database
-- (QuestieDB_Forever, Forever map percentages - Mulgore is already in Forever's rescaled coordinates); quest levels from the
-- same data. Forever-only quests: Gloomrise chain (Muln Earthfury), Jandia's two Roguefeather quests, Thundering Hearts.
-- Broodmother: player reports say Muln only offers it after Defending the Dead is handed in - optional, the kill steps skip
-- themselves when you don't take it. Warrior class quest The Islander is Warrior-only. Ends at Shimmering Flats pickups (~31);
-- the Ratchet / Orgrimmar errands are left for the next route.
RXPGuides.RegisterGuide([==[
<< Horde
#version 1
#classic
#group Gaz & Claude Routes (H)
#name 29-31 Mulgore + Thousand Needles (Excavation to RFK)
step
    >>|cRXP_WARN_Picks up where the Excavation Site primer ends (about level 29). Covers the Forever Gloomrise quests north of Thunder Bluff, then Thousand Needles, and leaves you at about 31 ready for Razorfen Kraul|r
    .goto Orgrimmar,45.12,63.89
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tOnly if you're in Orgrimmar: talk to |cRXP_FRIENDLY_Doras|r on the tower
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .target Doras
    .zoneskip Thunder Bluff
    .zoneskip Mulgore
step
    #completewith Muln1
    .goto Mulgore,33.42,22.52,40 >> Head to Skywatcher Plateau, the hill just north-west of Thunder Bluff
step
    #label Muln1
    .goto Mulgore,33.42,22.52
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Muln Earthfury|r
    .accept 96259 >> Accept Defending the Dead
    >>|cRXP_WARN_He won't offer The Broodmother yet - that comes after you hand this one in|r
    .target Muln Earthfury
step
    .goto Mulgore,32.52,20.60
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mazu'kon|r
    .accept 96241 >> Accept Talkin' bout Toxins, Mon
    .target Mazu'kon
step
    .goto Mulgore,32.46,19.99
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Yorn Grimtotem|r
    .accept 96260 >> Accept Stronger than Steel
    .target Yorn Grimtotem
step
    #loop
    .goto Mulgore,33.20,9.80,0
    .goto Mulgore,32.40,12.00,40,0
    .goto Mulgore,33.40,9.40,40,0
    .goto Mulgore,35.00,9.00,40,0
    .goto Mulgore,34.50,12.50,40,0
    >>Gloomrise, the spider nest due north. Kill |cRXP_ENEMY_Gloomrise Hatchlings|r and |cRXP_ENEMY_Gloomrise Soldiers|r, take |cRXP_LOOT_Crystalline Silk|r from |cRXP_ENEMY_Gloomrise Spinners|r, and use the |cRXP_LOOT_Toxin Extractor|r on |cRXP_PICK_Gnawed Corpses|r
    >>|cRXP_WARN_Stay out of the far north end for now - the Broodmother sits there|r
    .complete 96259,1
    .complete 96259,2
    .complete 96260,1
    .complete 96241,1
    .use 273015
    .mob Gloomrise Hatchling
    .mob Gloomrise Soldier
    .mob Gloomrise Spinner
step
    .goto Mulgore,32.52,20.60
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mazu'kon|r
    .turnin 96241 >> Turn in Talkin' bout Toxins, Mon
    .target Mazu'kon
step
    .goto Mulgore,32.46,19.99
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Yorn Grimtotem|r
    .turnin 96260 >> Turn in Stronger than Steel
    .target Yorn Grimtotem
step
    .goto Mulgore,33.42,22.52
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Muln Earthfury|r
    .turnin 96259 >> Turn in Defending the Dead
    .accept 96261 >> Accept The Broodmother (optional)
    >>|cRXP_WARN_Optional: Broodmother Valraxx is a level 30-31 ELITE. Reward: the Transformative Cocoon trinket, and her letter starts A Darker Truth. Don't take it if you won't kill her - the next two steps then skip|r
    .target Muln Earthfury
step
    .goto Mulgore,33.50,7.30
    >>Kill |cRXP_ENEMY_Broodmother Valraxx|r at the north end of Gloomrise. Loot the |cRXP_LOOT_Bloody Parchment|r and click it to start A Darker Truth
    >>|cRXP_WARN_Clear the spiders round her first. She poisons (less healing taken, slowed), puts a poison DoT on you and webs you in place|r
    .complete 96261,1
    .collect 273658,1,96294
    .accept 96294 >> Accept A Darker Truth
    .use 273658
    .mob Broodmother Valraxx
    .isOnQuest 96261
step
    .goto Mulgore,33.42,22.52
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Muln Earthfury|r
    .turnin 96261 >> Turn in The Broodmother
    .turnin 96294 >> Turn in A Darker Truth
    .target Muln Earthfury
    .isOnQuest 96261
step
    #completewith next
    .goto Thunder Bluff,46.90,50.30,60 >> Ride up into Thunder Bluff - the lifts are on the south side of the bluffs
    .zoneskip Thunder Bluff
step
    .goto Thunder Bluff,55.00,51.40
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Zangen Stonehoof|r
    .accept 1196 >> Accept The Sacred Flame
    >>|cRXP_WARN_Only if you did part 1 (the Ashenvale moonwell phial). If not, skip this step - the rest of the chain skips with it|r
    .target Zangen Stonehoof
    .isQuestTurnedIn 1195
step
    .goto Thunder Bluff,61.53,80.92
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Melor Stonehoof|r on Hunter Rise
    .accept 1131 >> Accept Steelsnap
    .target Melor Stonehoof
step << Warrior
    .goto Thunder Bluff,57.20,87.40
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tWarriors at level 30: talk to |cRXP_FRIENDLY_Torm Ragetotem|r
    .accept 1718 >> Accept The Islander
    >>|cRXP_WARN_Warrior class quest (Fray Island in the Barrens) - it's done on the next route, just take it now. Come back at 30 if you're not there yet|r
    .target Torm Ragetotem
step
    .goto Thunder Bluff,36.01,59.90
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Auld Stonespire|r on Spirit Rise
    .accept 1102 >> Accept A Vengeful Fate
    >>|cRXP_WARN_A Razorfen Kraul quest - keep it for the dungeon|r
    .target Auld Stonespire
step
    .goto Thunder Bluff,45.83,64.74
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to the innkeeper
    .home >> Set your Hearthstone to Thunder Bluff (you'll be back once mid-way)
step
    .goto Thunder Bluff,47.00,49.83
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r
    .fly Camp Taurajo >> Fly to Camp Taurajo
    .target Tal
step
    .goto The Barrens,45.10,57.70
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tatternack Steelforge|r
    .accept 1153 >> Accept A New Ore Sample
    >>|cRXP_WARN_Only offered if you did Weapons of Choice earlier - skip otherwise|r
    .target Tatternack Steelforge
    .isQuestTurnedIn 893
step
    #completewith next
    .goto The Barrens,48.94,86.31,60 >> Ride south down the road towards Bael Modan
step
    .goto The Barrens,48.94,86.31
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Feegly the Exiled|r
    .accept 857 >> Accept The Tear of the Moons
    .target Feegly the Exiled
step
    .goto The Barrens,49.10,84.20
    >>Open |cRXP_PICK_General Twinbraid's Strongbox|r just north of Feegly and take the |cRXP_LOOT_Tear of the Moons|r
    .complete 857,1
step
    .goto The Barrens,48.94,86.31
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Feegly the Exiled|r
    .turnin 857 >> Turn in The Tear of the Moons
    .target Feegly the Exiled
step
    #completewith next
    .goto Thousand Needles,31.86,21.66,60 >> Ride south-west to the Great Lift and take it down into Thousand Needles
step
    .goto Thousand Needles,31.86,21.66
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Grish Longrunner|r at the bottom of the lift
    .turnin 5881 >> Turn in Calling in the Reserves
    .target Grish Longrunner
    .isOnQuest 5881
step
    .goto Thousand Needles,32.20,22.20
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Brave Moonhorn|r
    .accept 4542 >> Accept Message to Freewind Post
    .target Brave Moonhorn
step
    #completewith Freewind
    .goto Thousand Needles,39.40,33.10,0
    >>On the way, kill the |cRXP_ENEMY_Galak Messenger|r if you see him (he walks the road) - his note starts Assassination Plot
    .collect 12564,1,4881
    .accept 4881 >> Accept Assassination Plot
    .use 12564
    .mob Galak Messenger
step
    #label Freewind
    .goto Thousand Needles,45.70,50.70
    >>Follow the road south-east to Freewind Post, up on the big mesa. |Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Cliffwatcher Longhorn|r
    .turnin 4542 >> Turn in Message to Freewind Post
    .accept 4841 >> Accept Pacify the Centaur
    .target Cliffwatcher Longhorn
step
    .goto Thousand Needles,46.00,50.90
    >>Click the |cRXP_PICK_Wanted Poster|r beside him
    .accept 5147 >> Accept Wanted - Arnak Grimtotem
step
    .goto Thousand Needles,46.21,51.51
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Jandia|r
    .accept 98069 >> Accept Stolen Freewind Supplies
    .accept 98070 >> Accept Stop the Screeching
    .target Jandia
step
    .goto Thousand Needles,46.10,51.70
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rau Cliffrunner|r
    .turnin 1196 >> Turn in The Sacred Flame
    .accept 1197 >> Accept The Sacred Flame
    .target Rau Cliffrunner
    .isOnQuest 1196
step
    .goto Thousand Needles,44.60,50.30
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Hagar Lightninghoof|r
    .accept 4821 >> Accept Alien Egg
    .target Hagar Lightninghoof
step
    .goto Thousand Needles,44.90,48.90
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Elu|r
    .accept 4767 >> Accept Wind Rider
    .target Elu
step
    .goto Thousand Needles,45.14,49.11
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Nyse|r
    .fp Freewind Post >> Get the Freewind Post flight path
    .target Nyse
step
    #completewith CentaurDone
    >>Kill |cRXP_ENEMY_Galak Scouts|r, |cRXP_ENEMY_Wranglers|r and |cRXP_ENEMY_Windchasers|r as you go
    .complete 4841,1
    .complete 4841,2
    .complete 4841,3
step
    .goto Thousand Needles,42.00,31.50
    >>Head north to the Galak centaur camps. In the camp by the cliff, click the |cRXP_PICK_Ancient Brazier|r for the |cRXP_LOOT_Cloven Hoof|r
    .complete 1197,1
    .isOnQuest 1197
step
    #label CentaurDone
    #loop
    .goto Thousand Needles,43.40,38.50,0
    .goto Thousand Needles,43.30,38.00,40,0
    .goto Thousand Needles,44.40,36.30,40,0
    .goto Thousand Needles,42.40,40.00,40,0
    .goto Thousand Needles,39.40,33.10,40,0
    >>Finish the centaurs. Keep an eye out for the |cRXP_ENEMY_Galak Messenger|r on the road west of the camps if you still need his note
    .complete 4841,1
    .complete 4841,2
    .complete 4841,3
    .mob Galak Scout
    .mob Galak Wrangler
    .mob Galak Windchaser
step
    .goto Thousand Needles,53.95,41.49
    >>Go east to |cRXP_FRIENDLY_Dorn Plainstalker|r, standing by the planks over the canyon
    .accept 1149 >> Accept Test of Faith
    .target Dorn Plainstalker
step
    >>Walk out to the end of the plank and jump. Trust it - you won't die
    .complete 1149,1
step
    .goto Thousand Needles,53.95,41.49
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Dorn Plainstalker|r
    .turnin 1149 >> Turn in Test of Faith
    .accept 1150 >> Accept Test of Endurance
    .target Dorn Plainstalker
step
    #completewith EggDone
    .goto Thousand Needles,55.50,51.40,0
    >>Optional: if you took Thundering Hearts in Undercity, kill |cRXP_ENEMY_Stormheart|r - it roams the mesas east of Freewind
    .complete 97985,1
    .mob Stormheart
    .isOnQuest 97985
step
    #completewith EggDone
    .goto Thousand Needles,64.00,46.90,0
    >>Kill |cRXP_ENEMY_Gravelsnout Diggers|r and |cRXP_ENEMY_Surveyors|r (kobolds) when you see them for an |cRXP_LOOT_Unrefined Ore Sample|r
    .complete 1153,1
    .mob Gravelsnout Surveyor
    .mob Gravelsnout Digger
    .isOnQuest 1153
step
    #label EggDone
    .goto Thousand Needles,52.30,55.20
    >>Find the |cRXP_PICK_Alien Egg|r. It's in one of a few spots south-east of Freewind - check around 52,55, then 56,50, then 37,56 to the west
    .complete 4821,1
step
    .goto Thousand Needles,45.70,50.70
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tBack at Freewind, talk to |cRXP_FRIENDLY_Cliffwatcher Longhorn|r
    .turnin 4841 >> Turn in Pacify the Centaur
    .accept 5064 >> Accept Grimtotem Spying
    .target Cliffwatcher Longhorn
step
    .goto Thousand Needles,46.10,51.70
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rau Cliffrunner|r
    .turnin 1197 >> Turn in The Sacred Flame
    .target Rau Cliffrunner
    .isOnQuest 1197
step
    .goto Thousand Needles,44.60,50.30
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Hagar Lightninghoof|r
    .turnin 4821 >> Turn in Alien Egg
    .accept 4865 >> Accept Serpent Wild
    .target Hagar Lightninghoof
step
    #completewith Grenka
    .goto Thousand Needles,27.20,51.00,0
    >>Head west to Roguefeather Den. Kill |cRXP_ENEMY_Screeching Harpies|r, |cRXP_ENEMY_Roguefeathers|r and |cRXP_ENEMY_Windcallers|r, and pick up |cRXP_PICK_Stolen Freewind Supplies|r around the den
    .complete 98070,1
    .complete 98070,2
    .complete 98070,3
    .complete 98069,1
step
    #label Grenka
    .goto Thousand Needles,26.30,55.50
    >>Kill |cRXP_ENEMY_Grenka Bloodscreech|r at the back of the den and take her claw
    >>|cRXP_WARN_Level 31 named harpy - pull her guards first|r
    .complete 1150,1
    .mob Grenka Bloodscreech
step
    #loop
    .goto Thousand Needles,27.20,51.00,0
    .goto Thousand Needles,27.20,50.60,40,0
    .goto Thousand Needles,26.40,54.00,40,0
    .goto Thousand Needles,27.60,49.90,40,0
    >>Finish Jandia's harpies and supplies
    .complete 98070,1
    .complete 98070,2
    .complete 98070,3
    .complete 98069,1
    .mob Screeching Harpy
    .mob Screeching Roguefeather
    .mob Screeching Windcaller
step
    #completewith Paoka
    .goto Thousand Needles,14.00,37.00,0
    >>Go north-west up to Highperch (the wyvern mesas). Grab |cRXP_PICK_Highperch Wyvern Eggs|r as you pass them
    .complete 4767,1
step
    #label Paoka
    .goto Thousand Needles,17.90,40.60
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Pao'ka Swiftmountain|r
    .accept 4770 >> Accept Homeward Bound
    >>|cRXP_WARN_Escort - he walks you off Highperch. Finish the eggs first if you want, he'll wait|r
    .target Pao'ka Swiftmountain
step
    #loop
    .goto Thousand Needles,14.00,37.00,0
    .goto Thousand Needles,12.00,37.00,40,0
    .goto Thousand Needles,13.90,39.10,40,0
    .goto Thousand Needles,16.00,34.00,40,0
    .goto Thousand Needles,11.00,35.00,40,0
    >>Finish the |cRXP_PICK_Highperch Wyvern Eggs|r, then escort |cRXP_FRIENDLY_Pao'ka|r down
    .complete 4767,1
    .complete 4770,1
step
    .goto Thousand Needles,17.80,19.80
    >>Go north to |cRXP_ENEMY_Steelsnap|r, a level 30 hyena in the north-west canyon, and take his rib
    .complete 1131,1
    .mob Steelsnap
step
    .goto Thousand Needles,21.20,32.10
    >>Go south to Whitereach Post. |Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Kanati Greycloud|r
    .turnin 4881 >> Turn in Assassination Plot
    .accept 4966 >> Accept Protect Kanati Greycloud
    .target Kanati Greycloud
    .isOnQuest 4881
step
    .goto Thousand Needles,21.20,32.10
    >>Kill the |cRXP_ENEMY_Galak Assassins|r that come for |cRXP_FRIENDLY_Kanati|r
    .complete 4966,1
    .mob Galak Assassin
    .isOnQuest 4966
step
    .goto Thousand Needles,21.20,32.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Kanati Greycloud|r
    .turnin 4966 >> Turn in Protect Kanati Greycloud
    .target Kanati Greycloud
    .isOnQuest 4966
step
    .goto Thousand Needles,21.50,32.40
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Motega Firemane|r
    .turnin 4865 >> Turn in Serpent Wild
    .accept 5062 >> Accept Sacred Fire
    .turnin 4770 >> Turn in Homeward Bound
    .target Motega Firemane
step
    .goto Thousand Needles,21.40,32.50
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Wizlo Bearingshiner|r
    .accept 5151 >> Accept Hypercapacitor Gizmo
    .target Wizlo Bearingshiner
step
    .goto Thousand Needles,22.80,24.60
    >>Go north to the cage. Kill the |cRXP_ENEMY_Enraged Panther|r and loot the |cRXP_LOOT_Gizmo|r and |cRXP_LOOT_Cage Key|r
    .complete 5151,1
    .mob Enraged Panther
step
    .goto Thousand Needles,21.40,32.50
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Wizlo Bearingshiner|r
    .turnin 5151 >> Turn in Hypercapacitor Gizmo
    .target Wizlo Bearingshiner
step
    #loop
    .goto Thousand Needles,35.80,34.90,0
    .goto Thousand Needles,33.30,33.00,40,0
    .goto Thousand Needles,36.00,38.80,40,0
    .goto Thousand Needles,37.80,35.00,40,0
    >>Go east to the plants around the Sacred Fire of Life and pick |cRXP_PICK_Incendia Agave|r
    .complete 5062,1
step
    .hs >> Hearth to Thunder Bluff
step
    .goto Thunder Bluff,61.53,80.92
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Melor Stonehoof|r
    .turnin 1131 >> Turn in Steelsnap
    .target Melor Stonehoof
step << Warrior
    .goto Thunder Bluff,57.20,87.40
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tWarriors: talk to |cRXP_FRIENDLY_Torm Ragetotem|r if you weren't 30 last time
    .accept 1718 >> Accept The Islander
    .target Torm Ragetotem
step
    .goto Thunder Bluff,69.80,30.90
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Magatha Grimtotem|r on Elder Rise
    .turnin 5062 >> Turn in Sacred Fire
    .accept 5088 >> Accept Arikara
    .target Magatha Grimtotem
step
    .goto Thunder Bluff,36.01,59.90
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Auld Stonespire|r if you didn't get A Vengeful Fate earlier
    .accept 1102 >> Accept A Vengeful Fate
    .target Auld Stonespire
step
    .goto Thunder Bluff,47.00,49.83
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r
    .fly Camp Taurajo >> Fly to Camp Taurajo
    .target Tal
    .isOnQuest 1153
step
    .goto The Barrens,45.10,57.70
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tatternack Steelforge|r
    .turnin 1153 >> Turn in A New Ore Sample
    .target Tatternack Steelforge
    .isQuestComplete 1153
step
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tFly to Freewind Post (from Thunder Bluff, or from Camp Taurajo's |cRXP_FRIENDLY_Omusa Thunderhorn|r)
    .fly Freewind Post >> Fly to Freewind Post
step
    .goto Thousand Needles,44.90,48.90
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Elu|r
    .turnin 4767 >> Turn in Wind Rider
    .target Elu
step
    .goto Thousand Needles,46.21,51.51
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Jandia|r
    .turnin 98069 >> Turn in Stolen Freewind Supplies
    .turnin 98070 >> Turn in Stop the Screeching
    .target Jandia
step
    .goto Thousand Needles,46.07,51.50
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to the innkeeper
    .home >> Set your Hearthstone to Freewind Post
step
    .goto Thousand Needles,53.95,41.49
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Dorn Plainstalker|r
    .turnin 1150 >> Turn in Test of Endurance
    .accept 1151 >> Accept Test of Strength
    .target Dorn Plainstalker
step
    .goto Thousand Needles,31.80,32.60
    >>Darkcloud Pinnacle (Grimtotem tauren, north-west). Open the |cRXP_PICK_Document Chest|r here for Secret Note #1
    .complete 5064,1
step
    .goto Thousand Needles,33.80,40.00
    >>Open the second |cRXP_PICK_Document Chest|r for Secret Note #2
    .complete 5064,2
step
    .goto Thousand Needles,39.30,41.50
    >>Open the third |cRXP_PICK_Document Chest|r for Secret Note #3
    .complete 5064,3
step
    .goto Thousand Needles,38.10,35.40
    >>Use the |cRXP_PICK_Sacred Fire of Life|r to call up |cRXP_ENEMY_Arikara|r. Kill her and take her skin
    .complete 5088,1
    .complete 5088,2
    .mob Arikara
step
    .goto Thousand Needles,38.10,26.90
    >>Climb to the top of Darkcloud Pinnacle and kill |cRXP_ENEMY_Arnak Grimtotem|r for his hoof
    .complete 5147,1
    .mob Arnak Grimtotem
step
    .goto Thousand Needles,21.50,32.40
    >>Back west to Whitereach Post. |Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Motega Firemane|r
    .turnin 5088 >> Turn in Arikara
    .target Motega Firemane
step
    #loop
    .goto Thousand Needles,13.90,30.60,0
    .goto Thousand Needles,11.00,24.00,50,0
    .goto Thousand Needles,14.00,30.60,50,0
    .goto Thousand Needles,17.00,38.00,50,0
    >>Find |cRXP_ENEMY_Rok'Alim the Pounder|r, a level 30 elemental that walks the west side of the zone, and take the Fragments
    .complete 1151,1
    .mob Rok'Alim the Pounder
step
    .goto Thousand Needles,38.00,26.40
    >>Go back to the top of Darkcloud Pinnacle. |Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Lakota Windsong|r
    .accept 4904 >> Accept Free at Last
    >>|cRXP_WARN_Escort - she takes you down off the pinnacle. Grimtotems attack on the way|r
    .target Lakota Windsong
step
    >>Keep |cRXP_FRIENDLY_Lakota|r alive until she's safe
    .complete 4904,1
step
    .hs >> Hearth to Freewind Post
step
    .goto Thousand Needles,45.70,50.70
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Cliffwatcher Longhorn|r
    .turnin 5064 >> Turn in Grimtotem Spying
    .turnin 5147 >> Turn in Wanted - Arnak Grimtotem
    .target Cliffwatcher Longhorn
step
    .goto Thousand Needles,45.97,51.61
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thalia Amberhide|r
    .turnin 4904 >> Turn in Free at Last
    .target Thalia Amberhide
step
    .goto Thousand Needles,53.95,41.49
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Dorn Plainstalker|r
    .turnin 1151 >> Turn in Test of Strength
    .target Dorn Plainstalker
step
    #completewith next
    .goto Thousand Needles,77.80,77.30,80 >> Ride south-east down into the Shimmering Flats (the salt flats with the race track)
step
    .goto Thousand Needles,77.80,77.30
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Kravel Koalbeard|r
    .accept 1110 >> Accept Rocket Car Parts
    .accept 1111 >> Accept Wharfmaster Dizzywig
    .target Kravel Koalbeard
step
    .goto Thousand Needles,78.10,77.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Fizzle Brassbolts|r and |cRXP_FRIENDLY_Wizzle Brassbolts|r
    .accept 1104 >> Accept Salt Flat Venom
    .accept 1105 >> Accept Hardened Shells
    .target Fizzle Brassbolts
    .target Wizzle Brassbolts
step
    .goto Thousand Needles,80.20,75.90
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Pozzik|r
    .accept 1176 >> Accept Load Lightening
    .target Pozzik
step
    .goto Thousand Needles,81.60,78.00
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Trackmaster Zherin|r
    .accept 1175 >> Accept A Bump in the Road
    .target Trackmaster Zherin
step
    >>|cRXP_WARN_Route done - you should be about 31. The Shimmering Flats quests, Wharfmaster Dizzywig (Ratchet) and The Islander carry on in the next route. Razorfen Kraul is ready to go: A Vengeful Fate is in your log|r
]==])
