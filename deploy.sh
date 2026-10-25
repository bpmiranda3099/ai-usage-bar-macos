#!/bin/bash
# Rebuilds AIAgentsUsageBar and redeploys it as a background LaunchAgent (no
# .app bundle, no Dock/Launchpad icon needed).
set -euo pipefail

cd "$(dirname "$0")"
swift build -c release

INSTALL_DIR="$HOME/Library/Application Support/AIAgentsUsageBar"
mkdir -p "$INSTALL_DIR"

launchctl bootout "gui/$(id -u)/com.bpmiranda3099.aiagentsusagebar" 2>/dev/null || true

cp .build/release/AIAgentsUsageBar "$INSTALL_DIR/AIAgentsUsageBar"
rm -rf "$INSTALL_DIR/ai-agents-usage-bar_AIAgentsUsageBar.bundle"
cp -R .build/release/ai-agents-usage-bar_AIAgentsUsageBar.bundle "$INSTALL_DIR/ai-agents-usage-bar_AIAgentsUsageBar.bundle"

launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.bpmiranda3099.aiagentsusagebar.plist

echo "Deployed and running."
