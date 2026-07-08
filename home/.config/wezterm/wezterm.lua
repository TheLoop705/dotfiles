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
end

return config
