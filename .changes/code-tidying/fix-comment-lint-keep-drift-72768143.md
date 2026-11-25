---
bump: patch
---

### Fixed

- The comment lint passes a URL or RFC only in its own paragraph, the consecutive comment lines holding a word character, and only when that paragraph runs at most `class_c_max_lines` lines (team file or personal override, default 2). Before, a blank `#` line counted as prose, so one link anywhere in a comment passed every line of it, and no line budget applied.
