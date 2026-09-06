# Split brevity triggers by whether the phrase names an artifact

- Status: accepted
- Date: 2026-09-06

## Context

The `writing` plugin ships `writing:be-concise`, whose bare invocation sets a standing
posture: reshape every piece of reader-facing prose for the rest of the session.

`discipline:tighten-your-output` already holds a standing brevity posture. It carries
`discipline-batch: core` with rank 110, so it auto-loads in every session, and its
description claims nine trigger phrases including `'be more concise'`, `'too verbose'`,
`'say it in fewer words'` and `'cut the wordiness'`.

Two standing postures competing for the same words is unroutable. Boundary prose cannot
resolve a same-phrase collision: whichever skill the phrase reaches first wins, and the
reader has no way to steer. The collision surfaced during the plan review, after the
interview had already settled that the new skill would carry both modes.

Three options were live. Drop the new skill's posture mode and make it target-only.
Keep both postures and accept the overlap. Or migrate the vocabulary so each phrase has
one owner.

## Decision

Migrate the vocabulary. Each brevity phrase gets exactly one owner, split on a single
question: **does the phrase name the output in front of us, or an artifact a reader will
open?**

- Names the output in flight, or names no artifact at all, so its default target is the
  conversation: `discipline:tighten-your-output`.
- Names a ticket, a pull-request body, a doc, a status update, or the person who will
  read one: `writing:be-concise`.

The table lives in `discipline:tighten-your-output`, the skill giving phrases up. It has
15 rows and it moved zero phrases, because applying the criterion strictly, none of
`tighten-your-output`'s nine names an artifact, and every artifact-naming phrase was
already claimed by the new skill. The two vocabularies are disjoint by construction
rather than by negotiation.

## Consequences

A future reader will find `discipline:tighten-your-output` still claiming
`'be more concise'` while a skill named `be-concise` exists, which looks like an
oversight and is not. The criterion is what settles it: `'be more concise'` is a register
directive on the conversation, not a request to reshape a document.

Two closest calls are recorded rather than hidden. `'be more concise'` and
`'cut the wordiness'` could defensibly move, since the first near-verbatim names the new
skill and the always-resident skill wins ties on arrival. They stayed because both are
register directives, and both skills now route by target at the pointer, so a
phrase arriving at the wrong skill self-corrects.

A cross-plugin phrase move is also structurally expensive. `check-skill.sh` check 3
scans only siblings under the same skills root, so moving a phrase to another plugin
reads as a dropped trigger and hard-fails the gate even when the receiving description
gains it. Any future migration between these two skills pays that cost and should budget
for it.

The criterion generalises. A third brevity-adjacent skill would be placed by the same
question rather than by another round of negotiation.
