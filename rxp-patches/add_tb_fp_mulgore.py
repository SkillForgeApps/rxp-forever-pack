"""Add a Thunder Bluff visit (flight path + Journey into Thunder Bluff) to both Mulgore routes, after A Sacred Burial.

Why (28 Sep 2026, a Tauren warrior): the 6-12 route later flies you to Thunder Bluff from the Crossroads
(Ride to Thunder Bluff) but never sends you to Tal first. RXP assumes Tauren start with the Thunder Bluff flight path -
its Durotar guide gets it "<< !Tauren" - which is Classic behaviour; on Forever a new Tauren does NOT know it (Gaz had
to pick it up himself). Gaz: "if you're going to get the TB FP then we should also hand in Journey into Thunder Bluff".
775 is accepted at the Rite of Wisdom spirit, so the visit goes straight after "Turn in A Sacred Burial" (the next
steps - Mazzranache's items, swoops - roam towards Thunder Bluff anyway). Inserted steps: travel in (RXP's own entry
point 1456/1,182.67,-1314.05), Tal .fp (RXP's coords 1456/1,26.1,-1196.66), Cairne .turnin 775 (+ .accept 776 Rites of
the Earthmother in the 6-12 route; the 7-13 route has RXP's 776 accept commented out, so hand-in only), then back down
to Mulgore (RXP's own ".zone Mulgore / .zoneskip Thunder Bluff,1" exit pattern). RXP's later Cairne step completes by
itself (775 turned in, 776 on the log). .fp completes once RXP has seen the path on a flight map; a character that
already has it talks to Tal once or skips. ADDS 4 STEPS per route: characters past A Sacred Burial shift by 4 -
RXPForever's fingerprint restore keeps them on their step. Idempotent; backs up the original next to this script.
Re-run after every RXP update (after fix_mulgore_barrens_text.py).
"""
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"   # edit if your game is elsewhere
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
TAG = "#label TBFlightPath"


def block(accept_776):
    cairne = [
        "step",
        "    #label TBJourney",
        "    .goto 1456/1,-109.58,-1209.75",
        "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Cairne|r",
        "    .turnin 775 >>Turn in Journey into Thunder Bluff",
    ]
    if accept_776:
        cairne.append("    .accept 776 >>Accept Rites of the Earthmother")
    cairne.append("    .target Cairne Bloodhoof")
    return [
        "step",
        "    #completewith TBFlightPath",
        "    .goto 1456/1,182.67,-1314.05,40,0",
        "    .zone Thunder Bluff >> Head into |cRXP_FRIENDLY_Thunder Bluff|r. Ride a lift up to the mesas",
        "    .zoneskip Thunder Bluff",
        "step",
        "    " + TAG,
        "    .goto 1456/1,26.1,-1196.66",
        "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Tal|r at the top of the tower",
        "    >>|cRXP_WARN_The route flies you to Thunder Bluff from the Crossroads later - that needs this flight path. "
        "Tauren don't start with it on Forever|r",
        "    .fp Thunder Bluff >> Get the Thunder Bluff flight path",
        "    .target Tal",
    ] + cairne + [
        "step",
        "    #completewith next",
        "    .zone Mulgore >> Take a lift back down to Mulgore",
        "    .zoneskip Thunder Bluff,1",
    ]


path = os.path.join(ADDONS, "RXPGuides", "Guides", "forever", "Horde-1-12_Mulgore.lua")
src = open(path, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
lines = src.split(nl)
if TAG in src:
    print("Horde-1-12_Mulgore.lua: nothing to patch (already patched?)")
    raise SystemExit
route_713 = next(i for i, l in enumerate(lines) if l.strip() == "#name 7-13 Mulgore")
anchors = [i for i, l in enumerate(lines) if l.strip() == ".turnin 833 >>Turn in A Sacred Burial"]
if len(anchors) != 2:
    raise SystemExit("expected 2 'Turn in A Sacred Burial' steps (one per route), found %d - redo by hand" % len(anchors))
for i in reversed(anchors):
    end = next(j for j in range(i + 1, len(lines)) if lines[j].strip().startswith("step"))   # start of the next step
    lines[end:end] = block(accept_776=i < route_713)
backup = os.path.join(HERE, "Horde-1-12_Mulgore.BEFORE-tbfp.lua")
if not os.path.exists(backup):
    shutil.copy2(path, backup)
open(path, "w", encoding="utf-8", newline="").write(nl.join(lines))
print("Horde-1-12_Mulgore.lua: Thunder Bluff visit added after A Sacred Burial in %d routes; backup %s"
      % (len(anchors), backup))
