# Changes made to RestedXP Guides v4.11.9

Every modified file is in `rxp-patches/v4.11.9`. The script that made each change is in `rxp-patches/`.

## `RXPGuides.lua`, `functions.lua` - gamepad lock-up fix (`patch_rxp_no_hideuipanel.py`)
Five `HideUIPanel(QuestFrame)` calls and one `HideUIPanel(MerchantFrame)` call are commented out. Called from addon
code they taint the UI panel manager. The game then blocks `SetPreferredGamepadInteractTarget()`, and controller
interaction (and sometimes chat) stops working until a reload. The quest and merchant windows still close normally.

## `map.lua` - no world-map flash (`patch_rxp_no_map_flash.py`)
Before drawing route lines RXP opened and shut the world map from addon code whenever the map had not been opened
yet (after every reload). That taints the gamepad UI the same way, so closing bags or windows with the controller
was blocked (`SetPreferredGamepadInteractTarget()`, blamed on RXPGuides). The lines are now skipped until you open
the map, and RXPForever draws them the first time it is open.

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
