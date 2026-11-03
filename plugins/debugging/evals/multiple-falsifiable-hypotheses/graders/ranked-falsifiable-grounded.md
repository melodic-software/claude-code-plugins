---
type: llm
---

PASS if the reply lists between 3 and 5 hypotheses in a ranked order, each one stating a prediction (what change or observation would confirm or refute it), and the ranking draws on real repository state: it cites a recent commit in the exporter, an ADR, or a known-issues note, or says it will check one of those, named, before ranking. A row already marked confirmed or ruled out from reading the source still passes, as long as that row keeps its prediction: reading the source grounds the ranking and is not testing.

FAIL if the reply gives one or two hypotheses, more than five, any hypothesis with no prediction (a bare verdict such as "Refuted" is not one), a ranking with no reference to repository state, a promise to check the repository that names no source, or if it reports running a test or editing a fix for one cause before the full set is listed.
