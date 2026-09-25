"""Give the "Loot the Book in the shelf" step (#label MetaBook) in RXP's forever/Horde-01-14_Undead.lua a waypoint.

25 Sep 2026, Gaz: "step 76 needs a waypoint loot the book in the shelf". RXP's step only has the text and
`.collect 208185` (The Apothecary's Metaphysical Primer), with a TODO. Wowhead Forever: the item is contained in the
object "Apothecary Society Primer" (405879) at Tirisfal Glades (uiMap 1420) 59.4,52.3 - the Alchemy trainer's house
(Carolai Anise) as you enter Brill; a comment (17 Sep) says it is on the potion shelf on the right.
Run once: python add_metabook_waypoint.py
"""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Horde-01-14_Undead.lua"
MARK = "-- [RXPForever] MetaBook waypoint"

text = open(G, encoding="utf-8", newline="").read()
if MARK in text:
    sys.exit("already patched")
nl = "\r\n" if "\r\n" in text else "\n"
L = text.split(nl)

lab = [i for i, l in enumerate(L) if l.strip() == "#label MetaBook"]
assert len(lab) == 1, "#label MetaBook not found once (%d)" % len(lab)
i = lab[0]
assert L[i + 1].strip() == ">>Loot the |cRXP_PICK_Book|r in the shelf", "unexpected step text: " + L[i + 1]
L[i + 1:i + 2] = [
    "    .goto 1420,59.4,52.3",
    "    >>Loot the |cRXP_PICK_Book|r (Apothecary Society Primer) in the shelf - inside the Alchemy trainer's house"
    " (|cRXP_FRIENDLY_Carolai Anise|r) as you enter Brill, the potion shelf on the right",
    "    " + MARK + " (Wowhead Forever object 405879)",
]
open(G, "w", encoding="utf-8", newline="").write(nl.join(L))
print("MetaBook step now has .goto 1420,59.4,52.3")
