# audit-pass — retired-conventions fleet sweep

This file owns the one Phase 3 lane that runs a script rather than a skill: the sweep of every
installed plugin's `retirements.yaml` against the target repository, using this plugin's own
canonical `lib/check-retirements.sh`.

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md). Finding identity:
[finding-identity.md](finding-identity.md). Suppression: [suppression.md](suppression.md).

## Why this lane exists

A plugin's own setup `check` detects its retired conventions, but only when the operator re-runs
that setup. A consumer who updates a plugin and never re-runs setup carries the leftover
indefinitely, and nothing re-checks it. The sweep closes that gap at the fleet level without a
generator or a committed aggregate: it reads the manifests that are installed at the moment it
runs. The cross-plugin contract — schema, helper exit codes, severity map — is the marketplace's
retired-conventions convention; this file states what the pass itself needs in order to run it.

## Discovering manifests

The lane needs the root directory of every installed plugin, and that is the one input it cannot
derive from the target repository. Two sources, in order, and both are **probed, not assumed**:

1. **`claude plugin list`**, where its output names an install path per plugin. Take each path as
   that plugin's root and probe `<root>/retirements.yaml`. Prefer this source: it names the
   *enabled* version, so the manifest read is the one whose setup the consumer would run.
2. **A bounded `find` over the plugin cache** when the CLI output names no paths: the cache lives
   under the config directory (`~/.claude/plugins/cache` by default), and the search is
   `-maxdepth 4 -name retirements.yaml` — `<marketplace>/<plugin>/<version>/retirements.yaml` is
   depth 4, and a deeper hit is not a plugin root. **The cache layout is internal and
   undocumented.** Say so in the lane's coverage note whenever this source is the one used; a
   layout change makes the fallback find nothing, which is the next case, not a crash. Where the
   cache holds several versions of one plugin, take the highest version directory and name the
   choice in the coverage note.

When **neither** source yields a root, the lane does not report clean. It records itself as
**unchecked with its reason** — "no installed plugin roots discoverable: `claude plugin list`
named no paths and the cache fallback found nothing" — exactly as an absent delegated plugin would
be recorded. An empty manifest set is a real state and reports as one lane with zero findings; an
undiscoverable one is a coverage gap and reports as one.

Every discovered manifest is listed in the lane's coverage note by plugin name and the source that
found it, so a plugin whose manifest silently dropped out of the set between two runs fails the
determinism property rather than looking like an improvement.

## Running the helper

For each manifest, one invocation of **this plugin's** copy, never the owning plugin's:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "<root>/retirements.yaml" --root "<target>"
```

The owning plugin's synced copy is byte-identical by CI contract, but the pass never reaches into
another plugin's `lib/`; the manifest is the published seam and the helper is ours. `--root` is the
resolved target, the same value Phase 0 keyed and locked on.

Per manifest, the helper's exit code decides the shape of what is recorded:

| Exit | Recorded as |
|---|---|
| 0 | No active leftover for that plugin. Any `report-only` rows it still emitted become `info` findings. |
| 1 | One finding per TSV row (below). |
| 2 | **One FAIL finding for that plugin**, carrying the helper's stderr as the message. Never a skip: an unreadable or invalid manifest is a defect in the plugin, and a run that silently dropped it would report a consumer as clean on the strength of a manifest nobody evaluated. |

## Finding identity

Each TSV row (`id`, `kind`, `path`, `action`, `status`, `note`) maps onto the pass's identity tuple
as follows, so the finding is stable across runs and suppressible per the usual record:

- **`check`**: `claude-config/audit-pass/retired-convention`. Fully qualified, as §1 requires.
- **`claim`**: the lane **declares** its template set, so it is never claim-unqualified:
  `leftover(<record-id>)` for a row, and `manifest-invalid(<plugin>)` for an exit-2 manifest. The
  record id is the bound parameter; it is what makes two rows from one plugin two findings, and one
  row across two runs one finding.
- **`sites`**: one site. `surface` is the row's `path` — already a repo-relative POSIX path under
  the target, so it takes the project-scope form with no prefix; for `kind: dir` it is the
  directory path as declared. `anchor` is **whole-surface (`s:`)** for every kind: a leftover is a
  finding about the artifact's existence, and §1 is explicit that such a finding must not be
  retired by editing a line inside it. A `line`-kind leftover is still about the *file carrying*
  the retired line, and the `match` pattern is the record's, not the consumer's, so an excerpt
  anchor over the matched text would tie identity to consumer content the record never named.
  A rename is a new surface and correctly re-reports. An exit-2 finding's site is the manifest's
  owning plugin, in the scope-prefixed logical form `plugin:<plugin>/retirements.yaml`, since the
  manifest lives outside the target root.

**Severity** follows the convention's single map, so a consumer sees one severity for one record
wherever it is reported: `migrate` → FAIL, `delete` / `remove-line` → WARN, `status: report-only`
→ INFO regardless of action, `manifest-invalid` → FAIL. Presentation carries the row's `note`, the
`action`, and the remediation — always "run `/<plugin>:setup apply`", never a `--clean` performed
here.

## Tier and determinism

The lane is **derived-tier**: the helper is deterministic, the manifest set is enumerated, and no
model is in the path between the TSV and the finding. Its identity set must be exactly equal across
two runs over an unchanged tree **and an unchanged installed manifest set** — the manifest set is
part of the lane's input digest for that reason, and a plugin installed or updated between two runs
makes the runs non-comparable on this lane, reported as such rather than as instability.

## Read-only, and what that rules out

The sweep never invokes `--clean`, under any flag, including `--fix`. Two reasons, and either alone
would suffice:

1. **The operator gate lives in the owning plugin's setup `apply`.** A `migrate` record's
   `successor` prose tells the model what to carry where; the convention doc it reads while doing
   so is consumer prose and untrusted input; the operator confirms the migrated result before
   `--clean --i-migrated`. None of that is this pass's to perform: it dispatches and never reaches
   inside another plugin's contract.
2. **Phase 5's mutation scope is project files this pass's own delegated findings proposed.** A
   cleanup here would be an edit proposed by another plugin's manifest and applied by this one, with
   the accepted-set-equals-applied-set check unable to say whose acceptance it was checking.

So a `--fix` run records every sweep finding with its remediation and applies none of them.

## Repeated declines

An operator who has judged a leftover and decided to keep it records that decision in the target's
`.claude/audit-pass.md` per [suppression.md](suppression.md), keyed by the finding's identity above.
No new consumer-side file, no marker in the leftover itself, and the same four dispositions apply:
a suppressed leftover that is later cleaned closes as a fix; one whose record is demoted to
`report-only` is still emitted (at `info`) and its entry still matches, because the identity does not
carry severity.
