# Return-accounting capture slice

Wires the capture-enabled state of
[`${CLAUDE_PLUGIN_ROOT}/reference/return-accounting.md`](${CLAUDE_PLUGIN_ROOT}/reference/return-accounting.md),
discovery-first. Everything wireable lands as reviewable changes; GUI-only or
entitlement-gated surfaces get advisory steps with cost surfaced.

1. **Detect the tracker class and close-flow surface** — which tracker the org's work items
   live in, whether it supports native custom fields at the org's entitlement, and where the
   task-boundary close flow is machine-editable (close-triggered workflow, tracker
   automation).
2. **WIRE where machine-editable + reviewable** — a close-triggered snippet
   ([`templates/return-capture.md`](../templates/return-capture.md)) posting the UNATTESTED
   record + the attestation request addressed to the accountable human; the close flow never
   blocks. Native-field write where entitled AND provenance-verifiable per the contract's
   record-integrity rule — setup verifies, before selecting `native_fields`, that record-field
   writes are ACL-restricted to the bound automation identity or that the tracker exposes a
   queryable field-audit trail attributing writes; entitlement alone never selects the
   surface, because unverifiable field authorship would let a manual edit pass as an
   authentic attestation — the marker-keyed structured comment otherwise (the universal
   floor, which carries authorship structurally). Entitlement is
   detected at the org's plan level and does NOT confirm the complete v1 record field set is
   provisioned and attached on the item surface — a disclosed v1 limitation this slice does
   not detect: a tracker entitled for custom fields yet missing one or more of the v1 record
   fields cannot hold a conforming record on native fields, so full-field-set
   discovery/provisioning is future work; the universal comment floor stays conforming
   regardless. The trigger is
   GATED to autonomous-class work (the convention's capture scope): the snippet fires only
   when ALL THREE hold — the closing item carries the tracker binding's autonomous-eligible
   role label (the class-scope discriminator; the label marks pickup eligibility, not that
   the work was actually executed autonomously), AND the close event's actor is the bound
   automation identity (the execution-evidence discriminator; proves the closing action
   itself was autonomous), AND the closure outcome is COMPLETED/delivered — a not-planned,
   cancelled, or duplicate closure never captures, even when the automation performs it
   (nothing was delivered, so a record would assert autonomous completion of undone work). Neither alone suffices: the label without automation-actor
   closure would let a human who completes and closes an eligible item post a false
   autonomous record; the automation actor without the label would let interactive items
   the bot closes leak into capture. An unlabeled item, or one closed by any other actor,
   never enters capture (interactive work, and human-closed eligible work, both stay
   exempt). Label-plus-automation-actor closure is itself a PROXY for execution evidence,
   not a bound dispatch record: a close action run by the automation identity after a human
   performed the underlying work is not distinguished from one following genuine autonomous
   work by this gate alone. A first-class dispatch/execution-provenance signal is future
   work the guardrail matrix owns — this interim gate is deliberately the cheapest signal
   available today, not a claim of proof, and the discriminator recorded here is the interim
   boundary, not a parallel class vocabulary. The class-scope label gate resolves the
   autonomous-eligible label from the work-items tracker binding; the standalone path (no
   such binding) has no source for that label and the `capture` binding carries no
   label-mapping key — a disclosed v1 limitation: on that path setup neither assumes a
   default label nor silently omits the gate, so standalone gated capture stays advisory
   until an equivalent label/marker convention is bound, which is future work.
3. **WIRE the reply-triggered attestation handler where machine-editable** — a companion
   comment-created event handler, wired the same reviewable way as the close trigger (a
   native-field-change trigger surface is NOT a substitute: the only defined human input is
   the reply — `partial, 1-4h` or the `attest:` form — and v1 defines no native field-edit
   submission protocol carrying the two values, so a tracker with field-change automation
   but no comment-created surface routes to the ADVISE step like any other
   reply-triggerless tracker): on a new reply, check the reply's actor against the record's
   `attestation_owner` snapshot (resolved once at close; never re-resolved from a mutable
   source, per the contract), require the contract's reply-correlation rule (the event responds to the
   recorded `attestation_request`, or carries the flat-tracker `attest:` token — an
   incidental parseable comment never attests), and on a parseable reply carrying both
   values, upsert the SAME attested record
   (not a second contract — this is the one attestation upsert, wired from its own trigger
   surface) — branched by `record_surface`: on the comment floor, find the marker comment
   AUTHORED BY THE BOUND AUTOMATION IDENTITY and edit it in place (the lookup filters by
   author per the record-integrity rule — a foreign-posted marker is ignored, never
   selected or allowed to shadow the real record — and the bot-authored marker's absence
   enforces the contract's attestation-never-creates rule structurally: no close-time
   record, nothing to edit); on native fields there is no
   marker, but the same rule binds — the handler MUST first verify the close-time
   UNATTESTED v1 record is already present on the item's fields (written by the close
   trigger, which owns the eligibility gate) and treat its absence as inadmissible; where
   the surface was selected on the audit-trail alternative (fields not ACL-restricted),
   presence is not enough — the handler confirms through the trail that the bound
   automation identity created the record AND authored every subsequent revision of the
   record fields (any field-writer could forge a conforming unattested set, or alter an
   existing one — `attestation_owner`, `counterfactual` — after creation; a record with any
   non-automation revision is non-conforming and rejected before the owner snapshot is
   trusted) — only then writing the attested fields directly on that same item (the
   fields are scoped 1:1 to the closing item, so no lookup beyond that verification is
   needed). Where the tracker offers no reply-triggered surface (no comment webhook, a
   plan/tier limit), this step routes through the ADVISE step below instead of silently
   wiring only the close half and calling capture complete.
4. **Route comment writes through the bound tracker adapter's documented comment mechanics
   where a work-item-tracker binding is present** (comments are provider-specific mechanics
   there, not a race-safe seam — only coordination claims are race-safe; no marker upsert
   primitive exists to reuse). The marker-keyed upsert and its attestation-preserving dedupe
   rule are THIS contract's own obligations and apply identically on both paths; the
   standalone snippet differs only in posting directly, and both paths carry the contract's
   stated create-create race rule.
5. **ADVISE where GUI-only or entitlement-gated** — org-gated native fields, plan-gated
   automation: steps + cost surfaced, explicit opt-in. Private-repo close- and
   reply-triggered runs draw metered CI minutes — surfaced on the wire path.
6. **Attestation routing** — the binding records the accountable-human routing per class:
   the requester-identity source for ordinary (requester-carrying) items — which
   tracker-class-specific identity IS the requester (item author, a named custom field);
   never guessed from `tracker_class` alone — and the standing attestation owner (or
   attestation-exempt marking) for requester-less classes. Setup VALIDATES that every
   declared `standing_owner` is a human platform account distinct from
   `automation_identity`, and the close trigger applies the contract's human-owner rule to
   each resolution: a bot/app or automation-matching identity produces no owned record —
   route to the class's standing owner, else that item's capture stays advisory
   (self-attestation would bypass the never-estimate rule). An attestation-exempt class's close trigger posts NEITHER the
   unattested record NOR the attestation request — `return-accounting.md` forbids a
   perpetually-unattested default, so an exempt class's cost is reported separately,
   outside this record schema entirely.
7. **Record the binding** — the `capture` section of the schema-versioned binding (additive,
   like the telemetry section), with these serialized keys:

   | Key | Value |
   |---|---|
   | `tracker_class` | string, the detected tracker class |
   | `record_surface` | `native_fields` \| `comment` — which surface step 2 wired |
   | `automation_identity` | the bound automation's platform identity — checked by step 2's trigger gate and by `return-accounting.md`'s record-integrity rule; MAY be null (undiscoverable and not yet interviewed — never invented, same as `roles`) |
   | `requester_source` | how the accountable requester's platform identity resolves from an ordinary (requester-carrying) item in this tracker class — a tracker-specific identity source such as the item-author field or a named custom field; step 3's reply handler addresses the attestation request to it and validates the attesting actor against it; MAY be null (same ladder) — unbound means the actor check for ordinary items cannot be wired, so their attestation stays unwired and reported, never guessed |
   | `routing` | object keyed by a per-surface identifier for each requester-less recurring surface (standing routines, scheduled sweeps) — the bound work-item tracker's own recurring-schedule row id where that binding exists, else an identifier the setup interview asks for and persists. The key must be resolvable FROM THE CLOSING ITEM per the contract's routing rule: setup verifies the surface's filing template stamps the identifier on each item it files (item-body marker, label, or field — the stamp mechanism recorded alongside the entry), wires the stamp in as a reviewable change where the template lacks it, and leaves the entry unwired-and-reported where the surface cannot stamp (never title-match correlation); each entry is `{"standing_owner": "<platform-identity>", "role": "reviewer" \| "maintainer" \| "other"}` (`role` optional, default `other` — the value the reply handler derives `attestor_role` from on a standing-owner match, per the contract's derivation rule) or `{"attestation_exempt": true}`. A class with a requester needs no entry — the requester IS the routing, resolved through `requester_source`; the whole key MAY be absent when the org has no requester-less autonomous-eligible class yet |

   A binding missing the `capture` section has not wired this slice (absent-section
   tolerance, same as telemetry). `tracker_class` and `record_surface` land once step 1
   detects them; `automation_identity`, `requester_source`, and `routing` follow the SAME
   convention-resolution ladder as every other binding value (config present → use it;
   absent → infer, but ONLY from a signal that verifies the value's defining property;
   cannot infer → interview when `apply` runs interactively, else record null/unbound) —
   NEVER invented. For `requester_source` the tracker's documented item-author semantics
   qualify as such a signal. For `automation_identity` — a TRUST ANCHOR — usage history
   never qualifies: a recent close-event actor may be a human maintainer or an unrelated
   integration, and persisting it would make the close-actor gate pass for human-closed
   items, asserting autonomous completion falsely; only provider-verifiable identity
   metadata (the platform marks the account as an app/bot identity) or an explicit
   configured/interviewed value binds it. Unbound values are never a reason to block a
   non-interactive run or leave the section silently unwired: an unbound
   `automation_identity` means step 2's trigger gate cannot fire yet, and an unbound
   `requester_source` means ordinary-item capture stays ADVISORY on BOTH halves — the close
   trigger too, not just the reply handler, since a close-time record requires the resolved
   `attestation_owner` snapshot and an addressed request (an unowned record could never be
   attested); requester-less surfaces with resolved routing entries may still wire — each
   unbound value is reported, not hidden.
