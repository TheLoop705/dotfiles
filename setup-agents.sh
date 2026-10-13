#!/usr/bin/env bash
# Apply the shared agent layout without requiring a full Nix rebuild.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_PI=true
case "${1:-}" in
  --links-only) INSTALL_PI=false ;;
  "") ;;
  *) echo "Usage: $0 [--links-only]" >&2; exit 2 ;;
esac

# Preserve existing files/directories locally; never import auth or sessions.
link_config() {
  local source="$1" target="$2" backup
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] && [ "$source" -ef "$target" ]; then
    return
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup="${target}.before-shared-agents.$(date +%Y%m%d%H%M%S).$$"
    mv "$target" "$backup"
    echo "Preserved $target at $backup"
  fi
  ln -s "$source" "$target"
}

# Claude's import uses ~/dotfiles, so support checkouts at another location.
if [ "$DIR" != "$HOME/dotfiles" ]; then
  if [ -e "$HOME/dotfiles" ] && ! [ "$DIR" -ef "$HOME/dotfiles" ]; then
    echo "~/dotfiles already points to a different checkout; refusing to replace it." >&2
    exit 1
  fi
  link_config "$DIR" "$HOME/dotfiles"
fi

link_config "$DIR/agents/skills" "$HOME/.agents/skills"
link_config "$DIR/agents/skills" "$HOME/.claude/skills"
link_config "$DIR/agents/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
link_config "$DIR/agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
link_config "$DIR/agents/pi/settings.json" "$HOME/.pi/agent/settings.json"
link_config "$DIR/home/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link_config "$DIR/agents/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"

if [ "$INSTALL_PI" = true ]; then
  command -v npm >/dev/null || {
    echo "npm is required: apply ./bootstrap.sh or ./rebuild.sh first." >&2
    exit 1
  }
  # User-owned prefix, already on the Home Manager PATH; no sudo needed.
  npm install --global --prefix "$HOME/.local" --ignore-scripts @earendil-works/pi-coding-agent
  "$HOME/.local/bin/pi" --version
fi

echo "Shared agent configuration installed."
