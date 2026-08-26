# L2 progressive disclosure: `M-repo-root`

10 files: repo root, `.claude/`, `.github/`, `prompts/`. All three `T1` files in the corpus live
here.

Totals: T1=1, T2=1, T3=3.

## The always-loaded tier

Three files, 466 bytes total, and two of them are empty or near-empty:

| Path | Bytes | Lines | Content |
|---|---|---|---|
| `AGENTS.md` | 0 | 0 | empty |
| `CLAUDE.md` | 11 | 1 | `@AGENTS.md` |
| `.claude/rules/vendor-docs-are-not-style.md` | 455 | 10 | one rule, no `paths:` frontmatter |

The always-loaded budget is already near zero. Per the sweep plan, that is reported and not
treated as a defect.

### Tier 3, awareness only: the `@AGENTS.md` indirection is a no-op

`CLAUDE.md:1`:

> `@AGENTS.md`

The tier model records that `@path` imports do not reduce cost against inlining, so a one-line
`CLAUDE.md` importing a zero-byte `AGENTS.md` costs the same as an empty `CLAUDE.md` and buys the
cross-tool `AGENTS.md` filename. That is a deliberate compatibility choice, not a disclosure
defect. No treatment. Recorded so a later lane does not read the empty `AGENTS.md` as an accident.

### Tier 3, awareness only: `vendor-docs-are-not-style.md` is scope-mismatched but correctly so

`.claude/rules/vendor-docs-are-not-style.md:5-9`:

```text
Docs under `plugins/*/skills/*/vendor/**` are upstream reference material.
Do not copy their formatting, including em dashes, into this repo's own
instruction surfaces (`SKILL.md`, plugin READMEs, `AGENTS.md`, `CLAUDE.md`,
`.claude/rules/**`).
```

The rule has no `paths:` frontmatter, so it is always-loaded, and its content applies only when
writing markdown prose. Anthropic's scope-mismatch routing rule would send it to a path-scoped
rule (`paths: ["**/*.md"]`), demoting it from always-loaded to invocation-loaded.

**No treatment, and this is a deliberate non-finding.** The rule costs roughly 120 tokens, and the
demotion has a real downside: the rule binds an agent that has *read* a vendored file and is about
to write prose elsewhere, which a `paths:` glob on the write target would still catch but a
narrower one would not. Trading a certain 120 tokens for a conditional load of a rule whose whole
job is to bind every prose author is not a good trade at this budget. Recorded because the routing
rule technically applies and a future reader should see that it was considered rather than missed.

## Split lane

### `mixed-concerns` + `missing-toc`: `prompts/loops/loop-lane-prompts.md` (Tier 2)

**1,961 lines**, the longest file in the corpus. `T3`, so no session cost, but the file
contradicts its own stated scope.

`prompts/loops/loop-lane-prompts.md:3-6`:

> `Reusable templates for the three-lane topology, plus one on-demand attended`
> `template (3b) for the parked-decision states the standing lanes deliberately`
> `exclude. Fill the variables, paste a block. Nothing below is specific to one`
> `repository except the profile you fill in yourself.`

Two of its 14 H2 sections are that exception, and they are 775 lines, 40% of the file:

| Line | Heading | Span |
|---|---|---|
| 1,187 | `## Profile: melodic-software/claude-code-plugins` | 1,187 to 1,293 |
| 1,294 | `## Ready to paste — melodic-software/claude-code-plugins` | 1,294 to 1,961 |

`prompts/loops/loop-lane-prompts.md:1189`:

> `Filled instance for the repository in use as of 2026-07-25.`

A reader adopting the templates for a different repository (the case `## Adopting a new
repository` at line 244 exists to serve) reads 775 lines of one repo's filled values before
reaching the end. The template concern and the instance concern are one topic per file apart.

**Split spec.**

New file: `prompts/loops/loop-lane-profile-claude-code-plugins.md`

Moves: lines 1,187 to 1,961 verbatim, the first H2 promoted to H1
`# Loop-lane profile: melodic-software/claude-code-plugins`, the second kept as an H2, and a
`## Contents` list added at the top.

Replaces lines 1,187 to 1,961 in `loop-lane-prompts.md` with:

```markdown
## Filled profiles

This file stays repository-agnostic. A filled instance lives in its own file next to it:

- [`loop-lane-profile-claude-code-plugins.md`](loop-lane-profile-claude-code-plugins.md). Read it
  when launching a lane against `melodic-software/claude-code-plugins`, or as a worked example of
  a completed profile. It carries the filled variable table and the ready-to-paste launch blocks
  for that repository only.

Adopting a different repository: follow "Adopting a new repository" above, then write a sibling
profile file rather than editing this one.
```

Resulting `loop-lane-prompts.md`: 1,961 - 775 + 13 = **1,199 lines**, and its opening claim at
line 5 becomes true.

## Structure lane

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `prompts/loops/loop-lane-prompts.md` | 1,961 |

14 H2 sections, no `## Contents`. The file's own line 13 sends the reader to a named subsection
("see 'Raw intake has two unserialized owners' under Known gaps") with no way to reach it.

Remediation: insert a `## Contents` anchor list after the opening paragraph (after line 6) and
before the ownership table at line 8, listing every H2 including the per-lane H3s under
`## 1 — Worker lane`, `## 2 — Merge lane`, `## 3 — Attended queue`, and
`## 3b — Parked-decision burn-down`. Apply **after** the profile split above so the list does not
need regenerating.

### Not findings

`README.md` (135 lines), `REVIEW.md` (111), `prompts/cloud-bootstrap-rollout.md` (176),
`.claude/source-control.md` (44), `.github/pull_request_template.md` (38), and `SECURITY.md` (27)
are all inside the 100 to 300 awareness band or below it, and none is reference-shaped enough for
the band to matter. `.claude/source-control.md` is a config file with a header comment, not a
disclosure surface.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

3 files. No treatment.

## Cross-lane observations

- `prompts/loops/loop-lane-prompts.md` and `docs/conventions/loop-lane/README.md` (group
  `K-repo-docs`) both describe the three-lane topology and its ownership table. L3.
- `prompts/loops/loop-lane-prompts.md:1189` carries an as-of date on a filled profile
  (`as of 2026-07-25`) with no recheck trigger. Whether a dated instance file earns its existence
  is L1.
