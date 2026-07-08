# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `homebrew.onActivation.cleanup = "zap"` in `configuration.nix` is intentional. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible. Do not soften it to `uninstall` or `none`. Users are warned about its effect in README.md; this note is for anyone tempted to change the setting itself.
- Keep this repo portable across macOS and Ubuntu. macOS system settings belong in `configuration.nix`; portable shell, editor, prompt, and agent settings belong in `home.nix` and `home/`.
- Never commit local validation evidence, machine secrets, Nix build outputs, runtime logs, or app caches.
