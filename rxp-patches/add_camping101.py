"""Add the Camping 101 profession quests (Eric Brighthammer, Kharanos) to RXP's Forever Dun Morogh guide.
Data: Wowhead Forever 23 Sep 2026. Each quest: raise that profession to 20, hand in to its trainer, learn a camp
item recipe, 270 XP. Cooking: learn Cooking from Gremlock Pilsnor and hand in to him. Pickups follow RXP's own
pattern from forever/Alliance-1-13_Human.lua (one step per profession gated by `.skill <prof>,<1,1`); hand-ins
are gated by `.isQuestComplete` so they only appear once the skill is 20.
Run once: python add_camping101.py   (edits the installed guide in place; refuses to run twice)"""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Alliance-1-14_DwarfGnome.lua"
BUBBLE = "|Tinterface/worldmap/chatbubble_64grey.blp:20|t"

s = open(G, encoding="utf-8").read()
if "Camping 101" in s:
    sys.exit("Camping 101 already present - not applying twice")

# ---------- 1. pickups at Eric, right after The Great Outdoors turn-in ----------
anchor1 = """    .turnin -96608 >> Turn in The Great Outdoors
    .target Eric Brighthammer
"""
assert s.count(anchor1) == 1, "anchor1"
PICKUPS = [  # quest, rxp skill key, profession, trainer, where
    (96044, "blacksmithing", "Blacksmithing", "Tognus Flintfire", "Kharanos"),
    (96058, "engineering", "Engineering", "Bronk Guzzlegear", "Kharanos"),
    (96046, "mining", "Mining", "Yarr Hammerstone", "Kharanos"),
    (96047, "firstaid", "First Aid", "Thamner Pol", "Kharanos"),
    (96050, "fishing", "Fishing", "Paxton Ganter", "Iceflow Lake"),
    (96031, "leatherworking", "Leatherworking", "Gretta Finespindle", "Ironforge"),
    (96055, "herbalism", "Herbalism", "Reyna Stonebranch", "Ironforge"),
    (96056, "skinning", "Skinning", "Balthus Stoneflayer", "Ironforge"),
    (96057, "tailoring", "Tailoring", "Uthrar Threx", "Ironforge"),
]
add1 = f"""step
    .goto Dun Morogh,46.6,53.8
    >>{BUBBLE}Talk to |cRXP_FRIENDLY_Eric Brighthammer|r again
    .accept 96629 >> Accept Camping 101: Cooking
    .target Eric Brighthammer
    .isQuestTurnedIn 96608
"""
for q, key, prof, trainer, where in PICKUPS:
    add1 += f"""step
    .goto Dun Morogh,46.6,53.8
    >>{BUBBLE}Talk to |cRXP_FRIENDLY_Eric Brighthammer|r: Camping 101 for your {prof}. Raise {prof} to 20, then hand it in to |cRXP_FRIENDLY_{trainer}|r ({where}) for a camp item recipe and 270 XP
    .accept {q} >> Accept Camping 101: {prof}
    .target Eric Brighthammer
    .isQuestTurnedIn 96608
    .skill {key},<1,1 -- only if you have {prof}
"""
add1 += f"""step
    .goto Dun Morogh,47.6,52.4
    >>{BUBBLE}Talk to |cRXP_FRIENDLY_Gremlock Pilsnor|r, the cooking trainer inside the inn
    .train 2550 >> Train |T133971:0|t[Cooking]
    .turnin -96629 >> Turn in Camping 101: Cooking
    .target Gremlock Pilsnor
"""
s = s.replace(anchor1, anchor1 + add1)

# ---------- 2. Kharanos hand-ins, after the last Kharanos visit (First Aid training at Thamner Pol) ----------
anchor2 = """step << !Warrior !Rogue !Paladin
    .goto Dun Morogh,47.180,52.610
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thamner Pol|r
    .train 3273 >> Train |T135966:0|t[First Aid]
    .target Thamner Pol
"""
assert s.count(anchor2) == 1, "anchor2"
KHARANOS = [
    (96044, "Blacksmithing", "Tognus Flintfire", "45.2,52.0", ""),
    (96047, "First Aid", "Thamner Pol", "47.2,52.4", ""),
    (96058, "Engineering", "Bronk Guzzlegear", "50.2,50.4", ""),
    (96046, "Mining", "Yarr Hammerstone", "50.0,50.4", " inside downstairs"),
    (96050, "Fishing", "Paxton Ganter", "35.4,40.2", " at Iceflow Lake (a short detour west)"),
]
add2 = ""
for q, prof, trainer, xy, extra in KHARANOS:
    add2 += f"""step
    .goto Dun Morogh,{xy}
    >>{BUBBLE}Talk to |cRXP_FRIENDLY_{trainer}|r{extra}
    .turnin {q} >> Turn in Camping 101: {prof}
    .target {trainer}
    .isQuestComplete {q}
"""
s = s.replace(anchor2, anchor2 + add2)

# ---------- 3. Ironforge hand-ins, after Senator Barin Redstone on the Ironforge visit ----------
anchor3 = """    .turnin 291 >> Turn in The Reports
    .target Senator Barin Redstone
"""
assert s.count(anchor3) == 1, "anchor3"
IRONFORGE = [
    (96055, "Herbalism", "Reyna Stonebranch", "55.4,58.4"),
    (96057, "Tailoring", "Uthrar Threx", "43.4,28.2"),
    (96031, "Leatherworking", "Gretta Finespindle", "39.0,32.4"),
    (96056, "Skinning", "Balthus Stoneflayer", "39.4,32.4"),
]
add3 = ""
for q, prof, trainer, xy in IRONFORGE:
    add3 += f"""step
    .goto Ironforge,{xy}
    >>{BUBBLE}Talk to |cRXP_FRIENDLY_{trainer}|r
    .turnin {q} >> Turn in Camping 101: {prof}
    .target {trainer}
    .isQuestComplete {q}
"""
s = s.replace(anchor3, anchor3 + add3)

open(G, "w", encoding="utf-8", newline="\n").write(s)
print("added: 1 cooking pickup + %d profession pickups + cooking hand-in, %d Kharanos and %d Ironforge hand-ins"
      % (len(PICKUPS), len(KHARANOS), len(IRONFORGE)))
