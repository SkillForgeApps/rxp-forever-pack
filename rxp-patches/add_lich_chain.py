"""Restore the start of the Gunther / lich chain in RXP's Undead guide while it still gives XP (every Undead).

Why (29 Sep 2026, Gaz on an Undead Paladin: "check why the whole lich book, Proving Allegiance, Prodigal Lich Returns
chain was missed out"; then "a good place for the first one is before the instruction to die on the small island ...
whilst it's still XP viable, then leave the later ones for the runs between east and west"). RXP cut the chain:
405 The Prodigal Lich is accepted by everyone (Sevren, Brill) but only Warlocks/Mages hand it in to Bethor Iceshard,
the 357 The Lich's Identity accept is commented out there, the "loot Gunther's Books" step on the island is `<< skip`,
Return the Book 366 only appears in `<< skip` steps and 409 Proving Allegiance is missing. Chain (Wowhead Forever):
405 (lvl 8) Sevren's Orders to Bethor -> 357 (lvl 8) the Lich's Spellbook from Gunther's island back to Bethor ->
366 (lvl 8) return Gunther's book to him -> 409 (lvl 12) Candle of Beckoning, Lillith Nefara -> 411 (lvl 12) Nether
Gem to Bethor (Bone Buckler).
This script (early part, every Undead):
  1. the Warlock-only Bethor step in the all-class Undercity visit (~line 2315) becomes << Undead and accepts 357;
     the Mage copy (~2524) gets its 357 accept back too (it self-completes if already taken);
  2. the island "loot Gunther's Books" step (~2722, right before "Die ON THE SMALLER ISLAND") is switched on;
  3. a Bethor step after the Tanis Alderwood step (next Undercity visit, ~3026) hands in 357 and gives 366 to
     PALADINS only - the rest of the chain rides the paladin's east-west Tirisfal runs (add_lesson_in_divinity.py).
Every step is gated on the quest, so characters who skipped part of it are not blocked. Run AFTER
add_lesson_in_divinity.py. Idempotent; backs up the original next to this script. Re-run after every RXP update.
"""
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"   # edit if your game is elsewhere
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
TAG = "-- [RXPForever] lich chain"
T = "|Tinterface/worldmap/chatbubble_64grey.blp:20|t"

path = os.path.join(ADDONS, "RXPGuides", "Guides", "forever", "Horde-01-14_Undead.lua")
src = open(path, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
L = src.split(nl)
if TAG in src:
    print("Horde-01-14_Undead.lua: nothing to patch (already patched?)")
    raise SystemExit


def step_start(i):
    while not L[i].startswith("step"):
        i -= 1
    return i


# 1. Bethor steps that hand in 405 with the 357 accept commented out
bethor = [i for i, l in enumerate(L) if l.strip() == "--.accept 357 >>Accept The Lich's Identity"]
if len(bethor) != 2:
    raise SystemExit("expected 2 commented 357 accepts (Warlock + Mage Bethor steps), found %d" % len(bethor))
for i in bethor:
    L[i] = L[i].replace("--.accept 357", ".accept 357") + "  " + TAG
first = step_start(bethor[0])
if L[first].strip() != "step << Warlock":
    raise SystemExit("first Bethor step is not 'step << Warlock' (%r)" % L[first])
L[first] = "step << Undead  " + TAG + " (was << Warlock: everyone hands in The Prodigal Lich here)"
L.insert(first + 1, "    .isOnQuest 405")

# 2. switch on the island book loot step
loot = [i for i, l in enumerate(L) if l.strip() == ".complete 357,1 --The Lich's Spellbook (1)"]
if len(loot) != 1:
    raise SystemExit("expected 1 'loot Gunther's Books' step, found %d" % len(loot))
s = step_start(loot[0])
if L[s].strip() != "step << skip":
    raise SystemExit("the book loot step is not 'step << skip' (%r)" % L[s])
L[s] = "step << Undead  " + TAG + " (was << skip)"
L.insert(loot[0] + 1, "    .isOnQuest 357")

# 3. Bethor after the Tanis Alderwood step: hand in 357, Return the Book for paladins
tanis = [i for i, l in enumerate(L) if l.strip() == ".accept 94435 >>Accept A Lesson in Divinity"]
if len(tanis) != 1:
    raise SystemExit("expected 1 Tanis Alderwood step (.accept 94435), found %d" % len(tanis))
j = tanis[0] + 1
while not L[j].startswith("step"):
    j += 1
L[j:j] = [
    "step << Undead",
    "    .goto 1458/0,66.74,1766.18",
    "    >>" + T + "Talk to |cRXP_FRIENDLY_Bethor|r in the Magic Quarter  " + TAG,
    "    .turnin 357 >>Turn in The Lich's Identity",
    "    .accept 366 >>Accept Return the Book << Paladin",
    "    .target Bethor Iceshard",
    "    .isQuestComplete 357",
]

backup = os.path.join(HERE, "Horde-01-14_Undead.BEFORE-lich.lua")
if not os.path.exists(backup):
    shutil.copy2(path, backup)
open(path, "w", encoding="utf-8", newline="").write(nl.join(L))
print("Horde-01-14_Undead.lua: lich chain start restored (Bethor x2, island book, Bethor hand-in); backup %s" % backup)
