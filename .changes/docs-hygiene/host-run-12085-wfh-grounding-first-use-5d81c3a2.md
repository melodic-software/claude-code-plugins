---
bump: patch
---

### Changed

- `/docs-hygiene:write-for-humans` tightens the test for its grounding rule: a term's definition goes in the first sentence that uses it or an earlier one, never the next, and a common word that names one specific thing ("the broker") counts as a term to introduce. A post-draft step checks each term's first use ([#12085](https://github.com/melodic-software/claude-code-plugins/issues/12085)).
