# Mutant records: `--record-mutants` and `--replay-mutants`

How [`../SKILL.md`](../SKILL.md) records the mutants one run applied and replays exactly those
mutants in a later run, so a caller can check that editing tests lost no kill. The record format is
private to this plugin: no other plugin reads a record. A caller passes record paths and reads the
report.

## The record

A UTF-8 text file. The first line is the commit sha of the production code the run mutated (`git
rev-parse HEAD`), and nothing else. Then one tab-separated row per mutant, seven fields:

| Field | Value |
|---|---|
| `path` | the mutated file, repo-relative, `/`-separated |
| `line_start`, `line_end` | the 1-based line range the mutant replaces, `line_start <= line_end` |
| `operator` | the operator name the report's Survivors table uses (`statement-removal`, `comparison-inversion`) |
| `original` | the exact text of those lines before the mutant |
| `replacement` | the exact text that replaced them (empty for a removal that leaves nothing) |
| `state` | `killed`, `survived`, `no-coverage`, `timeout` or `invalid` |

In `original` and `replacement`, a tab is written `\t`, a newline `\n` and a backslash `\\`, so a
multi-line statement removal fits one row. No other escape exists.

A record is a working file for one batch, kept in the caller's gitignored `.work/` directory, never
committed.

## Recording (`--record-mutants <file>`)

Runs only with `--exercised` (with or without a test path): the record is defined over the exercised
scope's mapped-line set, which starts from the named tests as they stand, and a recording runs
before any test is edited. Refuse it beside `--paths` or `--full`, naming both flags.

- **Regime: always the manual protocol** with the config's `test-command`, whatever the configured
  tool, the same regime replay must use. A record taken through a tool's own runner and replayed
  through `test-command` would compare two different detectors. No usable `test-command` is the
  exercised scope's refusal, naming `/mutation-testing:setup apply`.
- One mutant per mapped line, as the exercised scope already generates. The effort cap, `--max` and
  `max-mutants` apply unchanged, and the report states the cap and what it dropped.
- A red baseline of the test set stops the run and names the failing tests, as the exercised scope
  already does. No record is written.
- **The record is written only after Phase 3 verified restoration**, and only to a path outside
  tracked space: `git check-ignore -q <file>` succeeds, or the path resolves outside the checkout.
  Otherwise refuse before the first mutant, naming the path. The write is this flag's explicit
  override of the read-only contract, the same footing as `--persist-findings`.
- The report adds `Record: <file>, <n> mutants, K0 <n>`, where K0 counts the mutants detected
  (`killed` or `timeout`). A K0 of zero is reported as `K0 empty: nothing to gate on`.

## Replay (`--replay-mutants <before> --record-mutants <after>`)

Applies exactly the mutants listed in `<before>` and writes the result to `<after>`. Both flags and
`--exercised <test-path>` are required, with the same test path the recording used: the record does
not carry it. `<after>` must differ from `<before>`.

Phase 0, in this order, replacing the exercised scope's mapping:

1. Read `<before>`. A malformed record refuses: run SKILL.md's `compare-records.sh` command with
   `<before>` as both arguments, which exits 2 on a malformed row and on an empty K0 (nothing
   detected before proves nothing).
2. Refuse when the production files differ from the recorded sha on any listed path: `git diff
   --quiet <sha> -- "<path>" ...` compares the working tree with that commit, each record path
   quoted as its own argument (a record path is a file name from the repository, never shell text).
   Refuse when a listed `original` no longer matches its lines.
3. The test set is the tests under the test path now, recognized through `/testing:audit --file` as
   the exercised scope does. The mapping is skipped and so are its endings (`no changed tests: scope
   empty`, `no mapping: scope empty`): a batch that deleted tests must still be gated, not end as an
   empty scope. With no tests left, every listed mutant is recorded `no-coverage` without a run.
4. One baseline run of the test set with `test-command`. Red stops the replay and names the failing
   tests; no after record is written.

Then Phase 3 applies each listed mutant by hand (apply, run the test set, record the state,
revert, verify the revert), whatever tool is configured, with no cap, no incremental cache and no
regeneration. Mutant ids from a tool vary by version and config, so a regenerated set would compare
different mutants.

After restoration is verified, write `<after>` (same sha, same rows, new states) and run the
`compare-records.sh <before> <after>` command that SKILL.md "Record and replay" gives. It prints `newly-surviving <path>:<line_start> <operator>` per mutant detected before and not
after, then `K0 <n> K1 <n>`, and exits 0 (no loss), 1 (a loss) or 2 (it could not compare: stop and
report). Each newly surviving mutant goes to Phase 4 triage with the rest of the survivors; its
brief says the mutant was detected in the recording run and by which tests, which is direct
evidence against an equivalence call. A newly surviving mutant that triage calls equivalent or arid,
with the evidence Phase 4 requires, does not block.

The report adds, under the scope lines:

```text
Replay: <n> mutants from <before>   K0 <n>  K1 <n>
Gate: pass|block
newly-surviving <path>:<line_start> <operator>    <one per blocking mutant>
```

`Gate: block` when at least one newly surviving mutant is productive or unclassified; otherwise
`Gate: pass`.
