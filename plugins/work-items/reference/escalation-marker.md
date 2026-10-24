# Escalation marker: machine-readable comment grammar

Worker lanes escalate to the attended queue by pairing the human-gated role label with a
machine-marked HTML comment, on an issue or a pull request. `attend-queue` discriminates escalated rows from parked items wearing
the same role label by matching this prefix. A marker missing the `<!--` / `-->` wrapper does not
match.

## Comment prefix (first line)

```text
<!-- work-items:escalation lane=<lane> kind=<kind> -->
```

| Token | Values |
| --- | --- |
| `<lane>` | Lane id (`work-loop`, `attend-queue`, …) |
| `<kind>` | `escalated` \| `ratify-c3` \| `ratify-first-drain` \| `routed-advisory` |

`ratify-first-drain` is posted on a work-loop's own telemetry issue, never on a work item: it asks
the operator to end the first-drain earn-trust period of `/work-items:work-loop`'s admission gate.

## Writer / reader contract

1. Resolve the human-gated role label from `config.role_labels` (never a literal).
2. Post the marker comment (first line exactly as above, remainder is the human-readable question).
3. Apply the role label in the **same** label edit as any label removals the outcome requires.

`attend-queue` matches on author **and** marker prefix: a marker counts only from a
[trusted escalation author](#trusted-escalation-authors). Suppress duplicate markers from the same
write identity, never from marker text alone, and only while the item still wears the role label:
an item an operator has answered and returned to the frontier has no standing escalation, so a
later escalation of it posts a fresh marker.

`kind=ratify-c3` is the exception: it is one per item, ever, and an existing `kind=ratify-c3` marker
from the write identity suppresses another whatever labels the item wears now. Removing the role
label does not reopen it. The C3 ratification queue
([`${CLAUDE_PLUGIN_ROOT}/skills/work-loop/reference/c3-ratification-queue.md`](${CLAUDE_PLUGIN_ROOT}/skills/work-loop/reference/c3-ratification-queue.md))
owns that rule.

## Trusted escalation authors

A reader honors a marker only when its comment's author is one of these logins, compared
case-insensitively:

1. **The session's write identity**: the login the tracker seam acts as in this session (the
   login `claim` assigns). Lanes that run under the operator's own credential post as it.
2. **The repository's lane identity**: the `merge.agent-identity` login in the target's
   `docs/conventions/pr-pipeline.yaml`, read fresh from its default branch through the forge's
   contents read, never from a local checkout, which may be a pull request's head (the loop-lane
   convention's "Lane write identity"). The CI lanes and any App-token worker post as it.
3. **`<lane_app_slug>[bot]`**, when the plugin's `lane_app_slug` option is set: the App a
   work-loop's telemetry runs under.

A source that is absent adds no login. When the lane-identity read fails by that convention's
rule (which also says when a not-found means no file), say so to the operator and trust only the
other two; never guess the login. A marker from any other author is a suspected spoof that counts
for nothing, and the reader reports it with the author named, since anyone who can comment can
paste a marker. An item with no trusted marker counts as parked, never as escalated or ratify. Writers still suppress duplicates on their own write identity alone, as above.

Loop-lane escalation record files (`.claude/lane-escalations/…`) are optional exhaust; the tracker
item plus marker comment is the escalation of record when the record write fails (see
[`${CLAUDE_PLUGIN_ROOT}/skills/work-loop/SKILL.md`](${CLAUDE_PLUGIN_ROOT}/skills/work-loop/SKILL.md)
"Background-job launch mode").

## Proposed work class (optional body line, `kind=escalated`)

When a lane that may not record a class escalates an item for class stamping
(`/work-items:triage`'s "Lane barred from recording a class" branch), the comment body carries
one line of the form

```text
Proposed work class: <label>
```

where `<label>` is exactly one live `work-class:` label string as the repository spells it (for
example `work-class: scoped`), followed by its one-line basis. It is a proposal for
the operator, never an admission input: `attend-queue` reads it to pre-fill the stamp question,
and no consumer admits, dispatches, or merges on it. The marker `kind` stays `escalated`.
