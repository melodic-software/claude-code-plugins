---
bump: patch
---

### Changed

- On a lanes App merge-group run, ci-status lists main's tip once, with one unauthenticated `git ls-remote` of refs/heads/main and refs/tags/main, and passes it to the carry readers as `PR_MERGE_MAIN_TIP`. `onMain` then makes no `git/ref` read. It falls back to both REST reads when the listing failed or holds a tag named main. Each run is still compared with the tip.
- The merge-group hold-label step reads the queued pull request's labels in its existing GraphQL query in place of REST `issues/{n}/labels`. It fails closed on a cut or missing list.
