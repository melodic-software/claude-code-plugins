# Claude Code cloud sessions: concepts, setup guide, and this repo's setup

A how-to for provisioning Claude Code on the web (cloud sessions): what the pieces are, how to
set them up for any account or repository, and how this repository is set up. This doc states
this repository's decisions and its own measurements; for platform behavior, limits, and defaults
it links the exact upstream section instead of restating it. Read a linked section live before
acting on it (`/discovery:read-docs` caches the page). The upstream pages:

- [Use Claude Code in the cloud](https://code.claude.com/docs/en/claude-code-on-the-web),
  including its [Limitations](https://code.claude.com/docs/en/claude-code-on-the-web#limitations)
- [Get started with Claude Code in the cloud](https://code.claude.com/docs/en/web-quickstart)
- [Configure cloud environments](https://code.claude.com/docs/en/cloud-environments)
- [Routines](https://code.claude.com/docs/en/routines)
- [Remote Control vs cloud sessions](https://code.claude.com/docs/en/remote-control#remote-control-vs-cloud-sessions)

## Contents

- [What this is](#what-this-is)
- [Set up your own (any account, machine, or repo)](#set-up-your-own-any-account-machine-or-repo)
- [How this repository is set up](#how-this-repository-is-set-up)

## What this is

- [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) runs each
  session in a fresh, isolated cloud VM with your repository cloned into it,
  Anthropic-managed by default, or on an organization's
  [self-hosted environment](https://code.claude.com/docs/en/self-hosted-environments) when
  routed there. The onboarding walkthrough (connect GitHub, `/web-setup`, first task) lives on
  its own [Get started page](https://code.claude.com/docs/en/web-quickstart);
  `claude-code-on-the-web` is the full reference.
- Every session runs inside a
  [cloud environment](https://code.claude.com/docs/en/cloud-environments): the dialog with name,
  network access, environment variables, and setup script. Environments are **scoped to your
  claude.ai account** (or
  [shared org-wide by an Owner](https://code.claude.com/docs/en/cloud-environments#organization-shared-environments)),
  **not to a repository**: one environment serves every repo and
  [every surface that starts cloud sessions](https://code.claude.com/docs/en/cloud-environments).
- Two setup mechanisms exist, with an
  [official division of labor](https://code.claude.com/docs/en/cloud-environments#setup-scripts-vs-sessionstart-hooks):
  the environment's **setup script** provisions the VM itself (toolchains, CLI tools), while a
  repo-committed **[SessionStart hook](https://code.claude.com/docs/en/hooks#sessionstart)**
  handles project setup and runs in local and cloud sessions alike.
- [What carries over from your setup](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup)
  is the key reference for which repo-committed and user-level config reaches a cloud session.
  User-level `~/.claude` config does not, which is why the fleet `claude-permissions` floor, composed
  locally by chezmoi into `~/.claude/settings.json`, never reaches a cloud session
  ([#3172](https://github.com/melodic-software/claude-code-plugins/issues/3172)).

## Set up your own (any account, machine, or repo)

### 1. Account level: the environment

Usually nothing to do. Onboarding (the
[browser flow](https://code.claude.com/docs/en/web-quickstart#connect-github), or
[`/web-setup` from the CLI](https://code.claude.com/docs/en/web-quickstart#connect-from-your-terminal)
if you already use `gh`) creates a
[Default environment](https://code.claude.com/docs/en/cloud-environments#the-default-environment),
whose network level and reach are on that page and in
[Default allowed domains](https://code.claude.com/docs/en/cloud-environments#default-allowed-domains).
Configure an environment only when you need more, and keep it repo-agnostic, since it serves all
repos:

- [Create or edit environments](https://code.claude.com/docs/en/cloud-environments#configure-your-environment)
  from the environment selector; pick a
  [network access level](https://code.claude.com/docs/en/cloud-environments#access-levels) if
  the default isn't right. This fleet's accounts all run **Full** (see
  [One environment or several?](#one-environment-or-several)).
- Put no credentials in
  [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables):
  the page says who can read them, and
  [network secrets](https://code.claude.com/docs/en/cloud-environments#add-network-secrets) covers
  the plans that have a store for keys.
- A [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) is only for
  tools missing from the
  [pre-installed inventory](https://code.claude.com/docs/en/cloud-environments#installed-tools);
  write it to the [script requirements](https://code.claude.com/docs/en/cloud-environments#script-requirements)
  and the [caching behavior](https://code.claude.com/docs/en/cloud-environments#environment-caching).
  `gh` is in the pre-installed inventory, and the
  [GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy) authenticates it.
- CLI users pick their environment with
  [`/remote-env`](https://code.claude.com/docs/en/cloud-environments#select-an-environment-from-the-cli).

### 2. Repo level: a committed SessionStart hook

Everything repo-specific goes in source control, following the docs' pattern in
[Install dependencies with a SessionStart hook](https://code.claude.com/docs/en/cloud-environments#install-dependencies-with-a-sessionstart-hook):

- Register a `SessionStart` hook (matcher `startup|resume`) in the repo's
  `.claude/settings.json`, pointing at a script in the repo via `$CLAUDE_PROJECT_DIR`.
- In the script, exit immediately unless `CLAUDE_CODE_REMOTE=true` so local machines are never
  mutated, then install what the repo's own checks need.
- Design rules that matter in practice: make every step idempotent (see
  [Limitations in cloud sessions](https://code.claude.com/docs/en/cloud-environments#limitations-in-cloud-sessions)
  for when hooks run), fail the session only for installs the session genuinely can't work
  without, and warn-and-continue for the rest. Persist `PATH` or other variables by appending to
  `$CLAUDE_ENV_FILE`.
- Merge the hook to the default branch; from then on every cloud session on that repo picks it
  up. In a cloud session you can also ask Claude to create the hook.

### Setup script vs SessionStart hook: decision criteria

Where a given piece of setup belongs, per the
[official split](https://code.claude.com/docs/en/cloud-environments#setup-scripts-vs-sessionstart-hooks)
plus the cost model of
[environment caching](https://code.claude.com/docs/en/cloud-environments#environment-caching):

- **Setup script** (environment dialog; cached): heavy, repo-agnostic, static installs such as SDKs
  (e.g. .NET, which [Installed tools](https://code.claude.com/docs/en/cloud-environments#installed-tools)
  sends to a setup script), `apt` packages, and Docker image pulls. Its cost is paid once per
  cache rebuild (the rebuild events are in
  [Environment caching](https://code.claude.com/docs/en/cloud-environments#environment-caching)),
  not per session. Keep its runtime inside the
  [script requirements](https://code.claude.com/docs/en/cloud-environments#script-requirements),
  or the environment is not cached and
  [sessions can hang or fail at setup](https://code.claude.com/docs/en/web-quickstart#new-sessions-hang-or-time-out-during-setup).
- **SessionStart hook** (repo-committed; every session start and resume): anything driven by the
  repo's own manifests or that must track branch state, such as dependency installs and pinned-tool
  provisioning. Runs locally and in the cloud, so guard cloud-only work with
  `CLAUDE_CODE_REMOTE` and make every step idempotent; the cost is paid per session.
- **Neither is for processes**: the cache keeps files, not running services
  ([Environment caching](https://code.claude.com/docs/en/cloud-environments#environment-caching)).
  Start databases or `docker compose` stacks per session (ask Claude, or start them from the hook).
- **The setup script is the only pre-launch slot. Plugins require it, and it caches the
  bootstrap's work**: the setup script runs after the repository is cloned and before the
  session's Claude Code process starts, so a guarded line in the environment's setup script can
  run this repo's bootstrap and bake its results into the cached snapshot. That drops
  per-session hook time to the idempotent re-check (~3 s here). More importantly, it is
  the only point where `claude plugin install` can land before the process reads its plugin
  registry, which is what makes plugins live in a session at all (see the same-session limit
  under [Plugins in sessions on this repo](#plugins-in-sessions-on-this-repo)):

  ```bash
  [ -f .claude/cloud-bootstrap.sh ] && CLAUDE_CODE_REMOTE=true bash .claude/cloud-bootstrap.sh || true
  ```

  The guard keeps it a no-op for repositories without the script, so the environment stays
  generic, and this repo's ~40 s bootstrap fits comfortably inside the cache-build limit in the
  [script requirements](https://code.claude.com/docs/en/cloud-environments#script-requirements). (How the cache interacts with sessions across *different* repos isn't documented;
  the idempotent script makes either behavior safe.)

### One environment or several?

Start with one Default. Environments are account-scoped and repo-agnostic, so a single
environment serves every repository. This fleet runs its Default at **Full** network access
(operator decision 2026-08-22; rationale in
[cloud-fleet-setup.md](cloud-fleet-setup.md#step-1-the-shared-environment-claudeai-ui-one-time)).
Add a second, named environment only when a class of work needs something incompatible or heavy
enough to isolate: a big SDK whose cache churn you want contained, or an account that handles
sensitive material and therefore has to run narrower than Full, on a
[custom domain allowlist](https://code.claude.com/docs/en/cloud-environments#allow-specific-domains).
A repo needing a toolchain missing from
[Installed tools](https://code.claude.com/docs/en/cloud-environments#installed-tools) means
adding its install to a setup script. Extend Default, or create a dedicated environment and
select it when starting sessions on that repo. The toolchain question and the network-access
question are separate; the .NET `403` that settled the second as Full is recorded under
[Network access](cloud-fleet-setup.md#step-1-the-shared-environment-claudeai-ui-one-time).

## How this repository is set up

The owner keeps cloud sessions off for work and state because accounts rotate, and a cloud environment
and its sessions belong to one claude.ai account
([Configure cloud environments](https://code.claude.com/docs/en/cloud-environments)). The setup
below stays available, and no lane routes to it. Dissent: Lydia Hallie's talk "Rethinking Claude
Code Best Practices" ([video](https://www.youtube.com/watch?v=vlfCjWuv4es)) recommends starting
work in a cloud session. Owner decision of 2026-11-12.

The environment side stays generic (Default environment, **Full** network access, no variables,
and the setup script from [cloud-fleet-setup.md](cloud-fleet-setup.md#step-1-the-shared-environment-claudeai-ui-one-time),
which carries the guarded pre-launch bootstrap call from above). The repo side:

- [`.claude/cloud-bootstrap.sh`](../.claude/cloud-bootstrap.sh) is the bootstrap, with two
  callers: the account environments' setup scripts run it (with `CLAUDE_CODE_REMOTE=true`)
  after clone and before the session process launches, the only path that gets plugins loaded
  at turn one, and the `SessionStart` hook registered in
  [`.claude/settings.json`](../.claude/settings.json) (matcher `startup|resume`) re-runs the
  same script per session start/resume as drift repair, since the environment cache can be as
  old as its [expiry](https://code.claude.com/docs/en/cloud-environments#environment-caching). Cloud
  VMs only; ~40 s on a fresh VM, ~3 s on re-runs. It provisions the tool inventory
  [`pr-require-checks.yml`](../.github/workflows/pr-require-checks.yml) pins, reading in-repo manifests wherever one exists:

| Tool | Pin source | Required? |
|---|---|---|
| Node | `.node-version` (via the VM's nvm) | required: CI pins a major the VM image doesn't ship |
| claude CLI + Biome + markdownlint-cli2 | root `package-lock.json` (`npm ci`) | required: markdownlint stays repo-local so the `markdown-format` hook's `node_modules/.bin` probe (and a `~/.local/bin` symlink the bootstrap adds for PATH-based resolution) can see it; `npm -g` into the nvm prefix is invisible to hooks (#2739 / #2748) |
| ruff, pytest, pyyaml | `.github/requirements-ci.txt` (hash-locked) | required: `--require-hashes` fails closed |
| shellcheck, actionlint, typos, editorconfig-checker, gitleaks | pinned in the bootstrap (GitHub release binaries → `~/.local/bin`) | best effort: warns and continues |
| check-jsonschema | pinned in the bootstrap (uv tool / pip `--user`) | best effort |
| full git history + `origin/main` | `git fetch` | best effort: the base-ref diff gates need it |
| the enabled plugin catalog | the snapshot's fleet list (`/opt/melodic-fleet-plugins.json`) overlaid with `enabledPlugins` in `.claude/settings.json` | best effort: a plugin that fails to install costs its skills, not the session |

The bootstrap's startup `report_tool` resolves each binary under a **hook-safe PATH**
(the process PATH with the nvm prefix stripped) and prints the resolved path, so an
`npm -g` install that only the SessionStart shell can see cannot print false-green
again. `CLAUDE_ENV_FILE` PATH repairs still reach subsequent Bash tool calls only.
Hook processes inherit Claude Code's own environ, which includes `~/.local/bin` but
not the nvm global prefix.

Best-effort rather than required, deliberately. The plugin contract suites SKIP visibly when an
optional tool is absent and CI remains the enforcing gate, while a required install failure would
block the session from starting. GitHub release-asset downloads are additionally best-effort
because the [GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy)
scopes its requests to the repositories attached to the session, so a release asset from
another repository can be refused.

Not installed at session start (install on demand when working in those areas): the plugin npm
packages. `plugins/miro/server` and `.github/standards/runner-policy` are each an `npm ci` in their
own directory, while the video-digest, course-digest, and ai-briefing suites install through
their skills' entry scripts (`plugins/knowledge/skills/video-digest/scripts/run-tests.sh
install`, `plugins/knowledge/skills/course-digest/scripts/run-tests.sh install`,
`plugins/ai-briefing/skills/generate/scripts/run-tests.sh install`); the heavy ones pull
Playwright. `lychee` is likewise on-demand. `gh` and `pwsh` are not the bootstrap's to install:
they come from the VM image and the shared environment's setup script
([cloud-fleet-setup.md](cloud-fleet-setup.md#step-1-the-shared-environment-claudeai-ui-one-time)).

### Plugins in sessions on this repo

Being the marketplace doesn't make this repo's plugins active in a session: plugins load only
when a marketplace is registered, enabled, **and installed**. `.claude/settings.json` carries
this repo's `enabledPlugins` deltas and declares no marketplace, the fleet list baked into the
snapshot turns the catalog on, and the cloud bootstrap registers the marketplace and installs
from the two together (see
[Install and manage plugins](https://code.claude.com/docs/en/plugins/install) and
[enabledPlugins](https://code.claude.com/docs/en/settings-reference#enabledplugins)):

- The cloud bootstrap is the only place this checkout is registered as a `directory` marketplace
  source, and it runs only in cloud sessions, so a cloud session exercises the plugin code on the
  current branch rather than published `main`. Project settings declare no marketplace, so a
  local session keeps the user's own registration of `melodic-software`; to test a branch's
  plugin code locally, start Claude Code with `claude --plugin-dir ./plugins/<name>`. A cloud
  snapshot can already carry a marketplace of the same name registered from GitHub and tracking
  `main`; the bootstrap then never registers the checkout, every install resolves against that
  clone, and the session runs `main`'s plugin code. The bootstrap detects this from
  `plugin marketplace list --json`, brings the clone current, measures the refresh decision and
  the health verdict against the clone's HEAD rather than the checkout's, and prints one
  warning naming both commits, so a branch that changed a plugin knows its copy is not the one
  being served.
- **`skillListingBudgetFraction` is set to `0.06`, and what that buys depends on the live
  model's context window and its bytes per token.** Claude Code caps the per-turn skill listing
  at a fraction of the context window; the key and its default are in
  [`skillListingBudgetFraction`](https://code.claude.com/docs/en/settings-reference#skilllistingbudgetfraction),
  and what overflow drops is in
  [Skill descriptions are cut short](https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short).
  A skill whose description is dropped loses the keywords a request would have matched and goes
  on not being invoked. The budget is `window_tokens x bytes_per_token x fraction`, and
  bytes per token is 3 or 4 depending on the model.

  Measured 2026-11-05 on Claude Code 2.1.318 with
  `/harness-ops:audit-skill-visibility --installed --context-window 1000000 --listing-capture
  <session transcript>`: a fresh `claude-opus-5-5` session (1M window) in this repository lists
  225 skills in **114,261 characters** and sheds none at `0.06`. A probe at `0.03` got a
  listing of 89,974 characters against a 90,000 budget, so that model runs at 3 bytes per token.
  At `0.06`:

  | Context window | Budget at 3 bytes/token | Budget at 4 bytes/token | Against 114,261 |
  | --- | --- | --- | --- |
  | 200,000 | 36,000 chars | 48,000 chars | overflowing at either rate |
  | 750,000 | 135,000 chars | 180,000 chars | fits at either rate |
  | 1,000,000 | 180,000 chars | 240,000 chars | fits, 36% spare at 3 |

  `0.06` is the smallest step of 0.01 that keeps 15% headroom on the 1M/3 budget for both the
  live listing and every listing-eligible skill in this repository (138,574 characters by
  `plugins/skill-quality/scripts/check-listing-budget.sh plugins/*/skills`, 23% spare at
  180,000). A 200k-window session, including a subagent whose listing is sized to its own window,
  still sheds descriptions at any fraction anyone would want to pay for. Re-measure with the
  command above rather than trusting this table on a later `main`: the installed fleet also
  depends on each host's user-scope plugins, and this one was measured on a single WSL host.
  Growth erodes the margin with no check failing: this repository's skills grew 1,620 to 1,700
  description characters a day between July and September 2026, then fell from 146,814 on
  2026-10-11 to 138,574 by the 2026-11-05 measurement, and 153,000 (85% of 180,000) is where
  the 15% headroom ends. A
  scheduled report-only CI step measures this repository's skills at the configured fraction on
  a 750,000-token, 4-bytes-per-token basis. It does not cover a 3-bytes-per-token model, whose
  135,000-character budget at 750,000 tokens all of this repository's skills already exceed.
- **A declared marketplace is gated on workspace trust, and cloud sessions arrive untrusted.**
  [What runs before you trust a folder](https://code.claude.com/docs/en/permissions#what-runs-before-you-trust-a-folder)
  groups `extraKnownMarketplaces` entries with the content that needs *this exact folder* trusted,
  while hooks and the `env` block are used whether or not it is. Observed on 2026-08-15: a cloud
  session on this repo had `projects["<repo-root>"].hasTrustDialogAccepted` set to `false` in
  `~/.claude.json`, an empty `~/.claude/plugins/installed_plugins.json`, no plugin skill loaded
  and every `/plugin` command unknown, while the same settings file's `env` block *had* applied.
  That is exactly the split the table predicts.
  [What carries over from your setup](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup)
  now lists repo-declared plugins and marketplaces among what a cloud session does not install,
  which matches what this repo observed. Hooks run untrusted, so a hook can repair the on-disk
  state but not the running session; see the next bullet.
- **A SessionStart install is never visible to the session that ran it.** Observed 2026-08-15 in
  a cloud session on this repo: the hook completed `65 enabled, 65 newly installed, 0 failed`,
  `~/.claude/plugins/installed_plugins.json` and user-scope `settings.json` were fully populated
  with the whole catalog, yet the same session's plugin registry stayed empty: its first
  message, a plugin slash command, returned "Unknown command", and a mid-session probe of the
  skill registry resolved no plugin skill. The command/skill registry is built when the Claude
  Code process starts, before SessionStart hook effects land, and is not re-read afterwards; the
  hooks reference's only same-session pickup is
  [`reloadSkills`](https://code.claude.com/docs/en/hooks#reload-skills-that-a-hook-installs), whose
  section names skill directories and not a plugin install, and whether it reaches one is unprobed.
  Neither `/plugin`
  ([terminal-only commands](https://code.claude.com/docs/en/claude-code-on-the-web#manage-context))
  nor `--plugin-dir` exists in cloud sessions to force one. On an
  ephemeral VM the hook runs too late, because every fresh session re-installs after its registry is
  already built, so the hook alone can never produce a session with plugins loaded. What the
  hook still buys is correct on-disk state for any process start that happens *after* it: a
  resume (confirmed 2026-08-15: stopping and resuming the same session restarted the process,
  which re-read the registry and loaded the full catalog, plugin skills resolving from the
  first post-resume turn), and (the fix for turn one) the environment setup script
  running this same bootstrap at cache-build time, before any session process launches: the
  guarded one-liner in the
  [setup-script lever above](#setup-script-vs-sessionstart-hook-decision-criteria), implemented
  fleet-wide by the standards `cloud-environment` component that
  [cloud-fleet-setup.md](cloud-fleet-setup.md)'s step-1 stub fetches. Whether the cached
  snapshot's `~/.claude` actually reaches sessions is undocumented. After adding the line,
  rebuild the cache (edit saves the script) and verify with a fresh session whose *first*
  message is a plugin slash command.
- **Harness residual: first-turn slash of just-installed plugins (#2733).** The "Unknown
  command" outcome above is **not remediable inside any plugin in this repository**: the
  command registry is a Claude Code harness property (built at process start, not re-read).
  Track occurrences via `/harness-ops:known-issues` and, when reproducible on a fresh cloud
  session after a confirmed pre-launch bootstrap, report upstream (`anthropics/claude-code`)
  with the bootstrap log plus the first-turn transcript. In-session workarounds when a
  first-turn slash returns `Unknown command:` (a) **resume** the session so the process
  restarts and reloads the registry, or retry the slash on a later turn after a resume; (b)
  **direct-file fallback**: read `plugins/<plugin>/skills/<skill>/SKILL.md` from the repo
  working tree and follow it manually (note: this bypasses skill-load string substitutions
  such as `${CLAUDE_EFFORT}`). Prefer fixing the environment so the setup-script path
  pre-installs before process start; do not invent plugin-side registry hacks.
- Whether being a `directory` source
  ([its intended uses](https://code.claude.com/docs/en/settings-reference#extraknownmarketplaces))
  compounds the symptom was never separated out: the trust gate alone accounts for it, and the
  bootstrap makes the question moot.
- The bootstrap therefore registers the checkout by absolute path and installs the enabled set
  explicitly, for the benefit of the *next* process start, per the timing bullet above. It
  never calls `claude plugin marketplace remove`, which deletes the marketplace's
  entry from `.claude/settings.json` and would have the script mutate tracked config.
- The bootstrap reconciles user-scope installs at SessionStart (and at cache build, through the
  setup script); `/harness-ops:plugins` never detects or coordinates with it. Every `sync` and
  `audit` re-derives the fleet from `installed_plugins.json` and the settings maps on the run, so
  a bootstrap that ran a moment earlier shows up only as current state, never as a branch in the
  skill.
- On resume the bootstrap also repairs [same-version commit drift](migration-playbook.md#same-version-commit-drift-copied-installs):
  because a directory-source cache is keyed by the semver in `plugin.json` rather than the commit, a
  presence check alone would keep serving whichever commit installed first. The script compares the
  `gitCommitSha` recorded at install time against `HEAD` and forces the documented
  uninstall/install/enable cycle for the plugins whose own directory changed between the two, so
  the usual resume stays cheap. Uncommitted edits are out of scope by design. Use
  `claude --plugin-dir ./plugins/<name>`, which takes session precedence over the cached install.
- **Reading the summary line's `failed` count (corrected 2026-08-28).** That count used to be the
  exit status of the refresh chain, and the chain's tail step is nonzero on the healthy path:
  `claude plugin install --scope user` already leaves the plugin enabled, unless the catalog entry
  sets `defaultEnabled: false`, which the install honors, so the following
  `claude plugin enable --scope user` exits 1 with `Plugin "<id>" is already enabled at user
  scope`. Startup lines like `plugins 71 enabled, 5 newly installed, 0 refreshed, 65 failed` were
  therefore false alarms, and dozens of them per session start buried the only health signal this
  block emits. The script now runs the chain for effect and verifies the end state once per run,
  over every plugin the fleet list plus this repo's `enabledPlugins` deltas turn on rather than only
  the ones that run touched, since the plugins most likely to be wrong are the ones it decided to
  skip. A plugin counts as failed when any of these holds:
  - `claude plugin list --json` does not list it at user scope, or lists it there with `enabled`
    anything other than the JSON boolean `true`, except a catalog entry marked
    `defaultEnabled: false` whose user-scope record has `enabled` as the JSON boolean
    `false` (a missing, null, or string `enabled` value still fails);
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
  after the count. The leading count is `N declared` (ids the fleet list plus settings deltas
  turn on), not `N enabled`, because a catalog `defaultEnabled: false` entry is declared and
  installed without ever being enabled. So `0 failed` means every declared plugin was checked
  and each one is installed at user scope, serving sources that match `HEAD`, and either enabled
  there or (for a catalog-default-disabled id) explicitly JSON-`false` disabled; the one case
  where nothing can be claimed, `claude plugin list --json` itself being unreadable, counts
  every plugin as failed and says so in one line rather than one per plugin.
- **Consumer repos** should declare the marketplace with a `github` source,
  `{"source": "github", "repo": "melodic-software/claude-code-plugins"}`, since the `directory`
  source is specific to this repo's cloud bootstrap, whose reason to exist is validating
  in-flight plugin changes. Declaring it is necessary but, per the trust gate above, not sufficient in a
  cloud session; verify in a fresh session and add the same bootstrap-plus-hook setup if the
  catalog does not load.
- This repo's cloud sessions install the plugins the catalog has on by default, plus this repo's
  deltas. The shared environment's setup (`setup.sh` under `components/cloud-environment/` in
  standards) derives the fleet list from this catalog at cache build, taking every entry whose
  `defaultEnabled` is absent or `true`, writes it into the snapshot at
  `/opt/melodic-fleet-plugins.json`, and installs it at user scope; `cloud-bootstrap.sh` reads
  that snapshot copy overlaid with `.claude/settings.json`. **A plugin the catalog marks
  `defaultEnabled: false` is not installed in this repo's cloud sessions** unless the committed
  block opts it in, so a regression in one surfaces in CI and local use, not here. In the
  committed `enabledPlugins` block, an explicit `false` opts out of an on-by-default plugin, and
  `true` opts in to an off-by-default one. The block is project scope, so every key also sets that
  plugin's state in every local session in this repo, whatever the user's own scope says; a key
  that matches the catalog default changes nothing in the cloud and is there for that local
  effect. The block used to mirror the
  catalog, and a local session start in every checkout wrote one project-scope install record per
  mirrored entry into the user's `installed_plugins.json` (#3688); the current block writes
  none. The trade is context: every enabled plugin adds per-turn cost, so a *consumer* repo
  should opt out of what it does not need rather than copying anything wholesale. The cloud
  bootstrap provisions every tool the format/lint-on-edit hooks (`markdown-format`,
  `bash-format`, `javascript-format`, `spelling`, `actionlint`, `eol-normalizer`) shell out to.
- The `plugin-catalog-enablement-gate` CI lane holds the `enabledPlugins` block to the catalog:
  every key for this marketplace must name a catalogued plugin, since a key that names nothing silently
  no-ops, and keys stay in byte order. It also checks that `cloud-bootstrap.sh`'s hardcoded
  `marketplace_name` still names the marketplace the settings file declares. The bootstrap
  selects what it installs with `endswith("@" + $n)`, so a rename that updated the settings and
  the catalog but not that constant would leave its install set empty while the lane stayed green
  over it. The lane does not require a key per plugin: with the fleet list derived from the
  catalog, every catalogued plugin is either on by default or recorded off there.
  `harness-config`'s `check-plugin-drift.sh` cannot cover this repo: it diffs the catalog only
  against the settings file's `enabledPlugins` keys, reports a plugin with no key as NEW (report
  only), and checks no key order.
- Entries are sorted alphabetically, one per line, so a single plugin can be flipped without
  disturbing the rest. The one opt-out recorded today is `playgrounds`: its skill is a wrapper
  over the first-party `playground` plugin on `claude-plugins-official`, which the cloud bootstrap
  does not install, so enabled here it could only ever print install commands. An off-by-default
  plugin with no key here stays off; an operator who wants one turns it on with `/plugin enable`.
  One off-by-default plugin bundles an MCP server that needs a `userConfig` credential this
  environment has no reason to hold: `miro` (`miro_api_token`, no key here), set with
  `/plugin configure`. The cloud bootstrap does not install it, so in a cloud session Miro is
  reachable only as a claude.ai connector, when the account has connected one (see
  [Documentation and search connectors](#documentation-and-search-connectors)), not through the
  `miro` plugin's server. The off-by-default `dometrain` plugin ships no server: the user-scope
  `dometrain` server it reads from stays off in cloud sessions, because user-scope MCP servers
  live in `~/.claude.json` and do not reach a cloud session
  ([What carries over from your setup](https://code.claude.com/docs/en/cloud-environments#what-carries-over-from-your-setup)).
  No lane stage calls Miro or Dometrain.

### Documentation and search connectors

Context7, Ref, Firecrawl and Perplexity reach cloud sessions as OAuth claude.ai connectors, added
once per account at
[claude.ai/customize/connectors](https://claude.ai/customize/connectors) by the account owner
([#7006](https://github.com/melodic-software/claude-code-plugins/issues/7006)). Agents do not
add them.

- **Endpoints.** Context7: `https://mcp.context7.com/mcp/oauth`, the OAuth endpoint on
  [Set Up OAuth](https://context7.com/docs/howto/oauth). Ref: `https://api.ref.tools/mcp` with no
  key, which starts OAuth sign-in; an account in more than one Ref team appends
  `?scope=<team_id>` ([Ref install](https://docs.ref.tools/install)). Firecrawl:
  `https://mcp.firecrawl.dev/v2/mcp-oauth`, the OAuth URL on
  [Firecrawl MCP Server](https://docs.firecrawl.dev/mcp-server).
- **Delivery.** The cloud host passes the account's connectors into every cloud session, under
  the controls in
  [How connectors reach Claude Code](https://code.claude.com/docs/en/mcp#how-connectors-reach-claude-code).
  A routine (a scheduled task, in research preview) includes every connected connector unless it
  is removed, and a run can use each one it includes, writes too
  ([Connectors](https://code.claude.com/docs/en/routines#connectors)); trim each routine to what
  it needs. When a run stops for approval is in
  [Permission prompts during a run](https://code.claude.com/docs/en/routines#permission-prompts-during-a-run).
- **Cost rule.** A connector is allowed only on a vendor plan with a set cost and no automatic
  overage or automatic top-up, so that more usage happens only when the account owner buys it by
  hand. A plan that bills usage past its included amount on its own does not qualify until that
  billing is off. Read the vendor's page for the plan terms, never a copy here:
  [Context7 plans](https://context7.com/plans), [Ref pricing](https://docs.ref.tools/usage/pricing),
  [Firecrawl pricing](https://www.firecrawl.dev/pricing).
  The owner confirmed on 2026-10-24 that this fleet's Context7 and Ref accounts meet the rule
  ([recorded on #7006](https://github.com/melodic-software/claude-code-plugins/issues/7006#issuecomment-6395023400)),
  and later that its Firecrawl account does
  ([recorded on #7006](https://github.com/melodic-software/claude-code-plugins/issues/7006#issuecomment-6398682964)).
  The Perplexity account is not yet confirmed; the account owner adds it only after confirming it
  meets the rule.
- **Perplexity.** Its connector bills tool calls to the API organization chosen at sign-in, not a
  consumer subscription ([Perplexity MCP server](https://docs.perplexity.ai/guides/mcp-server));
  the same cost rule applies to that organization's billing.
- **No repository route.** The repository adds no `.mcp.json` and no `claude mcp add` in
  `.claude/cloud-bootstrap.sh`.
- **Untrusted input.** Stages that read untrusted input do not run on a cloud host: the lanes
  launcher refuses every cloud host for them, because the no-connector check has no deterministic
  form yet
  ([Untrusted-input stages](contracts/execution-target/README.md#untrusted-input-stages)).
- **Local sessions.** The connectors also load in local CLI sessions. A local Context7 server at
  another URL appears beside the connector; the
  [Disable claude.ai connectors](https://code.claude.com/docs/en/mcp#disable-claude-ai-connectors)
  `/mcp` toggle turns one off per project.

**As of:** 2026-10-25.

**Recheck:** a vendor page above moves its OAuth endpoint or billing terms, or
[How connectors reach Claude Code](https://code.claude.com/docs/en/mcp#how-connectors-reach-claude-code)
changes what governs connectors in cloud sessions.

### GitHub MCP tools vs the gh CLI

Both exist in cloud sessions and don't conflict, because they serve different callers:

- The **built-in GitHub MCP tools** are how the agent itself reads issues, PRs, and CI; they
  authenticate through the
  [GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy) with no setup.
- The **`gh` CLI** is what this repo's plugin scripts and hooks shell out to (several
  `source-control`, `guardrails`, and `work-items` suites SKIP without it). It is in the VM
  image's [installed tools](https://code.claude.com/docs/en/cloud-environments#installed-tools),
  and this fleet's environment setup script replaces that build with a pinned release
  ([cloud-fleet-setup.md](cloud-fleet-setup.md#step-1-the-shared-environment-claudeai-ui-one-time)).
  In cloud sessions it
  [authenticates through the proxy](https://code.claude.com/docs/en/cloud-environments#work-with-github-issues-and-pull-requests),
  and the [GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy) refuses
  its GraphQL-backed subcommands, which is why this repo opens PRs and issues there through the
  GitHub MCP tools and reads with `gh api` REST calls. Locally, contributors authenticate `gh`
  themselves as usual.

### Known gap: Ubuntu-archive `gh` 2.45 vs the seam's 2.94 floor (#3169)

[#3169](https://github.com/melodic-software/claude-code-plugins/issues/3169) closed not planned by the
owner's 2026-10-21 decision (no cloud sessions planned); reopen it when cloud sessions are in use.

### Known gap: no fleet permission floor (#3172)

[#3172](https://github.com/melodic-software/claude-code-plugins/issues/3172) closed not planned by the
owner's 2026-10-21 decision (no cloud sessions planned); reopen it when cloud sessions are in use.

### Maintenance caveats

- Some bootstrap pin sources are materialized from `melodic-software/standards` (see the
  [sync manifest](https://github.com/melodic-software/standards/blob/main/distribution/sync-manifest.yml)).
  Of the files the bootstrap reads, `.node-version` is in the
  synced set (verified against the `chore: sync standards components` history on 2026-07-30), so
  its Node pin updates arrive via sync. `.claude/settings.json` and the bootstrap script itself
  are repo-owned.
- `.github/requirements-ci.txt` is hash-locked. The lockfile carries ABI-specific hashes for both
  the CI interpreter (cp314 / 3.14) and the cloud VM system Python (cp311 / 3.11; #2657), so the
  bootstrap always installs with `--require-hashes` and a digest mismatch stays fatal:
  no interpreter-mismatch skip, no unpinned fallback. Installs use `pip` rather than `uv`, whose
  PyPI fetches time out against the VM's egress proxy.
- The bootstrap's own version pins exist only because those tools have no in-repo manifest; the
  cloud proxy blocks the GitHub API and `releases/latest` redirects, so the script can't
  self-resolve "latest". Each GitHub-release asset also carries a pinned SHA-256 the script
  verifies before installing (mismatch refuses the install and warns). Bump pin and hash together
  when the corresponding configs bump.
