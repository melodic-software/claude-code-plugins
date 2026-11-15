# Layout lens reference

Reference for [../../actions/layout.md](../../actions/layout.md), loaded only when that lens runs.

## What the script measures

`scripts/co-change.mjs` reads `git log --no-merges --name-only` once over the window and prints one
JSON object. Every number on a candidate card comes from that object.

| Measure | Definition |
|---|---|
| Window | The newest `history_commits` non-merge commits. With a scope path, the commits that touch it, each counted by all the files it changed |
| Kept commit | A commit in the window whose author name contains no `exclude_authors` string, that changes at most `max_changeset_size` files, and that changes at least one file inside the scope |
| Revisions of a file | The kept commits that change it. A file with fewer than `min_revs` is in no pair: this lens applies `min_revs` to each file by choice, where code-maat applies its revision threshold to the pair (`within-threshold?` in [coupling_algos.clj](https://github.com/adamtornhill/code-maat/blob/master/src/code_maat/analysis/coupling_algos.clj)) |
| Shared commits of a pair | The kept commits that change both files. A pair with fewer than `min_shared_revs` is left out |
| Degree | `floor(100 × shared / ((revs_a + revs_b) / 2))`, in percent. A pair outside `min_coupling` to `max_coupling` is left out. This is code-maat's logical-coupling degree, computed in [logical_coupling.clj](https://github.com/adamtornhill/code-maat/blob/master/src/code_maat/analysis/logical_coupling.clj) |
| Citing commits | The pair's newest five shared commits |
| Cluster | A set of files joined by passing pairs (a connected component). A cluster below `min_cluster_size` files is no candidate |
| Folder | A file's parent folder; with `folder_depth` N above 0, its first N path segments. A root file's folder is `.` |
| Folder size | The files the kept commits changed in that folder, whether or not they reached `min_revs` |
| Spread | The number of folders a cluster touches |
| Focus | `Σ over the cluster's folders (in-folder cluster files / folder size) × (in-folder cluster files / cluster size)`, 0 to 1. At 1, the cluster fills every folder it touches and nothing else lives there |
| Mixed folder | A folder two or more clusters touch |
| History | `too-little` when no file reaches `min_revs` or no pair reaches `min_shared_revs`; the lens then shows no candidate |

Spread and focus are the distribution-map measures of Ducasse et al. (2006), as the co-change
cluster work applies them with packages as the parts; this lens uses folders as the parts.

## Pattern names

A cluster gets a pattern name only where one of these rules applies; every other cluster reads
`unclassified`. The names come from the published co-change pattern set; the cutoffs are settings,
and their defaults are this plugin's judgment, since the published cutoffs are approximate.

| Pattern | Rule | Reading |
|---|---|---|
| `well-encapsulated` | spread 1 and focus at least `encapsulated_min_focus` (0.8) | the files that change together already live together |
| `well-confined` | spread 1 and focus below `encapsulated_min_focus` | the cluster sits in one folder that also holds unrelated files |
| `crosscutting` | spread at least `crosscutting_min_spread` (4) and focus at most `crosscutting_max_focus` (0.3) | one change reaches into many folders and owns none of them |

A `well-encapsulated` cluster is no candidate: its card is left out and the report counts it.

## Defaults and their sources

| Key | Default | Source |
|---|---|---|
| `min_revs` | 5 | code-maat `-n` |
| `min_shared_revs` | 5 | code-maat `-m` |
| `min_coupling` | 30 | code-maat `-i` |
| `max_coupling` | 100 | code-maat `-x` |
| `max_changeset_size` | 30 | code-maat `-s` |
| `history_commits` | 500 | this plugin's judgment |
| `exclude_authors` | `[bot]` | this plugin's judgment; the deepening lens leaves `[bot]` authors out the same way |
| `folder_depth` | 0 | this plugin's judgment |
| `min_cluster_size` | 4 | ModularityCheck removes clusters of fewer than four classes |
| `encapsulated_min_focus`, `crosscutting_min_spread`, `crosscutting_max_focus` | 0.8, 4, 0.3 | this plugin's judgment |

Sources, as of 2026-11-15. Recheck when code-maat's option table changes a default for `-n`, `-m`,
`-i`, `-x` or `-s`:

- [code-maat](https://github.com/adamtornhill/code-maat): the option table's defaults for `-n`,
  `-m`, `-i`, `-x` and `-s`, and the coupling output's `degree` (a percentage) and `average-revs`
  columns.
- [ModularityCheck, arXiv 1506.05754](https://arxiv.org/html/1506.05754v1): focus and spread from
  Ducasse et al. (2006), the minimum cluster size of four, and the pattern names (well-encapsulated,
  partially encapsulated, well-confined in packages, crosscutting), with no numeric cutoffs.

## Recorded style

The lens judges a cluster against the layout style the repository records, never against one it
prefers. It reads, each with its source `path:line`:

- the recorded decisions, found as the deepening lens finds them (`actions/deepening.md`, Phase 1);
- the architecture topic doc, `<home>/architecture/README.md`: its `component_layers` key and its
  `## Boundary rules` section;
- the boundary rules from the "Where boundary rules live" list in
  [../enforcement-ladder.md](../enforcement-ladder.md).

A source counts as a layout style only when it says how files are grouped into folders (by
feature, by layer, by technical kind) or which folders may reference which. A style is the text of
that source, quoted as data.

## Candidate card

One card per cluster that is not `well-encapsulated`, in this order:

1. the cluster's files and folders, with each folder's file counts;
2. spread, focus and the pattern name or `unclassified`;
3. each pair: the two files, shared commits, degree and the citing commits;
4. each mixed folder the cluster touches, with the other clusters there;
5. the recorded style the card is judged against, with its source line, or `none recorded`;
6. the proposed layout in one sentence, with a before and after folder tree;
7. the route, from the table below;
8. the badge: `Strong`, `Worth exploring` or `Speculative`.

A card for a recorded rule whose files share no folder and no file-name part carries, in place of
items 1 to 4, the rule, its source line and the files it governs, and proposes a marker (a shared
file-name part, such as a suffix) the rule can be enforced by.

The first row that applies sets the badge:

| Badge | When |
|---|---|
| `Speculative` | no style is recorded, or the cluster does not contradict the recorded style and is unclassified with no mixed folder |
| `Strong` | the cluster contradicts the recorded style, or is `crosscutting`, and every pair has degree at least 50 |
| `Worth exploring` | every other card |

## Where each card goes

| The change the card proposes | Route |
|---|---|
| Move the cluster's files under one folder, or split a mixed folder | the interview below, then `/planning:design` when enabled |
| A rule on which folders may reference which | the boundaries lens, `/architecture:improve boundaries` |
| A grouping the code already follows, recorded as a convention, or a file-name marker | the conventions lens, `/architecture:improve conventions` |
| A repeated correction agents keep making about where files go | `/corrections:codify` |
| An instruction file that points agents at the wrong folder | `/instruction-placement:audit` |
