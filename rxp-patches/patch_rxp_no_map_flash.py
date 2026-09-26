"""Stop RestedXP flashing the world map open and shut from addon code.

Why (26 Sep 2026, BugGrabber + Gaz: "we are still getting [errors] on opening windows"): with the gamepad UI on,
closing bags / windows with the controller kept failing with "[ADDON_ACTION_FORBIDDEN] AddOn 'RXPGuides' tried
to call the protected function 'SetPreferredGamepadInteractTarget()'" (x8 on 26 Sep 10:59, stack all Blizzard:
CloseAllBags -> SmartNavigation -> DeactivateBindingGroup -> UpdateInteractIcons) - the 23 Sep HideUIPanel patch
was already in place. Remaining RXP source: map.lua addWorldMapLines() does
    if width == 0 or height == 0 then WorldMapFrame:Show() WorldMapFrame:Hide() end
to give the map canvas a size before drawing route lines. The canvas is 0x0 until the map has been opened once,
so this runs after every reload / guide load (UpdateMap(true)). Showing and hiding a gamepad-managed window from
addon code runs the gamepad FrameControlsManager tainted, and the taint sits in its state until /reload.
Patch: skip the lines while the canvas has no size (return). RXPForever redraws the lines once the map has been
opened (its "map lines after first open" block), so nothing is lost. Idempotent; backs up the original next to
this script. Re-run after every RXP update. Revert: copy the backup over the installed map.lua.
"""
import os
import shutil

RXP = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides"
HERE = os.path.dirname(os.path.abspath(__file__))
TAG = "-- RXPForever: no WorldMapFrame Show/Hide from addon code (taints the gamepad UI); lines drawn after the map opens"

path = os.path.join(RXP, "map.lua")
src = open(path, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
lines = src.split(nl)
done = 0
for i in range(len(lines) - 1):
    if lines[i].strip() == "WorldMapFrame:Show()" and lines[i + 1].strip() == "WorldMapFrame:Hide()" \
            and lines[i - 1].strip() == "if width == 0 or height == 0 then":
        indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
        lines[i:i + 2] = [indent + "return  " + TAG]
        done += 1
        break
if not done:
    print("map.lua: nothing to patch (already patched?)")
else:
    backup = os.path.join(HERE, "orig-map-before-noflash.lua")
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    open(path, "w", encoding="utf-8", newline="").write(nl.join(lines))
    print("map.lua: patched; backup %s" % backup)
