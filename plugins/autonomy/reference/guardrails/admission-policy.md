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

An item with no stamped class is evaluated with the work-class axis `"*"` once the
[`C5` trust tests](work-classes.md#executable-provenance-tests) have run: it matches only
rules whose work class is `"*"`. An item those tests mark untrusted is `C5`
(trigger-dispatch rule).

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
| `"*"` | `"*"` | `C5` | `human-gated` |
| `channel-feed` | `"*"` | `"*"` | `human-gated` |

The shipped rows apply beneath the binding's own rules: where no binding rule matches an
item, a shipped row that matches it decides, so a binding need not restate them.

Default disposition where no rule matches, binding or shipped: `autonomous-eligible`, within
caps.

- The two shipped rows are trust holds, not class gates: `C5` is the untrusted-provenance
  class the [work-class trust tests](work-classes.md) assign, and a `channel-feed` signal
  carries no class unless the binding classifies that surface, so its surface row holds
  it. A binding rule more permissive than either needs an `override_justification`; once
  the binding classifies `channel-feed`, that includes a wildcard-surface rule binding a
  work class.
- Every other item that clears the trigger-dispatch trust holds (an unverified routine
  identity or `agent-internal` parent) is autonomous-eligible within caps REGARDLESS of
  provenance: blocking
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

## Intake admission charge terms

Intake admission refuses an issue whose stated work names a charge term, matched as whole words
outside fenced code blocks and inline code spans, which name jobs and files, not charges; a
backslash-escaped backtick opens no span. The charge terms: billing, billed, spending limit,
subscription (but not a subscription login, usage of the subscribed model vendor's subscription,
or a measured pass run on the subscription, which are model usage, not cost; a change to or
purchase of that subscription, and another vendor's subscription usage, still refuse), SKU,
retention, a larger or self-hosted runner, seat, Codespaces, a paid plan, top-up, auto-renew,
auto-reload, extra usage. A hosted runner and macOS minutes refuse unless the repository's
visibility reads public, where the forge's standard hosted runner minutes are free. Work that adds
or raises a charge waits for the owner unless an owner-recorded decision already covers it, and
that check is a person's, not intake admission's.

Intake admission applies the charge terms to what the issue will do rather than to its
background: the title and the body's task items and sections under a heading the definition's
`work_headings` names, each up to the next heading at its level or shallower (`#` headings only),
or the whole body when it has neither. A charge named only under another heading on such a body
does not refuse there, and no comment is read.

Because code is not read, intake also holds an issue, for the owner, when an edit moved a charge
term from prose into code: a comparison of adjacent revisions of the body, and of title renames,
for a term the text still holds in code. The hold names the edit and the term. A deleted revision,
or a history past one page, holds too. A history that fails to read, or a body edited between the
two reads, refuses without a hold: no person answers it, and intake dispatched again judges it anew.

## Binding and fail-closed behavior

- Serialization home: the security binding's `admission` object, holding the decision-table
  rules, the caps, and the signal→work-class classification rules adapters stamp from.
  The binding schema is contract-owned and ships with the security binding; this leaf
  owns the semantics it serializes.
- An ABSENT or invalid admission binding fail-closes at the seam: everything enqueues
  `human-gated` (the trigger-dispatch contract's absent-binding clause).
- No repo-local (agent-writable) surface may supply any admission input: rules, caps,
  or the work class used for admission.
