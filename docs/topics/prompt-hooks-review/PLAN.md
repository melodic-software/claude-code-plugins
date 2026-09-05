# prompt-hooks-review

## Brief

### TLDR

Fix the one verified defect in the prompt-hook lane (`context-guard`'s
`zone-crossing-inject.sh` writes state on every fire where the gate needs to
move once), bring its `hooks.json` to current-schema shape, and commit the
corrected fleet audit so it survives the container. Everything larger the
audit found belongs to other lanes and has been handed off.

### Goal

A small, self-contained PR on `claude/prompt-hooks-review-cf00b1` touching
only `plugins/context-guard/hooks/` plus the committed audit record.

### Constraints

- Cross-session protocol: six parallel sessions on separate branches with
  separate clones. I own `plugins/context-guard/hooks/hooks.json` (ceded by
  the PreToolUse lane) and `zone-crossing-inject.sh`. No other
  `plugins/*/hooks/**`, no `lib/hook-utils.sh` or its copies, no
  `docs/conventions/hook-*`, no `scripts/check-*.sh`.
- `lib/hook-utils.sh` is a synced cluster with a CI drift gate; never edit a
  copy.
- Every PR opens as a draft and satisfies `.claude/rules/pr-body-contract.md`.
- Validate with `scripts/affected-tests.sh --run`, not the full suite.
- House prose style (`ai-slop:audit`): no em dashes in repo prose.
- Announce branch, PR title and file list to all live peers before opening.

### Acceptance criteria

1. `zone-crossing-inject.sh` writes `.zone` and `.armed` only when the
   observation changes what the next fire must compare against. A
   three-batch turn that stays in one zone performs the state write once,
   not four times. Existing contract test
   (`zone-crossing-inject.test.sh`) still passes, including partial-write
   recovery.
2. `plugins/context-guard/hooks/hooks.json` carries a top-level
   `description` and its four rows drop `timeout: 60` to a value at or below
   the event default (the docs put `UserPromptSubmit`'s command default at 30;
   the hook measures roughly 30 ms).
3. `docs/topics/prompt-hooks-review/` holds the consolidated audit report
   with every peer-refuted finding recorded as withdrawn, not deleted.
4. `scripts/affected-tests.sh --run` is green for the changed files.
5. Draft PR body satisfies the pr-body contract; peers were notified before
   it was opened.

### Captured assumptions

- The wasted-write fix is I/O only; it does not change when the notice is
  emitted. The armed-rank hysteresis already suppresses duplicate injection.
- Lowering the timeouts is safe by a wide margin: the hook's measured cost
  is roughly 15 spawn-equivalents on a quiet host, and a stalled advisory
  hook should fail fast rather than hang a turn for a minute.
- Adding `description` to one `hooks.json` while the other 19 lack it is
  acceptable; the fleet-wide pass needs a single owner and is out of scope.

### Measured baseline (audit evidence, Linux container, spawn floor S interleaved)

Timings the audit stands behind. Interpretive findings that peer review
overturned are omitted here on purpose; the narrative lives in #3685.

| Surface | Wall | S | Note |
|---|---|---|---|
| PostToolUse verifier trio, `.md` citing a skill + 4 CLI commands | 825 ms | 421 | realistic marketplace payload |
| same, `.md` prose only | 101 ms | 51 | |
| `skill-reference-verify` alone on that path | 630-690 ms | ~330 | 2 `jq` + 2 `tr` per manifest, 74 manifests; PostTool corroborated at 601-622 ms |
| `skill-reference-verify` index, one batched `jq` | 7.9 ms | 4.2 | PostTool corroborated at 5.7 ms |
| `cli-flag-verify` cold cache, first run | 11,391 ms | | 24 h TTL, so cold keys recur daily |
| PreToolUse Bash lane, 8 guards, one process | 104 ms | 44 | ~32 ms spawn, ~70 ms bash-internal |
| Disabled hook (kill switch false) | 7.1-8.7 ms | 3.8-4.6 | switch read after the 2,766-line library parse, 43/43 sites |
| `lib/hook-utils.sh` source alone | 5.1 ms | 2.3 | |
| `zone-crossing-inject` steady zone | ~30 ms | ~15 | this lane |

Method caveat recorded for the budget convention: spawn-equivalents only
survive a host change for spawn-dominated hooks; work-dominated ones
(`markdown-format` ~35 ms/exec, `context-budget` ~39 ms/exec) are
overstated by roughly 40x in the doc's reference-host column.

### Out-of-scope

- The PostToolUse verifier lane (`skill-reference-verify`, `cli-flag-verify`,
  `stale-path-verify`): PostToolUse lane, handed off with patch shapes.
- Kill-switch hoist across 43 hook entry scripts: assigned to the PostToolUse
  lane.
- `block-hook-bypass` disposition: PreToolUse lane runs a corpus sweep first.
- `async: true` on the `UserPromptExpansion` telemetry row: PostToolUse lane's
  file, passed as a note.
- `description` on the other 19 `hooks.json` files; the disk-hygiene
  PowerShell `if` row; any budget-doc edits (routed to #3685 as evidence).
- New hooks on the 15 unused events, and any `type: prompt` / `type: agent`
  handler: parked for a fresh-context interview.

### Deferred questions

None. All seven register rows are answered; see
`.work/prompt-hooks-review/interview-checklist.md`.

## Plan

(empty; `/planning:plan` fills this)
