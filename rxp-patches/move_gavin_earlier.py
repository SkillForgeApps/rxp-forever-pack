"""Move the Father Gavin chain earlier in RXP's 06-11 Dun Morogh guide (Gaz 23 Sep: "it needs to be early").
Dawn in the Mountains pickup: from after the level-10 First Aid step -> right after the Thunder Ale barrel step
(Kharanos inn, where Maxan Anvol stands). Gavin block: from just before Rudra -> right after the Kharanos hand-ins
that end with Frosthowl (after Shimmer Ridge, ~level 9, before the trip west to Gnomeregan / Frostmane Hold).
Only the main 06-11 guide is changed; the Hunter copy keeps its block before Rudra. Step count unchanged."""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Alliance-1-14_DwarfGnome.lua"
s = open(G, encoding="utf-8").read()
if "#label GavinEarly" in s:
    sys.exit("already moved")
hunter_at = s.find("#name 6-11 Dun Morogh (Hunter)")
main, rest = s[:hunter_at], s[hunter_at:]

# the Dawn pickup step as inserted by add_gavin_and_saddle.py
d0 = main.find("step\n    .goto Dun Morogh,47.2,52.2\n")
d1 = main.find("\nstep", d0 + 5) + 1
dawn = main[d0:d1]
assert "Accept Dawn in the Mountains" in dawn, "dawn block"
main = main[:d0] + main[d1:]

# the Gavin block: from the Dawn turn-in step up to (not including) the Rudra step
g0 = main.find("step\n    .goto Dun Morogh,57.4,44.8\n    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Father Gavin|r in the old building")
g1 = main.find("step\n    #label Rudra\n", g0)
assert g0 > 0 and g1 > g0, "gavin block"
gavin = main[g0:g1]
main = main[:g0] + main[g1:]
gavin = gavin.replace("step\n    .goto Dun Morogh,57.4,44.8\n", "step\n    #label GavinEarly\n    .goto Dun Morogh,57.4,44.8\n", 1)
gavin = gavin.replace("in the old building in the hills", "in the old building in the hills north-east of Kharanos", 1)
dawn = dawn.replace("(Forever quest - opens Father Gavin's 2,100 XP chain)",
                    "(Forever quest - opens Father Gavin's 2,100 XP chain, done after Shimmer Ridge)")

def after_step(text, anchor, block):
    i = text.find(anchor)
    assert i > 0 and text.count(anchor) == 1, "anchor %r x%d" % (anchor[:40], text.count(anchor))
    j = text.find("\nstep", i) + 1
    return text[:j] + block + text[j:]

main = after_step(main, "    .accept 311 >> Accept Return to Marleth\n", dawn)
main = after_step(main, "    .turnin -98326 >> Turn in Frosthowl\n", gavin)
open(G, "w", encoding="utf-8", newline="\n").write(main + rest)
print("moved: Dawn pickup + Gavin block (%d chars)" % len(gavin))
