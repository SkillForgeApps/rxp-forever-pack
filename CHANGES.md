# Changes made to RestedXP Guides v4.11.9

Every modified file is in `rxp-patches/v4.11.9`. The script that made each change is in `rxp-patches/`.

## `RXPGuides.lua`, `functions.lua` - gamepad lock-up fix (`patch_rxp_no_hideuipanel.py`)
Five `HideUIPanel(QuestFrame)` calls and one `HideUIPanel(MerchantFrame)` call are commented out. Called from addon
code they taint the UI panel manager. The game then blocks `SetPreferredGamepadInteractTarget()`, and controller
interaction (and sometimes chat) stops working until a reload. The quest and merchant windows still close normally.

## `RXPGuides.lua` - quest reward icon outside the quest window (`patch_rxp_reward_icon_parent.py`)
RXP's best-reward icon created its frame inside the quest reward window. With the gamepad UI on, Blizzard's gamepad
navigation refreshes itself whenever a frame is created inside an open window, so that refresh ran in addon code and
the navigation stayed tainted until a reload: closing windows or bags with the controller then failed
(`SetPreferredGamepadInteractTarget()`, blamed on RXPGuides). Found with `/console taintLog 11`. The icon's frame now
sits on the main UI, over the reward button, and looks the same.

## `map.lua` - no world-map flash (`patch_rxp_no_map_flash.py`)
Before drawing route lines RXP opened and shut the world map from addon code whenever the map had not been opened
yet (after every reload). That taints the gamepad UI the same way, so closing bags or windows with the controller
was blocked (`SetPreferredGamepadInteractTarget()`, blamed on RXPGuides). The lines are now skipped until you open
the map, and RXPForever draws them the first time it is open.

## `InventoryManager.lua` - bags and the gamepad UI (`patch_rxp_no_bag_updateall.py`)
RXP's junk-coin marker refreshed every bag window from addon code shortly after each bag opened. With the gamepad UI
on, that blocked the controller (`SetOverrideBindingClick`, blamed on RXPGuides) until a reload. The coins are now drawn
straight onto the bag slots instead.

## `libs/HereBeDragons/HereBeDragons-Pins-2.0.lua` - world-map icons (`patch_hbd_worldmap_overlay.py`)
RestedXP's world-map icons were Blizzard map pins created from addon code; every map open then ran addon code inside
Blizzard's map and tainted the gamepad UI. The icons are now drawn on RestedXP's own overlay above the map and look the same.

## `Guides/forever/Horde-01-12_Durotar.lua` - Durotar
- **Valley hand-ins** (`add_durotar_valley_handins.py`): if the Skull Rock death-skip respawns you in the Valley of Trials,
  hand in *Thazz'ril's Pick* and the *Burning Blade Medallion* there, then hearth back; the step text explains both respawns.
- **Profession manual** (`add_profession_reminders_dur_undead.py`): pick the profession-manual reward from Galgar's quest, and
  buy a pick or knife at the next vendor.

## `Guides/forever/Horde-12-22_Barrens.lua` - The Barrens (`fix_barrens_mudsnapper.py`)
Innkeeper Wiley's step in Ratchet no longer needs 20 Longjaw Mud Snappers (he doesn't stock them on Forever) - it completes
when you visit him.

## `Guides/forever/Alliance-1-14_DwarfGnome.lua` - Dun Morogh (both the normal and the Hunter guide)
- **Camping 101** (`add_camping101.py`): the Cooking quest from Eric Brighthammer and the profession quests at the
  campfire, each only if you have that profession, with their hand-ins in Kharanos/Iceflow and Ironforge.
- **Vagash** (`fix_vagash_order.py`): accept *Protecting the Herd* from Rudra **before** the "go up the path / kite
  Vagash" steps. The Fang of Vagash only drops while you are on the quest.
- **Father Gavin's chain** (`add_gavin_and_saddle.py`, `move_gavin_earlier.py`, `fix_gavin_sequential.py`): Dawn in the
  Mountains -> Finding Warmth -> Rime's Wrath (x2) + Treacherous Cold. The chain is offered one quest at a time. The
  firewood and elemental areas use looping waypoints, and each rifle gets its own step with its own waypoint.
- **Never Saddle on Quality**: accepted with Rudra, pelts from Elder Snow Leopards, handed back to Rudra.
- **The Quarry's Smith** (`add_quarry_smith.py`): Frast Dokner at Gol'Bolar Quarry, boar hides with the leopards, hand-in
  skipped automatically if you don't have the Copper Bars.

## `Guides/forever/Horde-1-12_Mulgore.lua` - Camp Narache (`fix_narache_waypoint.py`)
Chief Hawkwind's hand-ins (Attack on Camp Narache, Rite of Strength) each get their own waypoint. The single waypoint
used to disappear once *Rites of the Earthmother* was accepted, even with quests still to hand in.

- **Camp Taurajo** (`fix_mulgore_barrens_text.py`): the "travel to The Barrens" step now says Camp Taurajo is just over
  the border east of Mulgore.
- **Kaga Wildhoof** (`add_mulgore_adventurer.py`, `add_mulgore_camping101.py`): *The Adventurer* and *The Great Outdoors*,
  then the Camping 101 profession quests, with their hand-ins at the Bloodhoof and Thunder Bluff trainers.
- **Profession manual and Seer Graytongue:** pick the profession-manual reward at Greatmother Hawkwind; shamans are told
  which of Seer Graytongue's quests to skip.
- **Thunder Bluff visit** (`add_tb_fp_mulgore.py`): Tauren don't start with the Thunder Bluff flight path on Forever, so
  after *A Sacred Burial* the guide takes you up into Thunder Bluff: flight path from Tal, *Journey into Thunder Bluff*
  to Cairne, then back down. The later "fly to Thunder Bluff" step works after that.

## `Guides/forever/Horde-Mage-12-21.lua` - Samophlange valves
The Regulator and Main Control valves are split into one step each. A step with two fixed-spot objectives only ever
pointed the arrow at the first one.

## `Guides/forever/Horde-01-14_Undead.lua` - Tirisfal Glades (Undead)
- **Undead Paladin class quests** (`undead_paladin_quests.py`): *Rediscovering the Light* (heal 5 Injured Deathguard
  around Deathknell's chapel) is back in the guide - it unlocks *Coming to Terms*, which the guide asked for but could
  never be offered without it. The chain now runs Rediscovering the Light -> Coming to Terms (the Frightened Paladin,
  with a waypoint) -> Continue Your Training. Each part is its own step that only shows when it applies, so skipping
  one never blocks the guide.
- **Camping 101** (`add_camping101_undead.py`): after *The Great Outdoors*, Eleanor Shackleton's Camping 101 quests -
  Cooking (learn it from William Pickman in Brill) and one per profession, each only if you have that profession, with
  the hand-ins at the Brill, Undercity-road and Undercity trainers once you reach skill 20.
- **Cooking and Mining** (`add_cooking_mining_undead.py`): like the Dun Morogh guide in Coldridge - loot Stringy Wolf
  Meat from the Darkhounds and Worgs you pass and cook Charred Wolf Meat to Cooking 50, and mine the Copper Veins you
  pass to Mining 20 while you're on Camping 101: Mining.
- **Brill book** (`add_metabook_waypoint.py`): the "loot the Book in the shelf" step gets a waypoint - the Alchemy
  trainer's house as you enter Brill, potion shelf on the right.
- **Sevren on the way** (`add_sevren_on_the_way.py`): hand in *Return to the Magistrate* in Brill on the way to
  Agamand Mills instead of after it.
- **Undercity sewers** (`add_sewer_entrance.py`): the "go into the Undercity through the sewers" arrow starts at the
  sewer entrance outside, not at a point inside the tunnel.
- **Skull Rock** (`fix_skull_rock_waypoint.py`): the *Hidden Enemies* step (Lieutenant's Insignia) had one waypoint
  written so that RXP never shows an arrow for it. It now uses RXP's own nine-point route through Skull Rock from the
  Barrens guide.
- **A Lesson in Divinity** (`add_lesson_in_divinity.py`): the Undead Paladin chain is finished - Danitha Morr at Bandarion
  Keep, Venomweb Vale and back, ending with Redemption (RestedXP accepted part 5 and never came back).
- **Lich chain** (`add_lich_chain.py`): *The Prodigal Lich* and *The Lich's Identity* for every Undead while they still give XP.
- **Profession manual** (`add_profession_reminders_dur_undead.py`): the profession-manual reward from Marla's Last Wish.
