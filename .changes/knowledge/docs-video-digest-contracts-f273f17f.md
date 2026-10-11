---
bump: patch
---

### Fixed

- video-digest documents the JSON it has subagents write (per-sheet triage, promotion decisions, post-promotion audit) in `templates/vision-json-shapes.md`, with a worked example each that passes the validators, and each brief carries its file's section ([#6818](https://github.com/melodic-software/claude-code-plugins/issues/6818)).
- video-digest frames ingested transcripts, descriptions, comments, decks, companion pages and cloned repositories as untrusted data in the skill and in every subagent brief ([#6820](https://github.com/melodic-software/claude-code-plugins/issues/6820)).
- video-digest names Git Bash on Windows and Node 20.11 as prerequisites, and the knowledge plugin's prerequisites check now reports a node older than 20.11 ([#6828](https://github.com/melodic-software/claude-code-plugins/issues/6828)).
