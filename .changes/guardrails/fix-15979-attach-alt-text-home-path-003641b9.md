---
bump: patch
---

### Fixed

- `block-github-post-content` blocks again a `gh pr|issue` `--attach` operand under the Bash tool whose alt text holds a home path after a character the path patterns do not take as a left boundary (a second `#`, `,`, `;`, `|`, `<`, `-` or a letter). An alt text holding `/` or `\` is now judged with the whole operand, so such an alt text beside a home-directory source blocks, failing closed; an alt text without one is still judged with the base name only.
