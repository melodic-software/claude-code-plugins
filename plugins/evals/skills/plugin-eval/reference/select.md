# select: which cases a change runs

`select` names the eval cases a branch's change affects and what running them costs, before any
run. It makes no model call. The change classes below are what it applies: a removed or changed
instruction word is a cut that runs the affected cases, and so is a meaning-flipping word
(`MEANING_FLIP_WORDS` in `scripts/select_mapping.py`) inserted into an existing line; other added
text runs nothing, and a case,
grader, prompt, fixture or scaffold change runs its own case and the cases that call it. Where the
repository records its own eval run policy, that policy decides what each line obliges.

An edit inside a SKILL.md `## Next`, `## Related` or `## See also` section runs nothing: those
sections name other skills for the person and change no tool call. Neither does renaming a routing
heading (Boundaries, Scope boundary, Siblings, Routing, Handoff, Composition, Integration, Workflow
position, What this skill does not do) to another of those names or to Next or Related.

A decided-term swap or a comment-line deletion runs nothing anywhere: a hunk, frontmatter value,
eval case file or renamed path whose only difference swaps a term for the word the repository
glossary's "Rejected terms" table decided (`docs/glossary.md`, else `GLOSSARY.md`), or that word's
last word (`--lane` to `--area` for `focus area`), singular or plural, leaving old and new
byte-identical once each swap is replaced, or deletes lines a comment fills in a code, YAML or
shell file (`#`, `//`, `/* */`, with no code before or after it; never markdown, whose HTML
comments a model can read). A hunk with any other change keeps the rules above.

A `description` or `when_to_use` edit runs nothing when the old and new text are equal after three
removals: each routing clause (a `Not for`, `Skip` or `prefer` clause that names a `plugin:skill`),
the difference between skill tokens (`plugin:skill` against `/plugin:skill`, or a renamed skill),
and each decided-term swap. Any other wording change keeps the rule above.

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
| `no-run-exempt:` | Skills whose `description` or `when_to_use` edit is routing-only or a decided-term swap, then the reason; their triggering and no-fire cases are in `affected-no-run:` | Nothing |
| `uncovered:` | A changed skill or agent with no affected case | Add a case with `/evals:design` |
| `plugin-wide:` | Hooks, `.mcp.json`, `plugin.json` or settings changed | No automatic run; judge whether a case should run |
| `unmapped:` | A changed file no rule maps to a case | Judge it by hand |
| `unread-graders:` | A Skill or Agent grader whose `input_match` names no skill the shared rule can read | Rewrite the grader so it names its skill, or check it by hand |
| `compare-refused:` | Each changed path of the plugin that the repository's `.github/scripts/plugin-eval/select-plugins.mjs` refuses, with its reason; printed only where that script exists and Node runs it | Dispatch no compare run; merge first, then run the cases in a suite run on the default branch |
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
