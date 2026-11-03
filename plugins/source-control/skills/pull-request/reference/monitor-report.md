# 3.4 Final monitoring report (readiness-gated)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there.

**Do NOT declare convergence until the full [readiness checklist](readiness.md) passes.** Run all 7 of its gates before presenting the monitoring report; no "close enough" for merge readiness.

**The readiness checklist includes a 2-minute cooldown** after the last check-run completion or comment arrival. If a new comment or check result arrives during cooldown, restart the cooldown.

When all readiness gates pass:

```markdown
## PR Monitoring Complete: All Readiness Gates Passed

**PR:** #N, title
**Check runs:** X passed, Y skipped, Z failed-informational
**Security:** [scanner] evaluated, N findings classified
**Comments:** X from N reviewers, Y fixed, Z deferred (structural, urgent, or fix blocked on research; item ids), W incorrect
**Review threads:** 0 unresolved
**Review lanes:** [each lane on the checks roster: productive, or ABSENT with what was run locally in its place]
**Cooldown:** 2+ min since last activity
**Fix iterations:** N
**Failures classified:**
- `<check>`: FAILURE, [exact reason from logs]
**All readiness gates passed. Recommend merge.**
```

**After presenting the readiness report, self-terminate the Monitor watch** (same protocol as 3.0.5). After a later push, the next `/source-control:pull-request monitor` invocation re-arms via 3.0.1.

**If any gate fails**, present which gates failed and what action is needed, leading with any action that needs the user (a decision, an approval, a human reviewer's thread). Never suggest merge with open gates, even in `full` mode.
