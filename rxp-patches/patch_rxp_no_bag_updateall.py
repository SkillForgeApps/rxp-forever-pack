"""Stop RestedXP re-running Blizzard's whole bag update from addon code.

Why (27 Sep 2026, desktop BugGrabber, Gaz: "lua crashes when i open my bag and it then stops the gamepad ui taking
input and forces me to restart the ui"): "[ADDON_ACTION_BLOCKED] AddOn 'RXPGuides' tried to call the protected
function 'SetOverrideBindingClick()'" with RXP in the stack for once:
    RXPGuides/InventoryManager.lua:660 BagHandler (OnUpdate) -> :621 UpdateAllBags -> :608 DetectBagMods
    -> ContainerFrame_UpdateAll -> ContainerFrame Update -> PromptedBindingFooter Refresh -> DeactivateBindingGroup
    -> InputBindingManager RemoveSet -> SetOverrideBindingClick (blocked)
plus the familiar "'RXPGuides' tried to call SetPreferredGamepadInteractTarget()" when the bag closes (CloseAllBags ->
SmartNavigation -> DeactivateBindingGroup). RXP's junk-coin feature hooks ToggleAllBags / ToggleBag and
BAG_UPDATE_DELAYED / BAG_CONTAINER_UPDATE, waits 0.33 s, and with Blizzard's own bags (no bag mod) calls
ContainerFrame_UpdateAll() - so every bag open and every bag change rebuilt all bag frames, their gamepad footer and
navigation bindings, in RXP's tainted execution. The gamepad binding stack then refuses protected calls until /reload.
Patch: replace that call with a direct redraw of the gold junk coins on the open bags (see v2 note below), then
return true as before. Idempotent; upgrades a v1-patched file; backs up the original next to this script. Re-run after every RXP
update. Revert: copy the backup over the installed InventoryManager.lua.
"""
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"   # edit if your game is elsewhere
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
# v1 (27 Sep 22:13) only dropped the call. Gaz 22:40: the gold junk coins stopped showing - Blizzard's UpdateJunkItem
# (ContainerFrame.lua:1898) hides JunkIcon unless a vendor is open, and the dropped call was what re-ran RXP's
# UpdateItems hook after each bag change. v2 redraws the coins directly: JunkIcon:SetShown on the open bags' item
# buttons (the same thing RXP's UpdateItems hook does), no Blizzard bag code run from addon code.
TAG_V1 = "-- RXPForever: no ContainerFrame_UpdateAll() from addon code (taints the gamepad bag bindings); UpdateItems hook sets the icons"
TAG = "-- RXPForever v2: no ContainerFrame_UpdateAll() from addon code (taints the gamepad bag bindings); redraw the coins directly"
BLOCK = [
    TAG,
    "for n = 0, NUM_CONTAINER_FRAMES or 13 do",
    "    local bf = n == 0 and _G.ContainerFrameCombinedBags or _G[\"ContainerFrame\" .. n]",
    "    if bf and bf:IsShown() then",
    "        for _, b in pairs({bf:GetChildren()}) do",
    "            if b.JunkIcon and b.GetBagID and b.GetID then",
    "                local bag, slot = b:GetBagID(), b:GetID()",
    "                if bag and slot and slot >= 0 then",
    "                    local id = GetContainerItemID(bag, slot)",
    "                    b.JunkIcon:SetShown((inventoryManager.IsJunkIconEnabled() and id and IsJunk(id)) and true or false)",
    "                end",
    "            end",
    "        end",
    "    end",
    "end",
]

path = os.path.join(ADDONS, "RXPGuides", "InventoryManager.lua")
src = open(path, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
lines = src.split(nl)
done = 0
for i in range(1, len(lines) - 1):
    if lines[i].strip() in ("_G.ContainerFrame_UpdateAll()", TAG_V1) \
            and lines[i - 1].strip() == "elseif _G.ContainerFrame_UpdateAll then" and lines[i + 1].strip() == "return true":
        indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
        lines[i:i + 1] = [indent + l for l in BLOCK]
        done += 1
        break
if not done:
    print("InventoryManager.lua: nothing to patch (already patched?)")
else:
    backup = os.path.join(HERE, "orig-InventoryManager-before-noupdateall.lua")
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    open(path, "w", encoding="utf-8", newline="").write(nl.join(lines))
    print("InventoryManager.lua: patched; backup %s" % backup)
