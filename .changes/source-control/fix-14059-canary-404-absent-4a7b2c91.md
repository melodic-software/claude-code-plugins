---
bump: patch
---

### Fixed

- The post-merge check reads a repository without the silent-revert canary workflow as having no
  canary, instead of unreadable: a 404 on the `post-merge-detect-silent-revert.yml` run listing,
  with that file absent on the default branch, gives no canary signal, and a merge verifies on its
  dispatch run and read-back alone. Every other failed canary read (403, 5xx, a 404 while the file
  is present, a partial listing) stays unreadable, and the full-run reads are unchanged. Before,
  the pr-merge lane refused every unattended merge in such a repository with
  `post-merge:unreadable: ... gh: Not Found (HTTP 404)`.
