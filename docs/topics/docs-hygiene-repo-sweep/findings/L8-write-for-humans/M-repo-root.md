# M-repo-root

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 4 `HUMAN` rows of the group's 10:

```text
README.md
SECURITY.md
prompts/cloud-bootstrap-rollout.md
prompts/loops/loop-lane-prompts.md
```

The other 6 rows in the group are `AGENT` and belong to `L7`.

This is the smallest slice and the most-read one. `README.md` is the first document any person meets
in this repository, so it was read line by line rather than sampled.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| M1 | `README.md:54` | `Am4` | S3 |
| M2 | `SECURITY.md:9` | `A1` | S3 |
| M3 | reclassification | `prompts/**` | n/a |

### M1

`README.md:54` to `:55`, verbatim:

```text
- Not sure which skill to invoke? Start at the [skill cheat sheet](docs/SKILL-CHEAT-SHEET.md). A
  scan-and-go map from what you're doing to the skill to use.
```

Two observations, and only one of them is a finding.

**Not a finding**: `A scan-and-go map from what you're doing to the skill to use.` is a verbless
appositive. It is the same house cadence documented in `A-doc-quality.md`, and the two list items
below it use the identical shape (`Every plugin by category, generated from the manifests and kept
in sync by CI.` and `The category vocabulary the catalog is grouped by.`). Three consecutive items
in one parallel construction is deliberate, and the address layer's own rule is to keep list items
parallel. Leave it.

**The finding**, predicate `Am4`, is `the skill to use`. Read once, `to use` attaches to `the skill`
and the phrase means "the skill you should use". Read again, `from what you're doing to the skill`
is a from-X-to-Y construction and `to use` dangles. The sentence resolves on the second reading,
which is exactly the cost this predicate exists to remove.

Replacement:

```text
- Not sure which skill to invoke? Start at the [skill cheat sheet](docs/SKILL-CHEAT-SHEET.md). A
  scan-and-go map from what you are doing to the skill that does it.
```

Filed at S3. The line is understood on a second pass and the cost is small, but this is line 54 of
the repository's front door.

### M2

`SECURITY.md:9`, verbatim:

```text
Please do **not** report security vulnerabilities through public GitHub issues, discussions, or pull requests.
```

And `SECURITY.md:18`:

```text
Please include enough detail to reproduce and assess the issue: the affected plugin and version (from its
```

Predicate `A1`. The address layer says no `please` in instructions, and both of these are
instructions.

**Filed at S3 with no edit recommended**, and the reason matters more than the finding. `SECURITY.md`
is a GitHub community-health file addressed to an external reporter who owes this project nothing,
often a stranger doing the project a favour. `Please` is doing real work there: it marks a request
rather than a command, which is the correct register for asking a volunteer to withhold a disclosure.
The resolved guide's own improve-it-anyway test settles it. Removing `please` would not improve the
document; it would make it colder to exactly the reader it needs to keep.

Recorded so a later pass does not "fix" it, and so the exemption is visible as a decision rather
than as an oversight.

The same file uses Title Case headings (`Reporting a Vulnerability`, `Supported Versions`) where the
rest of the repository uses sentence case. Also not a finding: this repository declares no heading
rule (see `standard-resolution.md`, override 7), and Title Case is the GitHub community-health
convention this file is written to.

### M3. Reclassification: `prompts/**` is agent-facing

Both files are classified `HUMAN`. Both are prompt templates, and the repository's own `README.md:70`
says what they are, verbatim:

```text
- `prompts/`, launch-prompt templates meant to be filled in and pasted into a session; unlike
  `lib/`, nothing copies them, and plugin skills cite them by path.
```

A launch-prompt template is filled in by a person and then read by a **model**. Its wording is
instruction to an agent, and its register, its imperatives, and its structure should be judged
against `write-for-agents` doctrine, not `write-for-humans`.

`prompts/loops/loop-lane-prompts.md:1` confirms it from the other side:

```text
Reusable templates for the three-lane topology, plus one on-demand attended
template (3b) for the parked-decision states the standing lanes deliberately
exclude. Fill the variables, paste a block.
```

**Reclassify both to `AGENT`, routing to `L7-write-for-agents`.**

Each file has a human-facing preamble (the "Why this layout" section in
`cloud-bootstrap-rollout.md`, the ownership table in `loop-lane-prompts.md`) that is genuinely
addressed to the operator filling the template in. If the orchestrator prefers a split
classification, the seam is the first fenced prompt block in each file. This lane's recommendation is
the simpler whole-file reclassification, because the preambles are short and both lanes' doctrine
agrees about them.

`prompts/cloud-bootstrap-rollout.md` carries 7 of this group's `L1` hits and
`prompts/loops/loop-lane-prompts.md` carries the group's heaviest em-dash density (311). Both move
with the files.

## Document mode

### `README.md` is correct

Mode: **how-to**, with a reference section. The structure earns that reading:
`## Use this marketplace` gives the two commands, `## Finding your way` points at the reference
documents rather than inlining them, `## What's here` is a directory reference, and
`## Validate a change` is a second how-to addressed to a contributor.

The one thing worth naming as a strength, since this file sets the pattern the plugin READMEs
follow: `## Finding your way` links out to `docs/SKILL-CHEAT-SHEET.md`, `docs/CATALOG.md`, and
`docs/CATALOG-TAXONOMY.md` instead of reproducing them. That is the skill's "split and link instead"
rule applied correctly, and it is why this file has no `M1` finding despite serving two audiences.

The contributor-facing `## Validate a change` section serves a different reader from the rest of the
document. That is the same two-audience question raised in `H-knowledge-research.md` and
`J-toolchain-platform.md`. It is **not** filed here: a repository root README is conventionally
addressed to both a consumer and a contributor, and the section is clearly headed. Recorded for
consistency with the other two groups.

### `SECURITY.md` is correct

Mode: **how-to** (`## Reporting a Vulnerability`, two numbered steps, condition first) plus
**reference** (`## Supported Versions`). Two modes in one document, split by heading, with no
mixing inside either section. That is the correct handling, not a violation.

## Predicates with no findings in this group

`M1` as its own finding, `M2`, `M3`, `A2`, `L1`, `Am1`, `Am2`, `Am3`, `N1`, `C1`.

On `C1`: `README.md` makes no numeric claim about plugin or skill counts anywhere, which is the
right call for a file that would go stale on every plugin added. It points at the generated
`docs/CATALOG.md` instead. This is the skill's third survives-the-guide rule followed by
construction rather than by enforcement.

On `L1`: zero sentences over the filter in `README.md` and `SECURITY.md`. The seven hits in this
group are all in `prompts/cloud-bootstrap-rollout.md`, which M3 reclassifies out.

## Cross-lane observations

- **`ai-slop:audit`**: `SECURITY.md:3` carries a pair of em dashes:

  ```text
  This marketplace distributes plugins — skills, hooks, and agents — that run code on a consumer's machine and
  ```

  `SECURITY.md` is not in the scope `.claude/rules/vendor-docs-are-not-style.md` declares
  (`SKILL.md`, plugin READMEs, `AGENTS.md`, `CLAUDE.md`, `.claude/rules/**`), so whether this is in
  policy is `ai-slop:audit`'s call, not this lane's.
- **`source-control`**: nothing in this group.
