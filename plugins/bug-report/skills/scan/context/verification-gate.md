# The verification gate — the precision stage of `/bug-report:scan`

Loaded on demand by `/bug-report:scan` Step 3. This is the prompt contract for the gate: **one
separate fresh-context subagent per candidate**, dispatched by the scan skill, never the hunter that
produced the candidate.

Why separate and fresh: a model re-checking its own work rubber-stamps it. The gate must arrive with
no memory of why the candidate looked convincing — only the candidate, the code, and a mandate to
kill it.

## Stance — default refute

The gate's job is **not** "confirm this bug". It is: *try to prove this is not a bug, and report a
finding only if you fail.*

Give the gate this stance verbatim:

> Your default verdict is REFUTE. Assume the code is correct and the candidate is a false positive
> until you have specifically failed to explain it away. Do not accept the candidate's reasoning; redo
> it from the source. **If uncertain, it is NOT a finding.**

The known failure mode of a verification subagent is declaring a pass without doing the work. Counter
it with an explicit imperative: the gate MUST open the cited file and read the surrounding code, MUST
attempt the falsification routes below, and MUST state which ones it tried.

## What the gate receives

- The single candidate: symptom, `path:line`, evidence quote, claimed fault, claimed trigger, impact.
- Read access to the repository.
- Nothing else — no other candidates, no hunter rationale, no prior verdicts. Blackbox verification is
  cheap precisely because context transfer is minimal.

## Falsification routes (attempt each, name the ones you tried)

1. **Unreachable path.** Is there a guard, an earlier validation, a type constraint, or a caller
   contract that makes the claimed trigger impossible? Find the callers before concluding it is
   reachable.
2. **Already handled.** Is the fault caught downstream — a wrapper, a retry, an error boundary, a
   framework default, a database constraint — such that the observable behavior is correct?
3. **Misread source.** Re-read the quoted lines in their full context. Is the operator, the type, the
   shadowed variable, or the overload what the candidate assumed?
4. **Intended behavior.** Does a test, a docstring, a comment, or a repo convention assert the current
   behavior deliberately? A finding that contradicts a passing test that encodes the behavior is a
   refutation, not a bug.
5. **No impact.** Even granting the fault, does anything observable break? If nothing does, refute.

If a route succeeds, the candidate is **refuted** and you are done.

## Confirming — what a surviving finding must carry

A candidate survives only with **all** of:

- A verbatim evidence quote of the offending source (`path:line`), re-extracted by the gate itself.
- A **concrete reproduction argument**: the specific input, state, or call sequence that reaches the
  fault, traced from a real entry point — not "if a caller passes null".
- A statement of the observable wrong behavior, and who or what it affects.
- The falsification routes attempted, and why each failed to explain the candidate away.

Nothing weaker qualifies. A finding you would describe as "worth a look" is a refutation.

## Evidence label

Every surviving finding carries exactly one label:

| Label | Use when |
|---|---|
| `reproduced` | A check was actually run and observed to fail — an existing test, a scratch invocation, a script, a query. State the command and what it showed. |
| `verified-by-reading` | No cheap check exists, and the fault is established from the source plus a traced reproduction argument. State why a check was not run (no harness, no fixture, side effects, requires production data). |

**Attempt a cheap reproduction first.** If a test file, a REPL, or a one-line invocation can settle it
in under a minute, run it — reproduction is the strongest precision lever available. Never claim
`reproduced` for a check you did not run, and never run anything that mutates the repository or any
external system.

## Retained-refuted output contract

Refuted candidates are **returned, never dropped**. An adversarial gate of this kind kills the large
majority of candidates, and some of those kills are wrong; silently discarding them denies a human the
chance to overturn one and lets the same dead candidate resurface next run.

Return every candidate in one of two shapes:

```markdown
VERDICT: finding
label: reproduced | verified-by-reading
evidence: <verbatim quote with path:line>
reproduction: <the concrete path to the fault>
impact: <observable wrong behavior, and who it affects>
falsification-attempted: <routes tried, and why each failed>
```

```markdown
VERDICT: refuted
refuting-argument: <the specific route that explained it away, with its own quote or path:line>
```

A refutation needs its own evidence, at the same standard as a finding — "seems fine" is not a
refuting argument.

## Boundaries

- Read-only. No edits, no writes, no branches, no filing, no network mutation.
- One candidate per dispatch. Do not compare candidates or deduplicate — the scan skill owns that.
- Do not rewrite the candidate into a different, better bug you noticed while reading. Refute this one
  and mention the observation in one line; the next hunt wave can pick it up.
