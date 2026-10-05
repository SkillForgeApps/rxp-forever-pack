"""Finish the Forever Undead Paladin chain "A Lesson in Divinity" (ends with Redemption) in RXP's Undead guide.

Why (29 Sep 2026, Gaz on an Undead Paladin, level 15, 94435 complete since level 12): RXP's 6-12 Tirisfal route takes
parts 94427 -> 94434 and ACCEPTS 94435 at Tanis Alderwood in the Undercity (line ~3021), then heads for Silverpine and
never comes back: 94435 is never handed in and parts 94436-94441 are not in the guide at all. Chain (Wowhead Forever,
all level 12, Undead Paladin, added 1.60.1):
  94435 hand in to Danitha Morr, Bandarion Keep / Tyr's Watch (Tirisfal 22.0,44.6) -> 94436 speak with Deathguard
  Billmuth (22.0,44.4) -> 94438 use the Symbol of Life (6866) on Deathguard Falgan, Venomweb Vale (86.7,47.8 by Gaz's minimap standing next to him; the world-map pin 85.3,49.6 was wrong) ->
  94440 Scarlet Crusade Attack Plans (264693, Scarlet Friar 1538 / Scarlet Zealot 1537: camp just north of Falgan ~86.9,44.5 (Gaz, in game; not on Wowhead) and Crusader Outpost 76-81,53-57) back to Billmuth -> 94441 speak with
  Danitha Morr: learn Redemption.
Placement: the route's next pass through Tirisfal - "Exit Undercity" on the way to the zeppelin to Durotar, i.e. before
RFC, which is where Redemption is wanted. Every step is << Paladin and gated on its own quest (isOnQuest /
isQuestComplete), so it is skipped by anyone not on the chain. Inserted before the step carrying #label ZeptoDurotar.
ADDS 24 STEPS (14 paladin-only, 10 for every Undead - all gated) after that point. Idempotent; backs up the original next to this script. Re-run after
every RXP update (after fix_skull_rock_waypoint.py / undead_paladin_quests.py and the other Undead patches).
UNVERIFIED: objective indexes (1 each) and whether Falgan's resurrection is an item use or a gossip click.
"""
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"   # edit if your game is elsewhere
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
TAG = "#label DivinityKeep"
T = "|Tinterface/worldmap/chatbubble_64grey.blp:20|t"
NEW = [
    # v5 (Gaz 29 Sep: 'what about Deathguard Linnea's follow-on'): Rear Guard Patrol part 2 = 99156 (lvl 13 ELITE,
    # Riptear's Heart; Riptear npc 276020 roams east Tirisfal 78-83,41-55 by Venomweb Vale): accept at Linnea (paladins),
    # kill him after the Attack Plans, hand in at Linnea after the UC hearth + Raleigh. Rewards weak for a paladin
    # (2H axe / wand / +1 Agi cloak) - XP. v4 (Gaz 29 Sep, 'the HS cooldown is the only problem'): ONE hearth, at the end - the stone is unused all
    # chain, so it is ready; walk east from the keep via Brill (Sevren: 440 -> 441 Raleigh and the Undercity) and Linnea.
    # After the hearth: Raleigh Andrean, UC 62.4,43.5 (441, every Undead). v3 (Gaz 29 Sep): hearthstone stays in the Undercity - our RFC guide starts (Varimathras) and ends there and the
    # zeppelin tower is outside it; a Brill hearth saves nothing. After Billmuth: hearth to the Undercity, hand in Rear
    # Guard Patrol (Linnea, UC road) and The Engraved Ring (Sevren, Brill) on the way east - RXP never hands either in
    # (356 is accepted at line ~2045, 440 follows Rot Hide Clues); those two are for every Undead, gated on the quest.
    # 94438 is complete on accept (turning it in to Falgan IS the resurrection), so it has no objective step.
    # After Danitha: hearth to the Undercity again if the stone is ready - straight into the RFC prequests / zeppelin.
    "step << Paladin",
    "    " + TAG,
    "    .goto Tirisfal Glades,22.0,44.6",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Danitha Morr|r at Bandarion Keep (west Tirisfal)",
    "    >>|cRXP_WARN_Paladin class chain - it ends with|r |cRXP_WARN_[Redemption]|r",
    "    .turnin 94435 >>Turn in A Lesson in Divinity",
    "    .accept 94436 >>Accept A Lesson in Divinity",
    "    .target Danitha Morr",
    "    .isOnQuest 94435",
    "step << Paladin",
    "    .goto Tirisfal Glades,22.0,44.4",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Deathguard Billmuth|r (downstairs)",
    "    .turnin 94436 >>Turn in A Lesson in Divinity",
    "    .accept 94438 >>Accept A Lesson in Divinity",
    "    .target Deathguard Billmuth",
    "    .isOnQuest 94436",
    "step << Undead",
    "    #label DivinitySevren",
    "    .goto 1420/0,265.15,2305.94",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Magistrate Sevren|r in Brill (on your way east from the keep)",
    "    .turnin 440 >>Turn in The Engraved Ring",
    "    .accept 441 >>Accept Raleigh and the Undercity",
    "    .accept 408 >>Accept The Family Crypt << Paladin",
    "    .target Magistrate Sevren",
    "    .isOnQuest 440",
    "step << Undead",
    "    .goto 1420/0,74.00,2022.47",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Deathguard Linnea|r just south of Brill, on the road to the Undercity",
    "    .turnin 356 >>Turn in Rear Guard Patrol",
    "    .accept 99156 >>Accept Rear Guard Patrol << Paladin",
    "    .target Deathguard Linnea",
    "    .isQuestComplete 356",
    "step << Paladin",
    "    .goto Tirisfal Glades,76.8,54.2,15,0",   # round the hill at Crusader Outpost (Gaz's spyglass spot, 29 Sep)
    "    .goto Tirisfal Glades,80.9,54.5,15,0",   # second turn, clear run to Falgan (Gaz's spyglass, 29 Sep 20:02)
    "    .goto Tirisfal Glades,86.7,47.8",   # beside Falgan - Gaz's minimap readout 29 Sep 20:07 (Wowhead 86.5,47.6)
    "    >>Travel east to |cRXP_FRIENDLY_Venomweb Vale|r. " + T + "Talk to |cRXP_FRIENDLY_Deathguard Falgan|r - handing in raises him with the |cRXP_LOOT_Symbol of Life|r",
    "    >>|cRXP_WARN_Lost the Symbol? Danitha Morr gives you a new one|r",
    "    .turnin 94438 >>Resurrect Falgan",
    "    .accept 94440 >>Accept A Lesson in Divinity",
    "    .target Deathguard Falgan",
    "    .isOnQuest 94438",
    "step << Paladin",
    "    #loop",
    "    .goto Tirisfal Glades,86.9,44.5,0",
    "    .goto Tirisfal Glades,86.5,44.1,12,0",
    "    .goto Tirisfal Glades,87.3,44.1,12,0",
    "    .goto Tirisfal Glades,87.3,44.9,12,0",
    "    .goto Tirisfal Glades,86.5,44.9,12,0",
    "    >>Kill |cRXP_ENEMY_Scarlet Friars|r and |cRXP_ENEMY_Scarlet Zealots|r at the Scarlet camp just north of Falgan. Loot them for the |cRXP_LOOT_Scarlet Crusade Attack Plans|r",
    "    >>|cRXP_WARN_They are also at the Crusader Outpost south of the hill, on your way back west|r",
    "    .complete 94440,1",
    "    .mob Scarlet Friar",
    "    .mob Scarlet Zealot",
    "    .isOnQuest 94440",
    "step << Paladin",
    "    #loop",
    "    .goto Tirisfal Glades,80.5,44.5,0",
    "    .goto Tirisfal Glades,78.8,47.0,40,0",
    "    .goto Tirisfal Glades,81.2,42.8,40,0",
    "    .goto Tirisfal Glades,82.4,45.4,40,0",
    "    .goto Tirisfal Glades,80.6,55.2,40,0",
    "    >>Kill |cRXP_ENEMY_Riptear|r (level 13 elite, roams near Venomweb Vale). Loot him for |cRXP_LOOT_Riptear's Heart|r",
    "    >>|cRXP_WARN_Miners: plenty of copper veins around Venomweb Vale and Crusader Outpost - mine them while your hearthstone cools down (the Find Minerals icon on the minimap shows them)|r",
    "    .complete 99156,1",
    "    .unitscan Riptear",
    "    .isOnQuest 99156",
    # Gunther / lich chain, later part (add_lich_chain.py does the early part): on the way back west.
    "step << Paladin",
    "    .goto Tirisfal Glades,66.8,43.2",
    "    >>Swim out to |cRXP_FRIENDLY_Gunther's|r island in Brightwater Lake on your way west. " + T + "Talk to |cRXP_FRIENDLY_Gunther Arcanus|r",
    "    .turnin 366 >>Turn in Return the Book",
    "    .accept 409 >>Accept Proving Allegiance",
    "    .target Gunther Arcanus",
    "    .isOnQuest 366",
    "step << Paladin",
    "    .goto Tirisfal Glades,66.5,44.8",
    "    >>Take a |cRXP_LOOT_Candle of Beckoning|r from the crate on Gunther's island, then swim to the small island next to it",
    "    >>Kill the two guards, click the table and light the candle, then kill |cRXP_ENEMY_Lillith Nefara|r",
    "    >>|cRXP_WARN_She is level 12, arrives fast and hits hard - be at full health. Failed? Take another candle from the crate|r",
    "    .complete 409,1",
    "    .mob Lillith Nefara",
    "    .isOnQuest 409",
    "step << Paladin",
    "    .goto Tirisfal Glades,66.8,43.2",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Gunther Arcanus|r",
    "    .turnin 409 >>Turn in Proving Allegiance",
    "    .accept 411 >>Accept The Prodigal Lich Returns",
    "    .target Gunther Arcanus",
    "    .isQuestComplete 409",
    # The Family Crypt (408, lvl 13, not in RXP at all; Gaz 29 Sep: "add the family crypt to the loop") - Agamand crypt
    # entrance ~51,27, 3 floors down; Ancestors 50.4-52.2,26-31.6; Captain Dargol (npc 1658) bottom floor 52.4,26.5.
    "step << Paladin",
    "    #completewith DivinityCrypt",
    "    .goto Tirisfal Glades,51.0,27.5,20 >>Head north-west to the |cRXP_FRIENDLY_Agamand Family Crypt|r (north of Agamand Mills) and go in",
    "    .isOnQuest 408",
    "step << Paladin",
    "    #label DivinityCrypt",
    "    #loop",
    "    .goto Tirisfal Glades,51.2,29.6,0",
    "    .goto Tirisfal Glades,50.6,29.4,15,0",
    "    .goto Tirisfal Glades,51.2,28.0,15,0",
    "    .goto Tirisfal Glades,52.0,28.6,15,0",
    "    .goto Tirisfal Glades,51.8,30.5,15,0",
    "    .goto Tirisfal Glades,51.3,31.5,15,0",
    "    >>Kill |cRXP_ENEMY_Wailing Ancestors|r and |cRXP_ENEMY_Rotting Ancestors|r in the crypt",
    "    .complete 408,1",
    "    .complete 408,2",
    "    .mob Wailing Ancestor",
    "    .mob Rotting Ancestor",
    "    .isOnQuest 408",
    "step << Paladin",
    "    .goto Tirisfal Glades,52.4,26.5",
    "    >>Go down to the |cRXP_WARN_bottom floor|r of the crypt. Kill |cRXP_ENEMY_Captain Dargol|r and loot his |cRXP_LOOT_Skull|r",
    "    .complete 408,3",
    "    .mob Captain Dargol",
    "    .isOnQuest 408",
    "step << Paladin",
    "    .goto Tirisfal Glades,22.0,44.4",
    "    >>Travel back west to Bandarion Keep. " + T + "Talk to |cRXP_FRIENDLY_Deathguard Billmuth|r (downstairs)",
    "    .turnin 94440 >>Turn in A Lesson in Divinity",
    "    .accept 94441 >>Accept A Lesson in Divinity",
    "    .target Deathguard Billmuth",
    "    .isQuestComplete 94440",
    "step << Paladin",
    "    .goto Tirisfal Glades,22.0,44.6",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Danitha Morr|r in the keep",
    "    .turnin 94441 >>Turn in A Lesson in Divinity",
    "    .target Danitha Morr",
    "    .isOnQuest 94441",
    "step << Paladin",
    "    .hs >> Hearth to the Undercity - RFC prequests (Varimathras) and the zeppelin start there",
    "    .use 6948",
    "    .bindlocation 1497,1",
    "    .cooldown item,6948,>0",
    "    .isQuestTurnedIn 94441",
    "step << Undead",
    "    .goto Undercity,62.4,43.5",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Raleigh Andrean|r in the Undercity",
    "    .turnin 441 >>Turn in Raleigh and the Undercity",
    "    .target Raleigh Andrean",
    "    .isOnQuest 441",
    "step << Undead",
    "    .goto 1458/0,66.74,1766.18",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Bethor|r in the Magic Quarter",
    "    .turnin 411 >>Turn in The Prodigal Lich Returns",
    "    .target Bethor Iceshard",
    "    .isQuestComplete 411",
    # Easy dungeon-prequest pickups while here (Gaz 29 Sep): Varimathras (RFC 5725, Royal Quarter) and Deathguard
    # Kristof (Ruins of Lordaeron 92422, beside Linnea). Waypoint chains are the ones in our RFC guide (RXP's own).
    "step << Undead",
    "    #completewith next",
    "    .goto 1458,64.42,64.62,20,0",
    "    .goto 1458,51.88,64.84,20,0",
    "    .goto 1458,46.28,73.10,15,0",
    "    .goto 1458,45.31,78.24,15,0",
    "    .goto 1458,46.18,83.63,15,0",
    "    .goto 1458,48.80,87.63,15,0",
    "    .goto 1458,52.45,89.49,15,0",
    "    .goto 1458,56.4,92.4,12 >>Travel to the Royal Quarter",
    "    .zoneskip Undercity,1",
    "    .isQuestAvailable 5725",
    "    .isNotOnQuest 5725",
    "step << Undead",
    "    .goto 1458,56.4,92.4",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Varimathras|r beside Sylvanas",
    "    >>|cRXP_WARN_Ragefire Chasm prequest - done later with our RFC guide|r",
    "    .accept 5725 >>Accept The Power to Destroy...",
    "    .target Varimathras",
    "    .zoneskip Undercity,1",
    "    .isQuestAvailable 5725",
    "    .isNotOnQuest 5725",
    "step << Undead",
    "    #completewith DivinityLinnea2",
    "    .goto 1458,52.45,89.49,15,0",
    "    .goto 1458,48.80,87.63,15,0",
    "    .goto 1458,46.18,83.63,15,0",
    "    .goto 1458,45.31,78.24,15,0",
    "    .goto 1458,46.28,73.10,15,0",
    "    .goto 1458,51.88,64.84,20,0",
    "    .goto 1458,64.42,64.62,20,0",
    "    .goto 1458,65.50,56.75,20,0",
    "    .goto 1420/0,235.32,1883.89",
    "    .zone Tirisfal Glades >> Exit Undercity by the elevators",
    "    .zoneskip Undercity,1",
    "step << Undead",
    "    #label DivinityLinnea2",
    "    .goto 1420/0,74.00,2022.47",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Deathguard Linnea|r just outside the Undercity",
    "    .turnin 99156 >>Turn in Rear Guard Patrol",
    "    .target Deathguard Linnea",
    "    .isQuestComplete 99156",
    "step << Undead",
    "    .goto 1420,65.2,60.2",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Deathguard Kristof|r beside Linnea",
    "    >>|cRXP_WARN_Ruins of Lordaeron starter - done later with our RoL guide|r",
    "    .accept 92422 >>Accept The Wrath of Rath'mael",
    "    .target Deathguard Kristof",
    "    .xp <15,1",
    "    .isQuestAvailable 92422",
    "    .isNotOnQuest 92422",
    "step << Undead",
    "    .goto 1420/0,265.15,2305.94",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Magistrate Sevren|r in Brill, just north of the zeppelin tower",
    "    >>|cRXP_WARN_Reward: take Bonecracker (2H mace) - sell it if your weapon is better|r",
    "    .turnin 408 >>Turn in The Family Crypt",
    "    .target Magistrate Sevren",
    "    .isQuestComplete 408",
]

path = os.path.join(ADDONS, "RXPGuides", "Guides", "forever", "Horde-01-14_Undead.lua")
src = open(path, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
lines = src.split(nl)
if TAG in src:
    print("Horde-01-14_Undead.lua: nothing to patch (already patched?)")
    raise SystemExit
anchors = [i for i in range(1, len(lines)) if lines[i].strip() == "#label ZeptoDurotar" and lines[i - 1].startswith("step")]
if len(anchors) != 1:
    raise SystemExit("expected 1 '#label ZeptoDurotar' step, found %d - RXP changed the file, redo by hand" % len(anchors))
i = anchors[0] - 1
lines[i:i] = NEW
backup = os.path.join(HERE, "Horde-01-14_Undead.BEFORE-divinity.lua")
if not os.path.exists(backup):
    shutil.copy2(path, backup)
open(path, "w", encoding="utf-8", newline="").write(nl.join(lines))
print("Horde-01-14_Undead.lua: A Lesson in Divinity (94435-94441) added before the zeppelin to Durotar; backup %s" % backup)
