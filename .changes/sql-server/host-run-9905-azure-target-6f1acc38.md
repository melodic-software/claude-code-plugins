---
bump: minor
---

### Added

- The integration test (`integration/read-path.mjs`) takes `--azure-server <server>.database.windows.net` to run its S1/S2, S4, S5, S6 and S7 checks against an empty Azure SQL Database named `app`. It signs in with the Azure CLI account as the server's Entra admin and creates contained read-only and write users with passwords generated for the run (#9905).
