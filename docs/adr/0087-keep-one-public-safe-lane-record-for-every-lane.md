# Keep one public-safe lane record for every lane

- Status: accepted
- Date: 2026-11-01

## Context

Every lane, in ci-workflows and in this repository, reports what happened to one Claude credential
attempt: the failure class, the credential it used, whether it fell back, how long it ran and what
it spent. Agents and scripts read those reports to decide whether to hold a lane, replace a key or
rerun. Today the same facts are written in several shapes, some only as free text, and none of them
is safe to publish by construction.

Sources read 2026-11-01: ci-workflows `74faeae`. A path prefixed `ci-workflows:` is in that
repository; any other path is this repository at `725ee9f1018740d1e40cc30b444f2d5f5a028070`.

### Current state

- **One versioned contract exists, outside this repository.** ci-workflows'
  `docs/lane-outcome.md` and `schemas/lane-outcome.v1.schema.json` define the lane-outcome record,
  written by `.github/actions/report-lane-outcome`. It already carries the credential's secret
  name, the fallback reason and a list-price cost estimate. Its Compatibility section allows fields
  and class values to be added within `v: 1`.
- **The hub writes a second record.** `.github/actions/report-check-run/lane-record.mjs` posts a
  `lane=... activity=... class=...` summary line whose closed `CLASSES` set (lines 10-21) has no
  `credit-stop`.
- **A credit stop is written as a usage limit.** The hub lane workflows pass
  `known-failure-class: lane-class == 'credit-stop' && 'rate-limit'` to `report-lane-outcome` at 26
  calls (`.github/workflows/pr-verify.yml` 13, `pr-review-main.yml` 12,
  `maintenance-audit-lane-runs.yml` 1). `.github/scripts/pr-unblock/limit-stop.mjs` stops only on
  `rate-limit` and `auth` (line 48), so a key with no credit is held for a usage-limit window
  instead of being reported as dead.
- **The failure class has at least six spellings**: the record's `class`, the legacy `class=`
  token, `failure-class=`, the `failure_class` step output, the hub `CLASSES` line, and
  `outcome=` in `.github/scripts/work-resolve-issue/report-outcome.mjs` (line 537 and others).
- **Some facts exist only as free text or not at all.** A fallback off a dead key on a passing run
  shows only in a success notice. work-resolve-issue names no credential. Duration is in free text
  only, and no record carries a run or trace id. GitHub API calls are counted by the api-budget
  actions in only some workflows.
- **Public text has leak paths.** `plugins/work-items/scripts/lane-telemetry-upsert.sh` posts a
  body file with no containment (its own KNOWN LIMITS note, line 113) and falls back to the
  machine's hostname for the lane instance (lines 215-216). Every repository that runs lanes is
  public, so anything a lane writes to an annotation, summary, artifact or comment is published.

## Options

- **(a) Extend the lane-outcome v1 record into the one lane record for every lane.** Additive under
  the contract's own compatibility rules; reuses the emitter both repositories already call; the
  record stays on the check run, which agents already read.
- **(b) Send OpenTelemetry to Application Insights.** Rejected: ingestion is billed by volume
  ([Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/)), and the broker's existing App Insights traces are already lossy
  under a daily cap and default sampling, so lane history would inherit the same gaps.
- **(c) Write records to a private telemetry repository through the lanes App.** Rejected: it
  needs a new repository and a new write permission on the lanes App, a trust-boundary change, to
  hold data that is safe to publish once it is built from closed values.

## Decision

Adopt (a). The lane-outcome record in ci-workflows is the single lane record for every lane, hub
lanes included.

1. **Public-safe by construction.** The record holds closed enums, fixed-shape patterns and counts
   only. `credential.secret` is a secret's name and the schema admits only a Claude credential's
   name; no value, token prefix, email, hostname or machine path is written, in annotations,
   summaries, artifacts or comments. A field whose source is absent is left out, never guessed.
   ci-workflows `docs/lane-outcome.md`, Public safety, states this as a MUST.
2. **Fields.** Beyond what v1 already carries (credential name, fallback reason, cost estimate),
   the record adds `durationMs`, `runId`, `runAttempt`, a `traceId` derived from the run id and
   attempt, a `spanId` derived from the trace, job, lane and secret name, and `githubCalls` per
   counter (`GITHUB_TOKEN` requests and GraphQL requests, and the lanes App's).
3. **One closed failure-class enum**, with `credit-stop` its own class and never `rate-limit`. A
   class outside the enum is `other` in the record.
4. **Retire the other spellings over a deprecation window** that closes when no reader in the
   organization reads them. No current consumer breaks in the slice that adds the fields: the
   legacy tokens and step outputs keep their values.
5. **Hub history** becomes one dated local store agents query, replacing free-text event-log lines.

## Consequences

- Readers move from regex over annotation text to one JSON object after the `lane-outcome` marker.
- A dead key reads as `credit-stop` once the hub stops coercing it, so the limit-stop check can
  report it instead of holding a window.
- The record's 1,024-character limit now covers more fields; the emitter drops `models`, `usage`,
  `windows` and then `githubCalls` to fit.
- `githubCalls` counts only calls a job's api-budget readings recorded before the report step;
  workflows without the api-budget actions report none until slice 4.
- The hub `lane-record.mjs` line and the `outcome=` marker remain until their readers move.

## Slices

1. **Contract and emitter** (ci-workflows): the fields, the closed enum, the public-safety rule and
   the deprecation plan in `docs/lane-outcome.md`; the schema; `report-lane-outcome` filling what
   it can know.
2. **Hub emitters**: hub lanes pass `credit-stop` through, write the record on every lane
   (including the handoff record they skip today), and work-resolve-issue writes a credential and
   fallback marker.
3. **Hub readers**: `/harness-ops:morning-brief`, the operator's local monitor and `limit-stop.mjs`
   read the record; the `lane-record.mjs` format is retired.
4. **API-budget coverage**: the workflows and local scripts that make GitHub calls without a
   reading get one, so `githubCalls` is complete.
