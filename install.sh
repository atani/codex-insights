#!/usr/bin/env bash
# Install codex-insights
# Usage: curl -fsSL https://raw.githubusercontent.com/atani/codex-insights/master/install.sh | bash
set -euo pipefail

REPO="https://github.com/atani/codex-insights"
INSTALL_DIR="${HOME}/.local/share/codex-insights"
BIN_DIR="${HOME}/.local/bin"

echo "Installing codex-insights..."

# Check dependencies
for cmd in git jq codex; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required." >&2
    [[ "$cmd" == "codex" ]] && echo "  Install Codex CLI: https://github.com/openai/codex" >&2
    [[ "$cmd" == "jq" ]] && echo "  brew install jq" >&2
    [[ "$cmd" == "git" ]] && echo "  brew install git" >&2
    exit 1
  fi
done

mkdir -p "$BIN_DIR"

# Clone or update
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --quiet
else
  if [[ -d "$INSTALL_DIR" ]]; then
    echo "Removing existing non-git directory: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
  fi
  git clone --quiet "$REPO" "$INSTALL_DIR"
fi

chmod +x "${INSTALL_DIR}/codex-insights" "${INSTALL_DIR}/analyze.sh"

# Bin
ln -sfn "${INSTALL_DIR}/codex-insights" "${BIN_DIR}/codex-insights"

# Skills (Claude Code / Codex)
for dir in "${HOME}/.skills" "${HOME}/.claude/skills" "${HOME}/.codex/skills"; do
  [[ -d "$(dirname "$dir")" ]] || continue
  mkdir -p "$dir"
  ln -sfn "$INSTALL_DIR" "${dir}/codex-insights"
done

echo "Done! Run: codex-insights"

if ! echo "$PATH" | tr ':' '\n' | grep -q "^${BIN_DIR}$"; then
  echo ""
  echo "Add to PATH: export PATH=\"\${HOME}/.local/bin:\${PATH}\""
fi
