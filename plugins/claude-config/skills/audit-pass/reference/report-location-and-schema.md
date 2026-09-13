# audit-pass: where the report lives, and its schema

This file owns §2 and §7: where a run writes its two report artifacts, what `--report-to` may and
may not target, and the shape of the incremental partial, the assembled `findings.json`, and the
human-readable `report.md`.

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md).

## 2. Where the report lives

**A run never scans what it wrote.** If run 1 writes a report into the scanned tree and run 2 reads it,
run 2's tree is not unchanged and the idempotence property is unfalsifiable by construction.

**The governing condition is containment, not a flag.** Whether the run must protect itself from its own
report is decided by the predicate `report_path ⊆ target_root`, evaluated against the **resolved** report
path on every run. `--report-to` is one way that condition becomes true, not the definition of it;
gating on the flag would leave the default path unprotected wherever the same condition holds.

**A run writes two report artifacts, and "the report path" means both of them.** `findings.json` is
the diffable machine artifact every property in this contract is stated over; `report.md` is the
human-readable rendering of the same assembled document, written beside it in the same directory. The
pair exists because the JSON artifact is unreadable in the place an operator actually meets it: it is
a large single-line-per-section document at a deep key-derived path under the plugin data directory,
which a remote session cannot open and a terminal cannot usefully print. A pass whose only output is
that file has done the work and delivered none of it. **`report.md` is a rendering and never a
source**: it carries no fact the assembled document does not, nothing reads it back, and `--resume`
still reads the partial.

Every containment rule, exclusion rule, and destination refusal below is stated over **both**
resolved paths. Protecting one and not the other would leave the pass auditing its own `report.md`
while excluding its `findings.json`, which is the same unfalsifiable-idempotence defect in half.

- The two artifacts go under `${CLAUDE_PLUGIN_DATA}` at `runs/<state-key>/<run-id>/findings.json`
  and `runs/<state-key>/<run-id>/report.md`, which
  survives plugin updates. **State its location precisely, because a whole target class turns on it:**
  that directory resolves to `~/.claude/plugins/data/{id}/`
  ([plugins reference](https://code.claude.com/docs/en/plugins-reference), verified 2026-08-12), and no
  documented setting relocates it.

  **`{id}` is derived, and deriving it wrong loses the report.** Same page, verbatim: `{id}` is *"the
  plugin identifier with characters outside `a-z`, `A-Z`, `0-9`, `_`, and `-` replaced by `-`"*, with
  the worked example that a plugin installed as `formatter@my-marketplace` lands in
  `~/.claude/plugins/data/formatter-my-marketplace/`, because the `@` becomes `-`. A wrong derivation writes
  the report where the next run will not look for it, which is also how `--resume` loses a partial.

  **`${CLAUDE_PLUGIN_DATA}` is not in the Bash tool's environment. Do not try to expand it from a
  shell.** The same page scopes the export precisely: *"All three are exported as environment variables
  to hook processes and to MCP and LSP server subprocesses."* The Bash tool is none of those. The token
  does substitute in **skill content**, which is how a resolved path reaches you in this file, but
  `echo "$CLAUDE_PLUGIN_DATA"` inside a Bash call yields an empty string. Use the path already
  substituted into the text you are reading, or rebuild it from `~/.claude/plugins/data/` plus the
  mangled identifier above.

  It is therefore **outside** a target below `~` and **inside** any
  target at or above it. The default path is *usually* outside the scan set and is **not
  unconditionally** outside it. A dotfiles repository, or `~` itself, is a target where containment
  holds by construction.
- **`--report-to <dir>` takes a DIRECTORY, and redirects BOTH artifacts into it.** The flag was
  specified over "the report" singular, and with two artifacts that reading has to be settled rather
  than left to the caller. A directory is the answer, and a file path is refused:

  - A file path names **one** artifact, so the flag would have to invent the other's destination out
    of it, by appending a second extension or by writing the sibling next to a path the operator
    chose for something else. Both are the pass writing where nobody asked it to.
  - Redirecting **one** artifact is worse than redirecting neither. An operator who redirects into a
    reviewable location and gets only the JSON there, with the rendering still at the unreadable
    default path, has been given exactly the artifact the flag exists to rescue them from.
  - A directory makes the destination gate below decidable once, over the two resolved paths inside
    it, rather than once per artifact with a different rule for each.

  The artifacts keep their names inside that directory: `<dir>/findings.json` and `<dir>/report.md`.
  The directory is created if absent. A `--report-to` naming an existing path that is **not** a
  directory is refused non-zero, naming the path, and writes nothing. Redirection makes containment
  hold whenever the destination lies inside the target, exactly as before.
- **Whenever containment holds, by either route, the run records that path in its own exclusion set
  before it writes**, and says so in its output. Not only for subsequent runs: deferring the record to
  run 2 would put the path in one run's derived-tier exclusion artifact and not the other's, and 2.2
  requires those two derived sets to be equal. The path is recorded whether or not a file exists there
  yet. The exclusion is about the path this run is about to write, not about what it found there.
- **Where containment does not hold, none of this is owed** and the run writes its report without an
  exclusion entry, because there is nothing to exclude from a tree the path is not in.
- **The destination gate is evaluated over the two resolved paths inside the directory, and each is
  accepted only if it is an `audit-pass`-owned artifact or does not exist.** Recording a path
  unconditionally is right for the *exclusion* and no licence to *write*: a destination directory
  whose `report.md` is somebody's hand-written document would have that document overwritten by a
  rendering, with no `--fix` and no confirmation, a read-only invocation destroying target content.
  It would then exclude the corrupted path from every later run, so the damage hides itself.

  **A directory destination is refused outright when either resolved path is a recognized
  instruction surface, and non-existence does not make one safe.** `--report-to .claude/rules`
  resolves `report.md` inside a directory Claude loads from: the pass would write a rendering where
  nothing yet exists, Claude would load it as instructions, and the same rule that keeps the run from
  auditing its own artifact would hide it from every later scan. The pass would have manufactured a
  live, behavior-affecting instruction surface and then made itself blind to it. That is worse than
  the overwrite case, because there is no prior content whose loss would signal what happened. So a
  resolved path matching a recognized instruction path is refused **whether or not it exists**, on
  name rather than on content, since at creation time there is no content to judge. Anything else
  already at either path is refused too, non-zero, naming the file; the run does not offer to
  overwrite, because the only surfaces this pass may write are its own. Ownership is decided by the
  artifact's own identifying header, never by filename or location, so a hand-placed file cannot
  claim it, and **both artifacts carry that header**: `findings.json` in a top-level field,
  `report.md` in its first line.

| # | Assertion |
|---|---|
| 2.1 | After a run against a clean git worktree whose **resolved report path is not contained in the target root**, `git status --porcelain` is empty. Scoped on containment rather than on "no redirect", because the default path is contained too whenever the target is at or above `~`. |
| 2.5 | `--report-to <dir>` where `<dir>/findings.json` or `<dir>/report.md` already exists and is not an `audit-pass`-owned artifact exits non-zero naming that file, writes nothing, and leaves it byte-identical. The same holds when the resolved path is a recognized instruction surface, whether or not it exists. |
| 2.5a | `--report-to <path>` where `<path>` exists and is not a directory exits non-zero naming the path and writes nothing. |
| 2.7 | A run writes `findings.json` and `report.md` into the same directory, both carrying the ownership header, and redirects **both** under `--report-to`. `report.md` states no finding the assembled document does not carry, and `--resume` reads neither. |
| 2.2 | Where the report path is contained, a second run's scan set excludes it, and the two runs' derived identity sets are still equal. |
| 2.3 | The first run whose report path is contained records that path in its own exclusion artifact before writing the report, whether or not that path already exists, and whether it became contained by `--report-to` or by default resolution. |
| 2.4 | A run whose report path is contained in the target, against an otherwise-unchanging tree, reports the determinism gate as satisfied, not `indeterminate`, because writing its own report does not move its own state digest. Holds for the default path under a target at or above `~` exactly as it holds under `--report-to`. |
| 2.6 | A run against a target at or above `~` with **no** `--report-to` discloses that its default report path is contained, and names it. This is the default-path twin of the redirect disclosure, so a contained write is never silent. |

## 7. Report schema

Two artifacts, because incremental persistence and a sectioned report want different shapes.

**During the run: `findings.partial.<owner_epoch>.jsonl`.** One JSON object per line, appended as each lane
completes. Append-only is what makes §5 real: a single JSON document would be rewritten whole on
every append, which is exactly the operation an interrupted run leaves half-done. A lane's final
record is its terminating record.

**The append is `scripts/run-state.sh partial append`, not a hand-rolled redirection**, and its full
form carries the writer's epoch:

```
run-state.sh partial append --run-dir <run-dir> --record '<json-line>' --epoch <held>
```

**`--epoch` is not optional in practice.** The file is named for the epoch **the writer holds**, never
whatever the lease currently carries: omit it after an adoption and the fallback selects the
*adopter's* epoch, putting a superseded writer's rows into the adopter's file, exactly the
cross-writer interleaving §3's fencing exists to prevent. Where the two differ the command writes to
the writer's own file, says `FENCED`, and **exits 3**: the record is safe, and the run that wrote it
is superseded and must stop. A lease must exist either way, so the partial cannot outlive the thing
that classifies it, and a record that is not a well-formed single-line JSON object is refused.

**Assembly is executable, and the selection rules below are what it implements.**
[`scripts/assemble.sh`](../scripts/assemble.sh) reads the highest-epoch partial, applies the
highest-terminated-attempt selection, writes `findings.json`, and renders `report.md` from it. It was
prose before, which put the one step that decides *which rows reach the report* in the same class as
the steps a run improvises; a selection rule performed differently on two runs is a P1 failure the
gate cannot attribute. The script needs `python3`, and where that is absent it exits non-zero naming
the prerequisite and the run performs the selection itself against the rules below, which is why they
stay stated here in full rather than deferring to the implementation.

**Completion is read from the terminator's state, not from its presence.** A terminator lets
assembly render the lane; whether the lane is *done* is a separate question, and conflating them
would carry an outstanding `/doctor` handoff forward on every resume instead of closing it. A
terminator carrying `handed-back`, `declined`, or an ordinary lane completion marks the lane
**complete**; a terminator carrying **`open`** marks it **incomplete**, so `--resume` re-runs it,
which for a delegated lane is a re-prompt rather than a re-scan.

**Every record carries an attempt id, and an attempt is delimited at both ends.** A lane can be
attempted more than once, since a completed lane is invalidated on resume when its input digest moved,
and an attempt can itself die before terminating. So an append-only file accumulates rows from
several attempts of one lane, interleaved with rows appended after them. Without a boundary, final
assembly cannot tell an abandoned partial attempt from the successful one, and would duplicate
findings or retain stale ones. So:

- `attempt` = `(lane id, ordinal)`, the ordinal starting at 1 and incremented on every re-attempt of
  that lane. Every record of that attempt carries it, findings included.
- An attempt opens with a **start record** and closes with its **terminating record**. Neither is a
  finding.
- **Assembly takes, per lane, the highest-ordinal attempt that has a terminating record, and
  discards every other attempt's rows outright**, including any complete-looking prefix. An attempt
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
| Presentation | `group`, `primary_site`, `related_site`, `load_path`, the *rendered* heading path, rendered prose | Carried for reading and remediation. Changing any of them leaves `finding_id` untouched. **The rendered path only.** The normalized heading path is hashed into the excerpt anchor's duplicate discriminator per §1, so restructuring the headings around an excerpt does rename the finding. `group` is §1's `group/v1`, which ties one claim's split sites together without entering identity. |
| Run metadata | `lane`, `attempt`, `tier` | Where the record came from, and which attempt of that lane produced it. `tier` is `derived`, `judged`, `delegated`, or `note`. |

**A note record is not a finding record.** An overlap note carries a `note_id`, the two `finding_id`s
it names, and its rendered prose, and carries no `identity` block at all. Giving it one would put a
tier §6 excludes from `D(R)` into the same shape identity sets are built from, which is exactly the
confusion the separate id prevents. The emitter guard validates a note against this shape rather than
against the finding shape.

**At the end: `findings.json`.** One document assembled from the partial, carrying `schemaVersion`,
the run and target identity, the resolved version of every catalog consulted, and then the sections:

| Section | Contents |
|---|---|
| `inventory` | the three-scope surface list, derived tier |
| `mechanical` | derived-tier findings, including shadowed definitions |
| `behavioral` | judged-tier findings |
| `suppressed` | every entry with its reason, date, contributing cascade layer, and its disposition, including each `needs-reconfirmation` entry with the changed side named, each stale entry, each malformed entry, each **`personal-only, not applied`** entry, and every UNEXPLAINED DISAPPEARANCE |
| `notes` | note-tier cross-catalog overlap notes, each naming both `finding_id`s and neither merging them nor replacing either |
| `delegated` | `/doctor`'s output, diffed by nobody |
| `skipped` | every surface excluded, **with its reason**. A silent exclusion reads as coverage, and this section is what stops it |
| `verification` | per-lane verification mode (`verified` \| `inline` \| `skipped`) for lanes that mandate independent subagent dispatch; omitted only when every such lane verified |

**Beside it: `report.md`.** Rendered from the assembled document, never from the partial, so the two
artifacts cannot disagree about which attempt won. Its shape, in order:

| Block | Contents |
|---|---|
| Ownership line | The first line, the identifying header that makes the file `audit-pass`-owned |
| Header | Run id, target, resolved report directory, HEAD at both captures, harness version, the lane set and whether the run was partial-scope, and the arguments that affect behavior |
| Verdict | The determinism gate (`passed`, `failed`, `indeterminate`), the comparability verdict naming any input that moved, and P1-P6 each as satisfied, failed, or **not evaluated with the reason** |
| Headline | One line: counts per tier and per severity, and the count of surfaces skipped. This is the line the run prints inline |
| Findings | Derived tier then judged tier, grouped by lane, each finding with its severity, its site, its `finding_id`, and its `group` where one groups more than a single finding |
| Notes, suppressed, delegated, skipped, verification | One section each, mirroring the assembled document's sections of the same names |

**Every section of the assembled document appears, including the empty ones.** A rendering that
omits a section when it has no rows is one an operator reads as coverage: an absent `skipped`
section and an empty `skipped` section look identical on the page and mean opposite things. An empty
section renders its heading and the word `none`.

**The run prints the headline inline and offers the file; it never prints the report.** The whole
reason for the second artifact is that the full document does not fit where the operator is
standing, and pasting it into the transcript reintroduces that cost in the one place the pass
controls.

**Resume reads the partial, not the report**, so completion state is derivable from the artifact
rather than tracked beside it and able to disagree with it. §5 makes the same point from the other
side: the run manifest is these lane records, not a second file, because a manifest beside the partial is
precisely the thing that could disagree with it. And the instruction the report gives the operator,
to come back with `--resume`, is only true because the partial is written by a script as each lane
terminates, Phase 4's `open` handoff included.
