#!/usr/bin/env bash
# Install the Ubuntu system services needed for remote access. Home Manager
# owns user applications; this script owns only root-level Ubuntu/Tailscale
# setup and local machine enrollment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SETUP_USER="$(id -un)"

if [ "$(uname -s)" != "Linux" ] || [ ! -r /etc/os-release ]; then
  echo "This setup is only for Ubuntu Linux." >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ] || [ -z "${VERSION_CODENAME:-}" ]; then
  echo "Expected Ubuntu with VERSION_CODENAME in /etc/os-release." >&2
  exit 1
fi

if [ "$SETUP_USER" = "root" ]; then
  echo "Run this script as the desktop user, not root; it uses sudo itself." >&2
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  SETUP_TMP="$(mktemp -d)"
  trap 'rm -rf "$SETUP_TMP"' EXIT

  echo "==> Adding the official Tailscale apt repository for $VERSION_CODENAME"
  curl -fsSL -o "$SETUP_TMP/tailscale-archive-keyring.gpg" \
    "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg"
  curl -fsSL -o "$SETUP_TMP/tailscale.list" \
    "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list"
  sudo install -D -m 0644 "$SETUP_TMP/tailscale-archive-keyring.gpg" \
    /usr/share/keyrings/tailscale-archive-keyring.gpg
  sudo install -D -m 0644 "$SETUP_TMP/tailscale.list" \
    /etc/apt/sources.list.d/tailscale.list

  echo "==> Installing Tailscale"
  sudo apt-get update
  sudo apt-get install -y tailscale
else
  echo "==> Tailscale is already installed"
fi

echo "==> Enabling Tailscale and persistent user services"
sudo systemctl enable --now tailscaled.service
sudo loginctl enable-linger "$SETUP_USER"

echo "==> Enabling Tailscale SSH"
if sudo tailscale status >/dev/null 2>&1; then
  sudo tailscale set --ssh
else
  sudo tailscale up --ssh
fi

echo "==> Ubuntu remote-work setup complete"
echo "    Install Tailscale plus an SSH client on the iPhone, then SSH to this"
echo "    machine's Tailscale name. SSH auto-attaches tmux."
