# F-quality-verify

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 18 `HUMAN` rows (9 plugin READMEs,
9 CHANGELOGs). The 9 CHANGELOGs are judged as a class in `README.md`.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| F1 | `plugins/review/README.md:30` | `Am1` | S1 |
| F2 | `plugins/review/README.md:31` | `Am1` | S1 |
| F3 | `plugins/review/README.md:34` | `Am1` | S1 |
| F4 | `plugins/verification/README.md:44` | `Am1` | S2 |
| F5 | `plugins/bugs/README.md:127` | `M3` | S2 |

### F1 to F3. Three broken parentheticals in one list item

`plugins/review/README.md:28` through `:35`, verbatim:

```text
- **`/review:quality-gate [mode]`**, the single-lens checkpoint between "code works"
  and "code is ready". Modes: `self` (fresh-context self-review), `code`, `architecture`,
  `security`, `spec` (spec-fidelity. Did the change deliver what the originating item, plan, or
  brief asked for), `close-out` (the same fidelity lens at spec-container scale. One cumulative
  pass over everything a container shipped, across however many PRs, against the container's own
  body; derives its own diff basis per execution shape), `downstream` (what the change breaks
  outside its own diff. Callers, serialization boundaries, cross-service consumers), `pr`,
  `criteria`, `slice <name>`, `restatement`.
```

Predicate `Am1` three times. `(fresh-context self-review)` is correct: a noun phrase, no internal
period. The three that follow each end a sentence inside the parenthesis after a fragment.

The deeper problem is `M1`. This is a mode list, which is reference content, packed into a bullet
inside a skills list. Nine modes are named and three of them get a gloss, so the reader cannot tell
whether the other six have no gloss or whether it was omitted.

Replacement, splitting the reference out of the bullet:

```text
- **`/review:quality-gate [mode]`**, the single-lens checkpoint between "code works"
  and "code is ready".

  | Mode | Lens |
  |---|---|
  | `self` | Fresh-context self-review |
  | `code` | Correctness in the diff |
  | `architecture` | Structure and boundaries |
  | `security` | Security exposure in the diff |
  | `spec` | Spec fidelity: did the change deliver what the originating item, plan, or brief asked for |
  | `close-out` | The same fidelity lens at spec-container scale: one cumulative pass over everything a container shipped, across however many PRs, against the container's own body. Derives its own diff basis per execution shape |
  | `downstream` | What the change breaks outside its own diff: callers, serialization boundaries, cross-service consumers |
  | `pr` | Review of an open pull request |
  | `criteria` | The container's acceptance criteria |
  | `slice <name>` | One named slice of the change |
  | `restatement` | Restates the change back for confirmation |
```

**Wave 3 must verify the glosses I supplied for `code`, `architecture`, `security`, `pr`,
`criteria`, `slice`, and `restatement` against `plugins/review/skills/quality-gate/SKILL.md` before
applying.** They are not in the README today, so they are not quotes, and the resolved guide's
meaning-preservation rule forbids inventing claims during a fix pass. If a gloss cannot be
confirmed from the skill body, leave that cell empty rather than guessing. The three glosses taken
verbatim from the original (`spec`, `close-out`, `downstream`) are safe as written.

If wave 3 judges the table too large a change for a prose pass, the minimum fix is `Am1` alone:
replace each internal period with a colon or a comma and keep the bullet.

### F4

`plugins/verification/README.md:44`, verbatim:

```text
Artifact placement is governed by the tracked `.claude/topic-docs.yaml` concern file
(`/verification:setup` interviews for and persists it. `check` reports the effective
concern read-only, `apply` writes it). This plugin declares no userConfig options.
```

Predicate `Am1`. Both halves of the parenthetical are complete clauses, so this is milder than F1 to
F3, but the parenthetical as a whole is not a grammatical unit: it opens mid-sentence and closes
after a second independent sentence.

Also `A1`: the lead is passive with no actor (`Artifact placement is governed by`), where the actor
is known and named two words later.

Replacement:

```text
The tracked `.claude/topic-docs.yaml` concern file governs artifact placement.
`/verification:setup` interviews for that file and persists it: `check` reports the effective
concern read-only, and `apply` writes it. This plugin declares no userConfig options.
```

### F5. The generated options block is not under `## Configuration`

`plugins/bugs/README.md:127`. The block sits under `## Install`, starting at line 137. Predicate
`M3`. Remediation as in `B-cc-config-ops.md`.

This is the third `## Install` outlier in the corpus (`guardrails`, `github`, `bugs`), which
suggests a shared origin rather than three independent slips. Wave 3 should fix all three the same
way.

### The remaining `L1` sentence in this group

One sentence over the filter:

```text
plugins/evals/README.md:10
```

`plugins/review/README.md:71` was measured at 61 words but is exempt: the bulk of it is a verbatim
quotation from the Claude Code docs, which the resolved guide's legitimate-hit class 1 protects.
Wave 3 must not rewrite inside those quotation marks.

## Document mode

Eight of the nine plugin READMEs in this group hold one mode cleanly: reference, with a short
explanation lead and a skills table.

`plugins/review/README.md` is the exception and it is filed as F1 to F3: a reference table
(the mode list) is inlined into a bullet inside the skills list, which is the skill body's named
anti-pattern ("No reference tables inside a tutorial, no hand-holding inside reference").

`plugins/tdd/README.md:16` describes a routing table over fourteen author-attributed reference
files. That is a reference document pointing at reference documents, which is correct, not mixed.
No finding.

## Predicates with no findings in this group

`M2`, `A1` as its own finding, `A2`, `Am2`, `Am3`, `Am4`, `N1`, `C1`.

On `M2`: `plugins/review/README.md:17` uses `no longer` in a row describing what the
`doc-drift-detector` agent looks for (`Documentation that no longer matches the code`). That is the
agent's subject matter, not this README's release history. Not a finding.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs.
- **`source-control`**: nothing in this group.
