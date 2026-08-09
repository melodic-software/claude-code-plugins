# audit-pass — suppression

This file owns §4: where a suppression is recorded, how the cascade layers merge, and the four
dispositions an entry resolves to on the next run.

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md).

## 4. Suppression, per target class

**The governing rule: suppression is always central. There is no inline marker, at any target.**

An inline form is rejected, recorded here so it is not re-proposed. A marker would
have to carry the same constituents a central entry does — `check`, `claim`, every site, reason,
date — because the key is derived from them, so it duplicates the central record instead of
simplifying it. It cannot express a pairwise finding at all: a marker sits at one site, and a
two-site finding has no one site to sit at. And writing one into a clean worktree is the thing 2.1
forbids. A second format with strictly less capability, a second parser, and an unspecified
inline-versus-central merge rule is cost with no capability behind it.

**A central entry stores the finding's constituents, not a bare id.** `check`, `claim`, and **every**
`(surface, anchor)` site, alongside the required reason and date — with `finding_id` as the mapping
key derived from them. A bare id is a one-way hash: it can answer "is this exact finding still
present" and nothing else, so a record built on it cannot compute a tiered match and none of the four
dispositions below is implementable on top of it. The constituents also make the entry diagnosable by
a human reviewer — an operator auditing a year-old suppression can read what was accepted instead of
a hex string. They are required from the first published contract rather than retrofitted, because
this record is operator-authored and commonly committed: adding required keys later is a migration on
somebody else's tracked data, and the constituents cannot be recovered from the id they hash into.

| Target class | Disposition |
|---|---|
| A project-scope file the pass may edit | Central entry. Being *allowed* to edit a file is not a reason to edit it to silence a report about itself |
| A file the pass does not own | Central entry. Editing a file you do not own to silence a report is a boundary violation dressed as configuration |
| A user-scope file | Central entry, and **never** an edit to the file. User-scope surfaces are routed, never edited |
| A registered byte-identical cluster copy | **Refused**, naming the canonical source. The copy is excluded from the scan set, so an entry against it is stale by construction |

**The record and its layers.** `.claude/audit-pass.md` in the target repository, resolved across the
three config-cascade layers — user-global, team (tracked), and a gitignored local overlay. Layers
merge **per key**: a later layer's entry for one `finding_id` wins for that id alone, and every id it
does not mention keeps the earlier layer's entry. A list would be taken whole, so one personal entry
would silently discard the team's entire accepted set.

**A personal layer never enacts a suppression.** Two rules, and the first carries the weight:

1. **A personal entry for an id the team layer does not carry does not suppress.** It is reported as
   **`personal-only, not applied`**, naming promotion to the team layer as how to make it take
   effect. Absence from the team layer *is* the team's unsuppressed state, so applying such an entry
   would hide a finding the team never accepted. §3 already settles where the decision belongs: a
   suppression is a decision about the **repository**, not about a checkout — and a decision about
   the repository belongs in the layer the repository tracks.
2. **On a direct conflict for the same id the team layer wins**, inverting the usual precedence. This
   rule is narrower than it sounds, and saying so is the point: 4.5 forces an entry's constituents to
   hash to its own key, so two entries sharing a `finding_id` have identical `check`, `claim`, and
   `sites` by construction. The only fields that can differ are `reason` and `date` — so what the
   inversion protects is the team's recorded justification, not which findings are visible. Rule 1
   owns that.

A personal layer is therefore a **draft** surface: an entry there is read, reported, and attributed,
and takes effect only once promoted. Every reported entry names its contributing layer, which is what
makes both rules auditable rather than merely declared.

The cross-consumer key contract is published separately, as the **finding-suppression** convention in
this marketplace. This section states what the pass itself needs in order to run, so the skill
resolves nothing by reaching outside the plugin.

The record is **excluded from the scan set** — otherwise suppressing a finding changes the tree and
perturbs the next run.

### Matching an entry: the four dispositions

Storing constituents is what makes tiered matching computable at all — a bare id can only ever say
matched or gone — so the contract states the full table rather than a binary.

Tiered matching is prior art, not an invention. SARIF carries a whole **Appendix B (Normative), "Use
of fingerprints by result management systems"**, whose subject is that a fingerprint is expected to
be *stable enough* rather than absolutely stable. GitHub's documented behavior on a mismatch is
close-and-reopen: "If the filepaths differ for the same result, each time there is a new analysis a
new alert will be created, and the old one will be closed"
([SARIF support for code scanning](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning),
verified 2026-07-25).

| Condition | Disposition | Effect on the suppression |
|---|---|---|
| **Every** site's anchor matches, `(check, claim)` match, **and no matched site is in §1's anchor-collision state** | **SAME, UNCHANGED** | Applies silently, as an exact match always has. Phrased over the whole `sites` set rather than "both anchors", because the set holds one entry for an ordinary single-site finding and two for a pairwise one — the two-site phrasing left an unchanged single-site entry matching **no** row, so the commonest case in the table had no disposition at all. |
| Exactly one anchor changed; the other anchor and `(check, claim, both surfaces)` all match, **and no matched site is in §1's anchor-collision state** | **SAME, CHANGED** | **Carries forward, marked `needs-reconfirmation`**, surfaced in `suppressed` with the changed side named. Never silent: the edit may have *been* the fix attempt, and silently re-suppressing hides precisely the case the operator most needs to see. |
| Both anchors changed, **or** `claim` changed, **or** a surface changed, **or** any matched site is in §1's anchor-collision state | **OLD CLOSED, NEW OPENED** | The old entry goes **stale** per 4.2, never silently dropped. The new finding is unsuppressed. |
| The finding is absent from the new run entirely | **CLOSED** | Must be **accounted for** as exactly one of: matched to an applied fix; matched to a successor by partial match; **retired with its check**, when the check that raised it is absent or renamed in the new run's detection configuration; or reported as an **UNEXPLAINED DISAPPEARANCE**, which fails the run's self-check exactly as a P4a tolerance breach does. |

A single-site finding has no "other anchor", so row 2 cannot apply to one: a changed anchor on a
single-site finding falls to row 3.

**The collision clause is tested first, and it is what makes §1's guarantee reachable.** §1 states
that two identical normalized excerpts under one heading path collide and that **no suppression
carries forward across it** (assertion 1.10a) — but a collided site's anchor is, by construction,
*unchanged*: the discriminator is a digest of the heading path, so gaining a duplicate elsewhere in
the section moves nothing. Without the clause a previously-suppressed excerpt that later gains an
identical duplicate satisfies row 1 exactly and re-applies its suppression **silently**, over a
finding the operator's original decision provably cannot be attached to. So collision is evaluated
before the anchor comparison in every row and routes to row 3 whatever else matches, and the run
reports the collision with its occurrence count alongside the stale entry. This reuses row 3's
existing disposition rather than adding a fifth: stale-plus-unsuppressed is already this section's
fail-closed answer to an ambiguous match — the same answer row 2's unique-successor rule gives — so
the operator re-judges in one action and nothing is hidden in the meantime.

**`retired with its check` is a disposition rather than an exemption, and the difference matters.** A
delegated catalog that removes or renames a check legitimately makes its findings disappear with no
fix and no successor, and the unconditional rule called that an UNEXPLAINED DISAPPEARANCE and failed
the run — the comparability contract already treats a detection-version change as non-comparable, so
the two disagreed. But suppressing the accounting entirely would be worse: findings would vanish
silently on any catalog edit, which is the exact shape row 4 exists to detect. So the disappearance
is still accounted for, still reported, and named as retirement with the retiring check and the
version transition cited. Any suppression entry keyed to a retired check goes **stale** rather than
being deleted, because a check that returns under its old name must not silently re-apply a
suppression the operator has not seen since.

**Row 2 requires a unique successor, and without that requirement it is not a function.** Two current
pairwise findings can share the unchanged anchor, both surfaces, `check`, and `claim` while differing
only in the changed-side anchor — and then *both* satisfy row 2's condition for one old entry. The
**claim-unqualified fallback makes this ordinary rather than exotic**: with `claim` bound to the bare
check id, every claim that check can make at one site pair collapses onto one identity, so the
collision is the expected case for any catalog that has not declared its templates. Carrying the
entry to both suppresses a newly opened conflict the operator never accepted; picking one is
nondeterministic and would break P1 by construction, since the choice depends on iteration order.

So: **row 2 applies only when exactly one candidate satisfies it.** With two or more, the old entry
goes **stale** per 4.2 and *every* candidate is left unsuppressed and reported, with the ambiguity
named and the candidates listed. That is the fail-closed direction — it re-surfaces a finding the
operator may re-suppress in one action, where the alternative silently hides one they never saw. It
also gives the claim-unqualified fallback a visible cost at exactly the point that costs something,
which is where the coverage note says the imprecision would be felt.

**Row 4 is the detector P2 has been missing.** §6's P2 states that a finding vanishing without a fix
is a defect — a definition with nothing able to observe it. Requiring every disappearance to be
accounted for is what turns that definition into a check capable of failing.

| # | Assertion |
|---|---|
| 4.1 | A suppressed finding does not appear in the next run's findings, and appears in the `suppressed` section with its reason, its date, and its contributing cascade layer. |
| 4.1a | A personal-layer entry for a `finding_id` the team layer does not carry **does not suppress**: its finding still appears in the run's findings, and the entry appears in `suppressed` as **`personal-only, not applied`** naming its contributing layer. |
| 4.2 | Every entry resolves to exactly one of the four dispositions above. `SAME, CHANGED` carries the suppression forward and reports it as `needs-reconfirmation` naming the changed side; `OLD CLOSED, NEW OPENED` reports the old entry as **stale** and leaves the new finding unsuppressed. Neither is silent. |
| 4.3 | Adding a suppression does not change any other finding's `finding_id`. |
| 4.4 | No suppression mechanism writes to a path in the derived exclusion set. Attempting to suppress a finding in a registered cluster copy makes the run refuse and name the canonical source. |
| 4.5 | An entry whose stored constituents do not hash to its own key is reported as malformed and does not suppress. The constituents are authoritative; the key is derived from them. |
| 4.6 | Every finding present in the previous run and absent from this one is accounted for as exactly one of: matched to an applied fix; matched to a successor by partial match; **retired with its check**, when the check that raised it is absent or renamed in the new run's detection configuration; or reported as an **UNEXPLAINED DISAPPEARANCE**. Only the last fails the run's self-check. |
| 4.7 | Suppress an excerpt finding, then add an identical normalized excerpt under the same heading path: the entry does **not** apply silently. It resolves to `OLD CLOSED, NEW OPENED` — reported stale per 4.2 with the collision and its occurrence count named — and the finding appears unsuppressed, satisfying 1.10a through the matching table rather than only in §1's prose. |
