---
description: "Read-only report of the five DORA delivery metrics (deployment frequency, change lead time, change fail rate, failed deployment recovery time, deployment rework rate) as a team trend from the default branch's history, never per person. Use when: 'measure delivery', 'DORA metrics', 'deployment frequency', 'change lead time', 'change fail rate', 'how fast do we ship', 'delivery trend'. Backlog counts are /work-items:track stats."
argument-hint: "[--since YYYY-MM-DD] [--until YYYY-MM-DD] [--bucket week|month] [--branch <ref>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report the five DORA delivery metrics as a team trend from default-branch history
---

## Variables

Arguments: `$ARGUMENTS`, the window and period flags below, passed through to the script.

- `--since <YYYY-MM-DD>`: first UTC day of the window (default: the 84 days ending with `--until`).
- `--until <YYYY-MM-DD>`: last UTC day, inclusive (default: now).
- `--bucket week|month`: trend period (default `week`, ISO weeks starting Monday).
- `--branch <ref>`: the default branch (default: the ref `origin/HEAD` names).

## Purpose

Show how the team delivers over time: one row per period and a window total, for the five
metrics DORA defines (<https://dora.dev/guides/dora-metrics/>, read 2026-11-01). DORA applies
them to one application or service and to a team improving against its own past, not against
other teams; this skill reports them the same way. It reads history and writes nothing.

## Metrics

| Metric | Measured here as |
|---|---|
| Deployment frequency | Deployments per period, and per week over the window |
| Change lead time | Median hours from the earliest author date among a deployment's commits to its landing |
| Change fail rate | Failed deployments / deployments |
| Failed deployment recovery time | Median hours from a failed deployment to the first deployment that reverts it |
| Deployment rework rate | Deployments that revert an earlier change / deployments |

## Deploy signal

What counts as a deployment is the team setting `delivery_deploy_signal` in the repository's
`docs/conventions/work-items.yaml` (schema: `${CLAUDE_PLUGIN_ROOT}/schemas/work-items.schema.json`).
Its one value, and the default, is `merge-to-default-branch`:

- Each commit on the default branch's first-parent history is one deployment, at its committer
  date: a merge commit, or a squash or rebase landing.
- A deployment a later first-parent commit reverts is a failed deployment. A commit reverts a
  deployment when its message has `This reverts commit <sha>` naming the deployment or a commit
  it merged, or, with no such line, when its subject is `Revert "<subject>"` for an earlier
  deployment's subject. A merge counts the messages of the commits it merges, so a revert that
  lands through a merge commit is seen. A revert landing after `--until` still marks a
  deployment in the window as failed.

The signal reads only git history, so no tracker or forge call is made and any host works.

## Workflow

1. Resolve the deploy signal from the repository root:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/triage/scripts/parse-concern-value.sh" \
     docs/conventions/work-items.yaml delivery_deploy_signal
   ```

   Empty output means the key is unset: use the default, `merge-to-default-branch`. Report
   whether the value came from the file or the default. A value other than
   `merge-to-default-branch` stops the run: name the value and the one the schema allows.

2. Run the report. With no `--branch`, the script reads the ref `origin/HEAD` names, as of the
   last fetch. Run `git fetch` first only when the user asks for the remote's latest history;
   otherwise say the report covers history up to the last fetch.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/measure-delivery/scripts/delivery-metrics.sh" \
     --repo "<repo root>" --deploy-signal "<signal>" <the flags from $ARGUMENTS>
   ```

   Exit `2` is a bad flag or a branch that does not resolve: show the script's stderr line,
   and when `origin/HEAD` is unset, ask for `--branch`. Exit `3` is a failed git read and exit
   `8` a missing `git` or `jq`: report it and stop.

3. Render the JSON as one markdown table, a row per `trend` period then a `Window` row from
   `totals`, a column per metric. Show a null value as `n/a` (nothing to measure, such as a
   period with no deployments), and show rates as percentages. Mark the first or last period
   as partial when the window starts or ends inside it.

4. Add two or three lines that read the trend: which metrics moved between the first and last
   full periods with deployments, and in which direction. Describe the team's delivery only.

Done when the table and the trend lines are shown, with the window, branch and deploy signal
they cover.

## Gotchas

- **Never name a person.** The script emits counts, medians and ratios only. Do not add
  authors, committers, reviewers or a per-person breakdown, even when asked: DORA metrics
  describe a team's delivery, and per-person delivery numbers are a different report.
- **Squash and rebase landings can shorten lead time.** Lead time starts at the earliest author
  date git keeps for the change. A landing that rewrites author dates moves that start later,
  so the lead time reads short; a merge commit keeps every commit's author date.
- **A revert under another subject goes uncounted.** A hand-written undo with neither the
  `This reverts commit` line nor the `Revert "<subject>"` subject is invisible to the signal.
- **Per-item stage times are out of scope.** Time an item spent in each tracker stage is a
  separate report, not one of these five metrics.

## Next

`/work-items:track stats` for the open backlog behind the trend.
