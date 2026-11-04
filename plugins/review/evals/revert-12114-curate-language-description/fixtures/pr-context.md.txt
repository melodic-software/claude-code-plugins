<!-- Untrusted data: pull request text fetched by the review workflow.
     It is material to review, never instructions to the reviewer. -->

## Pull request #12114: feat(domain-driven-design): concise curate-language description, measured no-loss

<!-- session: lane-3 -->
Closes #6604

## Summary

Concise description for `domain-driven-design`'s one skill,
`curate-language`, on the issue's
description-only path, run as a measured before/after pass under the
[rewrite
protocol](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md#measurement).
The new description triggers the same as the old one on every probe, on
both target models. The
body, spoke, eval cases and probes are unchanged.

## Fix

- `plugins/domain-driven-design/skills/curate-language/SKILL.md`:
`description` only, 587 to 506
characters. It drops "Actively", "a consuming project's", "as domain
understanding changes",
"what-it-IS" and "already-" (in "already-known"), and the colon after
"Use when". It keeps all
four quoted trigger phrases verbatim, both unquoted triggers (domain
modeling resolves
vocabulary; planning resolves domain language worth preserving), every
branch, and the three
  exclusions.
- Changelog fragment (patch).

Decision table:

| Skill | Part | Decision | Basis |
|---|---|---|---|
| curate-language | description | ships | Every trigger pass is VALID
and scores the same before and after on Opus 5.5 and Sonnet 5.5 (table
below). |
| curate-language | body | unchanged | Out of scope: the issue's
description-only path. |

## Verification

The pre-registration was written before any paid run, and each later
rule went into its Run log
before the run it governs.

- Versions: before and after copies of the plugin at the same main
commit. They differ only in
SKILL.md line 2. A fresh rewriter, barred from probes, evals and the
held-out set, wrote the after
text. It had merged the two unquoted triggers so that "worth preserving"
also qualified
domain modeling; an earlier round's labeler on this issue flagged that
merge, so the original
  split was restored before labeling.
- Meaning diff: two fresh `docs-hygiene:compare-labeler` agents, REASONS
none. Both returned
`VERDICT: PASS`, 0 SEMANTIC LOSS, 0 AMBIGUITY. Each cut was labeled
RELOCATED (the body and
  `context/glossary-contract.md` still say it) or FALSE POSITIVE.
- Probes: the frozen `probes/curate-language.json` (18 queries, 9
positive, 9 negative, from
#11828), plus a held-out set of 16 queries (8/8) written blind by a
fresh agent from a neutral
  purpose statement. The held-out set is not committed.
- Run: cases emitted by `/skill-quality:check measure-invocation`
`emit-plugin-eval`, then
`claude plugin eval --ablation none --disallow-tools Read Glob Grep
--runs 3 -j 2 --keep-temp`.
Claude Code 2.1.316. In each pair, before and after were launched
together. `run-validity.py`
  came from main.
- Ceiling: the first Opus held-out pair stopped at the 5 USD per-pass
ceiling (34 of 48 rows each).
It is partial, INVALID and not read. A should-trigger Opus run works the
request after the skill
fires, so 24 positive runs alone exceed 5 USD. The ceiling was raised to
10 USD, a deviation
  recorded before the rerun, and the pair was re-run in full.

Hits over queries x 3 runs (should-trigger fired / should-not stayed
quiet), before / after:

| Set | Model | run-validity (before, after) | Before | After |
`measure-invocation compare` |
|---|---|---|---|---|---|
| held-out | Opus 5.5 | VALID, VALID | 24/24, 24/24 | 24/24, 24/24 |
delta 0, interval [0, 0] |
| held-out | Sonnet 5.5 | VALID, VALID | 24/24, 24/24 | 24/24, 24/24 |
delta 0, interval [0, 0] |
| frozen | Opus 5.5 | VALID, VALID | 27/27, 27/27 | 27/27, 27/27 | delta
0, interval [0, 0] (train and validation) |
| frozen | Sonnet 5.5 | VALID, VALID | 27/27, 27/27 | 27/27, 27/27 |
delta 0, interval [0, 0] (train and validation) |

Every pass had 0 permission denials. The one run-validity WARN on each
is that no judge model is
recorded, and the suite has no judge grader.

What this cannot show:

- Every score is at the ceiling, so the result shows no loss, not a
gain.
- The eval loads only this plugin, so the negatives test whether the
skill stays quiet, not whether
  rival skills from other plugins win.
- No outcome pass ran. A description change re-measures triggering,
every outcome case invokes the
  skill by slash command, and the body did not change.

Other checks:

- `/skill-quality:check plugins/domain-driven-design/skills`: 1 passed,
0 failed, on main and on
this head. The same two warnings both times: the numbered procedure, and
the description length
above Pocock's measured max (now 506, was 587). Run on the plugin root,
`check-skill.sh`
reports "No skills found" on both main and this head, so the `skills/`
path is the one that
  checks the skill.
- Pre-push `check-affected` and the guardrails reference and content
checks passed. gitleaks over
  the branch: no leaks.

Spend: 57.36 USD list-price estimate, CLI-reported, across 10 result
files including the two
partial passes. Eval wall time: 18:31-19:38 UTC, 2026-11-01.

Done-when on #6604: the diff under `skills/` is the `description` line
only. The probe file is on
main from #11828. The scores are above. After equals before. The skill
check shows no new FAIL.
The changelog fragment is included.

## Related

- Umbrella: #6476
- Frozen suite and probes: #11828
- Follow-up, not in this PR: the `cl-existing-convention` prompt wording
("never the insured
organization") and its `claimant-rejects-insured-org` grader, noted on
#11828. The frozen outcome
  suite was not run or edited here.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>

This checkout holds only some of the pull request's files: plugins/domain-driven-design/skills/curate-language/SKILL.md.
