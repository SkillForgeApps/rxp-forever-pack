"""Raise Cooking and Mining in RXP's forever/Horde-01-14_Undead.lua (6-12 guide), the way the Dun Morogh guide does
in Coldridge. 25 Sep 2026, Gaz: "raise cooking and mining should be in the guide in the same way it was in coldridge".
Run AFTER add_camping101_undead.py: inserted right after each "Camping 101 Cooking hand-in" step it added.
Dun Morogh pattern (RXP's own forever/Alliance-1-14_DwarfGnome.lua): optional "loot the meat as you pass" steps gated
on cooking skill (`.skill cooking,50,1` = only while under 50), and a Find Minerals prompt after training Mining.
Tirisfal data (Wowhead Forever 25 Sep): Stringy Wolf Meat 2672 drops from Decrepit Darkhound (lvl 5-6, 56%), Cursed
Darkhound (7-8, 65%), Ravenous Darkhound (9-10, 77%), Worg (10-11, 77%); darkhounds spawn all over Tirisfal (200+
each), so no fixed route - loot the ones you pass. Recipe: Charred Wolf Meat (item 2679).
Steps added (all #optional #sticky, so they stay on screen while you quest):
  1. Mining to 20 - only while on Camping 101: Mining (97959)
  2. collect 20 Stringy Wolf Meat - only while Cooking < 50
  3. cook Charred Wolf Meat to Cooking 50 - only while Cooking < 50
Run once: python add_cooking_mining_undead.py
"""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Horde-01-14_Undead.lua"
MARK = "-- [RXPForever] raise Cooking/Mining"
ANCHOR = "-- [RXPForever] Camping 101 Cooking hand-in = learning Cooking here"

text = open(G, encoding="utf-8", newline="").read()
if MARK in text:
    sys.exit("already patched")
assert ANCHOR in text, "run add_camping101_undead.py first"
nl = "\r\n" if "\r\n" in text else "\n"
L = text.split(nl)

BLOCK = [
    "step",
    "    #optional",
    "    #sticky",
    "    >>Cast |T136025:0|t[Find Minerals] and mine the |cRXP_PICK_Copper Veins|r you pass - Camping 101: Mining needs"
    " |T134708:0|t[Mining] 20",
    "    .skill mining,20 >>Raise |T134708:0|t[Mining] to 20",
    "    .isOnQuest 97959",
    "    " + MARK + " (Mining, Coldridge pattern)",
    "step",
    "    #optional",
    "    #sticky",
    "    >>Kill the |cRXP_ENEMY_Darkhounds|r and |cRXP_ENEMY_Worgs|r you pass. Loot them for |T133970:0|t|cRXP_LOOT_[Stringy Wolf Meat]|r"
    " to level your |T133971:0|t[Cooking]",
    "    >>|cRXP_WARN_Don't go out of your way to farm this now. Simply kill and loot the ones you're passing by|r",
    "    .collect 2672,20 --Stringy Wolf Meat (20)",
    "    .mob Decrepit Darkhound",
    "    .mob Cursed Darkhound",
    "    .mob Ravenous Darkhound",
    "    .mob Worg",
    "    .skill cooking,50,1 --XX Shows if cooking skill is <50",
    "    " + MARK + " (Cooking meat, Wowhead Forever drop data)",
    "step",
    "    #optional",
    "    #sticky",
    "    >>Cook |T133974:0|t[Charred Wolf Meat] at a campfire (the Brill inn fire, Eleanor's camp, or your own"
    " |T135805:0|t[Basic Campfire]) until |T133971:0|t[Cooking] 50",
    "    .skill cooking,50 >>Raise |T133971:0|t[Cooking] to 50",
    "    " + MARK + " (Cooking to 50, as Coldridge)",
]

hits = [i for i, l in enumerate(L) if l.strip() == ANCHOR]
assert len(hits) == 2, "expected 2 Cooking hand-in steps, found %d" % len(hits)
for i in reversed(hits):
    j = i + 1
    while j < len(L) and not L[j].lstrip().startswith("step"):
        j += 1
    L[j:j] = BLOCK

open(G, "w", encoding="utf-8", newline="").write(nl.join(L))
print("added the Cooking/Mining steps after both Cooking hand-in steps (%d lines each)" % len(BLOCK))
