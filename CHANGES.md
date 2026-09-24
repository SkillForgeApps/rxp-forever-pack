# Changes made to RestedXP Guides v4.11.9

Every modified file is in `rxp-patches/v4.11.9`. The script that made each change is in `rxp-patches/`.

## `RXPGuides.lua`, `functions.lua` - gamepad lock-up fix (`patch_rxp_no_hideuipanel.py`)
Five `HideUIPanel(QuestFrame)` calls and one `HideUIPanel(MerchantFrame)` call are commented out. Called from addon
code they taint the UI panel manager. The game then blocks `SetPreferredGamepadInteractTarget()`, and controller
interaction (and sometimes chat) stops working until a reload. The quest and merchant windows still close normally.

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
