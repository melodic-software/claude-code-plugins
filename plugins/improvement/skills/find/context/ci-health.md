# ci-health: GitHub Actions CI-health recipe (Tier 0, evidence rung 2)

Failure ratios, duration trends, and retry rates from GitHub Actions run history. Output:
CI-health candidates with citations like
`ci: 23% failure ratio, 9/40 runs retried (run_attempt > 1), 2026-07-01..2026-07-28 — rung 2`.

**Portability scope.** This recipe is GitHub-forge-specific by construction: the CI-health
*dimension* is neutral, but the mechanics below are the GitHub Actions API. On a repo hosted on
a non-GitHub forge (GitLab, Gitea, Azure DevOps, ...), record an evidence-gap line, e.g.
`gap: ci-health — non-GitHub forge; this recipe covers GitHub Actions only`, and rank without
CI evidence. Never adapt these calls by guesswork against another forge's API.

Owner/repo for every call below comes from the TARGET repository's remote
(`git -C <target-root> remote get-url origin`), never from the session's cwd. The target may be
a different checkout (SKILL.md "Repo as parameter").

## Access probe ladder (probe in order, record the outcome)

1. **GitHub MCP tools.** The `actions_*` toolset (`actions_list`, `actions_get`,
   `get_job_logs`) in this session's tool roster. Preferred. This recipe reads one repository per
   invocation, the target, so a tool scoped to the session's attached repositories still covers
   it.
2. **`gh` CLI.** `command -v gh` succeeds and `gh auth status` reports authentication. Make the
   calls through `gh api` REST paths, which is how every call below is written.
3. **None.** Record the evidence-gap line
   (`gap: ci-health — no GitHub access path (no MCP actions tools, no gh)`) and rank without CI
   evidence. A missing access path is never license to estimate CI health.

In a cloud session, which GitHub tools and `gh` paths are available, how they authenticate, and
which repositories and endpoints the proxy serves are read live, not assumed.

- **Pointer:** [cloud environments: work with GitHub issues and pull requests](https://code.claude.com/docs/en/cloud-environments#work-with-github-issues-and-pull-requests)
  and [cloud environments: GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy).

Derive `<owner>/<repo>` from the first configured remote URL (`git remote` /
`git remote get-url`), not from directory names.

## Never use the `/timing` endpoint

`GET /repos/{owner}/{repo}/actions/runs/{run_id}/timing` is being retired upstream, so do not build
anything on it. Every duration number below comes from run timestamps instead.

- **Pointer**: when checking the endpoint's status, fetch
  [Get workflow run usage](https://docs.github.com/en/rest/actions/workflow-runs#get-workflow-run-usage)
  live.

## Iterate by `created` date windows, never deep pagination

The run-listing endpoint caps the results of each filtered search, and page-walking past the cap
returns nothing rather than an error. The bound is per search, so splitting the period into
`created` windows gives each window its own budget, which is also the natural shape for trend
buckets (record at the end of the list below). Use the documented `created` date filter:

- Split the analysis period (default: last 28 days, in 7-day buckets) into windows and query
  each window separately with `created=<start>..<end>`.
- Write the window bounds as **literal ISO dates** you compute yourself. Do not shell out to
  date arithmetic, whose flags are dialect-split.
- If a window's `total_count` exceeds one page, either narrow the window or fetch the few extra
  pages *within* that window. Shallow pages inside a bounded window are fine; an unbounded page
  walk across the whole history is what the cap breaks.
  - **Pointer**: for the per-search result cap, the filters it applies to and the page-size
    limit (the `per_page` parameter), read
    [List workflow runs for a repository](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository).

## Metrics

Per completed run, three fields do all the work: `conclusion` (failure ratio), `run_attempt`
(retry detection: `run_attempt > 1`), and `updated_at − run_started_at` (wall duration; use
`run_started_at`, not `created_at`, which includes queue time).

- **Pointer**: for what each field records, read the response schema of
  [Get a workflow run](https://docs.github.com/en/rest/actions/workflow-runs#get-a-workflow-run).
- **As of**: 2026-11-03
- **Recheck trigger**: that schema renames or drops `run_attempt`, `run_started_at` or
  `created_at`.

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

Via the GitHub MCP tools, the per-run fields are the same (`conclusion`, `run_attempt`,
`run_started_at`, `updated_at`) but the window mechanics are NOT: the `actions_list` tooling
exposes no `created` date filter, so date-windowed iteration is unreachable through it. On the
MCP path, read the most recent page(s) only, cite the covered span verbatim ("last N runs,
&lt;oldest&gt;..&lt;newest&gt;"), and record the uncovered windows as a `gap:` line. Never page deep to
reach them and never present a recent-page sample as full-window coverage. Full date-window
iteration needs the REST call above (`gh api` or an equivalent raw-request path). Use
`get_job_logs` when a candidate needs "why is CI red" specifics.

- **Pointer**: for the filters `actions_list` takes and the options `get_job_logs` offers, fetch
  [GitHub MCP Server: Tools](https://github.com/github/github-mcp-server#tools) live.

Derived signals:

- **Failure ratio** = failures ÷ completed runs, per window; the across-window sequence is the
  trend.
- **Retry rate** = share of runs with `run_attempt > 1`. A high retry rate is a flakiness
  signal in its own right (humans re-running until green), often stronger than the failure
  ratio it masks.
- **Duration trend** = median (or p90) run duration per window; a rising sequence is a
  slow-CI candidate.
- **Per-workflow split.** Scope any of the above to one workflow via
  `repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs` when a single workflow dominates
  the signal.

## Zero runs / repo without Actions: a branch, not an error

A repo with no `.github/workflows/`, or with workflows but zero runs in every window, resolves
to one of two outcomes, never an error and never a fabricated "CI is healthy":

- Record the evidence-gap line: `gap: ci-health — no Actions runs in window (no CI history to rank on)`.
- Where CI evidence would matter for this target (there is code to build or test), propose the
  instrument-first candidate per ranking.md: add a baseline CI workflow so future runs can rank
  on failure ratios and durations.

## Citation shape

Every CI-health candidate cites: the metric(s), the window(s), the access path used, and the
rung, e.g. `ci: median duration 6m→11m over 4 weekly windows (updated_at − run_started_at), via gh — rung 2`.
Numbers come only from runs actually fetched; a partially-fetched window is either completed or
recorded as a gap.
