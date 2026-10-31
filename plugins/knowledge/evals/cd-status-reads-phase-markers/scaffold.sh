#!/usr/bin/env bash
# Seed two extracted courses at courses/<platform>/<slug>/ under the working
# directory, made its own git toplevel with no remote (the eval home above it is
# a repository). library_dir defaults to "." in both versions, so both resolve
# the course root to this directory. One course has every phase marker set; the
# other stopped after extraction.
set -euo pipefail

git init -q

done_dir=courses/dometrain/tdd-csharp-ferreira
mkdir -p "$done_dir"
cat >"$done_dir/course.json" <<'JSON'
{
  "title": "Test-Driven Development in C#",
  "slug": "tdd-csharp-ferreira",
  "platform": "dometrain",
  "url": "https://dometrain.com/course/from-zero-to-hero-test-driven-development-tdd-csharp/",
  "instructor": "Guilherme Ferreira",
  "totalLessons": 3,
  "status": "analyzed",
  "modules": [],
  "phases": {
    "extract": { "completedAt": "2026-09-01T10:00:00Z", "lessonsExtracted": 3 },
    "extractFrames": { "completedAt": "2026-09-01T11:00:00Z", "framesExtracted": 40 },
    "processFrames": { "completedAt": "2026-09-01T11:30:00Z", "manifests": 3, "kept": 31 },
    "analyzeCodeRepo": { "completedAt": "2026-09-01T12:00:00Z", "sections": 2 },
    "validate": { "completedAt": "2026-09-01T12:10:00Z", "passed": 6, "warnings": 0, "failed": 0 },
    "synthesize": { "completedAt": "2026-09-02T09:00:00Z" },
    "analyze": { "completedAt": "2026-09-02T10:00:00Z" }
  }
}
JSON

partial_dir=courses/teachable/event-driven-dotnet-quill
mkdir -p "$partial_dir"
cat >"$partial_dir/course.json" <<'JSON'
{
  "title": "Event-Driven Architecture in .NET",
  "slug": "event-driven-dotnet-quill",
  "platform": "teachable",
  "url": "https://courses.example.tech/p/event-driven-dotnet",
  "instructor": "Morgan Quill",
  "totalLessons": 12,
  "status": "extracting",
  "modules": [],
  "phases": {
    "extract": { "completedAt": "2026-09-20T08:00:00Z", "lessonsExtracted": 12 },
    "extractFrames": null,
    "processFrames": null,
    "analyzeCodeRepo": null,
    "validate": null,
    "synthesize": null,
    "analyze": null
  }
}
JSON
