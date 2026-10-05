"""Durotar 1-6 (and 1-7 in v4.11.9): the Valley of Trials hand-ins around the Skull Rock death-skip, and the hearth back.

5 Oct 2026, Gaz (new orc mage). Three edits to the already patched Horde-01-12_Durotar.lua in installed-v4.11.9 and installed-v4.11.13
(run AFTER add_profession_reminders_dur_undead.py, which regenerates that file from the release zip; then refresh_manifest.py <version>
for both). Safe to run twice; each edit checks for itself.

1. Death-skip wording. RXP's arrow is at -4326,-41 (outside the cave, also the logout-skip cliff edge): dying THERE respawns you at the
   Razor Hill graveyard, next stop Gar'thok. Gaz died in the cave and respawned in the Valley of Trials. The text now says both.
2. Hand-ins at the Valley respawn: Thazz'ril's Pick 6394 (Foreman Thazz'ril) and Burning Blade Medallion 794 (Zureetha, + accept 805)
   straight after the death-skip, gated .isQuestComplete and `.subzoneskip 363,1` (363 = Valley of Trials per Questie's
   subZoneToParentZone: they only show if you really respawned there).
3. "Hearth to the Valley of Trials" was `#completewith next` where the next step is the Thazz'ril hand-in; once edit 2 had already turned
   that quest in, the hearth step completed itself at once and the guide went on to "Accept The Adventurer" 1 km away. It is a normal step
   now (stays until you hearth), skipped when already in the Valley (.subzoneskip 363) or the stone is on cooldown.
"""
import os
import re

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REL = "RXPGuides/Guides/forever/Horde-01-12_Durotar.lua"
BUBBLE = "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to "
GATE = "    .subzoneskip 363,1\n"

DEATH_OLD = ".deathskip >> |cRXP_WARN_Die and respawn at the |cRXP_FRIENDLY_Spirit Healer|r near the arrow|r\n"
DEATH_NEW = (".deathskip >> |cRXP_WARN_Die AT THE ARROW (outside the cave) to respawn at the |cRXP_FRIENDLY_Razor Hill|r|cRXP_WARN_ Spirit Healer, "
             "then go to Gar'thok. If you die inside the cave you respawn in the Valley of Trials instead: hand in there first (the next steps appear)|r\n")
ANCHOR_RE = re.compile(r"step\n    #softcore\n    #completewith next\n    \.goto 1411/1,-4326\.01,-41\.23\n    \.deathskip >> [^\n]*\n    \.target Spirit Healer\n")

THAZZ = ("step\n"
         "    .goto 1411/1,-4322.31,-611.58\n"
         + BUBBLE + "|cRXP_FRIENDLY_Thazz'ril|r\n"
         "    .turnin 6394 >>Turn in Thazz'ril's Pick\n"
         "    .target Foreman Thazz'ril\n"
         "    .isQuestComplete 6394\n")
ZUREETHA = ("step\n"
            "    .goto 1411/1,-4228.19,-629.20\n"
            + BUBBLE + "|cRXP_FRIENDLY_Zureetha|r\n"
            "    .turnin 794 >>Turn in Burning Blade Medallion\n"
            "    .accept 805 >>Accept Report to Sen'jin Village\n"
            "    .target Zureetha Fargaze\n"
            "    .isQuestComplete 794\n")
HAND_OLD = THAZZ + ZUREETHA                   # first version: no gate
HAND_NEW = THAZZ + GATE + ZUREETHA + GATE     # current version

HS_OLDS = ["step\n    #completewith next\n    .hs >>Hearth to the Valley of Trials\n    .use 6948\n",
           "step\n    #completewith BurningBladeTurnin\n    .hs >>Hearth to the Valley of Trials\n    .use 6948\n"]   # 2nd: 1-7 variant in v4.11.9
HS_NEW = "step\n    .hs >>Hearth to the Valley of Trials\n    .use 6948\n    .cooldown item,6948,>2,1\n    .subzoneskip 363\n"

for ver in ("v4.11.9", "v4.11.13"):
    p = os.path.join(HERE, "installed-" + ver, REL.replace("/", os.sep))
    with open(p, "rb") as f:
        raw = f.read().decode("utf-8")
    crlf = "\r\n" in raw
    s = raw.replace("\r\n", "\n")
    done = []

    # 1) wording
    if DEATH_OLD in s:
        s = s.replace(DEATH_OLD, DEATH_NEW)
        done.append("death-skip text")

    # 2) hand-ins after the death-skip step
    out, pos, added, upgraded = [], 0, 0, 0
    for m in ANCHOR_RE.finditer(s):
        tail = s[m.end():]
        out.append(s[pos:m.end()])
        if tail.startswith(HAND_NEW):
            pos = m.end()
        elif tail.startswith(HAND_OLD):
            out.append(HAND_NEW)
            pos = m.end() + len(HAND_OLD)
            upgraded += 1
        else:
            out.append(HAND_NEW)
            pos = m.end()
            added += 1
    out.append(s[pos:])
    s = "".join(out)
    if added:
        done.append("hand-ins added x%d" % added)
    if upgraded:
        done.append("hand-ins gated x%d" % upgraded)

    # 3) hearth back stays until you hearth
    for HS_OLD in HS_OLDS:
        if HS_OLD in s:
            n = s.count(HS_OLD)
            s = s.replace(HS_OLD, HS_NEW)
            done.append("hearth step now blocks x%d" % n)

    with open(p, "wb") as f:
        f.write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))
    print(ver, "; ".join(done) if done else "already up to date")
