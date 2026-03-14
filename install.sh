#!/usr/bin/env bash
# install.sh — adds cmdwatch to your ~/.zshrc

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_FILE="${PLUGIN_DIR}/cmdwatch.zsh"
ZSHRC="${HOME}/.zshrc"
SOURCE_LINE="source \"${PLUGIN_FILE}\""

if grep -qF "$PLUGIN_FILE" "$ZSHRC" 2>/dev/null; then
    echo "cmdwatch is already installed in ${ZSHRC}"
    exit 0
fi

{
    printf '\n# cmdwatch — smart alias suggester\n'
    printf '%s\n' "$SOURCE_LINE"
} >> "$ZSHRC"

echo "✓ Installed. Run 'source ~/.zshrc' or open a new terminal to activate."
