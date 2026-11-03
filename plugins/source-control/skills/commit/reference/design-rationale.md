# Commit skill: sources and design rationale

Detail behind [SKILL.md](../SKILL.md): where the type set comes from, the mod that can change
injected commit guidance, the trailer key spelling, and the recorded frontmatter deviation. None of
it changes a step; read it when a rule here is questioned.

## Where the 11 types come from

The 11 types. `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test`. Come from
the Conventional Commits spec, the Angular convention, commitlint's `@commitlint/config-conventional`
source, and `amannn/action-semantic-pull-request`'s default `types` list; all four agree on this exact
set. `security` is **not** a Conventional Commits type in any of them, never add it.

## A mod can change the injected commit guidance

Behind "Which authority wins", source 3. A mod can rewrite or blank that guidance before you see
it: its `attribution.text` hook receives the commit trailer (`kind: commit`) and the PR footer
(`kind: pr`) as the engine composed them and returns the text the model reads instead. So absent
or unusual injected guidance says nothing about the project's wishes; sources 1 and 2 still decide.
(Claim: the event and its kinds. Basis:
[mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
"Prompts and what Claude reads", `attribution.text` row, fetched 2026-10-01, and the
`AttributionTextKind` type in the built-in `plugin-authoring` skill's `claude-code.d.ts` for
Claude Code 2.1.287. As of: 2026-10-01. Recheck: the row or the type changes.)

## Key spelling

**Key spelling.** This skill emits `Co-authored-by`, the spelling GitHub's own documentation uses
exclusively and the one GitHub itself writes when it appends co-author trailers to a squash-merge
message. GitHub's attribution is not case-sensitive in practice (a commit carrying a
`Co-Authored-By:` trailer resolves its co-author in the GraphQL `Commit.authors` connection just the
same; the docs do not state case sensitivity either way), so this is a consistency choice, not a
correctness one: branch commits and the forge-written squash merges agree. Git preserves a trailer
key's case verbatim (`git interpret-trailers` does not normalize it, and no `trailer.*` config here
changes that), so existing history keeps whatever spelling it was written with; this skill never
rewrites it. A consumer who wants a different spelling expresses it as a `trailer_policy` template.

## Recorded deviations

- **Model invocation stays enabled** (`disable-model-invocation: false`, declared explicitly rather
  than left to the default). The fleet archetype for a `/source-control:commit`-shaped skill is
  `disable-model-invocation: true`. User-invoked only. This skill deliberately deviates because its
  composition design requires the model to reach it: a workflow skill that composes the commit
  mechanic cannot do so if the model may not load it. Compensating controls: surgical staging (never
  `git add -A`), the subject pre-check before any git invocation, no hook bypass, and a
  user-visible SHA + subject report after every commit.
