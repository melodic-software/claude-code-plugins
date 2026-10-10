---
bump: patch
---

### Fixed

- video-digest records a `--target` passed as a local checkout path in `watch.json` as its portable `owner/repo` name (from the checkout's GitHub `origin`, else the directory name), never the machine path.
- video-digest documents how the deck harvest types links and fetches them: the session adds a `kind` to each `harvested-links.json` entry, then runs `harvesting/fetch-deck-attachments.js`.
- video-digest's SKILL.md names which `mark-phase` marker each phase uses, since the skill-session phases share the `vision`, `research` and `close` markers.
