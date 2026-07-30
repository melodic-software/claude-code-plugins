# Claude Code cloud sessions — concepts, setup guide, and this repo's setup

A how-to for provisioning Claude Code on the web (cloud sessions): what the pieces are, how to
set them up for any account or repository, and how this repository is set up. Details
deliberately live in the linked official pages, not here — link freshness was verified on
2026-07-30, and per the [upstream-drift convention](conventions/upstream-drift/README.md) you
should re-fetch a page before acting on it.

## What this is

- [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) runs each
  session in a fresh, isolated cloud VM with your repository cloned into it.
- Every session runs inside a
  [cloud environment](https://code.claude.com/docs/en/cloud-environments) — the dialog with name,
  network access, environment variables, and setup script. Environments are **scoped to your
  claude.ai account** (or
  [shared org-wide by an admin](https://code.claude.com/docs/en/cloud-environments#organization-shared-environments)),
  **not to a repository**: one environment serves every repo and every surface that starts cloud
  sessions (web, `claude --cloud`, mobile, desktop, routines).
- Two setup mechanisms exist, with an
  [official division of labor](https://code.claude.com/docs/en/cloud-environments#setup-scripts-vs-sessionstart-hooks):
  the environment's **setup script** provisions the VM itself (toolchains, CLI tools), while a
  repo-committed **[SessionStart hook](https://code.claude.com/docs/en/hooks#sessionstart)**
  handles project setup and runs in local and cloud sessions alike.
- [What carries over from your setup](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup)
  is the key reference: repo-committed `.claude/` config reaches cloud sessions; user-level
  `~/.claude` config never does.

## Set up your own (any account, machine, or repo)

### 1. Account level: the environment

Usually nothing to do — onboarding creates a
[Default environment](https://code.claude.com/docs/en/cloud-environments#the-default-environment)
whose Trusted network level already reaches the
[default allowed domains](https://code.claude.com/docs/en/cloud-environments#default-allowed-domains)
(common package registries, GitHub, SchemaStore). Configure an environment only when you need
more, and keep it repo-agnostic, since it serves all repos:

- [Create or edit environments](https://code.claude.com/docs/en/cloud-environments#configure-your-environment)
  from the selector at claude.ai/code; pick a
  [network access level](https://code.claude.com/docs/en/cloud-environments#access-levels) if
  Trusted isn't right.
- [Environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)
  are readable by anyone who uses the environment and there is no secrets store — no credentials.
- A [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) is only for
  tools missing from the
  [pre-installed inventory](https://code.claude.com/docs/en/cloud-environments#installed-tools);
  mind its [requirements](https://code.claude.com/docs/en/cloud-environments#script-requirements)
  and [caching behavior](https://code.claude.com/docs/en/cloud-environments#environment-caching).
  The docs' worked example installs the `gh` CLI, which pairs with the
  [GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy) for auth.
- CLI users pick their environment with
  [`/remote-env`](https://code.claude.com/docs/en/cloud-environments#select-an-environment-from-the-cli).

### 2. Repo level: a committed SessionStart hook

Everything repo-specific goes in source control, following the docs' pattern in
[Install dependencies with a SessionStart hook](https://code.claude.com/docs/en/cloud-environments#install-dependencies-with-a-sessionstart-hook):

- Register a `SessionStart` hook (matcher `startup|resume`) in the repo's
  `.claude/settings.json`, pointing at a script in the repo via `$CLAUDE_PROJECT_DIR`.
- In the script, exit immediately unless `CLAUDE_CODE_REMOTE=true` so local machines are never
  mutated, then install what the repo's own checks need.
- Design rules that matter in practice: make every step idempotent (hooks run on every startup
  and resume — see the
  [limitations list](https://code.claude.com/docs/en/cloud-environments#limitations-in-cloud-sessions)),
  fail the session only for installs the session genuinely can't work without, and warn-and-
  continue for the rest. Persist `PATH` or other variables by appending to `$CLAUDE_ENV_FILE`.
- Merge the hook to the default branch; from then on every cloud session on that repo picks it
  up. In a cloud session you can also just ask Claude to create the hook — an Anthropic-provided
  `session-start-hook` skill is preloaded there for exactly this.

## How this repository is set up

The environment side stays generic (Default environment, Trusted network, no variables, empty
setup script). The repo side:

- [`.claude/settings.json`](../.claude/settings.json) registers the `SessionStart` hook
  (matcher `startup|resume`).
- [`.claude/hooks/session-start.sh`](../.claude/hooks/session-start.sh) is the bootstrap. Cloud
  VMs only; ~40 s on a fresh VM, ~3 s on re-runs. It provisions the tool inventory
  [`ci.yml`](../.github/workflows/ci.yml) pins, reading in-repo manifests wherever one exists:

| Tool | Pin source | Required? |
|---|---|---|
| Node | `.node-version` (via the VM's nvm) | required — CI pins a major the VM image doesn't ship |
| claude CLI + Biome | root `package-lock.json` (`npm ci`) | required |
| ruff | `.github/requirements-ci.txt` (hash-locked) | required |
| shellcheck, actionlint, typos, editorconfig-checker, gitleaks | pinned in the hook (GitHub release binaries) | best effort — warns and continues |
| markdownlint-cli2, check-jsonschema | pinned in the hook (npm -g / uv tool) | best effort |
| full git history + `origin/main` | `git fetch` | best effort — the base-ref diff gates need it |

Best-effort rather than required, deliberately: the plugin contract suites SKIP visibly when an
optional tool is absent and CI remains the enforcing gate, while a required install failure would
block the session from starting. GitHub release-asset downloads are additionally best-effort
because the [GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy)
documents that release assets from repositories not attached to the session can return 403.

Not installed at session start (install on demand when working in those areas): the four plugin
npm roots (`plugins/miro`, `plugins/knowledge/skills/youtube-digest/extraction`,
`plugins/knowledge/skills/course-digest/extraction`,
`plugins/ai-briefing/skills/generate/output/build`) and
`.github/standards/runner-policy` — each is an `npm ci` in that directory; the heavy ones pull
Playwright. `gh`, `pwsh`, and `lychee` are likewise on-demand.

### Maintenance caveats

- Some hook pin sources are materialized from `melodic-software/standards` (see
  [`AGENTS.md`](../AGENTS.md)) — of the files the hook reads, `.node-version` is in the synced
  set (verified against the `chore: sync standards components` history on 2026-07-30), so its
  Node pin updates arrive via sync. `.claude/settings.json` and the hook script itself are
  repo-owned.
- The hook's own version pins exist only because those tools have no in-repo manifest; the cloud
  proxy blocks the GitHub API and `releases/latest` redirects, so the hook can't self-resolve
  "latest". Bump them when the corresponding configs bump.
