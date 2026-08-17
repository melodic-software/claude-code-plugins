# ci-health — GitHub Actions CI-health recipe (Tier 0, evidence rung 2)

Failure ratios, duration trends, and retry rates from GitHub Actions run history. Output:
CI-health candidates with citations like
`ci: 23% failure ratio, 9/40 runs retried (run_attempt > 1), 2026-07-01..2026-07-28 — rung 2`.

**Portability scope.** This recipe is GitHub-forge-specific by construction: the CI-health
*dimension* is neutral, but the mechanics below are the GitHub Actions API. On a repo hosted on
a non-GitHub forge (GitLab, Gitea, Azure DevOps, ...), record an evidence-gap line — e.g.
`gap: ci-health — non-GitHub forge; this recipe covers GitHub Actions only` — and rank without
CI evidence. Never adapt these calls by guesswork against another forge's API.

## Access probe ladder (probe in order, record the outcome)

1. **GitHub MCP tools** — the `actions_*` toolset (`actions_list`, `actions_get`,
   `get_job_logs`) in this session's tool roster. Preferred: works in cloud sessions where `gh`
   is absent. Note: in cloud sessions the MCP server is repo-scoped to attached repos — most
   reliable for the repo this invocation targets, which matches the one-repo-per-invocation
   scope.
2. **`gh` CLI** — `command -v gh` succeeds and `gh auth status` reports authentication.
3. **None** — record the evidence-gap line
   (`gap: ci-health — no GitHub access path (no MCP actions tools, no gh)`) and rank without CI
   evidence. A missing access path is never license to estimate CI health.

Derive `<owner>/<repo>` from the first configured remote URL (`git remote` /
`git remote get-url`), not from directory names.

## Never use the `/timing` endpoint

`GET /repos/{owner}/{repo}/actions/runs/{run_id}/timing` carries an official deprecation notice
("in the process of closing down") — do not build anything on it. Every duration number below
comes from run timestamps instead.

## Iterate by `created` date windows — never deep pagination

Deep page-walking of `/actions/runs` has a community-reported cap at roughly 1,000 runs
(~10 pages × 100); pages beyond it silently return nothing. The safe iteration pattern — and the
natural shape for trend buckets — is the documented `created` date filter:

- Split the analysis period (default: last 28 days, in 7-day buckets) into windows and query
  each window separately with `created=<start>..<end>`.
- Write the window bounds as **literal ISO dates** you compute yourself — do not shell out to
  date arithmetic, whose flags are dialect-split.
- `per_page` caps at 100 (values above are silently clamped). If a window's `total_count`
  exceeds 100, either narrow the window or fetch the few extra pages *within* that window —
  shallow pages inside a bounded window are fine; an unbounded page walk across the whole
  history is what the cap breaks.

## Metrics

Per completed run, three fields do all the work: `conclusion` (failure ratio), `run_attempt`
(retry detection — a run with `run_attempt > 1` was re-run), and
`updated_at − run_started_at` (wall duration of the latest attempt; use `run_started_at`, not
`created_at`, which includes queue time).

Via `gh` (one window; repeat per window):

```bash
gh api "repos/$OWNER/$REPO/actions/runs?created=2026-07-01..2026-07-07&per_page=100" \
  --jq '[.workflow_runs[] | select(.status == "completed")]
        | {total: length,
           failures: [.[] | select(.conclusion == "failure")] | length,
           retried:  [.[] | select(.run_attempt > 1)] | length}'
```

Per-run durations (seconds) for the trend line:

```bash
gh api "repos/$OWNER/$REPO/actions/runs?created=2026-07-01..2026-07-07&per_page=100" \
  --jq '.workflow_runs[] | select(.status == "completed")
        | [.name, .conclusion, .run_attempt,
           ((.updated_at | fromdateiso8601) - (.run_started_at | fromdateiso8601))]
        | @tsv'
```

Via the GitHub MCP tools, the same recipe holds: list runs per window with the `actions_list`
tooling and read the same per-run fields (`conclusion`, `run_attempt`, `run_started_at`,
`updated_at`) — the tools front the same endpoint. Use `get_job_logs` (failed-jobs-only option)
when a candidate needs "why is CI red" specifics.

Derived signals:

- **Failure ratio** = failures ÷ completed runs, per window; the across-window sequence is the
  trend.
- **Retry rate** = share of runs with `run_attempt > 1` — a high retry rate is a flakiness
  signal in its own right (humans re-running until green), often stronger than the failure
  ratio it masks.
- **Duration trend** = median (or p90) run duration per window; a rising sequence is a
  slow-CI candidate.
- **Per-workflow split** — scope any of the above to one workflow via
  `repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs` when a single workflow dominates
  the signal.

## Zero runs / repo without Actions — a branch, not an error

A repo with no `.github/workflows/`, or with workflows but zero runs in every window, resolves
to one of two outcomes — never an error and never a fabricated "CI is healthy":

- Record the evidence-gap line: `gap: ci-health — no Actions runs in window (no CI history to
  rank on)`.
- Where CI evidence would matter for this target (there is code to build or test), propose the
  instrument-first candidate per ranking.md: add a baseline CI workflow so future runs can rank
  on failure ratios and durations.

## Citation shape

Every CI-health candidate cites: the metric(s), the window(s), the access path used, and the
rung — e.g. `ci: median duration 6m→11m over 4 weekly windows (updated_at − run_started_at),
via gh — rung 2`. Numbers come only from runs actually fetched; a partially-fetched window is
either completed or recorded as a gap.
