#!/bin/bash
# Prompt Inspector - One-command installer
# Usage: ./install.sh <project_path>

set -e

PROJECT_PATH="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

echo "═══════════════════════════════════════════════════════════════"
echo "  🔧 Prompt Inspector Installer"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Run setup
echo "📦 Step 1/2: Installing component..."
python3 "$SCRIPT_DIR/setup.py" "$PROJECT_PATH" --force

echo ""
echo "🔍 Step 2/2: Discovering APIs..."
python3 "$SCRIPT_DIR/discover_apis.py" "$PROJECT_PATH"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Installation Complete!"
echo ""
echo "  Next steps:"
echo "  1. Start your dev server (npm run dev)"
echo "  2. Look for the toolbar at bottom-right"
echo "  3. Click 'Select Element' to start binding APIs"
echo "═══════════════════════════════════════════════════════════════"
