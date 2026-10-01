# Invocation probes

On-demand harness for #3526: whether a skill's `description` would win the
requests it should, and stay quiet on the ones it should not.

## What this measures

Auto-invocation is the model matching a user request against listing text. Static
gates (`check-skill.sh` length cap, trigger-phrase preservation) do not measure
that match. This harness does, in two layers:

| Method | What it is | When to run |
|---|---|---|
| `listing-overlap` | Deterministic floor: quoted-trigger hits plus content-token overlap against the target listing and named competitors | By hand, before and after a rewrite (`score` then `compare`). CI validates the probe schema and runs the harness tests only. The committed baseline uses this method. |
| `emit-plugin-eval` | Writes `claude plugin eval` cases (`tool_used: Skill`) per probe | On demand, within one plugin. The CLI loads a single plugin, so cross-plugin competitors are out of scope for this method. |
| Headless `claude -p` | Live cross-plugin selection | On demand, documented, not wrapped here. Replay its fire/quiet bits through `compare`. |

`listing-overlap` is **not** a model-graded auto-invocation rate. A high floor
means the listing text already contains the request's nouns; a low floor means
a rewrite still has room. The exit criterion for a rewrite is a validation-split
gain on a model-graded run, with trigger-phrase preservation still passing.

Packed `description` vs `when_to_use` is out of scope: the harness joins them
the same way the listing does (`check-skill.sh` combined-length check).

## Command

```shell
# Schema, polarity, train/validation split, roughly-20 count, copied listing words
bash plugins/skill-quality/scripts/measure-invocation.sh validate plugins/skill-quality/probes

# Lexical floor, JSON on stdout, per-split rates on stderr
bash plugins/skill-quality/scripts/measure-invocation.sh score plugins/skill-quality/probes \
  > /tmp/invocation-score.json

# Delta versus the committed baseline (train and validation separately)
bash plugins/skill-quality/scripts/measure-invocation.sh compare \
  plugins/skill-quality/probes/baselines/listing-overlap.json \
  /tmp/invocation-score.json

# Emit plugin-eval cases for a live run
bash plugins/skill-quality/scripts/measure-invocation.sh emit-plugin-eval \
  plugins/skill-quality/probes /tmp/invocation-eval-cases
```

From a session, `/skill-quality:check measure-invocation` is the same script.

## Probe shape

One JSON file per skill under `probes/` (not `probes/baselines/`):

- `skill`, `plugin`, `skill_dir` (repo-relative directory holding `SKILL.md`)
- `competitors[]` and `competitor_dirs` (how the floor finds rival listings)
- `queries[]`: `id`, `split` (`train` or `validation`), `expect_trigger`, `request`

Target: roughly 20 labeled queries, both polarities, both splits. `validate`
FAILs under 8, WARNs outside 16–24.

## Seed set

CI has no live `harness-ops:audit-skill-visibility` starvation report. The seed
is two skills chosen for competitor density, not for a claimed starvation rank:

- `skill-quality:check` against `playbooks:skill-authoring` (check vs write)
- `mcp-tools:audit` against `mcp-tools:audit-posture` (tool design vs supply chain)

Replace the seed when a starvation report is in hand. Fleet-wide description
rewrites stay attended and are not filed from this harness.

## Baseline (2026-10-01, listing-overlap)

Committed at `probes/baselines/listing-overlap.json`. Positive trigger rate is 1.0
on both skills and both splits: current descriptions already contain the request
nouns the seed positives use, even with no positive copying four or more
consecutive listing words. False-trigger rates are the gap the floor can see:

| Skill | Train false-trigger | Validation false-trigger |
|---|---|---|
| `mcp-tools:audit` | 0.00 | 0.25 |
| `skill-quality:check` | 0.33 | 0.50 |

False positives on this floor are token-greedy: `check this SKILL.md before publishing`
scores as `mcp-tools:audit` because that listing contains `check`; `write me a brand-new
skill` scores as `skill-quality:check` because that listing contains `skill`. That is why
the floor is not a model-graded auto-invocation rate, and why a rewrite's exit criterion
is a validation-split gain on a live plugin-eval or `claude -p` run.

## Probe wording

Write should-trigger probes the way a user would ask, not in the description's words. A
probe that quotes the listing measures the copy, so `validate` WARNs when a should-trigger
probe shares 4 or more consecutive words with the target listing (`--copy-span N` changes
the span). Should-not-trigger probes are exempt.

## emit-plugin-eval results

No script ingests `plugin-eval` or `claude -p` results. Turning them into a report JSON
that matches `score` output, so `compare` can diff it against the baseline, is a manual step
today.

## Outside the marketplace checkout

The shipped seed probes name skills of this marketplace checkout (`plugins/mcp-tools/...`,
`plugins/skill-quality/...`) through repo-relative `skill_dir` values. In a plugin-cache install
none of those paths exist, and `score` stops with exit 2 and says so. Pass your own probes
directory (same JSON shape, `skill_dir` relative to your repo root or absolute), or set
`MEASURE_INVOCATION_REPO_ROOT` to the repo root the probes name. When only some probe files
resolve, `score` keeps its per-skill error and exits 1. `validate` keeps a WARN per unresolved
`skill_dir` and ends with one INFO line giving the count, so it stays green in the marketplace
repo.

## Report fields

Per skill, per split: `n`, `n_positive`, `n_negative`, `trigger_rate`
(positives that the method selected), `false_trigger_rate` (negatives it
selected). `compare` prints treatment minus baseline for both rates on both
splits so a rewrite cannot hide a validation drop behind a train gain.

Each trigger-rate delta also carries `trigger_rate_delta_interval`, a 95%
normal-approximation interval over the baseline and treatment `n_positive` for that split,
clamped to [-1, 1] and null when either rate falls outside [0, 1], and
`trigger_rate_within_noise`, true when that interval contains 0; stderr repeats it
as one INFO line per split. With about 4 to 6 positives per split, only a large
delta clears noise. When both rates are 0 or 1 the interval has zero width, so
read the probe count before trusting it.

`emit-plugin-eval` writes `runs: 3` per case, the CLI's default; `--runs N`
changes it.

## Trigger-phrase preservation

A description rewrite still has to pass `check-skill.sh` check 3 (advisory drop
warning vs the base ref). A dropped quoted trigger that this harness needed is
a failed rewrite, not a measurement win.
