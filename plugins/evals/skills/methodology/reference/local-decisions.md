# Local decisions

This repository's defaults where its eval guidance chooses between sources, and the source conflicts
behind each choice. The maintainer `update` action re-fetches only the four distilled reference
files, so a re-fetch never overwrites this file. One heading per record; each record states the
default in our words, names the setting that changes it, and carries the pointer, the conflict, the
as-of date and the recheck trigger. No source's position is restated here; read it at the link.

## Split policy

Default: a hillclimb splits the cases into train and test the way the bundled hillclimb guide does by
default. The `split_policy` setting changes it: `train-test` (default) or `reporting-only`, which
also holds back a split that no keep-or-revert decision and no final pick reads, used only to
report the result.

- **Pointer**: for the default split, see
  [eval-hillclimb.md Step 3](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-3-set-up-state-split-the-data-and-take-a-baseline).
- **Source conflict**: [eval-hillclimb.md Step 3](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-3-set-up-state-split-the-data-and-take-a-baseline)
  and [HarnessOpt-Bench](https://arxiv.org/abs/2608.06301) disagree on whether the split a result
  is reported on may also select among candidates.
- Correlate with <https://claude.dev/blog/automating-eval-design-and-hillclimbing#claude-api-hillclimb>.
- **As of**: 2026-10-01
- **Recheck trigger**: a commit to `anthropics/skills` changes Step 3 of `eval-hillclimb.md`, or a
  docs page starts covering the hillclimb split; then the pointer moves there.

## Interval method

Default: the normal approximation, with the with-versus-without difference
paired over per-case deltas. The `interval_method` setting changes it: `normal` (default),
`wilson` or `jeffreys`. Wilson and Jeffreys apply only to pass counts (cases that pass the
threshold), because a case score is not a proportion of trials; score intervals stay normal
whatever the setting.

- **Pointer**: for upstream's interval, see
  [report/SCHEMA.md PairedDelta](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/report/SCHEMA.md#paireddelta)
  and
  [eval-audit.md section 5](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md#5-can-it-detect-the-change-youre-after).
- **Pointer**: for the Wilson and Jeffreys intervals, see <https://doi.org/10.1214/ss/1009213286>.
- **Source conflict**: [report/SCHEMA.md PairedDelta](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/report/SCHEMA.md#paireddelta)
  and [Bowyer, Aitchison and Ivanova](https://arxiv.org/abs/2503.01747) disagree on the interval
  method for small evals.
- **As of**: 2026-10-01
- **Recheck trigger**: a commit to `anthropics/skills` changes `PairedDelta` in `report/SCHEMA.md`
  or section 5 of `eval-audit.md`, or the plugin-evals docs page starts reporting an interval.

## Repeat count

Default: no fixed repeat count. Repeats and cases are sized together from the suite's noise check,
and a suite whose interval is too wide gets more cases before more repeats. A kept
change is confirmed at the CLI's default run count. No setting: the run count is the CLI's own
per-case and per-invocation option.

- **Pointer**: for sizing repeats and cases together, see
  [eval-audit.md section 5](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md#5-can-it-detect-the-change-youre-after);
  for the CLI's default run count, see
  <https://code.claude.com/docs/en/plugin-evals#how-a-case-is-scored>; for repeats against more
  cases, see <https://arxiv.org/abs/2512.21326>.
- **Source conflict**: none recorded.
- **As of**: 2026-10-01
- **Recheck trigger**: the plugin-evals page changes its default run count, or a commit to
  `anthropics/skills` changes section 5 of `eval-audit.md`.

## Rubric form

Default: a judge rubric is a list of checkable pass/fail claims. The 1-to-5 recipes in
[recipes.md](recipes.md) are the platform page's and stay labeled as that page's.

- **Pointer**: for checkable rubric properties, see
  [eval-audit.md, When the grader is an LLM judge](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md#when-the-grader-is-an-llm-judge).
- **Source conflict**: [Define success criteria and build evaluations, Example evals](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#example-evals)
  and
  [eval-audit.md, When the grader is an LLM judge](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md#when-the-grader-is-an-llm-judge)
  disagree on rubric form.
- Correlate with <https://claude.dev/blog/automating-eval-design-and-hillclimbing#validating-the-grader>,
  which departs from the platform page on rubric form as of 2026-10-01.
- **As of**: 2026-10-01
- **Recheck trigger**: the platform page changes its Example evals section, or a commit to
  `anthropics/skills` changes the LLM-judge section of `eval-audit.md`.

## Review output

Default: `/evals:design` shows candidate cases for approval as a Markdown file, a table plus one
fenced block per case. The `review_format` setting changes it: `markdown` (default) or `html`.
This repository renders its HTML option itself, with
[render-review.py](../../design/scripts/render-review.py), because skill-eval cases follow this
repository's own schema. The renderer escapes every key and value.

- **Pointer**: for input approval and the report builder, see
  [build-eval.md, Get the inputs approved](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#get-the-inputs-approved).
- **Source conflict**: [build-eval.md, Get the inputs approved](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#get-the-inputs-approved)
  and this repository's [render-review.py](../../design/scripts/render-review.py) disagree on
  which HTML surface may show case text for review.
- **As of**: 2026-10-01
- **Recheck trigger**: the builder accepts skill-eval cases; then route the `html` format through it
  and drop the renderer's own HTML.
