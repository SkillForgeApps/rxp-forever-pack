"""Don't block the Barrens guide on buying 20 Longjaw Mud Snappers from Innkeeper Wiley (Ratchet).

Why (29 Sep 2026, Gaz on a Tauren Warrior, 12-17 The Barrens step 73: "there are no Longjaw Mud Snappers at
Wiley"): both Wiley steps (12-17 and 17-22 route) carry `.collect 4592,20,<quest>,1`, which only completes with 20
snappers in the bags. Wowhead Forever still lists them in Wiley's shop (possibly Classic data), but in game he had
none - the step could never complete. The snappers are only a food suggestion, so the .collect line goes and the text
says "if he has them"; the step still completes on its .vendor (sell your junk to him). Casters' Melon Juice line is
left alone. Idempotent; backs up the original next to this script. Re-run after every RXP update.
"""
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"   # edit if your game is elsewhere
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(ADDONS, "RXPGuides", "Guides", "forever", "Horde-12-22_Barrens.lua")
src = open(path, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
lines = src.split(nl)
TAG = "-- [RXPForever] Longjaw Mud Snapper collect removed (Wiley had none on Forever)"
out, n = [], 0
for l in lines:
    if re.match(r"\s*\.collect 4592,20,\d+,1", l):
        out.append(l[: len(l) - len(l.lstrip())] + TAG)
        n += 1
        continue
    if "[Longjaw Mud Snappers]" in l and "extremely cheap" in l:
        l = l.replace("are extremely cheap, buy as many as you want", "are cheap food - buy some if he has them")
    out.append(l)
if not n:
    print("Horde-12-22_Barrens.lua: nothing to patch (already patched?)")
else:
    backup = os.path.join(HERE, "Horde-12-22_Barrens.BEFORE-mudsnapper.lua")
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    open(path, "w", encoding="utf-8", newline="").write(nl.join(out))
    print("Horde-12-22_Barrens.lua: %d Mud Snapper collect(s) removed; backup %s" % (n, backup))
