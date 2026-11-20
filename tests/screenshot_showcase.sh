#!/usr/bin/env bash
# Screenshots of our controller addons for their CurseForge pages: drives the
# screenshot tour (Showcase.lua, development builds only) with its one key and
# shoots each step.
#
#   tests/screenshot_showcase.sh [output folder]
#   default folder: ~/Documents/Coding/WoW/Screenshots/<date> showcase
#
# Needs WoW running with GamepadReticleCustomizer (its Showcase.lua loaded) and
# Gamepad Reticle On Target, the controller UI on, out of combat, standing in a
# town: a vendor or trainer, a quest giver, a friendly player and a neutral NPC
# around you, in front of you. Stay still and don't touch the controller.
# The tour sets its own look and puts your settings back at the end.
# Only the tour's key is pressed: no mouse (the cursor would hide the reticle),
# no Escape (the tour scrolls and closes the settings window itself).
# The square in the game's top-left corner: magenta busy (the script presses the
# key again to look for the next target), red not found (no shot), gone ready.
# Exit codes: 0 done, 2 the game isn't running, 9 a step never got ready.
set -u
SCRIPT_FOLDER="$(cd "$(dirname "$0")" && pwd)"
DEV_ADDONS="${DEV_ADDONS:-$SCRIPT_FOLDER/../../devAddons}"
# shellcheck source=/dev/null
. "$DEV_ADDONS/game_window.sh"
OUTPUT_FOLDER="${1:-$HOME/Documents/Coding/WoW/Screenshots/$(date +%Y-%m-%d) showcase}"
SHOWCASE_KEYS="ctrl+alt+shift+b"   # Showcase.lua's KEY
STEP_SECONDS=80                    # longest wait for one step (40 tries of a target)
PRESS_AGAIN_SECONDS=1.2            # between presses while a target is looked for
mkdir -p "$OUTPUT_FOLDER"

# The tour's steps, "kind name" per line, read from Showcase.lua with just enough of a game.
STEPS="$(cd "$SCRIPT_FOLDER/.." && luajit -e '
    local stub = setmetatable({}, { __index = function() return function() end end })
    CreateFrame = function() return stub end
    GamepadReticleCustomizer = {}
    dofile("Showcase.lua")
    for _, step in ipairs(GamepadReticleCustomizer.Showcase.STEPS) do print(step.kind .. " " .. step.name) end')"

shoot() { spectacle --background --nonotify --fullscreen --output "$1" >/dev/null 2>&1; }

# The corner square in a screenshot: "busy", "notfound" or "ready".
read_marker() {
    python3 - "$1" <<'PY'
import sys
from PIL import Image
red, green, blue = Image.open(sys.argv[1]).convert("RGB").getpixel((4, 4))
if red > 200 and green < 60 and blue > 200:
    print("busy")
elif red > 200 and green < 60 and blue < 60:
    print("notfound")
else:
    print("ready")
PY
}

window="$(find_game_window)"
[ -n "$window" ] || { echo "The game isn't running." >&2; exit 2; }
focus_game_with_kwin "$window"
sleep 0.5
probe="$OUTPUT_FOLDER/.probe.png"
number=0
while read -r kind name; do
    number=$((number + 1))
    file="$OUTPUT_FOLDER/$(printf '%02d' "$number")-$name.png"
    xdotool key --clearmodifiers "$SHOWCASE_KEYS"
    started=$SECONDS; last_press=$(date +%s.%N)
    while :; do
        sleep 0.5
        shoot "$probe"
        state="$(read_marker "$probe")"
        if [ "$state" = ready ]; then
            sleep 0.3; shoot "$file"; echo "shot $file"
            break
        elif [ "$state" = notfound ]; then
            echo "skipped $name: no such target near you"
            break
        elif [ "$kind" = target ] && [ "$(echo "$(date +%s.%N) - $last_press > $PRESS_AGAIN_SECONDS" | bc)" = 1 ]; then
            xdotool key --clearmodifiers "$SHOWCASE_KEYS"; last_press=$(date +%s.%N)
        fi
        [ $((SECONDS - started)) -gt $STEP_SECONDS ] && { echo "$name never got ready" >&2; rm -f "$probe"; exit 9; }
    done
done <<< "$STEPS"
# One last press ends the tour: your settings back, the target cleared.
xdotool key --clearmodifiers "$SHOWCASE_KEYS"
rm -f "$probe"
echo "Done: $OUTPUT_FOLDER"
