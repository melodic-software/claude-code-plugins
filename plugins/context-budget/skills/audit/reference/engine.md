# Measurement engine contract

The record shapes `scripts/measure.mjs` emits, the mechanism claims the skill relies on with their
official citations, and the comparability rules the engine enforces. Method is the durable content
here; values are deliberately absent — every number the plugin ever shows was measured by the run
that shows it, at the consumer's binary, and stamped with that binary's version.

## Degradation ladder

| Rung | Mode | Precision | Requires | Recorded caveats |
|---|---|---|---|---|
| 1 | `sdk` | `exact` (integer tokens) | `@anthropic-ai/claude-agent-sdk` resolvable from `--sdk-dir` or the working directory | none |
| 2 | `cli-parse` | `display-rounded` (table cells like `11.4k`) | `<binary> -p "/context"` producing the category table | rounded values; headless `/context` is undocumented as a `-p`-capable command — load-bearing but unsanctioned |
| 3 | — | — | — | exit 3 with a `context-budget.error/1` record naming the remediation; **never a wrong number** |

The `/context` output format carries no stability guarantee in either direction and has materially
changed several times; the parser therefore refuses loudly (rung 3) when the expected sections are
absent rather than guessing. Known parse traps handled: an unredirected-stdin warning line
prepended to output; skill token cells formatted `~<int>` or `< <int>` unlike every other table;
`--output-format json` returning the same markdown as a string (the engine parses plain output
instead).

## Mechanism claims and citations

| Claim the skill relies on | Source |
|---|---|
| A bare tool name in a deny rule removes the tool's definition from the request; a scoped rule (`Bash(rm *)`) is a runtime guard whose schema still ships | [Agent SDK permissions — allow and deny rules](https://code.claude.com/docs/en/agent-sdk/permissions#allow-and-deny-rules) |
| Deferred tool loading controls what enters the context window, not what is sent — the full schema still goes out in the request | [Tool search — deferred tool loading](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#deferred-tool-loading) |
| `--disallowedTools` exists as a per-invocation CLI flag; there is **no** `disallowedTools` settings key — persistent config uses `permissions.deny` | [CLI reference — flags](https://code.claude.com/docs/en/cli-reference#cli-flags), [settings](https://code.claude.com/docs/en/settings) |
| The Agent SDK exposes structured context usage over the control protocol (`getContextUsage()`) | [Agent SDK TypeScript reference](https://code.claude.com/docs/en/agent-sdk/typescript) |

Where the engine's behavior rests on empirical observation rather than documentation (headless
`/context`, the skill-listing subtraction below), the record says so in `caveats` — reported,
never silently assumed durable.

## Comparability rules (enforced, not advisory)

1. **Skill-listing signature.** The `System tools` bucket has listed skill-frontmatter tokens
   subtracted from it, so its value is only meaningful relative to a run with an identical skill
   listing. Every snapshot carries `skillListing.signature` — a hash of the sorted
   (name, source) listing — and `compare`/`attribute` mark `systemToolsComparable: false` on
   mismatch, with the reason in `comparability.reasons`. Denying a tool changes no skills, which
   is what makes per-tool attribution well-posed under this rule.
2. **One mode, one binary.** Deltas across modes mix precisions; deltas across binary versions or
   paths measure the upgrade, not the lever. Both mark the row incomparable.
3. **Signed deltas.** `delta` is after-minus-before (a saving is negative); `attribute` rows carry
   `savedTokens` with the sign flipped for ranking. `prefixDelta` and `deferredDelta` stay
   separate: a deferred-bucket saving reduces request weight without moving the context-usage
   headline, and merging them would misstate both.
4. **Headline semantics.** `totalTokens` excludes the deferred pools, free space, and the
   autocompact buffer in both modes, matching the renderer's own headline. Deferred pools are
   plural: built-in and MCP deferred tools are accounted in separate `... (deferred)` categories
   (measured at the verified version), and both are excluded from the *headline*, not from the
   *request* — see the deferral citation above.

## Record schemas

All records are JSON on stdout (and `--out <file>`), schema-tagged:

- `context-budget.snapshot/1` — one measured run: `mode`, `precision`, `sessionKind: "headless"`,
  `binary {path, version}`, `sdk {version, entry} | null`, `model`, `cwd`, `deny[]`,
  `categories {name: tokens}`, `totalTokens`, `maxTokens`, `tools[]` (live enumeration, sdk mode),
  `agents[]`, `mcpTools[]`, `memoryFiles[]`,
  `skillListing {totalSkills, includedSkills, tokens, signature, rows}`, `caveats[]`.
- `context-budget.attribution/1` — `baseline` (summary), ranked `perTool[]` rows
  `{tool, prefixDelta, deferredDelta, savedTokens, comparable, reasons}`, optional `additivity`
  (`--verify-additivity`: one combined-deny run checked against the sum of parts, with its own
  `comparable`/`reasons`), plus the binary stamp and `skillListingSignature`. A deny can empty a
  summed bucket out of the snapshot entirely; the bucket's delta is then null and the row (or
  additivity record) reports `savedTokens`/`combinedSaved` as `null` with `comparable: false` and
  the reason — a missing measurement, never a coerced zero. That vanish path fires in
  **cli-parse** mode, where an omitted bucket is genuinely ambiguous (format drift vs emptied
  bucket). In **sdk** mode the two attributed buckets are recorded as an explicit `0` when the
  SDK omits them (numbers are exact and the vocabulary is known), so a combined deny yields a
  real delta; a `caveats[]` entry names every synthesized zero so a raw `snapshot`/`ledger`
  consumer can tell a reported 0 from a filled-in omission. A bucket absent from *both* runs is
  outside that binary's category vocabulary and simply contributes nothing.
- `context-budget.ledger/1` — one before/after: `lever`, `emittedConfig`, `before`/`after`
  summaries, `delta` per category, `totalDelta`, `comparability`. A category present in only one
  run gets `null`, never an invented number.
- `context-budget.error/1` — the degradation record: `error`, `detail`, `remediation`. Exit 3.

## Ledger layout

Under the caller-derived data dir (`${CLAUDE_PLUGIN_DATA}/audit/<state-key>/` — the state key is
the marketplace's shared per-project scheme; the engine itself never derives keys):

```text
runs/<UTC-timestamp>-<lever-slug>.json   one file per run
ledger.jsonl                             one appended line per run — the trend source of truth
```

One file per run plus an appended history line, so a same-day rerun never erases an earlier
point. `ledger --append` validates the row's schema; `ledger --list` returns rows plus an honest
note when the ledger does not exist yet ("nothing measured for this project" — never an empty
success).

## Session-kind boundary

Every measurement is a **headless** session spawned against the pinned binary. Interactive
sessions can compose the payload differently (deferral eligibility is partly server-decided), so
records carry `sessionKind: "headless"` and reports repeat it. The spawned session's prompt is
`/context`, which the CLI handles itself — no model API call is made by a measurement.
