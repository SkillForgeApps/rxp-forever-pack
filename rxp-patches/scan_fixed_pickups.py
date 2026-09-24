"""Find RXP steps where several items/objects at FIXED spots share one step (Gaz 23 Sep 2026: "on item pick ups the
wp should not move on until the item has been picked up ... apply it across the board").
In such a step RXP marks each pass-through waypoint (`.goto x,y,r,0`) done as soon as you walk within r yards,
and a step with several plain `.goto`s only ever points at the first one - either way the arrow is not tied to
the item. The fix is one step per item: one `.goto x,y` (no radius) + that item's `.complete id,N`.
Kill-and-loot steps are excluded (their waypoints are a patrol route, moving on is right) and #loop steps too.
Run after every RXP update and after adding guide content:  python scan_fixed_pickups.py"""
import re, glob
ADDONS = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns"
files = glob.glob(ADDONS + r"\RXPGuides\Guides\forever\*.lua") + [ADDONS + r"\RXPForever\RXPForever.lua"]
n = 0
for f in files:
    s = open(f, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r'\nstep[^\n]*\n(.*?)(?=\nstep|\n\]\]|\Z)', s, re.S):
        body = m.group(1)
        if "#loop" in body:
            continue
        text = " ".join(re.findall(r'>>([^\n]*)', body))
        if re.search(r'\b(Kill|AoE|Slay|kill)\b', text) or not re.search(r'Loot|Collect|Pick up|Click|Grab|Open', text):
            continue
        gotos = re.findall(r'^\s*\.goto ', body, re.M)
        objs = set(re.findall(r'^\s*\.complete\s+(-?\d+),(\d+)', body, re.M))
        if len(gotos) >= 2 and len(objs) >= 2:
            n += 1
            print("%s:%d  %d waypoints, objectives %s  %s" % (f.split("\\")[-1], s[:m.start()].count("\n") + 2,
                                                               len(gotos), sorted(objs), text[:90]))
print("%d candidate step(s). Known OK: Alliance-11-20 Cave Mushrooms (947) - scattered ground spawns, area route." % n)
