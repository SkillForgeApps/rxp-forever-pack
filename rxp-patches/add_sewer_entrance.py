"""Point the "Travel into the Undercity through the sewers" step at the sewer entrance first.

25 Sep 2026, Gaz: "waypoint mark the way to the undercity sewers". In RXP's forever/Horde-01-14_Undead.lua that step's
waypoint chain starts INSIDE the sewers (1458/0,714.8,1604.24), so from outside the arrow points at an underground
spot and never shows the way in. RXP's own "Leave Undercity through the Sewers" chains in the same guide end at the
sewer mouth outside in Tirisfal: 1420/0,724.25,1682.66. This adds that point as the FIRST goto of the way-in chain
(radius 30, hidden-intermediate like the rest), so the arrow leads to the entrance and then down the tunnel.
Run once: python add_sewer_entrance.py
"""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Horde-01-14_Undead.lua"
MARK = "-- [RXPForever] sewer entrance"
MOUTH = "1420/0,724.25,1682.66"   # outside end of RXP's own "Leave Undercity through the Sewers" chains

text = open(G, encoding="utf-8", newline="").read()
if MARK in text:
    sys.exit("already patched")
assert MOUTH in text, "the sewer-mouth point is no longer in RXP's exit chains - check before patching"
nl = "\r\n" if "\r\n" in text else "\n"
L = text.split(nl)

z = [i for i, l in enumerate(L) if l.strip() == ".zone Undercity >> Travel into the Undercity through the sewers"]
assert len(z) == 1, "way-in step not found once (%d)" % len(z)
s = z[0]
while not L[s].lstrip().startswith("step"):
    s -= 1
first = next(i for i in range(s, z[0]) if L[i].lstrip().startswith(".goto"))
L[first:first] = ["    .goto " + MOUTH + ",30,0   " + MARK + " (outside end of RXP's own sewer exit chain)"]
open(G, "w", encoding="utf-8", newline="").write(nl.join(L))
print("sewer entrance added as the first waypoint of the way-in chain (line %d)" % (first + 1))
