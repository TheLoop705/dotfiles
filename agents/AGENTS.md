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

## Release branches

- Never push to a release branch directly (`release/*`, e.g. `release/2026.10.x`, `release/2026.10.0.x`), even when asked to force-push or "push wherever". Release branches change only through reviewed pull requests.
- Push only the ticket branch, always with an explicit refspec: `git push origin <branch>:refs/heads/<branch>`. A plain `git push` can follow an upstream inherited from a release branch.
- When creating a branch from a release branch, do not let it track the release branch: use `git switch --no-track -c <branch> origin/release/<x>`, or set the upstream to the ticket branch on the first push (`git push -u origin <branch>:refs/heads/<branch>`).
- Before any push, check `git rev-parse --abbrev-ref @{upstream}`. If it names a release branch, stop and fix the upstream.

## UFA / ATCloud releases (CPRC)

Applies to the ufa repository (`~/dev/ufa`, ATCloud in `web/projects/ATCloud`) and the devops repository (`~/dev/devops`).

- CPRC = three releases per year, named `m<n>-<year>`:

  | Release | Version line | CPRC branch |
  |---|---|---|
  | `m1-<year>` | `<year>.02` | `release/<year>.02.x` |
  | `m2-<year>` | `<year>.06` | `release/<year>.06.x` |
  | `m3-<year>` | `<year>.10` | `release/<year>.10.x` |

  Example: `m3-2026` = `release/2026.10.x`. `main` is always the next, unreleased CPRC (as of 2026-10: `m1-2027`, version line `2027.02`).
- Service releases branch from the CPRC branch as `release/<year>.<MM>.<patch>.x` (e.g. `release/2026.10.0.x`).
- Build tags (Git tags and container image tags):
  - mainline (internal) builds: `<year>.<MM><letters>`, e.g. `2027.02ay`, an internal `m1-2027` build from `main`
  - release-branch builds: `<year>.<MM>.<patch><letters>`, e.g. `2026.10.1j` (m3-2026, service release 1)
  - voice client-pod images append `.cyrus`, e.g. `2027.02ay.cyrus`
  - Helm chart versions must be SemVer: `2026.10.0ac` -> `2026.10.0-ac`; mainline `2027.02ay` -> `2027.02.0-ay`
- An environment named for a release (e.g. EKS customer `m1-2027-k8s`) uses only images built for that release line. Do not mix `m3-2026` images into an `m1-2027` deployment.
- Git conventions: ticket branches `dev/sd/<TICKET>` (e.g. `dev/sd/CLOUD-9886`) from `main` unless the user names a release base. Commit subjects follow `<TICKET> - <COMPONENT> - <what changed>`. See the `git-branching-workflow` skill for staging, `lib`/`ivy` submodule boundaries, pull and push rules.
