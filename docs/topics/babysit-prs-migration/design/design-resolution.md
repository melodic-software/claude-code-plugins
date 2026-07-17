# Design resolution — babysit-prs migration

outcome: early-exit

The composition design was settled during the interview stage and is locked in the Brief's
constraints: layered plugin-scope shared seam (B13 — shared review discipline + comment fetcher at
plugin root, cited by both skills; babysit owns fleet mechanics, `pull-request` keeps single-PR
lifecycle), Python engine backbone with Python-free safe default (B15), bot-agnostic review-trigger
module (B11), layered concurrency detection (B14), userConfig-first configuration (B5/B6). No new
programming-language types or public API contracts are introduced in Phase 1 — the deliverables are
markdown skill surfaces and relocated shell scripts. Engine module boundaries (Phase 2) are
explicitly deferred to the per-phase architect pass per the Brief's deferred-questions list.
