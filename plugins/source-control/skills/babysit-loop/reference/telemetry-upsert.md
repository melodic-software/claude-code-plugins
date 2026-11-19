# Telemetry comment upsert (per-instance singleton, race-converging)

The exact upsert this lane runs at cycle-shape step 6 to maintain its one sentinel-identified status
comment **for this lane instance**. `SKILL.md`'s "Telemetry and durable loop state" owns where the
comment lives and what goes in it; this file owns how the singleton is maintained and how a creation
race converges.

The upsert is a script in this plugin, not a call into `harness-ops`, because an installed plugin
cannot invoke a sibling plugin's scripts.

Per the convention's lane-instance identity rule, the marker names the **writer**, not the lane
type: a marker naming only the lane makes two concurrent instances resolve one comment and
clobber each other's durable state. Write the cycle's telemetry (cycle report, state block, guard
mode, `usage_sample`) to a file, then run:

```bash
bash <plugin-root>/skills/babysit-loop/scripts/telemetry-upsert.sh \
  --repo <owner/repo> --issue <telemetry issue number> \
  --instance '${user_config.lane_instance}' --app-slug '${user_config.lane_app_slug}' \
  --body-file <telemetry file> --body-dir "<plugin-data>"
```

Write the telemetry file under `<plugin-data>`, the plugin data dir that `../SKILL.md` gives as an
absolute path, and pass the same path as `--body-dir`. The script refuses a dir whose last segment
does not name `source-control`, or that is `/`, the home dir or an ancestor of it. The script refuses a symlink or
a path that resolves outside `--body-dir` before reading it (exit 3), so a prompt-injected path
cannot post a credential file as a public comment. It then scans the body with the shared leak scan
and withholds all of it on a hit (exit 3), naming the rule and never the match; rotate a real
credential.

Keep the single quotes: an unsubstituted placeholder inside double quotes is a bash
`bad substitution` error, while single quotes pass it through for the fallback below. The same
holds for `--app-slug`: an empty `lane_app_slug`, or a surviving literal `${user_config.…}`
placeholder, is treated as absent, like an unset `lane_instance`.

The script writes the sentinel line
`<!-- harness-ops:lane-telemetry marker=source-control:babysit-loop@<instance> -->` above the body,
so the file holds the telemetry alone (a file that already opens with that exact line is sent
as-is). An unset `lane_instance` (empty, or a surviving literal `${user_config.…}` placeholder)
falls back to a random `lane-<hex>` id the script makes once and keeps in
`<body-dir>/lane-instance`, and logs the assumption. Never the hostname: the marker is public, so a
`lane_instance` the leak scan reads as a fleet or private hostname exits 3 with nothing written;
unset the key so the stored random id is used. The id is
operator-supplied text that ends up in a `jq` program and an API path, so it is validated against
`^[a-z0-9][a-z0-9-]{0,31}$` and **rejected**, never trimmed into something that looks valid; the
stored fallback passes the same check.

**Only this lane's own comments count.** The sentinel is public and the instance id predictable, so
anyone who can comment on the tracking issue can post a lookalike. The lookup matches a
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
read or written: an unresolved identity fails closed instead of matching any author. Changing the identity (a user token swapped for an App token, or another account) leaves
the old comment and its durable state behind: the lane starts unclaimed under the new identity, and
the operator retires the old comment.

- **Pointer:** what an installation token can call and the login its writes carry,
  [Authenticating as a GitHub App installation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation);
  the slug output of the minting action,
  [actions/create-github-app-token outputs](https://github.com/actions/create-github-app-token#outputs).

**What the script checks, in order.** The pre-write gate rejects a body that is empty, opens with a
literal `@`, or carries under 16 bytes below the sentinel: the mechanical form of the `@path`-as-body
rule owned by `/harness-ops:lanes` ("Never pass a body as an `@path` string"). The lookup reads every
comment page; a failed lookup writes nothing. The write's own exit status is checked. Then the
comment is read back and **byte-compared with the body sent** (CR and trailing newlines stripped
from both sides, nothing else), so a write that reported success but stored something else (an
earlier body, a concurrent overwrite, a mangled store or a deleted comment) is caught, not
accepted because it still looks like telemetry.

**Exit codes.**

| Exit | Meaning | This cycle's telemetry |
|---|---|---|
| 0 | written, and the read-back matches the body sent | confirmed |
| 3 | invalid `--repo`/`--issue`/instance, a body file outside `--body-dir` or a symlink, or the body failed the pre-write gate or the leak scan; nothing written | fix the body composition, do not re-run blind |
| 4 | `gh` or `node` not found; nothing written | unreported |
| 5 | the write identity, the lookup, the POST, or the PATCH failed, or the POST landed under a login other than the resolved identity (a wrong `--app-slug`: the script deletes that comment and names the login it landed under); the comment holds an earlier body or none | unreported |
| 6 | the write was sent but is unconfirmed: the created comment was not re-found, the read-back failed, or the stored body differs | unreported |

Any non-zero exit means the lane is **UNREPORTED** for this cycle: carry that forward to the next
cycle and do not trust the comment's timestamp. A degraded or stale body still moves that timestamp,
so a consumer keying on it would read the lane as fresh while it carries nothing, and stderr does
not survive the session. A lane with durable loop state records it there; a lane without one carries
it in the cycle's own summary. A failed duplicate tombstone after a verified write is reported on
stderr only and retried next cycle.

**Creation race reconcile (in the script).** Two sessions racing the first-ever upsert can both
see an empty lookup and both POST, forking the singleton. The upsert converges duplicates on every
cycle that sees them: the lowest comment id is canonical (numeric sort, deterministic for
every session), the canonical comment receives the current cycle's full state, and every other
sentinel comment is edited to a one-line tombstone, only once the canonical write verifies, so
it never matches a lookup again. This covers a racer that died between its POST and its own
re-list, because the next session's ordinary upsert performs the same reconcile. A crashed
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
  --instance '${user_config.lane_instance}' --app-slug '${user_config.lane_app_slug}' --read \
  --body-dir "<plugin-data>"
```

It passes `--app-slug` as the write does. It prints the canonical comment's
body, or nothing when this identity has no sentinel comment yet (the marker is unclaimed), and
writes nothing. A non-zero exit means the state is unknown, not absent: do no work and do not claim
the marker this cycle.

## Instance-collision check (cycle start, before any write)

Run [lane-instance-collision-check.md](lane-instance-collision-check.md) after re-reading the block
with `--read` (above); `SKILL.md`'s state block carries the fields it reads.

The legacy un-suffixed comment is never adopted, edited, or tombstoned: its marker names no writer,
so no instance can prove it owns it, and adopting it would reintroduce the shared-comment clobber
the partition removes. Retiring it is an operator action.
