---
bump: patch
---

### Removed

- The `<!-- ready-skip head=<sha> -->` marker line from the `pull-request ready --skip` record comment, and the `--head` flag of `scripts/ready-skip-comment.sh` that only fed it. Nothing read the marker; the comment is now one line per skipped step.
