---
bump: patch
---

### Fixed

- lanes: `telemetry-upsert.sh` takes `--app-slug SLUG` and resolves its write identity as `restart-consumer.sh` does (User login, else `SLUG[bot]`, else the reported Bot login plus `[bot]`), so under an App installation token it adopts its own comment instead of failing to find it. A malformed slug exits 3; an unresolved identity writes nothing and exits 4 naming `--app-slug`.
