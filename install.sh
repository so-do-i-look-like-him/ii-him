#!/usr/bin/env bash

# Him's Illogical Impulse (ii) Install Script
# Sets up the QuickShell configuration directory

set -e

CONFIG_DIR="$HOME/.config/quickshell/ii"
BACKUP_DIR="$HOME/.config/quickshell/ii_backup_$(date +%Y%m%d_%H%M%S)"

echo "🚀 Starting installation for Him's II QuickShell config..."

# 1. Backup existing config if it exists
if [ -d "$CONFIG_DIR" ]; then
    echo "📦 Backing up existing config to $BACKUP_DIR..."
    mv "$CONFIG_DIR" "$BACKUP_DIR"
fi

# 2. Clone the repo
echo "📥 Cloning from GitHub..."
git clone https://github.com/so-do-i-look-like-him/II-him.git "$CONFIG_DIR"

# 3. Enter directory
cd "$CONFIG_DIR"

# 4. Initialize remotes
echo "🔗 Setting up remotes..."
git remote add upstream https://github.com/end4/illogical-impulse.git || true

# 5. Check dependencies (basic check)
echo "🔍 Checking for QuickShell..."
if ! command -v quickshell &> /dev/null; then
    echo "⚠️  Warning: 'quickshell' command not found. You might need to install it via your package manager."
fi

echo "✅ Done! You can now start QuickShell or reload it."
echo "💡 Tip: To sync with the original project later, run: git fetch upstream && git rebase upstream/main"
