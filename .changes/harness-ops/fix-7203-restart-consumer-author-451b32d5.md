---
bump: patch
---

### Fixed

- read restart requests only from the lanes' write identity

  restart-consumer read restart_request from any comment carrying the public
  lane telemetry sentinel, so anyone who could comment on a telemetry issue
  could request lane restarts (#7203). It now reads only comments written by
  the lanes' write identity: the `gh api user` login when it reports a User,
  `<slug>[bot]` from a new `--app-slug` option when that call fails or reports
  a Bot, else the reported Bot login plus `[bot]`. With no identity resolved
  the run exits 4 before reading any lane. `print-schedule` carries a passed
  `--app-slug` into the commands it emits.
