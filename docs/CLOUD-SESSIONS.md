# Claude Code cloud sessions — concepts, setup guide, and this repo's setup

A how-to for provisioning Claude Code on the web (cloud sessions): what the pieces are, how to
set them up for any account or repository, and how this repository is set up. Details
deliberately live in the linked official pages, not here. Links into the three cloud pages
(`web-quickstart`, `claude-code-on-the-web`, `cloud-environments`) and the claims restated from
them were verified on 2026-08-13 against rung-1 raw-markdown fetches of those pages; links to
other pages were last verified 2026-07-30. Per the
[upstream-drift convention](conventions/upstream-drift/README.md), re-fetch a page before acting
on it.

**Recheck trigger:** re-verify the claims this document restates from those pages when any of
these change: the
`cloud-environments` page's Setup scripts vs SessionStart hooks, Environment caching, Default
allowed domains, Access levels, or What carries over from your setup sections; the
`web-quickstart` page's Connect GitHub or New sessions hang or time out during setup sections;
the `hooks#sessionstart` reference's documented pickup timing for hook effects; or Claude Code
ships a `/plugin`-equivalent or `--plugin-dir` mechanism usable in cloud sessions (closing the
first-turn slash gap tracked as #2733).

## Contents

- [What this is](#what-this-is)
- [Set up your own (any account, machine, or repo)](#set-up-your-own-any-account-machine-or-repo)
- [How this repository is set up](#how-this-repository-is-set-up)

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
  Trusted isn't right — this fleet's accounts all run **All** (see
  [One environment or several?](#one-environment-or-several)).
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
environment serves every repository — this fleet runs its Default at **All** network access
(operator decision 2026-08-22; rationale in
[CLOUD-FLEET-SETUP.md](CLOUD-FLEET-SETUP.md#step-1--the-shared-environment-claudeai-ui-one-time)).
Add a second, named environment only when a class of work needs something incompatible or heavy
enough to isolate — a big SDK whose cache churn you want contained, or an account that handles
sensitive material and therefore has to run narrower than All, on a
[custom domain allowlist](https://code.claude.com/docs/en/cloud-environments#allow-specific-domains).
A repo needing an uninstalled toolchain (the docs' example is the .NET SDK) means adding its
install to a setup script — extend Default, or create a dedicated environment and select it when
starting sessions on that repo. Reaching NuGet and dotnet.microsoft.com is not what settles .NET:
both are on the default allowlist, yet under Trusted the installer's redirect chain still came
back `403` (#2654 Blocker 1). That is why the toolchain question and the network-access question
are separate — and why the fleet answers the second with All.

## How this repository is set up

The environment side stays generic (Default environment, **All** network access, no variables, the
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
- **`skillListingBudgetFraction` is set to `0.05`, and what that buys depends entirely on the
  live model's context window.** Claude Code loads every enabled skill's name and description
  each turn and caps the total at
  [`skillListingBudgetFraction`](https://code.claude.com/docs/en/settings) of the context window,
  default `0.01`. On overflow it keeps every *name* and sheds *descriptions*, lowest-scoring
  skills first, so a skill that is never invoked loses the keywords a request would have matched
  and goes on not being invoked. Measured at `main` 3ea592bb with
  `plugins/skill-quality/scripts/check-listing-budget.sh plugins/*/skills`: **182 listing-eligible
  skills, 135,596 characters**. The budget is `window_tokens x 4 chars/token x fraction`, so at
  `0.05` the listing fits **only on a context window of 677,980 tokens or larger**. Read the
  setting as a window assumption, not a guarantee:

  | Context window | Budget at `0.05` | `claude-ops:audit-skill-visibility` |
  | --- | --- | --- |
  | 200,000 (Claude Code's documented default) | 40,000 chars | `overflowing`, **135 of 182 starved** |
  | 677,980 (break-even for today's fleet) | 135,596 chars | `listing-fits`, 0 starved |
  | 750,000 | 150,000 chars | `listing-fits`, 0 starved, 14,404 spare |
  | 1,000,000 | 200,000 chars | `listing-fits`, 0 starved, 64,404 spare |

  On a 200k-window machine this setting does not clear the fleet; it moves the starved count from
  177 to 135. It reaches 0 starved only on the large-window models this marketplace is actually
  driven on. Re-measured after merging `main` 8dd38b81: 182 skills, 135,572 characters — every
  row above reproduces unchanged, so treat the table as accurate to within a few dozen characters
  of whatever `main` you read it on, not as a live reading.

  **The repo did not previously run `0.03` or a 90,000-character budget.**
  `git log -S skillListingBudgetFraction -- .claude/settings.json` returns exactly one commit on
  this branch, 57db0238, the commit in this change that adds the key, so before it this repo
  inherited the harness default `0.01`,
  which is the documented 8,000-character fallback on a 200k window and leaves **177 of 182
  skills starved**. The `0.03` / 90,000-character pair belongs to one contributor's machine in
  [#3505](https://github.com/melodic-software/claude-code-plugins/issues/3505)'s debug log, where
  the audit reports 72 of 182 starved. That is a real observation of one consumer, not this
  repository's prior configuration.

  **This is a stopgap measured in days.** The same tool measured 59,465 characters on 2026-07-20
  and 86,316 on 2026-08-05 against 135,596 on 2026-09-05, which is 1,620 to 1,700 characters of
  growth a day. Against the 14,404-character headroom on a 750,000-token window that is **about
  9 days**; against the 64,404 on a 1,000,000-token window, **about 40 days**. No fraction anyone
  would want to pay for changes that shape, because the aggregate is what grows. Trimming the
  descriptions at their source is the fix, and it is
  [#3526](https://github.com/melodic-software/claude-code-plugins/issues/3526). That is required
  work, not optional follow-up. Until it lands, a second report-only CI step measures the
  aggregate at this configured fraction on the tighter 750,000-token basis, so the WARN arrives
  with days of warning instead of after the consumers on that basis have already overflowed.
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
- Being a `directory` source may compound the symptom —
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
- **Reading the summary line's `failed` count (corrected 2026-08-28).** That count used to be the
  exit status of the refresh chain, and the chain's tail step is nonzero on the healthy path:
  `claude plugin install --scope user` already leaves the plugin enabled, so the following
  `claude plugin enable --scope user` exits 1 with `Plugin "<id>" is already enabled at user
  scope`. Startup lines like `plugins 71 enabled, 5 newly installed, 0 refreshed, 65 failed` were
  therefore false alarms, and dozens of them per session start buried the only health signal this
  block emits. The script now runs the chain for effect and verifies the end state once per run,
  over every plugin `enabledPlugins` turns on rather than only the ones that run touched, since
  the plugins most likely to be wrong are the ones it decided to skip. A plugin counts as failed
  when any of these holds:
  - `claude plugin list --json` does not list it at user scope, or lists it there with `enabled`
    anything other than the JSON boolean `true`;
  - its own directory under `plugins/` changed between the `gitCommitSha` recorded for the
    user-scope install and `HEAD`, so the session would serve that plugin's older sources. A
    recorded sha that merely differs from `HEAD` is NOT a failure: the check is
    `git diff <recorded> HEAD -- plugins/<name>`, so unrelated commits since the install are
    correctly ignored;
  - the snapshot cannot be judged at all: no resolvable `HEAD` for the checkout, no registry
    file, no recorded `gitCommitSha`, a `null` one, or a recorded commit this clone does not
    have. Verification is deliberately fail-CLOSED here, unlike the refresh decision that reuses
    the same inputs and skips what it cannot judge.

  Each failure is named on stderr with its reason and the summary line appends the failing ids
  after the count. So `0 failed` means every enabled plugin was checked and each one is installed
  at user scope, enabled there, and serving sources that match `HEAD`; the one case where nothing
  can be claimed, `claude plugin list --json` itself being unreadable, counts every plugin as
  failed and says so in one line rather than one per plugin.
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
- The `plugin-catalog-enablement-gate` CI lane holds that whole-catalog claim to the file, in both
  directions: every `.claude-plugin/marketplace.json` entry must carry an `enabledPlugins` key, and
  every key for this marketplace must name a catalogued plugin. It also checks that
  `cloud-bootstrap.sh`'s hardcoded `marketplace_name` still names the marketplace the settings file
  declares — the bootstrap selects what it installs with `endswith("@" + $n)`, so a rename that
  updated the settings and the catalog but not that constant would leave its install set empty
  while the parity lane stayed green over it. It exists because the claim was
  prose for three plugin releases that shipped catalogued but never enabled — a silent failure,
  since the bootstrap computes its install set from the same map and a session simply comes up
  without those skills. `claude-config`'s `check-plugin-drift.sh` cannot cover it: that detector
  resolves each marketplace through `source.repo` and records SKIP for one declaring none, which
  is precisely this repo's relative `directory` source.
- Entries are sorted alphabetically, one per line, so a single plugin can be flipped to `false`
  without disturbing the rest — a state the gate accepts, since an explicit `false` is a recorded
  decision where an absent key is drift. Two entries carry required `userConfig` credentials that are unset
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

- Some bootstrap pin sources are materialized from `melodic-software/standards` (see the
  [sync manifest](https://github.com/melodic-software/standards/blob/main/distribution/sync-manifest.yml))
  — of the files the bootstrap reads, `.node-version` is in the
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
