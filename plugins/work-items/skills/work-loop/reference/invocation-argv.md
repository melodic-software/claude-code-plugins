# Invocation argument surface

Grammar (bash-style tokenization of `$ARGUMENTS`):

`[<owner/repo>] [--drain] [--shard <i>/<n>] [--ordering oldest-first|newest-first] [--instance <id>] [--scope <label>]`

**Parse and validate explicit invocation tokens before telemetry lookup or cycle work.** Reject
unknown flags fail-closed. After tokens are parsed, read the durable state block and bind every key
per the resolution order below. A launch-prompt `Scope:` line or other standing prose is not binding
— only tokens on the skill invocation line are.

**Resolution order** (first supplied value wins per key; report effective values and their source
at lane start):

1. **Invocation arguments** — the flags and optional `<owner/repo>` below.
2. **Persisted durable state** — prior-cycle telemetry block when the new invocation omits a key.
3. **`userConfig`** — `${user_config.lane_instance}` when `--instance` is absent and durable state
   carries no `lane_instance`.
4. **Defaults** — `stop_mode=standing`, `ordering=oldest-first`, `shard=null`, `scope=null`;
   instance from `userConfig` or sanitized hostname per
   [telemetry-upsert.md](telemetry-upsert.md).

Invocation tokens always override persisted values when both are present.

**`<owner/repo>`** (optional). When present, validate against the checkout's `origin` remote
(`git remote get-url origin` → normalize to `owner/repo`). Mismatch is a hard stop with a clear
message — never guess a repository. When absent, the bound tracker repository is the checkout.

**`--drain`**. Sets `stop_mode=drain`. At exit evaluation load
[mode-drain.md](mode-drain.md); when absent, `stop_mode=standing` and load
[mode-standing.md](mode-standing.md).

**`--shard <i>/<n>`**. Partition retained snapshot ids: keep only items whose issue number
satisfies `number % n == i`. Validate `0 <= i < n` and `n >= 1`; reject malformed shards
fail-closed. Persist `{"index":i,"count":n}` in durable state, or `null` when unset.

**`--ordering oldest-first|newest-first`**. Controls execute-step cap-slot fill order among
admitted items this cycle. Default `oldest-first`. Persist in durable state.

**`--instance <id>`**. Overrides `${user_config.lane_instance}` for this invocation. Validate
`^[a-z0-9][a-z0-9-]{0,31}$` and length ≤ 32 before building the telemetry marker — same gate as
[telemetry-upsert.md](telemetry-upsert.md). Reject invalid ids fail-closed.

**`--scope <label>`**. Exact label filter on snapshot ids before admission and exit evaluation
(e.g. `area:api`). Persist the label string or `null`.

**Fail-closed rejections** — stop with an explicit message naming the owning surface; never
silently ignore:

- **Babysit tier keywords** (`safe`, `worker`, `autopilot`) and **merge dimension flags**
  (`--merge …`) belong to `/source-control:babysit-loop`, not this worker lane.
- **Adaptive cap knobs** (`--item-cap`, `--cap`, `--wave-cap`, or any `work_loop_item_cap_*`
  override token) — cap bounds come from `userConfig` only.
- **Unknown flags** and duplicate conflicting tokens.

Headless launches take explicit invocation tokens or persisted durable state; never block on an
interview for these knobs (headless-config floor).
