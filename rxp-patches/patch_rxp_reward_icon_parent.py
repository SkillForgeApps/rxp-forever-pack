"""Stop RestedXP creating frames inside the quest reward window (gamepad UI taint).

Why (26 Sep 2026, taint.log at level 11 - Gaz ran /console taintLog 11): the first RXPGuides taint in any gamepad
code that session was
    Tainted value written to field mainGroup (...) by RXPGuides - Blizzard_GamepadSmartNavigation/Utility.lua:264
      SmartNavigation:RefreshButtonGroups() <- SmartNavigation.lua:206 <- CreateFrame()
      <- RXPGuides.lua:724 showRewardChoiceIcon() <- handleQuestComplete()
Blizzard's gamepad SmartNavigation does hooksecurefunc("CreateFrame", ...) and refreshes the navigation groups of any
open window the new frame's parent sits in. RXP's quest-reward recommendation (the gold coin / best-value icon)
created its overlay frame with the reward button as parent, so the refresh ran in RXP's tainted code and the
navigation tables stayed tainted until /reload. Every later window close with the controller then failed with
"[ADDON_ACTION_FORBIDDEN] AddOn 'RXPGuides' tried to call the protected function 'SetPreferredGamepadInteractTarget()'".
Patch: the overlay is parented to UIParent and anchored over the reward button (same strata, one level higher), and
hides itself when the button is no longer visible. The icon looks and behaves the same. Idempotent; backs up the
original next to this script. Re-run after every RXP update. Revert: copy the backup over RXPGuides.lua.
"""
import os
import shutil
import sys

RXP = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides"
HERE = os.path.dirname(os.path.abspath(__file__))
MARK = "-- RXPForever: overlay parented to UIParent"

path = os.path.join(RXP, "RXPGuides.lua")
src = open(path, encoding="utf-8", newline="").read()
if MARK in src:
    sys.exit("RXPGuides.lua: already patched")
nl = "\r\n" if "\r\n" in src else "\n"

OLD = nl.join([
    "    if not overlay then",
    "        overlay = _G.CreateFrame(\"Frame\", nil, rewardButton)",
    "",
    "        icon.overlay = overlay",
    "    else",
    "        overlay:SetParent(rewardButton)",
    "    end",
    "",
    "    overlay:SetFrameLevel(rewardButton:GetFrameLevel() + 1)",
])
NEW = nl.join([
    "    if not overlay then",
    "        " + MARK + ", not the reward button: Blizzard's gamepad SmartNavigation hooks CreateFrame and",
    "        -- refreshes the open window's navigation from addon code, which taints the gamepad UI until /reload",
    "        overlay = _G.CreateFrame(\"Frame\", nil, _G.UIParent)",
    "        overlay:SetScript(\"OnUpdate\", function(self)",
    "            local b = self.rxpRewardButton",
    "            if not (b and b:IsVisible()) then self:Hide() end",
    "        end)",
    "",
    "        icon.overlay = overlay",
    "    end",
    "    overlay.rxpRewardButton = rewardButton",
    "    overlay:ClearAllPoints()",
    "    overlay:SetAllPoints(rewardButton)",
    "    overlay:SetFrameStrata(rewardButton:GetFrameStrata())",
    "",
    "    overlay:SetFrameLevel(rewardButton:GetFrameLevel() + 1)",
])
assert src.count(OLD) == 1, "showRewardChoiceIcon block not found once (RXP changed?) - check before patching"
backup = os.path.join(HERE, "orig-RXPGuides-before-rewardicon.lua")
if not os.path.exists(backup):
    shutil.copy2(path, backup)
open(path, "w", encoding="utf-8", newline="").write(src.replace(OLD, NEW))
print("RXPGuides.lua: reward-choice overlay now parented to UIParent; backup %s" % backup)
