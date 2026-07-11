# Outcome Confirmation Mode

Structured comparison of approved plan against actual implementation. Use when an approved plan exists in the conversation and you need to verify every item was delivered.

## When to use

- An approved plan exists earlier in the conversation
- User asks "does this match the plan?" or "did we build everything?"
- Complex multi-step implementation where it's easy to miss items

## Process

### 1. Extract the plan

Find the approved plan in the conversation. Extract every deliverable, requirement, and acceptance criterion as a numbered list.

If no formal plan exists but user described requirements, extract those instead.

### 2. Map implementation to plan items

For each plan item:

1. **Find corresponding code change** — which files, which commits, which behavior?
2. **Assess coverage** — does implementation fully satisfy the item, partially, or not at all?
3. **Note deviations** — did implementation differ from the plan? Was deviation justified (discovered better approach) or accidental (forgot)?

### 3. Check for scope creep

Look for implementation work not tracing to any plan item:

- **Justified additions**: discovered requirements during implementation (edge cases, error handling, tests)
- **Unjustified additions**: gold-plating, "while I'm here" changes, features nobody asked for

Justified additions are fine but should be noted. Unjustified additions should be flagged — they increase review surface and risk without corresponding to stated needs.

### 4. Report

```
## Outcome Confirmation — Plan vs Implementation

### Plan Coverage
| # | Plan Item | Implementation | Files | Status |
|---|-----------|---------------|-------|--------|
| 1 | <from plan> | <what was built> | <files changed> | COMPLETE / PARTIAL / MISSING |

### Deviations from Plan
| # | Plan said | Implementation did | Justification |
|---|-----------|-------------------|--------------|
| 1 | <planned approach> | <actual approach> | <why it changed> |

### Scope Additions (not in plan)
| # | Addition | Justified? | Rationale |
|---|----------|-----------|-----------|
| 1 | <what was added> | Yes/No | <why> |

### Assessment
- Plan items: X/Y complete (Z%)
- Deviations: N (all justified / N unjustified)
- Scope additions: N (M justified)
```

### 5. Verdict

- **CONFIRMED** if all plan items are COMPLETE and deviations are justified
- **NEEDS WORK** if any plan items are MISSING or PARTIAL without justification
- If NEEDS WORK, list specific gaps with suggested actions

## UI evidence contract

When the change ships anything to a browser, the verdict requires captured evidence, not a "looks fine" claim. When the consuming project documents its own evidence contract, that governs; otherwise apply this portable one:

- **When it applies** — any change to components, templates, styles, or static assets shipped to the browser. Doc-only litmus: if no rendered pixel or runtime behavior can differ, the contract doesn't apply
- **Required artifacts** — pre-change snapshot, the action driven, post-change snapshot, console check (no new errors), network check (correct calls + status codes), and a behavior assertion
- **False-pass guard** — the assertion must be one of: text presence, element-role presence (from an accessibility snapshot), visual regression against a baseline, or an authored-test pass. A screenshot alone asserts nothing — the missing-toast failure mode is a page that looks fine while the expected element never rendered
- **Storage** — binary captures stay gitignored; persist an assertion-only manifest (frontmatter with `verified_at_sha`, a `## Reproduction` fenced block with the exact commands a reviewer runs locally, the artifacts table, the behavior assertion) beside the change's plan/notes artifacts. NO absolute paths to gitignored captures
- **Degraded path** — in sandboxed/cloud sessions that cannot run a browser, say so explicitly and mark UI verification as not performed; never substitute a static read for runtime evidence silently

When `/verify-changes outcome` produces a verdict, copy the required-artifacts table inline AND cite the manifest path so PR reviewers don't need to follow the link.
