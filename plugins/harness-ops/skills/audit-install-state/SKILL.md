---
description: "Read-only audit of `~/.claude` and `~/.claude.json`: the deep inventory of unmanaged files. Use when: 'audit my .claude folder', 'what is in my ~/.claude', 'why is my Claude Code install so big', 'is anything stale in my Claude directory', 'does Claude Code clean up after itself', 'check cleanupPeriodDays', 'is this lock file dead', 'tidy my Claude Code install'. Deleting: /disk-hygiene:clean."
argument-hint: "[unattended] [root]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Audit a Claude Code install directory. What is there, what the product manages, what is stale
  cadence: weekly
---

**Arguments.** `[unattended] [root]`. `root` is the tree to audit and reaches the engine as `--root`; it defaults to `$CLAUDE_CONFIG_DIR`, else `~/.claude`. Always pass `--csv` to the engine. The token `unattended` is consumed by the skill, is never passed to the engine script and never read as a root path; under it the suggestion is recorded in the report instead of asked.

## Purpose

Answers four questions about a Claude Code installation, and refuses to answer a fifth.

- **What is actually here?** Every entry labeled as an authored surface or a bulk tree, so a
  ~100k-file tree does not drown a ~150-file answer. Per-file rows live in the CSV.
- **What does the product already manage?** Recommending a manual prune of a path the retention
  sweep owns generates churn, not space.
- **For each number in a filename, what IS that number?** A liveness lookup against a TCP port or
  a shell `$$` returns a clean, confident, wrong "dead."
- **Is this tree in a deliberate or experimental state?** If it is, "looks like decay" is the wrong
  reading of almost everything.

The fifth question, *so what should I delete?*, is deliberately not answered. This skill is
report-only and never writes to the target tree. Deletion belongs to `/disk-hygiene:clean`, and
shedding project state belongs to `claude purge`.

## Scope boundary

| Question | Owner |
|---|---|
| Is this machine's Claude Code install directory healthy? | **this skill** |
| Are a repo's project-scope config FILES correct? | `/harness-config:audit` |
| Are permission grants portable and durable? | `/harness-config:audit-permission-grants` |
| Is the plugin fleet current, and at what scope? | `/harness-ops:plugins audit` |
| Delete a genuinely unmanaged leftover | `/disk-hygiene:clean` |

Rationale and handoffs: [reference/scope-and-handoffs.md](reference/scope-and-handoffs.md).

## Boundary, the bundled `doctor` skill

One native Claude Code surface asks a question that sounds like this skill's, and the two are
routinely conflated:

- **`doctor` (bundled skill, alias `checkup`)**: health-checks an installation and **offers to
  fix** what it finds:
  installation problems, unused extensions, duplicated or bloated memory files, slow hooks,
  updates, permissions. It also estimates what the skill listing costs in context. It is the one
  bundled skill `disableBundledSkills` does not remove; `DISABLE_DOCTOR_COMMAND=1` or a
  `skillOverrides` entry hides it instead. Basis for all four: the `/doctor` row on
  <https://code.claude.com/docs/en/commands> names the `/checkup` alias and the fix-in-place
  behavior, and <https://code.claude.com/docs/en/skills> carries the `disableBundledSkills`
  exemption and both hiding mechanisms. Verified 2026-09-06 against Claude Code 2.1.263 and those
  two pages as fetched that day. Recheck when either page stops carrying the row, or a release note
  names bundled-skill gating or the `doctor` surface.
- **This skill (marketplace plugin)**, the deep read-only inventory of the install tree: every
  file classified, product-managed retention separated from genuinely unmanaged state, filename
  schemes resolved before any liveness check, and a deliberate-or-experimental state detected
  before anything is called stale.

**Routing.** Person-invoked `/doctor` is offered at session end (Phase 6); this section records surface facts only. Its sibling `/harness-ops:audit-performance` owns the timed slowness-capture lane against the same native surface.

**Mutation gate.** `doctor` mutates: fixing is its point. This skill's contract is report-only, so
never chain into a `doctor` fix on this skill's behalf. Surface the finding, and let the user
invoke the fix themselves.

**Availability is never assumed.** Bundled surfaces are gated on settings and environment, plan,
platform, and host surface, so a session where `doctor` does not resolve is an ordinary session,
not a broken one. Nothing here depends on it being present: the read-only inventory is complete on
its own.

## Never read

`.credentials.json`, `daemon/control.key`, `daemon/pipe.key`, `ide/*.lock` (its body carries an
`authToken`), and the values inside `~/.claude.json`. These are inventory line-items: name, size,
mtime, and nothing more. **Every subagent this skill dispatches inherits this rule; say so
explicitly in any prompt you fan out.** The engine enforces it in its reader, and its whole
content-read allowlist is `settings.json`, `.last-cleanup`, `plugins/.last_inuse_sweep`,
`plugins/installed_plugins.json` and the `plugins/cache/*/*/*/.orphaned_at` markers; each entry
it read by content carries `content_read: true` with the paths opened. Everything else is stat-only.

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-install-state/scripts/install_state.py" \
  --samples 3 --csv ./claude-install-listing.csv --versions-out ./claude-install-versions.json \
  > ./claude-install-report.json
```

Write both artifacts **outside** the target root (`${CLAUDE_PLUGIN_DATA}` resolves *inside* it and
would be counted by the run that wrote it; in a cloud session use the session scratchpad). If a
destination inside the root is unavoidable, pass it as `--csv` and the engine excludes it under
`self_excluded`. **Always pass `--csv`**: it is the only artifact carrying per-file rows, and
without it `csv.path` is `null` and the run must not be described as covering every file.
`--authored-threshold` only decides which entries the JSON *labels* `per-file` versus `rolled-up`.
`--versions-out <path>` writes the complete `unreferenced_versions` list (Phase 3) and is excluded
the same way. Other flags: `--root <path>` (else `$CLAUDE_CONFIG_DIR`, else `~/.claude`), `--samples N` (default
2; use 3+ on a busy machine). Python 3.11+ is the only requirement. The header records
`engine_version` and the exact `invocation`, so a report reproduces from itself.

## Phase 0. Whose tree is this?

Read `environment` first. `tree_verdict` is `remote`, `local`, or `indeterminate`, and it is a
label: no staleness verdict depends on it. A `remote` tree belongs to a cloud-session container,
not the operator's workstation, so open the report with that sentence; a three-minute-old container
reads as healthy and would otherwise be reported as someone's machine. The verdict rests on tree
signals, each with its own evidence tag; the process-level `CLAUDE_CODE_REMOTE` variable sits under
`session_context` and never decides the tree alone, because `--root` can point anywhere. Report
`indeterminate` as such, never as `remote`.

## Phase 1. Deliberate state, before any staleness reading

Then read `deliberate_state` and `deny_roots`. A non-empty `deliberate_state` means a revert
ledger (`RESTORE.md`, `PLAYBOOK.md`, `restore*.py`, or a `manifest.json` / baseline shallow under
`plugins/data/`) was found; its subtree reports `deny-listed` instead of a verdict. Treat it as the
possible **sole copy** of somebody's revert path: propose nothing for it, check `age_days`, and
**diff against the stored baseline rather than believing the ledger's own summary**.

## Phase 2. Retention, before any staleness claim

Read `retention`. Report `effective_days` with its `effective_evidence`: `measured` when a file
supplied it, `documented-default` when upstream's 30-day default applies. The highest-severity
finding lives here: **an unparsable user `settings.json` pauses the retention sweep and warns in
`/status`**. If `settings-unparsable-pauses-sweep` appears in `retention.findings`, lead with it
and treat every staleness reading below as suspect. If
`managed-settings-unparsable-refuses-start` appears, Claude Code refuses to start (exit 1) and
names the managed source; that is not a paused sweep.

`.last-cleanup` is read by the engine and its timestamp is observed to advance when the sweep runs,
but no upstream page names the file, so `sentinels` carries it as `observed-undocumented` with an
unknown cadence. Report an advance as an observation, not a documented watermark; if it advanced
*during* your scan, say so, the tree was not quiesced.

## Phase 3. Entries and size

Each entry carries `surface`, a `reading` with its own `evidence`, and `file_count_sampled` as
`{min, max, n}`.

| Reading | What it means |
|---|---|
| `product-managed-healthy` | Every file is inside the retention window. Do not hand-prune |
| `age-exceeds-window` | `evidence: inferred`. Some mtimes exceed the window, a measurement, not proof the sweep is failing; the `why` names the sweep's documented unit |
| `keep` | Documented as retained, authored by you, session-scoped, or secret-bearing |
| `unclassified-report-only` | `evidence: no-upstream-row`. No documentation covers it either way |
| `deny-listed` | A revert ledger is in this subtree. Nothing here is a candidate |

`age-exceeds-window` is the reading most likely to be misread; several swept paths retain by a
unit other than the file. Per-path rules: [reference/surfaces.md](reference/surfaces.md). For "why
is my install so big", read `largest_subtrees` (top directories by measured bytes) and
`node_modules` (bytes the product installed into the cache's version directories, upstream basis in
its `why`; `node_modules` elsewhere under `plugins/` is measured apart and attributed to nobody).

`unreferenced_versions` lists each `plugins/cache/<marketplace>/<plugin>/<version>/` directory that
no `installPath` in `plugins/installed_plugins.json` references, largest first, with `bytes`, the
`.orphaned_at` marker's `orphaned_at` and `marker_age_days`, and `past_sweep_window` (true at 14
days or more). A directory with no marker has `orphaned_at: null` and is never past the window: the
sweep is documented as starting from the marker, so it has no removal date. The report keeps only
the 25 largest, so the field stops growing with the version count (each row repeats its path, so
very long directory names still make rows large).
`unreferenced_versions_total` is the full count and `unreferenced_versions_truncated` is true when
the list was cut; never report the list length as the total. `--versions-out` writes the complete
list as a JSON file, and `unreferenced_versions_file` then records its `path` and `count`. When the
registry is missing, unparsable, or belongs to another root, the list is empty and
`unreferenced_versions_note` says why; an empty list then means "not checked", not "none". The list
is a report, not a deletion list, and removing anything stays with `/disk-hygiene:clean`. That
skill treats the cache as managed state and leaves version directories to the product's own sweep;
do not remove them by hand.

A running session keeps the plugin version it loaded, so hook, guard, and denial messages can name
the previous version's path after an update. Restart the session to pick up the new version; the
old path is expected, not a defect.

Basis for the 14-day window, the marker, and the running-session behavior: the plugin caching
section of <https://code.claude.com/docs/en/plugins/loading> ("removes that directory in a
background cleanup 14 days later, so a session that already loaded the old version keeps running").
Verified 2026-09-29 against Claude Code 2.1.285 and that page as fetched that day. Recheck when the
page changes the window, the marker name, or the sweep condition, or a release note names plugin
cache cleanup; then update `ORPHAN_SWEEP_DAYS` in `lib/plugin_cache_versions.py` and its byte-identical copy in
`disk-hygiene`.

## Phase 4. Numeric names and liveness

`numeric_names` carries counts by `(meaning, liveness)`, every PID-typed group, and the unknown
sample grouped by name shape with a per-directory histogram. Everything that is not `pid` reads
`not_applicable` **by construction**, not because a lookup missed: `ide/<n>.lock` is a TCP port,
`rate-limit-guard/*.tmp.<n>` a shell `$$`, snapshot and backup numbers are epoch milliseconds, and
an unrecognized scheme fails closed as `unknown`. A `pid_typed` group marked `self_held` belongs to
the session running the audit: evidence about the auditor, not the tree; `self_pids_walk:
parent-only` means that ancestry could not be walked, so an `alive` group may still be this session.
`alive` measures *a* process with that id; "therefore in use" is an inference. A probe that could
not run reports `unverified`, **never** `dead`. Schemes: [reference/name-schemes.md](reference/name-schemes.md).

## Phase 5. Home-root state

`~/.claude.json` lives in the home directory, and **no value of `cleanupPeriodDays` touches it**.
Report its size and mtime, never its values; the supported remedy for its growth is `claude project
purge <path>`, which confirms before removing anything and supports `--dry-run`.
`.claude.json.tmp.<n>.<hash>` siblings are failed atomic-write remnants whose number is unverified,
so the engine marks it `unknown` and attempts no lookup.

## Phase 6. Report

Reproduce every claim with the `evidence` tag the engine attached; an untagged paraphrase turns an
inference into an apparent observation. Ranges, never a central tendency, for anything
time-varying: `411–413 files, n=3`, never `~412`, and carry any `unanimous_small_n_on_volatile_path`
flag into the report. Check `csv.rows` against `totals.files` before claiming completeness, cite the
CSV path and row count, and state that the tree was live (`quiesced: false`). Fan-out cross-review
and the upstream-claim rule (raw markdown only; absence from a summary is not evidence of absence):
[reference/evidence-discipline.md](reference/evidence-discipline.md).

### Person-invoked `/doctor` suggestion

Relay the sentence below to the user and do not run `/doctor` yourself: it is reserved for the person to run.

If /doctor is available in your session (gate basis: **Boundary, the bundled `doctor` skill** above), run it for the quick health-and-fix pass this read-only inventory does not perform.

**`unattended`:** record this suggestion in the report's final section; do not ask.

## Next

/disk-hygiene:clean
Consumes a genuinely unmanaged leftover this report surfaced; the audit itself never deletes.

## Gotchas

- **A number in a filename is not a PID until proven otherwise.** The most expensive error in this
  problem space, and the reason the liveness gate is code rather than advice.
- **`enabledPlugins: false` does not mean disabled.** Enablement spans several scopes and is read at
  session start; `recent_writers` is behavioral evidence, `/harness-ops:plugins audit` the verdict.
- **An empty directory may be deliberate**, and **a cloud-session tree is the common experimental
  state.** Phases 0 and 1 exist so neither is graded as decay.
- **`commands/`, `todos/`, `statsig/`, `logs/` being absent is good news.** It is positive evidence
  the sweep completed, including its remove-the-empty-directory step.
- **The "safe, no judgment required" tier most needs an independent check.** A case-insensitive
  comparer collapses deny rules that differ only by case; this skill's deny matching is
  case-sensitive and tested, and it encodes no dedupe or subsumption logic at all.
