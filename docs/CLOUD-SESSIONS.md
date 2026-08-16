# Claude Code cloud sessions — concepts, setup guide, and this repo's setup

A how-to for provisioning Claude Code on the web (cloud sessions): what the pieces are, how to
set them up for any account or repository, and how this repository is set up. Details
deliberately live in the linked official pages, not here. Links into the three cloud pages
(`web-quickstart`, `claude-code-on-the-web`, `cloud-environments`) and the claims restated from
them were verified on 2026-08-13 against rung-1 raw-markdown fetches of those pages; links to
other pages were last verified 2026-07-30. Per the
[upstream-drift convention](conventions/upstream-drift/README.md), re-fetch a page before acting
on it.

## What this is

- [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) runs each
  session in a fresh, isolated cloud VM with your repository cloned into it —
  Anthropic-managed by default, or on an organization's
  [self-hosted environment](https://code.claude.com/docs/en/self-hosted-environments) when
  routed there. The onboarding walkthrough (connect GitHub, `/web-setup`, first task) lives on
  its own [Get started page](https://code.claude.com/docs/en/web-quickstart);
  `claude-code-on-the-web` is the full reference.
- Every session runs inside a
  [cloud environment](https://code.claude.com/docs/en/cloud-environments) — the dialog with name,
  network access, environment variables, and setup script. Environments are **scoped to your
  claude.ai account** (or
  [shared org-wide by an admin](https://code.claude.com/docs/en/cloud-environments#organization-shared-environments)),
  **not to a repository**: one environment serves every repo and every surface that starts cloud
  sessions (web, `claude --cloud`, mobile, desktop, routines, and
  [Claude Tag](https://code.claude.com/docs/en/cloud-environments#organization-shared-environments) —
  whose channel sessions use org-shared environments only).
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

Usually nothing to do — onboarding (the
[browser flow](https://code.claude.com/docs/en/web-quickstart#connect-github), or
[`/web-setup` from the CLI](https://code.claude.com/docs/en/web-quickstart#connect-from-your-terminal)
if you already use `gh`) creates a
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
  — exit zero, finish within the roughly-five-minute cache-build budget, registries reachable at
  the chosen access level —
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

### Setup script vs SessionStart hook: decision criteria

Where a given piece of setup belongs, per the
[official split](https://code.claude.com/docs/en/cloud-environments#setup-scripts-vs-sessionstart-hooks)
plus the cost model of
[environment caching](https://code.claude.com/docs/en/cloud-environments#environment-caching):

- **Setup script** (environment dialog; cached): heavy, repo-agnostic, static installs — SDKs
  (e.g. .NET, which the docs call out as setup-script material), `apt` packages, Docker image
  pulls. Runs as root; its cost is paid once per cache rebuild (script/network-config edit, or
  roughly-seven-day expiry), not per session. Total runtime must stay under the
  roughly-five-minute cache-build budget or
  [sessions hang or fail at setup](https://code.claude.com/docs/en/web-quickstart#new-sessions-hang-or-time-out-during-setup)
  — parallelize independent installs and push oversized downloads into a SessionStart hook.
- **SessionStart hook** (repo-committed; every session start and resume): anything driven by the
  repo's own manifests or that must track branch state — dependency installs, pinned-tool
  provisioning. Runs locally and in the cloud, so guard cloud-only work with
  `CLAUDE_CODE_REMOTE` and make every step idempotent; the cost is paid per session.
- **Neither is for processes**: the cache keeps files, not running services. Start databases or
  `docker compose` stacks per session (ask Claude, or start them from the hook).
- **Performance lever — cache the hook's work**: the setup script runs after the repository is
  cloned, so a guarded line in the environment's setup script can run this repo's bootstrap and
  bake its results into the cached snapshot, dropping per-session hook time to the idempotent
  re-check (~3 s here):

  ```bash
  [ -f .claude/hooks/session-start.sh ] && CLAUDE_CODE_REMOTE=true bash .claude/hooks/session-start.sh || true
  ```

  The guard keeps it a no-op for repositories without the script, so the environment stays
  generic, and this repo's ~40 s bootstrap fits comfortably inside the five-minute cache-build
  budget. (How the cache interacts with sessions across *different* repos isn't documented;
  the idempotent hook makes either behavior safe.)

### One environment or several?

Start with one Default. Environments are account-scoped and repo-agnostic, so a single
Trusted-network environment serves every repository. Add a second, named environment only when a
class of work needs something incompatible or heavy enough to isolate — a big SDK whose cache
churn you want contained, or a
[custom domain allowlist](https://code.claude.com/docs/en/cloud-environments#allow-specific-domains).
A repo needing an uninstalled toolchain (the docs' example is the .NET SDK) means adding its
install to a setup script — extend Default, or create a dedicated environment and select it when
starting sessions on that repo; NuGet and dotnet.microsoft.com are already on the default
allowlist.

## How this repository is set up

The environment side stays generic (Default environment, Trusted network, no variables, at most
the optional `gh` setup-script one-liner from above). The repo side:

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
npm roots (`plugins/miro`, `plugins/knowledge/skills/video-digest/extraction`,
`plugins/knowledge/skills/course-digest/extraction`,
`plugins/ai-briefing/skills/generate/output/build`) and
`.github/standards/runner-policy` — each is an `npm ci` in that directory; the heavy ones pull
Playwright. `gh`, `pwsh`, and `lychee` are likewise on-demand.

### Plugins in sessions on this repo

Being the marketplace doesn't make this repo's plugins active in a session — plugins load only
when a marketplace is declared and plugins are enabled. `.claude/settings.json` does both, which
is the documented path for cloud sessions (see
[Discover and install plugins](https://code.claude.com/docs/en/discover-plugins) and
[extraKnownMarketplaces / enabledPlugins](https://code.claude.com/docs/en/settings#plugin-settings)):

- `extraKnownMarketplaces` declares this repo as its own marketplace via a `directory` source
  with a relative path, which
  [resolves against the repository's checkout](https://code.claude.com/docs/en/plugin-marketplaces#relative-paths)
  — cloud sessions install from the clone at session start; local collaborators are prompted
  once they trust the folder.
- `enabledPlugins` turns on a deliberately lean default set, curated to mirror this repo's own
  gates rather than everything the marketplace ships (every enabled plugin adds per-turn context
  cost): the six format/lint-on-edit hooks (`markdown-format`, `bash-format`, `biome-format`,
  `typos-format`, `actionlint`, `eol-normalizer`), plus `guardrails`, `source-control`, and
  `skill-quality`. The session-start hook provisions every tool those hooks shell out to.
- Everything else stays on demand: `/plugin install <name>@melodic-software` in any session.

### GitHub MCP tools vs the gh CLI

Both exist in cloud sessions and don't conflict — they serve different callers:

- The **built-in GitHub MCP tools** are how the agent itself reads issues, PRs, and CI; they
  authenticate through the
  [GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy) with no setup.
- The **`gh` CLI** is what this repo's plugin scripts and hooks shell out to (several
  `source-control`, `guardrails`, and `work-items` suites SKIP without it). It isn't
  pre-installed; the environment setup script installs it, and in cloud sessions it
  [authenticates via the proxy automatically](https://code.claude.com/docs/en/cloud-environments#work-with-github-issues-and-pull-requests)
  — no token needed. Locally, contributors authenticate `gh` themselves as usual.

### Maintenance caveats

- Some hook pin sources are materialized from `melodic-software/standards` (see
  [`AGENTS.md`](../AGENTS.md)) — of the files the hook reads, `.node-version` is in the synced
  set (verified against the `chore: sync standards components` history on 2026-07-30), so its
  Node pin updates arrive via sync. `.claude/settings.json` and the hook script itself are
  repo-owned.
- The hook's own version pins exist only because those tools have no in-repo manifest; the cloud
  proxy blocks the GitHub API and `releases/latest` redirects, so the hook can't self-resolve
  "latest". Each GitHub-release asset also carries a pinned SHA-256 the hook verifies before
  installing (mismatch refuses the install and warns). Bump pin and hash together when the
  corresponding configs bump.
