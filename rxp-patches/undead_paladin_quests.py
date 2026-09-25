"""Undead Paladin class quests in RXP's forever/Horde-01-14_Undead.lua - builds the whole fix from RXP's ORIGINAL file.

SUPERSEDES skip_coming_to_terms.py and add_rediscovering_the_light.py (25 Sep 2026, same day):
  - a level-4 Undead Paladin was never offered Coming to Terms (91208) -> first skipped it.
  - He then asked for Rediscovering the Light (90902, which RXP had commented out as "only 85xp, not worth doing").
  - After handing 90902 in, Coming to Terms appeared at Aramis: "rediscovering the light is the prequest to coming to
    terms". Wowhead Forever lists no prerequisite for 91208 - this link is from Gaz's own play.

Quest chain (Aramis Hammerhand, Deathknell chapel): 90902 Rediscovering the Light (level 2: heal 5 Injured Deathguard
with Holy Light; npc 259377, 17 spawns Tirisfal 30.0-33.6 x 62.0-66.6) -> 91208 Coming to Terms (level 4: the
Frightened Paladin west of the chapel, ~27.7,63.8) -> 91209 Continue Your Training (report to Shari Stilwell, Brill).

What this script does to the ORIGINAL guide text (every optional piece in its own gated step, so skipping a quest
never blocks the guide - Coming to Terms blocked the Aramis step for exactly that reason):
  1. level-2 Aramis step: restore `.accept 90902`
  2. new #sticky #loop step after it: heal 5 Injured Deathguard, `.isOnQuest 90902` (RXP's SetStep re-activates
     unfinished sticky steps behind your position, so a paladin already past the accept still gets it)
  3. new step before the 91209/98389 Aramis step: turn in 90902 + accept 91208, gated `.isQuestComplete 90902`
     (true once complete OR turned in); the original `.accept 91208` line in the 91209 step is removed
  4. Frightened Paladin step: add `.isOnQuest 91208`
  5. new step before the later Aramis step (98389 hand-in): turn in 91208, gated `.isQuestComplete 91208`; the
     original `.turnin 91208` line in that step is removed
Usage: python undead_paladin_quests.py            -> original = Horde-01-14_Undead.BEFORE-comingtoterms.lua here,
                                                      result written to the installed guide
       python undead_paladin_quests.py IN OUT     -> test run
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ORIGINAL = os.path.join(HERE, "Horde-01-14_Undead.BEFORE-comingtoterms.lua")   # RXP v4.11.9, untouched
GUIDE = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Horde-01-14_Undead.lua"
MARK = "-- [RXPForever] "
src, dst = (sys.argv[1], sys.argv[2]) if len(sys.argv) > 2 else (ORIGINAL, GUIDE)

text = open(src, encoding="utf-8", newline="").read()
assert "[RXPForever]" not in text, "the input must be RXP's original file"
nl = "\r\n" if "\r\n" in text else "\n"
L = text.split(nl)


def find(pred, what):
    hits = [i for i, l in enumerate(L) if pred(l)]
    assert len(hits) == 1, "%s: expected 1 line, found %d" % (what, len(hits))
    return hits[0]


def step_start(i):
    while not L[i].lstrip().startswith("step"):
        i -= 1
    return i


ARAMIS = ["    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Aramis Hammerhand|r",
          "    .target Aramis Hammerhand"]

# 5 first (bottom of the file), so earlier line numbers stay valid
t = find(lambda l: l.strip() == ".turnin 91208 >>Turn in Coming to Terms << Paladin", "turnin 91208")
del L[t]
s = step_start(t)
L[s:s] = ["step << Paladin", "    .goto 1420/0,1628.400,1837.000", ARAMIS[0],
          "    .turnin 91208 >>Turn in Coming to Terms", "    .isQuestComplete 91208", ARAMIS[1],
          "    " + MARK + "91208 hand-in: own step, only once the quest is complete"]

# 4 Frightened Paladin step: gate it, and give it a waypoint (RXP's step has none; Wowhead has no spawn data for the
#   npc - the only location is a Forever-tagged Wowhead comment on quest 91208, 22 Sep 2026: "/way 27.72 63.83 just
#   south of the bat cave")
c = find(lambda l: l.strip().startswith(".complete 91208,1"), "complete 91208")
L.insert(c + 1, "    .isOnQuest 91208")
L.insert(step_start(c) + 1, "    .goto 1420,27.72,63.83   " + MARK + "from a Wowhead Forever comment (no spawn data)")

# 3 hand-in 90902 + accept 91208 before the 91209 step
a = find(lambda l: l.strip() == ".accept 91208 >>Accept Coming to Terms << Paladin", "accept 91208")
del L[a]
s = step_start(a)
L[s:s] = ["step << Paladin", "    .goto 1420/0,1628.300,1837.300", ARAMIS[0],
          "    .turnin 90902 >>Turn in Rediscovering the Light",
          "    .accept 91208 >>Accept Coming to Terms",
          "    .isQuestComplete 90902", ARAMIS[1],
          "    " + MARK + "90902 unlocks 91208 (found in game 25 Sep); own step, only once 90902 is done"]

# 1 + 2 Rediscovering the Light accept + sticky heal step
r = find(lambda l: l.strip() == "--.accept 90902 >>Accept Rediscovering the Light", "commented accept 90902")
L[r] = "    .accept 90902 >>Accept Rediscovering the Light"
n = [j for j in range(r, r + 4) if L[j].strip() == "--90902 only 85xp, not worth doing"]
assert n, "RXP's 'not worth doing' note not found"
L[n[0]] = "    " + MARK + "90902 restored: it unlocks Coming to Terms (91208)"
nxt = r + 1
while not L[nxt].lstrip().startswith("step"):
    nxt += 1
L[nxt:nxt] = [
    "step << Paladin",
    "    #sticky",
    "    #loop",
    "    .goto 1420,31.6,64.4,15,0",
    "    .goto 1420,32.6,63.4,15,0",
    "    .goto 1420,33.6,64.8,15,0",
    "    .goto 1420,31.4,66.0,15,0",
    "    >>Cast |cRXP_WARN_Holy Light|r on 5 |cRXP_FRIENDLY_Injured Deathguard|r around Deathknell's chapel - do it"
    " while you quest here (it unlocks Coming to Terms)",
    "    .complete 90902,1 --Injured Deathguard healed (5)",
    "    .isOnQuest 90902",
    "    .target Injured Deathguard",
    "    " + MARK + "90902 heal step (Wowhead Forever npc 259377 spawns)",
]

open(dst, "w", encoding="utf-8", newline="").write(nl.join(L))
print("written", dst)
