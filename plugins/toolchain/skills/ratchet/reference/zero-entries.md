# Zero entries

A baseline or allowlist is a checked-in list of the offenders a check lets through while they are
paid down: one entry per file, rule hit or exemption. The ceiling holds the count of a counter;
the list holds its members.

## The rule

A baseline or allowlist that reaches zero entries is deleted in the same change that empties it,
together with:

- the code that reads it (the loader, the flag or variable that names its path, the branch that
  skips listed entries),
- the tests of that code (the cases that seed, read or expect the list),
- the doc lines and comments that name it.

The check that read it stays and fails on the first offender, with nothing left to exempt one.

## Why

An empty list exempts nothing, so the code that reads it is dead: it runs, tests and documents a
path no input takes. Kept, it is also an open door. One added line lets a new offender through
without the check ever failing, and a reviewer sees a one-line data change, not a weakened check.

## Applying it

- **Same change.** The change that fixes the last entry deletes the list. A later cleanup leaves
  the door open in between.
- **Already empty.** A list found at zero entries is deleted the same way, in its own change.
- **Not the ceilings file.** A single-count counter in the ceilings file is not a list of
  offenders. A per-file counter is one, and `propose-tighten` drops each file that reaches `0`. A
  count measured at `0` follows [§2 of the skill](../SKILL.md#2-the-lint-rollout-rule): a lint
  count lands its rule with no ceiling, and a count with no rule behind it is ratcheted at `0`.
- **Read by a file this change cannot edit.** When a workflow or other protected path reads the
  list, the list and its reader go together in a follow-up for whoever owns that path; deleting
  the list alone breaks the reader.
