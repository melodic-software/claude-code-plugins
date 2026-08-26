# L4 encapsulation. Leaked skills in `plugins/evals`

5 violations, all skill-to-skill: `evals:design`'s SKILL.md reaches into `evals:methodology`'s
private `reference/` four times across five cites.

**Owning skill:** `evals:methodology` (`plugins/evals/skills/methodology/`).
**Private surfaces reached:** `reference/success-criteria.md`, `reference/grading.md`,
`reference/recipes.md`, `reference/eval-design.md`.
**Leak kind:** private subdir (5 of 5).
**Citing file:** `plugins/evals/skills/design/SKILL.md`, an always-invocation-loaded T2 surface.

The contract is explicit that sibling skills stay slash-only. This cluster is the clearest instance
in the repo of the reason: `methodology`'s own description says it is "knowledge (WHY/WHAT of eval
design), not a runner; for scaffolding a suite use /evals:design". The two skills are deliberately
paired, and the pairing is currently wired through four private filenames.

## Route or promote

Both remedies are defensible and the choice is per cite:

- **Path B. route** fits V-eval-01, V-eval-02, V-eval-04. `design` is telling the reader where the
  reasoning lives, and `/evals:methodology <question>` is the documented public entry for exactly
  that (its `argument-hint` is `[question or concept]`).
- **Path A. promote** fits V-eval-05, where `design` inlines a prompt skeleton it reads out of
  `methodology`'s grading reference. A skeleton consumed verbatim by a second skill is shared
  vocabulary; move it to `plugins/evals/reference/llm-rubric-skeleton.md` (a plugin-level directory
  outside both skills) and have both cite it.

`plugins/evals/` has no plugin-level `reference/` today; creating one is the same move
`source-control`, `discovery`, `review`, and `work-items` already made.

## Violations

### V-eval-01. `plugins/evals/skills/design/SKILL.md:31`

**Private surface:** `reference/success-criteria.md`.

```text
([success-criteria.md](../methodology/reference/success-criteria.md)):
```

**Replacement text:**

```text
(`/evals:methodology success criteria`):
```

### V-eval-02. `plugins/evals/skills/design/SKILL.md:49`, first cite

**Private surface:** `reference/grading.md`.

```text
([grading.md](../methodology/reference/grading.md), [recipes.md](../methodology/reference/recipes.md)):
```

### V-eval-03. `plugins/evals/skills/design/SKILL.md:49`, second cite

**Private surface:** `reference/recipes.md`. Same line as V-eval-02; one replacement covers both.

**Replacement text for line 49:**

```text
(`/evals:methodology grading methods` and `/evals:methodology eval recipes`):
```

### V-eval-04. `plugins/evals/skills/design/SKILL.md:53`

**Private surface:** `reference/eval-design.md`.

```text
Case authoring ([eval-design.md](../methodology/reference/eval-design.md)):
```

**Replacement text:**

```text
Case authoring (`/evals:methodology eval-suite design`):
```

### V-eval-05. `plugins/evals/skills/design/SKILL.md:66`

**Private surface:** `reference/grading.md`. This is the content dependency, not a pointer.

```text
prompt skeleton from [grading.md](../methodology/reference/grading.md) inlined for `llm_rubric`
```

**Replacement text (post-promotion to `plugins/evals/reference/llm-rubric-skeleton.md`):**

```text
prompt skeleton from [`${CLAUDE_PLUGIN_ROOT}/reference/llm-rubric-skeleton.md`](../../reference/llm-rubric-skeleton.md) inlined for `llm_rubric`
```

**Route-only alternative:**

```text
prompt skeleton `/evals:methodology grading methods` supplies, inlined for `llm_rubric`
```

## Cross-lane observations

- L3 (SSOT): if the `llm_rubric` skeleton is already duplicated between `design` and `methodology`,
  V-eval-05's promotion target is the same artifact L3 would mint. Reconcile to one file.
