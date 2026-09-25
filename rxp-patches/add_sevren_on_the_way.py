"""Hand in "Return to the Magistrate" (360) to Magistrate Sevren on the way through Brill, before the Agamand Mills trip.

25 Sep 2026, Gaz: "step 112 wants me to travel north towards Agamand Mills but there's a quest hand in on the way,
return to the magistrate". RXP's forever/Horde-01-14_Undead.lua accepts 360 from Deathguard Linnea (on the road to
Undercity) and only hands it in at Sevren after the Mills, bundled with Speak with Sevren (355, from Coleman after
The Haunted Mills). Brill is on the way from Linnea to the Mills, so this adds one step right before #label
AgamandStart: talk to Sevren, turn in 360, gated `.isOnQuest 360`. RXP's later Sevren steps still turn in 355 (their
360 line completes itself because it's already turned in).
Run once: python add_sevren_on_the_way.py
"""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Horde-01-14_Undead.lua"
MARK = "-- [RXPForever] Sevren on the way"

text = open(G, encoding="utf-8", newline="").read()
if MARK in text:
    sys.exit("already patched")
nl = "\r\n" if "\r\n" in text else "\n"
L = text.split(nl)

lab = [i for i, l in enumerate(L) if l.strip() == "#label AgamandStart"]
assert len(lab) == 1, "#label AgamandStart not found once (%d)" % len(lab)
s = lab[0]
while not L[s].lstrip().startswith("step"):
    s -= 1
L[s:s] = [
    "step",
    "    .goto 1420/0,265.15,2305.94",
    "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Sevren|r in Brill on your way north",
    "    .turnin 360 >>Turn in Return to the Magistrate",
    "    .isOnQuest 360",
    "    .target Magistrate Sevren",
    "    " + MARK + " (Brill is on the way from Linnea to Agamand Mills)",
]
open(G, "w", encoding="utf-8", newline="").write(nl.join(L))
print("added the Sevren hand-in before AgamandStart")
