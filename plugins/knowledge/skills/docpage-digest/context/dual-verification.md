# Phase 4: dual verification

The terminal verification phase of [`../SKILL.md`](../SKILL.md), run once Phase 3's digest exists
and before anything is presented. A digest presented without it is unverified, which is the state
this phase exists to rule out.

Two independent verifiers over the full digest set, fresh context, production rationale withheld:

- **Verifier A**. Same-vendor Claude, at the strongest effort available to the session,
  checking completeness (no source section unrepresented), fidelity (digest claims traceable to
  source), and fabrication (no claim without a source anchor).
- **Verifier B**. Cross-vendor (e.g. Codex via the `codex` plugin, high reasoning effort), same
  three checks. Cross-vendor independence is the point: correlated blind spots differ.

Verdicts land in `<work-root>/verification/` and are **append-only historical records**. A
wrong verdict gets a dated corrections-applied file beside it, never a rewrite. Corrections
apply to the digests; re-verify what changed.

**Pin on agent-REPORTED completion, never file presence.** A digest file on disk does not mean
its agent is done. One unit's agent rewrote its file seven minutes after a presence-based pin.
Pin the tree only after every dispatched digest agent has *returned*, then write
`<work-root>/verification/pin-manifest.json` (path + sha256 per frozen file; shape in
[pipeline-hardening.md](pipeline-hardening.md)). That manifest freezes the tree
for the verification window. Each arm hashes what it audits and states those hashes in its
verdict; a mismatch is BLOCKED, not a content finding. **A verdict file on disk is an
intermediate write, never a report**. Do not apply corrections or re-pin because a file
appeared; wait for the arm to return. Editing a slice mid-audit voids that audit: the verifier's
findings stop describing bytes that exist.

**Every correction round leaves an applied record, and the next round reads it.** The record is
dated, lands beside the verdicts, and names what changed and why; any finding the round surfaced but
was not scoped to fix goes in its "New findings" section, which is a **required input to the next
round's brief**. Both halves bind, a faithfully written record nobody reads drops findings on the
floor exactly as silently as no record at all. A verdict likewise lands in
`<work-root>/verification/` or it did not happen: one written to a session scratchpad is unreachable
by every later round. (One slice's round-3 record was written faithfully, "New findings" section and
all, and the next round never read it. Three findings it named were still unfixed a round later, and
only a verifier's cross-check noticed; an 18-unit fan-out in the same slice edited seven units with
no record, leaving them unattested; two of the slice's verdicts were written outside `verification/`
and no later round could read them.)

**A mechanical gate reports only what it parsed, and only the fields it checks.** Any script used as
a verification gate errors loudly on input it cannot recognize, and a clean result is read as
covering just the rows and fields it actually exercised. **A gate is a claim that needs its own
evidence:** do not believe a PASS until that gate's negative-control suite has failed the known-bad
fixtures (empty, unparsable, zero-parse, indented fence, fabricated payload). **The ordering is
not negotiable:** a gate that silently skips what it cannot parse is fixed *before* it is made a
required artifact, or the mandate converts a visible gap into an invisible pass. (Both arms
independently caught the campaign's quote checker printing "all checks clean" over a digest whose
14 claims it could not parse at all; `gate-family-consistency.sh` printed PASS after `mktemp`
failed and it parsed zero claims; `gate-coverage.sh` printed OK over blank inventories.)

**Standing gates (required, after the pin):**
[`check-fences-exact.py`](../scripts/check-fences-exact.py) and
[`check-snippets.py`](../scripts/check-snippets.py). Invocation in
[pipeline-hardening.md](pipeline-hardening.md). They stand alongside the quote
gate. Prerequisite: `python3` (3.9+). A PASS covers only what each script prints. Their
negative-control evidence is `scripts/test_check_fences_exact.py` and
`scripts/test_check_snippets.py`.

**Commands are replayable in every pipeline artifact, not just digest rows.** INDEX rows, applied
records, verdicts, rulings and handoffs carry commands too, in the same command-plus-raw-count form,
and each is replayed where it is authored. No sweep reaches an artifact that did not yet exist
when it ran, so the phase that writes one replays it before that phase ends. (One slice yielded
five record-level command defects: two greps quoted without a path operand, an unrunnable command
invisible to the replay regex, and two records misstating their own pair counts, and one
correction record propagated the wrong line number it had been written to fix.)

**Reconcile the digest set against itself before Phase 5.** Every other check is scoped within a row
or between a row and `source.md`, so parallel digest agents can affirm, deny, and abstain on the same
external page and still earn PASS from both verifiers. Group the digests' claims by quoted text and
by cited site: identical quotes carrying non-identical tags, and rows of the same assertion class
resting on materially different absence bases, are defects to resolve or to disclose in the handoff.
(Ten rows digesting one directive reached two different tags via at least three distinct absence
bases; the tag split was the visible symptom, the bases diverged first. Both arms found splits of
this shape by hand, and only by choosing to look.)

**Degraded-verifier fallback (never silent):** when the cross-vendor verifier is unavailable
(not installed, sandbox-broken, quota), substitute a second same-vendor verifier briefed as an
adversarial refuter, and RECORD the degradation and its reason in the verdict file header. A
verification record that hides its degraded provenance is worse than a missing one. That rule
covers a *missing* cross-vendor arm, not a session that cannot spawn.

**Subagent-death / usage-limit ladder** (dominant failure mode, ahead of content defects. Lost
agents, killed completion reports, mid-audit kills, slot exhaustion, refused fan-out):

1. **Retry window**. Re-dispatch the same brief once; record the death and the retry.
2. **Inline-with-disclosure**, if the retry also dies, complete that unit inline and record
   `inline-with-disclosure` naming the dead slot and the unit.
3. **Degraded marker + re-run trigger**, if inline is impossible, write the marker and name the
   unfinished units; do not tick the phase complete.

Silence is not a rung. Detail: [pipeline-hardening.md](pipeline-hardening.md).
