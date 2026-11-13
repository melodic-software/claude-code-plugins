# check-born-triaged

Gate the intake lane (`intake-triage.yml`: its triage and its `needs-triage` floor label) so it skips an issue
another skill routes, or one `/work-items:decompose` published already triaged. Issue text is
untrusted, so the marker alone never skips intake.

## Routing labels

`skip=true` with reason `routing-label` when the issue carries the container label (a decompose
spec container) or a label starting with the wayfind prefix (a `/planning:wayfind` map or one of
its decision items). Those labels are the work-items seam's own routing state
([label taxonomy](../../../plugins/work-items/reference/label-taxonomy.md), "Container label" and
"Hold lists and the wayfind prefix"), so intake's priority, verdict and floor label would only
compete with it. Both come from the binding at `tracker-config` (`tracker.config.container_label`,
default `spec-container`; `tracker.config.wayfind_label_prefix`, default `wayfind:`), read the way the
merge lanes read it (`trackerBindingText` in `.github/scripts/pr-merge/merge-holds.mjs`). A missing
file keeps both defaults; a value that is not a string keeps them with a warning. The step prints a
notice naming the label. Only an account with triage access can label an issue as it is opened, so
this rule checks no author. It applies whatever `born-triaged` says, once the trusted-actor list
reads.

## Born-triaged rule

With `born-triaged` true (the default), `skip=true` with reason `born-triaged` only when all of
these hold on the issue:

- Its body ends with `<!-- work-items:born-triaged -->` as its last line, where the decompose
  publisher writes it; a copy elsewhere in the body does not count.
- Its author is on [`trusted-actors.json`](../../standards/trusted-actors/trusted-actors.json) with
  kind `human`, or is the lanes App bot, both matched by numeric user id. A marker in an issue from
  anyone else is ignored.
- It has an Issue Type and a status: a Work status field a trusted account set to anything but
  `needs-triage`, or the label `agent-ready`, `needs-human`, `needs-spec`, `admission-deferred`, or
  any `status:` label. While `models.issue-status` is set and the field holds no trusted state,
  `agent-ready` alone is no status: the label starts no lane run and admission writes the field, so
  the gate returns `skip=false` with reason `label-only` at once, and intake triages the issue.

The publisher sets the type and status in calls after the issue is created, so while only those are
missing the gate re-reads the issue every 5 seconds, 6 reads in all, before it gives up. A publisher
on gh older than 2.94 sets a `type:` label instead of an Issue Type, so its items still get intake.
With `born-triaged` false the gate reads the issue once and, with no routing label, returns
`skip=false` with reason `born-triaged-off`.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `issue-number` | `github.event.issue.number` | The issue to check |
| `trusted-actors-path` | `.base/.github/standards/trusted-actors/trusted-actors.json` | The list, from a default-branch checkout |
| `lanes-app-id` | empty | The lanes App bot's user id, normally `${{ vars.AUTOMATION_LANES_APP_SENDER_ID }}`; empty trusts listed humans only |
| `github-token` | `github.token` | Reads the issue; needs `issues: read` |
| `born-triaged` | `true` | `false` skips only on a routing label; `intake-triage.yml` passes `false` on a reopen and a dispatch |
| `tracker-config` | `.base/docs/conventions/work-items.yaml` | The work-items binding holding the routing labels, from a default-branch checkout |

## Outputs

| Output | Values |
|---|---|
| `skip` | `true` to skip intake, otherwise `false` |
| `reason` | `routing-label`, `born-triaged`, `born-triaged-off`, `no-marker`, `untrusted-author`, `no-type`, `no-status`, `label-only`, `list-unreadable` or `issue-unreadable` |
| `label` | The routing label that skipped the issue; empty otherwise |
| `human-ids` | The list's `kind: human` ids, comma-joined, for the intake lane's `allowed-author-ids`; empty when the list is unreadable |
| `rate-limited` | `true` when the rate guard holds a stop on the issue read's pool, from this read or an earlier step of the job; the callers then skip their jobs that call GitHub with the same token. Otherwise `false` |

The step always exits 0. A failed gate job leaves `skip` and `human-ids` empty, so the callers'
intake jobs fall through to the reusable, which turns away every person.
