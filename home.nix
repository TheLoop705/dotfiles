{ config, pkgs, lib, user, homeDirectory ? (if pkgs.stdenv.isDarwin then "/Users/${user}" else "/home/${user}"), ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home.username = user;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  home.packages = with pkgs; [
    # CLI tools used constantly.
    ripgrep
    fd
    fzf
    jq        # json on the command line
    gh
    git
    htop
    lazygit
    neovim
    tmux
    wget
  ] ++ lib.optionals (pkgs ? nerd-fonts && pkgs.nerd-fonts ? hack) [
    pkgs.nerd-fonts.hack
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # Lets the Whisper dictation daemon type transcribed text via the
    # Wayland virtual-keyboard protocol. Linux-only; ydotool needs an
    # /dev/uinput group membership this account doesn't have, wtype needs
    # no special permissions under Mutter.
    wtype

    # Build deps for pkgs/dictation-daemon (see home.activation below):
    # cargo/rustc build it, cmake+libclang are needed by whisper-rs
    # (whisper.cpp via cmake, bindgen via libclang). ydotool is its
    # preferred text-injection path (wtype above is the fallback).
    # playerctl is optional (pause/resume media while recording).
    cargo
    rustc
    cmake
    gnumake
    llvmPackages.libclang
    ydotool
    playerctl
  ];
  # Deliberately NOT Nix packages, even though this project's build would
  # happily use them, because each one either gets linked straight into the
  # binary or determines what does: the system's gcc must be the actual
  # linker (not Nix's), because whatever compiler performs the final link
  # step is what embeds the binary's runtime dynamic loader -- Nix's gcc
  # embeds Nix's own hermetic loader, which only ever searches the Nix
  # store and can't see /usr/lib at all, in any environment, regardless of
  # LD_LIBRARY_PATH. That breaks every library linked into the result, not
  # just the ones covered below:
  # - alsa-lib: nixpkgs' build is minimal with no runtime plugins, so even
  #   with a working loader, it can't find the system's PipeWire ALSA
  #   plugin (different, incompatible plugin search path) and audio
  #   capture fails at runtime.
  # - dbus: pulls in a transitive runtime dep on libsystemd that only
  #   resolves inside a Nix-managed runtime, not a plain Ubuntu one.
  # - pkg-config: nixpkgs wraps it to search only Nix store paths, never
  #   system ones, by design (build purity) -- so it could never find the
  #   system's alsa.pc/dbus-1.pc regardless of PKG_CONFIG_PATH.
  # All three come from the system instead (see the "Manual steps" section
  # in the root README): build-essential (gcc), pkg-config, libasound2-dev,
  # libdbus-1-dev. home.activation.dictationDaemon below checks for them
  # before building and fails with an explicit apt command if they're
  # missing, rather than a confusing build or runtime error.
  fonts.fontconfig.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BUN_INSTALL = "$HOME/.bun";
    KUBECONFIG = "$HOME/.kube/config";
  };
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.bun/bin"
    "$HOME/.opencode/bin"
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    history = {
      size = 100000;
      save = 100000;
      path = "$HOME/.zsh_history";
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };
    initContent = ''
      bindkey '^f' autosuggest-accept

      if [ -s "$HOME/.bun/_bun" ] && (( $+functions[compdef] )); then
        source "$HOME/.bun/_bun"
      fi

      if command -v podman >/dev/null 2>&1; then
        alias docker=podman
        if [ -z "''${DOCKER_HOST:-}" ]; then
          PODMAN_SOCKET="$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' podman-machine-default 2>/dev/null || true)"
          if [ -n "$PODMAN_SOCKET" ]; then
            export DOCKER_HOST="unix://$PODMAN_SOCKET"
          fi
          unset PODMAN_SOCKET
        fi
      fi

      if command -v podman-compose >/dev/null 2>&1; then
        alias docker-compose=podman-compose
      fi

      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word
      bindkey '^[[3~' delete-char
      bindkey '^[[3;5~' kill-word
      bindkey '^[[H' beginning-of-line
      bindkey '^[[F' end-of-line
      bindkey '^[[1~' beginning-of-line
      bindkey '^[[4~' end-of-line

      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"

      command -v kubectl >/dev/null 2>&1 && source <(kubectl completion zsh)
      command -v podman >/dev/null 2>&1 && source <(podman completion zsh)

      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

      if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
      fi

      # Machine-specific profile: aliases/functions that only make sense on
      # this laptop. Deliberately not tracked in this repo.
      if [ -f "$HOME/.profile" ]; then
        source "$HOME/.profile"
      fi
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      c = "clear";
      stt = "systemctl --user status dictation.service";
      stt-start = "systemctl --user start dictation.service";
      stt-stop = "systemctl --user stop dictation.service";
      stt-restart = "systemctl --user restart dictation.service";
      stt-logs = "journalctl --user -u dictation.service -f";
      lg = "lazygit";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      t = "tmux new-session -A -s main";
      tn = "tmux new-session -s";
      v = "nvim";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
      ll = "ls -alF";
      la = "ls -A";
      l = "ls -CF";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".tmux.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.tmux.conf";
  home.file.".config/gh/config.yml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/gh/config.yml";
  home.file.".config/git/ignore".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/git/ignore";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # Standalone Home Manager on non-NixOS Linux can't reach into the systemd
  # user manager's own environment the way it does on real NixOS, so
  # systemd --user services (like the dictation daemon) don't see
  # ~/.nix-profile/bin in PATH and fail to find Nix-installed tools (wtype,
  # etc) even though an interactive shell does. Takes effect on next login.
  xdg.configFile."environment.d/50-nix-profile-path.conf" = lib.mkIf pkgs.stdenv.isLinux {
    text = ''
      PATH=${homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:''${PATH}
    '';
  };

  # Builds pkgs/dictation-daemon (vendored from J-monti/whisper-dictation-linux,
  # patched to read hotkeys via evdev instead of X11 -- see that directory's
  # README) and installs it to ~/.local/bin, skipping the build if the vendored
  # source hasn't changed since the last one. Also fetches the Whisper model
  # on first run. systemd.user.services.dictation below runs the result.
  home.activation.dictationDaemon = lib.mkIf pkgs.stdenv.isLinux (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      DICTATION_SRC="${dotfiles}/pkgs/dictation-daemon"
      DICTATION_BIN="$HOME/.local/bin/dictation"

      # Home Manager activation scripts run with a minimal bootstrap PATH,
      # not the interactive shell's -- /usr/bin isn't reliably on it, so
      # every system binary below is referenced by absolute path rather
      # than trusting PATH resolution. /usr/bin is also put first on the
      # PATH used for the actual build (below) so cargo's linker resolves
      # to the system's gcc, not a Nix one -- see the package-list comment
      # above for why that matters for a binary that has to run outside
      # Nix's own environment.
      SYSTEM_BIN=/usr/bin

      if [ ! -x "$DICTATION_BIN" ] \
        || [ "$DICTATION_SRC/src/main.rs" -nt "$DICTATION_BIN" ] \
        || [ "$DICTATION_SRC/Cargo.toml" -nt "$DICTATION_BIN" ]; then
        if [ ! -x "$SYSTEM_BIN/cc" ] || [ ! -x "$SYSTEM_BIN/pkg-config" ] \
          || ! "$SYSTEM_BIN/pkg-config" --exists alsa 2>/dev/null \
          || ! "$SYSTEM_BIN/pkg-config" --exists dbus-1 2>/dev/null; then
          echo "ERROR: a system C compiler, pkg-config, alsa.pc, and/or dbus-1.pc" >&2
          echo "       weren't found. Install them, then re-run this:" >&2
          echo "         sudo apt install build-essential pkg-config libasound2-dev libdbus-1-dev" >&2
          echo "       (deliberately not Nix packages here: see the comment on" >&2
          echo "       home.packages' dictation-daemon build deps in home.nix)" >&2
        else
          echo "Building dictation daemon..."
          # cargo/rustc/cmake come from the exact Nix store paths below
          # rather than depending on activation order (this runs before
          # installPackages links the generation into ~/.nix-profile). The
          # actual C compiler (cc/gcc), pkg-config, alsa.pc, and dbus-1.pc
          # are deliberately left to the system's own copies (see above).
          $DRY_RUN_CMD env \
            PATH="$SYSTEM_BIN:${pkgs.cmake}/bin:${pkgs.gnumake}/bin:${pkgs.cargo}/bin:${pkgs.rustc}/bin:$PATH" \
            LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib" \
            ${pkgs.cargo}/bin/cargo build --release \
              --manifest-path "$DICTATION_SRC/Cargo.toml" \
              --target-dir "$DICTATION_SRC/target"
          $DRY_RUN_CMD mkdir -p "$HOME/.local/bin"
          $DRY_RUN_CMD install -m755 "$DICTATION_SRC/target/release/dictation" "$DICTATION_BIN"
        fi
      fi

      $DRY_RUN_CMD mkdir -p "$HOME/whisper-models"
      if [ ! -f "$HOME/whisper-models/ggml-base.en.bin" ]; then
        echo "Downloading Whisper base.en model (~150MB)..."
        $DRY_RUN_CMD ${pkgs.wget}/bin/wget -q -O "$HOME/whisper-models/ggml-base.en.bin.part" \
          https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
        $DRY_RUN_CMD mv "$HOME/whisper-models/ggml-base.en.bin.part" "$HOME/whisper-models/ggml-base.en.bin"
      fi

      if ! id -nG | tr ' ' '\n' | grep -qx input; then
        echo "WARNING: $(id -un) is not in the 'input' group -- the dictation" >&2
        echo "         hotkey will not work until you run:" >&2
        echo "           sudo usermod -aG input $(id -un)" >&2
        echo "         then log out and back in." >&2
      fi
    ''
  );

  systemd.user.services.dictation = lib.mkIf pkgs.stdenv.isLinux {
    Unit = {
      Description = "Whisper Dictation Daemon (local speech-to-text)";
      After = [ "graphical-session.target" ];
      Wants = [ "ydotool.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/.local/bin/dictation";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Desktop/application-menu launchers for the user service. The start
  # launcher is also copied to ~/Desktop on Linux so the daemon can be
  # started without opening a terminal.
  xdg.desktopEntries = lib.mkIf pkgs.stdenv.isLinux {
    "whisper-dictation-start" = {
      name = "Start Whisper Dictation";
      comment = "Start the local Whisper speech-to-text service";
      exec = "systemctl --user start dictation.service";
      icon = "audio-input-microphone";
      terminal = false;
      categories = [ "AudioVideo" "Audio" ];
    };
    "whisper-dictation-stop" = {
      name = "Stop Whisper Dictation";
      comment = "Stop the local Whisper speech-to-text service";
      exec = "systemctl --user stop dictation.service";
      icon = "audio-input-microphone";
      terminal = false;
      categories = [ "AudioVideo" "Audio" ];
    };
    "whisper-dictation-restart" = {
      name = "Restart Whisper Dictation";
      comment = "Restart the local Whisper speech-to-text service";
      exec = "systemctl --user restart dictation.service";
      icon = "audio-input-microphone";
      terminal = false;
      categories = [ "AudioVideo" "Audio" ];
    };
  };

  home.file."Desktop/Whisper Dictation.desktop" = lib.mkIf pkgs.stdenv.isLinux {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Start Whisper Dictation
      Comment=Start the local Whisper speech-to-text service
      Exec=systemctl --user start dictation.service
      Icon=audio-input-microphone
      Terminal=false
      Categories=AudioVideo;Audio;
    '';
    executable = true;
  };
  systemd.user.startServices = lib.mkIf pkgs.stdenv.isLinux "sd-switch";
}
