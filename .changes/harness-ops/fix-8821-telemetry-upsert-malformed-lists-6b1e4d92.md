---
bump: patch
---

### Fixed

- `telemetry-upsert.sh` no longer posts a duplicate telemetry comment when the comment list is empty, `null`, `false` or holds a non-object element, or when its detection `jq` fails. Each case exits 5 with nothing written.
- Under a personal token with `--app-slug`, a failed `gh api user` resolves to `SLUG[bot]` only when the token can list its installation's repositories. A transient failure under a personal token now exits 4 and writes nothing, where it used to post a duplicate.
