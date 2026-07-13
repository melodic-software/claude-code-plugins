# Storage Schema

All course data lives under the invoking project's `library_dir` seam (or `${CLAUDE_PLUGIN_DATA}` when no library dir is configured), as `courses/<platform>/<slug>/`.

## Platform naming

Use platform's lowercase brand name: `dometrain`, `pluralsight`, `udemy`, `manning`, `oreilly`. Single public YouTube videos use `/knowledge:youtube` and its own slice layout — not this course data tree.

## Slug naming

Derive slug from course title: lowercase, kebab-case, max 50 chars, include instructor surname for disambiguation.

Examples:

- "Test-Driven Development in C#" by Guilherme Ferreira → `dometrain/tdd-csharp-ferreira`
- "From Zero to Hero: Dependency Injection in .NET" by Nick Chapsas → `dometrain/dependency-injection-dotnet-chapsas`

## Directory structure

```
courses/<platform>/<slug>/
  course.json                    # Course metadata + extraction progress
  modules/
    01-course-overview/          # Zero-padded position + kebab-case title
      module-summary.md          # Phase 3 output: module-level synthesis
      01-welcome/                # Zero-padded position + kebab-case title
        transcript.md            # Timestamped transcript
        notes.md                 # Lesson notes (if platform provides them)
        code-snippets.md         # Code extracted from lesson (inline code blocks)
        resources.json           # Download URLs, article links, PDF links (Teachable adapter)
        screenshots/             # Key frames as PNGs
          001-slide-intro.png    # Zero-padded, descriptive suffix
          002-code-example.png
      02-what-will-you-learn/
        transcript.md
        ...
    02-the-fundamentals/
      module-summary.md
      01-what-is-tdd/
        transcript.md
        ...
  code/                          # Code analysis: repo snapshot + per-lesson downloads
    analysis.json                # Phase 2c: structure, frameworks, modules (tracked in git)
    repo/                        # Final snapshot of companion source code
      evently/                   # (or section dirs for per-section repos)
        src/                     # Read by Phase 3 for architecture overview + cross-module patterns
        test/
    downloads/                   # Per-lesson code ZIPs (Initial + Final pairs)
      02.3 - Building the First Module - Initial.zip
      02.3 - Building the First Module - Final.zip
      ...                        # Read by Phase 3 for per-lesson deltas (diff = lesson's teaching)
  slides/                        # Presentation slide decks (PDFs)
  guides/                        # Bonus course guides, supplementary PDFs (NOT slides)
  resources/                     # Non-code resources: SQL, Postman, OpenAPI, Keycloak configs
  analysis/                      # Phase 4-5 outputs
    course-summary.md            # Full course synthesis
    repo-candidates.md           # What applies to our repo
    action-items.md              # Concrete next steps
```

## File formats

### course.json

```json
{
  "title": "Test-Driven Development in C#",
  "slug": "tdd-csharp-ferreira",
  "platform": "dometrain",
  "url": "https://dometrain.com/take/course/...",
  "instructor": "Guilherme Ferreira",
  "duration": "5h 41m",
  "totalLessons": 67,
  "extractedAt": "2026-03-31T...",
  "status": "extracting",
  "modules": [
    {
      "position": 1,
      "title": "Course overview",
      "slug": "01-course-overview",
      "lessons": [
        {
          "position": 1,
          "title": "Welcome",
          "slug": "01-welcome",
          "duration": "1m 37s",
          "url": "https://...",
          "status": "extracted",
          "hasTranscript": true,
          "hasScreenshots": false,
          "hasDownload": false,
          "hasVideo": true,
          "providerResources": {
            "lessonNotes": false,
            "readThisLesson": false
          }
        }
      ]
    }
  ],
  "resources": {
    "githubUrl": null,
    "downloadAvailable": true
  },
  "phases": {
    "extract": { "completedAt": "2026-04-01T...", "lessonsExtracted": 44 },
    "extractFrames": { "completedAt": "2026-04-01T...", "framesExtracted": 996 },
    "processFrames": { "completedAt": "2026-04-01T...", "manifests": 44, "kept": 893 },
    "analyzeCodeRepo": { "completedAt": "2026-04-01T...", "sections": 10 },
    "validate": { "completedAt": "2026-04-01T...", "passed": 52, "warnings": 0, "failed": 0 },
    "synthesize": null,
    "analyze": null
  }
}
```

**Status values:** `pending` → `extracting` → `extracted` → `analyzed`

**Phase tracking:** `phases` object records which pipeline phases have completed and when.
Each phase is `null` (not started) or an object with `completedAt` timestamp and phase-specific
metrics. Tools should set phase marker after successful completion. On resume, check which
phases are non-null to determine where to continue.

### transcript.md

```markdown
# Welcome

**Duration:** 1m 37s
**Module:** Course overview

## Transcript

[0:00] Hello, and welcome to the From Zero to Hero course on test-driven
development in C#.

[0:07] My name is Guilherme Ferreira, also known as GI, and I'm a Microsoft
MVP for developer technologies.

[0:15] Not only that, but I'm addicted to test-driven development.
```

Preserve timestamps as `[M:SS]` markers at natural paragraph breaks. Clean up auto-generated transcript artifacts (repeated words, sentence fragments) but don't editorialize content.

### module-summary.md

```markdown
# Module: The Fundamentals

**Lessons:** 8 | **Duration:** ~25 min

## Key concepts

- **Concept name** — Brief explanation. (Lesson: "Lesson Title")
- ...

## Code patterns demonstrated

- Pattern description with context

## Best practices advocated

- Practice with rationale

## Anti-patterns warned against

- Anti-pattern with why it's problematic

## Tools and frameworks mentioned

- Tool/framework with context of how it's used
```

### resources.json (Teachable adapter)

Per-lesson resource metadata — download URLs, article links, PDF links extracted by adapter's `extractResources()` method. Not all platforms produce this file (Dometrain uses button-based detection instead).

```json
{
  "downloads": [
    { "label": "02.4 - Refactoring - Initial.zip", "href": "https://uploads.teachablecdn.com/..." },
    { "label": "02.4 - Refactoring - Final.zip", "href": "https://uploads.teachablecdn.com/..." }
  ],
  "articleLinks": [
    { "label": "How To Use Domain Events", "href": "https://www.milanjovanovic.tech/blog/..." }
  ],
  "pdfLinks": [
    { "label": "Modular Monolith Architecture.pdf", "href": "https://uploads.teachablecdn.com/..." }
  ],
  "textContent": ["Source Code:", "Useful Articles & Resources:"]
}
```

### Code analysis strategy (two levels)

**`code/repo/`** — final/latest snapshot of companion source code. Use for:

- Architecture overview (module organization, project references, shared infrastructure)
- Cross-module patterns (how modules communicate, shared domain events)
- Complete solution understanding (what the finished app looks like)

**`code/downloads/`** — per-lesson Initial/Final ZIP pairs. Use for:

- Per-lesson deltas (diff between Initial and Final = what the lesson teaches)
- Understanding progression (how codebase evolves lesson by lesson)
- Catching discrepancies (what code does vs what instructor says)

Phase 3 synthesis agents read BOTH: repo for architectural context, downloads for lesson-specific teaching. Repo alone misses journey; ZIPs alone miss big picture.

For courses with GitHub repos instead of ZIPs, `code/repo/` is a shallow clone and per-section analysis comes from `git log` or directory-based sections.

### Screenshots

- Format: PNG
- Max width: 1280px
- Naming: `{NNN}-{descriptive-suffix}.png` (e.g., `001-test-list-creation.png`)
- Only capture when visual content adds information beyond transcript:
  - Code on screen (IDE, terminal)
  - Architecture diagrams
  - Slides with visual content
  - UI demonstrations
- Do NOT screenshot talking-head segments — transcript covers those

## Size management

- **No video/audio files** — ever
- **Screenshots**: resize to 1280px wide, compress with reasonable quality
- **Transcripts**: typically 1-3 KB per minute of video (~30 KB for a 30-min lesson)
- **course.json**: grows with lessons but stays under 50 KB for large courses
- **Expected total per course**: 1-5 MB for transcripts + metadata, 10-50 MB with screenshots
