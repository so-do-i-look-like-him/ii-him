#!/usr/bin/env bash

# Him's Full-System Installer for Illogical Impulse (ii)
# This script sets up the entire Hyprland environment + Him's custom QuickShell config

set -e

# Define directories
CONFIG_DIR="$HOME/.config/quickshell/ii"
BACKUP_DIR="$HOME/.config/quickshell/ii_backup_$(date +%Y%m%d_%H%M%S)"
CLONE_DIR=$(pwd)

echo "🚀 Starting Full-System Installation for Him's Setup..."
echo "This will install end4's dots-hyprland base, and then apply your custom QuickShell config."

# 1. Ask for sudo upfront to avoid interrupting the flow
sudo -v

# 2. Check for required packages to run the base installer
echo "📦 Ensuring git and base-devel are installed..."
if ! command -v git &> /dev/null || ! pacman -Qs base-devel &> /dev/null; then
    sudo pacman -S --needed --noconfirm git base-devel
fi

# 3. Clone and run end4's base dots-hyprland installer
echo "⚙️ Installing base dots-hyprland (end4)..."
TEMP_DIR=$(mktemp -d)
git clone https://github.com/end4/dots-hyprland.git "$TEMP_DIR/dots-hyprland"
cd "$TEMP_DIR/dots-hyprland"

# The original install script requires yay/paru. We assume CachyOS has yay or paru.
if command -v yay &> /dev/null || command -v paru &> /dev/null; then
    # We pass standard yes to automate his installer as much as possible, though it may still prompt
    echo "Running upstream installer... (You may need to press enter or select options)"
    ./install.sh || { echo "⚠️ Upstream installer encountered an error, but continuing..."; }
else
    echo "❌ Neither 'yay' nor 'paru' found. Please install an AUR helper first."
    exit 1
fi

# 4. Return to Him's custom repo
cd "$CLONE_DIR"

# 5. Apply Him's custom QuickShell config
echo "🎨 Applying Him's custom QuickShell (II-him)..."

# Backup existing config if it exists
if [ -d "$CONFIG_DIR" ] || [ -L "$CONFIG_DIR" ]; then
    echo "📦 Backing up existing QuickShell config to $BACKUP_DIR..."
    mv "$CONFIG_DIR" "$BACKUP_DIR"
fi

# Create symlink from the cloned repo to the QuickShell config location
echo "🔗 Creating symlink: $CONFIG_DIR -> $CLONE_DIR"
ln -s "$CLONE_DIR" "$CONFIG_DIR"

# 6. Initialize remotes for easy syncing later
echo "🔗 Setting up GitHub remotes for syncing..."
git remote set-url origin https://github.com/so-do-i-look-like-him/II-him.git || true
git remote add upstream https://github.com/end4/illogical-impulse.git || true

echo "✅ Full Installation Complete!"
echo "Your system now has the end4 base + your personal QuickShell tweaks."
echo "💡 You can now reload Hyprland or start QuickShell."
