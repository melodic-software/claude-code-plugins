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
rung: editorconfig-severity | analyzer-pack-rule | custom-analyzer | semgrep-rule | architecture-test | hook | llm-only
owner: <invocation, plugin name, or URL>
---

## Finding

<Location, Tier, Confidence, Surface(s), Finding, Action, verbatim, pipes unescaped>

## Proposed rung

<one paragraph: the rung, why this class lands there, what the check would assert>

## Next step

<the gated invocation or the pointer, with the fallback when the plugin is absent>

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

## Filename

`<rank, two digits>-<rung>-<slug>.md`, where `<slug>` is the first 40 characters of the row's
`Location` lowercased with every character outside `[a-z0-9._-]` replaced by `-`. An existing
path is never overwritten: the writer takes `-2`, then `-3`, and so on.

## What the writer fills and what it does not

The writer is deterministic. It renders the row's cells verbatim (pipes unescaped), and it
renders the rung, class, basis, and owner it was handed on the classification TSV. The judgment
that produced those four values belongs to the skill body's derivation ladder, not to the
writer, and the skill's in-conversation report carries the reasoning. A stub is therefore
reproducible from the same findings file plus the same TSV.
