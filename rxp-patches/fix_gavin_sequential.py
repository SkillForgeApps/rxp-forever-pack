"""Make the Father Gavin chain sequential (Gaz, 23 Sep 2026: after turning in Dawn he was offered ONLY Finding
Warmth - Rime's Wrath and Treacherous Cold were not in his log, so the old step that accepted 99159+99160+99162
at once could never complete and the guide stalled / scrolled past it).

New order: accept Finding Warmth -> firewood (#label GavinFirewood) -> hand it in and take whatever Gavin offers
next (Rime's Wrath, Treacherous Cold) -> elementals -> hand in, take Rime's Wrath part 2 -> Avala -> rifles ->
final hand-ins. Accepts that depend on an earlier hand-in carry a "click to skip if not offered" warning, because
the exact unlock order for 99160/99162 isn't published.
Applied to both copies in Alliance-1-14_DwarfGnome.lua, its PATCHED mirror, and the standalone guide in
RXPForever.lua (source + installed). Idempotent."""
import sys

B = "|Tinterface/worldmap/chatbubble_64grey.blp:20|t"
FILES = [r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Alliance-1-14_DwarfGnome.lua",
         r"D:\wow-forever-addons\rxp-forever\patches\Alliance-1-14_DwarfGnome.PATCHED.lua",
         r"D:\wow-forever-addons\rxp-forever\RXPForever\RXPForever.lua",
         r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPForever\RXPForever.lua"]

START = f"""step
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r
    .accept 99159 >> Accept Finding Warmth
    .accept 99160 >> Accept Rime's Wrath
    .accept 99162 >> Accept Treacherous Cold
"""
END = """    .turnin -99162 >> Turn in Treacherous Cold
    .target Father Gavin
"""

NEW = f"""step
    #label GavinWarmth
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r
    .accept 99159 >> Accept Finding Warmth
    .target Father Gavin
    .isQuestTurnedIn 99158
step
    #label GavinFirewood
    .goto Dun Morogh,55.4,44.6,40,0
    .goto Dun Morogh,53.4,43.8,40,0
    .goto Dun Morogh,56.4,46.8,40,0
    >>Pick up |cRXP_LOOT_Mostly Dry Firewood|r around Father Gavin - the white trunks on the ground next to trees (some give 2)
    .complete -99159,1 --Mostly Dry Firewood (14)
step
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r
    >>|cRXP_WARN_If he doesn't offer one of these, click this step to move on|r
    .turnin -99159 >> Turn in Finding Warmth
    .accept 99160 >> Accept Rime's Wrath
    .accept 99162 >> Accept Treacherous Cold
    .target Father Gavin
    .isQuestTurnedIn 99158
step
    #label GavinElementals
    .goto Dun Morogh,55.4,44.6,40,0
    .goto Dun Morogh,53.4,43.8,40,0
    .goto Dun Morogh,56.4,46.8,40,0
    >>Kill |cRXP_ENEMY_Minor Ice Elementals|r around Father Gavin
    .complete -99160,1 --Minor Ice Elemental slain (10)
    .mob Minor Ice Elemental
step
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r
    >>|cRXP_WARN_If he doesn't offer these, click this step to move on|r
    .turnin -99160 >> Turn in Rime's Wrath
    .accept 99161 >> Accept Rime's Wrath
    .accept 99162 >> Accept Treacherous Cold
    .target Father Gavin
    .isQuestTurnedIn 99159
step
    .goto Dun Morogh,58.2,42.6
    >>Kill |cRXP_ENEMY_Avala|r, the large ice elemental just north-east of Father Gavin. Loot its |cRXP_LOOT_Core|r
    .complete -99161,1 --Avala's Core (1)
    .mob Avala
step
    .goto Dun Morogh,52.0,44.0,15,0
    .goto Dun Morogh,53.0,59.0,15,0
    .goto Dun Morogh,60.0,50.0,15,0
    >>Collect the three rifles lying next to fallen mountaineers:
    >>|cRXP_LOOT_Coalbeard's Rifle|r - follow the frozen river west, under the tree fallen across it
    >>|cRXP_LOOT_Stoneanvil's Rifle|r - in the valley to the south, next to a cart
    >>|cRXP_LOOT_Sunhammer's Rifle|r - next to a cart on the small path up to Vagash's cave
    .complete -99162,1
    .complete -99162,2
    .complete -99162,3
step
    .goto Dun Morogh,57.4,44.8
    >>{B}Talk to |cRXP_FRIENDLY_Father Gavin|r
    .turnin -99161 >> Turn in Rime's Wrath
    .turnin -99162 >> Turn in Treacherous Cold
    .target Father Gavin
"""

for path in FILES:
    s = open(path, encoding="utf-8").read()
    if "#label GavinFirewood" in s:
        print("already done:", path)
        continue
    out, pos, n = [], 0, 0
    while True:
        i = s.find(START, pos)
        if i < 0:
            break
        j = s.find(END, i)
        assert j > 0, "no end marker in " + path
        out += [s[pos:i], NEW]
        pos = j + len(END)
        n += 1
    if n == 0:
        sys.exit("start marker not found in " + path)
    out.append(s[pos:])
    open(path, "w", encoding="utf-8", newline="\n").write("".join(out))
    print("rewrote %d Gavin block(s): %s" % (n, path))

# Follow-up 23 Sep ~21:30 (done inline, already applied to all four files): the firewood and elemental steps got
# `#loop` + map pins (`.goto Dun Morogh,x,y,0`) in front of the three 40-yd points. Without #loop RXP marks each
# point done once you pass it and then drops the arrow (Gaz: "lost the waypoint arrow", firewood 7/14).
