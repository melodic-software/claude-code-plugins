# Metrics Criterion — baseline / compare

Verify a **code-metrics-improvement claim** (simpler, cleaner, less coupled, better covered) against measured deltas. Use when someone claims code is "simpler," "cleaner," "more maintainable," or "better organized" and you need evidence, not assertion.

This file owns the metrics-family measurement discipline; the phase table, invocation forms, measure-delta vs review-for-ship boundary, and tooling notes are owned by SKILL.md ("Two-phase model" / "Purpose") — run the phases manually when the consuming project has no collector. Do not route metric measurement into a review gate — that would graft measurement onto a review skill and orphan `performance`'s twin.

## Quality metrics (measurable proxies)

Quality is partly subjective, but some aspects ARE measurable:

| Quality aspect | Measurable proxy | How to check |
|---------------|-----------------|--------------|
| Complexity | Cyclomatic complexity, nesting depth | Count conditionals, measure max nesting |
| Size | Lines of code, file count, method length | Line counter (`wc -l` on POSIX/Git Bash, `Measure-Object -Line` in PowerShell), `git diff --stat` |
| Coupling | Dependency count, import count | Count import/dependency declarations (`import`/`require`/`using`, package or project references) |
| Cohesion | Methods per class, related functionality | Inspect class responsibility |
| Duplication | Repeated code blocks | Grep for similar patterns |
| Test coverage | Test count, assertion count | Your test runner's output, test inventory |
| API surface | Public member count | Count `public` declarations |

## `baseline` phase (at planning time)

1. **Map the claim to a proxy** — "simpler" → fewer lines / lower complexity / less nesting; "cleaner" → better naming / less duplication; "more maintainable" → fewer deps / better cohesion / more tests; "better organized" → feature-aligned structure / reduced coupling.
2. **Capture pre-change metrics** for the chosen proxies (line count from `git show <base>:<file>` piped to a line counter — `wc -l` on POSIX/Git Bash, `Measure-Object -Line` in PowerShell; complexity count, dependency count). Store in the topic's memory-tier baselines directory (SKILL.md "Two-phase model" — machine-bound, never committed) and record in the plan.

## `compare` phase (at `/verification:measure metrics`)

1. **Measure the after-state** on the same proxies.
2. **Qualitative assessment** for aspects that resist quantification — naming, abstraction level, single-responsibility, readability — backed by specific examples ("`ProcessOrder` was 47 lines / 6 nesting levels → 3 methods averaging 12 lines / max 2 levels").
3. **Report:**

   ```text
   ## Metrics — compare vs baseline

   ### Claim
   <what improvement is claimed>

   ### Quantitative
   | Metric | Before | After | Delta | Better? |
   |--------|--------|-------|-------|---------|
   | Lines of code | <N> | <N> | <diff> | Yes/No/Neutral |
   | Max nesting depth | <N> | <N> | <diff> | Yes/No/Neutral |
   | Method count | <N> | <N> | <diff> | Yes/No/Neutral |
   | Dependencies | <N> | <N> | <diff> | Yes/No/Neutral |

   ### Qualitative
   | Aspect | Before | After | Improved? |
   |--------|--------|-------|-----------|
   | Naming | <desc> | <desc> | Yes/No |
   | Structure | <desc> | <desc> | Yes/No |

   ### Trade-offs
   <more files? more indirection? harder to debug?>
   ```

4. **Verdict:**
   - **CONFIRMED** — measurable metrics improved AND no significant trade-offs
   - **MIXED** — some improved, some degraded (document both)
   - **NOT CONFIRMED** — metrics neutral or worse despite the claim
   - Quality changes without measurable impact may still be valid — back them with qualitative examples, not assertions

## Common pitfalls

- **"Fewer lines" isn't always better** — extracting a 5-line inline block into a 20-line file just moves complexity.
- **More abstractions isn't always better** — a `UserServiceFactory` → `UserService` → `UserRepository` chain is worse than the repository directly unless each layer earns its place.
- **Don't confuse motion with progress** — renaming files / reorganizing directories / reformatting is housekeeping, not quality improvement. Valid, but don't claim it improved quality.

## Marketplace plugin skills (invoke only when installed)

These are .NET-ecosystem plugin skills — invoke each only when your stack is .NET and its plugin is installed; otherwise draw the same evidence from the project's own complexity/coverage tooling:

- **CRAP scores** — `dotnet-test:crap-score` combines cyclomatic complexity + coverage into one risk metric ("safer to change" evidence).
- **Test quality** — `dotnet-test:test-anti-patterns` detects test smells before claiming suite improvements.
- **EF Core queries** — `dotnet-data:optimizing-ef-core-queries` for N+1 detection / query-optimization evidence.
