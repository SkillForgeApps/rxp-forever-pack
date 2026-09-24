"""Stop RestedXP force-closing the quest / merchant windows from addon code.

Why (23 Sep 2026, BugGrabber): on Forever's modern client the UI panel manager is protected. RXP's quest
automation calls HideUIPanel(QuestFrame) right after AcceptQuest()/CompleteQuest() (RXPGuides.lua ~1154-1174)
and HideUIPanel(MerchantFrame) after auto-vendoring (functions.lua ~5599). Hiding a panel from insecure code
taints the panel manager; the next time any panel closes, the gamepad binding stack runs tainted and
Blizzard_GamepadActionBars' SetPreferredGamepadInteractTarget() is blocked
("[ADDON_ACTION_FORBIDDEN] AddOn 'RXPGuides' tried to call the protected function
'SetPreferredGamepadInteractTarget()'"), breaking the controller's interact prompt until /reload.
The windows close by themselves when the server confirms the accept / turn-in / sale, so the calls are
commented out. Idempotent; backs up the originals next to this script. Re-run after every RXP update.
Revert: copy the backups back over the installed files."""
import os, shutil, sys

RXP = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides"
HERE = os.path.dirname(os.path.abspath(__file__))
TAG = "-- RXPForever: removed insecure HideUIPanel (taints the panel manager -> gamepad interact blocked)"

targets = {
    "RXPGuides.lua": "HideUIPanel(_G.QuestFrame)",
    "functions.lua": "HideUIPanel(_G.MerchantFrame)",
}
total = 0
for name, call in targets.items():
    path = os.path.join(RXP, name)
    src = open(path, encoding="utf-8").read()
    lines = src.split("\n")
    n = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == call:
            indent = line[: len(line) - len(line.lstrip())]
            lines[i] = indent + "-- " + call + "  " + TAG
            n += 1
    if n == 0:
        print("%s: nothing to patch (already patched?)" % name)
        continue
    backup = os.path.join(HERE, "orig-" + name.replace(".lua", "") + "-before-nohide.lua")
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("%s: commented out %d call(s); backup %s" % (name, n, backup))
    total += n
print("done, %d call(s) patched" % total)
