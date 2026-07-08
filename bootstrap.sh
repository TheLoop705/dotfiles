#!/usr/bin/env bash
# Takes a fresh macOS or Linux machine from nothing to a built dotfiles config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
OS="$(uname -s)"

if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

if [ -x /nix/var/nix/profiles/default/bin/nix ]; then
  export PATH="/nix/var/nix/profiles/default/bin:$PATH"
fi

linux_arch() {
  case "$(uname -m)" in
    x86_64) printf 'x86_64' ;;
    aarch64 | arm64) printf 'aarch64' ;;
    *)
      echo "Unsupported Linux architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

switch_target() {
  case "$OS" in
    Darwin) printf 'mac' ;;
    Linux) printf '%s@linux-%s' "$(whoami)" "$(linux_arch)" ;;
    *)
      echo "Unsupported operating system: $OS" >&2
      exit 1
      ;;
  esac
}

rewrite_flake_user() {
  case "$OS" in
    Darwin) sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix" ;;
    Linux) sed -i -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix" ;;
  esac
}

echo "==> Step 1: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: personalize the configured username"
# Do this before any sudo call: sudo resets $USER to root, so whoami has to run
# as the real interactive user first.
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    rewrite_flake_user
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

TARGET="$(switch_target)"
echo "==> Step 4: first switch for $TARGET"
case "$OS" in
  Darwin)
    # darwin-rebuild may not exist yet, so run it straight from the release
    # branch this once. The system config it applies is still pinned here.
    NIX_BIN="$(command -v nix)"
    sudo "$NIX_BIN" run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
      switch --flake "$HOME/.dotfiles#$TARGET"
    ;;
  Linux)
    nix run github:nix-community/home-manager/release-26.05 -- \
      switch -b hm-backup --flake "$HOME/.dotfiles#$TARGET"
    ;;
esac

echo "==> Done. Use ./rebuild.sh for future changes."
