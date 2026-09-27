# Gating CI on a plugin eval suite

Read when wiring the command into a pipeline, or when a green pipeline is suspected of hiding a
failure.

## Contents

- [The recipe](#the-recipe)
- [Exit codes](#exit-codes)
- [The parser](#the-parser)
- [Keeping a trend honest](#keeping-a-trend-honest)
- [What the job needs](#what-the-job-needs)

## The recipe

```bash
claude plugin eval . \
  --trust-plugin \
  --json results.json \
  --threshold 0.8 \
  --model <pinned agent model> \
  --judge-model <pinned judge model> \
  --no-publish \
  --max-cost-usd 20
```

- `--trust-plugin` is mandatory in practice. Without it a job whose checkout is untrusted is refused
  with exit 1 where there is no terminal, and waits at the prompt where the runner allocates one.
- Pin **both** models so a model rollout is not read as a plugin regression and rubric verdicts stay
  comparable. The pinned values are the operator's choice and carry their own refresh cadence:
  review them whenever the provider retires or renames a model, and record the swap alongside the
  trend so a step change in scores has a cause.
- `--threshold 0.8` rather than the default 1.0. At 1.0 every stochastic near-miss is a red build,
  and exit 1 stops carrying information.
- `--no-publish` keeps the HTML report local. It is a single self-contained file that makes no
  external requests, so attach it to the job.
- `--max-cost-usd` is the ceiling the job cannot exceed. Prefer it over tight per-run limits.
- `claude plugin eval init` needs a terminal; in CI use `init --bare <name>` for a blank template.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Every case met `--threshold` and every case file loaded |
| 1 | Overloaded across six causes: a case below threshold, a case file that failed to load, no cases found, a run that could not start, an untrusted directory without `--trust-plugin`, or an invalid option |
| 2 | Partial: the cost ceiling was hit, or the credential was rejected at or before the first run. The JSON is still written with `partial: true` |
| 130 | Interrupted. Partial results are written |
| 143 | Terminated, for example by a CI timeout |

Report writing or publishing failures never change the exit code. A typo in `--case` produces exit 1
with `No eval cases found matching --case "<glob>"`, which no exit code distinguishes from a real
failure.

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| The exit-code table above, the documented CI invocation, and the flag defaults it relies on (`--threshold` 1.0, `--judge-model` a small fast model, `--concurrency` 1 with a range of 1 to 8) | `claude plugin eval --help` plus <https://code.claude.com/docs/en/plugin-evals>, verified 2026-09-12, with the untrusted-directory refusal and the ceiling behavior reproduced locally | Recheck trigger: a release note touches `plugin eval`, or `--help` no longer matches a row. Then re-run `--help`, re-read the page, re-derive the table, and refresh this record with the outcome |

## The parser

Because exit 1 is overloaded and exit 2 still writes a document, the gate reads the JSON. Order
matters: `partial` first, then run health, and only then any score.

```bash
jq -e '
  if .partial then
    "PARTIAL: \(.partialReason)" | halt_error(2)
  else . end
  | [ .cases[]
      | select( any(.arms[][]; .skippedPaidGraders or (.error != null)) )
      | .name ] as $tainted
  | if ($tainted | length) > 0 then
      "NOT COMPARABLE: \($tainted | join(", "))" | halt_error(2)
    else . end
  | [ .cases[] | select(has("aggregates") and (.aggregates | has("delta") | not)) | .name ] as $nodelta
  | if ($nodelta | length) > 0 then
      "NO DELTA: \($nodelta | join(", "))" | halt_error(2)
    else . end
  | .aggregates.meanDelta
' results.json
```

This parser is the two-arm comparability gate, layered on top of the CLI's own threshold check: the
command already exits 1 on a below-threshold case, and the parser adds what the exit code cannot
carry. Under `--ablation none` no case has a `delta` at all, so a one-arm lane gates on
`aggregates.casesPassed == aggregates.casesTotal` and drops the last clause.

Three rules the parser encodes, each of which a naive reader gets wrong:

- An **omitted** `delta` is not zero. A case whose arms were not comparable has no delta field at
  all, and `jq`'s `//` operator would silently turn that into a passing zero.
- A run with `skippedPaidGraders: true` is not a low score, it is an unscored run: its judge graders
  were skipped and recorded as failures.
- A non-null `error` is not a zero either. The run is graded on what it produced, which is exactly
  why a rate limit reads as a regression.

## Keeping a trend honest

- Exclude every `partial: true` document and every run carrying `skippedPaidGraders` or a non-null
  `error`.
- Hold the ablation mode fixed across runs; mixing two-arm and `--ablation none` results breaks the
  line silently, because nothing is excluded from scoring in the second mode.
- Record `claudeVersion` and `suite` (`ablation`, `threshold`, `concurrency`, `caseFilter`) with
  each point, so a step change has somewhere to be attributed.
- Commit `mocks/.replay/` so agent mocks replay without a model call. It is the one lever that makes
  MCP-touching cases deterministic.

## What the job needs

- A Claude Code install at or above the version floor, and credentials in the environment.
- A sandbox backend on the runner if any case grants `Bash`, `Write`, or `Edit`: Linux needs
  `bubblewrap` and `socat`. Without one, each granting run is refused rather than run unconfined.
- Budget awareness: the command has no free mode, so an every-commit lane should use deterministic
  graders only, and the expensive judge lane should run on a schedule or on demand.
- A fallback plan for the server-side switch. The command can answer
  `plugin eval is currently unavailable`, and nothing on the runner restores it, so a required check
  built on this command can block merges for reasons no one in the repository controls.
