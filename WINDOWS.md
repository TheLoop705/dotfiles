# Windows + WSL 2 setup

This is the Windows counterpart to the macOS and Ubuntu setup. It keeps the
host operating system as Windows and runs the shared Nix/Home Manager workflow
inside Ubuntu on WSL 2. It does **not** install NixOS.

## What this configures

- WSL 2 with an Ubuntu development environment.
- Nix and the repo's `wsl-*` Home Manager target inside Ubuntu.
- zsh, Neovim, tmux, Starship, GitHub CLI, and the rest of the portable CLI
  tools from `home.nix`.
- Native Windows WezTerm, configured to open directly into the Ubuntu WSL
  domain with zsh as a login shell.
- Windows Terminal, which automatically discovers the Ubuntu WSL profile.

## Weston and WSLg

WSLg already uses a Microsoft-managed Weston compositor. Do not install and
launch a second standalone Weston session in WSL: it is unnecessary and does
not integrate with the Windows desktop. A healthy WSLg install exposes the
Wayland socket at `/mnt/wslg/runtime-dir/wayland-0`; Linux GUI programs will
then appear as normal Windows windows.

Check it from Ubuntu:

```sh
test -S /mnt/wslg/runtime-dir/wayland-0 && echo "WSLg/Weston is ready"
```

## Fresh Windows machine

### 1. Install WSL 2 and Ubuntu

Open an elevated PowerShell window and run:

```powershell
wsl --install -d Ubuntu
wsl --update
```

Restart if Windows asks, then open **Ubuntu** once and create its Linux user.
Confirm the distribution uses WSL 2:

```powershell
wsl --list --verbose
```

The Ubuntu row must show version `2`. Enable systemd in `/etc/wsl.conf` if the
distribution was created without it, then run `wsl --shutdown` from PowerShell
and reopen Ubuntu:

```ini
[boot]
systemd=true
```

### 2. Install the Windows terminal applications

Run these in normal PowerShell. Windows Terminal is often already installed;
the commands are safe to repeat.

```powershell
winget install --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements
winget install --id Microsoft.WindowsTerminal --exact --source winget --accept-package-agreements --accept-source-agreements
winget install --id wez.wezterm --exact --source winget --accept-package-agreements --accept-source-agreements
```

Windows Terminal's generated **Ubuntu** profile is ready to use without editing
its settings. Use its Ubuntu profile whenever you prefer the Microsoft terminal.

### 3. Clone the repo on Windows and link the native WezTerm configuration

Keep a small Windows checkout for the native WezTerm config. Development
projects, including a second checkout of this repo, belong in the Linux file
system rather than under `/mnt/c`.

```powershell
git clone https://github.com/TheLoop705/dotfiles.git "$HOME\dotfiles"
New-Item -ItemType Directory -Force -Path "$HOME\.config"
New-Item -ItemType Junction -Path "$HOME\.config\wezterm" -Target "$HOME\dotfiles\home\.config\wezterm"
```

If `~/.config/wezterm` already exists, move it somewhere safe before creating
the junction.

The shared `wezterm.lua` recognizes Windows and sets `WSL:Ubuntu` as its default
domain. WezTerm therefore opens directly into WSL and preserves Linux working
directories across new tabs and panes. Its Windows shortcuts are:

- `Ctrl+Shift+T`: new WSL tab
- `Ctrl+Shift+D`: split horizontally
- `Ctrl+Shift+Alt+D`: split vertically
- `Ctrl+Shift+W`: close the current tab (with confirmation)

### 4. Bootstrap the Linux development environment

Inside the **Ubuntu** profile in Windows Terminal or WezTerm, run:

```sh
sudo apt update
sudo apt install -y curl git xz-utils ca-certificates zsh
git clone https://github.com/TheLoop705/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
chsh -s /usr/bin/zsh
```

`bootstrap.sh` installs Determinate Nix if needed, links `~/dotfiles` to
`~/.dotfiles`, and applies `.#<your-linux-user>@wsl-x86_64` (or the ARM64
equivalent). If the configured `wslUser` differs from the Ubuntu account, it
offers to update only that WSL-specific value; the normal Ubuntu target remains
unchanged.

Start a fresh configured shell after the switch:

```sh
exec zsh -l
```

`chsh` asks for the Ubuntu account password and makes zsh the default for the
Windows Terminal Ubuntu profile as well. WezTerm already launches zsh directly.

### 5. Verify

From Ubuntu:

```sh
command -v nix nvim tmux rg fd fzf lazygit starship
nix flake check --no-build
t
```

From PowerShell:

```powershell
wsl -d Ubuntu -- bash -lc 'test -S /mnt/wslg/runtime-dir/wayland-0 && echo WSLg-ready'
wezterm.exe start --domain WSL:Ubuntu
```

`wezterm.exe start --domain WSL:Ubuntu` is also a useful diagnostic if a normal
WezTerm launch does not open an Ubuntu shell.

## Updating later

Update the Linux checkout and reapply Home Manager:

```sh
cd ~/.dotfiles
git pull
./rebuild.sh
```

When a commit changes `home/.config/wezterm`, update the small Windows checkout
as well, then restart WezTerm:

```powershell
git -C "$HOME\dotfiles" pull
```

## Local speech-to-text dictation

The Windows-native dictation service lives in
[`windows/whisper-dictation`](windows/whisper-dictation). It runs the local,
multilingual Whisper `small` model through faster-whisper using CPU INT8, which
is a good accuracy/speed balance for German and English. It loads the model at
Windows sign-in and never sends recorded speech to a cloud service.

Install it from normal PowerShell:

```powershell
& "$HOME\dotfiles\windows\whisper-dictation\install.ps1"
```

Use `Ctrl+Shift+Space` once to begin recording and again to stop. The service
transcribes the recording and types the text into the app that had focus. See
[`windows/whisper-dictation/README.md`](windows/whisper-dictation/README.md)
for behavior, files, and troubleshooting.

## Troubleshooting

- If WezTerm reports that `WSL:Ubuntu` is unavailable, run `wsl --list --verbose`.
  The distribution name must be `Ubuntu`; otherwise change `config.default_domain`
  in `home/.config/wezterm/wezterm.lua` to `WSL:<exact distribution name>`.
- If a GUI Linux application cannot connect, run `wsl --update`, then
  `wsl --shutdown`, reopen Ubuntu, and repeat the Weston socket check above.
- Do not develop out of `/mnt/c/...`: the Linux file system is faster and avoids
  executable-permission, file-watcher, and symlink edge cases.
