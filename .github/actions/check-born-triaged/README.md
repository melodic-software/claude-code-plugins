# check-born-triaged

Gate the intake lanes (`intake-triage.yml`, `intake-label-needs-triage.yml`) so they skip an issue
`/work-items:decompose` published already triaged. Issue text is untrusted, so the marker alone
never skips intake.

## Skip rule

`skip=true` only when all of these hold on the issue:

- Its body contains `<!-- work-items:born-triaged -->`, which the decompose publisher writes.
- Its author is on [`trusted-actors.json`](../../standards/trusted-actors/trusted-actors.json) with
  kind `human`, or is the lanes App bot, both matched by numeric user id. A marker in an issue from
  anyone else is ignored.
- It has an Issue Type and a status label: `agent-ready`, `needs-human`, or any `status:` label.

The publisher sets the type and labels in calls after the issue is created, so while only those are
missing the gate re-reads the issue every 5 seconds, 6 reads in all, before it gives up. A publisher
on gh older than 2.94 sets a `type:` label instead of an Issue Type, so its items still get intake.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `issue-number` | `github.event.issue.number` | The issue to check |
| `trusted-actors-path` | `.base/.github/standards/trusted-actors/trusted-actors.json` | The list, from a default-branch checkout |
| `lanes-app-id` | empty | The lanes App bot's user id, normally `${{ vars.AUTOMATION_LANES_APP_SENDER_ID }}`; empty trusts listed humans only |
| `github-token` | `github.token` | Reads the issue; needs `issues: read` |

## Outputs

| Output | Values |
|---|---|
| `skip` | `true` to skip intake, otherwise `false` |
| `reason` | `born-triaged`, `no-marker`, `untrusted-author`, `no-type`, `no-status`, `list-unreadable` or `issue-unreadable` |
| `human-ids` | The list's `kind: human` ids, comma-joined, for the intake lane's `allowed-author-ids`; empty when the list is unreadable |
| `rate-limited` | `true` when the rate guard holds a stop on the issue read's pool, from this read or an earlier step of the job; the callers then skip their jobs that call GitHub with the same token. Otherwise `false` |

The step always exits 0. A failed gate job leaves `skip` and `human-ids` empty, so the callers'
intake jobs fall through to the reusable, which turns away every person.
