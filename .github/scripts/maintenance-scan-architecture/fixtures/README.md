# Captured GitHub responses

Read-only `gh api` GETs against `melodic-software/claude-code-plugins` on 2026-11-27. Each keeps
every field the scripts read and drops the rest, including every author, email and avatar field.
The tests derive their variants from these shapes: more runs by changing `id`, `created_at` and
`head_sha`, and a stopped or failed scan by changing the `Scan` job's `conclusion`.

| File | Request | jq filter |
|---|---|---|
| `workflow-runs.json` | `actions/workflows/maintenance-tidy-code-upkeep.yml/runs?branch=main&status=completed&per_page=2` | `{total_count, workflow_runs: [.workflow_runs[] \| {id, name, head_branch, head_sha, run_number, event, status, conclusion, workflow_id, created_at, updated_at, run_attempt, run_started_at, path}]}` |
| `run-jobs.json` | `actions/runs/45762108070/jobs?filter=latest&per_page=100` | `{total_count, jobs: [.jobs[] \| {id, run_id, run_attempt, head_sha, status, conclusion, name, started_at, completed_at, workflow_name, head_branch}]}` |
| `issues-page.json` | `issues?state=open&per_page=3` | `[.[] \| {number, title, state, labels: [.labels[] \| {name}], pull_request: {url}}]`, with `pull_request` left out of the issue, as GitHub does |
| `label.json` | `labels/source%3A%20architecture-improve` | none |
| `issue.json` | `issues/18862` | `{id, node_id, number, title, state, labels: [.labels[] \| {name}], type: {name}, url, html_url, user: {type}}` |

The runs and jobs come from `maintenance-tidy-code-upkeep.yml`, which names its scan-carrier job
`Scan` as this lane does; this lane had no run on main to capture. `issue.json` stands in for the
create response: POST `/repos/{owner}/{repo}/issues` returns the same issue object with status 201
(<https://docs.github.com/en/rest/issues/issues?apiVersion=2022-11-28#create-an-issue>).
