# Fail a change that loosens a check

A bundled criterion: a change that makes a check accept more than it did is judged as a loosening
wherever it appears, on any path. `/review:quality-gate`'s diff modes, the `review:code-reviewer`
agent and `/review:fanout`'s criteria slices apply it when no consumer criterion covers the
concern. A consumer criterion on the same concern replaces it, and the report carries one line:

```text
Overrides bundled default Fail a change that loosens a check per <standards file>
```

## Which checks

**Ordinary checks are judged:** tests, lint, coverage, type checks, scanners and CI jobs. A secret
scanner and a dependency audit are ordinary checks here.

**A security control or a billing hold**, as the repository names one, keeps its existing stop. A
loosened one may also be reported here, never at a lower severity than that stop and never in its
place.

**A friction hold makes no finding:** a path hold, a trust-path hold, a person-approval hold, a
bot-author hold, or a pin or repin.

## What counts as a loosening

Each of these nine kinds is a loosening:

1. A test skipped, focused (so the tests beside it stop running) or deleted.
2. An assertion or expected value changed to match the code.
3. A threshold lowered.
4. A suppression, ignore or allowlist entry added.
5. A check set to soft-fail: it still runs, and its failure no longer fails the run.
6. A check removed.
7. A retry count raised.
8. A test's own timeout raised.
9. A check's own code, runner, workflow or settings changed so that it accepts more.

Not a loosening: a check added new as advisory, and a check's code made stricter (it rejects more).
Job, workflow and session timeouts and run caps stay where they are judged today; this criterion
does not judge them.

`loosened_check_patterns` adds the consumer's own entries. An entry is a path glob, or, when it
starts with `text:`, a regular expression matched against each added or removed line. A changed
file a glob matches counts as a check's own code or settings (kind 9), and a changed line a pattern
matches is judged against the nine kinds.

## Verdict

A loosening fails unless the spec allows it:

- **A loosening** passes only when the spec names it and says why.
- **A removed check** (a whole check, job or step, not one test inside a suite, which is the first
  kind) passes only when the spec names it.
- **A check set to soft-fail** passes only as the quarantine of a flaky test, when the spec names the
  test and gives the reason it is quarantined. Any other check set to soft-fail fails, with or
  without a reason in the spec.

`loosened_check_verdict` sets what a failing loosening is. `fail`, the default: a blocking finding,
at the tier that blocks merging in the severity vocabulary in use (CRITICAL in the plugin's
baseline). `note`: a finding at the lowest tier, which blocks nothing.

## Whose reason counts

Only trusted spec text gives a reason: the text of the issue the change resolves, the same text the
CI verifier reads as the spec, written by a person the repository trusts. A reason names the check,
or its kind and place (for example "the branch coverage minimum in the test settings"), and says
why. The pull request body, commit messages, code comments, review comments, and a plan or brief
the change's author wrote never give one, even when they name the check and a reason, so an author
cannot grant itself the exception. A review with no spec text has no reason for any loosening.

## Settings

Both settings are resolved before judging, as
[`reference/config.md`](../../../reference/config.md) says: the repository value comes from the
default branch's committed copy, never the head's, so a change cannot relax the verdict or drop a
pattern for its own review. Use the resolved values the brief carries; when no value could be
resolved, use `fail` and no consumer entries, and say why.

Report one line: `Loosened-check verdict: <value> (<layers>); patterns: <count>`.

## Finding

Each finding cites this criterion by its title, names the kind, the file and line, what the check
accepted before and after, and whether the spec names it and gives a reason. Example:

```text
Fail a change that loosens a check (threshold lowered): test settings line 7 lowers the branch
coverage minimum from 85 to 60; the spec does not name it.
```
