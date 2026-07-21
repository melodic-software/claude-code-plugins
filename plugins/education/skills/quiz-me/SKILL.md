---
name: quiz-me
description: "Post-work comprehension check: after a change is complete, generate a self-contained HTML report of what was done (context, intuition, decisions) with a quiz at the bottom that you answer — verifying the HUMAN absorbed the work, not the artifact. Non-gating by default; the quiz_policy userConfig tunes offer cadence. Also recalls prior work from the retained report library. Use when: 'quiz me', 'quiz me on this change', 'do I understand this change', 'comprehension check', 'a quiz at the bottom that I must pass', 'I want to make sure I understand everything that happened', 'what did we do on <ticket>'. Sibling to education:teach (multi-session coach) and education:explain (one-shot explainer); this verifies comprehension of COMPLETED WORK. Not artifact verification — that is verification:confirm (if installed)."
argument-hint: "[recall <query>] (empty = quiz me on the change just completed)"
user-invocable: true
---

## Purpose

Verify that the **human** absorbed a completed change — the object under test is the
person merging the work, never the artifact. After Claude finishes a change, generate an
HTML report of what was done (context, intuition, decisions) with a quiz at the bottom the
user answers. The failure mode this addresses: people glaze over plans and explainers, so
the human merging a PR cannot represent the change to a reviewer and their mental model of
the codebase decays, degrading future prompting.

Three value props:

- **Representation accountability** — can the user explain this change to a reviewer?
- **Loop retention** — keeping the user's mental model of the codebase current keeps their
  prompting sharp.
- **Late intent-mismatch detection** — a failed quiz surfaces "that's not what I intended"
  while there is still time to fix it, before merge.

**Use when:** the user asks to be quizzed on completed work, or to recall past work
(`quiz me`, `do I understand this change`, `what did we do on <ticket>`). **Skip when:**
the request is to verify the artifact (does it work / is it right), to extract the user's
intent before work starts, or to coach a general subject — see "What this skill does NOT
do". This skill auto-invokes (no `disable-model-invocation`) so policy-driven offers can
fire; `/education:quiz-me` is the guaranteed path.

## Effective configuration (substituted at load)

The values below substitute from this plugin's stored configuration when this skill loads.
A surviving literal `${user_config.…}` placeholder means that key is unset — apply its
documented unset behavior.

| Key | Value | Unset behavior |
| --- | --- | --- |
| `quiz_policy` | `${user_config.quiz_policy}` | `on-request` — act only when invoked. Values govern OFFER CADENCE only (see "Non-gating posture"). Unknown value → treat as `on-request`. |
| `report_library_dir` | `${user_config.report_library_dir}` | unset → artifacts land under `${CLAUDE_PLUGIN_DATA}` (see "Retention mechanics"). Set to a corpus checkout to redirect the library root there. |

Configure via the `/plugin` dialog, or headless with `claude plugin install
education@<marketplace> --config KEY=VALUE` (your installed marketplace name). A literal
non-home `report_library_dir` may be blocked by the hardcoded-path
guardrails — the same collision knowledge's `library_dir` hits (#798); adopt that issue's
path-indirection scheme for literal-path overrides once it lands.

## Action router

Parse `$ARGUMENTS`: first token selects the action.

| Action | Purpose |
| --- | --- |
| *(default, no args)* | Offer or generate a report + quiz for the change just completed — which one depends on who invoked it (below). |
| `recall <query>` | Answer "what did we do on X" from the retained report library first, git/tracker archaeology second — stating which source answered (see "Recall"). |

The default action branches on **who invoked it**: a **user-initiated** invocation
(`/education:quiz-me`, or "quiz me") is itself acceptance — generate the report + quiz
immediately. A **model-initiated** invocation that fires to satisfy `quiz_policy`
`always`/`above-threshold` is an OFFER — present it and wait for the user to accept before
generating anything (see "Non-gating posture"; generation is always user-confirmed).

## Report contract

Produce a **self-contained single-file HTML** report (all CSS/JS inline, no remote fetch,
openable via `file://`, synthetic data only — never real secrets or tokens). Markdown
fallback where the project convention prefers it. Sections: context, intuition, decisions,
what-was-done, then the **quiz at the bottom** the user must answer — the canonical prompt
pattern ("a quiz at the bottom on the changes that I must pass").

- **Answer key persists with the artifact.** Embed the key in the report — a collapsed
  `<details>` block in HTML, an appendix section in the markdown fallback. Grade
  in-conversation in the same session; a later or compacted session grades by reading the
  key back from the retained artifact, re-deriving from the report + diff only when the
  key is missing. Without the embedded key a report recalled weeks later could not be
  graded at all.
- **A failed quiz is a signal, not a gate.** Surface it as a possible intent mismatch to
  resolve before merge; never block the merge yourself (see "Non-gating posture").
- **Reference discipline — durable pointers only.** The report is self-contained.
  Restrict any external reference to durable, checkout-independent pointers: PR/issue
  URLs, commit SHAs or permalinks, promoted docs reachable on the default branch. Never
  link memory-tier paths (`.work/…`) or contract-slice paths (`docs/topics/…`) — both are
  pruned or checkout-local and will dangle. Distill ephemeral inputs (exploration/research
  notes, session context) inline instead of linking them.

## Retention mechanics

Artifacts NEVER land in the consuming repo's working tree. They land under a per-repo
library keyed on **repo identity, not checkout path** — this repo's per-ticket worktrees
are pruned after merge, so a path-keyed slug would strand every report under a dead slug
and leave `recall` from the main clone empty. The remote is normalized to a
protocol-agnostic `host/org/repo` form before hashing, so the SSH and HTTPS remotes of one
repo resolve to the same library. Derive the slug and destination:

```bash
url="$(git remote get-url origin 2>/dev/null)"
if [ -n "$url" ]; then
  canon="$(printf '%s' "$url" | sed -e 's/\.git$//' -e 's#/$##' \
          -e 's#^[a-z+]*://##' -e 's#^[^@/]*@##' -e 's#:#/#')"
  base="$(printf '%s' "$canon" | sed -e 's#^.*[/:]##' | tr '[:upper:]' '[:lower:]' \
          | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  hash="$(printf '%s' "$canon" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
else                                  # no remote — fall back to canonicalized project path
  p="$(realpath "${CLAUDE_PROJECT_DIR}" 2>/dev/null \
       || readlink -f "${CLAUDE_PROJECT_DIR}" 2>/dev/null || printf '%s' "${CLAUDE_PROJECT_DIR}")"
  base="$(basename "$p" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  hash="$(printf '%s' "$p" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
fi
repo_slug="$base-$hash"
```

- **Destination:** `${CLAUDE_PLUGIN_DATA}/$repo_slug/quiz-me/reports/` by default, or
  `<report_library_dir>/$repo_slug/quiz-me/reports/` when that userConfig is set. The
  `quiz-me/` segment fences these artifacts off from teach's path-keyed workspaces in the
  shared per-plugin data directory.
- **Repo-tree guard:** resolve `report_library_dir` to an absolute path before writing; if
  it is `${CLAUDE_PROJECT_DIR}` or nested under it, refuse it, warn the user, and fall back
  to the `${CLAUDE_PLUGIN_DATA}` default — reports must never land in the consuming repo's
  working tree, regardless of how the userConfig is set.
- **Filename:** `<date>-<change-slug>-<short-hash>.html` (or `.md`) — `<date>` is
  `YYYY-MM-DD`, `<change-slug>` a kebab slug of the change (from the PR/ticket title),
  `<short-hash>` the short HEAD commit hash, so reports stay unique and sortable.

## Non-gating posture

`quiz_policy` governs **offer cadence only** — no value ever auto-generates a report.
Generation is ALWAYS user-confirmed: the report + quiz is produced only after the user
accepts an offer, and a direct invocation ("quiz me") is itself that acceptance.

| `quiz_policy` | Offer behavior |
| --- | --- |
| `off` | Never offers. Direct invocation still works. |
| `on-request` (default) | Offers only when the user asks. |
| `always` | Suggests a quiz after each completed change. |
| `above-threshold` | Suggests when the change meets the threshold below. |

- **Threshold** (`above-threshold`): the change meets ANY of — more than 5 files touched,
  more than 200 changed LOC, or the governing plan records blast radius HIGH/CRITICAL.
  Resolve the default branch first, then judge from the merge-base diff at offer time
  (well-defined even after commits): `d="$(git remote show origin 2>/dev/null | awk '/HEAD
  branch/ {print $NF}')"; git diff --stat "$(git merge-base HEAD "$d")"..HEAD`.
- Offers are **best-effort**, model-initiated from the description triggers and this
  posture — there is no hook. An unknown `quiz_policy` value falls back to `on-request`.

## Recall

`recall <query>` answers "what did we do on X" (a ticket, a change, a date). Search the
retained report library (see "Retention mechanics") FIRST; fall back to git history and
the tracker second. **State which source answered.**

**Coverage boundary:** the library holds ONLY work that was actually quizzed
(retention-at-write) — it is not a general work-history engine. When a query names work
that was never quizzed, say so and route to the git/tracker archaeology fallback rather
than implying the library is complete.

## Composition

This skill is an optional post-work step; it never edits another plugin's gate sequence.
Consumers that run a staged workflow (session-flow's workflow skill, if installed) can
route to `/education:quiz-me` as a comprehension step by pointer — the composition lives
here and in that consumer's own on-ramps, not by mutating a shared stage list.

## Gotchas

- **The object is the human, not the artifact.** If you find yourself checking whether the
  code works, you are in the wrong skill (see "What this skill does NOT do").
- **Never write to the consuming repo's tree.** Reports go to the retention library only;
  a report committed into the product repo is a defect — and a `report_library_dir` pointing
  inside the repo tree is refused and defaulted, not honored.
- **Embed the answer key in the artifact.** A report with no key cannot be graded in a
  later session — the retention use case depends on it.
- **Don't imply library completeness on `recall`.** Only quizzed work is retained; name
  the boundary and fall back to archaeology for the rest.
- **Durable pointers only in reports.** A link to `.work/…` or `docs/topics/…` dangles the
  moment the checkout is pruned; distill those inputs inline instead.

## What this skill does NOT do

- **Not artifact verification.** "Did we build the right thing, and does it work?" — object
  = the artifact — belongs to `verification:confirm` (if installed). This skill's object is
  the human's comprehension of completed work.
- **Not pre-work intent extraction.** `planning:interview` (if installed) runs BEFORE work
  to extract the USER's intent, where the user holds the answers. Here the work is done and
  Claude holds the answer key; a failed quiz can surface an intent mismatch after the fact.
- **Not teach's `assess` / `exercise` actions.** `/education:teach assess` and
  `/education:teach exercise` quiz the learner on LEARNING CONTENT inside a teach workspace.
  `/education:quiz-me`'s object is the COMPLETED WORK of a change, with no learning
  workspace. Namespacing keeps them distinct.
- **Not a merge gate.** A failed quiz is a signal to resolve, not a block — `quiz_policy`
  only tunes how often a quiz is OFFERED, never whether the merge proceeds, and no report
  generates without the user's confirmation.
