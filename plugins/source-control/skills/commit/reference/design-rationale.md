# Commit skill: sources and design rationale

Detail behind [SKILL.md](../SKILL.md): where the type set comes from, the mod that can change
injected commit guidance, the trailer key spelling, and the recorded frontmatter deviation. None of
it changes a step; read it when a rule here is questioned.

## Where the 11 types come from

The 11 types, `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test`, are this
skill's default vocabulary. `security` is not one of them; never add it.

- **Pointer**: when the default type set is questioned, fetch commitlint's
  [config-conventional `type-enum`](https://github.com/conventional-changelog/commitlint/tree/master/%40commitlint/config-conventional#type-enum)
  live. It and Angular's [commit message Type](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md#type)
  disagree on the type set, so cite `type-enum`, never a consensus of sources. **As of**:
  2026-11-10. **Recheck trigger**: `type-enum`'s value changes, or the two sections agree.

## A mod can change the injected commit guidance

Behind "Which authority wins", source 3. A mod can change the commit attribution guidance before
you read it, so absent or unusual injected guidance says nothing about the project's wishes;
sources 1 and 2 still decide.

- **Pointer**: the `attribution.text` row of the
  [mods reference, "Prompts and what Claude reads"](https://code.claude.com/docs/en/plugins/mods/reference#prompts-and-what-claude-reads)
- **As of**: 2026-11-03
- **Recheck trigger**: that row changes or is removed

## Key spelling

This skill emits `Co-authored-by`, the spelling GitHub's co-author documentation uses, so branch
commits and forge-written squash merges agree. It is a consistency choice. The skill never rewrites
the spelling already in history. A consumer who wants a different spelling sets it as a
`trailer_policy` template.

- **Pointer**: GitHub's
  [Creating co-authored commits on the command line](https://docs.github.com/en/pull-requests/committing-changes-to-your-project/creating-and-editing-commits/creating-a-commit-with-multiple-authors#creating-co-authored-commits-on-the-command-line)
- **As of**: 2026-11-03
- **Recheck trigger**: that section changes the trailer key it shows

## Recorded deviations

- **Model invocation stays enabled** (`disable-model-invocation: false`, declared explicitly rather
  than left to the default). The fleet archetype for a `/source-control:commit`-shaped skill is
  `disable-model-invocation: true`. User-invoked only. This skill deliberately deviates because its
  composition design requires the model to reach it: a workflow skill that composes the commit
  mechanic cannot do so if the model may not load it. Compensating controls: surgical staging (never
  `git add -A`), the subject pre-check before any git invocation, no hook bypass, and a
  user-visible SHA + subject report after every commit.
