"""RXP forever/Horde-1-12_Mulgore.lua, Camp Narache hand-in step (both 1-6 and 1-7 copies). Gaz 24 Sep on
A Tauren character: "step 28 no waypoint". A `.goto` with no radius is tied to the objective line above it and counts
as reached once that objective is done; Hawkwind's only goto sat under `.accept 763`, so with 763 done and 781 (Attack
on Camp Narache, from the map on the cave floor) still to hand in there was no arrow. Fix: a goto under each Hawkwind
objective. Re-run after an RXP update. Idempotent."""
p = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Horde-1-12_Mulgore.lua"
G = "    .goto 1412/1,-221.83,-2878.31\n"
old = ("    .turnin 781 >>Turn in Attack on Camp Narache\n    .turnin 757 >>Turn in Rite of Strength\n"
       "    .accept 763 >>Accept Rites of the Earthmother\n")
new = ("    .turnin 781 >>Turn in Attack on Camp Narache\n" + G + "    .turnin 757 >>Turn in Rite of Strength\n" + G +
       "    .accept 763 >>Accept Rites of the Earthmother\n")
s = open(p, encoding="utf-8").read()
print("patched %d" % s.count(old)); s = s.replace(old, new)
open(p, "w", encoding="utf-8", newline="\n").write(s)
