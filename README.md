# dotfiles

Personal dotfiles for keeping the same terminal workflow across macOS and Ubuntu.
This repo is based on the structure of `kunchenguid/dotfiles`, adapted for `TheLoop705`.

## What this manages

- zsh with autosuggestions, syntax highlighting, aliases, and starship prompt
- common CLI tools through Home Manager: `rg`, `fd`, `fzf`, `jq`, `gh`, `git`, `lazygit`, `nvim`, `tmux`, `wget`
- a local Whisper dictation daemon (Linux only) — global hotkey works in any app, any window, regardless of display protocol; builds and installs itself automatically, see "Whisper dictation daemon" below
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
.#sultan@linux-x86_64

# Ubuntu/Linux ARM64
.#sultan@linux-aarch64
```

`flake.nix` uses a per-host username: `macUser` for the Darwin target, `linuxUser` for the Linux targets. Change whichever one applies before using this repo on a machine with a different account name — editing one never affects the other.

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

The dictation daemon (see "Whisper dictation daemon" below) additionally needs
`sudo apt install -y build-essential pkg-config libasound2-dev libdbus-1-dev`
and this account in the `input` group. `./rebuild.sh` builds and installs it
automatically once those are in place — it isn't part of the bootstrap
prerequisites above because it's Linux-specific and only strictly needed if
you want dictation working.

### 2. Username is already per-host

`flake.nix` keeps a separate username per platform, so editing one never touches the other:

```nix
macUser = "vpnuser";
linuxUser = "sultan";
```

This laptop's account is already `sultan`, matching `linuxUser`, so there's nothing to change here.
If you ever use this repo on a different Ubuntu/Linux account, either edit `linuxUser` in `flake.nix` yourself or let `./bootstrap.sh` do it — it checks `linuxUser` against the current account (`macUser` on macOS) and offers to rewrite just that line.

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
.#sultan@linux-x86_64
```

For an ARM64 Ubuntu laptop, the target is:

```sh
.#sultan@linux-aarch64
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
nix build '.#homeConfigurations."sultan@linux-x86_64".activationPackage' --dry-run
```

If the laptop is ARM64, use:

```sh
nix build '.#homeConfigurations."sultan@linux-aarch64".activationPackage' --dry-run
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
nix build '.#homeConfigurations."sultan@linux-x86_64".activationPackage' --dry-run
```

For ARM64 Linux, use:

```sh
nix build '.#homeConfigurations."sultan@linux-aarch64".activationPackage' --dry-run
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

## Whisper dictation daemon

Vendored at `pkgs/dictation-daemon/` from
[J-monti/whisper-dictation-linux](https://github.com/J-monti/whisper-dictation-linux)
(MIT), patched to read its global hotkey via raw `evdev` instead of `rdev`'s
X11-only backend — see that directory's own README for why. Ctrl+Shift+Space
starts/stops recording and types the transcription wherever the cursor is,
in any app, native Wayland or not.

`home.activation.dictationDaemon` in `home.nix` builds it with `cargo` and
installs it to `~/.local/bin/dictation` automatically on every
`./rebuild.sh`, skipping the build if the vendored source hasn't changed.
`systemd.user.services.dictation` runs it (`After=graphical-session.target`,
restarts on failure). It also fetches the Whisper model
(`~/whisper-models/ggml-base.en.bin`, ~150MB) on first run if missing.

Three things Nix deliberately doesn't provide for this build, and why (full
reasoning is in `home.nix`'s comment on the dictation-daemon package list):

- **A C compiler.** The linker that performs the final link step is what
  embeds a binary's runtime dynamic loader. Nix's `gcc` embeds Nix's own
  hermetic loader, which only ever searches the Nix store — never
  `/usr/lib` — in any environment, regardless of `LD_LIBRARY_PATH`. That
  breaks every system library linked into the result. The system's `gcc`
  (`build-essential`) is required so the binary gets a normal loader.
- **ALSA.** Even with a working loader, nixpkgs' `alsa-lib` is a minimal
  build with no runtime plugins, so it can't find the system's PipeWire
  ALSA plugin (different, incompatible search path) and audio capture
  fails. The system's `libasound2-dev` is required instead.
- **D-Bus.** Pulls in a transitive runtime dependency on `libsystemd` that
  only resolves inside a Nix-managed runtime. The system's `libdbus-1-dev`
  is required instead.

(`pkg-config` itself is also required from the system, since nixpkgs wraps
its own copy to search only Nix store paths by design.)

`home.activation.dictationDaemon` checks for all of these before building
and prints the exact `apt install` command if anything is missing, rather
than a confusing build or runtime error.

**Reading `/dev/input/event*` (the hotkey) and writing to `/dev/uinput`
(ydotool's text injection) both need this account in the `input` group.**
Home Manager can't grant that on non-NixOS Linux — it's a one-time manual
step:

```sh
sudo usermod -aG input "$(whoami)"
```

Then log out and back in (group membership is applied at login). Until
then, the daemon starts and runs, but the hotkey silently does nothing —
`home.activation.dictationDaemon` also checks for this and prints a warning
if it's missing.

## Notes

- Secrets, local databases, app caches, and machine-specific auth files are intentionally not tracked.
- `~/.profile` is also intentionally not tracked (not even referenced from `home/`): it holds laptop-specific aliases and SSH/bastion helpers that only make sense on one exact machine. `home.nix`'s `programs.zsh.initContent` sources `~/.profile` automatically when it exists, so it still loads on every shell without ever being committed.
- `~/.claude/settings.local.json` is globally ignored.
- The existing Git identity is not managed here; keep using `git config --global user.name` and `git config --global user.email`.
- The first `nvim` launch bootstraps lazy.nvim plugins from GitHub.

## Manual steps for this laptop (2026-07-09 setup)

Everything else in this README is already applied on this Ubuntu laptop as of today. What's left is either genuinely manual (needs an interactive password) or worth a deliberate look rather than a silent overwrite:

1. **Make zsh your system-wide login shell (optional).** WezTerm already launches zsh directly for every pane/tab via `home/.config/wezterm/wezterm.lua`, so this isn't required for day-to-day use — but if you also want zsh on a plain TTY or over SSH:

   ```sh
   chsh -s "$(command -v zsh)"
   ```

   This needs your account password interactively, so it can't be scripted. Log out and back in afterward.

2. ~~`ydotool.service` is inactive.~~ Resolved 2026-07-10 — see below; it needed the `input` group, same as the dictation daemon's hotkey.

3. **`~/.config/git` was root-owned on this account** (unclear why). Its one file already matched what this repo wanted, so activation skipped it harmlessly instead of erroring, but it isn't a proper Home Manager symlink like the others yet. To fully tidy it up: `sudo chown -R "$(whoami):$(whoami)" ~/.config/git`, then re-run `./rebuild.sh`.

4. **Review the merged Claude/Codex config.** `home/.claude/settings.json` and `home/AGENTS.md` now combine this laptop's prior local setup (an `env` block routing to a local Ollama server, `model: haiku`, the sandbox access-rules text) with the repo's fuller permissions/plugins list — including `defaultMode: bypassPermissions`, which was already in this repo before today and was kept intentionally. If anything about the merged behavior surprises you, the pre-merge versions are still on disk:
   - `~/.claude/settings.json.hm-backup`
   - `~/.claude/CLAUDE.md.hm-backup`
   - `~/.codex/AGENTS.md.hm-backup`
   - `~/.config/gh/config.yml.hm-backup`
   - `~/.config/starship.toml.hm-backup`

5. **Backups from the original, pre-Home-Manager local setup** are also still on disk, safe to delete once you've confirmed everything works:
   - `~/.zshrc.backup-before-dotfiles.20260708142711`
   - `~/.profile.backup-before-dotfiles.20260708142711`
   - `~/.codex/config.toml.backup-before-dotfiles.20260708142711`

6. **After a reboot, confirm:**
   - Ctrl+Alt+T opens a WezTerm window running zsh, with autosuggestions and syntax highlighting active.
   - The starship prompt renders.
   - `tmux` (or the `t` alias) starts with prefix `Ctrl+a`.
   - Ctrl+Shift+Space still triggers dictation.
   - `nvim` opens the lazy.nvim-managed config.

## Manual steps for this laptop (2026-07-10: dictation daemon)

The dictation daemon's global hotkey wasn't reaching some apps (native
Wayland windows specifically) and text wasn't typing at all. Both are fixed
now — see "Whisper dictation daemon" above for the full explanation — but
two things from that work are worth knowing about:

1. **This account was added to the `input` group today** (`sudo usermod -aG
   input sultan`, already applied and logged back in on this laptop). A
   fresh machine running this flake needs the same one-time command —
   `home.activation.dictationDaemon` prints a warning if it's missing
   rather than failing silently.

2. **`~/.config/systemd/user/dictation.service` and
   `~/.config/systemd/user/default.target.wants/dictation.service`** were
   previously a plain copied file and a manually-`systemctl enable`d
   symlink from before this repo managed the service declaratively. Both
   got moved aside automatically during activation
   (`dictation.service.hm-backup`, `dictation.service.hm-backup` under
   `default.target.wants/`) — safe to delete once you've confirmed the
   dictation service still starts on login.

## License

This repo is adapted from `kunchenguid/dotfiles`, licensed under MIT No Attribution.
See `LICENSE`.
