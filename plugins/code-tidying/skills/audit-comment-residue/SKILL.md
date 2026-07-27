---
name: audit-comment-residue
description: "Classify code comments for four residue shapes — history narration (\"used to… now…\"), plan/session references (\"Task 2 replaces the old…\", \"in this PR\"), conversational antecedents (\"per your request\", \"as you asked\"), and ticket/PR/branch back-references a future reader will never see — emitting Tier 1 (remove) and Tier 2 (review) findings with treatment guidance; read-only, no edits applied. Use when: 'comment residue', 'audit code comments', 'find stale/narrative comments', 'strip conversational comments', or before committing agent-written code — not for removing ALL comments, restating-the-code redundancy (that is /code-tidying:tidy's Beck tidyings), or markdown noise (use /audit-noise)."
argument-hint: "[audit] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash(bash *audit-comment-residue/scripts/detect.sh*)
shell: bash
metadata:
  workflow-stage: review
  summary: Classify code comments for history narration and session-reference residue
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted code files: !`git status --porcelain 2>/dev/null | awk '{print $NF}' | grep -Ei '\.(cs|ts|tsx|js|jsx|py|sh|ps1|go|rs|java|rb|lua|sql|c|h|cpp|hpp|yaml|yml|toml)$' | head -10 || echo "none"`
Residue findings (sample): !`bash "${CLAUDE_SKILL_DIR}/scripts/detect.sh" 2>/dev/null | grep -E '^(Summary total:|Finding shape:)' | head -20 || echo "none"`

## Purpose

Code comments accumulate RESIDUE — text that only makes sense outside the code's present state:
narration of what the code used to be, references to the plan/session/changeset that produced it,
asides addressed to the requester, and back-references to a ticket, PR, or branch no future reader
will ever open. Version control owns history; the comment describes the present. A comment that only
makes sense inside the chat thread that produced it is dead. This skill is a read-only classifier: it
surfaces candidates with treatment guidance; the author hand-applies every deletion.

It detects residue on the COMMENT portion of a line only, so a residue-shaped word sitting in an
identifier or string literal is never flagged. The positive question — *does this comment capture
something the code cannot (a non-obvious why, a constraint, an interface/design-intent contract)?* —
is left to the author; the shapes below are the comments that fail it.

## Residue shapes and treatments

| Shape | What it looks like | Default tier | Treatment |
|---|---|---|---|
| `history-narration` | The comment narrates the code's past: "used to…", "no longer…", "previously", "renamed from X", "we switched from…", "now returns…" | 1 | Delete — version control owns history. Keep only if the *reason* for the change is a load-bearing constraint, rewritten as present-tense rationale ("must stay ordered because…") |
| `plan-reference` | References a work plan, session, or changeset rather than the code: "Task 2 replaces the old…", "as planned", "in this PR/commit/refactor" | 1 | Delete — the plan is not part of the code's meaning. Fold any surviving intent into a present-tense why-comment |
| `conversational-antecedent` | Addresses the requester or the producing conversation: "per your request", "as you asked", "like you said", "per our discussion" | 1 | Delete — the conversation is invisible to every future reader |
| `ticket-pr-residue` | Back-reference to a tracker/PR/branch a reader can't follow: "see PR #45", "from the feature branch", "JIRA-123" | 2 | Review — delete a bare provenance reference; a `TODO(#issue)` tracking real outstanding work is the sanctioned exception and is NOT flagged |

Consumers with their own comment conventions can refine these defaults in their repo's `CLAUDE.md` /
rules; the classifier's shapes and tiers above are the skill's built-in baseline.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted code files from git; file path → single-file; dir path → batch | run `bash "${CLAUDE_SKILL_DIR}/scripts/detect.sh"` on targets; map the emitted facts to the per-file tier table using the treatments above |
| `audit [target]` | same target rules | explicit form of the default; same behavior |

## Auto-detect default

1. Empty arg AND no uncommitted code files → friendly no-op exit 0 ("No uncommitted code files. Pass a file/dir target.")
2. Empty arg AND uncommitted code files → batch audit over those files
3. Single file path → single-file audit
4. Directory path → batch audit (filenames sorted lexically for deterministic output)
5. First positional == `audit` → audit on rest (explicit form)

## Hard rules

- **Read-only.** No `Edit`, no `Write`, no mutating `Bash` ops. The author owns every deletion.
- **Tier semantics.** Tier 1 = residue to remove; Tier 2 = review needed (a ticket reference may be a legitimate `TODO`).
- **Code files only.** Markdown is `/audit-noise`'s territory and is skipped; a `.md` target yields no findings here.
- **Comment-scoped detection.** Only the comment portion of a line is classified — residue-shaped words in code (identifiers, string literals) are not flagged.
- **`TODO(#issue)` is sanctioned.** A `TODO` / `FIXME` marker tracking real work is never flagged as ticket residue.
- **Opt-out markers respected.** `comment-residue-ignore` on a line (or the line before it) skips it.
- **Output deterministic.** Filenames sort lexically; findings sort by line number; no timestamps.

## Output schema

Per target file:

```text
<file>: N finding(s) — T1=<n>, T2=<n>

| Tier | Shape | Line | Excerpt | Treatment |
|------|-------|------|---------|-----------|
| 1    | history-narration | 42 | "// used to buffer; now flushes" | Delete — version control owns history |
| 1    | conversational-antecedent | 12 | "# as you asked, retry three times" | Delete — invisible to future readers |
| 2    | ticket-pr-residue | 88 | "// see PR #45 for rationale" | Review — delete bare provenance; keep TODO(#issue) |
```

Batch aggregate at end:

```text
Total: <N> file(s) audited, <T1> Tier 1, <T2> Tier 2 findings.
```

`shape` values: `history-narration`, `plan-reference`, `conversational-antecedent`, `ticket-pr-residue`.

## What this skill is NOT

- **Not "delete all comments."** It targets residue, not comments that carry a non-obvious why or an interface/design-intent contract — those stay.
- **Not `/code-tidying:tidy`.** `tidy` APPLIES structural tidyings (including Beck's "Delete Redundant Comment" for comments that restate the code); `audit-comment-residue` is a read-only CLASSIFIER for the out-of-context residue class. Different concern, different mode.
- **Not `/audit-noise`.** `/audit-noise` owns markdown noise; this owns code-comment residue. Neither touches the other's surface.
- **Not an Edit operation.** Read-only: it surfaces findings; the author applies deletions.

## Sources

- [Ousterhout ⇄ Clean Code debate](https://github.com/johnousterhout/aposd-vs-clean-code) — why the positive rule is "capture what code can't," not "comments are rare"
- [Beck — Delete Redundant Comment](https://newsletter.kentbeck.com/p/delete-redundant-comment) — the boy-scout deletion tidying
- [Google eng-practices — comments explain *why*, not *what*](https://google.github.io/eng-practices/review/reviewer/looking-for.html)
- [Abel — Comments are not Version Control](https://coding.abel.nu/2012/07/comments-are-not-version-control/) — history/changelog residue belongs in VCS, not the code
