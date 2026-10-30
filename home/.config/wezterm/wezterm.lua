local wezterm = require("wezterm")
local config = wezterm.config_builder()

local is_windows = os.getenv("OS") and os.getenv("OS"):lower():find("windows")
local is_macos = wezterm.target_triple:lower():find("darwin") ~= nil
local is_linux = wezterm.target_triple:lower():find("linux") ~= nil

config.color_scheme = "rose-pine-moon"
-- config.color_scheme = "Builtin Solarized Light"

config.max_fps = 120
config.font = wezterm.font("Hack Nerd Font", { weight = "DemiBold" })
config.font_size = 13.0

config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.window_frame = {
  font = wezterm.font("Hack Nerd Font", { weight = "Bold" }),
  font_size = 11.0,
}

config.inactive_pane_hsb = {
  saturation = 0.0,
  brightness = 0.5,
}

if is_windows then
  config.win32_system_backdrop = "Acrylic"
  config.window_background_opacity = 0.7
  config.window_frame.font_size = 10.0

  -- Run the portable shell setup inside Ubuntu rather than cmd.exe or
  -- PowerShell. New tabs and panes inherit this WSL domain.
  config.default_domain = "WSL:Ubuntu"
  config.wsl_domains = wezterm.default_wsl_domains()
  for _, domain in ipairs(config.wsl_domains) do
    if domain.name == config.default_domain then
      domain.default_prog = { "/usr/bin/zsh", "-l" }
    end
  end
else
  -- Login zsh loads ~/.profile and automatically attaches to tmux.
  config.default_prog = { "zsh", "-l" }
end

if is_macos then
  config.window_background_opacity = 0.8
  config.macos_window_background_blur = 50
  config.font_size = 15.0
  config.window_frame.font_size = 13.0
end

if is_linux then
  -- Prefer X11/XWayland; GNOME's Wayland monitor reconfiguration can
  -- invalidate the client connection when the laptop lid/display changes.
  config.enable_wayland = false
  config.window_background_opacity = 0.95
end

-- keys
local act = wezterm.action

config.disable_default_key_bindings = true
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }

local function resize_window(width, height)
  return wezterm.action_callback(function(window, pane)
    window:set_inner_size(width, height)
  end)
end

config.keys = {
  -- Copy / paste
  {
    key = "c",
    mods = "CTRL|SHIFT",
    action = act.CopyTo("Clipboard"),
  },
  {
    key = "v",
    mods = "CTRL|SHIFT",
    action = act.PasteFrom("Clipboard"),
  },

  -- Search scrollback
  {
    key = "f",
    mods = "CTRL|SHIFT",
    action = act.Search({ CaseInSensitiveString = "" }),
  },

  -- Command palette
  {
    key = "p",
    mods = "CTRL|SHIFT",
    action = act.ActivateCommandPalette,
  },

  -- Font size
  {
    key = "+",
    mods = "CTRL|SHIFT",
    action = act.IncreaseFontSize,
  },
  {
    key = "-",
    mods = "CTRL|SHIFT",
    action = act.DecreaseFontSize,
  },
  {
    key = "0",
    mods = "CTRL|SHIFT",
    action = act.ResetFontSize,
  },

  -- Preset WezTerm window sizes
  {
    key = "1",
    mods = "LEADER",
    action = resize_window(900, 600),
  },
  {
    key = "2",
    mods = "LEADER",
    action = resize_window(1200, 800),
  },
  {
    key = "3",
    mods = "LEADER",
    action = resize_window(2100, 1200),
  },

  -- Fullscreen / reload
  {
    key = "f",
    mods = "LEADER",
    action = act.ToggleFullScreen,
  },
  {
    key = "r",
    mods = "LEADER",
    action = act.ReloadConfiguration,
  },

  -- Optional: keep WezTerm tabs/panes available, but secondary to tmux
  {
    key = "n",
    mods = "LEADER",
    action = act.SpawnTab("CurrentPaneDomain"),
  },
  {
    key = "s",
    mods = "LEADER",
    action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
  },
  {
    key = "v",
    mods = "LEADER",
    action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
  },
  {
    key = "x",
    mods = "LEADER",
    action = act.CloseCurrentPane({ confirm = true }),
  },
}

return config
