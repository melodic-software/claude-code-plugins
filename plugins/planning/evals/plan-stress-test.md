# Plan stress-test eval: grading method

The `st-*` cases measure the stress-tests `plan_stress_test` selects in `/planning:plan`. There
are 12 cases: `st-plan-1` to `st-plan-4`, `st-proposal-1` to `st-proposal-4` and `st-incumbent-1`
to `st-incumbent-4`. Each seeds a draft with three defects and one sound part, and grades the
review's final message with four graders.

| Grader | Type | Passes when |
|---|---|---|
| `defect-a`, `defect-b`, `defect-c` | `regex` | the reply reports that seeded defect |
| `sound-part` | `llm` | no finding attacks the draft's sound part |

## Why the sound-part check is a judge

The three defect graders stay regexes because each defect has concrete identifiers a pattern can
match, such as `SaveBins` or `ParseExact`. The sound-part check has no fixed wording: a reply can
attack sound work in many phrasings, and a correct reply can name the same element while it
approves it, reports a different defect or proposes a fix. The review rounds on #12835 kept
finding phrasings the `match: not_contains` regexes sorted wrong, and every miss was in the
wording around the target, not the identifier. So `sound-part` moved to a judge and the defect
graders did not (#12925). Basis: judgment, from those review rounds.

A judge grader costs three judge calls per run, and the suite scores close to its ceiling, so the
defect graders stay free.

## Writing a sound-part rubric

The judge reads only the final message (`focus: last_message`), not the seeded workspace, so each
rubric carries what it needs:

- what the draft does and why that part is sound, with the file or limit that settles it;
- PASS when no finding attacks it, with the nearby findings that still pass: the case's own
  defects, and fixes or approvals that name the same element;
- FAIL for each way a reply attacks it, including a reply that quotes the draft's approval and
  then rebuts it.

A rubric says nothing about an empty reply. Claude Code answers an empty reply with an injected
user turn, so a calibration run skips empty samples, and the defect graders fail an empty reply
anyway.

## Calibration

Each case's `samples/sound-part.json` holds the judge's labeled answers: `pass` answers leave the
sound part alone, and `fail` answers attack it. `/evals:validate` never calls a judge, so it
reports a WARN for each `llm` grader with samples. Checking the judge against those answers is a
paid run an operator starts on a host. When a real run misgrades a reply, add that reply to the
samples and tighten the rubric.
