#!/usr/bin/env bash
# Restart QuickShell (ii config) cleanly
# Usage: ./restart-qs.sh

# Kill existing qs process for this config
pkill -f "qs -c ii" 2>/dev/null
sleep 1

# Get Hyprland instance signature from socket directory
HYPR_SIG=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1)
if [ -z "$HYPR_SIG" ]; then
    HYPR_SIG=$(ls /tmp/hypr/ 2>/dev/null | head -1)
fi
export HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG"
export WAYLAND_DISPLAY=wayland-1
export XDG_SESSION_TYPE=wayland
export XDG_RUNTIME_DIR=/run/user/1000
export XDG_CURRENT_DESKTOP=Hyprland

# Start fresh, fully detached from terminal
nohup qs -c ii </dev/null >/tmp/qs-ii.log 2>&1 &
disown

sleep 2

if pgrep -f "qs -c ii" > /dev/null; then
    echo "QuickShell (ii) restarted successfully"
    pgrep -af "qs -c ii"
else
    echo "Failed to start QuickShell"
    tail -20 /tmp/qs-ii.log
fi
