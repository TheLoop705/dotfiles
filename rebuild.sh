#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

if [ -x /nix/var/nix/profiles/default/bin/nix ]; then
  export PATH="/nix/var/nix/profiles/default/bin:$PATH"
fi

ln -sfn "$DIR" ~/.dotfiles

case "$(uname -s)" in
  Darwin)
    TARGET="${DOTFILES_DARWIN_TARGET:-mac}"
    if command -v darwin-rebuild >/dev/null 2>&1; then
      exec sudo darwin-rebuild switch --flake "$HOME/.dotfiles#$TARGET"
    fi
    NIX_BIN="$(command -v nix)"
    exec sudo "$NIX_BIN" run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
      switch --flake "$HOME/.dotfiles#$TARGET"
    ;;
  Linux)
    case "$(uname -m)" in
      x86_64) ARCH="x86_64" ;;
      aarch64 | arm64) ARCH="aarch64" ;;
      *)
        echo "Unsupported Linux architecture: $(uname -m)" >&2
        exit 1
        ;;
    esac
    TARGET="${DOTFILES_HOME_TARGET:-$(whoami)@linux-$ARCH}"
    if command -v home-manager >/dev/null 2>&1; then
      exec home-manager switch -b hm-backup --flake "$HOME/.dotfiles#$TARGET"
    fi
    exec nix run github:nix-community/home-manager/release-26.05 -- \
      switch -b hm-backup --flake "$HOME/.dotfiles#$TARGET"
    ;;
  *)
    echo "Unsupported operating system: $(uname -s)" >&2
    exit 1
    ;;
esac
