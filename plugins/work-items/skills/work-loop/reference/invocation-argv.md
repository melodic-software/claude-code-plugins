# Invocation argument surface

Grammar (bash-style tokenization of `$ARGUMENTS`):

`[<owner/repo>] [--drain|--standing] [--shard <i>/<n>] [--ordering oldest-first|newest-first] [--instance <id>] [--scope <label>]`

**Parse and validate explicit invocation tokens before telemetry lookup or cycle work.** Reject
unknown flags fail-closed. A launch-prompt `Scope:` line or other standing prose is not binding.
Only tokens on the skill invocation line are. Under `/loop` that line is re-sent every cycle, so
it is the run config's source on every cycle, not only the first.

**Resolution order** (first supplied value wins per key; report effective values and their source
at lane start):

- **Run config** (`stop_mode`, `ordering`, `shard`, `scope`): the invocation tokens below, else
  the defaults `stop_mode=standing`, `ordering=oldest-first`, `shard=null`, `scope=null`. Never
  the durable state block: the lane records these keys there for the operator and never reads
  them back, because that comment is editable by the lane itself and by anyone with comment
  access. When the block recorded a different value, report the key and both values and run the
  resolved one.
- **Lane instance**: `--instance`, else the persisted `lane_instance`, else
  `${user_config.lane_instance}`, else the sanitized hostname per
  [telemetry-upsert.md](telemetry-upsert.md).

**`<owner/repo>`** (optional). When present, validate against the checkout's `origin` remote
(`git remote get-url origin` → normalize to `owner/repo`). Mismatch is a hard stop with a clear
message. Never guess a repository. When absent, the bound tracker repository is the checkout.

**`--drain` / `--standing`**. Set `stop_mode=drain` or `stop_mode=standing`; passing both is a
conflicting duplicate. At exit evaluation load [mode-drain.md](mode-drain.md) for `drain` and
[mode-standing.md](mode-standing.md) for `standing`. An interactive launch with neither runs
`standing` and reports it as the default.

**`--shard <i>/<n>`**. Partition retained snapshot ids: keep only items whose issue number
satisfies `number % n == i`. Validate `0 <= i < n` and `n >= 1`; reject malformed shards
fail-closed. Record `{"index":i,"count":n}` in durable state, or `null` when unset.

**`--ordering oldest-first|newest-first`**. Controls execute-step cap-slot fill order among
admitted items this cycle. Default `oldest-first`. Record in durable state.

**`--instance <id>`**. Overrides `${user_config.lane_instance}` for this invocation. Validate
`^[a-z0-9][a-z0-9-]{0,31}$` and length ≤ 32 before building the telemetry marker, the same gate as
[telemetry-upsert.md](telemetry-upsert.md). Reject invalid ids fail-closed.

**`--scope <label>`**. Exact label filter on snapshot ids before admission and exit evaluation
(e.g. `area:api`). Record the label string or `null`.

**Fail-closed rejections**: stop with an explicit message naming the owning surface; never
silently ignore:

- **Babysit tier keywords** (`safe`, `worker`, `autopilot`) and **merge dimension flags**
  (`--merge …`) belong to `/source-control:babysit-loop`, not this worker lane.
- **Adaptive cap knobs** (`--item-cap`, `--cap`, `--wave-cap`, or any `work_loop_item_cap_*`
  override token). Cap bounds come from `userConfig` only.
- **Unknown flags** and duplicate conflicting tokens.

## Headless launches

A headless launch (no operator can answer in the session: `claude -p`, a `claude --bg` lane, a
launcher-stored prompt, a scheduled run) never blocks on an interview (headless-config floor) and
never guesses the stop mode. It must carry `--drain` or `--standing`; with neither, stop before
any telemetry write or cycle work with: `work-loop: headless launch has no stop mode; relaunch
with --drain or --standing (plus any --shard, --scope, --ordering the lane should run with)`. A
drain lane relaunched without its flag would otherwise run standing and never stop, and the
durable state block that once recorded `drain` is not a source it may fall back to. `shard`,
`scope`, and `ordering` keep their defaults when absent: an absent `--shard` or `--scope` states
"the whole backlog", not a missing value.
