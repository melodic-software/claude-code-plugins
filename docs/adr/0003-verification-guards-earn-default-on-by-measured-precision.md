# Verification guards earn default-on by measured precision

- Status: accepted
- Date: 2026-07-25

## Context

The #1270 guard program scoped three advisory `PostToolUse` guards, siblings of `cli-flag-verify`,
each with a mechanical oracle: a version string against its owning manifest, a repo-relative path
asserted in markdown, and a `/plugin:skill` reference. All three oracles were sound. Only one
shipped default-on.

- **Version-vs-manifest** was dropped before implementation (#1270). Its only in-repo surface —
  a `## [<version>]` CHANGELOG heading versus the plugin manifest — was already covered
  deterministically by `scripts/check-changelog-parity.sh --check-bump`, a required CI gate. The
  residual prose surface a manifest-compare oracle would additionally read is historical, minimum-
  floor, and planned version claims it gets wrong. A guard whose only surface a required gate
  already owns supplies no new signal while adding a second place the rule can drift.
- **`asserted-path-verify`** was built to 61 contract cases, shipped in #1284, fully reviewed —
  then withdrawn in #1319 on measurement, not judgment. #1314 carries the sweep: every one of the
  975 tracked markdown files in this repo, each fed to the hook as a real `PostToolUse` `Write`
  payload. Result: **231/975 files (23.7%) fired, 389 findings, zero true positives.** The oracle
  never misfired — no candidate resolved at the repo root that shouldn't have. Every finding was a
  scoping problem: 72% cited a *consuming* repo's config surface (`.claude/**` and similar) that
  this repo, a marketplace, correctly does not carry; most of the rest were subtree-relative
  citations or declared forward-looking references. The guard's scope — resolve every asserted
  path against this repo's root — was wrong for a repo whose docs mostly describe other repos'
  trees.
- **`skill-reference-verify`** shipped in #1319 at 0.51% firing, 57% precision after excluding
  CHANGELOGs — the guard whose measured corpus behavior justified default-on.

The generalizable finding: a sound oracle is necessary but not sufficient for shipping a guard
default-on. A passing contract suite proves the oracle does what it claims on the cases it was
given; only a corpus sweep against the repo's real content proves the guard's *scope* fits where
it runs. `asserted-path-verify`'s 61 contract cases were all real assertions correctly judged —
the suite never lied. What it could not show was how often the guard's scope assumption (paths
resolve against the repo root) held across the actual corpus, because a hand-picked contract suite
is not a sample of that corpus.

This extends [ADR 0002](0002-default-on-ai-review-advisory-with-earned-promotion.md)'s
verification-promotion discipline one step earlier in the lifecycle. 0002 governs promoting an
already-shipped advisory gate to blocking on demonstrated precision. This ADR governs whether a
guard ships default-on *at all*, on the same evidentiary basis: a number, measured, cited in the
PR — not asserted from the oracle's design. `docs/conventions/hook-precision/README.md` owns the
precision *rules* a shipped hook's over-fire discipline follows post-ship; this ADR does not
restate them.

**Cost of measuring late.** `asserted-path-verify` was measured only after #1284 had already
carried it through a full review round — 13 real findings, all addressed, on a guard the corpus
sweep then disqualified outright. Running the same 975-file sweep as soon as the guard first
produced output, before polish and before requesting review, would have surfaced the 23.7%/0%
result a full review round earlier at no less accuracy. The measurement is cheap and non-destructive
(a dry-run sweep against tracked files); there was no reason to defer it to `#1319`.

## Decision

A verification guard does not ship default-on on oracle soundness alone. Before it ships default-on:

1. **Measure firing rate and precision against a real corpus** — every file (or command, or other
   input class) the guard's `PostToolUse` matcher would actually see in this repo, not a hand-
   picked contract suite. The contract suite proves the oracle; the corpus sweep proves the scope.
2. **The number appears in the PR.** Files/inputs fired on, findings, and true-positive count are
   stated plainly (as `asserted-path-verify`'s and `skill-reference-verify`'s were in #1319),
   not summarized as "reviewed" or "tested."
3. **Zero true positives disqualifies regardless of oracle soundness.** An oracle that never
   misfires but never fires correctly either is not evidence the guard is safe to ship — it is
   evidence the guard's scope does not fit this corpus. A guard that fires often and is never
   right trains authors to ignore every advisory it produces, including the real ones.
4. **"Wrong oracle" versus "wrong scope" decides deletion versus rescoping.** The version-vs-
   manifest guard was wrong-oracle-for-the-surface: no manifest-compare oracle can correctly read
   historical, minimum-floor, or planned version claims, so it was dropped rather than built.
   `asserted-path-verify` was wrong-scope: its filesystem oracle was correct, but resolving every
   asserted path against the repo root does not fit a marketplace repo whose docs largely describe
   *other* repos' trees. A wrong-oracle guard is deleted; a wrong-scope guard is a rescoping
   candidate (e.g. resolving against the citing doc's skill/plugin subtree, or excluding
   consumer-config path classes) — #1314 carries that rescoping option for a future guard,
   deliberately not exercised here.
5. **Measure as soon as the guard first produces real output**, before polish and before
   requesting review — not after. The evidentiary bar does not change with when it is applied;
   applying it earlier is strictly cheaper.

This is the same evidentiary posture as ADR 0002's promotion discipline (a gate earns its next
step of trust on demonstrated precision, not on schedule or on the strength of its design) applied
one lifecycle stage earlier: shipping default-on at all, rather than promoting advisory to
blocking.

## Consequences

- Every future `PostToolUse` verification guard scoped with a mechanical oracle runs a full-corpus
  sweep before its shipping PR, and that PR states the firing/finding/true-positive numbers
  directly rather than asserting the guard was "tested."
- A guard whose contract suite passes can still be correctly withdrawn pre-ship on a zero-true-
  positive corpus result; that is not a defect in the contract suite, it is the sweep doing its
  job. `asserted-path-verify`'s 61/61 contract pass and 0/389 corpus precision are both accurate
  and not in tension.
- The scoping ideas the corpus sweep produces (subtree-relative resolution, consumer-config
  exclusion) are not lost — they live with the measurement in #1314 as a rescoping option, distinct
  from the "ship now" question this ADR closes.
- `docs/conventions/hook-precision/README.md`'s post-ship over-fire discipline is unchanged and
  still owns the precision rules a shipped hook's structure follows; this ADR's corpus-sweep gate
  runs strictly before a guard reaches that discipline's scope.
