"""Mulgore: Forever's Camping 101 profession quests (Tauren set), from Kaga Wildhoof after The Great Outdoors (96605).

Pickups at Kaga (npc 265810, Mulgore 46.2,67.2), after the Great Outdoors hand-in step added by add_mulgore_adventurer.py:
  Cooking 96661 (everyone), and gated on having the profession (.skill <key>,<1,1 like the Undead/Dun Morogh patches):
  First Aid 97931, Fishing 97932, Herbalism 97933, Leatherworking 97934, Mining 97935, Skinning 97936. 270 XP each; objective: raise the skill to 20.
Hand-ins (Wowhead Forever "End:" NPCs), each gated .isQuestComplete so they only show once skill 20 is reached:
  Bloodhoof Village (Mulgore 1412): Pyall Silentstride 45.4,58 (Cooking), Vira Younghoof 46.8,60.8 (First Aid), Uthan Stillwater 44.4,60.6 (Fishing),
    Chaw Stronghide 45.4,57.8 (Leatherworking), Yonn Deepcut 45.4,57.8 (Skinning)  -> before the 'delete Prospector's Picks' step that follows the Bloodhoof turn-ins
  Thunder Bluff (1456): Brek Stonehoof 34.6,57.6 (Mining), Komin Winterhoof 49.8,39.8 (Herbalism) -> after the Cairne "Rites of the Earthmother" step
Applies to BOTH Mulgore variants in installed-v4.11.9 and installed-v4.11.13. Run from the repo root, then refresh_manifest.py for both. Safe to run twice.
"""
import os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REL = "RXPGuides/Guides/forever/Horde-1-12_Mulgore.lua"
BUBBLE = "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to "
KAGA_END = ("    .turnin 96605 >>Turn in The Great Outdoors\n"
            "    .target Kaga Wildhoof\n")


def pickup(qid, name, key, trainer):
    gate = "" if key is None else "    .skill %s,<1,1 -- only if you have %s\n" % (key, name)
    return ("step\n"
            "    .goto 1412,46.2,67.2\n"
            + BUBBLE + "|cRXP_FRIENDLY_Kaga|r: Camping 101 for your %s - raise it to 20, then hand it in to |cRXP_FRIENDLY_%s|r\n" % (name, trainer)
            + "    .accept %d >>Accept Camping 101: %s\n" % (qid, name)
            + "    .target Kaga Wildhoof\n"
            "    .isQuestTurnedIn 96605\n" + gate)


def handin(qid, name, npc, mapid, x, y, extra=""):
    return ("step\n"
            "    .goto %s,%s,%s\n" % (mapid, x, y)
            + BUBBLE + "|cRXP_FRIENDLY_%s|r\n" % npc
            + extra
            + "    .turnin %d >>Turn in Camping 101: %s\n" % (qid, name)
            + "    .target %s\n" % npc
            + "    .isQuestComplete %d\n" % qid)


PICKUPS = (pickup(96661, "Cooking", None, "Pyall Silentstride") +
           pickup(97931, "First Aid", "firstaid", "Vira Younghoof") +
           pickup(97932, "Fishing", "fishing", "Uthan Stillwater") +
           pickup(97933, "Herbalism", "herbalism", "Komin Winterhoof") +
           pickup(97934, "Leatherworking", "leatherworking", "Chaw Stronghide") +
           pickup(97935, "Mining", "mining", "Brek Stonehoof") +
           pickup(97936, "Skinning", "skinning", "Yonn Deepcut"))

BLOODHOOF = (handin(96661, "Cooking", "Pyall Silentstride", 1412, 45.4, 58, "    .train 2550 >>Train |T133971:0|t[Cooking]\n") +
             handin(97931, "First Aid", "Vira Younghoof", 1412, 46.8, 60.8) +
             handin(97932, "Fishing", "Uthan Stillwater", 1412, 44.4, 60.6) +
             handin(97934, "Leatherworking", "Chaw Stronghide", 1412, 45.4, 57.8) +
             handin(97936, "Skinning", "Yonn Deepcut", 1412, 45.4, 57.8))
THUNDER = (handin(97935, "Mining", "Brek Stonehoof", 1456, 34.6, 57.6) +
           handin(97933, "Herbalism", "Komin Winterhoof", 1456, 49.8, 39.8))

BLOODHOOF_ANCHOR = "step\n    #completewith AlphaTeeth\n    .destroy 4702 >>"   # the step right after the Bloodhoof turn-ins, both variants
TB_ANCHOR = "    .accept 776 >>Accept Rites of the Earthmother\n    .target Cairne Bloodhoof\n"

for ver in ("v4.11.9", "v4.11.13"):
    p = os.path.join(HERE, "installed-" + ver, REL.replace("/", os.sep))
    with open(p, "rb") as f:
        raw = f.read().decode("utf-8")
    crlf = "\r\n" in raw
    s = raw.replace("\r\n", "\n")
    if "96661" in s:
        print(ver, "already patched")
        continue
    kaga_n, bh_n, tb_n = s.count(KAGA_END), s.count(BLOODHOOF_ANCHOR), s.count(TB_ANCHOR)
    assert kaga_n == 2 and bh_n == 2 and tb_n >= 1, (kaga_n, bh_n, tb_n)
    s = s.replace(KAGA_END, KAGA_END + PICKUPS)
    s = s.replace(BLOODHOOF_ANCHOR, BLOODHOOF + BLOODHOOF_ANCHOR)
    s = s.replace(TB_ANCHOR, TB_ANCHOR + THUNDER)
    with open(p, "wb") as f:
        f.write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))
    print(ver, "patched (Kaga %d, Bloodhoof %d, Thunder Bluff %d)" % (kaga_n, bh_n, tb_n))
