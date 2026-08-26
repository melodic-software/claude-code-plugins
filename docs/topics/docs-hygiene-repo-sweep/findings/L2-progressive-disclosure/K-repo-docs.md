# L2 progressive disclosure: `K-repo-docs`

89 files, 0 `T2`, all `HUMAN`. Surfaces: `docs/adr`, `docs/conventions`, `docs/specs`,
`docs/upstream`, `docs/` root.

Totals: T1=15, T2=2, T3=1. (`T2`: the `MIGRATION-PLAYBOOK.md` split and the missing `docs/README.md`.)

Every file here is `T3`, so nothing in this group carries an invocation-loaded cost and `oversize`
cannot fire. The findings are structural: the group holds the corpus's two largest reference docs
and its densest concentration of untabled long files.

## Split lane

### `mixed-concerns` + `tier-mismatch`: `docs/MIGRATION-PLAYBOOK.md` (Tier 2)

1,738 lines, 27 H2 sections. The file's own opening states one purpose:

`docs/MIGRATION-PLAYBOOK.md:3-5`:

> `How skills, hooks, and agents become reusable plugins in this marketplace. One plugin is migrated at a`
> `time: lift it out, make it work in plugin form and in any repo, build in configuration and extensibility,`
> `vet it against best practices, then publish.`

**Six of its 27 sections are not that.** They are dated decision records:

| Line | Heading | Span |
|---|---|---|
| 1,473 | `## Shared code across plugins — decision record (2026-07-04)` | 1,473 to 1,545 |
| 1,555 | `## Deferred surfaces — decision record (2026-07-12)` | 1,555 to 1,585 |
| 1,586 | `## Unused official plugin components — decision record (2026-07-12)` | 1,586 to 1,623 |
| 1,624 | `## Knowledge-corpus consuming repo + integration flow — decision record (2026-07-13)` | 1,624 to 1,664 |
| 1,665 | `##`skill-quality`retrofit scope — decision record (2026-07-13)` | 1,665 to 1,693 |
| 1,694 | `## Convention-seam ratification & the shared-identity limitation — decision record (2026-07-23)` | 1,694 to 1,738 |

266 lines, 15% of the file. This repo already owns a surface for exactly this content:
`docs/adr/` holds 17 numbered decision records with a settled naming grammar
(`0001-defer-gitbook-as-knowledge-vault-backend.md` through
`0017-ship-the-product-code-lane-as-its-own-skill.md`). Anthropic's kind-mismatch routing rule
sends content to the surface whose kind it matches; a dated decision record inside a procedure
document is that mismatch.

**Split spec.** Six new files under `docs/adr/`, continuing the existing numbering from `0018`:

| New path | Moves |
|---|---|
| `docs/adr/0018-share-code-across-plugins-by-vendoring-not-a-shared-package.md` | lines 1,474 to 1,545 |
| `docs/adr/0019-defer-the-named-plugin-surfaces-until-demand-appears.md` | lines 1,556 to 1,585 |
| `docs/adr/0020-ship-no-plugin-component-the-marketplace-does-not-use.md` | lines 1,587 to 1,623 |
| `docs/adr/0021-consume-the-knowledge-corpus-from-a-separate-repository.md` | lines 1,625 to 1,664 |
| `docs/adr/0022-scope-the-skill-quality-retrofit-to-new-and-touched-skills.md` | lines 1,666 to 1,693 |
| `docs/adr/0023-ratify-convention-seams-and-accept-the-shared-identity-limit.md` | lines 1,695 to 1,738 |

Each new file keeps the original H2's title text as its H1 with the date preserved, and follows
the frontmatter and section shape of `docs/adr/0017-ship-the-product-code-lane-as-its-own-skill.md`.
Titles above are the ADR grammar's imperative form; if the applying agent judges any of them a
misreading of the record's actual decision, take the title from the record's own conclusion rather
than from this table.

Replaces lines 1,473 to 1,738 in `MIGRATION-PLAYBOOK.md` with one section:

```markdown
## Decision records

Decisions that shaped this playbook live in [`adr/`](adr/), one file each, and are not restated
here. Read the record when you are about to reopen the decision it settled, not while following
the playbook:

- [ADR 0018](adr/0018-share-code-across-plugins-by-vendoring-not-a-shared-package.md), sharing code
  across plugins (2026-07-04).
- [ADR 0019](adr/0019-defer-the-named-plugin-surfaces-until-demand-appears.md), deferred surfaces
  (2026-07-12).
- [ADR 0020](adr/0020-ship-no-plugin-component-the-marketplace-does-not-use.md), unused official
  plugin components (2026-07-12).
- [ADR 0021](adr/0021-consume-the-knowledge-corpus-from-a-separate-repository.md), knowledge-corpus
  consuming repo and integration flow (2026-07-13).
- [ADR 0022](adr/0022-scope-the-skill-quality-retrofit-to-new-and-touched-skills.md),
  `skill-quality` retrofit scope (2026-07-13).
- [ADR 0023](adr/0023-ratify-convention-seams-and-accept-the-shared-identity-limit.md),
  convention-seam ratification and the shared-identity limitation (2026-07-23).
```

Resulting `MIGRATION-PLAYBOOK.md`: 1,738 - 266 + 24 = **1,496 lines**, and every remaining section
is playbook procedure.

This split is inbound-reference heavy: `MIGRATION-PLAYBOOK.md` is cited from many plugin
CHANGELOGs and from `docs/PLUGIN-PHILOSOPHY.md`. None of those citations target the moved
sections by anchor as far as this pass could tell, but the applying agent must re-check anchors
before cutting, and L4 owns any citation rewrite that falls out.

## Structure lane

### `missing-toc` (Tier 1)

15 files above 300 lines with no table of contents, the second-largest concentration in the
corpus after `I-songwriting`.

| Path | Lines |
|---|---|
| `docs/MIGRATION-PLAYBOOK.md` | 1,738 |
| `docs/PLUGIN-PHILOSOPHY.md` | 1,096 |
| `docs/conventions/loop-lane/README.md` | 805 |
| `docs/conventions/detector-findings/README.md` | 639 |
| `docs/conventions/topic-docs/README.md` | 637 |
| `docs/upstream/aihero-course.md` | 488 |
| `docs/upstream/aihero-shipping-course.md` | 475 |
| `docs/adr/0004-rightsize-instruction-surfaces-by-incumbent-first-arbitration.md` | 465 |
| `docs/specs/dead-code-detector-landscape.md` | 438 |
| `docs/adr/0005-bound-instruction-surface-work-by-question-not-population.md` | 426 |
| `docs/specs/d1-model-already-knows-measurement.md` | 419 |
| `docs/specs/dead-code-lsp-viability.md` | 385 |
| `docs/conventions/upstream-drift/README.md` | 374 |
| `docs/CLOUD-SESSIONS.md` | 326 |
| `docs/adr/0002-default-on-ai-review-advisory-with-earned-promotion.md` | 315 |

`docs/MIGRATION-PLAYBOOK.md` and `docs/PLUGIN-PHILOSOPHY.md` are the two worst in the corpus after
the songwriting research files: 2,834 lines between them, 42 H2 sections, no way in except from
the top. Both are cited across the whole repo as the authority on one narrow question at a time
(`docs/MIGRATION-PLAYBOOK.md:6-7` sends the reader to `PLUGIN-PHILOSOPHY.md` and back), which is
the lookup access pattern the tier model says a TOC or a grep recipe serves better than a full
read.

The three `docs/conventions/*/README.md` files are the second cluster: every convention is cited
by name from skill bodies across the corpus, so each README is entered looking for one clause.

Remediation, all fifteen: insert a `## Contents` anchor list under the H1, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. For
`MIGRATION-PLAYBOOK.md` and `PLUGIN-PHILOSOPHY.md`, make the list two levels deep (H2 and H3) so a
reader can reach a named subsection. Apply the `MIGRATION-PLAYBOOK.md` TOC **after** the decision
record split above, so the list does not have to be regenerated.

### `missing-toc`: `docs/` has no index (Tier 2)

`docs/` holds 12 top-level `.md` files plus five subdirectories (`adr`, `conventions`,
`native-surfaces`, `specs`, `topics`, `upstream`) and contains no `README.md`. Files are cited
individually from all over the repo, so a reader who does not already know the filename has no
listing.

`docs/CATALOG.md`, `docs/GLOSSARY.md`, and `docs/OFFICIAL-DOCS.md` each index one thing, but none
indexes `docs/` itself.

Remediation: add `docs/README.md`, one row per top-level file and per subdirectory, each row
carrying a read-when clause rather than a description. Keep it a pure index; it owns no facts, so
it does not become a maintenance surface of its own. This is a new file, not a split, so it moves
no existing path and creates no dependency for the L3 or L4 lanes.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

31 files. No treatment.

## Cross-lane observations

- `docs/MIGRATION-PLAYBOOK.md:9-15` carries a paragraph of dated verification stamps
  ("verified against the official docs on 2026-06-22 ... on 2026-06-29 ... on 2026-07-12"). That
  is provenance prose in a human-facing doc. L5 or L8.
- `docs/conventions/loop-lane/README.md` and `prompts/loops/loop-lane-prompts.md` (group
  `M-repo-root`) both describe the three-lane topology. L3.
- Whether the two `docs/upstream/aihero-*.md` course notes earn their existence in this repo is an
  L1 question.
