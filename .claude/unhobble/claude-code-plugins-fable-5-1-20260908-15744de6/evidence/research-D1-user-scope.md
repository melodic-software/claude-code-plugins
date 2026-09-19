# Research memo D1: should user scope be opted in for the unhobble run?

All web sources fetched live on **2026-09-11** (WebFetch, plus `curl` of the Mintlify raw
`.md` for pages whose HTML render exceeded the fetch budget). No claim below rests on training
memory. Repo evidence is second-tier and labeled as such.

## Question

In a Claude Code on the web (cloud) session on `<worktree>`, the
user-global `~/.claude/settings.json` enables all 73 plugins of the repo's own marketplace (20
wiring hooks), and that file is synthesized by the cloud environment snapshot plus
`.claude/cloud-bootstrap.sh` rather than by a human editing personal settings. The unhobble
contract strips PROJECT-scope surfaces by default and treats user-global surfaces as opt-in.
Gather the evidence needed to decide whether to opt user scope in for this run. **No decision is
made here.**

## Findings

### 1. Settings scopes and precedence; where `enabledPlugins` lives

Four settings files plus managed sources; precedence is managed > command line > project local >
shared project > user.

> Claude Code reads settings from four files, and an organization can also deliver managed
> settings from the claude.ai console.
> — code.claude.com/docs/en/settings, "Settings files and who they affect", fetched 2026-09-11

> When the same key appears in more than one place, Claude Code uses the value from the highest
> level that sets it.
> — same page, "Settings precedence" (ordered list: 1 Managed, ... 5 User settings
> `~/.claude/settings.json`), fetched 2026-09-11

`enabledPlugins` is settable in **any** of the four files:

> Turn individual plugins on or off, keyed by `plugin-name@marketplace-name`. A plugin with no
> entry at any scope falls back to its `defaultEnabled` value.
> — code.claude.com/docs/en/settings-reference, "`enabledPlugins`" (Scope: `Any file`; Type:
> object mapping to Boolean), fetched 2026-09-11

**Which scope wins.** The docs state the project-over-user direction explicitly, and only that
direction:

> Project settings take precedence over user settings, so setting a plugin to `false` in
> `~/.claude/settings.json` doesn't disable a plugin that the project's `.claude/settings.json`
> enables.
> — same entry, fetched 2026-09-11

For the case asked about (true at user, **false** at project), the general precedence stack
implies project wins, but no sentence states it for `enabledPlugins` specifically. For
**absent** at project, the user value stands: `defaultEnabled` applies only when there is no
entry "at any scope", and an entry at any scope takes precedence over it:

> `defaultEnabled` is the fallback when nothing else has decided the plugin's state. Two things
> take precedence over it: **The user's setting**: an entry for the plugin in `enabledPlugins`
> at any settings scope.
> — code.claude.com/docs/en/plugins-reference, "Default enablement", fetched 2026-09-11

### 2. How an enabled plugin's hooks and skills load; per-project disable

Hooks: a plugin's `hooks/hooks.json` is a first-class hook source, active on enablement.

> | Plugin `hooks/hooks.json` | When plugin is enabled | Yes, bundled with the plugin |
> — code.claude.com/docs/en/hooks, hook-source table, fetched 2026-09-11

> When a plugin is enabled, its hooks merge with your user and project hooks.
> — same page, "Plugin scripts" tab, fetched 2026-09-11

Skills: plugin skills load wherever the plugin is enabled, namespaced, and their **descriptions**
occupy context every turn while bodies load on invocation.

> | Plugin | `<plugin>/skills/<skill-name>/SKILL.md` | Wherever the plugin is enabled, as
> `/plugin-name:skill-name` |
> — code.claude.com/docs/en/skills, "Where skills live", fetched 2026-09-11

> In a regular session, skill descriptions are loaded into context so Claude knows what's
> available, but full skill content only loads when invoked.
> — same page, frontmatter/invocation section, fetched 2026-09-11

**Per-project disable of a user-enabled plugin is possible** — `false` at project scope is a
documented, supported spelling:

> To keep a plugin out of one project's synced sessions in every environment, set
> `"<name>@synced": false` under `enabledPlugins` in that project's committed
> `.claude/settings.json`.
> — code.claude.com/docs/en/plugins-reference, "Synced plugins", fetched 2026-09-11

> The restriction is specific to `pluginConfigs`: `enabledPlugins` still honors project and local
> settings.
> — same page, `pluginConfigs` section, fetched 2026-09-11

The repo's own bootstrap already relies on this overlay direction: a repo `false` opts out of a
fleet entry (see finding 4).

### 3. Cloud provisioning; is `~/.claude` durable per-user state?

Fresh VM per session, repo cloned in:

> In Anthropic-hosted environments, each session gets a fresh virtual machine (VM) running
> Ubuntu 24.04 on x86_64 ... with your repository cloned and common toolchains pre-installed.
> — code.claude.com/docs/en/cloud-environments, "Cloud environments", fetched 2026-09-11

> Cloud sessions start from a fresh clone of your repository. Anything you commit to the repo is
> available. Anything you've installed or configured only on your own machine isn't available in
> the session.
> — same page, "What carries over from your setup", fetched 2026-09-11

The **user's own machine** `~/.claude` never reaches the cloud — and the docs name
`enabledPlugins` at user scope by name as a thing that does **not** carry over:

> | Plugins enabled only in your user settings | No | User-scoped `enabledPlugins` lives in
> `~/.claude/settings.json`. Declare them in the repo's `.claude/settings.json` instead ... |
> — same table, fetched 2026-09-11

> **User and project local settings** (`~/.claude/settings.json` and
> `.claude/settings.local.json`): not read. Both stay on your machine, and the local file isn't
> in the clone.
> — code.claude.com/docs/en/settings, "Settings in cloud sessions", fetched 2026-09-11

> Cloud sessions on Claude Code on the web don't read your local `~/.claude/settings.json`;
> hooks there come from the repo and from your organization's server-managed settings.
> — code.claude.com/docs/en/hooks, hook-sources note, fetched 2026-09-11

What *does* persist across sessions is the **environment cache**, a filesystem snapshot built by
the setup script:

> The cache is a filesystem snapshot, so it keeps what the setup script writes to disk and loses
> anything that was only running. Packages you install, Docker images you pull, and files you
> write all carry over.
> — code.claude.com/docs/en/cloud-environments, "Environment caching", fetched 2026-09-11

> The setup script runs again to rebuild the cache when you change the environment's setup script
> or allowed network hosts, and when the cache reaches its expiry after roughly seven days.
> Resuming an existing session never re-runs the setup script.
> — same section, fetched 2026-09-11

> You can also ask Claude to install packages mid-session, but those installs don't carry over to
> other sessions.
> — same page, "Run tests, start services, and add packages", fetched 2026-09-11

**Net:** the in-container `~/.claude/settings.json` is not the operator's personal file and is not
per-user durable state in the sense the docs use "user settings". It is per-environment
synthesized state, rebuilt by the setup script into the environment cache (≈7-day expiry) and
re-repaired by the repo's `SessionStart` hook. Docs are **silent** on whether the cache snapshot
covers `$HOME` specifically; that specific durability claim is unverified (see Unverified).

### 4. Repo's own account (second-tier): why the whole catalog is enabled at user scope

> The whole catalog is installed here, so this repo dogfoods everything it publishes and a
> regression in any plugin surfaces here first — bar what a repo delta opts out of.
> — `<worktree>/docs/CLOUD-SESSIONS.md` (~line 372), read 2026-09-11

> ... which the shared environment fetches at cache build, writes into the snapshot at
> `/opt/melodic-fleet-plugins.json`, and installs at user scope; `cloud-bootstrap.sh` reads that
> snapshot copy overlaid with `.claude/settings.json`, so the committed `enabledPlugins` block
> carries only this repo's deltas (an explicit `false` opts out of a fleet entry ...).
> — same file (~line 379), read 2026-09-11

> The trade is context: every enabled plugin adds per-turn cost, so a *consumer* repo should opt
> out of what it does not need rather than copying anything wholesale.
> — same file (~line 388), read 2026-09-11

Bootstrap comment confirming user scope is the mechanism, not a preference:

> Enabled set: the fleet list the shared environment baked into the snapshot ... overlaid with
> the tracked settings file, so a repo entry set to false opts out of a fleet entry ... so a
> settings block reduced to deltas still dogfoods the whole catalog from the current branch.
> — `<worktree>/.claude/cloud-bootstrap.sh` (~lines 205-210), read 2026-09-11

CI holds the dogfooding claim to the files:

> docs/CLOUD-SESSIONS.md promises `enabledPlugins` "turns on the whole catalog, so this repo
> dogfoods everything it publishes"; nothing enforced it ... The failure is silent by
> construction: .claude/cloud-bootstrap.sh computes its install set from that same
> enabledPlugins map.
> — `<worktree>/.github/workflows/ci.yml` (~line 761), read 2026-09-11
> (gate: `scripts/check-plugin-catalog-enablement.sh`)

Also relevant to how a strip would behave in-session: the repo records that a `SessionStart`
install is never visible to the session that ran it ("The command/skill registry is built when the
Claude Code process starts ... and is not re-read afterwards", CLOUD-SESSIONS.md ~line 286),
verified by that doc's own 2026-08-15 observation, not by an Anthropic page.

### 5. Official guidance on instruction hygiene; hooks that enforce vs. correct

Trimming guidance exists and is scope-agnostic — it names CLAUDE.md size and pruning without ever
distinguishing user-scope from project-scope instructions:

> Keep it concise. For each line, ask: *"Would removing this cause Claude to make mistakes?"* If
> not, cut it. Bloated CLAUDE.md files cause Claude to ignore your actual instructions!
> — code.claude.com/docs/en/best-practices, "Write an effective CLAUDE.md", fetched 2026-09-11

> **Fix**: Ruthlessly prune. If Claude already does something correctly without the instruction,
> delete it or convert it to a hook.
> — same page, "The over-specified CLAUDE.md", fetched 2026-09-11

> **Size**: target under 200 lines per CLAUDE.md file. Longer files consume more context and
> reduce adherence.
> — code.claude.com/docs/en/memory, "How CLAUDE.md affects behavior", fetched 2026-09-11

The memory page lists user scope (`~/.claude/CLAUDE.md`) and project scope in one load-order
table but attaches no different ablation or trimming advice to either.

Hooks: instructions are advisory context; hooks are the deterministic layer, and the docs
separate "enforce a gate" from "nudge behavior":

> Both are loaded at the start of every conversation. Claude treats them as context, not enforced
> configuration. To block an action regardless of what Claude decides, use a PreToolUse hook
> instead.
> — code.claude.com/docs/en/memory, "Two memory systems", fetched 2026-09-11

> Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guarantee the
> action happens.
> — code.claude.com/docs/en/best-practices, "Set up hooks", fetched 2026-09-11

> Because the `if` filter is best-effort, use the permission system rather than a hook to enforce
> a hard allow or deny.
> — code.claude.com/docs/en/hooks, matcher/`if` section, fetched 2026-09-11

> If your hook is meant to enforce a policy, use `exit 2`.
> — same page, exit-code note, fetched 2026-09-11

This matches, but does not originate, the unhobble contract's own carve-out: "Hooks that enforce
policy (secrets gates, PR-body contracts, permission guards) are classified `policy` at snapshot
time and are NOT stripped by default"
(`plugins/claude-config/skills/unhobble/SKILL.md`, "Scope and safety rails", read 2026-09-11).

## Consensus table

| Claim | Sources agreeing | Sources disagreeing / silent | Confidence |
|---|---|---|---|
| Four scopes: managed > command line > project local > shared project > user | settings (precedence list + graphic) | none | High |
| `enabledPlugins` may be set in any of the four files | settings-reference (`Scope: Any file`); plugins-reference | none | High |
| A project `false` can disable a plugin enabled elsewhere (per-project opt-out is supported) | plugins-reference (synced-plugin opt-out); repo bootstrap overlay | settings-reference states only the reverse (project `true` beats user `false`) for `enabledPlugins` | Medium-High |
| Plugin absent at project + `true` at user ⇒ enabled | plugins-reference "Default enablement" (an entry at any scope decides) | no page states the user-only case in those words | Medium-High |
| Enabling a plugin activates its hooks and loads its skills (descriptions each turn) | hooks (source table + "merge with your user and project hooks"); skills ("wherever the plugin is enabled"; descriptions in context) | none | High |
| A real user's `~/.claude/settings.json` never reaches a cloud session | cloud-environments "What carries over"; settings "Settings in cloud sessions"; hooks note | none | High |
| Each cloud session gets a fresh VM; only the environment cache (setup-script filesystem snapshot, ≈7-day expiry) persists between sessions | cloud-environments (fresh VM, caching); claude-code-on-the-web (expiry reclaims the VM) | no page says whether the snapshot covers `$HOME` | High for the mechanism, Low for `$HOME` |
| The repo's user-scope enablement is environment/bootstrap-synthesized dogfooding, not a human preference | CLOUD-SESSIONS.md; cloud-bootstrap.sh; ci.yml gate comment | no official Anthropic source describes this pattern | High (repo-internal), second-tier |
| Official trimming guidance does not distinguish user-scope from project-scope instructions | best-practices; memory | both are silent on the distinction rather than contradicting it | High (as a silence claim) |
| Hooks are the deterministic/enforcement layer; instructions are advisory | best-practices; memory; hooks | none | High |

## Unverified claims

1. **`enabledPlugins` `true` at user + `false` at project.** No page states the outcome for this
   exact pair. Inference from the general precedence stack (project over user) plus the
   synced-plugin opt-out sentence points to project winning; treat as inference, not doc.
2. **Whether the environment cache snapshot includes `$HOME/.claude`.** Docs say the cache "keeps
   what the setup script writes to disk" but never scope it to a directory. The repo's bootstrap
   behaves as if it does; unverified against Anthropic docs.
3. **In-session effect of disabling plugins mid-cloud-session.** Docs describe `/reload-plugins`
   and note `/plugin` is unavailable in cloud sessions; the repo records that the registry is
   built at process start and not re-read. No official page states what happens when
   `enabledPlugins` is edited on disk mid-cloud-session. Unverified.
4. **Anthropic engineering blog posts on Claude Code best practices** were not fetched; only
   code.claude.com docs were. Any claim attributed to anthropic.com/engineering would be
   unverified here.
5. **Per-turn context cost of 73 enabled plugins.** Only qualitative sources exist (skills page:
   descriptions load every session; discover-plugins: a per-plugin "Context cost" estimate in
   `/plugin`). No measured number was collected.

## Options the evidence supports

Listed, not ranked; no recommendation.

- **A. Leave user scope out (contract default).** Rests on: the in-container user file is
  environment-synthesized, so ablating it measures the environment's provisioning rather than
  standing human instructions; and the unhobble contract already reserves user-global surfaces
  for explicit opt-in.
- **B. Opt user scope in wholesale.** Rests on: 73 plugins' skill descriptions load into every
  turn and 20 plugins' hooks merge into every session (hooks + skills docs), so a project-only
  strip leaves the dominant instruction surface in place and the "bare baseline" is not bare.
- **C. Ablate at project scope instead of touching user scope** — add `"<plugin>@<marketplace>":
  false` entries to the repo's committed `.claude/settings.json`. Supported by the documented
  per-project opt-out and by the bootstrap's existing overlay semantics (repo `false` opts out of
  a fleet entry). Stays inside the contract's PROJECT-scope default and is reversible by git.
- **D. Partial opt-in: hooks only.** Strip the 20 hook-wiring plugins, keep the rest enabled,
  since hooks are the enforcement layer while skill descriptions are advisory context. Note the
  contract's `policy` carve-out (secrets gates, PR-body contracts, permission guards) would still
  exclude some of them.
- **E. Defer to the environment layer.** Change the fleet list / setup script rather than the
  session, accepting the ≈7-day cache rebuild latency and the fact that the change would affect
  every repo served by that environment, not just this one.
- **F. Run the experiment, then verify what actually loaded** with `/context` and
  `claude plugin list --json` before treating any arm as "stripped", given the unverified
  mid-session reload behavior (Unverified #3).
