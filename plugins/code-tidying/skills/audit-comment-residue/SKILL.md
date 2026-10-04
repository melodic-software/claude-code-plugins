---
description: "Classify code comments for residue: history narration, plan/session references, conversational antecedents, ticket/PR back-references, origin notes, and workarounds with no link or removal condition. Read-only. Use when: 'comment residue', 'audit code comments', 'find stale/narrative comments', 'strip conversational comments', 'origin note', or before committing agent-written code. Not for removing ALL comments, restating-the-code redundancy (/code-tidying:tidy), or markdown noise (/docs-hygiene:audit-noise)."
argument-hint: "[audit] [--added-since <base>] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/changed-code-files.sh:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(echo:*)"]
shell: bash
metadata:
  workflow-stage: review
  summary: Classify code comments for history narration and session-reference residue
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the `source-control` plugin's
[worktree/reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Pre-computed context

Uncommitted code files (empty = none matched or the probe returned nothing): !`${CLAUDE_SKILL_DIR}/scripts/changed-code-files.sh 10 2>/dev/null || echo "(git status unavailable)"`
Residue findings (sample): !`${CLAUDE_SKILL_DIR}/scripts/detect.sh 2>/dev/null | grep -E '^(Summary total:|Finding shape:)' | head -20 || echo "none"`

## Purpose

Code comments accumulate RESIDUE. Text that only makes sense outside the code's present state:
narration of what the code used to be, references to the plan/session/changeset that produced it,
asides addressed to the requester, back-references to a ticket, PR, or branch no future reader will
ever open, and origin notes naming where a block came from or when it was added. It also flags a
workaround comment that gives no link and no removal condition: nothing in it tells a reader the
workaround is temporary or when it can go, so the next author copies it. Version control
owns history; the comment describes the present. A comment that only makes sense inside the chat
thread that produced it is dead. This skill is a read-only classifier: it surfaces candidates with
treatment guidance.

It detects residue on the COMMENT portion of a line only, so a residue-shaped word sitting in an
identifier or string literal is never flagged. The positive question, *does this comment capture
something the code cannot (a non-obvious why, a constraint, an interface/design-intent contract)?*, is left to the author; the shapes below are the comments that fail it.

## Residue shapes and treatments

| Shape | What it looks like | Default tier | Treatment |
|---|---|---|---|
| `history-narration` | The comment narrates the code's past: "used to…", "no longer…", "previously", "renamed from X", "we switched from…", "now returns…" | 1 | Delete. Version control owns history. Keep only if the *reason* for the change is a load-bearing constraint, rewritten as present-tense rationale ("must stay ordered because…") |
| `plan-reference` | References a work plan, session, or changeset rather than the code: `"Task 2 replaces the old…"`, `"as planned"`, `"in this PR/commit/refactor"` | 1 | Delete, the plan is not part of the code's meaning. Fold any surviving intent into a present-tense why-comment |
| `conversational-antecedent` | Addresses the requester or the producing conversation: `"per your request"`, `"as you asked"`, `"like you said"`, `"per our discussion"` | 1 | Delete, the conversation is invisible to every future reader |
| `history-narration-weak` | Weak cues that usually narrate the past: `"exactly as before"`, `"as before"`, `"has always used"`, `"always used"`, `"the old <word>"` (`"the old shared group"`; `"replaces the old"` stays `plan-reference`), and a bare phase number (`"(ci-perf Phase 6b)"`, `"cleanup for Phase 6"`) | 2 | Review. Each cue also opens ordinary prose (`"as before the loop starts"`, `"the old value is compared against the new"`), so a person decides: delete the narration, or keep a rewrite as present-tense rationale. A phase number followed by more words (`"phase 2 of the build"`) is not a finding |
| `ticket-pr-residue` | Back-reference to a tracker/PR/branch a reader can't follow: `"see PR #45"`, `"dotfiles#647"`, `"from the feature branch"`, `"JIRA-123"` | 2 | Review. Delete a bare back-reference; a `TODO(#issue)` tracking real outstanding work is the sanctioned exception and is NOT flagged |
| `unjustified-workaround` | The comment names a workaround (`workaround`, `work around`, `works around`, `working around`) and carries neither a link nor a removal condition: `"# Workaround: write twice, the cache drops the first write"` | 2 | Review. The workaround code is open root-cause work: fix the cause, or give the comment a link (a URL, an issue or PR number such as `#412` or `owner/repo#77`, an RFC number) or a removal condition (`until`, `remove when`, `drop it once`, `once ... ships`). Either one on any line of the same comment run justifies the whole run. A workaround comment's own issue reference is that justification, so it is not also reported as `ticket-pr-residue`. The word in an identifier or string literal is not a finding |
| `origin-note` | The comment names where the block came from or when it was added: `"ported from the dotfiles profile"`, `"Merged 2026-07-24 from dot_bashrc"`, `"Added 2026-08-10 while wiring telemetry"` | 1 | Delete. Git history owns origin. Boundaries: a dated freshness stamp (`"verified 2026-09-03 against v2.1.259"`, and the same with `checked`, `confirmed` or `as of`) is not this shape and stays, a bare date matches nothing, and the verb-from cue has to open the comment or a clause inside it, so `"bytes copied from the source buffer"` is not a finding (the dated cue takes every anchor but the parenthesis). Two comment classes are exempt whatever verb they open with, because Tier 1 reads "remove": a marker comment (`TODO`, `FIXME`, `HACK`, `XXX`), which is tracked work, and a license or attribution header, whose text the reader may be legally required to keep. The license exemption is BLOCK-scoped: a run of contiguous comment lines in which ANY line carries `SPDX-License-Identifier`, `Licensed under`, `License:`, a `Copyright` next to a year or a `(c)`/`©` sign, or a `(c)` in front of a year is exempt whole, so the attribution line of a NOTICE header is covered even though the cue sits on a different line. The run ends at the first blank line or line of code, and a trailing comment on a code line starts no run, so the same sentence elsewhere in the file is an ordinary finding |

Consumers with their own comment conventions can refine these defaults in their repo's `CLAUDE.md` /
rules; the classifier's shapes and tiers above are the skill's built-in baseline.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted code files from git; file path → single-file; dir path → batch | run `${CLAUDE_SKILL_DIR}/scripts/detect.sh` on targets; map the emitted facts to the per-file tier table using the treatments above |
| `audit [target]` | same target rules | explicit form of the default; same behavior |
| `--added-since <base> [target]` | empty → the code files that gained lines against `<base>`; paths → those of them that gained lines | run `${CLAUDE_SKILL_DIR}/scripts/detect.sh --added-since <base> [target]`, which reports only comments on the lines the branch adds against the merge base of `<base>` and `HEAD` (tracked files; a deleted file adds nothing). An unknown base exits 2: report it and stop. Pull-request prep runs this form over a change's added lines |

## Auto-detect default

1. Empty arg AND no uncommitted code files → friendly no-op exit 0 ("No uncommitted code files. Pass a file/dir target.")
2. Empty arg AND uncommitted code files → batch audit over those files
3. Single file path → single-file audit
4. Directory path → batch audit (filenames sorted lexically for deterministic output)
5. First positional == `audit` → audit on rest (explicit form)
6. `--added-since <base>` anywhere → the added-lines scope above, combined with any target

## Hard rules

- **Read-only.** No `Edit`, no `Write`, no mutating `Bash` ops. The author owns every deletion.
- **Tier semantics.** Tier 1 = residue to remove; Tier 2 = review needed (a ticket reference may be a legitimate `TODO`, a weak history cue may be ordinary prose, and an unjustified workaround needs its cause fixed or its link or removal condition written, not a silent deletion).
- **No prompts.** Every path, `--added-since` included, runs to its report without asking a question, so an unattended caller can run it.
- **Wrapped comments.** A comment line that continues a comment on the line above is also read joined to it, so a phrase wrapped across the break is found. It is reported once, at the first line's number.
- **Code files only.** Markdown is `/docs-hygiene:audit-noise`'s territory and is skipped; a `.md` target yields no findings here.
- **Comment-scoped detection.** Only the comment portion of a line is classified. Residue-shaped words in code (identifiers, string literals) are not flagged.
- **`TODO(#issue)` is sanctioned.** A `TODO` / `FIXME` / `HACK` / `XXX` marker tracking real work is never flagged as ticket residue. The marker must be a whole word opening the comment or a clause and followed by `(` or `:`.
- **Opt-out markers respected.** `comment-residue-ignore` on a line (or the line before it) skips it.
- **Synced and generated files.** A finding in a file whose first 10 lines say `sync-managed`, `do not edit` or `@generated` belongs upstream, where the file is produced. The script labels it with a `Note: upstream (sync-managed or generated file) <path>` line before that file's summary, and the finding still counts in the tiers; nothing is silently hidden. To leave files out of a run on purpose, pass `--exclude-from <file>`: one root-relative glob per line, blank lines and `#` lines ignored, a missing file exits 2, and the run reports `Note: excluded N file(s) by --exclude-from`. That list is separate from `.claude/code-tidying/exclusion-overrides.md`, which lifts `/code-tidying:tidy`'s hard exclusions and has the inverse meaning.
- **Output deterministic.** Filenames sort lexically; findings sort by line number; no timestamps.

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

`shape` values: `history-narration`, `history-narration-weak`, `plan-reference`, `conversational-antecedent`, `ticket-pr-residue`, `origin-note`, `unjustified-workaround`.

## What this skill is NOT

- **Not "delete all comments."** It targets residue, not comments that carry a non-obvious why or an interface/design-intent contract. Those stay.
- **Not `/code-tidying:tidy`.** `tidy` APPLIES structural tidyings (including Beck's "Delete Redundant Comment" for comments that restate the code); `audit-comment-residue` is a read-only CLASSIFIER for the out-of-context residue class. Different concern, different mode.
- **Not `/docs-hygiene:audit-noise`.** `/docs-hygiene:audit-noise` owns markdown noise; this owns code-comment residue. Neither touches the other's surface.

## Next

- The findings are agreed and ready to apply: `/code-tidying:dissolve-comments`.
- The surviving comments restate the code rather than narrate its past: `/code-tidying:tidy`.
- An `unjustified-workaround` finding marks code whose cause is still unfixed: `/debugging:debug` or
  `/implementation:implement`, when either is among the available skills.

## Sources

- [Ousterhout ⇄ Clean Code debate](https://github.com/johnousterhout/aposd-vs-clean-code). Why the positive rule is "capture what code can't," not "comments are rare"
- [Beck, Delete Redundant Comment](https://newsletter.kentbeck.com/p/delete-redundant-comment), the boy-scout deletion tidying
- [Google eng-practices. Comments explain *why*, not *what*](https://google.github.io/eng-practices/review/reviewer/looking-for.html)
- [Abel, Comments are not Version Control](https://coding.abel.nu/2012/07/comments-are-not-version-control/), history/changelog residue belongs in VCS, not the code
