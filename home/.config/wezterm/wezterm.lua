local wezterm = require("wezterm")

local config = wezterm.config_builder()
local is_darwin = string.find(wezterm.target_triple, "darwin") ~= nil

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

  -- The RESIZE decoration's custom-drawn border renders as a separate
  -- Wayland subsurface. On this machine's fractional display scaling it
  -- intermittently computes a buffer size that isn't a valid multiple of
  -- the compositor's integer buffer scale, which Wayland treats as a fatal
  -- protocol error and kills the whole process. Drop to no decorations on
  -- Linux; Mac mini keeps RESIZE since it isn't affected by this bug.
  config.window_decorations = "NONE"

  -- The Whisper dictation daemon grabs its global hotkey via X11 (it's
  -- linked against libX11/libxcb, through XWayland). Under native Wayland,
  -- X11 grabs structurally cannot see key events while a native Wayland
  -- window has focus -- that's a Wayland security boundary, not a bug in
  -- either app. Forcing WezTerm through the X11/XWayland backend makes it
  -- a window the dictation daemon's grab can actually see. Trade-off: text
  -- may render very slightly softer on this machine's fractional-scaled
  -- displays, since XWayland scales less precisely than native Wayland.
  config.enable_wayland = false
end

return config
