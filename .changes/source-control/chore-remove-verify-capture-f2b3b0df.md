---
bump: patch
---

### Removed

- The merge gate's CI evidence comment, `babysit_evidence_comment.py`, which only linked a `pr-capture-<pr>-<head>` artifact: CI no longer captures a pull request's app, so the `merge-pr` enqueue and the `enable-auto-merge` arm post no evidence comment ([#17281](https://github.com/melodic-software/claude-code-plugins/issues/17281)). The `/source-control:pull-request evidence` comment is unchanged; its `--artifact-url` links any retained CI artifact.
