# L5-noise: `scope-meta`

**3 candidates in. 0 findings out. 3 rejected. Plus a recall check, no additions.**

All 3 read in full.

## Rejections

| Path and line | Grounds |
|---|---|
| `plugins/docs-hygiene/skills/audit-noise/SKILL.md:57` | shape self-definition, the row that names the cues |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md:8` | detector eval fixture, corpus-excluded |
| `docs/NATIVE-SURFACES.md:35` | describes a product behavior, not this file's loading mechanics |

### `docs/NATIVE-SURFACES.md:35`

Verbatim, in an evidence bullet under an `/export` verdict:

```text
  - output written to user paths sits outside the cleanupPeriodDays retention sweep (path-scoped to ~/.claude), which is the durability property the suggestions exist for
```

The shape targets body prose restating **this file's own** loading mechanics, which frontmatter or
config already owns. The cue here describes the scope of Claude Code's `cleanupPeriodDays`
retention sweep, an external product behavior, and it is the load-bearing half of the evidence:
the sweep's path scope is exactly why writing outside `~/.claude` is durable. Strip the
parenthetical and the bullet stops supporting its own conclusion.

## Recall check

A corpus-wide grep over all 1218 scanned files:

```text
path-scoped to
loads on Read of
auto-loads when
auto-loaded when
this file loads when
scoped to ... via frontmatter
```

returns the same two non-fixture hits already adjudicated above. No recall gap in this shape, and
no instance anywhere in the corpus of body prose restating a file's own frontmatter scoping.

## Observation

Zero real instances in 1218 files is itself a result: the repo does not narrate its own loading
mechanics in prose. Worth recording so a later sweep does not re-derive it.

## Cross-lane observations

- **L2-progressive-disclosure.** L2 owns tier-mismatch and what belongs in an always-loaded file.
  This lane found nothing that describes its own tier in prose, so there is no overlap to
  reconcile.
- **L1-derivability, L3-ssot, L6-compress.** Nothing.
