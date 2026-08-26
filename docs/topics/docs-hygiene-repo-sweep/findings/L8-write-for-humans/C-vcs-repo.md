# C-vcs-repo

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 11 `HUMAN` rows (5 plugin READMEs,
5 CHANGELOGs, plus `plugins/source-control/skills/worktree/fixtures/README.md`, which this lane
reclassifies out of the slice, see below). The 5 CHANGELOGs are judged as a class in `README.md`.

`plugins/disk-hygiene/README.md` is the largest document-mode finding in the corpus and takes most
of this file.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| C1 | `plugins/disk-hygiene/README.md:54` | `M1`, `M2` | S2 |
| C2 | `plugins/disk-hygiene/README.md:196` | `M1` | S2 |
| C3 | `plugins/repo-fleet-hygiene/README.md:11` | `Am1` | S2 |
| C4 | `plugins/repo-hygiene/README.md:60` | `Am1` | S3 |
| C5 | `plugins/repo-fleet-hygiene/README.md:39` | `M2` | S2 |
| C6 | `plugins/disk-hygiene/README.md:299` | `M3` | S1 |
| C7 | `plugins/github/README.md:71` | `M3` | S2 |
| C8 | `plugins/source-control/README.md:274` | `M3` | S2 |
| C9 | reclassification | `plugins/source-control/skills/worktree/fixtures/README.md` | n/a |

### C1. `## Requirements and platform support` is not a requirements section

`plugins/disk-hygiene/README.md:54` through `:135`, 81 lines. The heading promises reference: what
you need to run this. The content is a design-and-incident history written as bullets. Predicates
`M1` (mode) and `M2` (release history in a reference document), reinforcing each other.

Six release-history sites inside this one section, verbatim:

```text
Exec form is the regression this plugin hit twice: as
`"command": "bash"` in the wired hooks (#1416) and as `"command": "python3"` in the belt (#2568).
```

```text
the earlier bare-`${user_config.*}` argument that dropped the engine gate on a
default install is gone (since 0.9.0).
```

```text
- **A silent engine-gate launch/runtime failure is now surfaced (since 0.9.5, #1416).**
```

```text
Since 0.17.9 that includes the skill-scoped belt, which previously named `python3` directly as its
exec-form `command` and so could not start at all against the stub.
```

```text
(the same fail-open shape as the 0.6.3 launch-failure fix, via a
different vector)
```

```text
see the 0.17.8 delta for exactly what that bounds now that the string
reaches a shell
```

None of the six survives the predicate's carve-out. A person installing `disk-hygiene` today needs
to know that hooks are registered in shell form and that the launcher resolves Python
independently. They do not need to know that the plugin reached that state by hitting the same
regression twice, nor which release fixed it.

Remediation, in three moves. This is a restructure, so it is specified as a shape rather than as one
replacement string:

1. **Split the section by mode.** `## Requirements and platform support` keeps only what a reader
   needs before installing: Python 3.11 or later, Git optional except inside a worktree, `gh` for
   standalone-checkout evidence mode, and the Windows audit-only limitation. That is roughly 15
   lines of the current 81.
2. **Move the design rationale** (why hooks use shell form, why the launcher resolves Python itself,
   what fail-open means here) to a new `## How the guard is registered` section, or to the skill's
   own reference tree. It is explanation and it earns its place, but not under a requirements
   heading.
3. **Move every version delta and regression narrative to `plugins/disk-hygiene/CHANGELOG.md`.**
   `scripts/check-changelog-parity.sh` already requires that file to carry each version's entry, so
   in most cases the sentence is being duplicated rather than relocated. The wave 3 editor should
   check the changelog first and delete rather than move where the entry already exists.

The bare `(#1416)` and `(#2568)` citation forms are house convention per
`docs/conventions/tracker-reference-form/README.md` and are not themselves findings. Where a
sentence survives the move, its citation survives with it.

### C2. `## Plugin-acceptance security review` is a review artifact, not a README section

`plugins/disk-hygiene/README.md:196` through `:298`, 103 lines. Predicate `M1`.

The heading names a process (a review that was conducted) rather than a property of the plugin. The
content is a reviewer's checklist answered point by point, including measurement records with dates
and hardware:

```text
Known costs, accepted, with the always-on share measured per the hook-budget convention's method
(`time` wall-clock around direct hook invocation with a benign representative payload; Windows 11 +
Git Bash dev host, 2026-08-16)
```

Under Diátaxis this is neither reference nor explanation about the product. It is a record of an
assessment. A reader who wants to know whether the plugin is safe to install wants the answer, not
the audit.

Remediation: rename the section to `## Security posture` and rewrite its lead so it states the
posture rather than reporting a review. Two other plugins in the corpus already use that heading,
so this also serves predicate `N1`. Keep every fact. The measurement dates and host stay, because
the resolved guide's third survives-the-guide rule requires a measured number to carry the
conditions it was measured under.

Filed at S2 rather than S1 because the content is accurate and useful; only its framing and heading
are wrong.

### C3

`plugins/repo-fleet-hygiene/README.md:10` to `:12`, verbatim:

```text
- remote-tracking heads that still exist on origin after a GitHub merge (where
  `delete_branch_on_merge` is not enabled or was blocked. Enabling that setting is complementary,
  not a substitute for this visibility, and this plugin never changes repository settings);
```

Predicate `Am1`. The parenthetical opens with a subordinate clause, ends a sentence inside itself,
and then runs 20 more words before closing. A reader following the list item loses the thread.

Replacement:

```text
- remote-tracking heads that still exist on origin after a GitHub merge, because
  `delete_branch_on_merge` is not enabled or was blocked. Enabling that setting is complementary to
  this visibility rather than a substitute for it, and this plugin never changes repository
  settings.
```

### C4

`plugins/repo-hygiene/README.md:60`. Verbatim:

```text
(`disk_hygiene_enabled`, or `repo_hygiene_enabled`; user-scoped. Per-repository disable means disabling the plugin in that project's `settings.json`)
```

Predicate `Am1`, same shape, S3 because the fragment is short and the reader recovers quickly.

Replacement:

```text
(`disk_hygiene_enabled` or `repo_hygiene_enabled`, both user-scoped. To disable per repository,
disable the plugin in that project's `settings.json`.)
```

### C5. A capability table that is really a shipping log

`plugins/repo-fleet-hygiene/README.md:39` through `:43`. Predicate `M2`. Five consecutive table rows
whose third column is a release record. Verbatim, one row:

```text
| One fleet cleanup-plan handoff consuming that artifact | `repo-fleet-hygiene:apply` (owns batched merged-local-branch deletion; worktree cleanup in plan order) | Shipped in 0.22.0 / [#2597](https://github.com/melodic-software/claude-code-plugins/issues/2597); plan artifact from [#2644](https://github.com/melodic-software/claude-code-plugins/pull/2644) / [#2609](https://github.com/melodic-software/claude-code-plugins/issues/2609) |
```

A person reading this README wants to know what the plugin does. `Shipped in 0.22.0 / #2597` tells
them only when it was built. The column heading it sits under should be checked in wave 3; if every
row says `Shipped`, the column carries no information at all and the table is a changelog with a
capability column bolted on.

Remediation: drop the third column from the rows where it reads `Shipped in …`, keeping only rows
whose disposition is genuinely still open (`Delegated`, or an unshipped capability). The release
records already exist in `plugins/repo-fleet-hygiene/CHANGELOG.md`. Also `Am3`: the `0.22.0 / #2597`
slash is coordination and becomes `and`.

### C6 to C8. The generated options block is not under `## Configuration`

Class finding, detailed once in `README.md` under `M3`. This group holds three of the sixteen
outliers, including the single worst placement in the corpus:

| Path | Heading the block sits under | Options block at |
|---|---|---|
| `plugins/disk-hygiene/README.md:299` | `## Sources` | line 333 |
| `plugins/github/README.md:71` | `## Install` | line 83 |
| `plugins/source-control/README.md:274` | `## Security` | line 296 |

`plugins/disk-hygiene/README.md` is S1 rather than S2: a reader looking for the plugin's
configuration options will not open a section headed `## Sources`, and `## Sources` in every other
plugin README in the corpus means citations. That is predicate `N1` as well as `M3`: one heading
name is doing two jobs.

Remediation as in `B-cc-config-ops.md`: move the marker-delimited block and its `### How to set
these` sibling under a `## Configuration` heading, adding that heading where the plugin lacks one.
Do not edit the generated table.

### C9. Reclassification: a test fixture in the human slice

`plugins/source-control/skills/worktree/fixtures/README.md` is classified `HUMAN` in
`inventory/manifest.tsv`. It is a fixture-tree README documenting a test harness, and its content is
an experiment log (`claude -p stderr was "Not logged in · Please …"`, arm-by-arm trace results).

Reclassify as **out of scope: functional artifact**, matching the category `L1-derivability` used
for the same shape. No authoring doctrine applies, and no edit is proposed. See `README.md` for the
full reclassification set.

### The remaining `L1` sentences in this group

Nine sentences over the filter (45 or more words, 3 or more clause interrupters). Six are in
`plugins/disk-hygiene/README.md` and four of those sit inside the two sections C1 and C2 already
restructure, so they should be handled as part of that restructure rather than separately:

```text
plugins/disk-hygiene/README.md:22
plugins/disk-hygiene/README.md:56
plugins/disk-hygiene/README.md:102
plugins/disk-hygiene/README.md:110
plugins/disk-hygiene/README.md:206
plugins/disk-hygiene/README.md:220
plugins/source-control/README.md:124
plugins/source-control/README.md:134
plugins/source-control/README.md:154
```

## Document mode

Both mode findings in this group are in `plugins/disk-hygiene/README.md` and are filed above as C1
and C2. The pattern they share is worth naming for the orchestrator: **the heading names the process
that produced the content rather than the question the content answers.** `Requirements and platform
support` became a place to record why the requirements are what they are; `Plugin-acceptance
security review` names the review rather than the posture.

`plugins/github/README.md`, `plugins/repo-hygiene/README.md`, and `plugins/source-control/README.md`
each hold one mode cleanly. `plugins/repo-fleet-hygiene/README.md` has the C5 table, which is a
mode mix at table-row granularity rather than at section granularity.

## Predicates with no findings in this group

`A1`, `A2`, `Am2`, `Am4`, `C1`.

On `C1`: every numeric claim in the five plugin READMEs was checked against the tree and all are
correct, consistent with `scripts/check-skill-count-claims.sh` holding.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs.
- **`source-control`**: nothing in this group. The `source-control` plugin's own README is clean on
  every predicate except `M3`.
