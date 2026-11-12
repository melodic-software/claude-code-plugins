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
| `emit-plugin-eval` | Writes `claude plugin eval` cases (`tool_used: Skill`) per probe | On demand, one plugin's cases per run. Each case's `plugins:` list loads the target plugin and every competitor's plugin, so cross-plugin rivals compete (field: the pointer under [Report fields](#report-fields)); emit exits 2 when a competitor's plugin is not under `plugins/`. Run such cases against the repo root, as the emitted README shows. |
| Headless `claude -p` | Live selection with the whole installed set | On demand, documented, not wrapped here. Replay its fire/quiet bits through `compare`. |

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
  plugins/skill-quality/probes probe-evals/skill-quality
```

From a session, `/skill-quality:check measure-invocation` is the same script.

## Probe shape

One JSON file per skill under `probes/` (not `probes/baselines/`):

- `skill`, `plugin`, `skill_dir` (repo-relative directory holding `SKILL.md`)
- `competitors[]`: rival `plugin:skill` ids. The floor reads each rival's listing from
  `plugins/<plugin>/skills/<skill>`, derived from the id, and fails the skill when that directory
  holds no `SKILL.md`. An optional `competitor_dirs` map of id to directory overrides the derived path, for a
  rival outside this repository's `plugins/` tree.
- `queries[]`: `id`, `split` (`train` or `validation`), `expect_trigger`, `request`

Target: roughly 20 labeled queries, both polarities, both splits. `validate`
FAILs under 8, WARNs outside 16–24.

## Seed set

CI has no live `harness-ops:audit-skill-visibility` starvation report. The seed
is two skills chosen for competitor density, not for a claimed starvation rank. Each
probe file sits in its own plugin's `probes/` directory, so no probe file holds a path
into another plugin:

- `skill-quality:check` against `playbooks:skill-authoring` (check vs write), in
  `plugins/skill-quality/probes/`
- `mcp-tools:audit` against `mcp-tools:audit-posture` (tool design vs supply chain), in
  `plugins/mcp-tools/probes/`

Replace the seed when a starvation report is in hand. Fleet-wide description
rewrites stay attended and are not filed from this harness.

## Baseline (2026-10-01, listing-overlap)

Committed beside each seed probe set, at `probes/baselines/listing-overlap.json` in that
plugin; `compare` needs a baseline over the same skill set as the score it reads, so
compare a plugin's score against that plugin's baseline. Positive trigger rate is 1.0
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

Run the emitted cases with `--ablation none --keep-temp --disallow-tools Read Glob Grep Agent`,
as the emitted README shows. The run workspace is empty, so an agent that can search looks
outside it, and `run-validity.py` fails the run on those denied calls. An agent that can dispatch
a subagent, after the skill loads, hands it the task, and the run outlives its timeout. A case's
`allowed_tools` only adds tools, so `--disallow-tools` is what removes them. `run-validity.py`
reads the traces, which resolve only with `--keep-temp`, and its `probe tools` check warns when a
probe run could still call one of these tools.

- **Pointer**: `claude plugin eval --help`, the `--disallow-tools` line; the plugin-evals page,
  <https://code.claude.com/docs/en/plugin-evals#grant-tools>, documents grants only. **As of**:
  2026-11-01, Claude Code 2.1.316. **Recheck trigger**: the flag leaves the help, that page
  documents removing a tool per case, or a kept probe trace's init line lists Agent (as `Task`)
  with the flag passed.

No script ingests `plugin-eval` or `claude -p` results. Turning them into a report JSON
that matches `score` output, so `compare` can diff it against the baseline, is a manual step
today.

## Description controls

A description change ships only when its control drops clearly below the shipped text:
a generic description, in the same competitor listing, must draw a noise-report `case drop`
that reproduces, or a mean fall of 0.15 or more. Without that drop the part is unmeasurable,
and the before text ships. This is the description case of the negative-control step in
`/playbooks:skill-authoring`'s rewrite-a-plugin reference.

- **Competitor set:** the probe file's `competitors[]`. Emit reads that field and writes each
  case's `plugins:` from it, so the run's listing and the recorded set cannot drift apart.
- **The swap:** stage two copies of the repository's `plugins/` (`git archive HEAD plugins`),
  each under its own directory. In the control copy, replace only the skill's `description:`
  line with a generic one, such as `"Helper for repository maintenance tasks."`, and leave
  the shipped SKILL.md as it is. Emit each copy's cases into that copy's
  `probe-evals/<plugin>`, then run both copies together against their own roots.

Recorded runs (2026-11-02: Claude Code 2.1.316, Sonnet 5.5, 3 runs per probe, all passes VALID,
every competitor present on each with-arm init line):

| Skill | Competitor plugins | Should-trigger fired, shipped / control | Should-not quiet | Mean | Verdict |
|---|---|---|---|---|---|
| `naming:name-it-better` | docs-hygiene, docs-naming, domain-driven-design | 30/30 / 11/30 | 30/30 / 30/30 | 1.000 / 0.683 | measurable: 7 case drops |
| `domain-driven-design:curate-language` | planning, naming, docs-hygiene, architecture | 27/27 / 27/27 | 27/27 / 26/27 | 1.000 / 0.981 | unmeasurable: one drop that did not reproduce |
| `domain-driven-design:curate-language` | the same plus knowledge | 27/27 / 27/27 | 27/27 / 27/27 | 1.000 / 1.000 | unmeasurable: no case drop |

Why `curate-language` cannot drop: in both listings no competitor took any of its
should-trigger probes, even against the generic description, so the skill still won them by
elimination. Competitors did take near-miss should-not probes on both sides
(`docs-hygiene:rename-references`, `planning:design`, `naming:name-it-better`), and
no `knowledge` skill was called. Its probe set needs should-trigger queries that a
neighboring skill could plausibly take, frozen before any description cut.

Those queries and cross-plugin rivals are not always enough. On 2026-11-04 (Claude Code 2.1.318,
Opus 5.5, 3 runs per probe, all passes VALID, every rival on the init line) four
`architecture` skills got 6 blind should-trigger probes each, written to contest a named rival:

| Skill | Rival plugins added | Should-trigger fired, shipped / control |
|---|---|---|
| `architecture:map-data` | discovery, visualization | 18/18 / 18/18 |
| `architecture:map-events` | discovery, event-storming, visualization | 18/18 / 18/18 |
| `architecture:map-flow` | debugging, discovery, visualization | 18/18 / 18/18 |
| `architecture:map-deployment` | discovery, visualization | 18/18 / 18/18 |

All four are unmeasurable, so they keep the before text.

The name is what keeps such a control firing, at least on Opus. On the same version and model,
three `code-metrics` leaves ran the description-only control, then a control that also renamed the
skill's folder (each row 27 runs per arm, 9 should-trigger probes at 3 runs, all passes VALID):

| Skill | Should-trigger fired, shipped / description control / name and description control |
|---|---|
| `code-metrics:audit-coverage` | 27/27 / 27/27 / 0/27 |
| `code-metrics:audit-duplication` | 27/27 / 27/27 / 0/27 |
| `code-metrics:audit-suppressions` | 27/27 / 27/27 / 0/27 |

A renaming control shows that a probe set can fail, and nothing about the description, because it
removes the skill from view, so it falls all or nothing and never certifies a cut. These three are
unmeasurable and keep the before text. `naming:name-it-better` above shows the description control
can still drop, on Sonnet 5.5.

## Outside the marketplace checkout

The shipped seed probes name skills of this marketplace checkout (`plugins/skill-quality/...`
here, `plugins/mcp-tools/...` in the `mcp-tools` plugin) through repo-relative `skill_dir` values. In a plugin-cache install
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
paired normal-approximation interval over the per-probe hit changes of the positive
probes, matched by id between the two reports and clamped to [-1, 1]. It is null when
fewer than 2 probes pair or the positive probe ids differ between the reports.
`trigger_rate_within_noise` is true when that interval contains 0; stderr repeats it
as one INFO line per split. With about 4 to 6 positives per split, only a consistent
shift clears noise. When no probe changes, or every probe changes the same way, the
interval has zero width, so read the probe count before trusting it.

`emit-plugin-eval` writes `runs: 3` per case; the `plugin_eval_runs` setting in `skill-quality.yaml`
(README, Settings) changes it, and `--runs N` beats the setting.

- **Pointer**: for what one `claude plugin eval` run loads, the case-level `plugins` field, and
  how many times a case runs by default, fetch
  <https://code.claude.com/docs/en/plugin-evals#choose-what-to-evaluate>,
  <https://code.claude.com/docs/en/plugin-evals#prompt-md-fields> and
  <https://code.claude.com/docs/en/plugin-evals#how-a-case-is-scored> live. **As of**:
  2026-11-02. **Recheck trigger**: any of those sections changing what one run loads, how
  `plugins` paths resolve, or the default run count.
- **Pointer**: the plugin-evals page does not say which directories a case's `plugins` may name;
  the CLI's load error does ("outside the containment root ... Only plugins under it can be
  loaded"), so a case naming a sibling plugin runs against the directory holding `plugins/`.
  **As of**: 2026-11-02, Claude Code 2.1.316. **Recheck trigger**: the page documents the
  containment root, or a `plugins/<plugin>` target loads a sibling plugin.

## Trigger-phrase preservation

A description rewrite still has to pass `check-skill.sh` check 3 (advisory drop
warning vs the base ref). A dropped quoted trigger that this harness needed is
a failed rewrite, not a measurement win.
