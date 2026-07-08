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
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    BUN_INSTALL = "$HOME/.bun";
  };
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.bun/bin"
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
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
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      c = "clear";
      lg = "lazygit";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      t = "tmux new-session -A -s main";
      tn = "tmux new-session -s";
      v = "nvim";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
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
}
