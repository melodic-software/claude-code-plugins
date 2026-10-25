---
bump: patch
---

### Changed

- The docpage-digest Anthropic docs profile adds six tagging rules: a row splits by clause when a docs page states only one of its clauses, and a near-miss never drops `vendor-claimed`; a prescribed method no docs page states is `vendor-claimed`, while applying a documented method is `unverified-inference` only; a contradicted clause keeps `vendor-claimed` with a "contradicted by" note; a bare lever or feature word is not a request parameter; and every absence statement names the pages the run could not read.
