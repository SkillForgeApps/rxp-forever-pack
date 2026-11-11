-- Dungeon primer: Excavation Site (Wetlands), Horde. Written 11 Nov 2026 (Gaz & Claude), our own text - no RXP paid content.
-- Sources: Questie Forever DB (quest/NPC ids, Zaruk/Borstan/Bashana/Muln spots), Wowhead Forever (XP, all quests Sharable,
-- Dragonmaw Rumors -> Open the Maw), dungeon guides (entrance ~47.9,56.4 on the hill SE of Whelgar's Excavation, Deathstalker
-- Agent beside the portal; Horde can't get Open the Maw without Dragonmaw Rumors). Thandol Span waypoint from RXP's own route.
RXPGuides.RegisterGuide([==[
<< Horde
#version 1
#classic
#group Gaz & Claude Dungeon Primers (H)
#name Primer - DG - Excavation Site (24-29) - Wetlands
step
    >>|cRXP_WARN_Dungeon primer: picks up the Horde Excavation Site quests and gets you to the portal. All of them are shareable - only one player in the group needs the Orgrimmar and Hammerfall pickups; share them at the portal|r
    >>|cRXP_WARN_Quest XP: Changing Tastes 3150, Dragonmaw Rumors 250, Open the Maw 3150, Elder Knowledge 630, Earthen Echo 3150|r
    .goto Orgrimmar,57.20,53.32
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Borstan|r, the meat vendor in the Valley of Strength
    .accept 95697 >> Accept Changing Tastes
    .target Borstan
step
    #completewith ZeppelinUC
    .zone Durotar >> Leave Orgrimmar through the main gate
    .zoneskip Durotar
    .zoneskip Tirisfal Glades
    .zoneskip Undercity
step
    #label ZeppelinUC
    .goto Durotar,50.8,13.8,40 >> Go up the Zeppelin Tower
    .zone Tirisfal Glades >> Take the Zeppelin to Tirisfal Glades
    .zoneskip Tirisfal Glades
    .zoneskip Undercity
step
    #completewith FlyTM
    .goto Tirisfal Glades,61.80,65.06,20 >> Enter Undercity
    .zoneskip Undercity
step
    .goto Undercity,48.90,70.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tOptional, on the way: talk to |cRXP_FRIENDLY_Calder Gray|r in the Apothecarium, beside Faranell
    .accept 97985 >> Accept Thundering Hearts
    >>|cRXP_WARN_Forever quest, 3300 XP: kill Stormheart (level 30) on the Thousand Needles mesas east of Freewind and bring its heart back here. Skip this step if you're not heading to Thousand Needles|r
    .target Calder Gray
step
    #label FlyTM
    .goto Undercity,63.27,48.55
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Michael Garrett|r
    .fly Tarren Mill >> Fly to Tarren Mill
    .target Michael Garrett
    .zoneskip Hillsbrad Foothills
    .zoneskip Arathi Highlands
step
    #completewith HammerfallFP
    .goto Arathi Highlands,20.19,29.54,60 >> Leave Tarren Mill east and enter the Arathi Highlands through Thoradin's Wall
    .zoneskip Arathi Highlands
step
    #completewith HammerfallFP
    .goto Arathi Highlands,73.10,32.70,60 >> Follow the road east to Hammerfall
    >>|cRXP_WARN_Keep clear of Refuge Pointe (Alliance town, middle of the zone) - its guards will kill you|r
step
    #label HammerfallFP
    .goto Arathi Highlands,73.10,32.70
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Urda|r
    .fp Hammerfall >> Get the Hammerfall flight path (your way home after the dungeon)
    .target Urda
step
    .goto Arathi Highlands,74.54,35.64
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Zaruk|r
    .accept 95663 >> Accept Dragonmaw Rumors
    >>|cRXP_WARN_Needed - without it the Deathstalker Agent won't give you Open the Maw|r
    .target Zaruk
step
    #completewith DeathstalkerAgent
    .goto Arathi Highlands,45.46,88.21,50 >> Head south-west to the Thandol Span bridge into the Wetlands
    .zoneskip Wetlands
step
    #completewith DeathstalkerAgent
    .goto Wetlands,47.90,56.40,40 >> Cross the Wetlands south to the dungeon: a hill south-east of Whelgar's Excavation Site, reached by new roads
    >>|cRXP_WARN_Dark Iron dwarves at Dun Modr (just past the bridge) and Menethil Harbor's guards (west coast) are hostile - stay on the inland road|r
step
    #label DeathstalkerAgent
    .goto Wetlands,47.90,56.40
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to the |cRXP_FRIENDLY_Deathstalker Agent|r beside the portal
    .turnin 95663 >> Turn in Dragonmaw Rumors
    .accept 95682 >> Accept Open the Maw
    .target Deathstalker Agent
step
    #completewith ExcavationRun
    +|cRXP_WARN_Group up and share|r |cRXP_FRIENDLY_Changing Tastes|r |cRXP_WARN_and|r |cRXP_FRIENDLY_Dragonmaw Rumors|r |cRXP_WARN_(quest log > Share). Each player hands Dragonmaw Rumors to the agent to get Open the Maw|r
step
    #label ExcavationRun
    >>|cRXP_WARN_Excavation Site - bosses Saltspine, Shadetooth (with two Thicket Hunters), Highland Horror, Relic Guardian (31 elite, last)|r
    >>Kill |cRXP_ENEMY_Dragonmaw|r forces - the |cRXP_ENEMY_Dragonmaw Thaumaturgist|r carries the |cRXP_LOOT_Dragonmaw Dispatch|r
    >>Loot |cRXP_LOOT_Thicket Raptor Meat|r from the |cRXP_ENEMY_Thicket|r raptors or |cRXP_ENEMY_Shadetooth|r
    .complete 95682,1
    .complete 95697,1
step
    >>|cRXP_ENEMY_Relic Guardian|r drops the |cRXP_LOOT_Titan Relic|r (also |cRXP_LOOT_Reliquary Mantle|r, mail shoulders) - click the relic to start Elder Knowledge and share it with the group
    >>|cRXP_WARN_Elder Knowledge was reported bugged in the beta - skip this step if the relic doesn't start a quest|r
    .accept 95664 >> Accept Elder Knowledge
    .use 270866
step
    .goto Wetlands,47.90,56.40
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to the |cRXP_FRIENDLY_Deathstalker Agent|r outside the portal
    .turnin 95682 >> Turn in Open the Maw
    .target Deathstalker Agent
step
    #completewith BorstanTurnin
    .zone Orgrimmar >> Back to Orgrimmar: hearth if your hearthstone is Orgrimmar - otherwise run back north to Hammerfall, fly to Undercity and take the zeppelin from Tirisfal
    .zoneskip Orgrimmar
step
    #label BorstanTurnin
    .goto Orgrimmar,57.20,53.32
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Borstan|r
    .turnin 95697 >> Turn in Changing Tastes
    .target Borstan
step
    #completewith next
    .goto Orgrimmar,45.12,63.89
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Doras|r
    .fly Thunder Bluff >> Fly to Thunder Bluff
    .target Doras
    .zoneskip Thunder Bluff
    .isOnQuest 95664
step
    .goto Thunder Bluff,71.06,34.19
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Bashana Runetotem|r on the Elder Rise
    .turnin 95664 >> Turn in Elder Knowledge
    .accept 98823 >> Accept Earthen Echo
    .target Bashana Runetotem
    .isOnQuest 95664
step
    .goto Mulgore,33.42,22.52
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Muln Earthfury|r at Skywatcher Plateau, just north of Thunder Bluff
    .turnin 98823 >> Turn in Earthen Echo
    .target Muln Earthfury
    .isOnQuest 98823
]==])
