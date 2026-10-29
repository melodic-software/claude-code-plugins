---
bump: patch
---

### Fixed

- `/code-tidying:audit-comment-residue`: `detect.sh --added-since <base>` now runs shape detection only on each added line and the line on each side of it, which a wrapped phrase can join. The number of detection calls now follows the number of added lines, not the length of each file that gained one ([#8764](https://github.com/melodic-software/claude-code-plugins/issues/8764)). The comment-text and shape detectors return their result in `REPLY` instead of on stdout, so neither the per-line loop nor the license and workaround pre-passes start a command substitution per line. The two pre-passes still read each whole file. On Git for Windows, where each command substitution forks a slow process, an ordinary pull request in a large repository could run for minutes before this fix.
