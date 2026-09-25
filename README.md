# RXP Forever pack

Makes [RestedXP Guides](https://github.com/RestedXP/RXPGuides) work properly on the **WoW Forever beta**, plus a set of
guide fixes and Forever quests.

## Why you need it

The Forever beta client **writes addon saved data but never reads it back**. So every time you `/reload` or log in,
RestedXP forgets your guide, your step and your settings. This pack puts that data back for you, automatically.

## What you get

- **Your guide position survives every reload and login.** A small background helper copies RestedXP's saved data
  back into the game each time WoW saves. Your settings (font size, scale, options) are kept too.
- **Catch-up:** `/rxpcatchup` reads your quest log and jumps the guide to the first step you still need.
- **Smarter skipping:** travel steps (fly, hearth, zeppelin) are skipped when you already have what they were going for.
  "Only on this continent" checks work.
- **Trainer automation on:** RestedXP buys the guide's spells when you open a class trainer (its own option,
  which is off by default; switch it off in RestedXP's options if you prefer).
- **Auto hand-in for any finished quest the guide covers**, even when the hand-in step isn't the current one.
- **Guide edits don't lose your place.** Your step is remembered by what it is, not by line number.
- **Fold the step list:** a -/+ button on the guide-name bar hides the step list and keeps the current-step box
  (handy in dungeons). Remembered per guide.
- **A one-line summary of the current step under the waypoint arrow**, e.g. *Talk to Tundra MacGrann in the hut*.
- **Emergency reload button** by the minimap, plus **Ctrl+Shift+R**, for when the controller or chat stops responding.
- **Gamepad UI on/off icon** under it, plus **Ctrl+Shift+G**: switches Blizzard's Gamepad UI on or off and reloads in one
  click, instead of going through the settings.
- **Mouse buttons with the Gamepad UI on:** trainer, mailbox, quest, gossip, loot, bags, map and other windows keep their
  Train / Send / Reply / Accept / close buttons, so you can click them as well as using the controller.
- **Dungeon quest guides:** *Ragefire Chasm* and *Ruins of Lordaeron* (Horde). They start from wherever you are and only
  send you where you still need to go.
  While one is active, all its quests in your log are ticked to show on the quest tracker, including ones Blizzard
  doesn't track by itself (quests with no counter, like *A Frightened Request*).
- **Guide fixes for RestedXP v4.11.9:**
  - **Dun Morogh:** Father Gavin's chain (Dawn in the Mountains, Finding Warmth, Rime's Wrath, Treacherous Cold), Never
    Saddle on Quality, The Quarry's Smith and the Camping 101 profession quests.
  - **Vagash:** take Rudra's quest *before* pulling him (you get no fang otherwise).
  - **Pickups:** one step per rifle for the rifle pickups.
  - **Mulgore:** Camp Narache waypoint.
  - **Horde mage:** Samophlange valves.
  - **Gamepad:** a fix for the gamepad "interact" lock-up that RestedXP could trigger.

## Install

1. Install **RestedXP Guides** first (CurseForge or Wago). The guide fixes are built for **v4.11.9**; on any other
   version they're skipped and everything else still works.
2. Download this pack: green **Code** button → **Download ZIP**. Extract it anywhere.
3. Double-click **`install.bat`**.
   - It finds your WoW Forever folder by itself, or asks you to pick it (the folder with `Interface` and `WTF` in it,
     e.g. `...\World of Warcraft\_classic_beta_`).
   - Windows may ask whether to run it. It's a plain PowerShell script you can read first: `install.ps1`.
4. In game: `/reload`.

The helper starts hidden every time you log in to Windows. Its log is at `%LOCALAPPDATA%\RXPForeverSync\sync.log`.
Nothing is sent anywhere. It only reads WoW's saved files and writes two addon files on this PC.

## Update

Download the new ZIP and run `install.bat` again. Your saved data is kept.

## Uninstall

Right-click `uninstall.ps1` → **Run with PowerShell**. It stops and removes the helper, puts RestedXP's original files
back, and removes the two addons. RestedXP itself stays installed.

## What's in here

| Folder | What |
|---|---|
| `AddOns/RXPForever` | The main addon: catch-up, position restore, travel skip, auto hand-in, arrow summary, dungeon guides |
| `AddOns/!ForeverSV` | Puts saved data back when the client loads empty; emergency reload button |
| `sync/ForeverSync.ps1` | The background helper |
| `rxp-patches/v4.11.9` | The modified RestedXP files + `manifest.json` (fingerprints of the originals and the patched files) |
| `rxp-patches/*.py` | The scripts that made each change, for reference |

## Credits and licence

Built on **RestedXP Guides** by the RestedXP team, used under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). The files in `rxp-patches/v4.11.9` are
modified copies of RestedXP files; the changes are listed in [CHANGES.md](CHANGES.md). The rest of this pack is released
under the same licence: free to use, share and change, not for commercial use, keep the licence and credit.
Not affiliated with RestedXP or Blizzard.
