# The change set a review runs over

What every change-review skill in this plugin (`/review:fanout`, `/review:council`) resolves before
it dispatches a reviewer: the diff base, where findings go, the severity vocabulary, the pre-flight
gate, and the size tier. A skill points here and states only what differs.

## Review diff base

When an open PR exists for the branch, its `baseRefName` is the base: dispatched surfaces diff
`git merge-base origin/<baseRefName> HEAD`. A capped pre-computed PR list that lacks the current
branch is not proof of no PR: run `gh pr list --head <current-branch> --json number,baseRefName`
before concluding none exists. Otherwise `git merge-base origin/HEAD HEAD` (falling back to the
remote's resolved default branch via `git ls-remote --symref`, then `origin/main`). When none of
them yields a merge-base (no remote, or a shallow clone sharing no ancestor with it), the base is
unresolved: never fall back to `HEAD`. A hardcoded `git diff HEAD` is empty on a clean committed
branch, so it would read as nothing to review.

Surfaces diff the base in every case: `git diff <merge-base>` includes uncommitted tracked edits
alongside committed branch changes, so it covers dirty trees, clean committed branches and open
PRs alike. Instruct each surface to run the merge-base command itself.

## Severity vocabulary

The project's own review docs when present; else [`../context/severity.md`](../context/severity.md).

## Findings location

`<memory_dir>/reviews/<branch-slug>/`, never committed. `<memory_dir>` is `.work/` unless the
project's instructions declare another memory root. `<branch-slug>` is the branch name lowercased,
with `/` and every other non-`[a-z0-9._-]` character replaced by `-`; the mapping is lossy
(`feature/foo` and `feature-foo` collide), so the artifact's own `branch:` frontmatter, never its
directory, proves which branch it describes. Timestamps are ISO-basic UTC `YYYYMMDDTHHMMSSZ`
(`date -u +%Y%m%dT%H%M%SZ`), colon-free and Windows-safe; lexical sort equals chronological sort.
The session's first write verifies the memory root contains a `.gitignore` with `*`, creating it
(announced) when absent; never edit the consumer's root `.gitignore`. A writer and the `fix`
action's reader must land in the same directory or findings go silently unseen. The directory is
checkout-local: findings that must cross checkouts go through the work-item tracker as tickets that
point, never as pasted report bodies. With no git repo there is nothing to review, so stop before
any write.

## Pre-flight gate

**Ask-shape check first, before any diff resolution:** when the ask is a whole-repository security
audit rather than a change review, emit the deep-scan escalation below and STOP, regardless of diff
state. A tracked diff or open PR does not convert that ask into a change review; a diff-scoped
review would answer a question the user did not ask.

Otherwise resolve the review diff base and confirm it yields a non-empty diff BEFORE any surface is
spawned:

- **Unresolvable base**: an open PR's `origin/<baseRefName>` fails `git rev-parse --verify` even
  after a fetch (do NOT silently substitute a different base; that reviews the wrong diff), or no
  ladder ref resolves at all → report which ref failed and STOP.
- **Nothing to review**: decide whether anything is diffable.
  1. **Truly clean**: `git status --porcelain` empty AND the branch is not ahead of its base AND no
     open PR → report "no changes to review", spawn nothing, write no findings file. A clean
     committed branch with no PR yet is reviewable, not this case.
  2. **Untracked-only**: porcelain shows ONLY `??` entries AND the branch is not ahead of its base
     AND no open PR → report: ``Only untracked files present. `git diff` cannot show them; `git add`
     them to include in review.`` Spawn nothing. **Do NOT stage the files.**
  3. **Reviewable**: tracked uncommitted changes OR ahead of base OR an open PR → proceed.

Either stop spawns ZERO reviewers: a review against an empty or wrong change set spends the whole
panel to produce noise.

### Deep-scan escalation

The official Claude Security plugin's `/claude-security` scan is a self-orchestrating multi-agent
workflow, not a dispatchable leaf. Never add it to a fan-out or a panel. When the request is a
whole-repo security audit rather than a change-set review, recommend it (presence-gated: only when
its command appears in the skill listing; otherwise suggest installing
`claude-security@claude-plugins-official`). The pointer record for its jobs, prerequisites, and
output contract lives once, in the `quality-gate` skill's security context
([../skills/quality-gate/context/security.md](../skills/quality-gate/context/security.md#deep-scan-escalation)).

## Size tier

Deterministic diff-size thresholds, refined by a judgment layer. A 30-line change touching auth or
crossing a module boundary is NOT "small" in risk even if small in size; promote it. Size = the SUM
of the committed-vs-merge-base and the uncommitted shortstats, so dirty tracked edits count; when an
open PR targets a non-default base, recompute the committed side against that `baseRefName` first.
Print the tier with its reason, promotion included.

| Tier | Size trigger | Promote when |
|---|---|---|
| **small** | <50 changed lines | never |
| **medium** | 50–300 | small diff but security-sensitive, boundary-crossing, or high blast radius |
| **large** | >300 OR cross-cutting (many dirs / many ecosystems) | medium diff that is cross-cutting |

What each tier dispatches is the calling skill's choice.
