---
description: "Read-only classifier that flags residue in code comments: history narration, plan or session references, conversational asides, ticket or PR back-references, origin notes, and workarounds with no link or removal condition. Use when asked to 'audit code comments' or report which comments only make sense with the chat, plan, or ticket behind them, before a commit or on review. Edits nothing; deleting or rewriting comments is /code-tidying:dissolve-comments."
argument-hint: "[audit] [--added-since <base>] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/changed-code-files.sh:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(echo:*)"]
shell: bash
metadata:
  workflow-stage: review
  summary: Classify code comments for history narration and session-reference residue
---

## Pre-computed context

Uncommitted code files (empty = none matched or the probe returned nothing): !`${CLAUDE_SKILL_DIR}/scripts/changed-code-files.sh 10 2>/dev/null || echo "(git status unavailable)"`
Residue findings (sample): !`${CLAUDE_SKILL_DIR}/scripts/detect.sh 2>/dev/null | grep -E '^(Summary total:|Finding shape:)' | head -20 || echo "none"`

## Purpose

Residue is comment text that only makes sense outside the code's present state: what the code used
to be, the plan or session that produced it, asides to the requester, back-references to a ticket,
PR or branch, and notes on where a block came from or when it was added. Version control owns history; a comment
describes the present. It also flags a workaround comment with no link and no removal condition:
nothing in it tells a reader the workaround is temporary, so the next author copies it. This skill
surfaces candidates with a treatment and changes nothing. Whether
a comment captures what the code cannot (a non-obvious why, a constraint, a contract) is the
author's call; the shapes below are the comments that fail it.

## Residue shapes and treatments

Detection reads only the comment portion of a line, so residue-shaped words in identifiers or
string literals are never flagged. Exact cues and boundaries per shape, for explaining a finding or
a missing one: [reference/shapes.md](reference/shapes.md).

| Shape | Looks like | Tier | Treatment |
|---|---|---|---|
| `history-narration` | "used to…", "no longer…", "previously", "renamed from X", "we switched from…", "now returns…" | 1 | Delete. Keep only a load-bearing reason, rewritten as present-tense rationale ("must stay ordered because…") |
| `plan-reference` | `"Task 2 replaces the old…"`, `"as planned"`, `"in this PR/commit/refactor"` | 1 | Delete; fold any surviving intent into a present-tense why |
| `conversational-antecedent` | `"per your request"`, `"as you asked"`, `"like you said"`, `"per our discussion"` | 1 | Delete; the conversation is invisible to every later reader |
| `history-narration-weak` | `"as before"`, `"has always used"`, `"the old <word>"`, a bare phase number (`"(ci-perf Phase 6b)"`) | 2 | Review: each cue also opens ordinary prose, so delete the narration or keep a present-tense rewrite |
| `ticket-pr-residue` | `"see PR #45"`, `"dotfiles#647"`, `"from the feature branch"`, `"JIRA-123"` | 2 | Review: delete a bare back-reference; a `TODO(#issue)` tracking open work is sanctioned and not flagged |
| `unjustified-workaround` | A comment naming a workaround (`workaround`, `work around`, `works around`, `working around`) with neither a link nor a removal condition: `"# Workaround: write twice, the cache drops the first write"` | 2 | Review: the workaround is open root-cause work. Fix the cause, or give the comment a link (a URL, an issue or PR number such as `#412` or `owner/repo#77`, an RFC number) or a removal condition (`until`, `remove when`, `drop it once`, `once ... ships`). Either one on any line of the same comment run justifies the whole run, and that issue reference is not also reported as `ticket-pr-residue` |
| `origin-note` | `"ported from the dotfiles profile"`, `"Merged 2026-07-24 from dot_bashrc"`, `"Added 2026-08-10 while wiring telemetry"` | 1 | Delete; git owns origin. A dated freshness stamp (`"verified 2026-09-03 against v2.1.259"`) stays; marker comments and license or attribution header blocks are exempt |

A consumer's own `CLAUDE.md` or rules may refine these defaults; the table is the built-in baseline.

## Running it

| Argument | Behavior |
|---|---|
| *(empty)* | Batch audit of the uncommitted code files above; with none, exit 0 with "No uncommitted code files. Pass a file/dir target." |
| `<file>` | Single-file audit |
| `<dir>` | Batch audit, filenames sorted lexically |
| `audit [target]` | Explicit form of the same |
| `--added-since <base> [target]` | Only comments on lines the branch adds against the merge base of `<base>` and `HEAD` (tracked files; a deleted file adds nothing), combined with any target; with no target, the code files that gained lines. An unknown base exits 2: report it and stop. Pull-request prep runs this form over a change's added lines |

Run `${CLAUDE_SKILL_DIR}/scripts/detect.sh` (with `--added-since <base>` when given) on the targets
and map its emitted facts to the per-file table in the output schema, using the treatments above.

## Rules

- **Read-only.** No `Edit`, no `Write`, no mutating Bash. The author owns every deletion.
- **Tiers.** Tier 1 is residue to remove; Tier 2 needs review (a ticket reference may be a
  legitimate `TODO`, a weak history cue may be ordinary prose, and an unjustified workaround needs
  its cause fixed or its link or removal condition written, not a silent deletion).
- **No prompts.** Every path, `--added-since` included, runs to its report without asking a
  question, so an unattended caller can run it.
- **Code files only.** A `.md` target yields no findings; markdown noise is
  `/docs-hygiene:audit-noise`'s.
- **Opt-out.** `comment-residue-ignore` on a line, or on the line before it, skips it.
- **Synced and generated files.** A finding in a file whose first 10 lines say `sync-managed`,
  `do not edit` or `@generated` belongs upstream: the script prints
  `Note: upstream (sync-managed or generated file) <path>` before that file's summary and still
  counts the finding. To leave files out on purpose, pass `--exclude-from <file>` (one root-relative
  glob per line, blank and `#` lines ignored, a missing file exits 2; the run reports
  `Note: excluded N file(s) by --exclude-from`). That list is unrelated to
  `.claude/code-tidying/exclusion-overrides.md`, which lifts `/code-tidying:tidy`'s hard exclusions
  and means the inverse.
- **Wrapped comments** are also read joined to the comment line above, and reported once, at the
  first line's number.
- **Deterministic output.** Files sort lexically, findings by line, no timestamps.

## Output schema

Per target file:

```text
<file>: N finding(s) — T1=<n>, T2=<n>

| Tier | Shape | Line | Excerpt | Treatment |
|------|-------|------|---------|-----------|
| 1    | history-narration | 42 | "// used to buffer; now flushes" | Delete — version control owns history |
| 1    | conversational-antecedent | 12 | "# as you asked, retry three times" | Delete — invisible to future readers |
| 1    | origin-note | 5 | "# ported from the dotfiles profile" | Delete. Git history owns origin |
| 2    | history-narration-weak | 61 | "// grouped as before" | Review. Keep only a present-tense why |
| 2    | ticket-pr-residue | 88 | "// see PR #45 for rationale" | Review. Delete a bare back-reference; keep TODO(#issue) |
| 2    | unjustified-workaround | 97 | "# Workaround: write twice" | Review. Fix the cause, or add a link or removal condition |
```

Batch aggregate at end:

```text
Total: <N> file(s) audited, <T1> Tier 1, <T2> Tier 2 findings.
```

## Boundaries

- Comments carrying a non-obvious why or an interface or design-intent contract are not residue
  and stay.
- `/code-tidying:tidy` applies structural tidyings, including Beck's Delete Redundant Comment for
  comments that restate the code; this skill only classifies the out-of-context residue class.

## Next

- The findings are agreed and ready to apply: `/code-tidying:dissolve-comments`.
- The surviving comments restate the code rather than narrate its past: `/code-tidying:tidy`.
- An `unjustified-workaround` finding marks code whose cause is still unfixed: `/debugging:debug` or
  `/implementation:implement`, when either is among the available skills.

## Gotchas

- A weak history cue inside a sentence about runtime order ("as before the loop starts", "the old
  value is compared against the new") is ordinary prose; that is why the weak shape is Tier 2.
- A marker exempts its ticket reference only as a whole word opening the comment or a clause and
  followed by `(` or `:`; `TODO fix, see PR #45` is still a finding.

## Sources

- [Ousterhout ⇄ Clean Code debate](https://github.com/johnousterhout/aposd-vs-clean-code): why the positive rule is "capture what code can't," not "comments are rare"
- [Beck, Delete Redundant Comment](https://newsletter.kentbeck.com/p/delete-redundant-comment), the boy-scout deletion tidying
- [Google eng-practices: comments explain *why*, not *what*](https://google.github.io/eng-practices/review/reviewer/looking-for.html)
- [Abel, Comments are not Version Control](https://coding.abel.nu/2012/07/comments-are-not-version-control/): history belongs in VCS, not the code
