# dictation-daemon

Vendored from [J-monti/whisper-dictation-linux](https://github.com/J-monti/whisper-dictation-linux)
(MIT, see `LICENSE`), with one local patch on top: the global hotkey listener was
rewritten from `rdev`'s X11-only backend to a raw `evdev` reader (one thread per
keyboard-capable device under `/dev/input`).

## Why vendored instead of a git dependency

The patch isn't pushed anywhere upstream-fetchable (the only git remote on the
original clone is `J-monti`'s own repo, not a fork of ours), so a fresh machine
running this flake couldn't otherwise get the fix. Vendoring the source here
means `home.nix`'s build step doesn't depend on any external repo at all.

## Why the X11 backend didn't work

`rdev`'s only published Linux backend uses X11 (`XRecord`, through XWayland).
Under a native Wayland session that only sees keystrokes while an XWayland-backed
window has focus -- native Wayland clients (many browsers, GNOME's own apps, etc.)
never route through XWayland, so the hotkey silently didn't fire there. Reading
`/dev/input` directly sees every keystroke at the kernel level regardless of
what has focus or which display protocol it uses.

## Requirement this doesn't solve

Reading `/dev/input/event*` and writing to `/dev/uinput` (for `ydotool` text
injection) both need this account in the `input` group. Home Manager can't grant
that on non-NixOS Linux -- see the README at the repo root for the one-time
`usermod` command.

## Updating this vendored copy

Pull upstream's changes into `~/github/whisper-dictation-linux` (or wherever
it's cloned), reapply the evdev patch if upstream touched the hotkey listener,
then copy `Cargo.toml`, `Cargo.lock`, and `src/main.rs` back into this directory.
