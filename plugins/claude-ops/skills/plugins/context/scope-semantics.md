# Scope semantics — verified facts this skill depends on

Every claim below was verified against a fetched official-docs page or an empirical test on a real
machine, not assumed from training data. Last re-verified 2026-07-18 against
[plugins-reference](https://code.claude.com/docs/en/plugins-reference),
[discover-plugins](https://code.claude.com/docs/en/discover-plugins), the published plugin-manifest
JSON Schema, and the Claude Code changelog (version gates). Re-verify against those pages if Claude
Code's plugin CLI changes shape.

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

This section is the **single normative statement** of that filter rule. SKILL.md's Report section,
[converge.md](converge.md), and [gotchas.md](gotchas.md) point here rather than restating it, so a
change to the rule is a change to this section only.

Each `divergences[].scopes[]` entry also carries `projectPathExists` (true/false from a directory
test on the recorded `projectPath`; null for user-scope entries, which have none), so a consumer
proposing a `(cd "<projectPath>" && …)` command can withhold it per-scope when the recorded
directory no longer exists — see [converge.md](converge.md) Step 2.

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
had just rewritten, reverted to clean, then updated — the update left it clean. `sync`'s in-repo
update step is therefore safe to run without a settings-diff review. It is the exception, not the
rule: the next section lists the calls that do write.

## Every call that touches `enabledPlugins` at project scope writes committed settings

**Empirically verified on Claude Code 2.1.228** — one call each, against a clean tracked
`.claude/settings.json`, git-diffed after every step:

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
rather than writing a project-scope entry.

Two consequences:

- **`converge`** — an `uninstall -s project` against a project whose committed settings carry no
  `enabledPlugins` entry still dirties the tracked file, with a diff that changes no behavior: an
  empty map plus a key reorder. Expect it; it is not evidence an entry was removed.
  [converge.md](converge.md) Step 5 classifies it.
- **`sync`** — this is why [sync.md](sync.md) Step 5 enables automatically only at `user` and `local`
  scope and reports a `project`-scope gap instead of filling it. `sync` has no autonomous-session
  abort, so it has no safe moment to write a committed file; after that restriction, no `sync` path
  writes one.

## Project scope: the CLI keys on the cwd, `fleet-state.sh` matches on the checkout root

**Empirically verified on Claude Code 2.1.228.** `-s project` has no path flag — it acts on the
current directory, and it means that literally. Installing from `<checkout>/nested/subdir` recorded
`projectPath: <checkout>\nested\subdir` and created a fresh `nested/subdir/.claude/settings.json`,
rather than resolving up to the checkout root.

`fleet-state.sh` resolves its project root differently: `CLAUDE_PROJECT_DIR`, else
`git rev-parse --show-toplevel`, else a `.claude`-corroborated cwd (`fleet-state.sh:211-221`), and
`fleet-state.test.sh` pins that a session invoked from a nested subdirectory still matches the
checkout-root record.

The two layers therefore disagree, which is a real blind spot — see
[gotchas.md](gotchas.md). It also means two `git worktree` checkouts of one repo, sharing one `.git`
and one tracked `.claude/settings.json`, hold independent records and pin independently.

## `/reload-plugins` — bare by default, `--force` for the MCP-cache-invalidation case

**Verified against `code.claude.com/docs/en/discover-plugins`**: `/reload-plugins` refreshes skills,
agents, hooks, MCP, and LSP servers in-process. It does **not** cover monitors — per
`code.claude.com/docs/en/plugins-reference`, "monitors require a session restart". Recommend bare `/reload-plugins` by default; call out the restart requirement
only when an updated plugin ships a monitor.

**An install can now activate itself — but not the installs this skill issues.** As of Claude Code
2.1.221, an install started from the in-session `/plugin` interface reports its own activation state:
per `code.claude.com/docs/en/discover-plugins` (fetched 2026-08-10), the summary says either
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

`--force` is real (Claude Code ≥ 2.1.163), but scoped to one specific case: a plugin that provides an
MCP server whose tools aren't deferred by tool search invalidates the prompt cache on reload, and
`/reload-plugins` warns and does **not** apply the reload rather than eating that cost silently;
`--force` applies it anyway. Only suggest `--force` when the updated/installed component in this
sync's report actually ships such an MCP server (or the report already surfaced that warning) — never
recommend it by default alongside every reload, since it exists specifically to opt into a real token
cost the bare command declines to pay automatically.

## `userConfig` has no `enum` field

**Verified against the published plugin-manifest JSON Schema**: allowed `type` values are `string`,
`number`, `boolean`, `directory`, `file` — no `enum`. `install_new` ships as `type: string` with its
valid values (`ask`/`all`/`none`) documented in `description` and validated in prose by this skill,
not by the manifest schema.

## Renames are CC-native (≥ v2.1.193)

Claude Code rewrites a marketplace's `renames` map into installed/enabled state automatically at
session start (old id → new id; `null` means removal). This skill hard-codes no rename knowledge —
its only rename-adjacent behavior is that anything present in the current catalog but absent from
`installed_plugins.json` shows up as `missing_from_install`, which naturally covers a renamed
plugin's new id. `claude plugin prune` requires ≥ v2.1.121; renames mapping requires ≥ v2.1.193.

## `autoUpdate` is a background complement, not a substitute

Official-Anthropic marketplaces default `autoUpdate: true`; third-party and local-dev marketplaces
default it off (absent from `known_marketplaces.json`, not `false`). When on, Claude Code refreshes
marketplace data and bumps already-installed plugins once per session start, after a random delay of
up to ten minutes. This skill never mutates the setting — it only reports the marketplace's current
`autoUpdate` state and suggests enabling it when off, since it never overlaps with what this skill
covers (new-plugin install, `enabledPlugins` completeness, divergence detection/convergence,
deterministic on-demand execution).
