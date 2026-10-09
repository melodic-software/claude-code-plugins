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

1. **Find corresponding code change:** which files, which commits, which behavior?
2. **Assess coverage:** does implementation fully satisfy the item, partially, or not at all?
3. **Note deviations:** did implementation differ from the plan? Was deviation justified (discovered better approach) or accidental (forgot)?

### 3. Check for scope creep

Look for implementation work not tracing to any plan item:

- **Justified additions**: discovered requirements during implementation (edge cases, error handling, tests)
- **Unjustified additions**: gold-plating, "while I'm here" changes, features nobody asked for

Justified additions are fine but should be noted. Unjustified additions should be flagged. They increase review surface and risk without corresponding to stated needs.

### 4. Evidence ranking

Rank each piece of test evidence by how independent its expected value is from the code it grades, strongest first:

1. **Criteria-sourced user flow.** A user-flow or acceptance test written from the acceptance criteria and run against the app.
2. **Pre-existing test.** A test that predates the diff and still passes, so the producing session did not write its oracle.
3. **Self-authored, sourced.** A test added or changed in the diff under review whose expected value names an independent source per `/testing:test-value`.
4. **Self-authored, unsourced.** A test added or changed in the diff whose expected value names no independent source. This is a producer claim: report it as a finding, never as proof of the behavior.

Label every test the producing session wrote as self-authored in the evidence table. A criterion proved only by rank 4 evidence is not COMPLETE.

Basis: LLM-written test oracles were measured to assert what the code does rather than what it should do (three papers, measured on LLM test generators over benchmark repositories; the transfer to an interactive agent is inferred). Recorded in the agent-self-check research slice, 2026-10-06, prompted by Addy Osmani's 2026-10-05 post (<https://x.com/addyosmani/status/2106995301802541481>). Recheck trigger: a measurement on interactive coding agents that contradicts it.

### 5. Report

```
## Outcome Confirmation: Plan vs Implementation

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

### Existing behavior this leans on (out-of-diff couplings)
| # | Coupling | Where it lives | Evidence it still holds |
|---|----------|----------------|-------------------------|
| 1 | <unchanged behavior the change depends on> | <file/module> | <test name, assertion, or check run> |

### Evidence
| # | Plan item | Test or check | Rank (1-4) | Authorship | Oracle source |
|---|-----------|---------------|------------|------------|---------------|
| 1 | <plan item #> | <test name + assertion> | <rank> | pre-existing / self-authored | <criterion, spec, recording, or "none named"> |

### Assessment
- Plan items: X/Y complete (Z%)
- Deviations: N (all justified / N unjustified)
- Scope additions: N (M justified)
- Verifier model: <model passed to the fresh-context verifier> / not matched to the producing model (unknown)
```

### 6. Verdict

- **CONFIRMED** if all plan items are COMPLETE, deviations are justified, and Stage 1 left no environment skip
- **NEEDS WORK** if any plan items are MISSING or PARTIAL without justification
- **NOT VERIFIED** if no gap was found but Stage 1 left an environment skip (a missing tool, including one too old for the check, or missing dependencies): name each skip and its reason, and what running it needs
- Under any verdict, list an ecosystem whose only checks were syntax-only as "no real check ran"; it does not change the verdict by itself and never counts as a mechanical pass
- If NEEDS WORK, list specific gaps with suggested actions

## UI evidence contract

When the change ships anything to a browser, the verdict requires captured evidence, not a "looks fine" claim. When the consuming project documents its own evidence contract, that governs; otherwise apply this portable one:

- **When it applies.** Any change to components, templates, styles, or static assets shipped to the browser. Doc-only litmus: if no rendered pixel or runtime behavior can differ, the contract doesn't apply
- **Required artifacts:** pre-change snapshot, the action driven, post-change snapshot, console check (no new errors), network check (correct calls + status codes), and a behavior assertion
- **False-pass guard.** The assertion must be one of: text presence, element-role presence (from an accessibility snapshot), a geometry assertion, visual regression against a baseline, or an authored-test pass. A screenshot alone asserts nothing. The missing-toast failure mode is a page that looks fine while the expected element never rendered
- **Inspect the render.** Agents have passed UI changes as "looks good" over misaligned buttons, clipping, overlap and low contrast (user report, 2026-10-04), and an aria snapshot carries no layout. The verdict needs the layered render checks `/testing:run-e2e` defines, each with its result or why it did not run: an axe scan (necessary, not sufficient: report manual accessibility review as not performed unless a person did it), geometry assertions at two or more widths, a pixel baseline when the project keeps one, then a vision review of cropped screenshots whose findings are leads to confirm with a matching check (geometry for spatial leads, a measurable check such as a contrast ratio or baseline for the rest) or report as unconfirmed. "No issues found" from a vision review is never a pass
- **Storage.** Binary captures stay gitignored; persist an assertion-only manifest (frontmatter with `verified_at_sha`, a `## Reproduction` fenced block with the exact commands a reviewer runs locally, the artifacts table, the behavior assertion) beside the change's plan/notes artifacts. No absolute paths to gitignored captures
- **Degraded path.** In sandboxed/cloud sessions that cannot run a browser, say so explicitly and mark UI verification as not performed; never substitute a static read for runtime evidence silently

When `/verification:confirm outcome` produces a verdict, copy the required-artifacts table inline AND cite the manifest path so PR reviewers don't need to follow the link.
