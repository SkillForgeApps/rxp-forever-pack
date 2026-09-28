"""Give RXP's Undead "Hidden Enemies" Skull Rock step an arrow.

28 Sep 2026, a Tauren warrior (RFC dungeon quests guide): "missing waypoint to Skull Rock". RXP's own
forever/Horde-01-14_Undead.lua step `<< Undead` for 5726 (Lieutenant's Insignia) has ONE point written
`.goto 1411/1,-4769.10,1484.39,0`. In RXP's parser (functions.lua goto: radius == 0 without the optional 5th field)
that sets element.arrow = nil - the step never shows an arrow. RXPForever's RFC guide had copied that line (fixed in
RXPForever.lua the same day). RXP's Barrens guide walks Skull Rock with nine `15,0` points; this swaps the lone point
for that route (radius 15, hidden-intermediate, the arrow leads through the camp).
Run once: python fix_skull_rock_waypoint.py   (backup Horde-01-14_Undead.BEFORE-skullrock.lua next to this script)
"""
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"   # edit if your game is elsewhere
import os
import shutil
import sys

G = os.path.join(ADDONS, r"RXPGuides\Guides\forever\Horde-01-14_Undead.lua")
HERE = os.path.dirname(os.path.abspath(__file__))
OLD = "    .goto 1411/1,-4769.10,1484.39,0"
ROUTE = ["-4855.82,1498.84", "-4833.08,1494.96", "-4805.59,1495.67", "-4784.44,1535.85", "-4750.60,1531.62",
         "-4734.21,1505.54", "-4693.49,1519.64", "-4679.75,1501.31", "-4684.50,1466.06"]   # RXP Barrens guide, 5726 step

text = open(G, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in text else "\n"
lines = text.split(nl)
hits = [i for i, l in enumerate(lines) if l.rstrip() == OLD]
if not hits:
    sys.exit("already patched (the lone Skull Rock point is gone)")
assert len(hits) == 1, "expected the Skull Rock point once, found %d" % len(hits)
backup = os.path.join(HERE, "Horde-01-14_Undead.BEFORE-skullrock.lua")
if not os.path.exists(backup):
    shutil.copy2(G, backup)
i = hits[0]
lines[i:i + 1] = ["    .goto 1411/1,%s,15,0" % p for p in ROUTE]
open(G, "w", encoding="utf-8", newline="").write(nl.join(lines))
print("Skull Rock route (9 points) in place of the arrowless point, line %d" % (i + 1))
