# Coverage reconcile (task #15)

Completeness gate for the S1-S14 audit. Verified by construction, not inspection.

## Check 1 — every article body line survives into the audit source

Script: normalize (lowercase, strip punctuation, collapse whitespace) every content line of
`raw-capture.txt` lines 179-291, drop the known site-chrome lines, and assert each remaining line's
first eight words appear in `source-article.md`.

- Body lines checked: **113**
- Orphans: **0**

Scope limit, stated rather than implied: this proves `source-article.md` is faithful to
`raw-capture.txt`. It proves nothing about the live page — a later edit upstream would not be
detected. `raw-capture.txt` is a 2026-07-24 snapshot.

## Check 2 — the article's own pattern index

The article supplies its index in S4: 8 named patterns across three phases. Each has a dedicated
audit unit with a persisted ledger.

| Pattern | Unit | Ledger |
|---|---|---|
| Blind spot pass | S5 | `findings/S5.md` |
| Brainstorms and prototype | S6 | `findings/S6.md` |
| Interviews | S7 | `findings/S7.md` |
| References | S8 | `findings/S8.md` |
| Implementation plan | S9 | `findings/S9.md` |
| Implementation notes | S10 | `findings/S10.md` |
| Pitches and explainers | S11 | `findings/S11.md` |
| Quizzes | S12 | `findings/S12.md` |

8 of 8. Each ledger's subject term was grep-confirmed present in its own file.

## Check 3 — the four unknown quadrants

All four carry their own verdict section in `findings/S2.md`: Known knowns (covered), Known unknowns
(covered), Unknown knowns (covered, playbook stronger), Unknown unknowns (partial — the
achievable-ceiling facet is the gap).

4 of 4.

## Check 4 — ledger completeness

14 units dispatched, 14 ledgers persisted under `findings/`. No unit returned empty; no unit was
dropped.

## Cross-unit handoffs raised during the audit — all resolved

| Raised by | Handoff | Resolution |
|---|---|---|
| S2 | Q2 routing asymmetry → S7 | S7 assessed it: interview narrows, does not close. Both are one missing mechanism. |
| S2 | Q3 exemplar move overlaps S8 | S8 audited the exemplar move independently; no double-count. |
| S4 | reader-expertise axis → S11 | S11 declined it: no legitimate home, and attaching it would launder an auditor-originated finding. Kept as a separate observation with its own justification. |
| S13 | F4 explainer shares S11's doctrine | Flagged not-double-counted; S13 supplies a second trigger for whatever home S11 lands on. |
| S1 | post-implementation residue → S11/S12/S14 | All three audited it from their own angle. |

## Findings this gate did NOT check

- Whether individual verdicts are correct. That is the auditors' work, and two of them (S6, S7)
  shipped without an independent review pass because advisor was rate-limited. Recorded in those
  files.
- Whether the remediations are good. That is task #16.

## Outcome

No orphan text. No uncovered pattern. No uncovered quadrant. No missing ledger. Coverage is
satisfied by construction.
