# Admission policy

Normative admission-policy content for the [guardrail matrix](../guardrails.md): the
decision that turns a
queued signal into an autonomously dispatchable item, a human-gated item, or an audited
rejection. The [trigger-dispatch contract](../trigger-dispatch.md) enforces this policy
at its admission seam. Adapters ENFORCE admission, never define it, and this leaf owns
the content. Serialized rules and caps live in the `admission` object of the security
binding on the settings-as-code governance surface, outside the blast radius of the
agents they govern (an agent-writable admission policy is a bypass channel).

## Decision table

One table, three axes, one disposition per decision:

| Axis | Values |
|---|---|
| Signal-surface class | `tracker-vcs-event` \| `temporal` \| `agent-internal` \| `channel-feed`, the trigger-contract tokens |
| Initiator provenance | `human` \| `agent` \| `system` |
| Work class | `C1`–`C5`, stamped per the trigger-dispatch classification rules |

| Disposition | Meaning |
|---|---|
| `autonomous-eligible` | May dispatch autonomously, within caps and subject to every other guardrail: [isolation verdict](isolation-ladder.md), execution-surface attestation, verification gates |
| `human-gated` | Enqueued and held; a human admits the item before any dispatch |
| `audited-rejection` | Recorded as rejected, with provenance and the matched rule on the audit trail, never a silent drop |

An item the classification rules cannot resolve never reaches table evaluation:
unclassified is fail-closed `human-gated`, always (trigger-dispatch rule).

### Wildcards and precedence

Any axis in a rule may be the wildcard `"*"`. Matching is most-specific-wins: a rule
binding the full triple beats one binding two axes, which beats one axis, which beats
the default disposition. Two matching rules of EQUAL specificity with different
dispositions make the binding invalid. It fail-closes, like any invalid security binding.

A rule may carry an optional `override_justification`. A rule MORE PERMISSIVE than the
shipped default for its cell is invalid without one; tightening needs none. Permissiveness
decreases `autonomous-eligible` → `human-gated` → `audited-rejection`.

## Shipped defaults

| Surface class | Provenance | Work class | Disposition |
|---|---|---|---|
| `"*"` | `"*"` | `C1` | `autonomous-eligible`, within caps |
| `"*"` | `"*"` | `C2` | `autonomous-eligible`, within caps |
| `"*"` | `"*"` | `C3` | `human-gated`, per-item human admission |
| `"*"` | `"*"` | `C4` | `human-gated` |
| `"*"` | `"*"` | `C5` | `human-gated` |

Default disposition where no rule matches: `human-gated`.

- `C1`/`C2` are autonomous-eligible within caps REGARDLESS of provenance: blocking
  `agent` provenance would sever the agent-kicks-off-agent loop the `agent-internal`
  surface class exists for.
- Provenance is RECORDED input to gating, never trusted as isolation: provenance is
  claimable, so isolation decisions key on the work class and surface verdicts. For
  `agent-internal` signals the trigger-dispatch contract verifies claimed provenance
  against protected dispatch data before admission consumes the class.
- No shipped rule produces `audited-rejection`; the disposition exists for org rules,
  for example a surface class or provenance the org bans outright, and every rejection
  stays on the audit trail.

## Caps

Caps bound TOTAL autonomous fan-out, applying across all rules and surfaces, never
per rule:

| Token | Shipped default | Bounds |
|---|---|---|
| `autonomous_concurrency` | `1` | Autonomous dispatches in flight at any moment |
| `items_per_run` | `3` | Items one drain run may dispatch autonomously |

Values are org-bindable; the shipped defaults are a deliberately conservative
trust-before-scale floor. A cap never changes a disposition: an over-cap
`autonomous-eligible` item stays enqueued for a later drain run. It is deferred, not
rejected and not re-gated.

## Rule admission (C1/C2)

The table above decides a disposition once an item has a class; a person stamps that class by
applying the autonomous-eligible label and a `work-class:` label. Owner-written rules in the
binding's optional `admission.rule_admission[]` let a no-model evaluator admit an issue to C1 or
C2 without that label, from the intake-triage lane's proposed class. Each entry is
`{id, work_class, proposed_class}`: `id` is `R<n>`, `work_class` is `C1` or `C2`, and
`proposed_class` is the `work-class:` label the lane must propose. The evaluator writes no label;
an admit is recorded as `admitted-by-rule: <id>@<binding sha>`.

Precedence, top-down, first hit decides:

1. `needs-human` present → refuse.
2. Trust-surface hit → refuse: the `area: security` label, or a deny-list term in the title or
   body (hook, guard or guardrail, permission, allow or deny list, workflow, `.github`, ruleset,
   CODEOWNERS, secret, token, credential, pin, SHA, checksum, admission, work-class,
   label-provenance, autonomy, security, merge, sandbox, auto mode, binding, trust, ci), matched
   as whole words. Plugin names that contain a term, such as `context-guard`, refuse too: a false
   positive fails closed.
3. Any `work-class:` label present → refuse, label left untouched.
4. A rule matches → admit; otherwise refuse.

A rule matches only when every term of the shared predicate holds, each read from provider
metadata or lane output, never from text an agent controls:

- the issue author's association is `OWNER` or `MEMBER`;
- every comment is from an `OWNER` or `MEMBER`, or is the lane comment;
- exactly one lane comment exists (`github-actions[bot]`, starting with
  `<!-- claude-lane intake-triage -->`), its run was not escalated, and the issue body was not
  edited after it;
- no `provenance: signal`, `area: security`, `do-not-merge`, `work-map`, `status:` or `wayfind:`
  label;
- the lane comment's second line is `Proposed work class: <proposed_class>` for the rule's
  `proposed_class`.

Untrusted text can only refuse: the title and body scan is a deny list, and the proposed class is
model output, so it admits only beside the author and comment tests issue text cannot change.

Each rule carries a dispatch constraint. A rule-admitted C1 gets no push or PR authority, and any
diff escalates. A rule-admitted C2 is human-merged: its PR carries `Hold: a human merges this`, so
it never takes a gate-proven C2 auto-merge rung until that rung's promotion evidence exists.

## Binding and fail-closed behavior

- Serialization home: the security binding's `admission` object, holding the decision-table
  rules, the caps, and the signal→work-class classification rules adapters stamp from.
  The binding schema is contract-owned and ships with the security binding; this leaf
  owns the semantics it serializes.
- An ABSENT or invalid admission binding fail-closes at the seam: everything enqueues
  `human-gated` (the trigger-dispatch contract's absent-binding clause).
- No repo-local (agent-writable) surface may supply any admission input: rules, caps,
  or the work class used for admission.
