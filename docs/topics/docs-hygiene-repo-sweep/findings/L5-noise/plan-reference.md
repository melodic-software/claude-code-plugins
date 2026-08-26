# L5-noise: `plan-reference`

**2 candidates in. 1 finding out. 1 rejected. Plus 1 recall check, no additions.**

Both candidates read in full.

## Finding

### 1. `plugins/source-control/skills/babysit-prs/reference/loop.md:56` (Tier 1)

Verbatim, lines 56 to 59:

```text
**Draft policy (replaces the old blanket draft skip):** drafts stay in the discovery list in
every tier. In the safe tier a draft is evaluated — terminal state, CI, unaddressed findings —
and reported, never fixed, never marked ready. Worker/autopilot draft handling (zero-blocker
drafts route through a worker; `gh pr ready` only in autopilot) is defined in SKILL.md.
```

The parenthetical narrates the changeset that produced the policy. No reader of this file has the
old blanket draft skip to compare against, and the policy statement that follows is complete
without it. Tier 1 is the shape's default and this instance matches it cleanly: a first-person
changeset frame around a sentence that stands alone once the frame is cut.

**Remediation.** Delete the parenthetical only. Replacement for the bolded lead:

```text
**Draft policy:** drafts stay in the discovery list in
```

The rest of the paragraph survives verbatim.

## Rejection

`plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md:22` is the
detector's own eval fixture, authored to trip it:

```text
Task 2 replaces the old fixed-delay retry, and in this PR we make backoff the default.
```

The skill's prescribed corpus for a repo-wide run excludes `**/evals/fixtures/**`.

## Recall check

A corpus-wide grep over all 1218 scanned files for the shape's semantic forms beyond the
detector's literals:

```text
replaces the old
in this (PR|changeset|commit) (we|I)
Task [0-9]+ of the plan
as part of this (PR|change)
this PR (adds|removes|replaces|introduces)
```

returns one hit, the finding above. No recall gap in this shape.

## Cross-lane observations

- **L1-derivability, L3-ssot, L6-compress.** Nothing.
