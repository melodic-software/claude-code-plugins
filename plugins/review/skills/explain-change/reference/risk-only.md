# Risk-only action (`--risk-only`)

Rates one pull request's risk areas and nothing else: no policy check, no digest, no page, no quiz.
Run it when asked for the risk map alone, or when a caller wants a second read on whether a merge
needs a human.

## Steps

1. Read the head the rating applies to: `gh pr view <n> --repo <owner/repo> --json headRefOid,title,files`.
2. Read the diff with `gh pr diff <n> --repo <owner/repo>` and write the risk rows: area, level
   (`LOW`, `MEDIUM`, `HIGH`, or `CRITICAL`), and why. Levels are labels, not a computed score.
3. Check the rows with the fresh-context agent and brief of SKILL.md step 3, set each row's
   `check` and `checker` by its rules, and keep both levels.
4. Set `demote` (below), print the result, and stop. Never run `digest-policy.mjs` or
   `build-digest.mjs` for this action.

## The result

A markdown table of the rows, then this block:

```json
{"pr": 0, "head": "", "risks": [{"area": "", "level": "", "why": "", "check": "agreed|disputed|added|unchecked", "checker": ""}], "demote": false}
```

`demote` is `true` when any row's `level`, or the level in its `checker`, is `HIGH` or `CRITICAL`.
A disputed row counts at the higher of the two levels.

## What `demote` may do

`demote: true` may only turn an unattended merge of that head into a human merge. `demote: false`
never makes a pull request merge-eligible, never lifts a hold, and never raises a merge rung: the
merge gate in force decides alone. A new head needs a new rating. The action itself posts nothing
and gates nothing (SKILL.md step 5); a gate that reads `demote` follows these rules.
