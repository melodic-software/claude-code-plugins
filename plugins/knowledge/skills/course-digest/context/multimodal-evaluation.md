# Multi-Modal Gap Evaluation

Evaluation of audio processing and multi-modal gaps in the course digest pipeline.
Produced by Task 23 (Session 7, 2026-04-01).

## Current Pipeline Modalities

| Modality | Source | Processing | Used in Summaries |
|----------|--------|-----------|-------------------|
| Text transcripts | Dometrain DOM panel | Timestamped markdown | Yes |
| Video frames | ffmpeg scene detection + interval | Raw PNGs, contact sheets, dedup | No (TDD has 992 frames, MCP has 0) |
| Audio | Not extracted | None | No |
| Code from video | Not extracted | None | No |
| Slide text | Not extracted | None | No |

## Gap Analysis (Priority Order)

### P1: Code OCR from Video Frames — HIGH VALUE, LOW EFFORT

**Problem**: Instructor codes on screen. Transcript captures what they SAY about code but
misses actual syntax, variable names, import statements, function signatures, file structure.
For programming tutorials, this is 70%+ of visual content.

**Evidence**: Research (MDPI 2024, Springer 2026) confirms code extraction from screenshots
captures information absent from transcripts. LLMs outperform Tesseract (~95% vs 70-80%) but
cost more.

**Solution**: Run Tesseract OCR (with image preprocessing) on existing 992 TDD course frames.
For higher accuracy on specific frames, Claude's vision can read PNGs directly during
summarization phase.

**Recommended approach**: Hybrid two-pass — Tesseract on all frames (free, fast), then
selectively send high-value frames (code-heavy keyframes) to Claude vision during summarization.

**Output**: `code-snippets.md` per lesson, containing extracted code blocks.

**Cost**: ~5 min to run OCR on 992 frames. Zero API cost for Tesseract pass.

### P2: Slide Content Extraction — MEDIUM VALUE, LOW EFFORT

**Problem**: Architecture diagrams, bullet point slides, visual aids captured as frames
but not processed. Text on slides contains structured information (definitions, comparisons,
workflows) not present in spoken transcript.

**Evidence**: Panopto, FIZ Karlsruhe research confirms slide OCR adds 5-15% content over
transcripts alone. Most valuable for conceptual/architectural content.

**Solution**: Detect slide boundaries (frame-diff threshold) and extract per-slide text via OCR
with deduplication. Not yet built.

**Cost**: Low — runs on extracted frames.

### P3: Code Diff Detection — MEDIUM VALUE, MEDIUM EFFORT

**Problem**: In step-by-step coding tutorials, code evolves across lessons. Detecting what
changed between frames reveals instructor's incremental development process.

**Solution**: Compute frame-pair diffs over OCR'd code regions and highlight code changes.

**Cost**: Requires keyframe pairs (before/after) — needs scene analysis to identify code
transition points first.

### P4: Audio Re-transcription (Whisper) — LOW VALUE, HIGH EFFORT

**Problem**: Platform-provided transcripts may have auto-generated errors (names, technical
terms, acronyms). Whisper could provide higher accuracy.

**Evidence**: BrassTranscripts benchmark shows Whisper WhisperX large-v3 achieves 88-93%
accuracy. But Dometrain transcripts from DOM panel appear to be 90%+ already (manual spot
check of MCP course transcripts shows clean, readable text with proper terminology).

**Recommendation**: SKIP. DOM transcripts are sufficient. Only reconsider if a platform's
transcript quality degrades noticeably (add to validator checks — Task 22 already monitors
transcript quality via chars-per-minute ratios).

### P5: Audio Analysis (Pacing, Emphasis, Speaker ID) — LOW VALUE, HIGH EFFORT

**Problem**: Audio could reveal emphasis patterns, pacing (fast vs slow sections),
multi-speaker identification for Q&A sessions.

**Evidence**: Limited. For course digest, we care about WHAT was said (content), not HOW it was
said (delivery). Pacing data doesn't inform repo-applicable analysis.

**Recommendation**: SKIP entirely. Not relevant to pipeline's goal (extracting knowledge
for repo application).

## Integration Architecture

### Option A: Dedicated Frame-Analysis Phase (Recommended for Scale)

```
Phase 2: Extract → transcripts + frames
Phase 2.5: Analyze Frames (NEW) → OCR + slide extraction
Phase 3: Synthesize → module summaries (using ALL context)
```

Run a frame-analysis tool over extracted PNG frames:

- Tesseract OCR (with preprocessing) on each frame for code text
- Slide-boundary detection + per-slide OCR for slide-heavy lessons
- Store results as `code-snippets.md` and `slides.md` per lesson

**Advantage**: No changes to extraction pipeline. Runs on files already on disk.
**Challenge**: Need a maintained frame-analysis tool — either build a local script or vendor
one in. Mapping lesson frames to a stable lesson identifier is straightforward (filesystem
layout already groups frames per lesson).

### Option B: Claude Vision During Summarization

During Phase 3 (Synthesize), when generating module summaries, include selected keyframes
as images in Claude prompt. Claude's multimodal vision reads code from frames directly.

**Advantage**: Zero pipeline changes. Just pass PNG paths to Claude during summarization.
**Challenge**: 992 frames is too many for a single context window. Need keyframe selection
(contact sheets or manifests already do this via classify-frames.js).

### Recommendation

**Start with Option B** — zero-effort and Claude already reads images. Existing
classify-frames.js + generate-manifests.js pipeline produces curated frame sets per lesson.
Include these in summarization prompt.

**Graduate to Option A** when volume justifies automation (10+ courses) or when consistent
code extraction format matters for downstream analysis.

## Thresholds for Re-evaluation

| Trigger | Action |
|---------|--------|
| Platform transcript accuracy drops below 80% | Add Whisper re-transcription |
| 10+ courses digested | Automate frame analysis (Option A) — build or vendor an OCR + slide-extraction tool |
| Non-Dometrain platform without transcript panel | Build a full ingest pipeline (transcript via Whisper, scene detection via ffmpeg) |
| Slide-heavy course (>50% lessons with slides) | Add slide-boundary detection + per-slide OCR to workflow |
