---
bump: patch
---

### Fixed

- `observability` no longer describes `cli-flag-verify` as a PostToolUse hook: guardrails runs it at push time in the `reference-verify` git hook, so the report marks hallucination-guard catches as not collected rather than reading an empty count as clean.
- `plugins` no longer says `claude plugin list` shows the highest version across scopes: on 2.1.322 it prints one row per install record with its own scope and version, and still never says which row loads here.
- `plugins` no longer tells a user to run `/reload-plugins` after every `Run /reload-plugins to apply.` summary: since 2.1.268 the `/plugin` panel can apply changes itself, so the two-step checks what the panel did (at the install pointer) and asks for a bare reload only when the plugin is still not active.

### Changed

- `plugins`: the shallow-clone reason for comparing only installs at the clone's HEAD points at the host-marketplace section that describes the re-clone, instead of restating it beside an unanchored link.
- `lanes`: the cloud-session note points at agent view's "List sessions as JSON" section, and the schtasks payload limit points at the `/tr` row the config already cites.
- `audit-skill-visibility`: the usage-counters reference names the binary reading the plugin-use definition rests on, and drops an unsourced polling rate and public-report remark.
- Nine eval cases cover held re-audit rows across `changelog`, `plugins`, `audit-skill-visibility`, `lanes`, `audit-performance`, `observability` and `audit-native-overlap`.
