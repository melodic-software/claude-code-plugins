# Design Threads: search-indexing

## Thread 1: Index storage backend. RESOLVED

Decision: use the existing Postgres full-text index rather than adding a search engine.
Rationale: corpus is small and the ops cost of a second datastore is not justified at
current scale; revisit if corpus crosses 10M rows.

<!-- ai-slop-ignore-start: heading quoted verbatim by evals/evals.json eval 3 "decided-without-rationale-is-not-resolved" -->
## Thread 2: Reindex trigger — decided
<!-- ai-slop-ignore-end -->

Decided: reindex on write.
(No rationale recorded.)

## Thread 3: Stop-word and stemming configuration. unresolved

We discussed English vs multi-language stemming but did not land on which, and there is
no research tag naming the investigation needed.

## Thread 4: Ranking function. directional

Direction agreed: start with `ts_rank`, tune later.
Remaining detail carries research tag: [RESEARCH: benchmark ts_rank vs ts_rank_cd on a
representative query set].
