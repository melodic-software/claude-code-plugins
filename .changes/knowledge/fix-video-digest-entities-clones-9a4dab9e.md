---
bump: patch
---

### Fixed

- video-digest decodes HTML entities in transcripts built from auto captions, so a `&gt;&gt;` speaker marker reads `>>` as it already did for manual captions ([#6824](https://github.com/melodic-software/claude-code-plugins/issues/6824)).

### Security

- video-digest's shallow clones of repositories harvested from video descriptions now fail fast instead of prompting: the credential helper is cleared, terminal prompts and Git LFS downloads are disabled, and a clone still running after two minutes is killed and skipped ([#6829](https://github.com/melodic-software/claude-code-plugins/issues/6829)).
