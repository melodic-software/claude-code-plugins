---
description: "Read-only audit of a Claude Code INSTALLATION directory — the machine-scope `~/.claude` tree plus `~/.claude.json` — inventorying every file, separating what the product's own retention sweep already manages from what nothing manages, resolving what each number in a filename actually means before any process-liveness check, and detecting a deliberate or mid-experiment state before classifying anything as stale. Reports; never deletes. When the bundled doctor skill resolves in your session, prefer it for the quick native health-and-fix pass; this skill for the deep read-only inventory. Use when: 'audit my .claude folder', 'what is in my ~/.claude', 'why is my Claude Code install so big', 'is anything stale in my Claude directory', 'does Claude Code clean up after itself', 'check cleanupPeriodDays', 'is this lock file dead', 'tidy my Claude Code install'. Not for: a repo's project-scope .claude config (use /claude-config:audit), or deleting anything (use /disk-hygiene:clean)."
argument-hint: "[root] — root defaults to $CLAUDE_CONFIG_DIR or ~/.claude; always pass --csv"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Audit a Claude Code install directory — what is there, what the product manages, what is stale
  cadence: weekly
---

## Purpose

Answers four questions about a Claude Code installation, and refuses to answer a fifth.

1. **What is actually here?** Every entry labelled automatically as an authored surface or a bulk
   tree, so a ~100k-file tree does not drown a ~150-file answer. Per-file rows live in the CSV.
2. **What does the product already manage?** Claude Code runs its own retention sweep. Recommending
   a manual prune of a path it owns generates churn, not space.
3. **For each number in a filename — what IS that number?** A liveness lookup against a TCP port or a
   shell `$$` returns a clean, confident, wrong "dead."
4. **Is this tree in a deliberate or experimental state?** If it is, "looks like decay" is the wrong
   reading of almost everything.

The fifth question — *so what should I delete?* — is deliberately not answered. This skill is
report-only and never writes to the target tree. Deletion belongs to `/disk-hygiene:clean`, and
shedding project state belongs to `claude project purge`.

## Scope boundary

| Question | Owner |
|---|---|
| Is this machine's Claude Code install directory healthy? | **this skill** |
| Are a repo's project-scope config FILES correct? | `/claude-config:audit` |
| Are permission grants portable and durable? | `/claude-config:audit-permission-grants` |
| Is the plugin fleet current, and at what scope? | `/claude-ops:plugins audit` |
| Delete a genuinely unmanaged leftover | `/disk-hygiene:clean` |

Full rationale for every scope decision, and where each finding hands off:
[reference/scope-and-handoffs.md](reference/scope-and-handoffs.md).

## Boundary — the bundled `doctor` skill

One native Claude Code surface asks a question that sounds like this skill's, and the two are
routinely conflated:

- **`doctor` (bundled skill, alias `checkup`)** — ships with Claude Code rather than as a
  marketplace plugin. It health-checks an installation and **offers to fix** what it finds:
  installation problems, unused extensions, duplicated or bloated memory files, slow hooks,
  updates, permissions. It also estimates what the skill listing costs in context. It is the one
  bundled skill `disableBundledSkills` does not remove; `DISABLE_DOCTOR_COMMAND=1` or a
  `skillOverrides` entry hides it instead.
- **This skill (marketplace plugin)** — the deep read-only inventory of the install tree: every
  file classified, product-managed retention separated from genuinely unmanaged state, filename
  schemes resolved before any liveness check, and a deliberate-or-experimental state detected
  before anything is called stale.

**Routing.** When `doctor` resolves in your session, prefer it for the quick health pass and for
anything you want fixed in place. Prefer this skill when the question is *what is actually in this
tree, and what does nothing manage* — the classification, the evidence tags, and the per-file CSV
have no native counterpart. Its sibling `/claude-ops:audit-performance` owns the timed
slowness-capture lane against the same native surface; that description is not repeated here.

**Mutation gate.** `doctor` mutates: fixing is its point. This skill's contract is report-only, so
never chain into a `doctor` fix on this skill's behalf — surface the finding, and let the user
invoke the fix themselves.

**Availability is never assumed.** Bundled surfaces are gated on settings and environment, plan,
platform, and host surface, so a session where `doctor` does not resolve is an ordinary session,
not a broken one. Nothing here depends on it being present: the read-only inventory is complete on
its own.

## Never read

`.credentials.json`, `daemon/control.key`, `daemon/pipe.key`, `ide/*.lock` (its body carries an
`authToken`), and the values inside `~/.claude.json`. These are inventory line-items — name, size,
mtime — and nothing more. **This rule is inherited by every subagent this skill dispatches; say so
explicitly in any prompt you fan out.**

The engine enforces it in its reader rather than at each call site, and its entire content-read
allowlist is three files: `settings.json`, `.last-cleanup`, `plugins/.last_inuse_sweep`. Everything
else in the tree — including every file a sibling plugin deposited — is stat-only.

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-install-state/scripts/install_state.py" \
  --samples 3 --csv ./claude-install-listing.csv > ./claude-install-report.json
```

Write both artifacts **outside** the target root. `${CLAUDE_PLUGIN_DATA}` resolves to
`~/.claude/plugins/data/<id>`, which is *inside* the tree being scanned; a report written there gets
counted and classified by the run that created it. If a destination inside the root is unavoidable,
pass it as `--csv` and the engine excludes it from its own scan set and records that under
`self_excluded`.

**Always pass `--csv`.** It is the only artifact carrying per-file rows at all. The JSON is a
summary: one line per top-level entry, never a file listing. Without `--csv` the run wrote no
per-file listing anywhere, `csv.path` is `null`, and the report must not be described as covering
every file. `--authored-threshold` decides only which entries the JSON *labels* `listing:
"per-file"` (small enough to be a hand-authored surface worth reading file by file in the CSV)
versus `listing: "rolled-up"`; it embeds no per-file rows either way and never shrinks the CSV.

Useful flags: `--root <path>` (else `$CLAUDE_CONFIG_DIR`, else `~/.claude`) · `--samples N` (default
2; use 3+ on a busy machine) · `--authored-threshold N` (default 200). Python 3.11+ is the only
requirement — no PowerShell, no third-party packages.

## Phase 1 — read the deliberate-state result FIRST

Before reading any other part of the report, read `deliberate_state` and `deny_roots`.

A non-empty `deliberate_state` means a revert ledger (`RESTORE.md`, `PLAYBOOK.md`, `restore*.py`, or
a `manifest.json` / baseline shallow under `plugins/data/`) was found. Its directory subtree is
deny-listed and every entry under it reports `deny-listed` instead of a staleness verdict.

Treat a deny-listed subtree as the possible **sole copy** of somebody's revert path. Do not propose
anything for it. Check the ledger's `age_days` — live versus abandoned changes everything — and
**diff against the stored baseline rather than believing the ledger's own summary**; one such file
claimed "all 68 keys set false" when the truth was 70 keys with one still true.

## Phase 2 — retention, before any staleness claim

Read `retention`. Report `effective_days` together with its `effective_evidence`: `measured` when a
file supplied it, `documented-default` when nothing did and upstream's 30-day default applies.

The highest-severity finding this skill produces lives here: **an unparsable `settings.json` pauses
the retention sweep**, so nothing is being cleaned until it is fixed. If
`settings-unparsable-pauses-sweep` appears in `retention.findings`, lead the report with it and
treat every staleness reading below as suspect.

`.last-cleanup` advancing is direct evidence the sweep ran. If it advanced *during* your scan, say
so — the tree was not quiesced.

## Phase 3 — read the entries

Each entry carries `surface`, a `reading` with its own `evidence`, and `file_count_sampled` as
`{min, max, n}`.

| Reading | What it means |
|---|---|
| `product-managed-healthy` | Every file is inside the retention window. Do not hand-prune |
| `age-exceeds-window` | `evidence: inferred`. Some mtimes exceed the window — a measurement, not proof the sweep is failing. Read the `why`, which names the sweep's documented unit for that path |
| `keep` | Documented as retained, authored by you, session-scoped, or secret-bearing |
| `unclassified-report-only` | `evidence: no-upstream-row`. No documentation covers it, so no retention claim is available in either direction |
| `deny-listed` | A revert ledger is in this subtree. Nothing here is a candidate |

`age-exceeds-window` is the reading most likely to be misread. `file-history/` retains by **checkpoint
count** and keeps each file's first snapshot regardless of age; `subagents/` and `tool-results/` age
out with their parent transcript; `session-env/`, `tasks/` and `debug/` are per-session. Old mtimes
on those paths are the documented behaviour.
See [reference/surfaces.md](reference/surfaces.md).

## Phase 4 — numeric names and liveness

`numeric_names` carries counts by `(meaning, liveness)`, every PID-typed row, and a sample of names
whose scheme is unrecognised.

Everything that is not `pid` reads `not_applicable` **by construction** — not because a lookup
missed. That distinction is the whole point:

- `ide/<n>.lock` — the number is a **listening TCP port**. The real PID is in the body, which is not
  opened. One audit came within a step of deleting a live VS Code integration on this exact error.
- `rate-limit-guard/*.tmp.<n>` — MSYS2 `$$`, not an OS PID. Judge by age and zero length.
- `shell-snapshots/...`, `backups/...` — epoch milliseconds. No PID anywhere in the name.
- unrecognised — reported as `unknown`. A scheme the table has never seen fails closed.

`alive` is a measurement about *a* process with that id; PIDs get reused, so "therefore this file is
in use" is a further inference. A probe that could not run reports `unverified`, **never** `dead`.
See [reference/name-schemes.md](reference/name-schemes.md).

## Phase 5 — home-root state

`~/.claude.json` lives in the home directory, not under `~/.claude`, and **no value of
`cleanupPeriodDays` touches it**. Report its size and mtime; never its values (MCP server configs can
carry tokens). The supported remedy for its growth is `claude project purge <path>` — it prints the
full plan and confirms before removing anything, and `--dry-run` previews it.

`.claude.json.tmp.<n>.<hash>` siblings are failed atomic-write remnants whose number *looks* like a
PID and has never been verified, so the engine marks it `unknown` and attempts no lookup.

## Phase 6 — report

Reproduce every claim with the `evidence` tag the engine attached. Do not paraphrase a tagged claim
into an untagged sentence — that is precisely the step that turns an inference into an apparent
observation for the next reader.

Two output rules that are not negotiable:

- **Ranges, never a central tendency, for anything time-varying.** `411–413 files, n=3`, never
  `~412`. If `file_count_sampled` carries `unanimous_small_n_on_volatile_path`, re-run with more
  samples or carry the flag into the report.
- **Reference the CSV, and check `csv.rows` against `totals.files` before claiming completeness.**
  The CSV is the artifact in which "every file" literally exists; the JSON summary is not. Summarise
  in chat, cite the CSV path and its row count, and never silently drop 99% of the tree.

State that the tree was live (`quiesced: false`). Counts drift while a scan runs, and any orphan
count keyed on sessions carries a margin of error, because a session whose record vanished mid-run is
*unknown*, not *dead*.

If you fan this out across agents, keep an explicit cross-review stage: in the audit this skill came
from, five errors were made and five were caught, **none by the agent that made it**. Parallelism buys
coverage, not correctness. Verify a peer's claim against your own evidence before adopting it, and
record a disagreement nothing depends on as unresolved rather than settling it silently.
See [reference/evidence-discipline.md](reference/evidence-discipline.md).

## Verifying an upstream claim

Any claim about what Claude Code itself does must come from the raw markdown endpoint — `curl -sSL`
`https://code.claude.com/docs/en/claude-directory.md` to a file, then read the file. A summarizing
fetch returns a small model's answer *about* the page, so **absence from it is not evidence of
absence**, and no destructive conclusion may rest on one.
See [reference/evidence-discipline.md](reference/evidence-discipline.md) §6.

## Gotchas

- **A number in a filename is not a PID until proven otherwise.** The most expensive error in this
  problem space, and the reason the liveness gate is code rather than advice.
- **`enabledPlugins: false` does not mean disabled.** Enablement spans several scopes, plugin hooks
  live in each plugin's own manifest, direct-path invocations from `settings.json` bypass the plugin
  system, and enablement is read at session start. This skill emits `recent_writers` as behavioural
  evidence and tell the user to run `/claude-ops:plugins audit` for the verdict.
- **`backups/` cannot be pruned meaningfully.** It is a rotating buffer, retained at 5 and refilling
  in about 90 seconds. Any per-file finding about it is stale before it is written.
- **An empty directory may be deliberate.** An empty `skills/` can be an experiment's independent
  variable, not decay. Phase 1 exists for this.
- **`commands/`, `todos/`, `statsig/`, `logs/` being absent is good news.** It is positive evidence
  the sweep completed, including its remove-the-empty-directory step.
- **The "safe, no judgment required" tier is the one most in need of an independent check** — the one
  operation a prior audit called mechanically provable was wrong, because a case-insensitive
  comparer collapsed three distinct deny rules. This skill's deny matching is case-sensitive and
  tested; it encodes no dedupe or subsumption logic at all.
