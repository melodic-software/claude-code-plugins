---
bump: patch
---

### Fixed

- `fix-ci-context.mjs` writes two more fields to fix-ci's context file. `spec` holds the linked issues' trusted spec text, read by pr-verify's `linkedIssues`. `feedback_lines` holds the non-blank lines the pull request's last address-feedback commit added. Before, fix-ci could cut a line that met a criterion just to get under a size cap, and pr-verify then failed the head on that criterion. On #10919 the two lanes undid each other until the verify-fail cap left the PR unarmed. Each field has its own byte budget so the file stays under the read job's 1 MiB limit. A field the runner cannot read whole, or that does not fit its budget, is `null`, never a partial list.
