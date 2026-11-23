---
description: "Advisory health report for a plugin's eval suite: skills with no case or no deterministic triggering case, judged graders with no labeled samples, legacy-only skills, skills with no should-not-fire case, then judged findings on gate pairs, duplicate cases, grader fit and drift from the skill text. Edits nothing; each finding names where its fix goes. Use when: 'audit my evals', 'is my eval suite healthy', 'which skills have no eval case', 'which judges are uncalibrated', 'find duplicate eval cases', 'are my evals stale'. Not for load errors (/evals:validate) or running a suite (/evals:plugin-eval)."
argument-hint: "<plugin-dir|suite-dir>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Read-only eval-suite health report, counts plus judged findings, each with its route
---

# Audit an eval suite

Reports what a suite is missing or carrying that it should not, and changes nothing. The criteria
are the ones below: every skill has a deterministic triggering case, every gate has a fire and a
no-fire case, and a judged grader counts only once checked against labeled samples. Where the
repository records its own eval policy, read it too and report against it as well.

## 1. Counts

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/audit-suite.py" <plugin-dir|suite-dir>
```

Add `--json` for the same data as one object. The script reads which skill each case tests
through the plugin's shared `case_skills.py` rule, so its answer matches `/evals:validate` and
`/evals:plugin-eval select`. It prints:

- skills with no case;
- skills with no deterministic triggering case (no case with a `tool_used` Skill grader that
  needs the skill to fire);
- judged graders (`llm`, `baseline`) with no labeled `samples/<grader>.json`, which cannot have
  been calibrated, and the PASS and FAIL label counts of those that have one;
- skills whose only cases are a legacy `skills/<skill>/evals/evals.json`;
- skills with no should-not-fire case (advisory).

Relay its lines as they are; do not recount by hand.

## 2. Judged findings

Read the suite's cases and the skills they test, then report each of these the script cannot
count:

- **Gate pairs.** A skill rule that stops, refuses or gates an action needs a case where it fires
  and a case where it must not. Name each gate with only one side.
- **Duplicates.** Two cases that send the same kind of prompt to the same skill and check the
  same outcome. Name both and say which one to keep.
- **Grader fit.** A judged grader whose check a deterministic grader could make (a file exists, a
  tool was called, a string or pattern is present). Name the deterministic type that fits.
- **Drift.** A tag that names a skill which no longer exists, or a prompt or grader that quotes
  skill text the skill no longer holds.

Cite the case path and the skill line for each finding; drop any you cannot cite.

## 3. Report

One report: the script's counts, then the judged findings, each ending in its route in brackets.
A missing case or a gate side goes to `/evals:design`; a grader repair, a duplicate to delete or
a drifted tag goes to `/evals:validate` after the edit; an uncalibrated judge goes to
`/evals:plugin-eval` ("Calibrating a judge"). Each route is its own change: this skill edits no
file and starts no run.

## Next

- A missing case or gate side: /evals:design.
- A repaired case or grader: /evals:validate.
