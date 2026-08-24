# Barony Save Protector (macOS)

A robust, zero-configuration background service and launch wrapper for **Barony** on macOS. This script protects your save files from the game's strict perma-death mechanics by seamlessly intercepting death events and automatically resurrecting your characters, while correctly allowing you to permanently delete saves from the game's UI.

## Features

- **Seamless Steam Integration:** Runs automatically when you launch Barony through Steam. No need to start background scripts manually.
- **Deterministic Death Detection:** Parses the Barony engine's `log.txt` in real-time to definitively tell the difference between an in-game death and an intentional UI save deletion.
- **Ultra-Fast, Zero-Impact Polling:** Monitors your save files every 2 seconds without wasting CPU or I/O. It tracks the file's modification time (`mtime`) and only processes data when the game engine actually writes to the disk.
- **Automated Graveyard:** Every time a character dies, a permanent backup is archived in a `Graveyard` folder along with a clickable `Resurrect_Character.command` tool to easily restore them to an empty save slot.
- **The Fallen Chronicles:** Automatically maintains a lore-friendly text log of your fallen heroes, tracking their Cause of Death, Class, Race, Level, Floor reached, and total kills.
- **Smart Storage Limits:** Automatically prunes old backups and logs to prevent your hard drive from filling up. Keeps up to 10 rolling backups per active character, 100 total characters in the Graveyard, and 1200 lines in The Fallen Chronicles.
- **Fail-Safely Enforcement:** If the script cannot confidently determine why a save file vanished (e.g., the game crashed or the logs rotated), it defaults to resurrecting the character to ensure saves are never lost by mistake.

## Installation

1. On this GitHub page, click the green **Code** button and select **Download ZIP**.
2. Open your `Downloads` folder and unzip the file. It will create a folder called something like `Barony-main`.
3. Rename that folder to exactly **`Barony`**.
4. Open a new Finder window and drag your new `Barony` folder into your **Home Directory** (the folder with the house icon and your username).
   > [!WARNING]
   > **macOS Security Note:** Do **not** leave this folder in your `Documents`, `Desktop`, or `Downloads` folders. macOS strictly protects those directories, and Steam will be silently blocked from executing the script if it is placed there.

5. Open **Steam**.
6. Right-click **Barony** in your library and select **Properties...**
7. In the **General** tab, scroll down to **Launch Options**.
8. Paste the following command. 
   > [!IMPORTANT]
   > If you placed the script anywhere other than `~/Barony`, you **must** update the `/Users/YOUR_USERNAME/Barony/...` path in this command to match exactly where you put it, or it will not run!
   
   ```text
   /bin/bash "/Users/YOUR_USERNAME/Barony/barony_backup.sh" %command%
   ```

## Usage

### Playing the Game
Just launch Barony from Steam. You will receive a macOS notification letting you know the Save Protector is active. Play the game normally! 

- If you **die**, you will receive a notification that your character was saved. The save file will be instantly restored to the main menu.
- If you **delete a save manually** from the Barony main menu, the script will permanently delete the backups for that slot.

### The Graveyard
The script automatically generates a `Graveyard` folder in the same directory as the script. 
- Inside you'll find `Solo_Runs` and `Multiplayer_Runs` containing permanent backups of every death. 
- You'll also find `The_Fallen_Chronicles.txt` which tracks the stats and causes of death for every fallen hero.

### Automatic Resurrection (Default)
When your character dies, the script automatically catches it and instantly restores the save file to the next available empty slot in your game. 
- You do not need to do anything manually. The character will be waiting for you in the menu.
- A permanent copy is also sent to the `Graveyard` for your records.

### Manual Resurrection (For Old Characters)
If you ever want to replay an *older* dead character that has been archived in your Graveyard:
1. **Fully quit Barony.** (The engine will overwrite the save if you do this while the game is running).
2. Open the `Graveyard` folder and double-click the `Resurrect_Character.command` file.
3. Select the old character's `.baronysave` file from the prompt.
4. The character will be restored to the next available empty save slot.

## Requirements
- macOS (Compatible with Apple Silicon / Rosetta and Intel)
- Steam installation of Barony
- Standard macOS Python 3 installation (used for fast JSON and log parsing)

## Technical Details
This script is explicitly designed to bypass the macOS Steam Sandbox and handles execution handoffs cleanly to preserve the native Steamworks environment. It strictly conforms to macOS's default Bash 3.2 constraints and uses atomic file operations to prevent data corruption during power loss.

## Uninstallation
If you ever want to stop using the Save Protector:
1. Open Steam, go to Barony's **Properties** > **General**.
2. Delete the command from the **Launch Options** text box.
3. The game will now launch normally. You can safely delete the `Barony` folder from your Mac if you no longer want the Graveyard backups.

## Acknowledgments
- **Turning Wheel LLC** for creating [Barony](https://www.baronygame.com/), an incredible and unforgiving dungeon crawler.
- **Tink and JewcyJay** for the invaluable help with multiplayer testing and debugging.
- **Google Antigravity** for assisting with the code review of this project.

---
*Created by **Raven Lord** — Happy dungeon crawling!*
