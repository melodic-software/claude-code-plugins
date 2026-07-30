# Claude Code cloud sessions — environment and setup for this repo

How Claude Code on the web (cloud sessions) is provisioned for this repository, and why the
setup lives where it does. Facts below were verified against the official pages on 2026-07-30:
[Cloud environments](https://code.claude.com/docs/en/cloud-environments),
[Hooks reference](https://code.claude.com/docs/en/hooks),
[Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web). Per the
[upstream-drift convention](conventions/upstream-drift/README.md), re-fetch before acting on them.

## Environments are per account, not per repository

A cloud environment (the **Update cloud environment** dialog: name, network access, environment
variables, setup script) is personal to a claude.ai account — or organization-shared when created
by an admin on Team/Enterprise plans. The same environment applies to every repository and every
surface that starts cloud sessions (web, `claude --cloud`, mobile, desktop, routines). There is no
per-repository environment.

The consequence for this repo: **nothing repo-specific belongs in the environment dialog**,
because the environment can't know which repo a session will open. Everything repo-specific
belongs in source control, where the official split puts it:

> Use a setup script to provision the VM itself: toolchains and CLI tools that aren't
> pre-installed. Use a SessionStart hook for project setup that should run everywhere, cloud and
> local, like `npm install`.

## What this repo commits: a SessionStart hook

- [`.claude/settings.json`](../.claude/settings.json) registers a `SessionStart` hook
  (matcher `startup|resume`). Repo-committed project settings are an official hook location and
  are honored in cloud sessions ("Your repo's `.claude/settings.json` hooks — Yes — Part of the
  clone").
- [`.claude/hooks/session-start.sh`](../.claude/hooks/session-start.sh) is the bootstrap it runs.
  It exits immediately unless `CLAUDE_CODE_REMOTE=true`, so local machines are never touched.

On a fresh cloud VM the hook takes ~40 s; on re-runs (session resume) ~3 s, because every step
checks before installing. It provisions the tool inventory
[`ci.yml`](../.github/workflows/ci.yml) pins, reading in-repo manifests wherever one exists:

| Tool | Pin source | Required? |
|---|---|---|
| Node | `.node-version` (via the VM's nvm) | required — the image ships Node 20/21/22; CI pins 24.x |
| claude CLI + Biome | root `package-lock.json` (`npm ci`) | required |
| ruff | `.github/requirements-ci.txt` (hash-locked) | required |
| shellcheck, actionlint, typos, editorconfig-checker, gitleaks | pinned in the hook (GitHub release binaries) | best effort — warns and continues |
| markdownlint-cli2, check-jsonschema | pinned in the hook (npm -g / uv tool) | best effort |
| full git history + `origin/main` | `git fetch` | best effort — the base-ref diff gates need it |

It also appends the session `PATH` (Node bin, `node_modules/.bin`, `~/.local/bin`) to
`$CLAUDE_ENV_FILE`, the documented channel for persisting environment variables into the
session's Bash commands.

Best-effort rather than required, deliberately: the plugin contract suites SKIP visibly when an
optional tool is absent and CI remains the enforcing gate, while a required install failure would
block the session from starting at all. GitHub release-asset downloads are additionally
best-effort because the GitHub proxy documents that release assets from repositories not attached
to the session can return 403.

Not installed at session start (install on demand when working in those areas): the four plugin
npm roots (`plugins/miro`, `plugins/knowledge/skills/youtube-digest/extraction`,
`plugins/knowledge/skills/course-digest/extraction`,
`plugins/ai-briefing/skills/generate/output/build`) and
`.github/standards/runner-policy` — each is an `npm ci` in that directory; the heavy ones pull
Playwright. `pwsh`, `go` tooling beyond the image, and `lychee` are likewise on-demand.

## Recommended environment dialog settings

With the hook in the repo, the environment stays generic and reusable across repos:

- **Name**: Default (or any shared environment).
- **Network access**: **Trusted** — the default allowlist covers npm, PyPI, nodejs.org, GitHub,
  and SchemaStore, which is everything the hook needs.
- **Environment variables**: none. Values are readable by anyone who uses the environment and
  there is no secrets store, so never put credentials here.
- **Setup script**: empty. Optionally, `gh` is the one tool better installed at the VM level
  (the hook doesn't install it; the built-in GitHub tools cover most needs, and in cloud sessions
  `gh` authenticates through the GitHub proxy automatically):

  ```bash
  #!/bin/bash
  apt update && apt install -y gh || true
  ```

Setup-script constraints, for anything added later: runs as root on Ubuntu 24.04, must exit zero,
must finish within about five minutes; its result is filesystem-snapshot cached and re-runs only
when the script or allowed network hosts change, or after roughly seven days.

## Maintenance caveats

- `.claude/settings.json` is materialized from `melodic-software/standards` (see
  [`AGENTS.md`](../AGENTS.md)). The `hooks` block here must be mirrored upstream in the standards
  repo, or the next sync can silently drop it.
- The hook's own version pins (shellcheck, actionlint, typos, editorconfig-checker, gitleaks,
  markdownlint-cli2) exist only because those tools have no in-repo manifest; the cloud proxy
  blocks the GitHub API and `releases/latest` redirects, so the hook can't self-resolve "latest".
  Bump them when the corresponding configs bump.
- User-level `~/.claude` config never reaches cloud sessions; anything a cloud session needs must
  be committed to the repo (or arrive via server-managed settings).
