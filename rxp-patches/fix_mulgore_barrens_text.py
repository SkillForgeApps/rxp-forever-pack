"""Clearer wording for the Mulgore guides' "Travel to The Barrens" step (text only - no step numbers move).

Why (28 Sep 2026, Gaz on a Tauren Warrior, 06-12 Mulgore: "step 85 travel to the barrens, yet step 86 talk to omusa
get the camp taurajo flight path? is this right?"): the order IS right - Camp Taurajo is in The Barrens but sits just
over Mulgore's eastern border, so the step only means "run east to Camp Taurajo" (it is #completewith the Camp Taurajo
flight path step). The text read like a trip across the zone. No Thunder Bluff flight path step is needed: Tauren start
knowing it (RXP's own druid step flies there straight after Camp Taurajo). Applies to both Mulgore routes in the file
(6-12 Mulgore and 7-13 Mulgore). Idempotent; backs up the original next to this script. Re-run after every RXP update.
"""
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"   # edit if your game is elsewhere
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = ".zone The Barrens >> Travel to The Barrens"
NEW = (".zone The Barrens >> Head east out of Mulgore to |cRXP_FRIENDLY_Camp Taurajo|r - "
       "it is just over the border into The Barrens")

path = os.path.join(ADDONS, "RXPGuides", "Guides", "forever", "Horde-1-12_Mulgore.lua")
src = open(path, encoding="utf-8", newline="").read()
count = src.count(OLD)
if not count:
    print("Horde-1-12_Mulgore.lua: nothing to patch (already patched?)")
else:
    backup = os.path.join(HERE, "Horde-1-12_Mulgore.BEFORE-barrenstext.lua")
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    open(path, "w", encoding="utf-8", newline="").write(src.replace(OLD, NEW))
    print("Horde-1-12_Mulgore.lua: %d step(s) reworded; backup %s" % (count, backup))
