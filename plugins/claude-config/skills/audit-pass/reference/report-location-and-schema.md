# audit-pass — where the report lives, and its schema

This file owns §2 and §7: where a run writes its report, what `--report-to` may and may not target,
and the shape of both the incremental partial and the assembled `findings.json`.

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md).

## 2. Where the report lives

**A run never scans what it wrote.** If run 1 writes a report into the scanned tree and run 2 reads it,
run 2's tree is not unchanged and the idempotence property is unfalsifiable by construction.

**The governing condition is containment, not a flag.** Whether the run must protect itself from its own
report is decided by the predicate `report_path ⊆ target_root`, evaluated against the **resolved** report
path on every run. `--report-to` is one way that condition becomes true; it was never the definition of
it, and gating the machinery on the flag left the default path unprotected wherever the same condition
held.

- The report goes under `${CLAUDE_PLUGIN_DATA}` at `runs/<state-key>/<run-id>/findings.json`, which
  survives plugin updates. **State its location precisely, because a whole target class turns on it:**
  that directory resolves to `~/.claude/plugins/data/{id}/`
  ([plugins reference](https://code.claude.com/docs/en/plugins-reference), verified 2026-08-11), and no
  documented setting relocates it. It is therefore **outside** a target below `~` and **inside** any
  target at or above it. The default path is *usually* outside the scan set and is **not
  unconditionally** outside it — a dotfiles repository, or `~` itself, is a target where containment
  holds by construction, and the older unconditional claim was false there.
- `--report-to <path>` redirects the report, which makes containment hold whenever the destination lies
  inside the target.
- **Whenever containment holds — by either route — the run records that path in its own exclusion set
  before it writes**, and says so in its output. Not only for subsequent runs: deferring the record to
  run 2 would put the path in one run's derived-tier exclusion artifact and not the other's, and 2.2
  requires those two derived sets to be equal. The path is recorded whether or not a file exists there
  yet — the exclusion is about the path this run is about to write, not about what it found there.
- **Where containment does not hold, none of this is owed** and the run writes its report without an
  exclusion entry, because there is nothing to exclude from a tree the path is not in.
- **A redirect destination is accepted only if it is an `audit-pass`-owned report, or a new path that
  is not a recognized instruction surface.** Recording the path unconditionally is right for the
  *exclusion* and no licence to *write*: `--report-to CLAUDE.md` would overwrite an audited
  instruction surface with a JSON report, with no `--fix` and no confirmation — a read-only
  invocation destroying target content — and then exclude the corrupted path from every later run, so
  the damage hides itself.

  **Non-existence does not make an instruction path safe, and testing only for existence would miss
  that.** `--report-to CLAUDE.md` where no `CLAUDE.md` exists yet *creates* one: Claude then loads
  the JSON report as instructions, and the same rule that keeps the run from auditing its own
  artifact hides it from every later scan. The pass would have manufactured a live, behavior-
  affecting instruction surface and then made itself blind to it — worse than the overwrite case,
  because there is no prior content whose loss would signal what happened. So a destination matching
  a recognized instruction path is refused **whether or not it exists**, on name rather than on
  content, since at creation time there is no content to judge. Anything else already at the path is
  refused too, non-zero, naming the file; the run does not offer to overwrite, because
  the only surfaces this pass may write are its own. Ownership is decided by the artifact's own
  identifying header, never by filename or location, so a hand-placed file cannot claim it.

| # | Assertion |
|---|---|
| 2.1 | After a run against a clean git worktree whose **resolved report path is not contained in the target root**, `git status --porcelain` is empty. Scoped on containment rather than on "no redirect", because the default path is contained too whenever the target is at or above `~`, and the unscoped form was false there. |
| 2.5 | `--report-to <existing-non-report-path>` exits non-zero naming the file, writes nothing, and leaves the file byte-identical — including when the path is an audited instruction surface. |
| 2.2 | Where the report path is contained, a second run's scan set excludes it, and the two runs' derived identity sets are still equal. |
| 2.3 | The first run whose report path is contained records that path in its own exclusion artifact before writing the report, whether or not that path already exists, and whether it became contained by `--report-to` or by default resolution. |
| 2.4 | A run whose report path is contained in the target, against an otherwise-unchanging tree, reports the determinism gate as satisfied, not `indeterminate` — writing its own report does not move its own state digest. Holds for the default path under a target at or above `~` exactly as it holds under `--report-to`. |
| 2.6 | A run against a target at or above `~` with **no** `--report-to` discloses that its default report path is contained, and names it — the default-path twin of the redirect disclosure, so a contained write is never silent. |

## 7. Report schema

Two artifacts, because incremental persistence and a sectioned report want different shapes.

**During the run — `findings.partial.<owner_epoch>.jsonl`.** One JSON object per line, appended as each lane
completes. Append-only is what makes §5 real: a single JSON document would be rewritten whole on
every append, which is exactly the operation an interrupted run leaves half-done. A lane's final
record is its terminating record.

**Completion is read from the terminator's state, not from its presence.** A terminator lets
assembly render the lane; whether the lane is *done* is a separate question, and conflating them
would carry an outstanding `/doctor` handoff forward on every resume instead of closing it. A
terminator carrying `handed-back`, `declined`, or an ordinary lane completion marks the lane
**complete**; a terminator carrying **`open`** marks it **incomplete**, so `--resume` re-runs it —
which for a delegated lane is a re-prompt rather than a re-scan.

**Every record carries an attempt id, and an attempt is delimited at both ends.** A lane can be
attempted more than once — a completed lane is invalidated on resume when its input digest moved,
and an attempt can itself die before terminating — so an append-only file accumulates rows from
several attempts of one lane, interleaved with rows appended after them. Without a boundary, final
assembly cannot tell an abandoned partial attempt from the successful one, and would duplicate
findings or retain stale ones. So:

- `attempt` = `(lane id, ordinal)`, the ordinal starting at 1 and incremented on every re-attempt of
  that lane. Every record of that attempt carries it, findings included.
- An attempt opens with a **start record** and closes with its **terminating record**. Neither is a
  finding.
- **Assembly takes, per lane, the highest-ordinal attempt that has a terminating record, and
  discards every other attempt's rows outright** — including any complete-looking prefix. An attempt
  with a start record and no terminating record is abandoned by definition, whatever it managed to
  append.
- A resume that invalidates a completed lane appends a **supersession record** naming the lane and
  the ordinal it retires, so the retirement is in the artifact rather than inferred from ordering.
  Ordering alone cannot carry it: rows from a later attempt are appended after rows from an unrelated
  lane, and position is not provenance.

Each record separates the two field classes §1 distinguishes, because a reader who cannot tell them
apart cannot tell which fields a change would rename the finding through:

| Block | Fields | Rule |
|---|---|---|
| `identity` | `check`, `claim`, `sites` (each `surface` + versioned `anchor`, canonically sorted) | Hashed into `finding_id`. Nothing else is. |
| Presentation | `primary_site`, `related_site`, `load_path`, the *rendered* heading path, rendered prose | Carried for reading and remediation. Changing any of them leaves `finding_id` untouched. **The rendered path only** — the normalized heading path is hashed into the excerpt anchor's duplicate discriminator per §1, so restructuring the headings around an excerpt does rename the finding. |
| Run metadata | `lane`, `attempt`, `tier` | Where the record came from, and which attempt of that lane produced it. |

**At the end — `findings.json`.** One document assembled from the partial, carrying `schemaVersion`,
the run and target identity, the resolved version of every catalog consulted, and then the sections:

| Section | Contents |
|---|---|
| `inventory` | the three-scope surface list, derived tier |
| `mechanical` | derived-tier findings, including shadowed definitions |
| `behavioral` | judged-tier findings |
| `suppressed` | every entry with its reason, date, contributing cascade layer, and its disposition — including each `needs-reconfirmation` entry with the changed side named, each stale entry, each malformed entry, each **`personal-only, not applied`** entry, and every UNEXPLAINED DISAPPEARANCE |
| `delegated` | `/doctor`'s output, diffed by nobody |
| `skipped` | every surface excluded, **with its reason** — a silent exclusion reads as coverage, and this section is what stops it |

**Resume reads the partial, not the report**, so completion state is derivable from the artifact
rather than tracked beside it and able to disagree with it.
