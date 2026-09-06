# Scope semantics — verified facts this skill depends on

Every claim below was verified against a fetched official-docs page or an empirical test on a real
machine, not assumed from training data. Last re-verified 2026-09-05 against
[plugins-reference](https://code.claude.com/docs/en/plugins-reference),
[discover-plugins](https://code.claude.com/docs/en/discover-plugins),
[plugin-marketplaces](https://code.claude.com/docs/en/plugin-marketplaces), and the published
plugin-manifest JSON Schema, all re-fetched that day and all unchanged on the claims below. The
probes in "Where project-scope records come from, and why the skill cannot reap them" were run
2026-09-06 on **Claude Code 2.1.263** and carry that stamp.

**The file-level date is the date of the pass, not a blanket CLI stamp — per-claim stamps govern.**
The 2026-09-05 pass re-ran the plugin-CLI write matrix, the `update -s project` settings exemption
(against a real version bump, not a no-op), the project-scope cwd keying, the merged-effective
`enable` gate, and the reap-by-path survey live on **Claude Code 2.1.261**; those claims carry that
version. These claims were **not re-run on 2.1.261** and keep their older stamps:
the `/reload-plugins` bare-versus-`--force` warning behaviour, the install-summary activation line,
and the mid-session path-resolution behaviour, all of which need an interactive session and were
confirmed only as still-current documentation; the `claude plugin prune` `≥ 2.1.121` gate and the
`--force` `≥ 2.1.163` gate, neither of which the current docs state. The `userConfig` unset-key
render carries its own stamp, 2026-09-06 on **Claude Code 2.1.263**, in `SKILL.md`.

**Recheck trigger** (a date alone is not one): re-verify this file on any Claude Code **minor**
version bump that touches the plugin CLI, `pluginConfigs`/`userConfig` substitution, or
`/reload-plugins` — those are the observable events that can invalidate what is below. Each claim
that rests on an empirical probe rather than on documentation names the CLI version it was taken
on, so a stamp older than the running CLI is the signal to re-run that probe, not to trust it
harder.

## Scope-by-cwd loading

A plugin loads for a given working directory using scope precedence **local > project > user**:

| Scope | Settings file | Written by |
|---|---|---|
| `user` | `~/.claude/settings.json` | `claude plugin install\|update -s user` (default scope) |
| `project` | `<project-root>/.claude/settings.json` | `claude plugin install\|update -s project` — committed, team-shared |
| `local` | `<project-root>/.claude/settings.local.json` | `claude plugin install\|update -s local` — gitignored, personal |
| `managed` | Managed settings (enterprise) | Administrators only — this skill reports, never mutates |

`installed_plugins.json` (`~/.claude/plugins/installed_plugins.json`) can hold multiple install
records for the same `<plugin>@<marketplace>` id — one per scope, each with its own `version`. This
is normal, not a defect: a project can legitimately pin a different version than your personal user
scope. The record that actually loads for a given directory is the one at the *highest-precedence
scope present*, never simply "the newest version installed."

## Divergence is not automatically actionable

`fleet-state.sh`'s `divergences[]` lists every plugin id with more than one scope record, but tags
each with `versionsMatch`:

- `versionsMatch: true` — every scope pins the identical version. Benign, informational only. Do
  not count these toward a report's "N behind" line or list them under "Action needed."
- `versionsMatch: false` — scopes disagree on version. This is the actionable signal `sync`'s report
  surfaces and `converge` resolves.

A raw count of `divergences[].length` conflates the two and overstates drift — always filter on
`versionsMatch == false` before presenting a count to the user.

## `plugin list` / `plugin details` version output is misleading

**Verified misleading**: `claude plugin list` and `claude plugin details <name>` show the *highest
installed version across all scopes*, not the version actually loaded for the current working
directory. Never treat their output as "what's running here." Derive effective-version claims from
`fleet-state.sh`'s scope-by-cwd resolution (via `currentProject` + scope precedence) or a functional
probe — never from `list`/`details` text.

## `plugin update -s project` does NOT write committed settings

**Empirically verified** (hash-compared a real repo's `.claude/settings.json` and
`.claude/settings.local.json` before and after): `claude plugin update <id> -s project` updates only
the machine-local `installed_plugins.json` record. `enabledPlugins` carries no version — the
committed settings files are untouched by an update. Re-verified on Claude Code 2.1.228 under the
hardest available conditions: a tracked `.claude/settings.json` that a sibling `install -s project`
had just rewritten, reverted to clean, then updated — the update left it clean. Re-verified on
**Claude Code 2.1.261** against a real version bump, not a no-op: a throwaway local marketplace served
`probe-plugin` at `0.1.0`, an `install -s project` into a scratch repo wrote the id into its committed
`.claude/settings.json`, that file was reverted to clean, the marketplace was bumped and refreshed, and
`update -s project` then reported `updated from 0.1.0 to 0.1.1`. The `installed_plugins.json` record
advanced to `0.1.1` with a new `lastUpdated` and `installPath`, so a real write did happen, while
`git status` stayed empty. A second cycle (`0.1.1` → `0.1.2`) added a `.claude/settings.local.json` to
the scratch repo and hash-compared both settings files across the update: both were unchanged. `sync`'s in-repo
update step is therefore safe to run without a settings-diff review. It is the exception, not the
rule: the next section lists the calls that do write.

## Every call that touches `enabledPlugins` at project scope writes committed settings

**Empirically verified on Claude Code 2.1.228 and re-verified unchanged on 2.1.261** — one call
each, against a clean tracked `.claude/settings.json`, git-diffed after every step:

| Call | Writes `.claude/settings.json`? | Effect |
|---|---|---|
| `install <id> -s project` | yes | adds the id to `enabledPlugins`, value `true` |
| `uninstall <id> -s project` | yes | removes the entry, leaves `"enabledPlugins": {}` |
| `enable <id> -s project` | yes | adds the id, value `true` |
| `disable <id> -s project` | yes | adds the id, value `false` |
| `update <id> -s project` | no | the exemption above |

Three properties hold across every writing call:

- **The key is created when absent.** `uninstall` writes `enabledPlugins` even into a committed file
  that never had it, emptying the map to `{}` rather than deleting the key.
- **The whole file is re-serialized in Claude Code's key order,** so sibling keys unrelated to
  plugins can move. The reorder is a serialization artifact, not a semantic change.
- **`-s local` writes `.claude/settings.local.json` instead** — verified for `enable`/`disable`,
  which created that file and left the tracked `.claude/settings.json` clean. That file is
  gitignored, so local scope never dirties team-shared state.

`enable -s project` gates on the **merged effective** value, not that scope's raw map: enabling an id
that is `true` only at user scope fails with `Plugin "<id>" is already enabled at project scope`
rather than writing a project-scope entry. Re-verified on **Claude Code 2.1.261**, same error string,
and the committed file was byte-unchanged after the failed call.

Two consequences:

- **`converge`** — an `uninstall -s project` against a project whose committed settings carry no
  `enabledPlugins` entry still dirties the tracked file, with a diff that changes no behavior: an
  empty map plus a key reorder. Expect it; it is not evidence an entry was removed.
  [converge.md](converge.md) Step 5 classifies it.
- **`sync`** — this is why [sync-install-enable.md](sync-install-enable.md) Step 5 enables automatically only at `user` and `local`
  scope and reports a `project`-scope gap instead of filling it. `sync` has no autonomous-session
  abort, so it has no safe moment to write a committed file; after that restriction, no `sync` path
  writes one.

## Project scope: the CLI keys on the cwd, `fleet-state.sh` matches on the checkout root

**Empirically verified on Claude Code 2.1.228 and re-verified unchanged on 2.1.261.** `-s project`
has no path flag — it acts on the current directory, and it means that literally. Installing from
`<checkout>/nested/subdir` recorded `projectPath: <checkout>\nested\subdir` and created a fresh
`nested/subdir/.claude/settings.json`, rather than resolving up to the checkout root. The 2.1.261
re-run also confirmed the checkout root's own committed settings file stayed untouched.

`fleet-state.sh` resolves its project root differently: `CLAUDE_PROJECT_DIR`, else
`git rev-parse --show-toplevel`, else a `.claude`-corroborated cwd (the `PROJECT_ROOT` resolution in
`fleet-state.sh`), and
`fleet-state.test.sh` pins that a session invoked from a nested subdirectory still matches the
checkout-root record.

The two layers therefore disagree, which is a real blind spot — see
[gotchas.md](gotchas.md). It also means two `git worktree` checkouts of one repo, sharing one `.git`
and one tracked `.claude/settings.json`, hold independent records and pin independently.

## A `projectPath` outlives its directory, and no CLI verb reaps the record

Removing the directory a project/local install was made from leaves the install record in place,
still naming the path. **Re-verified on Claude Code 2.1.261**: `claude plugin --help` lists no verb that
removes an install record by path, and `claude plugin prune --help` reports "Remove auto-installed
dependencies that are no longer needed" — a *dependency* axis, whose own `-s project` has the same
no-path-flag behaviour documented above, so it acts on the cwd and cannot reach a record belonging to
a directory that is gone.

`fleet-state.sh` therefore annotates each project/local record (and each `divergences[].scopes[]`
entry) with `projectPathPresent: true|false|null` — a plain directory test, `null` where not
applicable. Read it precisely:

- It answers **"is this path present on this machine right now"**, and nothing else.
- `false` is **not** a verdict that the directory is gone. An unmounted volume, an offline network
  share, and unplugged removable media all produce `false`, and worktrees — which pin independently
  per the section above — are exactly the population most likely to look absent while being
  perfectly recoverable.
- It is **advisory**: it must never filter `installed[]` or `divergences[]`. Suppressing rows on a
  directory test hides real drift from anyone whose repos are not on a permanently-attached disk.

`sync` reports these rows in a section of their own, outside the actionable Divergences count,
because `converge`'s `(cd "<projectPath>" && …)` form cannot execute against an absent path. Naming
the condition is this skill's whole role here; reaping the record is not something it can or should
do.

## Where project-scope records come from, and why the skill cannot reap them

The section above says the records cannot be reaped. This one says where they come from. Every claim
below is doc-sourced or verified by a probe, each with its source or CLI version named. **Recheck
trigger:** any change to how a repo's committed `enabledPlugins` block is applied at session start,
or any `claude plugin` release note adding a verb that removes an install record by path.

**A repo's committed `.claude/settings.json` `enabledPlugins` block is the documented cloud install
mechanism.** Per
[cloud-environments](https://code.claude.com/docs/en/cloud-environments) ("What carries over from
your setup", fetched 2026-09-05), plugins declared in that committed block are "Installed at session
start from the marketplace you declared." Plugins enabled only in a user's own settings do not carry
over to a cloud session at all. So the block exists to make a team's plugin set reproducible
somewhere the user's `~/.claude` is not.

**Locally, session start writes the records.** Per
[discover-plugins](https://code.claude.com/docs/en/discover-plugins) ("Configure team marketplaces",
fetched 2026-09-05), as of v2.1.195 a plugin that only project settings enable, coming from an
external source, "doesn't load until the team member installs it." That sentence covers the case
where the user has never installed the plugin. When the user already holds it at user scope, the
session start does the install itself. **Verified 2026-09-06 on Claude Code 2.1.263**: a scratch git
repo under the temp directory with a committed `.claude/settings.json` declaring
`extraKnownMarketplaces` for an already-registered marketplace and two `enabledPlugins: true` ids
already installed at user scope; one headless `claude -p` session run from that directory; then
`installed_plugins.json` diffed against a copy taken before the run. The diff was exactly two new
`scope: "project"` records, one per enabled id, keyed by the scratch repo's absolute `projectPath`,
both with the same `installedAt` millisecond, each pinned to the version the user scope already held
and pointing `installPath` at the user scope's existing cache directory. No new cache directory was
created and the user-scope records were untouched. A field sample on 2.1.261 (64 records for one
repo path sharing one `installedAt` second) has the same shape: one session-start batch, one record
per `true` entry per checkout path. The write happens even though nothing new was fetched; the
record is a pin, not a download.

**Precedence explains why a user-scope duplicate does not prevent the project record.** Per
[settings-reference](https://code.claude.com/docs/en/settings-reference#enabledplugins) (fetched
2026-09-05), `enabledPlugins` resolves managed > `--settings` > local > project > user, and
"Project settings take precedence over user settings, so setting a plugin to false in
~/.claude/settings.json doesn't disable a plugin that the project's .claude/settings.json enables.
To opt out of a project-enabled plugin on your machine, set it to false in .claude/settings.local.json
instead." Precedence settles which `enabledPlugins` value is effective, and the probe above
establishes that an effective project-scope `true` writes its own record regardless of the user
scope. So every project-scope `true` duplicating a user-scope install produces one version-pinned
project record per plugin per checkout.

**A project-scope `false` writes nothing.** **Verified 2026-09-06 on Claude Code 2.1.263** in the
same scratch repo: the block reduced to one entry, `"<id>": false` for a plugin installed at user
scope; one headless session; `installed_plugins.json` byte-identical before and after (no new
record, no touched timestamp), and the session reported that plugin's skill as unavailable while a
sibling user-scope plugin's skill stayed available. A `false` entry is enablement state only; it
never manufactures an install record.

**Removing the records rewrites the committed block.** Observed in the same pass on 2.1.263:
`claude plugin uninstall -s project <id>` run from inside the checkout removed the project record
and also deleted that id from the repo's `.claude/settings.json` `enabledPlugins`, leaving an empty
`enabledPlugins: {}` and reordering the file's top-level keys. Undoing a stranded record for a live
checkout therefore dirties the working tree; do it before committing, or expect to revert the
settings file afterwards. For an absent path there is no cwd to run it from, which is the case the
section above records as unreapable.

**Nothing on either side of the boundary reaps the result.** `git worktree remove` deletes the
directory and does not touch `~/.claude`, and the section above records that no CLI verb removes a
record by path (`-s project` acts on the cwd only, `prune` is dependency-only). The product's own
retention sweep does not cover them either: the "Cleaned up automatically" list at
[claude-directory](https://code.claude.com/docs/en/claude-directory) (fetched 2026-09-05) names
nothing under `~/.claude/plugins/`. That the per-project records are a live, maintained mechanism
rather than vestigial state is visible in the Claude Code changelog for 2.1.224, "Fixed plugin
install records being silently corrupted when the same plugin is installed in multiple projects".
Nothing between 2.1.200 and 2.1.261 adds a prune-by-path verb.

**Synced plugins are the contrast case, not a source of these records.** Per
[plugins-reference](https://code.claude.com/docs/en/plugins-reference) ("Synced plugins", fetched
2026-09-05), plugins enabled on a claude.ai account load as `<name>@synced` in Cowork and cloud
sessions "with no marketplace and no install record", and "Claude Code doesn't load them in sessions
you start in your own terminal." That is enablement without any record at all, so a synced plugin
never explains a project-scope row. Whether a custom GitHub marketplace can be enabled at account
level on a personal account is undocumented.

## `/reload-plugins` — bare by default, `--force` for the MCP-cache-invalidation case

Everything in this section is doc-sourced and was re-fetched 2026-09-05 with the quoted text
unchanged. The *behaviour* — what a bare reload actually warns about in a live session — is **not
re-run on 2.1.261**: it needs an interactive session, which a non-interactive probe pass cannot
drive. The `≥ 2.1.163` gate for `--force` is likewise **not re-verified on 2.1.261**, because the
current docs page states the flag without naming the version that introduced it.

**Verified against `code.claude.com/docs/en/discover-plugins`**: `/reload-plugins` refreshes skills,
agents, hooks, MCP, and LSP servers in-process. It does **not** cover monitors — per
`code.claude.com/docs/en/plugins-reference`, "monitors require a session restart". Recommend bare `/reload-plugins` by default; call out the restart requirement
only when an updated plugin ships a monitor.

**An install can now activate itself — but not the installs this skill issues.** As of Claude Code
2.1.221, an install started from the in-session `/plugin` interface reports its own activation state:
per `code.claude.com/docs/en/discover-plugins` (re-fetched 2026-09-05, unchanged), the summary says either
`Plugin is now active.` — "Claude Code activated the plugin as part of the install" — or
`Run /reload-plugins to activate.`, which happens "because activating it would invalidate the prompt
cache or because the activation attempt failed". Before 2.1.221, "no install took effect in the
current session until you ran `/reload-plugins` or restarted".

This does **not** relax the reload guidance below, because `sync` installs through the shell command,
not the interface: "The `claude plugin install` shell command doesn't run in a session, so Claude Code
loads the plugins it installs the next time you start Claude Code, or when you run `/reload-plugins`
in a session that's already open." So a `sync` report still ends with reload guidance for everything
it installed. The activation line matters only for reading a user's own `/plugin` install summary —
when they say a plugin is already active, believe the summary rather than telling them to reload
again; and when the summary named the prompt-cache case, that is the same condition `--force` exists
for below.

`--force` is real (Claude Code ≥ 2.1.163). **The general condition it exists for is prompt-cache
invalidation** — per `code.claude.com/docs/en/discover-plugins`: "When the reload would invalidate
the prompt cache, the command warns and skips until you rerun it with `--force`."

The MCP case is the docs' worked example of that condition, not the condition itself: a plugin
providing an MCP server whose tools aren't deferred by tool search "costs more when its tools aren't
deferred by tool search", so it is **the common cause** of the warning — but treating it as the sole
trigger tells a reader that a warning arising any other way is not a `--force` case, when it is.

So follow the docs' own two-step rather than predicting the cause:

> Check the install summary: if it reports `Run /reload-plugins to activate.`, run `/reload-plugins`,
> and if that warns that the reload will re-read the conversation, rerun it as `/reload-plugins --force`.

Never recommend `--force` pre-emptively alongside every reload — it exists specifically to opt into a
real token cost the bare command declines to pay automatically. Recommend bare; escalate on the
warning.

## `pluginConfigs` and `enabledPlugins` have OPPOSITE scope rules

This skill reads both surfaces, and they do not agree on which scopes count. Getting this backwards
is silent in both directions, so the asymmetry is stated here once and pointed at from everywhere
else.

**`pluginConfigs` — three sources only.** Re-fetched 2026-09-05, wording unchanged. Per
`code.claude.com/docs/en/plugins-reference`: "Claude
Code reads all `pluginConfigs` values from only three settings sources" — user settings
(`~/.claude/settings.json`), `--settings`, and managed settings, with precedence
managed → `--settings` → user. In every one of those sources the value nests under `options`:
`{"pluginConfigs":{"<id>@<marketplace>":{"options":{"<key>":"<value>"}}}}`. A key placed directly
under the plugin id is silently ignored and the render shows the literal placeholder (verified
2026-09-06 on **Claude Code 2.1.263**). And explicitly:

> Entries in a project's `.claude/settings.json` or `.claude/settings.local.json` are ignored. Both
> files live in the workspace, so a cloned repository could supply values there, and those values
> would flow into plugin hook commands, MCP server configs, LSP commands, and monitor commands.
> Before v2.1.207, these entries were read. The restriction is specific to `pluginConfigs`:
> `enabledPlugins` still honors project and local settings.

**`enabledPlugins` — user, project, and local all count**, merged local > project > user. That is
why `fleet-state.sh` reads all three settings maps for enablement, and why doing the same for
`pluginConfigs` would be wrong.

Two consequences this skill must not get wrong:

- Setting `install_new` in a repo's `.claude/settings.json` does **nothing**. The value is ignored,
  the render falls back to the unset placeholder, and `sync` proceeds under the `ask` default with no
  indication the configured value was discarded. Never advise setting it at project or local scope.
- A `--setting-sources` invocation that omits `user` drops user settings from that three-source read
  list, so a headless `sync` launched that way silently loses `install_new` the same way. See
  [sync-install-enable.md](sync-install-enable.md) Step 4 — the fallback is correct, the silence is not.

## `userConfig` has no `enum` type

**Re-verified 2026-09-05 against the published plugin-manifest JSON Schema**: allowed `type` values
are `string`, `number`, `boolean`, `directory`, `file` — there is no `enum` *type*. The schema does
use an `enum` keyword, but only to constrain `type` itself to that list; an option cannot declare its
own allowed values. The schema's `required` array for
a `userConfig` option is `type`, `title`, `description`, and `claude plugin validate` on 2.1.261
rejects an option that omits `title`. `install_new` ships as `type: string` with its
valid values (`ask`/`all`/`none`) documented in `description` and validated in prose by this skill,
not by the manifest schema.

## Renames are CC-native (≥ v2.1.193)

Claude Code rewrites a marketplace's `renames` map into installed/enabled state automatically at
session start (old id → new id; `null` means removal). This skill hard-codes no rename knowledge —
its only rename-adjacent behavior is that anything present in the current catalog but absent from
`installed_plugins.json` shows up as `missing_from_install`, which naturally covers a renamed
plugin's new id. Renames mapping requires ≥ v2.1.193 — re-confirmed 2026-09-05 against
`code.claude.com/docs/en/plugin-marketplaces`, which still says "Automatic migration requires Claude
Code v2.1.193 or later." The `claude plugin prune` ≥ v2.1.121 gate is **not re-verified on 2.1.261**:
the current docs describe `prune` without naming an introducing version, so the gate stands on its
original source and nothing this pass found contradicts it.

## An unchanged version number keeps the old cache directory while `gitCommitSha` moves

`claude plugin update -y <plugin>@<marketplace>` re-points the install record's `gitCommitSha` in
`installed_plugins.json` without rewriting the plugin's cache directory when the manifest version
number is unchanged across the two commits. The cache is keyed by version, so an update that does
not move the version finds the directory already there and leaves the older build in it. The record
then names the new commit and the files on disk are the old one.

**Consequence, and it is the reason the check exists.** The version-and-sha comparison every
delivery script relies on passes in exactly this state, so it is not proof that the files loaded are
the files delivered. Any measurement or behaviour test run against that cache directory is a test of
a different build than the one the record names, and nothing in the report says so.

Observed on **Claude Code 2.1.259** (issue #3681 evidence, not re-run since). After a delivery,
six plugins reported the new sha while their cache directories still held files from an earlier
commit — twelve stale files in the worst case, including a reviewed dispatcher, three formatters, and
two `hooks.json` files. Removing those version directories and running the update again recreated
them correctly from the clone, which is both the confirmation and the remediation. **Recheck
trigger:** any minor-version bump touching plugin caching or the `plugin update` path — a date alone
is not a trigger.

`cache-content-check.sh` is the standing detection: it byte-compares every file in a cache directory
against the recorded commit in the marketplace clone, which is the only check that separates this
state from a healthy one. It reports and never repairs; see `SKILL.md`'s "Cache content" section.

**A marketplace clone is shallow, so most installs are unverifiable most of the time.** The clone
under `installLocation` carried a `.git/shallow` file and a three-commit history when this was
measured, so an install record naming any commit older than that window has no object to compare
against. Verified 2026-09-05 on **Claude Code 2.1.261**: 11 of 74 user-scope installs on the
authoring machine reported `sha-not-local` for exactly this reason, on a fleet with nothing wrong
with it. That is the steady state, not an edge case, and it caps how much any single run of the
check can establish. The check never fetches the missing commit: a fetch is a network mutation, and
it would repair the condition being reported. **Recheck trigger:** any change to how Claude Code
clones a marketplace, which would move the depth this number rests on.

## `autoUpdate` is a background complement, not a substitute

Official-Anthropic marketplaces default `autoUpdate: true`; third-party and local-dev marketplaces
default it off (absent from `known_marketplaces.json`, not `false`). When on, Claude Code refreshes
marketplace data and bumps already-installed plugins once per session start, after a random delay of
up to ten minutes. This skill never mutates the setting — it only reports the marketplace's current
`autoUpdate` state and suggests enabling it when off, since it never overlaps with what this skill
covers (new-plugin install, `enabledPlugins` completeness, divergence detection/convergence,
deterministic on-demand execution).
