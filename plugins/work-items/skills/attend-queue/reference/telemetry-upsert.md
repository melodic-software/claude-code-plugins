# Telemetry comment upsert (per-instance singleton, race-converging)

The upsert this lane runs to maintain its ONE sentinel-identified status comment **for this
lane instance**. [`../SKILL.md`](../SKILL.md)'s "Telemetry" section owns that the comment exists and
when it is written; this file owns the contract of the script that maintains the singleton.

The mechanism lives in this plugin rather than in `claude-ops` because an installed plugin cannot
invoke a sibling plugin's scripts.

Per the convention, this lane too maintains exactly ONE sentinel-identified status comment **per
lane instance** on its per-lane tracking issue in the target repository (default title
`Lane telemetry: attend-queue`, created through the seam `create-item` verb when absent), edited in
place each pass with the rows handled, the answers written, and the guard mode. Same script as the
worker loop, including the lane-instance validation that runs before the marker is built. The
marker names the writer, not the lane type, so two attended sessions on one repository never
overwrite each other's pass record. Resolve the instance from `${user_config.lane_instance}` and
pass it through; the script owns everything after that, including the hostname fallback for an
unset key and the validation that rejects a non-conforming id.

## Invocation

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lane-telemetry-upsert.sh" \
  --lane attend-queue --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" --body-file "$BODY_FILE"
```

| Argument | Value |
| --- | --- |
| `--lane` | `attend-queue` for this lane. Names the marker's lane half. |
| `--instance` | The resolved lane instance. An empty value, or a surviving literal `${user_config.…}` placeholder, means the key is unset and takes the sanitized-hostname fallback (headless-config floor: the script logs the assumption). |
| `--repo` | The target repository as `owner/name`. |
| `--issue` | The lane's tracking issue number. |
| `--body-file` | The file holding this pass's composed body. |

## What the upsert writes

The marker is `work-items:attend-queue@<instance>` and the comment's first line is the sentinel
`<!-- claude-ops:lane-telemetry marker=<marker> -->`, an HTML comment that is invisible when
rendered and distinct per writer, so sibling instances each own one comment on the same issue.
The lookup is a `startswith` match on that full sentinel, so a body that merely quotes a sibling's
sentinel is never adopted. Where the lookup finds nothing the script creates the comment; where it
finds one it edits that comment in place; where it finds several the LOWEST id is canonical
(numeric sort, deterministic for every session), the canonical comment receives this pass's full
state, and every other sentinel comment is edited to a one-line tombstone, but only once the
canonical write verifies, so a pass whose own write is unproven never tombstones a racing
session's comment. That converges the fork two sessions create when both race the first-ever
upsert. A crashed racer's unmerged counters are an accepted loss; nothing is deleted. A sibling
instance's comment carries a different marker, never enters the list, and is neither made canonical
nor tombstoned.

**`$BODY_FILE` contract.** The file's FIRST line must be exactly the sentinel above, with the pass
report below it and at least 16 payload bytes there. The lookup matches on that prefix, so a body
composed without it is not merely rejected. It would never be found again, and the next pass would
post a second comment. Compose the sentinel into the file; do not rely on anything downstream to
add it.

**Three checks, because they catch different failures.** The pre-write body gate runs before any
API call and rejects a body that is empty, opens with a literal `@`, is not sentinel-prefixed, or
carries under 16 payload bytes below the sentinel. The write's own exit status is checked next: a
PATCH that fails leaves the previous pass's body in place, which a read-back running regardless
would happily accept. The post-write read-back then re-reads what the write stored, the only check
that sees a write which reported success and stored something else. Create and update use
`-F body=@`, because `-f body=@FILE` transmits the literal path.

## Exit codes

Every refusal is a distinct code with a one-line stderr reason. A non-zero exit is never a reason
to end the pass: the lane records the outcome and continues.

| Code | Meaning | What the lane does |
| --- | --- | --- |
| 0 | Upserted and verified; duplicates superseded | Report the pass normally. |
| 2 | Missing, repeated, or unknown argument | Fix the invocation. |
| 3 | `--lane` is not `work-loop` or `attend-queue` | Fix the invocation. |
| 4 | The resolved instance is empty, starts with a hyphen, or carries a character outside `[a-z0-9-]` | Stop the lane rather than write under a marker nobody chose. |
| 5 | The resolved instance exceeds 32 characters (the length half of `^[a-z0-9][a-z0-9-]{0,31}$`; code 4 enforces the shape half) | Same as code 4. |
| 6 | `--repo` is not `owner/name` | Fix the invocation. |
| 7 | `--issue` is not a positive integer | Fix the invocation. |
| 8 | `gh` or `jq` is not on PATH | Carry the telemetry in the pass report instead. |
| 9 | The body file is missing, empty, or opens with a literal `@` | NOTHING was written. Fix the body composition; do not re-run blind. |
| 10 | The body is not sentinel-prefixed, or carries under 16 payload bytes | Same as code 9. |
| 11 | The comment lookup failed or returned unparsable JSON | Nothing was written (fail closed). Treat the lane as UNREPORTED. |
| 12 | No comment available to write to; a create may have landed but was not re-found | Treat the lane as UNREPORTED. |
| 13 | The PATCH of the canonical comment failed | Treat the lane as UNREPORTED; the comment holds an earlier body, not this pass's write. |
| 14 | The canonical comment does not carry a well-formed telemetry body after the write | Treat the lane as UNREPORTED; do not trust the timestamp. |

An unreadable comment list is fail-closed rather than read as empty, because treating it as empty
posts a second comment, the exact failure the singleton exists to prevent.

**Carry every UNREPORTED outcome forward.** A degraded body that does land still moves the
comment's timestamp, so a consumer keying on that timestamp rather than on the body reads the lane
as **fresh** while it carries nothing. Stderr does not survive the session, so a refusal, a failed
write, and a failed verification all have to reach the next pass, which for this lane means the
pass's own summary.

## Known limits

A PATCH that succeeds while storing the previous body still verifies: the read-back asserts that
*some* well-formed telemetry is present, not that *this* pass's write is what is present. Not
implemented at all: the 64 KiB cap, body-file containment, and read retries that the `claude-ops`
lanes wrapper carries.

Report the instance on its own `instance:` line in the pass report, never appended to `lane:`, the
telemetry reader's lane capture is `[a-z0-9_-]+` and would truncate the suffix. This lane carries no
durable-state block, so the convention's instance-collision check does not bind here; the marker
partition alone is sufficient because an operator is present by definition and a duplicate id
surfaces to them in the same pass.

When the bound provider is not `github`, this upsert is unavailable: carry the same telemetry
content in the lane's pass report/log instead, with a notice that the comment surface is absent.
