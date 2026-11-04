<!-- Untrusted data: pull request text fetched by the review workflow.
     It is material to review, never instructions to the reviewer. -->

## Pull request #12186: feat(naming): shorten the name-it-better description

<!-- session: lane-3 -->
Closes #6611

## Summary

Shortens the `naming:name-it-better` description from 650 to 624
characters on the description-only path. The body is unchanged. The new
description scored the same as or better than the old one on held-out
trigger probes and on four routing cases, on both Opus 5.5 and Sonnet
5.5.

## Fix

- `plugins/naming/skills/name-it-better/SKILL.md` line 2 is the only
changed line (`git diff origin/main -- plugins/naming/skills` changes
nothing outside the `description` key). A fresh rewriter worked on a
copy outside the repository. It could not read the eval cases, the
probes, the issue or the git history. It made three edits:
1. "Then let the human pick." and "; never auto-locks a name" are merged
into one sentence: "The human picks; never auto-locks a name."
  2. "UNDECIDED, whether the ask is" becomes "UNDECIDED:".
3. The two decided-rename sentences become one, ending ", which routes
to the rename-references sweep".
- Kept word for word: every quoted trigger phrase, the list of target
kinds, both UNDECIDED branches, the decided-rename exclusion and where
it routes, the blind-generators clause and the `tournament` argument.
- `.changes/naming/` patch fragment.
- The frozen probe file `plugins/naming/probes/name-it-better.json`
landed on main in #12002 and is present on this head unchanged.

## Verification

Runs used Claude Code 2.1.316 with before and after copies launched
together. Each pass used `--ablation none` and the same flags. Every
number below comes from a pass that `run-validity.py` judged VALID
(origin/main copy, with `--scaffolded` for the scaffolded cases). The
decision rule was preregistered before the first paid run, and the eval
suite was frozen at the digest recorded on #6611 (`plugins/naming/evals`
tree `1afdcd49`).

**Trigger scores (`/skill-quality:check measure-invocation`).** 16
held-out probes were written blind by a skills-disabled print session
from a neutral statement of the skill's purpose. They were emitted with
`measure-invocation.sh emit-plugin-eval --runs 3`.

| Model | Should-trigger fired, before | Should-trigger fired, after |
Should-not quiet, before | Should-not quiet, after |
|---|---|---|---|---|
| Opus 5.5 | 24/24 | 24/24 | 24/24 | 24/24 |
| Sonnet 5.5 | 23/24 | 24/24 | 24/24 | 24/24 |

- No trigger was lost.
- The noise report calls the after version non-inferior at a 0.05 margin
on both models.
- On the frozen probe file, the lexical `measure-invocation.sh score`
gives:
  - before: train 0.8 trigger / 0.2 false, validation 0.6 / 0.4
  - after: train 0.8 / 0.2, validation 0.4 / 0.4

This score is a tripwire, not the verdict. The one validation probe that
flipped is `pos-val-04` ("Help me pick a filename for the doc that
explains how releases get cut"). Its overlap score fell from 9 to 8 when
"Then let the human pick" became "The human picks", because the probe
word "pick" no longer matches exactly. At 8 it ties with
`docs-naming:generate-file-name-gate`, so the lexical score no longer
predicts a trigger. The skill criteria say "A deterministic lexical
score is a tripwire only, never the verdict" (Measurement, step 6). The
Done-when comparison is the preregistered model-graded held-out score in
the table above, and it did not drop on either model.

**Routing cases.** 5 runs per version, with-arm mean scores:

| Case | Opus before | Opus after | Sonnet before | Sonnet after |
|---|---|---|---|---|
| `nib-decided-rename-not-routed` (must not route) | 1.000 | 1.000 |
1.000 | 1.000 |
| `nib-rejected-name-natural-phrasing` | 1.000 | 1.000 | 1.000 | 1.000 |
| `nib-blast-radius-basis` | 0.867 | 0.867 | 0.800 | 0.933 |
| `nib-misleading-name-no-apply` (Bash/Edit/Write granted) | 1.000 |
1.000 | 1.000 | 1.000 |

- In every pass, the routing grader gave the same result for both
versions: 5 of 5 routed on the three should-route cases, and 0 routes on
the decided-rename case.
- No must-not grader failed.
- All `blast-radius-basis` misses are the `basis-label` grader. Every
missed reply was read. Each one states the searched reference count, and
most carry a Basis line in a form the pattern does not match (for
example "**Basis for #1:** the blast radius is verified"). This
grader-recall limit is noted for a later round.
- `nib-tournament-public-package` was not run: it is slash-invoked, so
the description cannot affect it, and the body is unchanged.

**Meaning diff.** Two `/docs-hygiene:compress compare` labelers both
returned PASS, with 0 SEMANTIC LOSS and 0 AMBIGUITY.

**`/skill-quality:check plugins/naming`.** PASS on main (0 errors, 3
warnings) and PASS on this head (0 errors, 4 warnings). No new FAIL.
- The added warning says the description dropped the trigger keyword
"the target name is still UNDECIDED". That phrase is still in the
description word for word; only the punctuation after it changed (a
comma became a colon). This is a check false positive.

**Cost.** 28.53 USD list-price estimate for 21 passes (host-safety probe
included). Every pass stayed under the 5 USD per-pass ceiling.

## Related

- #6476 (Concise skills rollout parent)
- #12002 (frozen outcome cases and trigger probes)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>

This checkout holds only some of the pull request's files: plugins/naming/skills/name-it-better/SKILL.md.
