# Deviations — native-overlap-inventory implementation

Conservative deviations taken during the Phases 1–6 build, each with what the plan said, what was
done instead, why, and the blast radius. Nothing here changes an acceptance criterion; all three
are tightenings or seams that keep a plan-specified check honest.

## 1. `self-check --cli-version` seam added

- **Planned.** The self-check's locally-decidable comparison is "the cli_version comparison sourced
  from cheap `claude --version` output when available — explicit degraded semantics, never a fresh
  323MB binary extraction per gate run" (PLAN Phase 3).
- **Done.** That is the default path, unchanged. An optional `--cli-version <v>` flag was added,
  which supplies the comparison value directly instead of probing.
- **Why.** Without it the check's outcome depends on whether `claude` happens to be on PATH, which
  makes both the unit tests and Phase 3's sanity check non-hermetic: the same store would exit `0`
  on one machine and `3` on another for reasons that have nothing to do with the store. The flag
  makes the comparison decidable in a test and in an offline CI runner, rather than skipping it.
- **Blast radius.** Additive flag on one subcommand; the probe remains the default and no gate in
  this change set passes the flag. Phase 3's sanity check was run as
  `overlap.py self-check --repo <fixture> --cli-version 2.1.232` (exit 0); the Phase 4 and Phase 5
  sanity checks ran without it against the real store (exit 0, probe matched 2.1.232).

## 2. `reason` is required on every store row, not only `prefer-ours`

- **Planned.** The verdict enum names a reason as required for `prefer-ours`
  (Brief locked decision 4).
- **Done.** `validate_row` requires a non-empty `reason` for every verdict value.
- **Why.** A row's recheck trigger obliges re-deriving the verdict when it fires, and a verdict with
  no stated premise cannot be re-derived — the reader has nothing to check the new evidence against.
  A `complementary` or `defer` row with no reason is the shape that decays silently.
- **Blast radius.** Stricter than specified, so no conforming row is rejected; all eight seeded rows
  carry reasons. A future author writing a reason-less row gets a `broken` verdict instead of a
  silently thin record.

## 3. Phase 2's SKILL.md deferred its `Run it` section to Phase 3

- **Planned.** Phase 2 creates `SKILL.md` (purpose, boundary, substrates, report structure, verdicts,
  apply and sweep contracts, store/view/self-check anatomy); Phase 3 creates the scripts.
- **Done.** Exactly that, with the concrete invocation section — which cites `scripts/overlap.py`,
  `scripts/test_overlap.py`, and `scripts/overlap.test.sh` in backticks — added in Phase 3 alongside
  the files it names.
- **Why.** `skill-quality:check`'s check 5 FAILs on a backtick-cited skill-internal path that does
  not resolve, so citing the scripts in Phase 2 would have made Phase 2's own sanity check
  (`check-skill.sh --require-evals` exits 0) fail on a file the plan does not create until Phase 3.
  Moving the citation rather than the check keeps both phases' sanity checks intact at full strength.
- **Blast radius.** None at the end state: the Phase 3 commit carries both the scripts and the
  section citing them, and `check-skill.sh` passes at every phase boundary.
