---
name: recheck-against-upstream
description: "Re-anchor the discipline that existing state — config, code, docs, infra — is not evidence of its own correctness, then audit the surface in flight against CURRENT official upstream docs and classify each divergence. Use when: 'recheck against upstream', 'check this against the docs', 'is our config still current', 'did upstream change', 'are we still doing this right', 'verify against the official docs', 'this may have drifted from upstream', 'audit our setup against the vendor docs', or at conversation start on config, infra, or integration work."
user-invocable: true
disable-model-invocation: false
metadata:
  re-anchor-batch: situational  # only when config/infra/integration is in play
  re-anchor-batch-rank: 30
---

# Recheck against upstream

A drift corrector for the discipline that existing state does not vouch for
itself. The method — re-anchor, audit the work in flight, correct forward,
report, and the tone that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to upstream-conformance
discipline.

## The discipline this re-anchors

Existing state — a config file, a code path, a runbook, an infra
definition — is evidence of *what is*, never proof that it matches the
upstream it depends on. Upstream ships new defaults, renames flags,
deprecates APIs, and obsoletes yesterday's workaround; the state that was
correct when written silently rots. Resolve the source of truth per the
method doc's ladder: if the consuming project states an
upstream-conformance rule in its own `CLAUDE.md` / `.claude/rules/`,
re-anchor THAT. Otherwise re-anchor this portable baseline:

- **Present state is not self-justifying.** "It's already configured this
  way" and "the code does X" describe the state; neither shows it still
  matches upstream. Conformance is a claim to verify, not to assume.
- **Compare against the CURRENT official upstream, fetched now.** Re-read
  the vendor's live documentation for the surface in play this session —
  never training-data recall of it, never a stale in-repo summary of it.
- **Resolve the applicable upstream version first.** When the repo pins a
  supported major/minor, compare against the docs for THAT version — the
  latest docs can legitimately prescribe APIs and defaults the pin does not
  have. Divergence between the pinned line and latest is its own finding
  (upgrade candidate or deliberate hold), never a false gap against the pin.
- **Unverified conformance is not "clean".** A surface you did not compare
  is unaudited, not passing. Report what was compared and what was skipped;
  do not launder the unchecked into a green result.

## The loop's audit step — classify each divergence

Run the method doc's audit as a compare-and-classify pass. For the surface
in flight, fetch the current upstream docs, diff the repo's state against
them, and sort every divergence into one of three categories:

1. **Gap** — docs say X, we do Y, and no rationale is recorded anywhere in
   the repo. Treat as a straight defect to correct toward upstream. Call out
   deprecation and version drift here: a flag upstream renamed, a default it
   changed, an API it marked deprecated is a gap even when the old form
   still functions today.
2. **Deliberate divergence** — a rationale IS recorded in the repo's docs or
   an ADR. Do not "correct" it. Audit only whether it STILL holds against
   the current docs: upstream may have shipped the very thing the workaround
   was written to route around, obsoleting the recorded rationale. Report-
   only when the rationale still holds; flag it when the docs have overtaken
   it.
3. **Undocumented divergence** — the state looks intentional but no written
   rationale exists, so the correct resolution is the human's call: adopt
   the docs' way, or keep the divergence and record its rationale. Route the
   resolution to the repo's ADR / docs convention (read it from the
   consuming project's own instruction layer); do not silently pick a side.

Correct each forward now per the method doc: fix gaps toward upstream,
re-check that deliberate divergences still hold, and surface undocumented
ones for the human with both options stated. Where your own reading of the
docs is the suspected source of error, re-verify in a fresh-context
subagent.

## Distinct axes — what this is NOT

- **vs `/re-anchor:reason-dont-recite`.** That skill interrogates INTERNAL
  precedent — inherited structure coasting on "that's how it's done here".
  This one measures against an EXTERNAL upstream authority: the vendor's
  current docs, not the repo's own inherited habits.
- **vs `/re-anchor:follow-our-standards`.** That skill audits against the
  consuming ORG's own engineering standards. This one audits against the
  third-party VENDOR's documentation — the upstream the state depends on,
  not the conventions the org authored.

## What this skill does NOT do

- **Does not treat divergence as automatic error.** A recorded, still-valid
  deliberate divergence audits clean; the duty is to classify, not to force
  every difference back to the default.
- **Does not fabricate conformance or a finding.** A surface that matches
  the current docs audits clean; a surface not compared is reported as
  skipped, never as passing.

## Gotchas

- **"Still functions" is not "still current".** A deprecated flag or a
  superseded default that has not yet been removed is a gap, not a pass —
  version drift is a finding even before it breaks.
- **A recorded rationale can expire.** The category-2 trap is treating "we
  decided this once" as permanent; re-check it against what upstream ships
  today, because the workaround may now be obsolete.
- **Silence about the unchecked reads as a pass.** State the surfaces you
  compared and the ones you did not; an honest skip list is part of the
  report, not an admission of failure.
