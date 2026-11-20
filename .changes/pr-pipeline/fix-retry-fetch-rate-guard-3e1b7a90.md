---
bump: patch
---

### Changed

- The lane scripts that run from a full checkout now send every GitHub call through the rate guard, so they honor the job's stop file and record their budget readings. `report-outcome.mjs --find-prior` reads through `createGitHub` and holds green while the stop file holds its pool, and its claim re-derive fails, as it does on any failed read. address-feedback's base-checkout mains, the dispatch clients and the importers of apply-patch's client get the guarded fetch. The rate-guard coverage test now fails any client whose default fetch skips the guard, not only a bare `fetch(` call. The scripts that run from a directory copy keep their own client and are listed with the reason.
