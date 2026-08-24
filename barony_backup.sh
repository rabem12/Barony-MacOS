#!/bin/bash
# ==========================================
# Barony Save Protector (macOS)
# Created by Raven Lord
# ==========================================

# ==========================================
# USER CONFIGURATION (REQUIRED)
# ==========================================
# Dynamically resolve the logged-in user to bypass Steam's macOS sandbox
MAC_USER=$(stat -f "%Su" /dev/console)
USER_HOME="/Users/$MAC_USER"

# ==========================================
# LAUNCHER & ECOSYSTEM SETUP
# ==========================================
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAVEYARD_DIR="$BASE_DIR/Graveyard"
SCRIPT_PATH="$BASE_DIR/$(basename "$0")"

if [ "$1" != "--monitor" ]; then
    # Create the user-facing Graveyard folders
    mkdir -p "$GRAVEYARD_DIR/Solo_Runs"
    mkdir -p "$GRAVEYARD_DIR/Multiplayer_Runs"
    mkdir -p "$GRAVEYARD_DIR/Hall_of_Fame"
    
    # Dynamically generate the metadata-aware Auto-Routing Resurrection Tool
    RESURRECT_TOOL="$GRAVEYARD_DIR/Resurrect_Character.command"
    if [ ! -f "$RESURRECT_TOOL" ]; then
        # Write the header and absolute path variable
        echo "#!/bin/bash" > "$RESURRECT_TOOL"
        echo "USER_HOME=\"$USER_HOME\"" >> "$RESURRECT_TOOL"
        
        # Append the rest of the script
        cat << 'EOF' >> "$RESURRECT_TOOL"
GRAVEYARD_DIR="$(cd "$(dirname "$0")" && pwd)"
SAVE_DIR="$USER_HOME/.barony/savegames"
LOG_FILE="$USER_HOME/.barony/Backups/protector.log"

if pgrep -i "barony" > /dev/null; then
    USER_CHOICE=$(osascript <<APPLESCRIPT
    try
        set dialogResult to display dialog "Barony is currently running! You must fully quit the game before resurrecting a character, otherwise the engine will instantly overwrite it." buttons {"Cancel", "Force Quit Barony"} default button 1 with icon caution with title "Graveyard Error"
        return button returned of dialogResult
    on error
        return "Cancel"
    end try
APPLESCRIPT
    )

    if [ "$USER_CHOICE" = "Force Quit Barony" ]; then
        pkill -i "barony"
        sleep 2
    else
        exit 1
    fi
fi

FILE_PATH=$(osascript <<APPLESCRIPT
try
    set theFile to choose file with prompt "Select a deceased character to resurrect:" default location POSIX file "$GRAVEYARD_DIR"
    return POSIX path of theFile
on error
    return ""
end try
APPLESCRIPT
)

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

FILENAME=$(basename "$FILE_PATH")
ORIG_BASE=$(echo "$FILENAME" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')

if [ -z "$ORIG_BASE" ]; then
    osascript -e "display dialog \"Error: Could not identify original save slot. File must contain [bracketed] name.\" buttons {\"OK\"} default button 1 with title \"Graveyard Error\""
    exit 1
fi

IS_MP=""
if [[ "$ORIG_BASE" == *"_mp"* ]]; then
    IS_MP="_mp"
fi

SLOT_NUM=0
while [ -f "$SAVE_DIR/savegame${SLOT_NUM}${IS_MP}.baronysave" ]; do
    SLOT_NUM=$((SLOT_NUM+1))
done

NEW_SLOT_NAME="savegame${SLOT_NUM}${IS_MP}.baronysave"

cp "$FILE_PATH" "$SAVE_DIR/$NEW_SLOT_NAME"
touch "$SAVE_DIR/$NEW_SLOT_NAME"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] USER ACTION: Resurrected $FILENAME into $NEW_SLOT_NAME" >> "$LOG_FILE"

osascript -e "display notification \"Character successfully restored to empty slot: $NEW_SLOT_NAME!\" with title \"Barony Graveyard\" sound name \"Glass\""
osascript -e 'tell application "Terminal" to close front window' & exit
EOF
        chmod +x "$RESURRECT_TOOL"
    fi

    # Detach monitor with App Nap protection, passing this script's PID
    nohup caffeinate -i /bin/bash "$SCRIPT_PATH" --monitor $$ >/dev/null 2>&1 &
    
    # LAUNCH FIX: Directly execute Steam arguments to inherit Steamworks environments
    if [ "$#" -gt 0 ]; then
        TARGET="$1"
        shift
        # If Steam passes the .app bundle directory instead of the binary, route to the binary
        if [[ "$TARGET" == *.app ]]; then
            TARGET="$TARGET/Contents/MacOS/Barony"
        fi
        exec "$TARGET" "$@"
    else
        exec open -W "$USER_HOME/Library/Application Support/Steam/steamapps/common/Barony/Barony.app"
    fi
fi

# ==========================================
# MONITOR MODE (Runs silently in background)
# ==========================================
SAVE_DIR="$USER_HOME/.barony/savegames"
BACKUP_DIR="$USER_HOME/.barony/Backups"
LOG_FILE="$BACKUP_DIR/protector.log"
MAX_BACKUPS=10
MAX_GRAVEYARD=100

mkdir -p "$BACKUP_DIR"

if [ -f "$LOG_FILE" ]; then
    tail -n 500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

TARGET_PID="$2"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Monitor started tracking Barony (PID $TARGET_PID). Monitoring saves..." >> "$LOG_FILE"

# Send startup notification
osascript -e 'display notification "Barony Save Protector is actively monitoring your saves." with title "Protector Active" sound name "Glass"'

while kill -0 "$TARGET_PID" 2>/dev/null; do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    shopt -s nullglob
    
    # --- BACKUP PHASE ---
    for file in "$SAVE_DIR"/*.baronysave; do
        if [ -s "$file" ]; then
            BASENAME=$(basename "$file" .baronysave)
            
            # Bash 3.2 safe dynamic variables: e.g. MTIME_savegame0
            VAR_NAME="MTIME_${BASENAME}"
            CURRENT_MTIME=$(stat -f %m "$file" 2>/dev/null)
            
            # Indirect expansion to check last known state
            if [ "$CURRENT_MTIME" = "${!VAR_NAME}" ]; then
                continue  # File hasn't changed, skip all I/O
            fi
            
            # Update the stored mtime
            eval "${VAR_NAME}=\"$CURRENT_MTIME\""

            # Fast grep extraction to ignore corrupted 0-HP Death Screen saves
            HP_MATCH=$(grep -m 1 -Eo '"HP": *[0-9]+' "$file" 2>/dev/null)
            HP=$(echo "$HP_MATCH" | grep -Eo '[0-9]+')
            if ! [[ "$HP" =~ ^[0-9]+$ ]]; then HP=1; fi
            
            if [ "$HP" -gt 0 ]; then
                # Extract and sanitize character name
                CHAR_MATCH=$(grep -m 1 -Eo '"name": *"[^"]+"' "$file" 2>/dev/null)
                CHAR_NAME=$(echo "$CHAR_MATCH" | sed -E 's/"name": *"([^"]+)"/\1/')
                SAFE_CHAR_NAME=${CHAR_NAME:-"Unknown"}
                SAFE_CHAR_NAME=$(echo "$SAFE_CHAR_NAME" | tr '/' '-' | tr -s ' ' '_')
                
                # Format: [Name]_[savegameX]_[timestamp].baronysave
                BACKUP_NAME="${SAFE_CHAR_NAME}_${BASENAME}_${TIMESTAMP}.baronysave"
                cp "$file" "$BACKUP_DIR/$BACKUP_NAME"
                
                # Cleanup older backups for THIS specific slot (ignore char name in search)
                BACKUP_FILES=("$BACKUP_DIR"/*_"${BASENAME}"_[0-9]*.baronysave)
                if [ ${#BACKUP_FILES[@]} -gt $MAX_BACKUPS ]; then
                    ls -1t "${BACKUP_FILES[@]}" | tail -n +$((MAX_BACKUPS + 1)) | while IFS= read -r old_file; do
                        rm -f "$old_file"
                    done
                fi
            fi
        fi
    done
    
    # --- RESTORE PHASE ---
    for backup in "$BACKUP_DIR"/*.baronysave; do
        if [ -f "$backup" ]; then
            BASENAME=$(basename "$backup")
            ORIG_NAME=$(echo "$BASENAME" | sed -E 's/.*_(savegame[0-9]+(_mp)?)_[0-9]{8}_[0-9]{6}\.baronysave$/\1.baronysave/')
            
            if [ ! -f "$SAVE_DIR/$ORIG_NAME" ]; then
                
                BACKUPS=( $(ls -1t "$BACKUP_DIR"/*_"${ORIG_NAME%.baronysave}"_[0-9]*.baronysave 2>/dev/null) )
                
                if [ -n "${BACKUPS[0]}" ] && [ -f "${BACKUPS[0]}" ]; then
                    LATEST="${BACKUPS[0]}" 
                    
                    # --- DETERMINISTIC LOG TRIAGE ---
                    # Use Python to evaluate log.txt for deterministic engine markers
                    LOG_TARGET="$USER_HOME/.barony/log.txt"
                    TRIAGE_STATUS=$(python3 -c "
import sys, os
log_file = sys.argv[1]
save_name = sys.argv[2]
try:
    if not os.path.exists(log_file):
        print('GHOST_WIPE')
        sys.exit(0)
        
    with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
        # Read the last 200 lines to ensure we capture the deletion context
        lines = f.readlines()[-200:]
        
    # Find the LAST occurrence of the engine deleting this specific savegame
    last_del_idx = -1
    search_str = 'deleting savegame in '
    for i in range(len(lines) - 1, -1, -1):
        if search_str in lines[i] and save_name in lines[i]:
            last_del_idx = i
            break
            
    if last_del_idx == -1:
        print('GHOST_WIPE')
        sys.exit(0)
        
    # Scan a strict window (+/- 15 lines) around the deletion event
    start_idx = max(0, last_del_idx - 15)
    end_idx = min(len(lines), last_del_idx + 15)
    
    for i in range(start_idx, end_idx):
        if '[JSON]: Successfully wrote json file' in lines[i]:
            print('DEATH')
            sys.exit(0)
            
    print('MANUAL_DELETE')
except Exception:
    print('GHOST_WIPE')
" "$LOG_TARGET" "$ORIG_NAME" 2>/dev/null)
                    DELETE_CONTEXT=$(grep -B 1 "You die\.\.\." "$LOG_TARGET" 2>/dev/null)

                    # --- FAIL SAFELY LOGIC FLOW ---
                    if [ "$TRIAGE_STATUS" = "MANUAL_DELETE" ]; then
                        # 100% Confirmed UI Deletion. Clean up backups.
                        echo "[$(date +'%Y-%m-%d %H:%M:%S')] User manually deleted $ORIG_NAME in UI. Cleaning up backups." >> "$LOG_FILE"
                        rm -f "$BACKUP_DIR"/*_"${ORIG_NAME%.baronysave}"_[0-9]*.baronysave
                        continue
                    elif [ "$TRIAGE_STATUS" = "GHOST_WIPE" ]; then
                        # FAIL SAFELY: The log is missing the deletion event entirely (e.g. rotation/bug).
                        echo "[$(date +'%Y-%m-%d %H:%M:%S')] FAIL SAFELY: $ORIG_NAME vanished without log context. Resurrecting character." >> "$LOG_FILE"
                        # Execution falls through to resurrection
                    fi
                    # If TRIAGE_STATUS = "DEATH", it naturally falls through to the resurrection block.
                    
                    # It's a death. Next Open Slot Logic:
                    ORIG_BASE="${ORIG_NAME%.baronysave}"
                    IS_MP=""
                    if [[ "$ORIG_BASE" == *"_mp"* ]]; then
                        IS_MP="_mp"
                    fi
                    
                    SLOT_NUM=0
                    while [ -f "$SAVE_DIR/savegame${SLOT_NUM}${IS_MP}.baronysave" ]; do
                        SLOT_NUM=$((SLOT_NUM+1))
                    done
                    SAFE_ORIG_NAME="savegame${SLOT_NUM}${IS_MP}.baronysave"
                    
                    cp "$LATEST" "$SAVE_DIR/$SAFE_ORIG_NAME"
                    touch "$SAVE_DIR/$SAFE_ORIG_NAME"
                    
                    if [[ "$ORIG_BASE" == *"_mp"* ]]; then
                        SUB_DIR="Multiplayer_Runs"
                    else
                        SUB_DIR="Solo_Runs"
                    fi
                    
                    # --- METADATA EXTRACTION ---
                    eval $(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    p = d.get('players', [])
    stats = p[0].get('stats', {}) if p else {}
    
    name = str(stats.get('name', '')).strip()
    name = name if name else 'Unknown'
    name = name.replace(\"'\", \"'\\''\")
    
    lvl = stats.get('LVL', 0)
    flr = d.get('dungeon_lvl', 0)
    hp = stats.get('maxHP', 0)
    gold = stats.get('GOLD', 0)
    kills = sum(p[0].get('kills', [])) if p else 0
    cid = p[0].get('char_class', -1) if p else -1
    rid = p[0].get('race', -1) if p else -1
    
    classes = {0:'Barbarian',1:'Warrior',2:'Healer',3:'Rogue',4:'Wanderer',5:'Cleric',6:'Merchant',7:'Wizard',8:'Arcanist',9:'Joker',10:'Sexton',11:'Ninja',12:'Monk',13:'Conjurer',14:'Accursed',15:'Mesmer',16:'Brewer',17:'Mechanist',18:'Punisher',19:'Shaman',20:'Hunter',21:'Bard',22:'Sapper',23:'Scion'}
    races = {0:'Human',1:'Skeleton',2:'Vampire',3:'Succubus',4:'Goatman',5:'Automaton',6:'Incubus',7:'Goblin',8:'Insectoid'}
    
    print(f'CHAR_NAME=\'{name}\'')
    print(f'CHAR_LVL=\"{lvl}\"')
    print(f'DUNGEON_FLR=\"{flr}\"')
    print(f'MAX_HP=\"{hp}\"')
    print(f'GOLD=\"{gold}\"')
    print(f'TOTAL_KILLS=\"{kills}\"')
    print(f'CHAR_CLASS=\"{classes.get(cid, f\"Class ID {cid}\")}\"')
    print(f'CHAR_RACE=\"{races.get(rid, f\"Race ID {rid}\")}\"')
except Exception:
    print('CHAR_NAME=\"Unknown\"')
    print('CHAR_LVL=\"0\"')
    print('DUNGEON_FLR=\"0\"')
    print('MAX_HP=\"0\"')
    print('GOLD=\"0\"')
    print('TOTAL_KILLS=\"0\"')
    print('CHAR_CLASS=\"Unknown\"')
    print('CHAR_RACE=\"Unknown\"')
" < "$LATEST" 2>/dev/null)
                    
                    SAFE_CHAR_NAME=${CHAR_NAME:-"Unknown"}
                    SAFE_CHAR_NAME=$(echo "$SAFE_CHAR_NAME" | tr '/' '-' | tr -s ' ' '_')
                    CHAR_LVL=${CHAR_LVL:-"0"}
                    DUNGEON_FLR=${DUNGEON_FLR:-"0"}
                    MAX_HP=${MAX_HP:-"0"}
                    GOLD=${GOLD:-"0"}
                    TOTAL_KILLS=${TOTAL_KILLS:-"0"}
                    CHAR_CLASS=${CHAR_CLASS:-"Unknown"}
                    CHAR_RACE=${CHAR_RACE:-"Unknown"}
                    
                    BACKUP_TIMESTAMP=$(echo "$LATEST" | grep -Eo '[0-9]{8}_[0-9]{6}')
                    GRAVEYARD_FILE="$GRAVEYARD_DIR/$SUB_DIR/${SAFE_CHAR_NAME}_[${ORIG_BASE}]_${BACKUP_TIMESTAMP}.baronysave"
                    
                    if [ ! -f "$GRAVEYARD_FILE" ]; then
                        cp "$LATEST" "$GRAVEYARD_FILE"
                        
                        CAUSE_OF_DEATH="Unknown cause."
                        if echo "$DELETE_CONTEXT" | grep -q "You die..."; then
                            RAW_DEATH_LINE=$(echo "$DELETE_CONTEXT" | grep -B 1 "You die..." | head -n 1)
                            CAUSE_OF_DEATH=$(echo "$RAW_DEATH_LINE" | sed -E 's/^\[[0-9-]+\] //')
                        fi
                        
                        {
                            echo "========================================"
                            echo "FALLEN HERO: $CHAR_NAME"
                            echo "DATE OF DEATH: $(date +'%B %d, %Y at %I:%M %p')"
                            echo "CAUSE OF DEATH: $CAUSE_OF_DEATH"
                            echo "----------------------------------------"
                            echo "Race: $CHAR_RACE | Class: $CHAR_CLASS"
                            echo "Level: $CHAR_LVL | Floor Reached: $DUNGEON_FLR"
                            echo "Total Enemies Defeated: $TOTAL_KILLS"
                            echo "Max HP: $MAX_HP | Wealth: $GOLD Gold"
                            echo "Run Type: ${SUB_DIR//_/ }"
                            echo "========================================"
                            echo ""
                        } > "$GRAVEYARD_DIR/The_Fallen_Chronicles.tmp"
                        
                        if [ -f "$GRAVEYARD_DIR/The_Fallen_Chronicles.txt" ]; then
                            cat "$GRAVEYARD_DIR/The_Fallen_Chronicles.txt" >> "$GRAVEYARD_DIR/The_Fallen_Chronicles.tmp"
                        fi
                        mv "$GRAVEYARD_DIR/The_Fallen_Chronicles.tmp" "$GRAVEYARD_DIR/The_Fallen_Chronicles.txt"
                    fi
                    
                    ALL_GRAVES=("$GRAVEYARD_DIR"/Solo_Runs/*.baronysave "$GRAVEYARD_DIR"/Multiplayer_Runs/*.baronysave)
                    if [ ${#ALL_GRAVES[@]} -gt $MAX_GRAVEYARD ]; then
                        ls -1t "${ALL_GRAVES[@]}" 2>/dev/null | tail -n +$((MAX_GRAVEYARD + 1)) | while IFS= read -r old_grave; do
                            rm -f "$old_grave"
                        done
                    fi
                    
                    if [ -f "$GRAVEYARD_DIR/The_Fallen_Chronicles.txt" ]; then
                        if [ $(wc -l < "$GRAVEYARD_DIR/The_Fallen_Chronicles.txt") -gt 1200 ]; then
                            head -n 1200 "$GRAVEYARD_DIR/The_Fallen_Chronicles.txt" > "$GRAVEYARD_DIR/The_Fallen_Chronicles.tmp"
                            mv "$GRAVEYARD_DIR/The_Fallen_Chronicles.tmp" "$GRAVEYARD_DIR/The_Fallen_Chronicles.txt"
                        fi
                    fi
                    
                    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Death detected. Restored $ORIG_NAME to $SAFE_ORIG_NAME and archived to $SUB_DIR." >> "$LOG_FILE"
                    osascript -e "display notification \"Your character died, but your save file was instantly restored. A permanent backup was sent to the Graveyard.\" with title \"Barony Save Protector\" sound name \"Glass\""
                    
                    sleep 5 
                fi
            fi
        fi
    done
    
    shopt -u nullglob
    sleep 2
done

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Barony closed. Exiting script." >> "$LOG_FILE"

# Send shutdown notification
osascript -e 'display notification "Barony has closed. Save Protector is going to sleep." with title "Protector Stopped"'