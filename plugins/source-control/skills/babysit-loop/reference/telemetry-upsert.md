# Telemetry comment upsert (per-instance singleton, race-converging)

The exact upsert this lane runs at cycle-shape step 6 to maintain its ONE sentinel-identified status
comment **for this lane instance**. `SKILL.md`'s "Telemetry and durable loop state" owns where the
comment lives and what goes in it; this file owns how the singleton is maintained and how a creation
race converges.

The upsert is a script in this plugin rather than a call into `harness-ops` because an installed
plugin cannot invoke a sibling plugin's scripts.

Per the convention's lane-instance identity rule, the marker names the **writer**, not the lane
type: a marker naming only the lane makes two concurrent instances resolve one comment and
clobber each other's durable state. Write the cycle's telemetry (cycle report, state block, guard
mode, `usage_sample`) to a file, then run:

```bash
bash <plugin-root>/skills/babysit-loop/scripts/telemetry-upsert.sh \
  --repo <owner/repo> --issue <telemetry issue number> \
  --instance '${user_config.lane_instance}' --app-slug '${user_config.lane_app_slug}' \
  --body-file <telemetry file>
```

Keep the single quotes: an unsubstituted placeholder inside double quotes is a bash
`bad substitution` error, while single quotes pass it through for the fallback below. The same
holds for `--app-slug`: an empty `lane_app_slug`, or a surviving literal `${user_config.…}`
placeholder, is treated as absent, like an unset `lane_instance`.

The script writes the sentinel line
`<!-- harness-ops:lane-telemetry marker=source-control:babysit-loop@<instance> -->` above the body,
so the file holds the telemetry alone (a file that already opens with that exact line is sent
as-is). An unset `lane_instance` (empty, or a surviving literal `${user_config.…}` placeholder)
falls back to the sanitized lowercased hostname, and the script logs the assumption. The id is
operator-supplied text that ends up in a `jq` program and an API path, so it is validated against
`^[a-z0-9][a-z0-9-]{0,31}$` and **rejected**, never trimmed into something that looks valid; the
hostname fallback passes the same check.

**Only this lane's own comments count.** The sentinel is public and the instance id predictable, so
anyone who can comment on the tracking issue can post a lookalike. The lookup therefore matches a
comment only when it opens with the sentinel **and** was written by the script's write identity; a
foreign sentinel comment is never adopted, edited, or tombstoned, however low its id. The script
resolves that identity before any lookup:

1. `gh api user` reporting a `User`: that login (a personal or machine-user token).
2. That call failing or reporting a `Bot`: the token is treated as a GitHub App's, and the
   identity is `<slug>[bot]` from `--app-slug <slug>`. Every call passes
   `--app-slug '${user_config.lane_app_slug}'`; a lane running under an App installation token sets
   `lane_app_slug`, and a workflow that mints the token takes the slug from whatever minted it.
3. A `Bot` report with no `--app-slug`: the reported login, with the `[bot]` suffix added when
   missing.

Anything else, or a login outside `[A-Za-z0-9-]` plus an optional `[bot]`, exits 5 with nothing
read or written: an unresolved identity fails closed rather than falling back to matching any
author. Changing the identity (a user token swapped for an App token, or another account) leaves
the old comment and its durable state behind: the lane starts unclaimed under the new identity, and
the operator retires the old comment.

- **Pointer:** what an installation token can call and the login its writes carry,
  [Authenticating as a GitHub App installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation);
  the slug output of the minting action,
  [actions/create-github-app-token outputs](https://github.com/actions/create-github-app-token#outputs).
- **As of:** 2026-10-11.
- **Recheck:** an App token's writes landing under a login other than `<slug>[bot]`, or a lane run
  under an App token exiting 5 with `--app-slug` passed.

**What the script checks, in order.** The pre-write gate rejects a body that is empty, opens with a
literal `@`, or carries under 16 bytes below the sentinel: the mechanical form of the `@path`-as-body
rule owned by `/harness-ops:lanes` ("Never pass a body as an `@path` string"). The lookup reads every
comment page; a failed lookup writes nothing. The write's own exit status is checked. Then the
comment is read back and **byte-compared with the body sent** (CR and trailing newlines stripped
from both sides, nothing else), so a write that reported success but stored something else, an
earlier body, a concurrent overwrite, a mangled store or a deleted comment, is caught rather than
accepted because it still looks like telemetry.

**Exit codes.**

| Exit | Meaning | This cycle's telemetry |
|---|---|---|
| 0 | written, and the read-back matches the body sent | confirmed |
| 3 | invalid `--repo`/`--issue`/instance, or the body failed the pre-write gate; nothing written | fix the body composition, do not re-run blind |
| 4 | `gh` not found; nothing written | unreported |
| 5 | the write identity, the lookup, the POST, or the PATCH failed, or the POST landed under a login other than the resolved identity (a wrong `--app-slug`: the script deletes that comment and names the login it landed under); the comment holds an earlier body or none | unreported |
| 6 | the write was sent but is unconfirmed: the created comment was not re-found, the read-back failed, or the stored body differs | unreported |

Any non-zero exit means the lane is **UNREPORTED** for this cycle: carry that forward to the next
cycle and do not trust the comment's timestamp. A degraded or stale body still moves that timestamp,
so a consumer keying on it would read the lane as fresh while it carries nothing, and stderr does
not survive the session. A lane with durable loop state records it there; a lane without one carries
it in the cycle's own summary. A failed duplicate tombstone after a verified write is reported on
stderr only and retried next cycle.

**Creation race reconcile (in the script).** Two sessions racing the first-ever upsert can both
see an empty lookup and both POST, forking the singleton. The upsert converges every cycle
duplicates are visible: the LOWEST comment id is canonical (numeric sort, deterministic for
every session), the canonical comment receives the current cycle's full state, and every other
sentinel comment is edited to a one-line tombstone, only once the canonical write verifies, so
it never matches a lookup again. This covers a racer that died between its POST and its own
re-list, because the NEXT session's ordinary upsert performs the same reconcile. A crashed
racer's unmerged counters are an accepted loss (durable state re-derives over a cycle); nothing
is deleted. The reconcile converges duplicates **within one instance's own sentinel set**, written
by its own identity; a sibling instance's comment carries a different marker, and a foreign
author's carries a different login, so neither matches the lookup, is made canonical, or is
tombstoned.

## Reading the state block (re-anchor)

Re-anchor and the collision check below read the block through the same filter, never by fetching
comments directly:

```bash
bash <plugin-root>/skills/babysit-loop/scripts/telemetry-upsert.sh \
  --repo <owner/repo> --issue <telemetry issue number> \
  --instance '${user_config.lane_instance}' --app-slug '${user_config.lane_app_slug}' --read
```

It passes `--app-slug` as the write does. It prints the canonical comment's
body, or nothing when this identity has no sentinel comment yet (the marker is unclaimed), and
writes nothing. A non-zero exit means the state is unknown, not absent: do no work and do not claim
the marker this cycle.

## Instance-collision check (cycle start, before any write)

Partitioning is correct only while instance ids are distinct, so a collision is detected rather than
assumed away. `SKILL.md`'s state block carries the four fields this reads: `writer_nonce` is
generated once per session, `heartbeat_at` is rewritten every cycle, alongside `lane_instance` and
`paused_until`. After re-reading the block with `--read` (above):

- No block at all → the marker is unclaimed. **Claim it before any work**: upsert a cycle-0 block
  carrying my nonce and heartbeat, immediately re-read, and run the creation-race reconcile above.
  If the canonical (lowest-id) comment for my marker then carries a different nonce, another
  session claimed the instance first. Take the live-collision branch below. Claiming first bounds
  the race to the claim itself: two same-id sessions starting together each stop before either has
  performed work or overwritten the other's first durable state.
- Nonce matches mine → ordinary continuation.
- Nonce differs **and** the block carries a non-null `restart_request` → **clean handoff.**
  Recording the request is a stopping lane's last write, so a fresh `heartbeat_at` beneath one is
  a stopped predecessor, not a live writer. Adopt the block, clear `restart_request`, write my
  nonce, continue, so a replacement launched right after a cycle-budget or expiry stop starts
  immediately instead of waiting out the staleness window.
- Nonce differs **and** the block is stale (`heartbeat_at` over **2 hours** old, and past
  `paused_until` when set) → an earlier session of this same instance restarted or died. Adopt the
  block, write my nonce, continue. This is the ordinary restart path. Two hours is twice the longest
  self-paced wait, so a healthy lane at maximum idle backoff never reads as stale. Pointer:
  [scheduled tasks: let Claude choose the interval](https://code.claude.com/docs/en/scheduled-tasks#let-claude-choose-the-interval).
  As of: 2026-10-11. Recheck trigger: that section's longest delay grows past half the two-hour
  window.
- Nonce differs **and** the block is fresh with no pending `restart_request` → **another live lane
  holds my instance id.** Write nothing to the block, escalate per the convention's escalation
  contract, and stop the loop cleanly.

`paused_until` is not `rate_limit_latch` and does not replace it: the latch says *do not claim
work*; `paused_until` says *do not read my silence as death*. Write it before entering a rate-limit
pause so a paused lane is never adopted as a dead one.

Report the instance on its own `instance:` line in the cycle report, never appended to `lane:`.
That reader's capture is `[a-z0-9_-]+` and would truncate the suffix at the `@`, rendering the lane
as if nothing were partitioned.

The legacy un-suffixed comment is never adopted, edited, or tombstoned: its marker names no writer,
so no instance can prove it owns it, and adopting it would reintroduce the shared-comment clobber
the partition removes. Retiring it is an operator action.
