# select: which cases a change runs

`select` names the eval cases a branch's change affects and what running them costs, before any
run. It makes no model call. The policy it applies is `docs/review/evals.md` in this repository
("Terms", "When a run is required", "Which cases run", "Budget"); this page says how to run it and
read it.

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/plugin-eval/scripts/select-cases.py" <diff-base> [--json] [--repo <dir>]
```

`<diff-base>` is the branch's base, `origin/main` for a pull request. `--repo` names the checkout
when it is not the current directory. `--json` prints the same data as one object keyed by
plugin. Exit 0 on success, 2 when the repository or the diff base cannot be read.

## Read it

A diff that affects nothing prints `no affected cases`. Otherwise one block per affected plugin:

| Line | Meaning | What to do |
|---|---|---|
| `cases:` | Cases with at least one deterministic grader that this change must run | Pass the list as the eval workflow's `cases` input: one dispatch runs exactly these |
| `judged:` | Run-requiring cases whose graders are all judged | Run them as `docs/review/evals.md` "Where and on what" says for judged cases |
| `run-after-merge:` | Triggering and no-fire cases of an additive-only `description` or `when_to_use` edit | Merge first, then run them on the default branch |
| `affected-no-run:` | Cases the change touches that the policy runs nothing for (added body text, scripts, samples) | Nothing; they are listed so the author sees them |
| `uncovered:` | A changed skill or agent with no affected case | Add a case with `/evals:design` |
| `plugin-wide:` | Hooks, `.mcp.json`, `plugin.json` or settings changed | No automatic run; judge whether a case should run |
| `unmapped:` | A changed file no rule maps to a case | Judge it by hand |
| `unread-graders:` | A Skill or Agent grader whose `input_match` names no skill the shared rule can read | Rewrite the grader so it names its skill, or check it by hand |
| `agent-runs:` | Each run-requiring case's runs times two arms, summed | State it with the case list before dispatch |

Which skill a case tests comes from the plugin's shared `case_skills.py` rule, the same rule
`/evals:validate` reads, so the two never disagree on a case.

## Before dispatch

State the `cases:` list and the `agent-runs:` count in the pull request, then dispatch through the
eval workflow with that list as its `cases` input. A list that exceeds one run's ceiling splits
across several dispatches as "Budget" says; never drop a listed case to fit.
