"""Add Father Gavin's Forever chain (99158-99162) and Never Saddle on Quality (95212) to RXP's Dun Morogh guide.
Data: Wowhead Forever, 23 Sep 2026.
  99158 Dawn in the Mountains (70 XP): Maxan Anvol (Kharanos inn 47.2,52.2) -> Father Gavin (57.4,44.8).
  99159 Finding Warmth (700): 14 Mostly Dry Firewood - white trunks on the ground next to trees, some give 2.
  99160 Rime's Wrath (700): 10 Minor Ice Elementals (npc 276003, around 52-58, 43-49).
  99161 Rime's Wrath (700): kill Avala (npc 276009, 57-59, 42-44) for Avala's Core. Offered after 99160 or
        with it - the guide turns 99160 in and accepts 99161 on the spot, which works either way.
  99162 Treacherous Cold (700): rifles by fallen mountaineers - Coalbeard 52.0,44.0 (under the tree across the
        frozen river W of Gavin), Stoneanvil 53.0,59.0 (valley S of Gavin, by a cart), Sunhammer 60.0,50.0 (by a
        cart on the path up to Vagash's cave). Coordinates from the map link in a Wowhead comment.
  95212 Never Saddle on Quality (630 XP, 75 Ironforge rep, req 7): Rudra Amberstill (ranch 63.0,49.8);
        6 Pristine Leopard Pelts from Elder Snow Leopards (npc 260157, lvl 9-10, 42% drop, 70-82, 51-63).
Placement: Dawn pickup at the last Kharanos inn visit; Gavin chain just before Rudra (Vagash section); Never
Saddle accepted with Protecting the Herd, pelts right after the Gol'Bolar Quarry hand-ins, then back to Rudra.
All completes/turn-ins use negative IDs (skip if not on the quest). Idempotent."""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Alliance-1-14_DwarfGnome.lua"
B = "|Tinterface/worldmap/chatbubble_64grey.blp:20|t"
s = open(G, encoding="utf-8").read()
if "99158" in s or "95212" in s:
    sys.exit("already applied")

def insert_after(text, anchor, block, expect=1):
    n = text.count(anchor)
    if n != expect:
        sys.exit("anchor found %d times (expected %d): %r" % (n, expect, anchor[:60]))
    return text.replace(anchor, anchor + block)

def insert_before(text, anchor, block, expect=None):
    n = text.count(anchor)
    if n == 0 or (expect is not None and n != expect):
        sys.exit("anchor found %d times: %r" % (n, anchor[:60]))
    return text.replace(anchor, block + anchor)

# 1. Dawn in the Mountains pickup - Kharanos inn, right after the First Aid training step (last inn visit)
thamner = """step << !Warrior !Rogue !Paladin
    .goto Dun Morogh,47.180,52.610
    >>""" + B + """Talk to |cRXP_FRIENDLY_Thamner Pol|r
    .train 3273 >> Train |T135966:0|t[First Aid]
    .target Thamner Pol
"""
s = insert_after(s, thamner, f"""step
    .goto Dun Morogh,47.2,52.2
    >>{B}Talk to |cRXP_FRIENDLY_Maxan Anvol|r in the inn (Forever quest - opens Father Gavin's 2,100 XP chain)
    .accept 99158 >> Accept Dawn in the Mountains
    .target Maxan Anvol
""")

# 2. Father Gavin chain, before the Rudra / Vagash section (both copies of the guide)
gavin = f"""step
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r in the old building in the hills
    .turnin 99158 >> Turn in Dawn in the Mountains
    .target Father Gavin
    .isOnQuest 99158
step
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r
    .accept 99159 >> Accept Finding Warmth
    .accept 99160 >> Accept Rime's Wrath
    .accept 99162 >> Accept Treacherous Cold
    .target Father Gavin
    .isQuestTurnedIn 99158
step
    .goto Dun Morogh,55.4,44.6,40,0
    .goto Dun Morogh,53.4,43.8,40,0
    .goto Dun Morogh,56.4,46.8,40,0
    >>Kill |cRXP_ENEMY_Minor Ice Elementals|r around Father Gavin
    >>Pick up |cRXP_LOOT_Mostly Dry Firewood|r - the white trunks on the ground next to trees (some give 2)
    .complete -99160,1 --Minor Ice Elemental slain (10)
    .complete -99159,1 --Mostly Dry Firewood (14)
    .mob Minor Ice Elemental
step
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r
    .turnin -99160 >> Turn in Rime's Wrath
    .accept 99161 >> Accept Rime's Wrath
    .target Father Gavin
    .isQuestTurnedIn 99158
step
    .goto Dun Morogh,58.2,42.6
    >>Kill |cRXP_ENEMY_Avala|r, the large ice elemental just north-east of Father Gavin. Loot its |cRXP_LOOT_Core|r
    .complete -99161,1 --Avala's Core (1)
    .mob Avala
step
    .goto Dun Morogh,52.0,44.0,15,0
    .goto Dun Morogh,53.0,59.0,15,0
    .goto Dun Morogh,60.0,50.0,15,0
    >>Collect the three rifles lying next to fallen mountaineers:
    >>|cRXP_LOOT_Coalbeard's Rifle|r - follow the frozen river west, under the tree fallen across it
    >>|cRXP_LOOT_Stoneanvil's Rifle|r - in the valley to the south, next to a cart
    >>|cRXP_LOOT_Sunhammer's Rifle|r - next to a cart on the small path up to Vagash's cave
    .complete -99162,1
    .complete -99162,2
    .complete -99162,3
step
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r
    .turnin -99159 >> Turn in Finding Warmth
    .turnin -99161 >> Turn in Rime's Wrath
    .turnin -99162 >> Turn in Treacherous Cold
    .target Father Gavin
"""
rudra_label = "step\n    #label Rudra\n"
s = insert_before(s, rudra_label, gavin)

# 3. Never Saddle on Quality - accept with Protecting the Herd (both copies)
s = s.replace("    .accept 314 >> Accept Protecting the Herd\n",
              "    .accept 314 >> Accept Protecting the Herd\n    .accept 95212 >> Accept Never Saddle on Quality\n")

# 4. Pelts right after the Gol'Bolar Quarry hand-ins, then back to Rudra (both copies)
quarry = "    .turnin 433 >> Turn in The Public Servant\n"
pelts = f"""step
    .goto Dun Morogh,72.5,55.0,40,0
    .goto Dun Morogh,76.0,58.5,40,0
    .goto Dun Morogh,79.5,54.0,40,0
    >>Kill |cRXP_ENEMY_Elder Snow Leopards|r east of the quarry. Loot them for |cRXP_LOOT_Pristine Leopard Pelts|r (about 2 in 5 drop one)
    .complete -95212,1 --Pristine Leopard Pelt (6)
    .mob Elder Snow Leopard
step
    .goto 1426/0,-1304.71,-5513.86
    >>{B}Back west to |cRXP_FRIENDLY_Rudra Amberstill|r at the ranch
    .turnin -95212 >> Turn in Never Saddle on Quality
    .target Rudra Amberstill
"""
out, pos, done = [], 0, 0
while True:
    i = s.find(quarry, pos)
    if i < 0:
        break
    j = s.find("\nstep", i)            # end of the quarry turn-in step
    if j < 0:
        break
    out.append(s[pos:j + 1])
    out.append(pelts)
    pos = j + 1
    done += 1
out.append(s[pos:])
s = "".join(out)
if done == 0:
    sys.exit("quarry anchor not found")

open(G, "w", encoding="utf-8", newline="\n").write(s)
print("added Dawn pickup, Gavin chain x%d, Never Saddle accept x%d, pelts+turn-in x%d"
      % (s.count("Accept Finding Warmth"), s.count("Accept Never Saddle"), done))
