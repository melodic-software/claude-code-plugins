# Refactor Confirmation Mode

Structured confirmation that a refactoring preserved existing behavior while improving code structure. Core question: "Does everything still work exactly the same way, just organized better?"

## When to use

- Code was restructured, renamed, reorganized, or extracted without changing behavior
- User asks "is behavior preserved?" or "did the refactor break anything?"
- A review pass flagged structural changes and recommended confirmation

## The fundamental rule

A refactor changes structure, not behavior. If tests passing before still pass after, that's strong evidence of behavior preservation. If ANY test previously passing now fails, the refactor introduced a behavioral change — intentional or not.

## Process

### 1. Classify the refactor

| Refactor type | Risk level | Key concern |
|--------------|-----------|-------------|
| **Rename** (file, class, method, variable) | Low | Broken references, missed renames |
| **Extract** (method, class, interface) | Medium | Changed call semantics, parameter passing |
| **Move** (file to different directory/project) | Medium | Broken imports, namespace changes, access modifiers |
| **Restructure** (split/merge modules) | High | Dependency changes, circular references, DI registration |
| **Replace** (swap implementation behind interface) | High | Behavioral differences in the new implementation |

### 2. Identify the behavior boundary

What behavior should be preserved? This defines what to test:

- **Public API contracts**: do all public methods accept same inputs and produce same outputs?
- **Side effects**: do same database writes, events, logs, notifications still occur?
- **Error behavior**: do same inputs still produce same errors?
- **Performance characteristics**: is refactored code still within acceptable performance bounds?

### 3. Run the full test suite

Not just tests for the refactored code — ALL tests in affected projects. Refactors can break distant consumers.

The Stage 1 mechanical-prerequisite results from `/verification:confirm` provide this. If Stage 1 passed, that's the primary evidence.

### 4. Check for untested behavior

Tests only prove preservation of TESTED behavior. Look for:

- **Public methods without tests**: if a public method was refactored but has no test, behavior preservation is unverified for that method
- **Integration points without integration tests**: if refactored code interacts with external systems and those interactions aren't tested, preservation is assumed, not proven
- **Configuration-dependent behavior**: if behavior changes based on config and only one configuration is tested, other configurations are unverified

Flag untested areas honestly — risks, not failures.

### 5. Structural comparison

Show what changed structurally:

```bash
# Files changed
git diff --stat HEAD~1

# Structural summary
git diff --name-status HEAD~1   # shows A(dded), M(odified), D(eleted), R(enamed)
```

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

### Untested Risk Areas
| Area | Why untested | Risk |
|------|-------------|------|
| <method/path> | <no test exists> | <LOW/MEDIUM/HIGH> |

### Assessment
- Tests covering refactored code: <X tests, Y assertions>
- Test gap areas: <N untested public methods>
```

### 7. Verdict

- **CONFIRMED** if all tests pass and no untested gaps are HIGH risk
- **LIKELY PRESERVED** if all tests pass but untested gaps exist (document the gaps)
- **NOT CONFIRMED** if any test that passed before now fails
- **BEHAVIORAL CHANGE DETECTED** if new test failures indicate the refactor changed behavior (may be intentional — flag for user decision)
