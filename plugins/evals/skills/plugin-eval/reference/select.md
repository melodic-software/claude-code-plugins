# select: which cases a change runs

`select` names the eval cases a branch's change affects and what running them costs, before any
run. It makes no model call. The change classes below are what it applies: a removed or changed
instruction word is a cut that runs the affected cases, and so is a meaning-flipping word
(`MEANING_FLIP_WORDS` in `scripts/select_mapping.py`) inserted into an existing line; other added
text runs nothing, and a case,
grader, prompt, fixture or scaffold change runs its own case and the cases that call it. Where the
repository records its own eval run policy, that policy decides what each line obliges.

## Run it

```bash
python3 "<skill-dir>/scripts/select-cases.py" <diff-base> [--json] [--repo <dir>]
```

`<skill-dir>` is the plugin-eval skill's directory.

`<diff-base>` is the branch's base, `origin/main` for a pull request. `--repo` names the checkout
when it is not the current directory. `--json` prints the same data as one object keyed by
plugin. Exit 0 on success, 2 when the repository or the diff base cannot be read.

## Read it

A diff that affects nothing prints `no affected cases`. Otherwise one block per affected plugin:

| Line | Meaning | What to do |
|---|---|---|
| `cases:` | Cases with at least one deterministic grader that this change must run | Pass the list as the run's case filter (an eval workflow with a `cases` input takes it as is) |
| `judged:` | Run-requiring cases whose graders are all judged | Run them where a judge grades them, and check that judge against labeled samples first |
| `run-after-merge:` | Triggering and no-fire cases of an additive-only `description` or `when_to_use` edit | Merge first, then run them on the default branch |
| `affected-no-run:` | Cases the change touches that the policy runs nothing for (added body text, scripts, samples) | Nothing; they are listed so the author sees them |
| `uncovered:` | A changed skill or agent with no affected case | Add a case with `/evals:design` |
| `plugin-wide:` | Hooks, `.mcp.json`, `plugin.json` or settings changed | No automatic run; judge whether a case should run |
| `unmapped:` | A changed file no rule maps to a case | Judge it by hand |
| `unread-graders:` | A Skill or Agent grader whose `input_match` names no skill the shared rule can read | Rewrite the grader so it names its skill, or check it by hand |
| `agent-runs:` | Each run-requiring case's runs times two arms, summed | State it with the case list before dispatch |

A triggering or no-fire case is one that leaves the choice of skill to the model (its prompt does
not open with a `/plugin:skill` command) and checks a Skill call, or one tagged `triggering`,
`no-trigger` or `no-fire`. A `description` edit cannot change a case that invokes the skill by
name, so those cases are not selected for one.

Which skill a case tests comes from the plugin's shared `case_skills.py` rule, the same rule
`/evals:validate` reads, so the two never disagree on a case.

## Before dispatch

State the `cases:` list and the `agent-runs:` count in the pull request, then start the run with
that list as its case filter. A list that exceeds one run's ceiling splits
across several dispatches; never drop a listed case to fit.
