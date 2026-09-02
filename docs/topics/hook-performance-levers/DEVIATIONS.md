# Deviations log: hook-performance-levers

Append-only. One entry per decision. Types: plan-confirmed, discovery, deviation, human-decision.

## 2026-09-02

- **deviation** (phase 1, summary line fields). Plan said: append `max_abs_ms=<n>` as "the same max in absolute ms" beside `max_ms`. Found: with `max_ms` already absolute the two fields are byte-identical (worker w1-harness raised it). Chose: `max_ms` stays absolute; the appended fields are `cpu_x_s=` and `max_x_s=` (sum and max divided by the run's overall S, one decimal), so the (B) ratios read directly and the 1,000 ms ceiling reads off `max_ms`. Revisit: none; PLAN.md items 3 and the phase 8 sanity list updated in the same commit. Outcome: unverified until the phase 1 harness lands.
- **plan-confirmed** (branch base). PR #3621 is still open, `main` moved one commit (`a34bd7d73`, standards sync). The plan branch `perf/hook-performance-program` was rebased onto `main` because it is docs only (PR #3625); code phases branch from `perf/hook-fanout-consolidation` until #3621 merges, per the handoff.
- **discovery** (host process check). `tasklist` shows three `claude.exe` processes on this host while this session runs, and the invoking MSYS bash has PPID 1, so the phase 0 helper's live-process refusal must walk Windows parent PIDs from `/proc/$$/winpid`, else it refuses forever. Encoded in the w0-helper brief. Outcome: unverified until the helper's self-test runs.
