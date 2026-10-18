# /knowledge:docpage-digest Checklist

Copy into `<work-root>/docpage-digest-checklist.md`. Tick each phase as it completes; the ticked
state is the cross-session resume pointer.

## Provenance

Fill `Canonical URL` and the resolved work root at run start, before the first fetch. SKILL.md's
collision check reads them to tell a resume from a slug collision.

- Canonical URL:
- Fetch date:
- Fetch channel (raw-md / rendered / binary+extraction):
- Extraction tooling (the tool and version that produced `source.txt` from a PDF original; `n/a`
  when the fetch needed no extraction):
- Publisher profile used (or "no profile"):
- Resolved work root (via the `library_dir` setting; record the absolute path so a resumed session
  need not re-derive it):

## Phases

- [ ] Phase 1: Fetch the unaltered original, snapshotted as `source.<ext>`, immutable: `source.md`
      for a markdown or rendered-text channel (plus the raw `source.html` where the profile
      requires it, to recover chart, diagram, alt, and caption text), or `source.pdf` **plus**
      its `source.txt` extraction for a PDF original (both are originals; name the extraction tooling above)
- [ ] Phase 2: Inventory, with `SOURCES.md` written (headings, themes, digest map, status rows,
      relied-on links read from the snapshot)
- [ ] Phase 3: Digest fan-out, one agent per digest unit → `digests/NN-slug.md` (fixed
      structure; verbatim quotes in column-0 fences under bold `**CN.**` labels; each unit's
      model recorded as mapped and actual; refusals and waits recorded)
- [ ] Phase 4: Dual verification: pin-manifest written on agent-reported completion; standing
      gates (`check-fences-exact.py`, `check-snippets.py`, `check-prose-terms.py`, and `check-html-rows.py` when digests
      carry `**FN.**` rows quoted from `source.html`) PASS; Verifier A (same-vendor) +
      Verifier B (cross-vendor) verdicts in `verification/` (append-only; each arm states the
      hashes it audited and one verdict, PASS / PASS-WITH-FINDINGS / FAIL / BLOCKED, done only on
      PASS or PASS-WITH-FINDINGS from both arms; degraded fallback / death-ladder recorded, never silent)
- [ ] Phase 5: Interview handoff, with `interview-handoff.md` authored (relied-on-links table: one
      disposition per link, covered / queued / skipped with a reason) and its own commands replayed
      (every Phase 4 check precedes it); `/planning:interview` run or artifact presented

## Skip criteria

- Phase 4 Verifier B: degrade per `context/dual-verification.md` only when the cross-vendor
  verifier is genuinely unavailable; record reason in the verdict header
- Phase 3/4 subagent death or refusal: the ladder in `context/pipeline-hardening.md` (a
  concurrency refusal waits, then one more dispatch → retry window → inline-with-disclosure, never
  for a unit the profile maps to another model → degraded marker + re-run trigger); do not tick
  the phase complete on a degraded marker
- Phase 5 interview invocation: skip (present artifact only) when the planning plugin is absent
