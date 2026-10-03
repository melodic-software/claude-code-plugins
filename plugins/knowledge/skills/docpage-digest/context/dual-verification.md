# Phase 4: dual verification

The terminal verification phase of [`../SKILL.md`](../SKILL.md), run once Phase 3's digest exists
and before anything is presented. A digest presented without it is unverified, which is the state
this phase exists to rule out.

Two independent verifiers over the full digest set, fresh context, production rationale withheld:

- **Verifier A**. Same-vendor Claude, dispatched as a Workflow `agent()` call, checking
  completeness (no source section unrepresented), fidelity (digest claims traceable to source),
  and fabrication (no claim without a source anchor). The call passes effort `high` by default,
  and the operator may set a different level for one run. A call that names an agent omits effort
  unless the run overrides it, so that agent's own pin holds. The verdict header records the
  effective effort and where it came from. Where the Workflow tool is unavailable, dispatch
  verifier A through the Agent tool instead. That tool sets no effort per call, so the effort is
  the named agent's pin or else the session level, and the verdict header says which. If that
  level is below `medium`, stop Phase 4 and report the level instead of verifying.
  - **Pointer**: `docs/plugin-philosophy.md` "Effort tiers", the "Where per-task effort is set"
    record, in the marketplace repository; no docs page covers per-call Workflow effort.
  - **As of**: 2026-10-02
  - **Recheck trigger**: a docs page starts covering it.
- **Verifier B**. Cross-vendor (e.g. Codex via the `codex` plugin, high reasoning effort), same
  three checks. Cross-vendor independence is the point: correlated blind spots differ.
  A Codex arm run in a sandbox without network access cannot re-fetch a live page. Brief it over the slice's local files (`source.*`, the digests, `SOURCES.md`, any
  absence-corpus pages already fetched to disk) and have it name, in its verdict header, every
  live-doc check it could not replay. That arm is degraded for those checks only, under the
  fallback rule below. Granting it network access instead is the operator's configuration call,
  recorded in the header when made.
  - **Pointer**: for a Codex sandbox's network default and how to enable it, see
    <https://learn.chatgpt.com/docs/agent-approvals-security#network-access>.
  - **As of**: 2026-10-01
  - **Recheck trigger**: that section changes the default network access of a local Codex
    sandbox mode.

Verdicts land in `<work-root>/verification/` and are **append-only historical records**. A
wrong verdict gets a dated corrections-applied record beside it, never a rewrite. Corrections
apply to the digests; re-verify what changed.

**One corrections file per digest unit per round.** Agents applying corrections in parallel
each write only their own unit's file,
`verification/corrections-<NN-slug>-r<round>-<YYYY-MM-DD>.md`; no two agents ever append to one
file. After every correction agent has returned, the parent writes the round's index,
`verification/corrections-applied-r<round>-<YYYY-MM-DD>.md`, which lists each unit file and
gathers their "New findings" sections. That index is the round's applied record below.

**Pin on agent-REPORTED completion, never file presence.** A digest file on disk does not mean
its agent is done: an agent can rewrite its file minutes after a presence-based pin.
Pin the tree only after every dispatched digest agent has *returned*, then write
`<work-root>/verification/pin-manifest.json` with
`python3 <skill-dir>/scripts/pin-manifest.py <work-root>` (path + sha256 per frozen file; shape
in [pipeline-hardening.md](pipeline-hardening.md)). That manifest freezes the tree for the
verification window, for every writer, the orchestrating session included. Each arm hashes what
it audits and states those hashes in its verdict, and `--check` on the same command names any
moved file; a mismatch is BLOCKED, not a content finding. **A verdict file on disk is an
intermediate write, never a report**. Do not apply corrections or re-pin because a file
appeared; wait for the arm to return. Editing a slice mid-audit voids that audit: the verifier's
findings stop describing bytes that exist.

**Every correction round leaves an applied record, and the next round reads it.** The record is
dated, lands beside the verdicts, and names what changed and why; any finding the round surfaced but
was not scoped to fix goes in its "New findings" section, which is a **required input to the next
round's brief**. Both halves bind, a faithfully written record nobody reads drops findings on the
floor exactly as silently as no record at all. A verdict likewise lands in
`<work-root>/verification/` or it did not happen: one written to a session scratchpad is unreachable
by every later round.

**Each correction round sweeps every fixed class twice.** For each class of defect the round
fixed, the round searches the digest set for other occurrences of that class, then runs a second
search for the same class worded differently (other terms or another pattern), so one wording's
blind spot cannot pass as a zero. The applied record carries both commands and their raw counts,
in the replayable form below.

**A mechanical gate reports only what it parsed, and only the fields it checks.** Any script used as
a verification gate errors loudly on input it cannot recognize, and a clean result is read as
covering just the rows and fields it actually exercised. **A gate is a claim that needs its own
evidence:** do not believe a PASS until that gate's negative-control suite has failed the known-bad
fixtures (empty, unparsable, zero-parse, indented fence, fabricated payload). **The ordering is
not negotiable:** a gate that silently skips what it cannot parse is fixed *before* it is made a
required artifact, or the mandate converts a visible gap into an invisible pass.

**Standing gates (required, after the pin):**
[`check-fences-exact.py`](../scripts/check-fences-exact.py) and
[`check-snippets.py`](../scripts/check-snippets.py), plus
[`check-html-rows.py`](../scripts/check-html-rows.py) when digests carry `**FN.**` rows quoted
from `source.html`. Invocation in
[pipeline-hardening.md](pipeline-hardening.md). They stand alongside the quote
gate. Prerequisite: `python3` (3.9+). A PASS covers only what each script prints. Their
negative-control evidence is `scripts/test_check_fences_exact.py`,
`scripts/test_check_snippets.py` and `scripts/test_check_html_rows.py`.

**Commands are replayable in every pipeline artifact, not just digest rows.** SOURCES rows, applied
records, verdicts, rulings and handoffs carry commands too, in the same command-plus-raw-count form,
and each is replayed where it is authored. No sweep reaches an artifact that did not yet exist
when it ran, so the phase that writes one replays it before that phase ends.

**Reconcile the digest set against itself before Phase 5.** Every other check is scoped within a row
or between a row and `source.md`, so parallel digest agents can affirm, deny, and abstain on the same
external page and still earn PASS from both verifiers. Group the digests' claims by quoted text and
by cited site: identical quotes carrying non-identical tags, and rows of the same assertion class
resting on materially different absence bases, are defects to resolve or to disclose in the handoff.
(A tag split between rows is the visible symptom; the absence bases diverge first, and only a
deliberate look finds them.)

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
