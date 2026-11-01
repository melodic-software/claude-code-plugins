# Stage-order baseline

This file records rounds, re-verifications, and turns and minutes per merged pull request. They were measured before the pipeline's stage order changes (#10205), and a later reorder is judged against them.

## Window and sources

Measured 2026-11-01. The window is pull requests merged in the 7 days before the measurement, 2026-10-24T23:56Z to 2026-10-31T23:56Z: 1,400 of them. Every figure comes from list reads, each made once and saved:

- Pull requests: `GET /repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=100`.
  - 17 pages, filtered on `merged_at`.
- Run artifacts: `GET /repos/{owner}/{repo}/actions/artifacts?per_page=100`.
  - 112 pages, back to 2026-10-22T23:21Z.
  - Deduplicated by artifact `id`: 11,192 artifacts.
- Turns and minutes: `GET /repos/{owner}/{repo}/actions/artifacts/{id}/zip`, reading `act-turns.json` from each.
  - A random sample of 60 of the 1,725 `skill-reply-*` artifacts.

## Figures

| Measure | Cohort | Mean | Median | p90 | Max |
|---|---|---|---|---|---|
| pr-verify runs per PR | 1,400 merged | 1.57 | 1 | 3 | 11 |
| Re-verifications per PR | 1,400 merged | 0.60 | 0 | 2 | 10 |
| Address-feedback rounds per PR | 235 created after 2026-10-31T00:30Z | 0.07 | 0 | 0 | 2 |
| Address-feedback runs ÷ merged PRs | 1,400 merged | 0.16 | | | |
| Code-review runs per PR | 235 created after 2026-10-31T00:30Z | 1.49 | 1 | 3 | 7 |
| Lane turns ÷ merged PRs | 1,400 merged | 55.5 (estimate) | | | |
| Lane model minutes ÷ merged PRs | 1,400 merged | 5.8 (estimate) | | | |
| Minutes from open to merge | 1,400 merged | 193 | 56 | 514 | 6,783 |
| Tokens per merged PR | | unavailable | | | |

### Re-verifications

- A re-verification is every pr-verify run on a pull request after its first.
- Each pr-verify run uploads one `pr-verify-<pr>-<head sha>-<verdict>` artifact.
  - The 2,822 listed artifacts come from 2,822 distinct runs.
  - The artifacts are kept 90 days, so the count covers the whole window.
- Totals: 1,360 of the 1,400 pull requests had a run, with 2,203 runs and 843 re-verifications. 194 of the runs gave a fail verdict.

### Rounds

The counter that `loop.review-rounds` caps is the `<!-- pr-unblock:address-feedback-round -->` marker comment on each pull request ([Loop caps](README.md#loop-caps)). `publish-feedback.mjs` posts one marker per address-feedback model run. Counting the markers would take one comment read per pull request, so this baseline counts address-feedback runs instead:

- **Per pull request:** the cohort is the 235 pull requests created and merged in the last day. 193 of them were reviewed.
  - **Dispatches.** Each `pr-feedback-dispatched-<review run>-<feedback run>` artifact records one dispatched pr-unblock run, not one model run. `pr-feedback-dispatch.yml` uploads it whenever the dispatch step returns a run id.
  - **Join.** A dispatch joins its pull request through the review run's `pr-review-cli-handoff-*` artifact and that artifact's head branch. Both artifacts are kept 1 day.
  - **Where the 80 dispatches landed:**
    - 31 on cohort pull requests.
    - 3 on merged pull requests created before the cohort.
    - 34 on pull requests closed unmerged.
    - 11 on pull requests still open.
    - 1 with no review artifact.
  - **Rounds.** A round is a dispatched run that reached the address-feedback model run, which is the run `publish-feedback.mjs` posts a marker for. A `skill-reply-pr-unblock-address-feedback-*` artifact in the same workflow run shows it got there.
    - 17 of the 31 cohort dispatches reached it, on 14 pull requests: 17 ÷ 235 = 0.07.
    - The other 14 dispatched runs stopped before the model run.
    - On the day as a whole, 39 of the 80 dispatched runs reached it. The day's 46 address-feedback model runs also include 7 that started without a dispatch.
- **Across the 7 days:** 227 `skill-reply-pr-unblock-address-feedback-*` model runs, on all pull requests including unmerged ones. 227 ÷ 1,400 merged = 0.16. This is a ratio of runs to merged pull requests, not a per-PR count.

### Turns and minutes

- `act-turns.json` holds the `num_turns` and `duration_ms` of each model run in `pr-run-activity-read.yml` and `pr-run-activity-write.yml`. It is kept 7 days.
  - The oldest kept artifact is from 2026-10-25T00:07Z, 11 minutes into the window.
- **The sample:**

  | | Mean | Median | Standard deviation |
  |---|---|---|---|
  | Turns | 45.1 | 23 | 45.4 |
  | Model minutes | 4.73 | 1.53 | 6.28 |

- **Scaled to the window:** the means times the 1,725 runs, over the 1,400 merged pull requests.

  | | Estimate | 95% interval | Weighted by lane |
  |---|---|---|---|
  | Turns | 55.5 | 41 to 70 | 58.1 |
  | Model minutes | 5.8 | 3.9 to 7.8 | 6.1 |

  The lane-weighted figure is each lane's sample mean times that lane's run count. The sample held no review-dependency run, so that lane's 14 runs are left out of it.
- **Lane runs.** The figures cover the six lane activities that upload `skill-reply-*`:

  | Activity | Runs | Mean turns | Mean minutes |
  |---|---|---|---|
  | resolve-issue | 790 | 78.4 | 9.34 |
  | fix-docs | 298 | 16.7 | 0.67 |
  | address-feedback | 227 | 25.5 | 1.60 |
  | resolve-conflicts | 213 | 21.7 | 1.18 |
  | fix-ci | 183 | 22.2 | 2.29 |
  | review-dependency | 14 | not sampled | not sampled |

  The code and security review lanes, pr-verify's judge, and runner time are not in them.

### Tokens

`act-turns.json` keeps model names, not token counts, and no stored token count was found. Tokens per merged pull request are therefore unavailable.

The sample's runs named these models: `claude-opus-5-5` 50 times, `claude-sonnet-5-5` 10 times and `claude-haiku-5-5` 7 times.

## Limits

- **Re-verifications are a floor.** pr-verify uploads its verdict artifact only when its judge step succeeds, so a run whose judge failed is not counted.
- **The one-day cohort undercounts rounds and reviews.** It holds only pull requests created and merged within about 23.5 hours. Their median time from open to merge is 41 minutes, against 56 for the whole window, so their rounds and review runs likely run low.
- **Lane turns and minutes are divided across merged pull requests only.** The numerator includes runs on pull requests that never merged, and resolve-issue runs that opened no pull request.
- **The listing has gaps and repeats.** Artifacts that expired while the listing was paged are missing from it. New artifacts shift the pages, and deduplication by `id` removes the repeats.
