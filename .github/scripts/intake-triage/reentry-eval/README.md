# Intake re-entry eval

A live model eval of intake triage on an issue that came back after a recorded decision
([#8491](https://github.com/melodic-software/claude-code-plugins/issues/8491)). It checks the
RE-ENTRY rules in the `instructions` input of [`intake-triage.yml`](../../../workflows/intake-triage.yml).

| Case | Decision | Expected |
|---|---|---|
| `partial-answer-reparks` | answers question 1 only | quote, `status: needs-decision`, question 2 asked again with `RECOMMENDED:` |
| `unsettled-assumption-asks` | answers both, names undefined "long-lived branches" | quote, `status: needs-decision`, a new question about those branches |
| `person-needed-keeps-needs-human` | answers both, first report waits on the owner's hand run | quote, `needs-human` label, `needs_human` false |
| `settled-confirms` | answers both | quote, no status label, no `needs-human`, nothing asked |

Every case also checks the decision's link, `needs_human` false, and a Read of the decision
comment, plus one `llm` grader on whether the reply re-asks a settled point or fills a gap itself.

## No prompt is kept here

`build-suite.mjs` reads the ci-workflows reusable at the commit the caller's `uses:` ref resolves
to, takes its compose step's script, and runs it with GitHub stubbed and this repository's
`allowed-labels` and `instructions`. Each case's `execution.prompt` is the prompt that script
writes, then one added line asking for the schema's JSON object as the reply (plugin eval has no
`--json-schema`), then the schema the script wrote. The committed `case.yaml` holds a placeholder.

The issue files go under `.intake-triage-eval/` in the run's workspace, in the fetch step's
shape, with `AGENTS.md` copied beside them. Paths are relative, where the lane's are absolute.
Tools are Read, Grep and Glob, as on the lane.

## Run

Subscription login only; `run.sh` refuses when an API key is in the environment. Nothing in CI
runs it: the plugin-eval workflow selects only paths under `plugins/`.

```bash
.github/scripts/intake-triage/reentry-eval/run.sh <ci-workflows clone> <out dir outside any git tree>
```

It builds two suites. `with` holds the instructions; plugin eval's default with/without ablation
runs it, and both arms tie by construction, because the stub plugin adds nothing to a
self-contained prompt. `without` is the reusable's prompt with `instructions` empty, run with
`--ablation none`: the score gap between `with` and `without` is what the instructions add.
Check `aggregate-result.json` with `/evals:plugin-eval`'s `run-validity.py`.
