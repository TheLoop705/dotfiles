{ lib, user, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  system.activationScripts.postActivation.text = lib.mkAfter ''
    zsh_site=/opt/homebrew/share/zsh/site-functions
    if [ -d "$zsh_site" ]; then
      chmod go-w /opt/homebrew /opt/homebrew/share

      # Homebrew migration left this symlink broken on this machine.
      if [ -L "$zsh_site/_brew" ] && [ ! -e "$zsh_site/_brew" ]; then
        rm -f "$zsh_site/_brew"
      fi

      for name in docker docker-compose; do
        src="/Applications/Docker.app/Contents/Resources/etc/$name.zsh-completion"
        dest="$zsh_site/_$name"
        if [ -f "$src" ]; then
          rm -f "$dest"
          install -m 0644 "$src" "$dest"
        fi
      done
    fi
  '';
  nix-homebrew = {
    enable = true;
    inherit user;
    autoMigrate = true;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    taps = [
      "hudochenkov/sshpass"
      "supabase/tap"
    ];
    brews = [
      "cocoapods"
      "docker-compose"
      "ffmpeg"
      "gh"
      "git"
      "gradle"
      "herdr"
      "htop"
      "libomp"
      "mas"
      "node"
      "nvm"
      "ollama"
      "openjdk@21"
      "podman"
      "podman-compose"
      "postgresql@16"
      "python@3.12"
      "python@3.13"
      "ser2net"
      "sevenzip"
      "sshpass"
      "supabase"
      "tailscale"
      "tmux"
      "wget"
      "xcodegen"
      "xcodes"
    ];
    casks = [
      "claude"
      "wezterm"
      "claude-code"
      "codex"
      "docker-desktop"
      "moonlight"
      "protonvpn"
      "retroarch"
      "stremio"
      "utm"
      "vlc"
      "warp"
    ];
  };
}
