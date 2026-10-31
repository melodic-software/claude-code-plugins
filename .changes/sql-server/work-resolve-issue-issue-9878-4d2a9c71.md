---
bump: patch
---

### Added

- An integration test of the read path, `node plugins/sql-server/integration/read-path.mjs`. It starts a local SQL Server 2022 container (Developer edition) with a read-only login and a second database, runs the stdio server on a registration confined to one database, and prints one PASS or FAIL line for each of #5940's S1/S2, S5, S6 and S7. S1/S2 passes when every write, DDL and session-state attempt is refused on each round and the data is unchanged. A write the reject list lets through, or one sent straight to the server, must meet the login's permission refusal. S5 passes when the second database cannot be reached, S6 when no password appears in the plugin, config or registration files, and S7 when `tools/list` never changes. Without Docker it prints `SKIP: docker not available` and exits 0.
