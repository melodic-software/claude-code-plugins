# Refactor Confirmation Mode

Structured confirmation that a refactoring preserved existing behavior while improving code structure. Core question: "Does everything still work exactly the same way, just organized better?"

## When to use

- Code was restructured, renamed, reorganized, or extracted without changing behavior
- User asks "is behavior preserved?" or "did the refactor break anything?"
- A review pass flagged structural changes and recommended confirmation

## The fundamental rule

A refactor changes structure, not behavior. If tests passing before still pass after, that's strong evidence of behavior preservation. If ANY test previously passing now fails, the refactor introduced a behavioral change, intentional or not.

## Process

### 1. Classify the refactor

| Refactor type | Risk level | Key concern |
|--------------|-----------|-------------|
| **Rename** (file, class, method, variable) | Low | Broken references, missed renames |
| **Extract** (method, class, interface) | Medium | Changed call semantics, parameter passing |
| **Move** (file to different directory/project) | Medium | Broken imports, namespace changes, access modifiers |
| **Restructure** (split/merge modules) | High | Dependency changes, circular references, DI registration |
| **Replace** (swap implementation behind interface) | High | Behavioral differences in the new implementation; needs differential evidence (below), not only passing tests |

**Replace needs differential evidence.** Passing tests prove only the tested behavior, and a Replace swaps all of it. Run the old implementation (or its recorded output) and the new one on the same inputs, a recorded corpus first, and report counts: inputs run, mismatches, mismatches explained by an intentional-differences ledger entry (cite each id), and unexplained mismatches. Each ledger entry names the difference, why it is intended, and who accepted it; widening the comparator to make the run match is not an explanation. A recorded baseline proves sameness with the old behavior, not correctness, so a bug the old code had passes this check. Recorded outputs captured for the comparison are stored and timed like any baseline: see `/verification:measure` "Behavior baselines".

Basis: the differential-testing slice of the agent-self-check research, 2026-10-06 (Scientist ignore blocks and reviewed snapshot re-approval for intentional differences; Feathers and the snapshot tools for sameness, not correctness), prompted by Addy Osmani's 2026-10-05 post (<https://x.com/addyosmani/status/2106995301802541481>). No accepted source shows agents validating rewrites this way; the rule extrapolates human-led practice. Recheck trigger: a source on agent-run rewrite validation that changes it.

### 2. Identify the behavior boundary

What behavior should be preserved? This defines what to test:

- **Public API contracts**: do all public methods accept same inputs and produce same outputs?
- **Side effects**: do same database writes, events, logs, notifications still occur?
- **Error behavior**: do same inputs still produce same errors?
- **Performance characteristics**: is refactored code still within acceptable performance bounds?

### 3. Run the full test suite

Run every test in the affected projects, not only the ones covering the refactored code. Refactors can break distant consumers.

The Stage 1 mechanical-prerequisite results from `/verification:confirm` provide this. If Stage 1 passed, that's the primary evidence.

### 4. Check for untested behavior

Tests only prove preservation of TESTED behavior. Look for:

- **Public methods without tests**: if a public method was refactored but has no test, behavior preservation is unverified for that method
- **Integration points without integration tests**: if refactored code interacts with external systems and those interactions aren't tested, preservation is assumed, not proven
- **Configuration-dependent behavior**: if behavior changes based on config and only one configuration is tested, other configurations are unverified

Flag untested areas honestly, as risks rather than failures.

### 5. Structural comparison

Show what changed structurally with `git diff --stat` and `git diff --name-status`, each run as its own plain git command, against the pre-refactor base: the working tree against `HEAD` for uncommitted work, or the branch against its merge-base when the refactor is committed. A committed refactor spans its commits, not only the last one.

### 6. Report

```
## Refactor Confirmation

### Refactor Description
- **Type**: <rename/extract/move/restructure/replace>
- **Risk level**: <Low/Medium/High>
- **Goal**: <why the refactor was done>

### Structural Changes
| Change type | Count | Details |
|------------|-------|---------|
| Files added | N | <list or "see git diff"> |
| Files modified | N | <list or "see git diff"> |
| Files deleted | N | <list or "see git diff"> |
| Files renamed | N | <old → new> |

### Behavior Preservation Evidence
| Evidence | Status | Details |
|----------|--------|---------|
| All pre-existing tests pass | PASS/FAIL | <from Stage 1> |
| No new test failures | PASS/FAIL | <any tests that broke?> |
| Public API unchanged | PASS/FAIL | <same method signatures?> |
| Architecture tests pass | PASS/FAIL/N/A | <dependency direction preserved?> |
| Differential run (Replace only) | PASS/FAIL/NOT RUN/N/A | <inputs run: N; mismatches: N; explained by ledger: N (ids); unexplained: N> |

### Untested Risk Areas
| Area | Why untested | Risk |
|------|-------------|------|
| <method/path> | <no test exists> | <LOW/MEDIUM/HIGH> |

### Assessment
- Tests covering refactored code: <X tests, Y assertions>
- Test gap areas: <N untested public methods>
- Verifier model: <model passed to the fresh-context verifier> / not matched to the producing model (unknown)
```

### 7. Verdict

- **CONFIRMED** if all tests pass and no untested gaps are HIGH risk; for a Replace, the differential run also ran with zero unexplained mismatches. A Replace is never CONFIRMED with an unexplained mismatch (that is BEHAVIORAL CHANGE DETECTED) or with no differential run (at best LIKELY PRESERVED, with the missing run named as the gap)
- **LIKELY PRESERVED** if all tests pass but untested gaps exist (document the gaps)
- **NOT CONFIRMED** if any test that passed before now fails
- **BEHAVIORAL CHANGE DETECTED** if new test failures indicate the refactor changed behavior (may be intentional, so flag for user decision)
