#!/usr/bin/env bash
# Runs /gcc debug in the game (Debug.lua, the in-game test suite) and screenshots
# each of its steps, then builds a comparison of the crosshair's looks.
#
#   tests/screenshot_debug.sh [output folder]
#   default folder: ~/Documents/Coding/WoW/Reports/screenshots/<date> crosshair customizer
#
# Needs WoW running with GamepadCrosshairCustomizer and its Debug.lua loaded, the
# controller UI on (the crosshair only shows then), friendly players near you
# (several classes if you can), and you standing still until the game asks you to
# move near a neutral or enemy NPC. It presses Debug.lua's START_KEY
# (Alt+Ctrl+Shift+C) in the game, then answers the corner square and screenshots
# each step:
#   green   a step, its number in the blue (step x MARKER_BLUE_PER_STEP): shot
#   yellow  waiting for the crosshair: touch the controller
#   blue    a friendly player wanted: presses TARGET_KEYS (/targetfriendplayer)
#   violet  a neutral or enemy NPC wanted: presses TARGET_ENEMY_KEYS (/targetenemy)
#           while you walk near one
#   navy    no target wanted: presses CLEAR_TARGET_KEYS (/cleartarget)
#   red     the run stopped; gone: done The game then opens the suite's reload box: its Reload writes
# the run (with where the crosshair was on screen each step) to
# GamepadCrosshairCustomizerDebugDB, and the crops follow those positions. With
# Later, or no reload within RELOAD_WAIT seconds, it crops around the screen's
# middle instead.
#   RELOAD_WAIT=120   COMPARE_ONLY=1 (no run: only the comparison, from the shots there)
#
# Window focus and key presses: devAddons/game_window.sh (WoWDevHelpers),
# DEV_ADDONS points to another copy.
# Exit codes: 0 done, 2 the game isn't running, 6 the run stopped in the game,
# 7 a step never showed, 8 over the time limit.

set -u
SCRIPT_FOLDER="$(cd "$(dirname "$0")" && pwd)"
DEV_ADDONS="${DEV_ADDONS:-$SCRIPT_FOLDER/../../devAddons}"
# shellcheck source=/dev/null
. "$DEV_ADDONS/game_window.sh"
GAME_FOLDER="${DAYLIGHT_GAME:-/var/mnt/data/Jeux - Installations/World of Warcraft/_forever_}"
SAVED_VARIABLES="$GAME_FOLDER/WTF/Account/129527646#1/SavedVariables/GamepadCrosshairCustomizer.lua"
OUTPUT_FOLDER="${1:-$HOME/Documents/Coding/WoW/Reports/screenshots/$(date +%Y-%m-%d) crosshair customizer}"
START_KEYS="ctrl+alt+shift+c"          # Debug.lua's START_KEY
TARGET_KEYS="ctrl+alt+shift+y"         # Debug.lua's TARGET_KEY
TARGET_ENEMY_KEYS="ctrl+alt+shift+z"   # Debug.lua's TARGET_ENEMY_KEY
CLEAR_TARGET_KEYS="ctrl+alt+shift+x"   # Debug.lua's CLEAR_TARGET_KEY
TARGET_PRESS_SECONDS=2                 # between presses while a target is wanted
MARKER_BLUE_PER_STEP=8          # Debug.lua's MARKER_BLUE_PER_STEP
# How many steps Debug.lua has: loaded here with just enough of a game to count them.
STEP_COUNT=$(cd "$SCRIPT_FOLDER/.." && luajit -e '
    local stub = setmetatable({}, { __index = function() return function() end end })
    CreateFrame = function() return stub end
    GamepadCrosshairCustomizer = {}
    dofile("Debug.lua")
    print(#GamepadCrosshairCustomizer.Debug.STEPS)')
RELOAD_WAIT="${RELOAD_WAIT:-120}"
START_RETRY_SECONDS=5
TIME_LIMIT=$((STEP_COUNT * 3 + 150 + 180 + 5 * 15))   # + walking to an NPC + the optional searches
mkdir -p "$OUTPUT_FOLDER"

# Prints the corner square's state in a screenshot: "stopped", "waiting" (for the
# crosshair to show), "friendly", "npc", "notarget", "step <n>" or "none".
read_marker() {
    python3 - "$1" "$MARKER_BLUE_PER_STEP" <<'PY'
import sys
from PIL import Image
red, green, blue = Image.open(sys.argv[1]).convert("RGB").getpixel((4, 4))
if red > 200 and green < 60 and blue > 240:
    print("none")   # magenta: DevReload's box, not ours
elif red > 200 and green < 60:
    print("stopped")
elif red > 200 and green > 200 and blue < 60:
    print("waiting")
elif red < 60 and green < 60 and blue > 200:
    print("friendly")
elif 100 < red < 160 and green < 60 and blue > 200:
    print("npc")
elif red < 60 and green < 60 and 100 < blue < 160:
    print("notarget")
elif green > 200 and red < 60 and blue > 0:
    print("step %d" % round(blue / int(sys.argv[2])))
else:
    print("none")
PY
}

shoot() { spectacle --background --nonotify --fullscreen --output "$1" >/dev/null 2>&1; }

if [ "${COMPARE_ONLY:-0}" != 1 ]; then
    window="$(find_game_window)"
    [ -n "$window" ] || { echo "The game isn't running." >&2; exit 2; }
    saved_before="$(stat -c %Y "$SAVED_VARIABLES" 2>/dev/null || echo 0)"
    rm -f "$OUTPUT_FOLDER"/step-*.png
    focus_game_with_kwin "$window"
    sleep 0.5
    # Right after game_reload.sh the game may still be loading, before Debug.lua
    # binds its key at login: the key is pressed again every START_RETRY_SECONDS
    # until the square shows (seen: the first press after a reload went nowhere).
    xdotool key --clearmodifiers "$START_KEYS"; last_press=$SECONDS
    echo "/gcc debug: $STEP_COUNT steps. After a reload, touch the controller once so its UI (and the crosshair) comes back; then stay still."
    started=$SECONDS; last_step=0; last_target_press=0; probe="$OUTPUT_FOLDER/.probe.png"
    while :; do
        shoot "$probe"
        marker="$(read_marker "$probe")"
        case "$marker" in
            "step "*)
                step="${marker#step }"
                if [ "$step" -gt "$last_step" ]; then
                    mv "$probe" "$(printf '%s/step-%02d.png' "$OUTPUT_FOLDER" "$step")"
                    echo "  step $step/$STEP_COUNT"
                    last_step=$step
                fi ;;
            waiting) : ;;   # Debug.lua waits for the crosshair (a touch of the controller)
            friendly|npc|notarget)
                if [ $((SECONDS - last_target_press)) -ge "$TARGET_PRESS_SECONDS" ]; then
                    case "$marker" in
                        friendly) keys="$TARGET_KEYS" ;;
                        npc) keys="$TARGET_ENEMY_KEYS"; echo "  move near a neutral or enemy NPC (one that won't attack you)" ;;
                        notarget) keys="$CLEAR_TARGET_KEYS" ;;
                    esac
                    focus_game_with_kwin "$window"; sleep 0.2
                    xdotool key --clearmodifiers "$keys"; last_target_press=$SECONDS
                fi ;;
            stopped) echo "The run stopped in the game (a fight?). Shots so far are in $OUTPUT_FOLDER." >&2; exit 6 ;;
            none)
                if [ "$last_step" -ge "$STEP_COUNT" ]; then break; fi
                # Debug.lua first waits up to 60 s for the crosshair (its square yellow).
                if [ "$last_step" -eq 0 ] && [ $((SECONDS - last_press)) -ge "$START_RETRY_SECONDS" ]; then
                    focus_game_with_kwin "$window"; sleep 0.3
                    xdotool key --clearmodifiers "$START_KEYS"; last_press=$SECONDS
                fi
                if [ "$last_step" -eq 0 ] && [ $((SECONDS - started)) -ge 90 ]; then
                    echo "The run didn't start (is Debug.lua loaded? a chat box holding the cursor?)." >&2; exit 7
                fi ;;
        esac
        [ $((SECONDS - started)) -lt "$TIME_LIMIT" ] || { echo "Over the time limit." >&2; exit 8; }
        sleep 0.3
    done
    rm -f "$probe"
    [ "$last_step" -ge "$STEP_COUNT" ] || { echo "Only $last_step of $STEP_COUNT steps were seen." >&2; exit 7; }
    echo "All steps shot. Click Reload in the game's box to save the run (for the crops)."
    waited=0
    while [ "$(stat -c %Y "$SAVED_VARIABLES" 2>/dev/null || echo 0)" = "$saved_before" ] && [ "$waited" -lt "$RELOAD_WAIT" ]; do
        sleep 2; waited=$((waited + 2))
    done
fi

# Each step's label and crosshair position, from the saved run (newest), as
# "label<TAB>x<TAB>y<TAB>width" lines; nothing if the run wasn't saved.
positions="$OUTPUT_FOLDER/positions.tsv"
luajit - "$SAVED_VARIABLES" > "$positions" 2>/dev/null <<'LUA' || : > "$positions"
local chunk = loadfile(arg[1]); if not chunk then return end
chunk()
local store = GamepadCrosshairCustomizerDebugDB
local run = store and store.runs and store.runs[#store.runs]
if not run then return end
for _, step in ipairs(run.steps or {}) do
    local onScreen = step.onScreen or {}
    print(table.concat({ step.label, onScreen.x or "", onScreen.y or "", onScreen.width or "" }, "\t"))
end
LUA

python3 - "$OUTPUT_FOLDER" "$positions" <<'PY'
import os, sys
from PIL import Image, ImageDraw, ImageFont
folder, positions_path = sys.argv[1], sys.argv[2]
shots = sorted(name for name in os.listdir(folder) if name.startswith("step-") and name.endswith(".png"))
if not shots:
    sys.exit("no screenshots in " + folder)
steps = [line.rstrip("\n").split("\t") for line in open(positions_path) if line.strip()]
TILE, CROP = 260, 130   # each tile shows CROP x CROP screen pixels around the crosshair, 2x
try:
    font = ImageFont.truetype(os.popen("fc-match -f '%{file}' sans").read().strip() or "DejaVuSans.ttf", 15)
except OSError:
    font = ImageFont.load_default()
columns = 6
rows = (len(shots) + columns - 1) // columns
sheet = Image.new("RGB", (columns * TILE, rows * (TILE + 40)), (20, 20, 20))
draw = ImageDraw.Draw(sheet)
for index, name in enumerate(shots):
    shot = Image.open(os.path.join(folder, name)).convert("RGB")
    step_number = int(name[5:7])
    label, x, y = "step %d" % step_number, shot.width // 2, shot.height // 2
    if step_number <= len(steps):
        entry = steps[step_number - 1]
        label = entry[0].split(": ", 1)[-1]
        if len(entry) > 2 and entry[1] and entry[2]:
            x, y = int(entry[1]), int(entry[2])
    half = CROP // 2
    crop = shot.crop((x - half, y - half, x + half, y + half)).resize((TILE, TILE), Image.NEAREST)
    left, top = (index % columns) * TILE, (index // columns) * (TILE + 40)
    sheet.paste(crop, (left, top))
    draw.text((left + 6, top + TILE + 4), "%d. %s" % (step_number, label[:34]), fill=(235, 235, 235), font=font)
    draw.text((left + 6, top + TILE + 21), label[34:68], fill=(235, 235, 235), font=font)
output = os.path.join(folder, "comparison crosshair looks.jpg")
sheet.save(output, quality=90)
print("Comparison: " + output + ("" if steps else " (run not saved: crops around the screen's middle)"))
PY
