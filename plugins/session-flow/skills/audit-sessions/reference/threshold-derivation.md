# Threshold derivation

The reference measurements behind the thresholds in [sweep-rules.json](sweep-rules.json): one
sweep of one reference machine's store, posted on
[#6077](https://github.com/melodic-software/claude-code-plugins/issues/6077#issuecomment-6514809921).
It holds aggregate figures only, no transcript content.

## Population

- **Filter:** interactive sessions, the sweep's default population by `census.session_class`
  (automated sessions set aside); none had an unknown entrypoint. Of 2,490 sessions ingested, the
  sweep covered 710 and set aside 1,780 automated ones.
- **Window:** sessions started 2026-09-28 to 2026-10-30 (UTC). Sessions started 2026-09-14 to
  2026-09-27 are excluded, so a since-fixed Stop-hook cost is not counted; that removed 38
  sessions and left 672. The store held no session older than 2026-09-14.
- **Claude Code versions:** 2.1.283 to 2.1.312.
- **Date:** 2026-10-30.

## Figures

Per-session values. `n` is the sessions with a value; `hooks.stop_ms` counts only sessions with a
Stop run, and `edits.churn_per_pr` counts path-PR pairs.

| Metric | Unit | n | Median | p90 | Max | Nonzero |
| --- | --- | --- | --- | --- | --- | --- |
| `tokens.main` | tokens | 672 | 95196.5 | 233586 | 630958 | 593 |
| `tokens.sub` | tokens | 672 | 13083 | 546457 | 7785928 | 455 |
| `cache.missed_input_tokens` | tokens | 672 | 0 | 26553 | 1473232 | 78 |
| `cache.write_5m_share` | ratio | 672 | 0.840 machine-wide | n/a | n/a | n/a |
| `time.active_s` | s | 672 | 6520.5 | 19372 | 46388 | 596 |
| `context.clear_commands` | count | 672 | 1 | 1 | 1 | 412 |
| `human.turns` | count | 672 | 5 | 15 | 61 | 577 |
| `tools.interrupts` | count | 672 | 0 | 0 | 6 | 47 |
| `tools.denials` | count | 672 | 3 | 17 | 160 | 435 |
| `subagents.count` | count | 672 | 7 | 36 | 470 | 456 |
| `hooks.stop_ms` | ms | 581 | 86 | 152 | 111151 | 581 |
| `edits.churn_per_pr` | count | 2054 | 1 | 5 | 174 | 2054 |

## Notes

- `time.active_s` reads `time.active_gap_s` (record gaps capped at 300 s). The earlier
  `turn_duration` sum was above wall clock in 56 records of this store; this definition in none.
- `hooks.stop_ms` is each session's p90 of the slowest hook per Stop run, over every `hookInfos`
  entry, the test-judge Stop hook included. The store keeps no hook names, so how often that hook
  ran is not known.
- In this sweep only `tokens.sub` was marked `baseline_stale`: its p90 is above
  `stale_p90_factor` times its threshold.
