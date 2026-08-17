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
- **The setup script is the only pre-launch slot — plugins require it, and it caches the
  bootstrap's work**: the setup script runs after the repository is cloned and before the
  session's Claude Code process starts, so a guarded line in the environment's setup script can
  run this repo's bootstrap and bake its results into the cached snapshot. That drops
  per-session hook time to the idempotent re-check (~3 s here) — and, more importantly, it is
  the only point where `claude plugin install` can land before the process reads its plugin
  registry, which is what makes plugins live in a session at all (see the same-session limit
  under [Plugins in sessions on this repo](#plugins-in-sessions-on-this-repo)):

  ```bash
  [ -f .claude/cloud-bootstrap.sh ] && CLAUDE_CODE_REMOTE=true bash .claude/cloud-bootstrap.sh || true
  ```

  The guard keeps it a no-op for repositories without the script, so the environment stays
  generic, and this repo's ~40 s bootstrap fits comfortably inside the five-minute cache-build
  budget. (How the cache interacts with sessions across *different* repos isn't documented;
  the idempotent script makes either behavior safe.)

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

The environment side stays generic (Default environment, Trusted network, no variables, the
`gh` setup-script one-liner and the guarded pre-launch bootstrap call from above). The repo side:

- [`.claude/cloud-bootstrap.sh`](../.claude/cloud-bootstrap.sh) is the bootstrap, with two
  callers: the account environments' setup scripts run it (with `CLAUDE_CODE_REMOTE=true`)
  after clone and before the session process launches — the only path that gets plugins loaded
  at turn one — and the `SessionStart` hook registered in
  [`.claude/settings.json`](../.claude/settings.json) (matcher `startup|resume`) re-runs the
  same script per session start/resume as drift repair, since the environment cache can be
  ~7 days stale. Cloud
  VMs only; ~40 s on a fresh VM, ~3 s on re-runs. It provisions the tool inventory
  [`ci.yml`](../.github/workflows/ci.yml) pins, reading in-repo manifests wherever one exists:

| Tool | Pin source | Required? |
|---|---|---|
| Node | `.node-version` (via the VM's nvm) | required — CI pins a major the VM image doesn't ship |
| claude CLI + Biome + markdownlint-cli2 | root `package-lock.json` (`npm ci`) | required — markdownlint stays repo-local so the `markdown-format` hook's `node_modules/.bin` probe (and a `~/.local/bin` symlink the bootstrap adds for PATH-based resolution) can see it; `npm -g` into the nvm prefix is invisible to hooks (#2739 / #2748) |
| ruff, pytest, pyyaml | `.github/requirements-ci.txt` (hash-locked) | required — `--require-hashes` fails closed |
| shellcheck, actionlint, typos, editorconfig-checker, gitleaks | pinned in the bootstrap (GitHub release binaries → `~/.local/bin`) | best effort — warns and continues |
| check-jsonschema | pinned in the bootstrap (uv tool / pip `--user`) | best effort |
| full git history + `origin/main` | `git fetch` | best effort — the base-ref diff gates need it |
| the enabled plugin catalog | `enabledPlugins` in `.claude/settings.json` | best effort — a plugin that fails to install costs its skills, not the session |

The bootstrap's startup `report_tool` resolves each binary under a **hook-safe PATH**
(the process PATH with the nvm prefix stripped) and prints the resolved path, so an
`npm -g` install that only the SessionStart shell can see cannot print false-green
again. `CLAUDE_ENV_FILE` PATH repairs still reach subsequent Bash tool calls only —
hook processes inherit Claude Code's own environ, which includes `~/.local/bin` but
not the nvm global prefix.

Best-effort rather than required, deliberately: the plugin contract suites SKIP visibly when an
optional tool is absent and CI remains the enforcing gate, while a required install failure would
block the session from starting. GitHub release-asset downloads are additionally best-effort
because the [GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy)
documents that release assets from repositories not attached to the session can return 403.

Not installed at session start (install on demand when working in those areas): the plugin npm
packages — `plugins/miro` and `.github/standards/runner-policy` are each an `npm ci` in their
own directory, while the video-digest, course-digest, and ai-briefing suites install through
their skills' entry scripts (`plugins/knowledge/skills/video-digest/scripts/run-tests.sh
install`, `plugins/knowledge/skills/course-digest/scripts/run-tests.sh install`,
`plugins/ai-briefing/skills/generate/scripts/run-tests.sh install`); the heavy ones pull
Playwright. `gh`, `pwsh`, and `lychee` are likewise on-demand.

### Plugins in sessions on this repo

Being the marketplace doesn't make this repo's plugins active in a session — plugins load only
when a marketplace is declared, enabled, **and installed**. `.claude/settings.json` declares and
enables; the cloud bootstrap installs (see
[Discover and install plugins](https://code.claude.com/docs/en/discover-plugins) and
[extraKnownMarketplaces / enabledPlugins](https://code.claude.com/docs/en/settings#plugin-settings)):

- `extraKnownMarketplaces` declares this repo as its own marketplace via a `directory` source
  with a relative path, so a session exercises the plugin code on the current branch rather than
  published `main`. Local collaborators are prompted once they trust the folder.
- **A declared marketplace is gated on workspace trust, and cloud sessions arrive untrusted.**
  [What runs before you trust a folder](https://code.claude.com/docs/en/permissions#what-runs-before-you-trust-a-folder)
  groups `extraKnownMarketplaces` entries with the content that needs *this exact folder* trusted,
  while hooks and the `env` block are used whether or not it is. Observed on 2026-08-15: a cloud
  session on this repo had `projects["<repo-root>"].hasTrustDialogAccepted` set to `false` in
  `~/.claude.json`, an empty `~/.claude/plugins/installed_plugins.json`, no plugin skill loaded
  and every `/plugin` command unknown — while the same settings file's `env` block *had* applied.
  That is exactly the split the table predicts, and it is why
  [what carries over](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup)
  promising plugins "installed at session start from the marketplace you declared" did not hold
  here. Hooks run untrusted, so a hook can repair the on-disk state — but not the running
  session; see the next bullet.
- **A SessionStart install is never visible to the session that ran it.** Observed 2026-08-15 in
  a cloud session on this repo: the hook completed `65 enabled, 65 newly installed, 0 failed`,
  `~/.claude/plugins/installed_plugins.json` and user-scope `settings.json` were fully populated
  with the whole catalog — yet the same session's plugin registry stayed empty: its first
  message, a plugin slash command, returned "Unknown command", and a mid-session probe of the
  skill registry resolved no plugin skill. The command/skill registry is built when the Claude
  Code process starts, before SessionStart hook effects land, and is not re-read afterwards; the
  [hooks reference](https://code.claude.com/docs/en/hooks#sessionstart) documents no same-session
  pickup, and neither `/plugin` nor `--plugin-dir` exists in cloud sessions to force one. On an
  ephemeral VM this is a chicken-and-egg: every fresh session re-installs after its registry is
  already built, so the hook alone can never produce a session with plugins loaded. What the
  hook still buys is correct on-disk state for any process start that happens *after* it — a
  resume (confirmed 2026-08-15: stopping and resuming the same session restarted the process,
  which re-read the registry and loaded the full catalog, plugin skills resolving from the
  first post-resume turn), and (the fix for turn one) the environment setup script
  running this same bootstrap at cache-build time, before any session process launches: the
  guarded one-liner in the
  [setup-script lever above](#setup-script-vs-sessionstart-hook-decision-criteria), implemented
  fleet-wide by the standards `cloud-environment` component that
  [CLOUD-FLEET-SETUP.md](CLOUD-FLEET-SETUP.md)'s step-1 stub fetches. Whether the cached
  snapshot's `~/.claude` actually reaches sessions is undocumented — after adding the line,
  rebuild the cache (edit saves the script) and verify with a fresh session whose *first*
  message is a plugin slash command.
- **Harness residual — first-turn slash of just-installed plugins (#2733).** The "Unknown
  command" outcome above is **not remediable inside any plugin in this repository**: the
  command registry is a Claude Code harness property (built at process start, not re-read).
  Track occurrences via `/claude-ops:known-issues` and, when reproducible on a fresh cloud
  session after a confirmed pre-launch bootstrap, report upstream (`anthropics/claude-code`)
  with the bootstrap log plus the first-turn transcript. In-session workarounds when a
  first-turn slash returns `Unknown command:` (a) **resume** the session so the process
  restarts and reloads the registry, or retry the slash on a later turn after a resume; (b)
  **direct-file fallback** — read `plugins/<plugin>/skills/<skill>/SKILL.md` from the repo
  working tree and follow it manually (note: this bypasses skill-load string substitutions
  such as `${CLAUDE_EFFORT}`). Prefer fixing the environment so the setup-script path
  pre-installs before process start; do not invent plugin-side registry hacks.
- Being a `directory` source may compound it —
  [that source is documented for development only](https://code.claude.com/docs/en/settings#extraknownmarketplaces)
  and the carry-over note qualifies install-at-session-start with "requires network access to reach
  the marketplace source". The two candidates were not separated, because the trust gate alone
  accounts for the symptom and the bootstrap makes both moot.
- The bootstrap therefore registers the checkout by absolute path and installs the enabled set
  explicitly — for the benefit of the *next* process start, per the timing bullet above. It
  never calls `claude plugin marketplace remove`, which deletes the marketplace's
  entry from `.claude/settings.json` and would have the script mutate tracked config.
- On resume it also repairs [same-version commit drift](MIGRATION-PLAYBOOK.md): because a
  directory-source cache is keyed by the semver in `plugin.json` rather than the commit, a
  presence check alone would keep serving whichever commit installed first. The script compares the
  `gitCommitSha` recorded at install time against `HEAD` and forces the documented
  uninstall/install/enable cycle for the plugins whose own directory changed between the two, so
  the usual resume stays cheap. Uncommitted edits are out of scope by design — use
  `claude --plugin-dir ./plugins/<name>`, which takes session precedence over the cached install.
- **Consumer repos** should declare the marketplace with a `github` source —
  `{"source": "github", "repo": "melodic-software/claude-code-plugins"}` — since the relative
  `directory` source is specific to this repo, whose reason to exist is validating in-flight
  plugin changes. Declaring it is necessary but, per the trust gate above, not sufficient in a
  cloud session; verify in a fresh session and add the same bootstrap-plus-hook setup if the
  catalog does not load.
- `enabledPlugins` turns on the whole catalog, so this repo dogfoods everything it publishes and a
  regression in any plugin surfaces here first. The trade is context: every enabled plugin adds
  per-turn cost, so a *consumer* repo should enable only the plugins it needs rather than copying
  this set wholesale. The cloud bootstrap provisions every tool the format/lint-on-edit hooks
  (`markdown-format`, `bash-format`, `biome-format`, `typos-format`, `actionlint`,
  `eol-normalizer`) shell out to.
- Entries are sorted alphabetically, one per line, so a single plugin can be flipped to `false`
  without disturbing the rest. Two entries carry required `userConfig` credentials that are unset
  here — `miro` (`miro_api_token`) and `dometrain` (`dometrain_api_key`) — so their bundled MCP
  servers exit at startup until configured; set them with `/plugin configure`, or flip those two
  to `false` if a session shouldn't try.

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

- Some bootstrap pin sources are materialized from `melodic-software/standards` (see
  `melodic-software/standards` `distribution/sync-manifest.yml`) — of the files the bootstrap reads, `.node-version` is in the
  synced set (verified against the `chore: sync standards components` history on 2026-07-30), so
  its Node pin updates arrive via sync. `.claude/settings.json` and the bootstrap script itself
  are repo-owned.
- `.github/requirements-ci.txt` is hash-locked. The lockfile carries ABI-specific hashes for both
  the CI interpreter (cp314 / 3.14) and the cloud VM system Python (cp311 / 3.11; #2657), so the
  bootstrap always installs with `--require-hashes` and a digest mismatch stays fatal —
  no interpreter-mismatch skip, no unpinned fallback. Installs use `pip` rather than `uv`, whose
  PyPI fetches time out against the VM's egress proxy.
- The bootstrap's own version pins exist only because those tools have no in-repo manifest; the
  cloud proxy blocks the GitHub API and `releases/latest` redirects, so the script can't
  self-resolve "latest". Each GitHub-release asset also carries a pinned SHA-256 the script
  verifies before installing (mismatch refuses the install and warns). Bump pin and hash together
  when the corresponding configs bump.
