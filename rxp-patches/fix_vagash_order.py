"""Make RXP's Dun Morogh guide accept Protecting the Herd (314) BEFORE sending you to pull Vagash.

RXP shows "Go up the dirt path" + "Kite Vagash down to Rudra" (both #completewith the accept step) above
"Talk to Rudra: Accept Protecting the Herd", intending you to accept mid-fight. Gaz and a friend followed the
top lines, killed Vagash twice with no quest and got no fang (the Fang of Vagash only drops while you're on the
quest). This moves the Rudra accept step in front of the dirt-path step and adds a warning. Applied to both copies
(6-11 Dun Morogh and the Hunter version). Idempotent."""
import sys

G = r"D:\World of Warcraft\_classic_beta_\Interface\AddOns\RXPGuides\Guides\forever\Alliance-1-14_DwarfGnome.lua"
s = open(G, encoding="utf-8").read()
if "#label VagashPull" in s:
    sys.exit("already applied")

old_head = """step
    #completewith Rudra
    #label Dirt
"""
old_accept = """step
    #label Rudra
    .goto 1426/0,-1304.71,-5513.86
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rudra Amberstill|r
    .accept 314 >> Accept Protecting the Herd
    .target Rudra Amberstill
"""
new_accept = """step
    #label Rudra
    .goto 1426/0,-1304.71,-5513.86
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Rudra Amberstill|r at the ranch FIRST
    >>|cRXP_WARN_Take this before you pull Vagash - the Fang of Vagash only drops if you're on the quest. Share it with your group|r
    .accept 314 >> Accept Protecting the Herd
    .target Rudra Amberstill
"""
n_head, n_acc = s.count(old_head), s.count(old_accept)
if n_head != n_acc or n_head == 0:
    sys.exit("unexpected layout: %d dirt steps, %d accept steps" % (n_head, n_acc))

out, pos, done = [], 0, 0
while True:
    i = s.find(old_head, pos)
    if i < 0:
        break
    j = s.find(old_accept, i)
    if j < 0:
        break
    between = s[i:j]            # dirt step + kite step, originally shown before the accept
    between = between.replace("#completewith Rudra\n    #label Dirt", "#completewith VagashPull\n    #label Dirt", 1)
    between = between.replace("    #completewith next\n    #requires Dirt", "    #completewith VagashPull\n    #requires Dirt", 1)
    out.append(s[pos:i])
    out.append(new_accept)       # accept first
    out.append(between)          # then the path and the kite
    out.append("step\n    #label VagashPull\n")   # the kill step now carries the label the pull steps finish with
    pos = j + len(old_accept)
    # the original kill step starts with "step\n" right after the accept; drop that one "step\n" (we just wrote it)
    if s.startswith("step\n", pos):
        pos += len("step\n")
    done += 1
out.append(s[pos:])
s = "".join(out)
open(G, "w", encoding="utf-8", newline="\n").write(s)
print("reordered %d Vagash section(s)" % done)
