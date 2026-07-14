local wezterm = require("wezterm")

local config = wezterm.config_builder()
local is_darwin = string.find(wezterm.target_triple, "darwin") ~= nil
local is_windows = string.find(wezterm.target_triple, "windows") ~= nil

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.8
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"
config.use_dead_keys = true

-- German macOS layouts need Option for @, braces, brackets, backslash, pipe,
-- and tilde. Let macOS compose those characters instead of treating Option as
-- terminal Meta.
config.send_composed_key_when_left_alt_is_pressed = true
config.send_composed_key_when_right_alt_is_pressed = true

config.keys = {
  { key = "Enter", mods = "CMD", action = wezterm.action.ToggleFullScreen },
  { key = "t", mods = "CMD", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "CMD", action = wezterm.action.CloseCurrentTab({ confirm = true }) },
  { key = "d", mods = "CMD", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "d", mods = "CMD|SHIFT", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "LeftArrow", mods = "CMD", action = wezterm.action.ActivatePaneDirection("Left") },
  { key = "DownArrow", mods = "CMD", action = wezterm.action.ActivatePaneDirection("Down") },
  { key = "UpArrow", mods = "CMD", action = wezterm.action.ActivatePaneDirection("Up") },
  { key = "RightArrow", mods = "CMD", action = wezterm.action.ActivatePaneDirection("Right") },
  { key = "h", mods = "CMD|CTRL", action = wezterm.action.ActivatePaneDirection("Left") },
  { key = "j", mods = "CMD|CTRL", action = wezterm.action.ActivatePaneDirection("Down") },
  { key = "k", mods = "CMD|CTRL", action = wezterm.action.ActivatePaneDirection("Up") },
  { key = "l", mods = "CMD|CTRL", action = wezterm.action.ActivatePaneDirection("Right") },
}

if is_darwin then
  config.macos_window_background_blur = 50
elseif is_windows then
  -- Native Windows GUI, Linux shell: use WezTerm's WSL domain instead of
  -- spawning cmd.exe or PowerShell. It preserves the working directory when
  -- creating tabs and panes, unlike launching `wsl.exe` as a local process.
  config.default_domain = "WSL:Ubuntu"
  config.wsl_domains = wezterm.default_wsl_domains()
  for _, domain in ipairs(config.wsl_domains) do
    if domain.name == config.default_domain then
      domain.default_prog = { "/usr/bin/zsh", "-l" }
    end
  end

  -- Windows-friendly counterparts to the existing macOS Super-key bindings.
  table.insert(config.keys, { key = "t", mods = "CTRL|SHIFT", action = wezterm.action.SpawnTab("CurrentPaneDomain") })
  table.insert(config.keys, { key = "w", mods = "CTRL|SHIFT", action = wezterm.action.CloseCurrentTab({ confirm = true }) })
  table.insert(config.keys, { key = "d", mods = "CTRL|SHIFT", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) })
  table.insert(config.keys, { key = "d", mods = "CTRL|SHIFT|ALT", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) })

  -- Ctrl+Shift+Space is the global Windows Whisper dictation shortcut.
  table.insert(config.keys, {
    key = "phys:Space",
    mods = "SHIFT|CTRL",
    action = wezterm.action.DisableDefaultAssignment,
  })
else
  -- Always launch zsh as a login shell on Linux, regardless of the
  -- account's default login shell in /etc/passwd.
  config.default_prog = { "/usr/bin/zsh", "-l" }

  -- Ctrl+Shift+Space is reserved system-wide for the Whisper dictation
  -- daemon. WezTerm's built-in QuickSelect default binds the same combo,
  -- so it has to be explicitly disabled here or it wins while WezTerm has
  -- focus. Mac mini keeps QuickSelect since it has no dictation daemon.
  table.insert(config.keys, {
    key = "phys:Space",
    mods = "SHIFT|CTRL",
    action = wezterm.action.DisableDefaultAssignment,
  })

  -- The Whisper dictation daemon grabs its global hotkey via X11 (it's
  -- linked against libX11/libxcb, through XWayland). Under native Wayland,
  -- X11 grabs structurally cannot see key events while a native Wayland
  -- window has focus -- that's a Wayland security boundary, not a bug in
  -- either app. Forcing WezTerm through the X11/XWayland backend makes it
  -- a window the dictation daemon's grab can actually see. Trade-off: text
  -- may render very slightly softer on this machine's fractional-scaled
  -- displays, since XWayland scales less precisely than native Wayland.
  config.enable_wayland = false

  -- Side effect of the XWayland switch above: keystrokes typed (or
  -- injected via ydotool/wtype, e.g. by the dictation daemon) into a
  -- WezTerm window now get resolved through XWayland's own independent
  -- X11 keymap instead of Mutter's native-Wayland one. XWayland defaults
  -- to "us" and never syncs with GNOME's configured layout, so on a
  -- German keyboard/input-source this silently swaps y/z and other keys
  -- that differ between the two layouts. WezTerm is the only thing on
  -- this machine that starts XWayland, so re-sync its keymap every time
  -- a WezTerm GUI process starts.
  wezterm.on("gui-startup", function()
    wezterm.background_child_process({ "/bin/setxkbmap", "de" })
  end)
end

return config
