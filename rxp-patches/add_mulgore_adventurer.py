"""Mulgore: add Forever's camp quests "The Adventurer" (96659) and "The Great Outdoors" (96605).

The Adventurer: accept from Chief Hawkwind (same step where Rites of the Earthmother 763 is accepted, req level 4, 410 XP),
deliver the Supply Bundle to Kaga Wildhoof (npc 265810, Mulgore 46.2,67.2, just outside Bloodhoof Village).
The Great Outdoors: accept from Kaga, /sit near her campfire for a minute (Boosted Rest buff), hand in to Kaga (410 XP).
Added after the Innkeeper Kauth / hearth step in BOTH Mulgore variants (6-12 and 7-13). Same shape as RXP's Durotar chain
(96652 / 96604) but not hardcore-only. Applies to the patched Horde-1-12_Mulgore.lua in installed-v4.11.9 and installed-v4.11.13.
Run from the repo root, then refresh_manifest.py for both versions.  Safe to run twice.
"""
import os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REL = "RXPGuides/Guides/forever/Horde-1-12_Mulgore.lua"
BUBBLE = "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to "

ACCEPT_OLD = "    .accept 763 >>Accept Rites of the Earthmother\n"
ACCEPT_NEW = ACCEPT_OLD + "    .accept 96659 >>Accept The Adventurer\n"

ANCHOR = "    .bindlocation 222\n    .subzoneskip 222,1\n"
KAGA = ("step\n"
        "    .goto 1412,46.2,67.2\n"
        + BUBBLE + "|cRXP_FRIENDLY_Kaga|r|cRXP_WARN_ at her camp just outside Bloodhoof Village|r\n"
        "    .turnin 96659 >>Turn in The Adventurer\n"
        "    .accept 96605 >>Accept The Great Outdoors\n"
        "    .target Kaga Wildhoof\n"
        "    .isOnQuest 96659\n"
        "step\n"
        "    #optional\n"
        "    .goto 1412,46.2,67.2\n"
        + BUBBLE + "|cRXP_FRIENDLY_Kaga|r\n"
        "    .accept 96605 >>Accept The Great Outdoors\n"
        "    .target Kaga Wildhoof\n"
        "step\n"
        "    .goto 1412,46.2,67.2\n"
        "    >>|cRXP_WARN_Type /sit next to Kaga's campfire and wait one minute until you get the Boosted Rest buff|r\n"
        "    .complete 96605,1 --|1/1 Use the /sit emote near the campfire\n"
        "    .macro Sit,134400 >>/sit\n"
        "    .timer 59, RP\n"
        "    .complete 96605,2 --|Gain the Boosted Rest buff\n"
        "step\n"
        "    .goto 1412,46.2,67.2\n"
        + BUBBLE + "|cRXP_FRIENDLY_Kaga|r\n"
        "    .turnin 96605 >>Turn in The Great Outdoors\n"
        "    .target Kaga Wildhoof\n")

# before leaving camp (shamans: before the Manifestation trip): vendor the trash again at Kawnie
VENDOR_STEP = ("step\n"
               "    .goto 1412/1,-279.37,-2893.73\n"
               + BUBBLE + "|cRXP_FRIENDLY_Kawnie|r\n"
               "    .vendor >> Vendor Trash\n"
               "    .target Kawnie Softbreeze\n")


for ver in ("v4.11.9", "v4.11.13"):
    p = os.path.join(HERE, "installed-" + ver, REL.replace("/", os.sep))
    with open(p, "rb") as f:
        raw = f.read().decode("utf-8")
    crlf = "\r\n" in raw
    s = raw.replace("\r\n", "\n")
    if "96659" in s:
        print(ver, "already patched")
        continue
    assert s.count(ACCEPT_OLD) == 2 and s.count(ANCHOR) == 2, (s.count(ACCEPT_OLD), s.count(ANCHOR))
    # the Chief step ends with .target/.goto lines; put the vendor step right after them
    chief_end = ACCEPT_NEW + "    .target +Chief Hawkwind\n    .goto 1412/1,-221.83,-2878.31\n"
    s = s.replace(ACCEPT_OLD + "    .target +Chief Hawkwind\n    .goto 1412/1,-221.83,-2878.31\n", chief_end + VENDOR_STEP)
    s = s.replace(ANCHOR, ANCHOR + KAGA)
    with open(p, "wb") as f:
        f.write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))
    print(ver, "patched")
