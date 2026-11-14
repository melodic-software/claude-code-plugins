# Gate reviewer media by a four-value policy and IaC-defined labels

- Status: accepted
- Date: 2026-11-13
- Refs: owner decisions of 2026-11-13 (Q34, Q57, Q65, Q66, Q79, Q81, Q83; design thread T11)

## Context

Reviewer media is off unless a repository or a pull request asks for it. A request label must be able
to ask for media when the repository default is off, and a repository must be able to refuse media
outright. Downstream repositories see the policy values and label names.

## Decision

1. **The `reviewer-media` convention's `policy` takes four values:**
   - `never`: nothing is produced, and the request label is ignored;
   - `on-request` (default): produced only when the request label is present;
   - `when-selected`: produced when the pull request crosses a review-digest threshold
     (`docs/conventions/review-digest.yaml`), or on request;
   - `always`: produced for every pull request.
2. **Three labels, configurable, each optional:** `reviewer-media: requested`,
   `reviewer-media: posted`, `reviewer-media: failed`. A label set to `false` is skipped.
3. **Labels for this organization are defined in `melodic-software/github-iac`.** No skill creates a
   label; downstream repositories name their own or turn them off.
4. **Every label change and failure leaves a trail:** a failed build retries once, then swaps to the
   failure label with one failure comment carrying a reason code, and never runs again on that head.

### One-way doors

The policy values and label names are seen by downstream repositories; renaming either is a breaking
change.

## Considered options

- **Rename `never` to `on-request` and offer true-off only by `labels.requested: false`.** Rejected:
  off becomes implicit.
- **Keep `never` and document that the label overrides it.** Rejected: the name would mislead.

## Consequences

- The convention reads `never` / `on-request` / `when-selected` / `always`; the Brief's `off` and
  `auto` map to `on-request` and `when-selected`.

## Revisit triggers

- A repository needs a policy no value expresses (for example, path-scoped selection).
