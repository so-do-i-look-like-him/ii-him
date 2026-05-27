#!/usr/bin/env bash

# Him's Illogical Impulse (ii) Install Script
# Sets up the QuickShell configuration by symlinking this folder to ~/.config/quickshell/ii

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TARGET_DIR="$HOME/.config/quickshell/ii"
BACKUP_DIR="$HOME/.config/quickshell/ii_backup_$(date +%Y%m%d_%H%M%S)"

echo "🚀 Setting up Him's II QuickShell config..."

# 1. Ensure the parent config directory exists
mkdir -p "$HOME/.config/quickshell"

# 2. Check if the target already exists
if [ -e "$TARGET_DIR" ] || [ -L "$TARGET_DIR" ]; then
    # Check if it's already symlinked to the right place
    if [ "$(readlink -f "$TARGET_DIR")" == "$SCRIPT_DIR" ]; then
        echo "✅ Already linked correctly to $SCRIPT_DIR"
    else
        echo "📦 Existing config detected. Moving to $BACKUP_DIR..."
        mv "$TARGET_DIR" "$BACKUP_DIR"
        echo "🔗 Creating symlink: $TARGET_DIR -> $SCRIPT_DIR"
        ln -s "$SCRIPT_DIR" "$TARGET_DIR"
    fi
else
    echo "🔗 Creating symlink: $TARGET_DIR -> $SCRIPT_DIR"
    ln -s "$SCRIPT_DIR" "$TARGET_DIR"
fi

# 3. Ensure remotes are set up correctly in this folder
echo "🔗 Configuring Git remotes..."
git remote add origin https://github.com/so-do-i-look-like-him/II-him.git 2>/dev/null || git remote set-url origin https://github.com/so-do-i-look-like-him/II-him.git
git remote add upstream https://github.com/end4/illogical-impulse.git 2>/dev/null || true

# 4. Check dependencies
echo "🔍 Checking for QuickShell..."
if ! command -v quickshell &> /dev/null; then
    echo "⚠️  Warning: 'quickshell' command not found."
    echo "   On CachyOS/Arch, you can install it with: yay -S quickshell-git"
fi

echo "✨ Installation complete!"
echo "🔄 To apply changes, reload QuickShell (usually Super+Alt+R or killall quickshell && quickshell &)"
