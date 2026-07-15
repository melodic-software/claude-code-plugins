# codebase-health — Phase 1 discovery method

The full claim-extraction + per-file fan-out method. The SKILL.md Phase 1 keeps the goal + the
scope-first cost gate; this file carries the method detail, execution steps, scope-fencing, and the
finding-report format.

## How discovery works

For each active dimension, follow the **claim-extraction method**:

1. **Read the file top to bottom.**
2. **Extract every factual claim** — anything asserting something about the codebase (file paths,
   tool names, package names, configuration values, convention descriptions, ranges, counts).
3. **Verify each claim** — read the file or run the command that confirms or denies it.
4. **Record the result** — either it matches (verified passing) or it doesn't (finding).

Not a checklist to browse. Read every line. The audit config's per-dimension `example-claims` rows
(`{ claim: "If a doc asserts X", verify-via: "<command/path>" }`) are the ones the agent will
actually see in THIS repo — apply the same pattern to every claim encountered: extract the claim,
identify the verification path, run it.

**Critical: verify ALL claims, not just some.** A single line or bullet list often contains multiple
factual claims. Finding one issue on a line does NOT mean other claims on that line are correct —
verify each one independently. For example:

- A tools list ("tool A, tool B, tool C, tool D") contains separate claims — verify ALL of them
  against the package manifest, not just the first two.
- A dependency rule ("Layer A → Layer B only") is a verifiable claim — read the actual build
  manifest to confirm, even if another claim on the same line already has an issue.
- A line with both a file reference AND a factual assertion needs both verified separately.

## Dimension-specific guidance

Read [`${CLAUDE_PLUGIN_ROOT}/skills/audit/reference/audit-checklist.md`](../reference/audit-checklist.md) for the kinds of claims to
watch for in each dimension. The checklist is a guide for **what to look for**, not a list to check
off. The primary method is always: read the file, extract claims, verify each one.

## Execution: fan out one subagent per file

Discovery runs as a **parallel subagent fan-out — one agent per primary-source file**, NOT a single
sequential pass. A single context cannot exhaustively verify many files at once: it skips claims as
context fills (the #1 audit failure named above). One dedicated subagent per file keeps each file's
verification in a fresh, focused context — empirically ~2× the claim coverage and ~4× the drift
caught vs a single sequential agent.

1. **Enumerate** — expand the active dimensions' `primary-sources` globs (from the resolved audit
   config) to a concrete file list. `verification-sources` are the read-only ground-truth set every
   agent may consult.
2. **Scope first (MANDATORY — cost gate)** — a full unscoped run fans out across every doc/config/
   source file (hundreds of thousands of tokens). REQUIRE a `[scope]` or dimension filter
   (`--docs-only` etc.) for large targets. If the enumerated list exceeds ~20 files, confirm scope
   with the user before dispatching. Never fan out the whole repo unprompted.
3. **Dispatch** — one subagent per file. Each agent's ALLOWED surface = its ONE assigned file
   (read) + all verification-sources (read-only) — verification-sources stay read-only ALLOWED even
   when the same path also appears as another dimension's primary-source. FORBIDDEN = every other
   primary-source file (except those doubling as verification-sources, per the read-only exception),
   any write, any git op. Each agent applies the claim-extraction method above to its file and
   returns findings + a verified-count. Use repo-relative paths only (never absolute machine
   paths — agents must audit the current worktree). Throttle in waves (≤~16 concurrent); lower-tier
   worker models are sufficient and dodge burst overload.

   **Peer files a claim must be checked against are read via `verification-sources`, not the fence
   exception.** A cross-file claim — DRY duplication across N files, a dependency-direction rule, an
   architecture boundary — can only be validated by reading peer files, and the fence forbids the
   *other* primary-source files. So for any dimension whose claims are cross-file (notably
   `code-quality` and `architecture`), the config MUST list the relevant source roots and dependency
   manifests in `verification-sources` as well (they may also be `primary-sources` — the read-only
   exception covers the overlap). If a cross-file dimension's `verification-sources` omit the peer
   files its claims reference, those findings are systematically missed — the setup skill wires this
   in by default.
4. **Collect** — aggregate per-file findings + verified counts into the Phase 2 input.

Because each agent owns one file, the "complete one dimension before the next" sequencing is moot —
there is no shared context to thin out, so dimension order does not matter.

**Background / unattended variant:** the same per-file fan-out can run as a saved workflow
(background execution, same-session resume, rerunnable script) instead of in-session subagents —
same discovery, different executor. This applies only when your environment provides a
background/saved-workflow execution surface; the in-session fan-out above is the default. Reach for
the workflow form only when you want a fire-and-forget periodic audit you can walk away from — an
interactive audit you are actively driving stays with the in-session fan-out.

## What to report

Report **every discrepancy** found, no matter how small. Also report what you verified as correct —
this proves the audit was thorough and didn't skip files.

For each finding:

```
- file: <path:line>
- category: <doc-drift|config-drift|code-quality|architecture|missing-enforcement>
- severity: <error|warning|info>
- description: <what the doc/config claims vs what's actually true>
- verification: <how you confirmed this — what file you read, what command you ran>
```
