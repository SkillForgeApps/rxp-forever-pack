"""Add the Camping 101 quests (Eleanor Shackleton, Tirisfal) to RXP's forever/Horde-01-14_Undead.lua (6-12 guide).

25 Sep 2026, Gaz: "eleanor shackleton adventurer, probably the same issue we had in the gnome dwarf zone, new quests
with campfires > the great outdoors". RXP's guide turns in The Great Outdoors (96607) at Eleanor but has the Camping
101 accepts commented out (Cooking, Mining) and none of the others. Data: Wowhead Forever 25 Sep (Eleanor npc 265812,
Tirisfal 57.2,55.4; each quest's End npc + g_mapperData). Same pattern as add_camping101.py (Dun Morogh):
  * pickups right after each Eleanor turn-in step (two routes pass her), profession quests only if you have that
    profession (`.skill <key>,<1,1`), all gated `.isQuestTurnedIn 96607`
  * Cooking: learn Cooking from William Pickman in Brill = the hand-in, done straight after the pickups
  * profession hand-ins at later visits, gated `.isQuestComplete` (skill 20 reached):
      Brill + the Deathknell road -> after the Magistrate Sevren step (Return to the Magistrate)
      Rhobarts on the Undercity road -> after Deathguard Linnea's step (same spot)
      Undercity trainers -> after the "Take the lift down to the Undercity" step
Run once: python add_camping101_undead.py   (edits the installed guide; refuses to run twice)
"""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Horde-01-14_Undead.lua"
BUBBLE = "|Tinterface/worldmap/chatbubble_64grey.blp:20|t"
MARK = "-- [RXPForever] Camping 101"

text = open(G, encoding="utf-8", newline="").read()
if MARK in text:
    sys.exit("already patched")
nl = "\r\n" if "\r\n" in text else "\n"
L = text.split(nl)

# quest, rxp skill key, profession, trainer, map, x, y, where
PROFS = [
    (97951, "alchemy", "Alchemy", "Carolai Anise", 1420, 59.4, 52.2, "Brill"),
    (97952, "blacksmithing", "Blacksmithing", "Basil Frye", 1458, 59.2, 29.4, "Undercity"),
    (97953, "enchanting", "Enchanting", "Vance Undergloom", 1420, 61.6, 51.6, "Brill"),
    (97954, "engineering", "Engineering", "Graham Van Talen", 1458, 75.2, 72.4, "Undercity"),
    (97955, "firstaid", "First Aid", "Nurse Neela", 1420, 61.8, 52.8, "Brill"),
    (97956, "fishing", "Fishing", "Clyde Kellen", 1420, 67.2, 51.0, "Brill"),
    (97957, "herbalism", "Herbalism", "Faruza", 1420, 59.8, 52.0, "Brill"),
    (97958, "leatherworking", "Leatherworking", "Shelene Rhobart", 1420, 65.4, 60.0, "the road to Undercity"),
    (97959, "mining", "Mining", "Brom Killian", 1458, 55.4, 36.2, "Undercity"),
    (97960, "skinning", "Skinning", "Rand Rhobart", 1420, 65.4, 60.0, "the road to Undercity"),
    (97961, "tailoring", "Tailoring", "Bowen Brisboise", 1420, 52.4, 55.6, "the road from Deathknell to Brill"),
]


def step_end(i):
    """index of the line after the step that contains line i"""
    j = i + 1
    while j < len(L) and not L[j].lstrip().startswith("step"):
        j += 1
    return j


def handin(q, prof, trainer, m, x, y, where):
    return ["step",
            "    .goto %d,%.1f,%.1f" % (m, x, y),
            "    >>%sTalk to |cRXP_FRIENDLY_%s|r (%s)" % (BUBBLE, trainer, where),
            "    .turnin %d >>Turn in Camping 101: %s" % (q, prof),
            "    .isQuestComplete %d" % q,
            "    .target %s" % trainer,
            "    " + MARK + " hand-in"]


pickups = ["step",
           "    .goto 1420,57.2,55.4",
           "    >>%sTalk to |cRXP_FRIENDLY_Eleanor Shackleton|r again: Camping 101 (learn Cooking in Brill; the "
           "profession ones: raise it to 20, then hand in to that trainer for a camp item recipe)" % BUBBLE,
           "    .accept 96658 >>Accept Camping 101: Cooking",
           "    .target Eleanor Shackleton",
           "    .isQuestTurnedIn 96607",
           "    " + MARK + " pickups (Wowhead Forever, Eleanor npc 265812)"]
for q, key, prof, trainer, m, x, y, where in PROFS:
    pickups += ["step",
                "    .goto 1420,57.2,55.4",
                "    >>%sTalk to |cRXP_FRIENDLY_Eleanor Shackleton|r: Camping 101 for your %s - raise it to 20, then "
                "hand it in to |cRXP_FRIENDLY_%s|r (%s)" % (BUBBLE, prof, trainer, where),
                "    .accept %d >>Accept Camping 101: %s" % (q, prof),
                "    .target Eleanor Shackleton",
                "    .isQuestTurnedIn 96607",
                "    .skill %s,<1,1 -- only if you have %s" % (key, prof)]
pickups += ["step",
            "    .goto 1420,61.8,51.4",
            "    >>%sTalk to |cRXP_FRIENDLY_William Pickman|r, the cooking trainer in Brill" % BUBBLE,
            "    .train 2550 >>Train |T133971:0|t[Cooking]",
            "    .turnin -96658 >>Turn in Camping 101: Cooking",
            "    .target William Pickman",
            "    " + MARK + " Cooking hand-in = learning Cooking here"]

# insert bottom-up so earlier indexes stay valid
inserts = []
# Undercity hand-ins after "Take the lift down to the Undercity"
lift = [i for i, l in enumerate(L) if "Take the lift down to the Undercity" in l]
assert lift, "UC lift step not found"
uc = []
for q, key, prof, trainer, m, x, y, where in PROFS:
    if m == 1458:
        uc += handin(q, prof, trainer, m, x, y, where)
inserts.append((step_end(lift[0]), uc))
# Brill + Deathknell-road hand-ins after the Magistrate Sevren step (Return to the Magistrate)
sev = [i for i, l in enumerate(L) if l.strip() == ".turnin 360 >>Turn in Return to the Magistrate"]
assert sev, "Sevren step not found"
brill = []
for q, key, prof, trainer, m, x, y, where in PROFS:
    if m == 1420 and "Undercity" not in where:
        brill += handin(q, prof, trainer, m, x, y, where)
# RXP has two Sevren hand-ins (a level-10 one and a later fallback) - use the later visit: more time to reach 20
inserts.append((step_end(sev[-1]), brill))
# Rhobarts after Deathguard Linnea's step
lin = [i for i, l in enumerate(L) if l.strip() == ".accept 356 >>Accept Rear Guard Patrol"]
assert len(lin) == 1, "Linnea step not found once (%d)" % len(lin)
road = []
for q, key, prof, trainer, m, x, y, where in PROFS:
    if "road to Undercity" in where:
        road += handin(q, prof, trainer, m, x, y, where)
inserts.append((step_end(lin[0]), road))
# pickups after each Eleanor turn-in step
for i, l in enumerate(L):
    if l.strip() == ".turnin 96607 >>Turn in The Great Outdoors":
        inserts.append((step_end(i), pickups))
assert sum(1 for _, b in inserts if b is pickups) == 2, "expected the 2 Eleanor turn-in steps"

for at, block in sorted(inserts, key=lambda t: t[0], reverse=True):
    L[at:at] = block

open(G, "w", encoding="utf-8", newline="").write(nl.join(L))
print("added: pickups at 2 Eleanor steps (%d each), Cooking at Pickman, %d Brill/road, %d Rhobart, %d Undercity hand-ins"
      % (len(PROFS) + 1, len(brill) // 7, len(road) // 7, len(uc) // 7))
