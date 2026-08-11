# Scope decisions, and where a finding goes next

Each decision below was open when the skill was specified. Each is recorded with the argument, so a
later reader can reopen it on evidence rather than taste.

## Skill, not a new plugin — and in `claude-ops`

**A skill.** The exploratory question ("what is in this install, and what of it is real?") is one
coordinated read-only pass, which is what a skill is for.

**In `claude-ops`, not `claude-config`.** `claude-config` states its own charter as
configuration-health for **a repo's** Claude Code configuration; its coordinator refuses any target
that is not the active project root, and it never edits user scope in any mode. This skill's subject
is machine-scope install state. `claude-ops` is "running Claude Code well over time", and already
reads `~/.claude/plugins/installed_plugins.json` and reasons about machine-scope semantics; this is
the missing sibling to `plugins` (fleet state) and `observability` (telemetry state).

**Not a delegate of `claude-config:audit-pass`.** That coordinator's target must resolve to the
active project root and is refused otherwise, so `~/.claude` can never be a valid target for it.
Three things are reused rather than reinvented: the `(check, claim, sites)` identity discipline, the
finding-suppression convention, and the rule that a run never writes into its own scan set.

**Not a new plugin.** One skill does not earn a manifest, README, changelog, marketplace entry, and
catalog row of its own. If it later grows hooks or a kill switch, that decision reopens.

## Report-only. No apply mode in v1

The strong prior from the source audit was that audit and apply must be separate. The most defensible
reading of "separate", for a first version, is that the write side does not ship at all.

Concretely: the engine never writes to, moves, or removes anything under the target root, and it is
the `audit` verb, whose contract in this marketplace is a read-only findings report.

The reason is not caution for its own sake. Safe deletion on this tree needs a live-handle preflight,
reparse-point and mount-point stops, snapshot revalidation between preview and apply, and
descriptor-relative removal. `/disk-hygiene:clean` already implements all of that, under review, with
a kill switch. Reimplementing any of it here would be strictly worse, and would put a deletion engine
behind an audit's evidence standards rather than a deletion engine's.

## Cross-platform, with one explicit seam

Everything is `os.walk` + `stat` + regex in Python 3.11+, and behaves identically on every platform:
inventory, surface classification, name-scheme classification, retention resolution, the deliberate-
state sweep, sampling.

**The seam is exactly one function**, `probe_pid()`, with a POSIX body (`os.kill(pid, 0)`) and a
Windows body (`OpenProcess`). No PowerShell anywhere. The root is resolved from `CLAUDE_CONFIG_DIR`
else `~/.claude`, and managed-settings paths are resolved per platform.

The seam fails safe: a probe that cannot run, or returns something unmapped, yields `unverified`.
**It never yields `dead`.** That is the trap from `name-schemes.md` encoded as a data value rather
than a warning, and it matches `disk-hygiene`'s existing `handle_state_unverified` vocabulary.

## A run never writes into its own scan set

`${CLAUDE_PLUGIN_DATA}` resolves to `~/.claude/plugins/data/<id>` — **inside** the tree being
scanned. A report written there would be counted, classified, and possibly reported as an unmanaged
leftover by the run that created it.

So: write the report outside the target root. If a destination inside it is unavoidable, pass it as
`--csv` and the engine adds it to its own exclusion set and records that under `self_excluded`.

## Where each finding goes

| Reading | Handoff |
|---|---|
| `product-managed-healthy` | Nothing to do. The only lever that shrinks it is lowering `cleanupPeriodDays` — a config change, not a deletion |
| `age-exceeds-window` | Investigate the sweep's unit for that path first. Never a deletion authorisation |
| `settings-unparsable-pauses-sweep` | Fix the JSON. Retention is stopped until you do. `/claude-config:audit` owns settings correctness |
| Home-root `~/.claude.json` growth | `claude project purge <path>` — the supported command. `--dry-run` previews |
| `deny-listed` | Stop. Read the ledger, diff against the stored baseline, and confirm with whoever ran the experiment |
| `keep` / secret-bearing | Nothing to do |
| `unclassified-report-only`, and you want it gone | `/disk-hygiene:clean` — the engine that owns exact-path deletion with a live-handle preflight |
| Permission-rule or settings-key findings | `/claude-config:audit`, `/claude-config:audit-permission-grants` |
| Which plugins are actually installed / at what scope | `/claude-ops:plugins audit` |

## Detect a deliberate state before classifying anything

The largest near-miss in the source audit was not a bad check. It was a correct check run against a
tree whose current state was **deliberate**: an experiment was live, and half the lanes were
diagnosing its independent variable as damage. The experiment's only revert store lived under
`plugins/data/`, a path a plugin-cleanup pass would plausibly prune.

So the ledger sweep runs **first**, and anything it finds deny-lists its subtree before a single
staleness verdict is produced.

Two calibrations, both learned by running it:

- **An experiment's self-record is not authoritative.** One `RESTORE.md` claimed "all 68 keys set
  false"; reality was 70 keys with one still true. Diff against the stored baseline copy.
- **Match on strong names everywhere, weak names only in the hotspot.** A first version globbed
  `manifest.json` and `*baseline*` across the whole tree and matched browser payloads, plugin-cache
  fixtures, and subagent directories — deny-listing most of the install and rendering the signal
  useless. Corroborating names now count only within three levels of `plugins/data/`, and vendored
  `plugins/cache` and `plugins/marketplaces` are skipped entirely.

A live worked example sits in this very repository: `AGENTS.md` and `CLAUDE.md` are **zero bytes** at
`main`, reset by commit `8b411824` as the independent variable of a deliberate bare-baseline
experiment. An empty instruction file reads as damage and is the point of the experiment. Recovering
their content from git history is the correct move; "restoring" them is not.

## What this skill deliberately does not do

- **No enablement verdict.** Enablement is not one file: it lives in several scopes, plugin-declared
  hooks live in each plugin's own manifest, direct-path invocations from `settings.json` bypass the
  plugin system entirely, and enablement is read at session start so a running session keeps what it
  loaded. Any single-file answer will confidently contradict reality. The engine emits
  `recent_writers` — behavioural evidence that something wrote to the tree — and leaves the verdict
  to `/claude-ops:plugins audit`.
- **No parsing of sibling-plugin state.** A plugin owns its own state. Those paths are inventoried by
  name, size, and mtime; nothing is opened and no owner is attributed from a directory name.
- **No rule dedupe or subsumption.** See `evidence-discipline.md` §4.
- **No deletion, ever.** See above.
