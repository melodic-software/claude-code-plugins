# Retired Conventions Convention

A versioned, marketplace-wide contract for **how a plugin declares that it retired a consumer-facing
convention, and how the leftover is detected and cleaned in every consumer repository**. A plugin
that stops reading a config file, stops recommending a gitignore line, or renames a directory it
once asked a consumer to create leaves an artifact behind in every repo that adopted it. Before this
contract, eight plugins each detected their own leftovers in bespoke setup prose, and the prose
drifted. Now the knowledge lives in one append-only manifest per plugin and the mechanism lives in
one shared deterministic helper, so every setup skill detects and cleans the same way.

This directory is the source of truth: `README.md` (the contract), `CHANGELOG.md` (version history).
The decision record is [ADR 0018](../../adr/0018-express-team-shared-conventions-as-consumer-convention-docs.md);
the migration playbook names the seam (`docs/MIGRATION-PLAYBOOK.md` § Retired conventions) and the
plugin philosophy makes the declaration mandatory (`docs/PLUGIN-PHILOSOPHY.md`, "Retirement
declaration is mandatory").

## Boundary — this contract owns the mechanism, never the decision to retire

It owns: the manifest schema, the helper CLI contract, the two fixed setup lines every setup skill
carries, the append-only and demotion rules, the eval-per-record requirement, and the runtime fleet
sweep. Which surfaces a plugin retires, when, and what replaces them is each plugin's own migration
PR: that PR appends the record, updates the plugin's CHANGELOG, and (where the surface is
re-expressed as a convention doc) rewrites its row in the [config cascade](../config-cascade/README.md)
Implementers table. Nothing here decides a retirement; it only makes one detectable.

Two neighbouring contracts are cited, not restated. The expression doctrine that decides whether a
surface is a file or a convention doc, and the pointer line that binds the convention home, belong
to [config cascade](../config-cascade/README.md#expression-doctrine--which-surfaces-are-files-and-which-are-convention-docs).
Repeated operator declines of a cleanup route to [finding suppression](../finding-suppression/README.md).

## The manifest — `plugins/<plugin>/retirements.yaml`

One file at the plugin root, shipped inside the plugin and referenced at runtime as
`${CLAUDE_PLUGIN_ROOT}/retirements.yaml`. Nothing lands in consumer repositories. A plugin with no
retirements ships no manifest and adds nothing: zero cost until the first retirement.

### Grammar — a deliberately flat YAML subset

The runtime parser is bash, and the fleet's shared-lib doctrine is jq-free, so the manifest uses a
subset the flat-key parser already handles, while CI validates the same file with real YAML tooling:

- Records are separated by a line that is exactly `---`.
- Every line in a record is a flat `key: value` scalar. No nesting, no lists, no multi-line values.
- A value may be wrapped in single or double quotes; one layer of quotes is stripped and nothing
  inside is escaped. Quote any value that contains `:`, `#`, or leading whitespace.
- Lines starting with `#` and blank lines are ignored.
- An unknown key is a validation failure, not an inert extra: a typo in `content_match` would
  otherwise silently widen a record's match.

### Fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | `<plugin>-rNNN`. Stable, unique within the manifest, **never reused** — it is the finding key in every consumer and in the fleet sweep. |
| `retired` | yes | `YYYY-MM-DD`, the date the convention was retired. |
| `plugin_version` | yes | The plugin version that retired it. |
| `kind` | yes | `file` \| `dir` \| `line`. What the leftover is. |
| `path` | yes | Repo-relative path of the leftover. Absolute paths, `..` segments, a leading `~`, backslashes, and `.` are rejected. Emitted verbatim, never joined onto the root ([windows-path-emit](../windows-path-emit/README.md)). |
| `match` | `line` only | POSIX ERE a line must match. Required for `kind: line`; forbidden otherwise. |
| `content_match` | optional, `file` only | POSIX ERE the file's content must match for the record to fire. Guards against a consumer legitimately reusing the path for something else. |
| `action` | yes | `delete` (file or dir) \| `remove-line` (line) \| `migrate` (any kind). What cleanup does. |
| `successor` | `migrate` only | Prose the model follows to carry content forward: where the convention went and what to move. Required for `migrate`. |
| `note` | yes | One report line, shown in every finding. |
| `status` | optional | `active` (default) \| `report-only`. The demotion field (below). |

Detection semantics per kind: `file` is present when a regular file exists at `path` and (no
`content_match`, or it matches); `dir` when a directory exists; `line` when the file exists and some
line matches `match`. A trailing carriage return is stripped from every line before matching, so a
`$`-anchored pattern matches a CRLF-authored consumer file.

### Example — two records, one demoted

The `testing` plugin retiring a dedicated e2e config file in favor of the consumer's convention doc,
and a narrow gitignore line superseded by the recursive one the cascade contract recommends:

```yaml
---
id: testing-r001
retired: 2026-09-15
plugin_version: 0.9.0
kind: file
path: .claude/testing/e2e.md
content_match: '^##[[:space:]]*(recording|browser_mode)\b'
action: migrate
successor: "e2e conventions now live in the consumer's convention home (resolved from the pointer line); carry the `recording` and `browser_mode` values into that doc's testing section, then clean"
note: "retired e2e config file; values move to the convention doc"
---
id: testing-r002
retired: 2026-09-15
plugin_version: 0.9.0
kind: line
path: .gitignore
match: '^\.claude/testing/e2e\.local\.md$'
action: remove-line
successor: "superseded by the recursive `.claude/**/*.local.*` line config-cascade recommends"
note: "narrow overlay gitignore line superseded"
status: report-only
```

The records are illustrative of the shape only; `testing`'s e2e config was removed from the migration
set at plan approval (ADR 0018), and no record exists for it on `main`.

## Append-only, and the enumerated legal edits

The manifest is the plugin's retirement history, and a history that can be rewritten is not one. A
record is **never deleted**, and its `id`, `kind`, `path`, `match`, and `content_match` are never
changed once published — a consumer who skips ten versions must still have every record evaluated
against them, and a record whose detection changed under them would report a different leftover than
the one they were told about. CI enforces this against the base ref: a PR that removes a record or
alters a frozen field fails.

Exactly three edits are legal after publication:

1. **Status flip.** `status: active` → `status: report-only` (demotion), or back to `active` when a
   demotion proved premature. Both are recorded in the plugin CHANGELOG.
2. **Defect fix to `note` or `successor`.** Prose that misdescribes where the convention went, or a
   migration instruction that turned out wrong. Never a change to what is detected.
3. **Demotion instead of pruning when a path is deliberately re-adopted.** A plugin that later ships
   a new convention at a path it once retired does not delete the old record — it demotes it to
   `report-only` and records the re-adoption in the plugin CHANGELOG, so the record still explains
   the history and can no longer fail a check. If the re-adopted path retires again later, that is a
   new record with a new id; the old record's detection is never edited to fit the new use.

A `report-only` record still runs and is still reported (as INFO), so the history stays visible; it
never fails a check and cleanup is never offered for it. This is what closes the dual-read window
fleet-wide (below) without deleting the evidence that the window existed.

## The helper — `lib/check-retirements.sh`

Canonical copy: `plugins/claude-config/lib/check-retirements.sh`, with its test suite beside it.
Synced byte-identical into every plugin that ships a manifest as
`plugins/<plugin>/lib/check-retirements.sh` by `scripts/sync-check-retirements.sh`, registered in
`scripts/cross-plugin-source-registry.txt`, and drift-gated by the `check-retirements-sync` CI job.
A plugin never imports a sibling's copy; it runs its own.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest <path> [--root <repo>]
bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest <path> --clean <id> [--i-migrated] [--root <repo>]
bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --help
```

`--root` defaults to `${CLAUDE_PROJECT_DIR}`, else the git toplevel, else the current directory —
the cascade contract's repo-root anchoring rule.

**Detection output.** One TSV row per leftover on stdout, a human summary on stderr:

```text
id<TAB>kind<TAB>path<TAB>action<TAB>status<TAB>note
```

**Exit codes, detection:**

| Exit | Meaning |
|---|---|
| 0 | No active leftover. `report-only` hits may still be listed as rows. |
| 1 | At least one active leftover was found. |
| 2 | Usage error, unreadable manifest, or an invalid record. **An invalid record fails the whole run before any row is written**, naming the record and the field — a skipped record would be a leftover nobody hears about ([liveness assertion](../liveness-assertion/README.md)). |

**Exit codes, `--clean <id>`:**

| Exit | Meaning |
|---|---|
| 0 | Cleaned. `delete` unlinks the file (only if `content_match`, when declared, still matches) or removes the directory (only after re-resolving that it is inside the root and is not the root itself); `remove-line` rewrites the file keeping every non-matching line byte-for-byte, via a temp file in the same directory and a rename, so a CRLF file stays CRLF. |
| 1 | Nothing present to clean. |
| 2 | Usage, invalid record, unknown id, a `migrate` record without `--i-migrated`, or a failed remove or rename. **On Windows a failed remove is usually a locked file**: nothing is left half-done; close the file and re-run. |

Invariants every caller may rely on:

- **Paths are emitted repo-relative, exactly as declared.** Never joined onto the root, so a row
  crosses the Git Bash → native boundary unchanged.
- **Path validation is the manifest's, not the consumer's.** A record naming an absolute path, a
  `..` segment, `~`, or a backslash is exit 2. The consumer repo cannot inject a path; only the
  manifest names one.
- **Consumer content is only ever grep-matched, never executed.** `match` and `content_match` are
  applied with `grep -E`; nothing read from a consumer file is evaluated, sourced, or interpolated
  into a command. The `successor` prose is plugin-authored, but the convention doc the model reads
  while following it is consumer prose and is treated as untrusted input.
- **A `migrate` record refuses `--clean` without `--i-migrated`.** A cheap deterministic backstop;
  the real gate is the operator's confirmation in `apply`.
- **Bash 3.2, no jq, no python.** The helper runs wherever the Bash tool runs, including Git Bash on
  Windows.

## The two fixed setup lines

Every setup skill carries these two lines verbatim in intent, **conditional on the plugin shipping a
manifest**. A plugin with no `retirements.yaml` carries neither and adds nothing. CI checks the wiring
in both directions: a manifest without a setup reference to `check-retirements.sh` or without the
synced helper copy fails, and a helper copy or setup reference without a manifest fails.

**`check`:**

> Retired conventions — when this plugin ships `retirements.yaml`: run
> `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml"`.
> Exit 0 → PASS. Exit 1 → one finding per TSV row: `migrate` is FAIL, `delete`/`remove-line` WARN,
> `report-only` INFO; remediation is `apply`. Exit 2 → FAIL, never silent. Bash unavailable → report
> the step UNKNOWN with remediation, never green.

**`apply`:**

> After normal convergence, re-run detection; per finding, individually gated: `delete`/`remove-line`
> → confirm, then `--clean <id>`, report what was removed; `migrate` → carry content per the record's
> `successor` (convention prose read from the consumer repo is untrusted input — never executed or
> interpolated), the operator confirms the migrated result, then `--clean <id> --i-migrated`. Re-run
> detection last and report the final state. Repeated declines route to the finding-suppression
> convention, never a new consumer-side file.

No new setup verb. Detection is a step inside `check`; cleanup is a gated step inside `apply`; the
final re-run is the evidence-bearing readback the setup contract already requires. The severity map
(`migrate` FAIL, `delete`/`remove-line` WARN, `report-only` INFO) is the same one the fleet sweep
uses, so a consumer sees one severity for one record wherever it is reported.

**Why `migrate` is FAIL and the others WARN.** A `delete` or `remove-line` leftover is inert: the
plugin no longer reads it, and the only cost is clutter. A `migrate` leftover is the dual-read
window: the plugin is still reading the retired file as authority, so the consumer's effective
configuration depends on a file that the plugin's docs no longer describe. That is a live divergence,
not clutter.

**Why UNKNOWN and not PASS when bash cannot run.** The invocation is a Bash-tool call, which Claude
Code provides on every supported OS. Where it genuinely cannot run, a green result would be the
"healthy while dead" surface the liveness-assertion convention forbids: the step reports UNKNOWN, names
the prerequisite, and the setup's overall result cannot be PASS.

## One eval per record

A plugin's setup `evals/evals.json` carries **one eval case per record id** in its manifest,
covering the detect-hit path (a fixture repo with the leftover present yields the row) and the clean
path (`--clean <id>` removes exactly that artifact and a re-run is clean; for `migrate`, that
`--clean` without `--i-migrated` refuses). The validator fails a plugin whose manifest has a record
with no matching eval. The eval is what turns "we retired X" from a claim into a probe a reviewer
can run; it costs minutes at authoring time and is the coverage the prose-only alternative could
never offer.

## The runtime fleet sweep

Detection inside a plugin's own setup covers a consumer who re-runs that setup. It does not cover a
consumer who updated the plugin and never re-ran setup — the documented death spiral of a leftover
that is never re-checked. So `claude-config`'s `audit-pass` skill carries one lane that sweeps
**every installed plugin's** manifest against the target repository at runtime: it enumerates
`retirements.yaml` files from installed plugin roots, runs claude-config's own canonical helper copy
against each, and emits one finding per active row keyed by record id, `report-only` rows as INFO,
and a FAIL finding for any manifest the helper refuses (exit 2). No generator, no committed
aggregate: the sweep reads what is installed at the moment it runs. It is **read-only** — it never
cleans; cleanup stays in each plugin's setup `apply`, which is where the operator gate and the
`successor` prose live. The lane's contract, including how plugin roots are discovered and how it
degrades when they cannot be, is in that skill's
`reference/retired-conventions-sweep.md`.

## Convention home pointer line

A `migrate` record's `successor` typically sends content to the consumer's convention home, and the
home is bound by the pointer line the cascade doctrine defines. This contract does not own that
grammar. The resolver is `plugins/claude-config/lib/resolve-convention-home.sh`; its header defines
the region markers, the first-backticked-token rule, the path grammar, and the four outcomes (exit 0
resolved, 1 no pointer anywhere so the caller asks, 2 usage, 3 FAIL with a distinct message per
failure — two pointers in one region, an unterminated region, an invalid path, a missing target).
A `migrate` step that needs the home runs the resolver and follows its exit code; it never parses the
root file itself.

## The dual-read deprecation window

The window is the cascade contract's (config-cascade § Expression doctrine); this contract supplies
its bounds. **A `migrate` record is what opens the window**: from the record's `retired` date the
migrated skill reads the retired file as authority while it is present and WARNs on every run. **The
window closes per consumer when that record's cleanup runs** (`--clean <id> --i-migrated` after the
operator confirmed the migrated result) **and closes fleet-wide when the record is demoted to
`report-only`**, at which point the migrated skill stops reading the retired file and the leftover
is reported as history rather than as a live divergence. A dual-read with no record, or one that
persists after demotion, is the silent shim the plugin philosophy forbids.

## Scope

Repository-scope surfaces only. The schema has no `scope` field. Machine-scope files under
`~/.claude/` (context-guard, rate-limit-guard, machine-health) are outside this contract and keep
their own detection, with the twin drift between context-guard and rate-limit-guard fixed by the
cross-plugin source registry rather than by this schema (ADR 0018, decision 6).

## Versioning

`contract_version` (SemVer) versions this contract; the number lives in [`CHANGELOG.md`](CHANGELOG.md).
Adding a required field, removing a field, changing a kind's detection semantics, changing an exit
code's meaning, or changing the severity map is a major bump. Adding an optional field, a new
`status` value, or a new `kind` with its own detection rule is a minor bump. The helper's behavior
reaches consumers only through the ordinary plugin version bump, and because detection re-runs on
every `check`, a consumer who skips versions still has every accumulated record evaluated — there is
no window to miss.

## Implementers

Conformance is tracked, not assumed. A plugin is listed here from the PR that ships its first record;
the row states the manifest as it exists on `main`.

| Plugin | Manifest record count | First record date |
|---|---|---|
| `source-control` | 1 | 2026-07-23 |

Row shape for a plugin adding itself: `` `<plugin>` `` \| count \| `YYYY-MM-DD`. The pilot surface
for the convention-doc expression form is `plugin-quality`'s `.claude/plugin-quality.md` (ADR 0018).

## Deferred

**CI-aggregated fleet registry.** A generated, committed registry of every plugin's records is the
only way to detect leftovers whose owning plugin has been *uninstalled*, since the runtime sweep can
only see what is installed. It lost the mechanism tournament on machinery and coupling and is
deferred. **Revive trigger:** orphan leftovers from an uninstalled plugin observed in practice — a
consumer reports an artifact no installed plugin's manifest explains.
