"""Forever early-profession reminders for Durotar (Galgar's Cactus Apple Surprise) and Tirisfal (Marla's Last Wish).

The quest reward is a pick-one of Mining for Dummies / Pelt Collecting for Beginners / Wild Harvest (+2 skill, teaches the
profession if you have fewer than two). Adds a yellow "pick your reward" line at the hand-in and a "buy a pick / knife" line at the
vendor step right after it. Run from the repo root:  python rxp-forever/patches/add_profession_reminders_dur_undead.py
Durotar is RXP's own file (taken from each release zip, patched, then added to that version's manifest);
Undead is our already-patched copy in installed-vX. Safe to run twice (skips a file that already has the reminder).
Afterwards run refresh_manifest.py <version> for both versions.
"""
import hashlib
import json
import os
import zipfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUR = "RXPGuides/Guides/forever/Horde-01-12_Durotar.lua"
UND = "RXPGuides/Guides/forever/Horde-01-14_Undead.lua"
BUBBLE = "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to "
PICK = ("    >>|cRXP_WARN_Pick your reward: |r|cRXP_LOOT_Mining for Dummies|r|cRXP_WARN_, |r|cRXP_LOOT_Pelt Collecting for Beginners|r"
        "|cRXP_WARN_ (Skinning) or |r|cRXP_LOOT_Wild Harvest|r|cRXP_WARN_ (Herbalism), then right-click it to learn the profession "
        "(+2 skill). If you already know a profession, pick that one|r\n")
BUY = ("    >>|cRXP_WARN_If you took Mining or Skinning, buy a|r |T134708:0|t[Mining Pick] |cRXP_WARN_or|r |T134366:0|t[Skinning Knife] "
       "|cRXP_WARN_from %s if %s stocks it. Herbalism needs no tool|r\n")
GALGAR = BUBBLE + "|cRXP_FRIENDLY_Galgar|r\n"
GALGAR_TURNIN = "    .turnin 4402 >>Turn in Galgar's Cactus Apple Surprise\n"
DUOKNA = BUBBLE + "|cRXP_FRIENDLY_Duokna|r\n"
ELRETH = BUBBLE + "|cRXP_FRIENDLY_Elreth|r and |cRXP_FRIENDLY_Duesten|r << Priest\n"
MARLA_TURNIN = "    .turnin 6395 >> Turn in Marla's Last Wish\n"
ARREN = "    .target Executor Arren\nstep\n    .goto 1420/0,1568.35,1859.49\n"
ARCHIBALD = BUBBLE + "|cRXP_FRIENDLY_Archibald|r\n"


def sha(b):
    return hashlib.sha256(b).hexdigest().upper()


def text(raw):
    s = raw.decode("utf-8")
    return s.replace("\r\n", "\n"), "\r\n" in s


def back(s, crlf):
    return (s.replace("\n", "\r\n") if crlf else s).encode("utf-8")


def durotar(raw):
    # every Galgar turn-in gets the reward line; the Duokna vendor step right after it (if any) gets the tool line
    s, crlf = text(raw)
    if "Mining for Dummies" in s:
        return raw
    old = GALGAR + GALGAR_TURNIN
    assert s.count(old) >= 2, s.count(old)
    out, pos = [], 0
    while True:
        i = s.find(old, pos)
        if i < 0:
            break
        out.append(s[pos:i] + GALGAR + PICK + GALGAR_TURNIN)
        pos = i + len(old)
        j = s.find(DUOKNA, pos)
        if 0 <= j - pos < 600:
            out.append(s[pos:j] + DUOKNA + BUY % ("Duokna", "she"))
            pos = j + len(DUOKNA)
    out.append(s[pos:])
    return back("".join(out), crlf)


def undead(raw):
    s, crlf = text(raw)
    if "Mining for Dummies" in s:
        return raw
    a = ELRETH + MARLA_TURNIN
    b = ARREN + ARCHIBALD
    assert s.count(a) == 1 and s.count(b) == 1, (s.count(a), s.count(b))
    s = s.replace(a, ELRETH + PICK + MARLA_TURNIN)
    s = s.replace(b, b + BUY % ("Archibald", "he"))
    return back(s, crlf)


for ver in ("v4.11.9", "v4.11.13"):
    d = os.path.join(HERE, "installed-" + ver)
    man_path = os.path.join(d, "manifest.json")
    man = json.load(open(man_path))
    orig = zipfile.ZipFile(os.path.join(HERE, "staging", "RXPGuides-%s.zip" % ver)).read(DUR)
    new = durotar(orig)
    p = os.path.join(d, DUR.replace("/", os.sep))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        f.write(new)
    entry = next((f for f in man["files"] if f["path"] == DUR), None)
    if entry is None:
        man["files"].append({"path": DUR, "original": sha(orig), "patched": sha(new), "previous": []})
    up = os.path.join(d, UND.replace("/", os.sep))
    with open(up, "rb") as f:
        patched = undead(f.read())          # read fully BEFORE opening for write ("wb" truncates)
    with open(up, "wb") as f:
        f.write(patched)
    with open(man_path, "w", newline="\n") as f:
        json.dump(man, f, indent=2)
    print(ver, "durotar", sha(new)[:12], "undead", sha(patched)[:12])
