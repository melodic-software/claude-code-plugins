# Telemetry comment upsert (per-instance singleton, race-converging)

The upsert this lane runs to maintain its ONE sentinel-identified status comment **for this
lane instance**. `SKILL.md`'s "Telemetry and durable loop state" owns where the comment lives and
what goes in it; this file owns the contract of the script that maintains the singleton.

The mechanism lives in this plugin rather than in `claude-ops` because an installed plugin cannot
invoke a sibling plugin's scripts.

**Resolve the lane instance first.** The marker names the *writer*, not the lane type, per the
convention's lane-instance identity rule. Resolution order matches `SKILL.md`'s invocation surface
(cited from [invocation-argv.md](invocation-argv.md)): a supplied `--instance` token wins, else
persisted `lane_instance` from the durable state block, else `${user_config.lane_instance}`. Pass
the resolved value through; the script owns everything after that, including the hostname fallback
for an unset key and the validation that rejects a non-conforming id.

## Invocation

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lane-telemetry-upsert.sh" \
  --lane work-loop --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" --body-file "$BODY_FILE"
```

| Argument | Value |
| --- | --- |
| `--lane` | `work-loop` for this lane. Names the marker's lane half. |
| `--instance` | The resolved lane instance. An empty value, or a surviving literal `${user_config.…}` placeholder, means the key is unset and takes the sanitized-hostname fallback (headless-config floor: the script logs the assumption). |
| `--repo` | The target repository as `owner/name`. |
| `--issue` | The lane's tracking issue number. |
| `--body-file` | The file holding this cycle's composed body. |

## What the upsert writes

The marker is `work-items:work-loop@<instance>` and the comment's first line is the sentinel
`<!-- claude-ops:lane-telemetry marker=<marker> -->`, an HTML comment that is invisible when
rendered and distinct per writer, so sibling instances each own one comment on the same issue.
The lookup is a `startswith` match on that full sentinel, so a body that merely quotes a sibling's
sentinel is never adopted. Where the lookup finds nothing the script creates the comment; where it
finds one it edits that comment in place; where it finds several the LOWEST id is canonical
(numeric sort, deterministic for every session), the canonical comment receives this cycle's full
state, and every other sentinel comment is edited to a one-line tombstone, but only once the
canonical write verifies, so a cycle whose own write is unproven never tombstones a racing
session's comment. That converges the fork two sessions create when both race the first-ever
upsert. A crashed racer's unmerged counters are an accepted loss (durable state re-derives over a
cycle); nothing is deleted. A sibling instance's comment carries a different marker, never enters
the list, and is neither made canonical nor tombstoned.

**`$BODY_FILE` contract.** The file's FIRST line must be exactly the sentinel above, with the
cycle's telemetry below it and at least 16 payload bytes there. The lookup matches on that prefix,
so a body composed without it is not merely rejected. It would never be found again, and the next
cycle would post a second comment. Compose the sentinel into the file; do not rely on anything
downstream to add it.

**Three checks, because they catch different failures.** The pre-write body gate runs before any
API call and rejects a body that is empty, opens with a literal `@`, is not sentinel-prefixed, or
carries under 16 payload bytes below the sentinel. The write's own exit status is checked next: a
PATCH that fails leaves the previous cycle's body in place, which a read-back running regardless
would happily accept. The post-write read-back then re-reads what the write stored, the only check
that sees a write which reported success and stored something else. Create and update use
`-F body=@`, because `-f body=@FILE` transmits the literal path.

## Exit codes

Every refusal is a distinct code with a one-line stderr reason. A non-zero exit is never a reason
to end the loop: the lane records the outcome and continues.

| Code | Meaning | What the lane does |
| --- | --- | --- |
| 0 | Upserted and verified; duplicates superseded | Report the cycle normally. |
| 2 | Missing, repeated, or unknown argument | Fix the invocation. |
| 3 | `--lane` is not `work-loop` or `attend-queue` | Fix the invocation. |
| 4 | The resolved instance is empty, starts with a hyphen, or carries a character outside `[a-z0-9-]` | Stop the lane rather than write under a marker nobody chose. |
| 5 | The resolved instance exceeds 32 characters (the length half of `^[a-z0-9][a-z0-9-]{0,31}$`; code 4 enforces the shape half) | Same as code 4. |
| 6 | `--repo` is not `owner/name` | Fix the invocation. |
| 7 | `--issue` is not a positive integer | Fix the invocation. |
| 8 | `gh` or `jq` is not on PATH | Carry the telemetry in the cycle report instead. |
| 9 | The body file is missing, empty, or opens with a literal `@` | NOTHING was written. Fix the body composition; do not re-run blind. |
| 10 | The body is not sentinel-prefixed, or carries under 16 payload bytes | Same as code 9. |
| 11 | The comment lookup failed or returned unparsable JSON | Nothing was written (fail closed). Treat the lane as UNREPORTED. |
| 12 | No comment available to write to; a create may have landed but was not re-found | Treat the lane as UNREPORTED. |
| 13 | The PATCH of the canonical comment failed | Treat the lane as UNREPORTED; the comment holds an earlier body, not this cycle's write. |
| 14 | The canonical comment does not carry a well-formed telemetry body after the write | Treat the lane as UNREPORTED; do not trust the timestamp. |

An unreadable comment list is fail-closed rather than read as empty, because treating it as empty
posts a second comment, the exact failure the singleton exists to prevent.

**Carry every UNREPORTED outcome forward.** A degraded body that does land still moves the
comment's timestamp, so a consumer keying on that timestamp rather than on the body reads the lane
as **fresh** while it carries nothing. Stderr does not survive the session, so a refusal, a failed
write, and a failed verification all have to reach the next cycle: a lane with durable loop state
records it there, a lane without one carries it in the cycle's own summary.

## Gotcha: compound-command permission matching and the isolated-calls fallback

The gate order lives inside the script, so the invocation is one simple command rather than the
compound shape (variable assignment, a lookup function, an `if/elif/else`, a `for` loop, and
several `gh api` calls in one Bash invocation) a permission rule may not cover. Verified 2026-09-06
against Claude Code 2.1.263 and the permissions page at
`https://code.claude.com/docs/en/permissions#compound-commands`, which states that an allow rule must
match each subcommand independently, and that a deny or ask rule applies when any subcommand matches,
including one nested in a subshell or a control-flow body. Recheck when that page stops carrying the
per-subcommand matching rule, or when a release note names compound-command permission matching. When the
invocation is blocked anyway, retry it rather than hand-transcribing the upsert: reproducing the
gates in isolated calls loses the distinct exit codes the lane reads its own outcome from.

## Known limits

A PATCH that succeeds while storing the previous body still verifies: the read-back asserts that
*some* well-formed telemetry is present, not that *this* cycle's write is what is present. Not
implemented at all: the 64 KiB cap, body-file containment, and read retries that the `claude-ops`
lanes wrapper carries.
