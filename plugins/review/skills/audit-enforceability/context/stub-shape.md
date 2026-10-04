# Stub shape

The shape `scripts/emit-stubs.sh` writes, one file per finding row.

```markdown
---
type: enforceability-stub
date: <ISO-8601 UTC, the write instant>
source-findings: <file name>
source-sha256: <first 12 hex of the findings file's content digest>
source-branch: <the findings file's branch: value>
rank: <Rank>
finding-class: <class>
class-basis: rule-id | rule-family | dimension | judgment | unresolved
rung: make-impossible | editorconfig-severity | analyzer-pack-rule | custom-analyzer | semgrep-rule | architecture-test | hook | llm-only
earliest-stage: design | edit | build | commit | test | tool-call | review
owner: <invocation, plugin name, or URL>
---

## Finding

<Location, Tier, Confidence, Surface(s), Finding, Action, verbatim, pipes unescaped>

## Proposed rung

<one paragraph: the rung, why this class lands there, what the check would assert>

## Error text

<the sixth TSV field: one line the check would print, naming the fix; "none proposed" when absent or empty>

## Next step

<the gated invocation or the pointer, with the fallback when the plugin is absent>

## Ratchet offer

<present only on a counting rung while the offer is on: a non-zero violation count goes to /review:ratchet; a zero count lands the rule>

## Not done here

This stub proposes. Nothing was implemented.
```

## Forbidden markers

A stub carries none of these, and the writer refuses (removing every stub it wrote that run)
when one reaches a written file:

| Marker | Why it is forbidden |
|---|---|
| `type: review-findings` | The fix action's admission test. A stub carrying it is offered to the fix pass as a real findings file. |
| `type: fix-pass-record` | The consumption ledger's marker. A stub carrying it subtracts real findings from a later merge set. |
| A top-level `branch:` key | The second half of the admission test. The stub records the source branch as `source-branch:` instead, which nothing scans for. |
| A `## Findings` heading | The table anchor every findings reader parses. |

The `type:` marker is the load-bearing exclusion. The writer's home refusals (a stub home
inside the fix action's scan directory, a stub home inside the input file's own directory, a
home carrying a `..` segment, a home outside `--memory-root` when the caller composed the path,
and a last path segment outside the branch-slug charset `[a-z0-9._-]`) are defense in depth on
top of it, not a substitute for it. The two sibling refusals ask the filesystem first, by device and inode, about
the part of each path that already exists, then compare only the unresolved
tails under a spelling fold coarser than any filesystem's case fold. Existence
decides which half answers: two directories the filesystem can already tell
apart are not folded together, because one directory can still be addressed by
more than one absolute path and comparing those spellings as strings would
report "not within" for the very case the fence exists to catch, while folding
them before asking would refuse distinct siblings the filesystem has already
named.

## Earliest stage

The writer derives `earliest-stage` from the rung with this fixed table. It names the first
point in the change's life at which the rung's check can run, so a reader sees how early the
finding would have been caught.

| Rung | Earliest stage |
|---|---|
| `make-impossible` | `design` |
| `editorconfig-severity` | `edit` |
| `analyzer-pack-rule` | `build` |
| `custom-analyzer` | `build` |
| `semgrep-rule` | `commit` |
| `architecture-test` | `test` |
| `hook` | `tool-call` |
| `llm-only` | `review` |

A rung outside the table is refused: the run stops with exit 2, names the TSV line and the value,
and writes nothing. An empty rung field takes the `llm-only` default.

## When a stub carries the ratchet offer

The writer's `--ratchet-offer` flag takes `on` or `off`; absent means `on`, and any other value
exits 2 before anything is written. Under `on`, the section appears on the five counting rungs,
whose check reports how many places violate it: `editorconfig-severity`, `analyzer-pack-rule`,
`custom-analyzer`, `semgrep-rule` and `architecture-test`. `make-impossible` removes the state
rather than counting it, and `hook` and `llm-only` produce no count, so those stubs never carry it.
Under `off`, no stub carries it. The section is one fixed paragraph: once the rule exists, a count
above zero goes to `/review:ratchet` as a CI ceiling, and a count of zero lands the rule with no
ceiling.

## Filename

`<rank, two digits>-<rung>-<slug>.md`, where `<slug>` is the first 40 characters of the row's
`Location` lowercased with every character outside `[a-z0-9._-]` replaced by `-`. An existing
path is never overwritten: the writer takes `-2`, then `-3`, and so on.

## What the writer fills and what it does not

The writer is deterministic. It renders the row's cells verbatim (pipes unescaped), and it
renders the class, basis, rung, owner, and error text it was handed on the classification TSV;
the earliest stage comes from the table above. The judgment that produced the TSV values
belongs to the skill body, not to the writer, and the skill's in-conversation report carries the
reasoning. A stub is therefore reproducible from the same findings file plus the same TSV.

The writer splits each TSV line on tabs itself, so an empty field keeps its position and takes
its default (`unclassified`, `unresolved`, `llm-only`, `none`, or `none proposed` for the error
text) without shifting the fields after it. A line with other than five or six fields, or whose
first field is not a rank the `## Findings` table carries, or whose rung is outside the table
above, stops the run with exit 2 and the line
number before anything is written. That is how a tab inside the error text (seven fields) and a
newline inside it (a continuation line with one field, even one that starts with a digit) are
caught. Fully empty lines are skipped.
