# /knowledge:docpage-digest Checklist

Copy into `<work-root>/docpage-digest-checklist.md`. Tick each phase as it completes; the ticked
state is the cross-session resume pointer.

## Provenance

Fill `Canonical URL` and the resolved work root at run start, before the first fetch — SKILL.md's
collision check reads them to tell a resume from a slug collision.

- Canonical URL:
- Fetch date:
- Fetch channel (raw-md / rendered / binary+extraction):
- Extraction tooling (the tool and version that produced `source.txt` from a PDF original; `n/a`
  when the fetch needed no extraction):
- Publisher profile used (or "no profile"):
- Resolved work root (via the `library_dir` seam — record the absolute path so a resumed session
  need not re-derive it):

## Phases

- [ ] Phase 1: Fetch — unaltered original snapshotted as `source.<ext>`, immutable: `source.md`
      for a markdown or rendered-text channel, or `source.pdf` **plus** its `source.txt`
      extraction for a PDF original (both are originals; name the extraction tooling above)
- [ ] Phase 2: Inventory — `INDEX.md` written (headings, themes, digest map, status rows)
- [ ] Phase 3: Digest fan-out — one agent per digest unit → `digests/NN-slug.md` (fixed structure)
- [ ] Phase 4: Dual verification — Verifier A (same-vendor) + Verifier B (cross-vendor) verdicts
      in `verification/` (append-only; degraded fallback recorded, never silent)
- [ ] Phase 5: Interview handoff — `interview-handoff.md` authored; `/planning:interview` run or
      artifact presented

## Skip criteria

- Phase 4 Verifier B — degrade per SKILL.md only when the cross-vendor verifier is genuinely
  unavailable; record reason in the verdict header
- Phase 5 interview invocation — skip (present artifact only) when the planning plugin is absent
