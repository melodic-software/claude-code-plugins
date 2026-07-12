# Design Threads — search-indexing

## Thread 1: Index storage backend — RESOLVED

Decision: use the existing Postgres full-text index rather than adding a search engine.
Rationale: corpus is small and the ops cost of a second datastore is not justified at
current scale; revisit if corpus crosses 10M rows.

## Thread 2: Reindex trigger — RESOLVED

Decision: reindex on write.
Rationale: writes are infrequent and the index must be query-consistent immediately;
a batch reindex was rejected because it leaves search stale between runs.

## Thread 3: Stop-word and stemming configuration — unresolved

We discussed English vs multi-language stemming but did not land on which, and there is
no research tag naming the investigation needed.

## Thread 4: Ranking function — directional

Direction agreed: start with `ts_rank`, tune later.
Remaining detail carries research tag: [RESEARCH: benchmark ts_rank vs ts_rank_cd on a
representative query set].
