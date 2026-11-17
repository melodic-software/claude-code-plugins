---
bump: minor
---

### Added

- **Pipeline slots in `autonomy:setup`.** Discovery gains a fourth step for the four slots an autonomous agent pipeline needs: runner, git host, ticket tracker and observability. Each slot reads the discovery that already owns it (substrate, role homes, the work-items tracker binding, the telemetry slice), lists option classes with no preference, and hands wiring to that owner. A new `context/pipeline-slots.md` holds the table, the option classes and a live price-research step: prices are fetched from the vendor's page at run time and shown, cited, in the reply only, never stored. Two evals cover the slot flow and the price rule.
- **WSL and local-lane rungs in the isolation ladder.** `reference/guardrails/isolation-ladder.md` records that default WSL adds no isolation (`L0`), WSL2 with the per-command sandbox is `L1`, what `/etc/wsl.conf` interop and automount keys narrow without raising a level, local lanes as unattended with no exemption yet (a known gap), and guidance for a machine where only Windows is allowed.
