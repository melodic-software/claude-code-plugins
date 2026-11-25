---
bump: patch
---

### Changed

- The shared GitHub client (`github-client.mjs` `createGitHub`, and `budgetedFetch` through it) sends a repeated GET of the same URL, under the same token, with the kept answer's ETag as `If-None-Match`, and a 304 returns the kept body. A 304 to an authorized request does not count against the primary rate limit. Any other answer is returned as before; a 304 with no kept answer is still an error. With `GITHUB_READ_STORE` naming a directory, the kept answers also carry to later steps of the same job: pr-verify sets it on its resolver and trigger-gate steps, and the gate now reads the commit's pull requests at the resolver's URL (`?per_page=100&page=1`), so that read is a conditional one. The trigger gate's own re-run record listing memo is replaced by the client's store.
