# Fleet eval corpus vs Agent Skills evaluation pipeline

This document records a gap analysis of the marketplace fleet's `evals/evals.json` corpus (303 skill-level files on
2026-09-29; the corpus grows, so treat the count as a dated snapshot, not a pinned value) against the pipeline described in Anthropic's [evaluating
skills](https://agentskills.io/skill-creation/evaluating-skills) guidance and the `skill-creator`
reference on `claude-plugins-official`.

**Method:** read the official pipeline elements, map each to an existing fleet surface (`evals.json`,
`/evals:plugin-eval`, `/evals:design`, `/skill-quality:check validate-evals`, subagent dispatch
patterns), and record one verdict per row. Where two levels differ (for example plugin versus
skill `evals.json`), the row carries one scoped verdict per level.

**Status of the verdicts:** this is a read-only analysis. Every **adopt** verdict is a proposal,
re-gated to the operator one element at a time (operator decision on #3614, 2026-09-27); none is
decided here.

| Pipeline element | Fleet today | Verdict | Notes |
|---|---|---|---|
| With-skill vs without-skill baseline runs | `claude plugin eval` runs each plugin case twice (with / without) and writes `aggregate-result.json`; `/evals:plugin-eval` documents the delta read order. Per-skill `evals/evals.json` cases are prompt + `expectations[]` only, with no built-in no-skill arm. | **already-covered** (plugin) / **adopt** (skill `evals.json`) | Plugin-level baselines are covered. Skill-level files should document when a no-skill arm is required and route authors to `plugin eval` or an explicit A/B harness for whole-plugin claims. |
| Workspace / iteration directory layout | Plugin eval uses the CLI's suite layout; consumer repos use `docs/eval-criteria/` via `/evals:design`. No fleet-wide convention for iteration folders beside `.work/` memory slices during skill iteration. | **adopt** | Add a documented iteration layout in `/evals:design` output (criteria doc + eval dir + run artifacts) mirroring skill-creator's propose/run/review folders without requiring that plugin. |
| Assertion discipline (verifiable, specific, countable; not vague or brittle) | `skill-quality` ships `evals.schema.json` and `validate-evals`; cases use `expectations[]` strings. [Assertion discipline measurement](#assertion-discipline-measurement) counts the corpus: a screen for vague wording flags a small share of strings, and no count of truly vague expectations exists. | **already-covered** (mechanism) / **adopt** (enforcement) | Keep schema validation; extend lint or review guidance to refuse untestable expectation phrasing (same bar as planning sanity checks). |
| Script-based grading for mechanical checks; blind LLM judge for holistic quality | Methodology reference describes code-graded vs LLM-graded paths. Most fleet `evals.json` files are LLM-grader-shaped natural-language expectations only. | **adopt** | Prefer script or deterministic graders in `evals:validate` / future runner hooks where output is constrainable; reserve LLM judge for holistic rows and document blindness requirements. |
| Benchmark deltas weighing pass-rate against token/time cost | `/evals:plugin-eval` preflight prints `estimate_usd` and reads results with cost awareness; `max_cost_usd` user config caps spend. Skill-level eval files do not record token/time budgets per case. | **already-covered** (plugin-eval) / **adopt** (corpus metadata) | Plugin path is covered. Add optional per-suite metadata for expected cost class so triage can compare pass-rate wins against price. |
| Closed propose → apply → rerun → review loop | `/playbooks:skill-authoring` and `skill-quality` document the loop; nothing in CI reruns evals on skill edits by default. | **adopt** | Wire highest-value skills to optional CI or lane hooks that rerun a bounded eval subset on skill diff (cost-gated), matching the documented loop. |
| Subagent isolation as clean-context eval mechanism | Planning, discovery, implementation, and review plugins dispatch purpose-built agents; plugin eval runs cases in isolated CLI sessions. | **already-covered** | Fleet already treats clean context as default for verification-style work; eval runners should keep prohibiting implementer numbers in verifier briefs (same pattern as `/performance:verify`). |
| Task-completion notification as token/duration metrics source | `/claude-ops:observability` and session tooling expose usage; not wired into eval aggregate JSON for skill `evals.json` runs. | **rejected** (for skill evals.json runner) | Official guidance targets Claude Code task notifications; this repo's skill eval format is static prompt grading, not live harness telemetry. Revisit only if the fleet adopts a single runner that executes cases inside Claude Code and records completion metrics. |
| Compare against `skill-creator` on `claude-plugins-official` before building parallel infra | `/evals:design` and playbooks cite skill-creator and `plugin eval` separation. [Reference implementation: skill-creator coverage](#reference-implementation-skill-creator-coverage) records the comparison; no automated diff vs upstream skill-creator exists. | **adopt** | The one-time comparison is done. What remains is a periodic manual or scripted re-run against upstream skill-creator before expanding fleet runner scope, with deltas recorded in this file. |

## Reference implementation: skill-creator coverage

Read on 2026-09-29 in `anthropics/claude-plugins-official` at `fbe07fb6ce7d`, under
`plugins/skill-creator/skills/skill-creator/`. Paths below are relative to that directory.

**What it ships**

| Group | Files | What it does |
|---|---|---|
| Procedure | `SKILL.md` | Prose the agent follows: spawn a with-skill and a baseline subagent per case in one turn, draft assertions while they run, save timing, grade, aggregate, review, improve, rerun |
| Grading, comparison, analysis | `agents/grader.md`, `agents/comparator.md`, `agents/analyzer.md` | Grade expectations against a transcript and critique weak ones; compare two outputs without knowing which skill made them; explain a comparison after unblinding it and, in a second section, flag non-discriminating or high-variance assertions in a benchmark |
| Benchmark | `scripts/aggregate_benchmark.py` | Reads each run's `grading.json` and writes `benchmark.json` and `benchmark.md`: mean, stddev, min and max for pass rate, time and tokens, plus the with-skill versus baseline delta |
| Review UI | `eval-viewer/generate_review.py`, `eval-viewer/viewer.html` | A local page with an outputs tab (a feedback box per case) and a benchmark tab; writes `feedback.json` |
| Description tuning | `scripts/run_eval.py`, `scripts/run_loop.py`, `scripts/improve_description.py`, `scripts/generate_report.py`, `assets/eval_review.html` | Test whether a skill's description makes Claude trigger the skill for a set of queries, split the set into train and held-out, propose a better description, report each attempt, and edit the query set in a page. This tunes the description; it does not run a skill's output cases |
| Validation, packaging | `scripts/quick_validate.py`, `scripts/package_skill.py` | Check `SKILL.md` frontmatter (it reads no `evals.json`); build a `.skill` archive that leaves the skill root's `evals/` directory out |
| Schemas | `references/schemas.md` | `evals.json`, `history.json`, `grading.json`, `metrics.json`, `timing.json`, `benchmark.json`, `comparison.json`, `analysis.json` |

Its `evals.json` case fields (`prompt`, `expected_output`, `files`, `expectations`) match the fleet's rich form; its per-run `eval_metadata.json` names the same list `assertions`.

**What it does not ship:** a runner for a skill's output cases (the with-skill and baseline runs are subagents the agent spawns from `SKILL.md`); a static check of expectation phrasing; reusable script graders (`SKILL.md` tells the agent to write and run a script for any assertion that can be checked programmatically); a CI or scheduled rerun; and any cost or time budget stored in `evals.json`.

**Coverage by pipeline row**

| Pipeline row | skill-creator surface | Covers it? |
|---|---|---|
| Baseline runs | `SKILL.md` step 1: `without_skill` for a new skill, an `old_skill` snapshot when improving | Yes, as instructions. No script runs it and it does not touch `evals.json` |
| Workspace layout | `SKILL.md` and `references/schemas.md`: `<skill>-workspace/iteration-N/eval-<id>/{with_skill,without_skill}/outputs/` beside `eval_metadata.json`, `timing.json`, `grading.json`, `benchmark.json`, `feedback.json` | Yes. The fleet proposal is to mirror this layout, not design one |
| Assertion discipline | `SKILL.md` step 2; the critique step of `grader.md`; the benchmark section of `analyzer.md` | Partly: guidance and post-run critique, no static lint |
| Script grading, blind judge | `SKILL.md` step 4 (write a script when checkable); `comparator.md` and `analyzer.md` (blind A/B, then unblind) | Blind judge: yes, optional. Script graders: instruction only, none ship |
| Benchmark deltas | `aggregate_benchmark.py`; `timing.json` | Yes, in the run workspace. Nothing is written into `evals.json` |
| Closed loop | `SKILL.md` "Improving the skill" and `--previous-workspace`; `run_loop.py` for descriptions only | Yes, interactively. No CI rerun |
| Subagent isolation | `SKILL.md` step 1 (one subagent per run) and the grader agent | Yes |
| Task-completion notification | `SKILL.md` step 3 saves `total_tokens` and `duration_ms` from it into `timing.json`, by hand | Used, without a runner |
| Comparison against skill-creator | This section | Done once; not automated |

**Verdict effect.** No verdict cell changes; every verdict stays a proposal for the operator gate. The comparison narrows three adopt proposals: the skill-level baseline row becomes a pointer to `SKILL.md` step 1, the layout row becomes mirroring the layout above, and the script-grading row keeps only its script-grader half, because the blind-judge half is `comparator.md`. It also weakens the premise of the task-completion-notification rejection: the notification is a usable metrics source for a run without a fleet runner, so whether to reopen that row is a question for the operator gate.

## Assertion discipline measurement

Measured on 2026-09-29 (`origin/main` at 8ad20db24) over `git ls-files 'plugins/*/evals/evals.json'`:

| Measure | Count |
|---|---|
| `evals.json` files (all parse) | 303 |
| Cases | 2,230 |
| Cases with no `expectations[]` (`expected_output` only, which the schema allows) | 47 |
| Expectation strings | 8,327 |
| Fewer than 6 words | 230 (2.8%) |
| Contains a quality word | 186 (2.2%) |
| Contains a strongly evaluative word | 20 (0.2%) |

The rule is a screen, not a verdict. A string is **short** when it has fewer than 6 whitespace-separated words. It contains a **quality word** when a case-insensitive word-boundary match finds one of: good, appropriate, reasonable, properly, correctly, well, clear, useful, helpful, adequate, relevant, sensible, quality, effective. It contains a **strongly evaluative word** when it matches one of those except well, clear, relevant, quality and effective, which mostly appear as technical or idiomatic terms. The script:

```python
import json, re, subprocess

QUALITY = "good appropriate reasonable properly correctly well clear useful helpful adequate relevant sensible quality effective".split()
NOISY = {"well", "clear", "relevant", "quality", "effective"}


def screen(words):
    return re.compile(r"\b(" + "|".join(words) + r")\b", re.I)


any_word, strong_word = screen(QUALITY), screen([w for w in QUALITY if w not in NOISY])
files = subprocess.run(["git", "ls-files", "plugins/*/evals/evals.json"],
                       capture_output=True, text=True, check=True).stdout.split()
cases = no_exp = total = short = quality = strong = 0
for path in files:
    for case in json.load(open(path))["evals"]:
        cases += 1
        exps = case.get("expectations") or []
        no_exp += not exps
        for e in exps:
            total += 1
            short += len(e.split()) < 6
            quality += bool(any_word.search(e))
            strong += bool(strong_word.search(e))
print(len(files), cases, no_exp, total, short, quality, strong)
```

Both broad screens over-match, so they bound the defect and do not count it. The short strings are mostly precise, checkable statements ("Modifies no file", "Writes no findings file", "Routes to /pixel-art:sprite"). "effective" (61 strings) and "quality" (34) account for most of the broad screen and are technical terms ("the effective value", "skill-quality"). No count of vague expectations exists, and getting one needs a person or a model to read a sample.

A hand read of the 20 strongly evaluative strings found at least four that leave the qualifier undefined:

- `plugins/code-tidying/skills/batch-simplify`: "Runs ecosystem-appropriate verification after each group"
- `plugins/testing/skills/audit`: "Output notes the skill is read-only on the suite and routes repair to the appropriate lane"
- `plugins/skill-quality/skills/check`: "Output redirects the user to an appropriate skill-authoring path"
- `plugins/claude-ops/skills/plugins`: "The response redirects to the appropriate `claude plugin` CLI command (or the converge action) instead of manual state surgery"

## Proposed adoptions for the operator gate (priority)

Each proposal is tracked, with a recommendation and its basis, in the umbrella intake issue [#5255](https://github.com/melodic-software/claude-code-plugins/issues/5255). None is decided here.

1. Skill-level **no-skill arm** documentation and routing (`evals.json` → when to use `plugin eval`).
2. **Script graders** for mechanical expectations in high-traffic skills.
3. **Cost metadata** on suites that run through `plugin eval`.
4. Optional **CI rerun** hook for skill edits (cost-capped).

## Recorded verdict summary

| Row verdict | Rows |
|---|---|
| already-covered only | 1 |
| adopt only | 4 |
| already-covered at one level, adopt at another | 3 |
| rejected | 1 |
| **Total** | **9** |

Acceptance for #3614: each pipeline element above carries **adopt**, **already-covered**, or
**rejected** with reason.
