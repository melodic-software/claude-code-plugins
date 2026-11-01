---
bump: none
---

Adds two `/docs-hygiene:write-for-humans` eval cases, `wfh-grounding-readme` and `wfh-grounding-howto`. They check whether a README or how-to written from source notes introduces each domain term before a sentence relies on it, or names the term as knowledge it assumes the reader has. The skill has no such rule yet, and these cases measure whether it needs one. No shipped skill text changes, so no release is needed.
