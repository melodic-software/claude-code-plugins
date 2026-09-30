# changelog: decision rows, where decisions live, fan-out and persistence

`diff` reports decisions about components, not a triage of changelog items. This file defines the
row, where each kind of decision is recorded, how the work fans out, and what a run leaves on disk.
The lenses and their definitions are in [classification-rubric.md](classification-rubric.md).

## Decision rows

`diff` emits one row per (owner surface, lens), grouped by owner surface. An owner surface is a
component the repo owns: a skill, hook, rule, script, doc, or setting. Several items that land on
the same surface and lens fold into one row that lists their ids.

| Owner surface | Lens | Items | Required sentence | Outcome |
|---|---|---|---|---|
| `<component path>` | correct, replace, adopt | `2.1.257-001, 2.1.260-015` | see below | fix, nominate, adopt, decline, defer pending probe |

The required sentence is what makes a row a decision and not a restated item:

- **correct**: the claim as the component states it (false) and as the release states it (true)
- **replace**: the problem the component solves, so the reader can judge whether the native surface solves the same one
- **adopt**: the problem the item solves for the component

A row without its sentence is not emitted. A **note** is one line under the table. A **skip** item
leaves no row and no line; it shows only in the read summary's count.

After the table, a **docs-lag** section lists each changelog-versus-docs disagreement as a pair
(what the changelog states, what the page states, the page). It is input to `/claude-ops:known-issues`
when that skill is installed, and is never a decision row.

Item ids are stable: `<version>-<ordinal>`, the ordinal counted as three digits over every bullet of
the release block in the order the fetched page lists them, whatever its prefix. `2.1.257-001` is the
first bullet of release `2.1.257`. The item files record each id, so a saved working set keeps its
pointers if the page's layout later changes.

## Where decisions live

| Decision | Recorded in |
|---|---|
| Correction | The owning plugin's `CHANGELOG.md`. The ledger's Corrected table points at that entry |
| Replace candidate | Nominated into the `/claude-ops:audit-native-overlap` gate. A run never writes the verdict and never edits the component. The ledger row reads `nominated`, never `replaced` |
| Adoption, decline, defer | The upstream ledger, in its Adopted and Declined tables |
| Read marker | The upstream ledger's marker line (see [read-actions.md](read-actions.md)) |

The upstream ledger (default `docs/upstream/claude-code.md`) keeps one table per outcome, in the
shape already there: Corrected, Nominated, Adopted, Declined. Each row carries its decision, its item
ids, its owner surface or component, and its record; a Declined row also carries its reopen
condition. A release that produced no decision leaves no row, and the ledger never restates a
changelog item: the id column is the pointer.

The harness facts a skill states, with their verification stamps and recheck triggers, follow the
[upstream-drift convention](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/upstream-drift/README.md).
This skill does not restate it; the fetch route is in [read-actions.md](read-actions.md).

## Fan-out shape

No Workflow script is used. The orchestrating session spawns ordinary subagents, sized so cost
follows the number of clusters and not the number of items:

1. **Item files.** Ingest writes one file per release, one line per item, each led by its stable id.
2. **Explore.** One explorer per release cluster of about fifty items, reading the item files and grepping the surfaces in [repo-surfaces.md](repo-surfaces.md). Each returns candidate (surface, lens) pairs, the repo evidence, and the questions research must answer.
3. **Research.** One researcher per feature cluster, receiving the explorers' questions. It grounds every claim by `curl` of the docs page to a local file and returns the page URL with each claim. An uncited claim is unverified.
4. **Verify.** One local verifier checks the repo-side facts: each cited component says what the row says, each path exists, each false-versus-true pair is a pair.

Each explorer reads the repo once and each docs page is fetched once per feature cluster, so a wider
range adds explorers in steps of about fifty items and adds researchers only for new features.

## Persistence

`diff` writes its working set under `<memory_dir>/claude-code-changelog/<range>/`, where
`<memory_dir>` is the consuming repo's bound memory directory (default `.work/`) and `<range>` reads
`<A>..<B>`:

- `items/<version>.md`: the item files
- `rows.md`: the repository revision (`git rev-parse HEAD`) the rows were derived at, then the decision rows and the docs-lag section, each row with its recheck trigger (the page it rests on and the condition that would change it)
- `pages/`: the docs pages the researchers fetched, each with its URL and fetch time on its first line
- `native-drift/`: `apply` Phase 7's extraction, overlap candidates, summary and drift report ([native-drift.md](native-drift.md)). The summary is then copied to `<memory_dir>/claude-code-changelog/native-surface-summary.json`, the one file outside any range: the next run diffs against it

`apply` consumes that directory instead of re-running `diff`. It re-fetches only what a recheck
trigger names: a release newer than `<B>` exists, or a row's own trigger is met. A row whose
trigger has not fired is used as saved, once the local verifier has re-checked it against the current tree: the row's owner path must exist and its false-versus-true pair must still hold there. A row that fails is re-derived. When the recorded revision is not the current one, or the memory directory is shared across worktrees, the verifier runs on every row. With no working set for the range, `apply` runs `diff` first.
