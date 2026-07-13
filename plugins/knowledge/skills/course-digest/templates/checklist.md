# /knowledge:course-digest Checklist

Copy into `.work/<slug>/course-digest-checklist.md`. Tick each phase as it completes; skip per the criteria below.

## Phases (`[full-context]` synthesis requires transcript + frames + code)

- [ ] Phase 1: Discover — course structure (modules, lessons, URLs) → `course.json`
- [ ] Phase 2: Extract — per-lesson transcript, screenshots, notes, code references
- [ ] Phase 2b: Process Frames — classify, dedup (report-only), manifests (needs ffmpeg + ImageMagick)
- [ ] Phase 2c: Download resources + analyze companion code repo
- [ ] Phase 2d: Validate — `validate-extraction.js` quality checks before synthesis
- [ ] Phase 3: Synthesize — per-module multi-agent summaries
- [ ] Phase 4: Analyze — course-level synthesis, cross-cutting themes
- [ ] Phase 5: Recommend — what applies to THIS repo (`repo-candidates.md`, `action-items.md`)

## Skip criteria

- Phase 2 screenshots/frames — skip for lessons with no visual content (summaries become `[transcript-only]`)
- Phase 2b — skip when no frames were extracted
- Phase 2c — skip when no companion repo or downloadable resources exist
- `extract` action stops after Phase 2d; `analyze` action starts at Phase 3 on already-extracted content
