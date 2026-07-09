# Shared agent instructions

- Keep responses direct and action-oriented.
- Do not restart, shut down, log out, or close remote sessions unless explicitly asked.
- Do not commit secrets, machine tokens, local databases, caches, or generated runtime state.
- Prefer small, reviewable changes and verify them with the closest practical command.
- Always prefer concise technical answers.

## Access rules

Exception: `~/.codex` may be inspected and modified for Codex configuration and skills work.

Do not read parent directories, home directories, SSH files, shell history, environment files, credential stores, .env files, or unrelated projects.

You may run read/write/execute commands without per-command approval when they remain inside this workspace sandbox.

Ask for approval only when an escalation outside the sandbox is required, including network access, package installation, or touching files outside the approved workspace paths.
