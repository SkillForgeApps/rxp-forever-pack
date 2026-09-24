"""Add The Quarry's Smith (95217, Forever-only; Gaz 23 Sep 2026: "is the quarry smith in the guide, if not add it").
Wowhead Forever 23 Sep: giver/turn-in Frast Dokner <Apprentice Weaponsmith> (npc 1698), Gol'Bolar Quarry camp
68.8,55.8; req level 7, level 10; 12 Copper Bars (2840) + 4 Toughened Boar Hides (267416, from Scarred Crag Boars
npc 1689, lvl 9-10, 71-87 x 33-58 - same ground east of the quarry as the Elder Snow Leopards); reward 630 XP,
75 Ironforge rep, Plans: Rough Copper Chain Boots. Not in any RXP guide.
Placement (both 06-11 Dun Morogh copies): accept right after the step that accepts Those Blasted Troggs! (Gol'Bolar
Quarry); boar hides added to the Never Saddle pelt step; hand-in at Frast Dokner before heading back west to Rudra,
`.turnin -95217,1` = skipped automatically if not on it or not complete (e.g. no Copper Bars yet). Idempotent."""
import sys

B = "|Tinterface/worldmap/chatbubble_64grey.blp:20|t"
FILES = [r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Alliance-1-14_DwarfGnome.lua",
         r"D:\wow-forever-addons\rxp-forever\patches\Alliance-1-14_DwarfGnome.PATCHED.lua"]

ACCEPT = f"""step
    .goto Dun Morogh,68.8,55.8
    >>{B}Talk to |cRXP_FRIENDLY_Frast Dokner|r at the quarry camp (Forever quest: 630 XP)
    >>|cRXP_WARN_Needs 12 Copper Bars (mine + smelt, or buy on the AH) plus 4 boar hides from the boars east of here. If he doesn't offer it, click this step to move on|r
    .accept 95217 >> Accept The Quarry's Smith
    .target Frast Dokner
"""
OLD_PELTS = """    >>Kill |cRXP_ENEMY_Elder Snow Leopards|r east of the quarry. Loot them for |cRXP_LOOT_Pristine Leopard Pelts|r (about 2 in 5 drop one)
    .complete -95212,1 --Pristine Leopard Pelt (6)
    .mob Elder Snow Leopard
"""
NEW_PELTS = """    >>Kill |cRXP_ENEMY_Elder Snow Leopards|r east of the quarry. Loot them for |cRXP_LOOT_Pristine Leopard Pelts|r (about 2 in 5 drop one)
    >>Kill |cRXP_ENEMY_Scarred Crag Boars|r in the same area for |cRXP_LOOT_Toughened Boar Hides|r
    .complete -95212,1 --Pristine Leopard Pelt (6)
    .complete -95217,2 --Toughened Boar Hide (4)
    .mob Elder Snow Leopard
    .mob Scarred Crag Boar
"""
TURNIN = f"""step
    .goto Dun Morogh,68.8,55.8
    >>{B}Back at the quarry camp: talk to |cRXP_FRIENDLY_Frast Dokner|r (skipped if you don't have the 12 Copper Bars yet)
    .turnin -95217,1 >> Turn in The Quarry's Smith
    .target Frast Dokner
"""
RUDRA = f"step\n    .goto 1426/0,-1304.71,-5513.86\n    >>{B}Back west to |cRXP_FRIENDLY_Rudra Amberstill|r at the ranch\n"
TROGGS = "    .accept 432 >> Accept Those Blasted Troggs!\n"

for path in FILES:
    s = open(path, encoding="utf-8").read()
    if "95217" in s:
        print("already applied:", path)
        continue
    # 1. accept after each step that accepts 432
    out, pos, n1 = [], 0, 0
    while True:
        i = s.find(TROGGS, pos)
        if i < 0:
            break
        j = s.find("\nstep", i) + 1
        out += [s[pos:j], ACCEPT]
        pos = j
        n1 += 1
    out.append(s[pos:])
    s = "".join(out)
    # 2. hides on the pelt step, 3. hand-in before Rudra
    n2, n3 = s.count(OLD_PELTS), s.count(RUDRA)
    if not (n1 == n2 == n3 == 2):
        sys.exit("unexpected anchors %d/%d/%d in %s" % (n1, n2, n3, path))
    s = s.replace(OLD_PELTS, NEW_PELTS).replace(RUDRA, TURNIN + RUDRA)
    open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("added Quarry's Smith x2:", path)
