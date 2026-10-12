---
bump: patch
---

### Fixed

- **video-digest watch recovery picks the same caption as acquisition.** `resolveWorkArtifacts` in `recover-watch-bootstrap.js` chose the first `.vtt` without `-orig` in its name, so a work dir holding `<id>.en.vtt` and `<id>.en-orig.vtt` with no manual English track in info.json rebuilt the transcript from the possibly machine-translated bare track. It now resolves the caption through `selectCaptionFile` with the `manualLanguages` signal from the work dir info.json and the source adapter caption class, so recovery and acquisition agree. Candidate captions and info.json are scoped to the recovered video's `<id>.` prefix, so a multi-video X work dir never takes another entry's caption; when the recovered entry's own caption or info.json is missing, recovery fails with an error instead of using a sibling's (#6837).
