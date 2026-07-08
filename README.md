# dotfiles

Personal dotfiles for keeping the same terminal workflow across macOS and Ubuntu.
This repo is based on the structure of `kunchenguid/dotfiles`, adapted for `TheLoop705`.

## What this manages

- zsh with autosuggestions, syntax highlighting, aliases, and starship prompt
- common CLI tools through Home Manager: `rg`, `fd`, `fzf`, `jq`, `gh`, `git`, `lazygit`, `nvim`, `tmux`, `wget`
- Neovim with lazy.nvim, rose-pine moon, file picker, grep, git signs, Neogit, and Oil
- WezTerm config, with macOS-only blur guarded so the file also works on Linux
- herdr config
- shared agent instructions for Claude, Codex, and opencode
- Claude settings/status line
- gh config and global git ignore
- macOS system defaults and Homebrew inventory through nix-darwin

## Platform split

Portable user workflow lives in `home.nix` and `home/`.

macOS-only config lives in `configuration.nix`:

- Apple system defaults
- nix-homebrew
- Homebrew taps, formulae, and casks
- `aarch64-darwin` host platform for this Mac mini

Ubuntu uses Home Manager only. It does not apply macOS defaults or Homebrew.

## Targets

The flake exposes these targets:

```sh
# macOS on this Mac mini
.#mac

# Ubuntu/Linux x86_64
.#vpnuser@linux-x86_64

# Ubuntu/Linux ARM64
.#vpnuser@linux-aarch64
```

Change the single `user = "vpnuser";` line in `flake.nix` before using this repo on machines where the username differs.

## Fresh machine setup

Clone the repo:

```sh
git clone https://github.com/TheLoop705/dotfiles.git
cd dotfiles
```

Run:

```sh
./bootstrap.sh
```

`bootstrap.sh` does four things:

1. Installs Determinate Nix if `nix` is missing.
2. Symlinks the repo to `~/.dotfiles`.
3. Checks the flake username against the current account and offers to rewrite it.
4. Applies the right target for the current OS.

After bootstrap, use:

```sh
./rebuild.sh
```

`rebuild.sh` auto-detects macOS versus Linux and applies the matching target.

## Ubuntu 26.04 laptop setup

These steps are for a normal Ubuntu 26.04 laptop, run from that laptop's terminal or over SSH.
Do not run the bootstrap as root.

### 1. Install bootstrap prerequisites

```sh
sudo apt update
sudo apt install -y curl git xz-utils ca-certificates
```

### 2. Use the expected username

This repo currently has a single shared user value:

```nix
user = "vpnuser";
```

Best path: make the Ubuntu account username `vpnuser` too.
Then the Mac mini and Ubuntu laptop can use the same committed flake with no per-machine edits.

If the Ubuntu username is different, `./bootstrap.sh` will offer to rewrite `flake.nix`.
That works for the laptop, but it also changes the macOS target username because this repo intentionally has one user variable.
In that case, either commit that username change for all machines or add a per-host user split before using the repo on machines with different account names.

### 3. Clone and bootstrap

```sh
git clone https://github.com/TheLoop705/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

On Ubuntu, bootstrap will:

1. Install Determinate Nix if it is missing.
2. Symlink this checkout to `~/.dotfiles`.
3. Apply the matching Home Manager target.

For a typical Intel/AMD Ubuntu laptop, the target is:

```sh
.#vpnuser@linux-x86_64
```

For an ARM64 Ubuntu laptop, the target is:

```sh
.#vpnuser@linux-aarch64
```

### 4. Start using the shell

Home Manager installs and configures zsh, but Ubuntu may still log you into bash by default.
For the current session:

```sh
exec zsh -l
```

To make zsh permanent for future SSH and terminal sessions:

```sh
sudo apt install -y zsh
chsh -s /usr/bin/zsh
```

Then log out and back in.

### 5. Verify the laptop

```sh
command -v nvim tmux rg fd fzf lazygit starship
nix build '.#homeConfigurations."vpnuser@linux-x86_64".activationPackage' --dry-run
```

If the laptop is ARM64, use:

```sh
nix build '.#homeConfigurations."vpnuser@linux-aarch64".activationPackage' --dry-run
```

Useful workflow checks:

```sh
t                 # attach/create the main tmux session
nvim              # opens the repo-managed Neovim config
./rebuild.sh      # re-apply after editing Nix/Home Manager files
```

### 6. Updating later

```sh
cd ~/.dotfiles
git pull
./rebuild.sh
```

Home Manager backs up replaced files with the `hm-backup` suffix.
For example, if an existing zsh config was in the way, look for `~/.zshrc.hm-backup`.

### Ubuntu notes

- Ubuntu does not use `configuration.nix`; that file is macOS-only.
- Homebrew packages and casks are macOS-only.
- WezTerm config is linked on Ubuntu, but the WezTerm app itself is not installed by this repo on Ubuntu yet.
  Install WezTerm separately if you want to use it as the local laptop terminal.
- If you only SSH into the Mac mini from the Ubuntu laptop, the Ubuntu terminal app does not matter much; tmux, zsh, nvim, and the other commands run on the remote Mac.

## Validate without applying

After Nix is installed:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
nix build '.#homeConfigurations."vpnuser@linux-x86_64".activationPackage' --dry-run
```

For ARM64 Linux, use:

```sh
nix build '.#homeConfigurations."vpnuser@linux-aarch64".activationPackage' --dry-run
```

## Homebrew warning

`configuration.nix` intentionally sets:

```nix
homebrew.onActivation.cleanup = "zap";
```

On macOS, every switch removes Homebrew packages and casks that are not listed in `configuration.nix`.
This keeps the Mac reproducible, but it means any new manual `brew install` should be added to `configuration.nix` before the next `./rebuild.sh`.

The initial list was seeded from the current Mac mini Homebrew setup and then extended with upstream workflow tools such as `herdr`, `wezterm`, and `claude-code`.

This headless Mac manages Tailscale as the `tailscale` Homebrew formula.
The `tailscale-app` cask is not managed because its package installer requires macOS system-extension approval through the GUI and fails in a headless rebuild.

## Edit-in-place files

Home Manager uses out-of-store symlinks for config directories:

- `~/.config/nvim` -> `home/.config/nvim`
- `~/.config/wezterm` -> `home/.config/wezterm`
- `~/.config/herdr` -> `home/.config/herdr`
- `~/.config/gh/config.yml` -> `home/.config/gh/config.yml`
- `~/.config/git/ignore` -> `home/.config/git/ignore`
- `~/.claude/settings.json` -> `home/.claude/settings.json`
- Claude, Codex, and opencode agent files -> `home/AGENTS.md`

Editing files under `home/` changes the live config after the symlink is installed.
Run `./rebuild.sh` when changing Nix package lists, system settings, or Home Manager declarations.

## Notes

- Secrets, local databases, app caches, and machine-specific auth files are intentionally not tracked.
- `~/.claude/settings.local.json` is globally ignored.
- The existing Git identity is not managed here; keep using `git config --global user.name` and `git config --global user.email`.
- The first `nvim` launch bootstraps lazy.nvim plugins from GitHub.

## License

This repo is adapted from `kunchenguid/dotfiles`, licensed under MIT No Attribution.
See `LICENSE`.
