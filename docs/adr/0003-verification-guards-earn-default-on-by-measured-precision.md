# Verification guards earn default-on by measured precision, not by plausible oracle

- Status: accepted
- Date: 2026-07-25

## Context

A program to add claim-verification guards to `guardrails` (#1270) scoped three, on the
reasoning that each had a mechanical oracle and no existing coverage:

| Candidate | Oracle | Tier claimed at scoping |
|---|---|---|
| Asserted repo-relative path that does not exist | filesystem test | Deterministic |
| Version string disagreeing with its owning manifest | manifest compare | Deterministic |
| `/plugin:skill` reference that does not resolve | glob the plugins tree | Detect-then-judge |

All three reasoned soundly from the oracle. Two did not survive contact with the repository.

The **version guard** was dropped before implementation. Its only in-repo surface — a
`## [<version>]` heading versus the manifest — is already covered deterministically by
`scripts/check-changelog-parity.sh --check-bump`, a required CI gate. An enumeration of the
residual prose surface (all `*.md` under `plugins/` and `docs/`, every string in every
`plugin.json` and `marketplace.json` outside the `version` field, `plugins/*/hooks/*.sh`,
`.github/**`, `scripts/`, `.claude/`) found only third-party versions no local manifest can
adjudicate, plus claim shapes a manifest compare reads *wrong*: historical
("before the `0.6.0` split"), minimum floors ("implementation `0.9.0`+", true and documented
as explicitly *not* a version dependency), and planned values ("CREATE: `0.1.0`").

The **path guard** was built, tested to 61 contract cases, reviewed, and then withdrawn on
measurement. Swept across all 975 tracked markdown files, each fed to the hook as a real
`PostToolUse` payload:

| | |
|---|---|
| Files firing | **231 / 975 = 23.7%** |
| Findings | **389** |
| True positives | **0** |

The oracle never misfired — no candidate resolved at the repo root. Every finding was a
scoping failure. 72% were consumer-project config paths (`.claude/**` and similar) that a
doc describes for a *consuming* repo and that a marketplace correctly lacks; its
first-segment gate passed only because this repo happens to carry same-named top-level
directories. Fixing the three dominant causes still left ~4% firing at zero true positives.

The **reference guard** shipped. Same corpus: 4 true positives, verified individually. Its
noise was 89% CHANGELOG rename entries — content the hook's own advisory calls correct as
written, because a CHANGELOG is append-only by contract and a rename entry must keep naming
the old command. Excluding CHANGELOGs moved it from 3.4% firing at 6% precision to **0.51%
firing at 57% precision**.

## Decision

**A verification guard does not ship default-on until its firing rate and precision have
been measured against a real corpus.** A sound oracle is a necessary condition, never a
sufficient one. Specifically:

1. **Measure before shipping, on the real corpus, at real scale.** Not a sample, not the
   contract suite. A passing contract suite proves the oracle; only a corpus sweep proves
   the scoping. The path guard had 61 green cases and a 23.7% real-world firing rate.
2. **Report the number in the PR.** "It looks quieter now" is not a measurement. The
   before/after firing rate and precision are the artifact that justifies default-on.
3. **Zero true positives on a real corpus disqualifies the guard**, however sound its
   oracle. A guard that fires on a quarter of writes and is never right trains readers to
   ignore every advisory, including the ones that are right — it has negative value, not
   low value.
4. **Distinguish "wrong oracle" from "wrong scope."** The path guard's oracle was exact; its
   scope was a repo whose docs describe other repos' trees. That distinction decides whether
   a guard is deleted or re-filed for rescoping. It was re-filed (#1314).
5. **A guard whose only surface an existing gate owns does not ship at all.** Duplicating
   `check-changelog-parity --check-bump` would have added a component that never fires
   correctly — the defect class `PLUGIN-PHILOSOPHY.md` names as "a silently skipped feature
   is a defect."

## Consequences

- Withdrawal is a normal outcome of the build, not a failure of it. Two of three candidates
  in #1270 were withdrawn, one before implementation and one after full review. Both
  withdrawals are recorded with their evidence (#1314 carries the sweep) so the ideas can be
  rescoped rather than rediscovered.
- The cost is real: the path guard reached 61 contract cases and a full review round before
  the measurement ran. Measuring earlier — right after the first working version, before
  review — would have saved that. **The sweep belongs immediately after the guard first
  works, not after it is polished.**
- This extends the verification-promotion discipline in
  [ADR 0002](0002-default-on-ai-review-advisory-with-earned-promotion.md) one step earlier in
  the lifecycle. That ADR governs promoting an advisory gate to blocking on demonstrated
  precision; this one governs whether an advisory gate ships default-on at all, on the same
  evidentiary basis.
- `docs/conventions/hook-precision/README.md` owns the over-fire discipline for a guard
  already in the tree. This ADR is the pre-ship counterpart and defers to it thereafter.

## Sources

- #1270 (scoping, amended twice), #1284 (the two-guard PR, closed), #1319 (the shipped
  guard), #1314 (the withdrawn guard's measurement and rescope)
- `docs/conventions/hook-precision/README.md` — over-fire discipline
- `docs/PLUGIN-PHILOSOPHY.md` — "a silently skipped feature is a defect"
- `melodic-software/standards`, `conventions/engineering/enforceability-tiers.md` —
  classify the tier first, justify automation second
