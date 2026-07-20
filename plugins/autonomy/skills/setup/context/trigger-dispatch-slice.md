# Trigger/dispatch slice

Wires the signal-adapter and dispatch state of
[`${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md`](${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md),
discovery-first. Everything lands as reviewable changes; plan-gated surfaces are advisory +
explicit opt-in with cost surfaced. Vendor event names and invocation flags live in THIS
slice and its templates — the contract stays surface-class vocabulary only.

1. **Discover signal surfaces per class** — interview + repo/org inspection for which of the
   contract's four surface classes exist here, the transport each surface actually offers
   (`push` / `push-lifecycle` / `poll`), and entitlements. Per-org absence of a class is a
   binding outcome, never a blocker; an entitlement gap routes that surface to the advisory
   step. The contract's carried research gaps are re-verified at wire time against current
   vendor docs (fresh-docs mandate), not assumed still true.
2. **Wire the DIY floor as reviewable changes** — the kick and the drain:
   - *Kick* (`tracker-vcs-event`): a platform event workflow on the tracker/VCS host running
     the adapter shape from
     [`templates/trigger-adapters.md`](../templates/trigger-adapters.md). Marked example, on
     the GitHub Actions class of CI: `issues` (types `labeled`, `assigned`),
     `issue_comment` (type `created`) for @-mention forms, `pull_request` for PR events —
     all verified against the official events reference at wire time; event-trigger
     workflows must exist on the default branch to fire.
   - *Drain* (`temporal`): a scheduled workflow invoking the queue drain. Marked example:
     `schedule` cron (shortest interval 5 minutes; runs may be delayed under load; public
     repos auto-disable schedules after 60 days without activity — surface both caveats)
     plus `workflow_dispatch` for manual kicks. Poll-detector backstops for
     `push-lifecycle` wirings ride the same scheduled surface.
   - *`channel-feed`* (where wanted): a chat-platform bot + events subscription, or a plain
     inbound webhook receiver, normalizing into the same adapter shape — DIY floor only;
     vendor-hosted channel agents are step 3's advisory path.
   - *`agent-internal`*: no wiring — sessions file follow-up work through the queue seam
     directly; the slice records the surface as active and states the `signal.parent_item`
     provenance obligation.
   - *Executor invocation* (marked example, self-operated CLI class): headless `claude -p`
     with `--bare` for deterministic CI context, tool allowlisting via `--allowedTools` /
     `--permission-mode` — verified against the official headless reference at wire time.
3. **Advise plan-gated native integrations** — vendor-hosted channel agents and native
   tracker automations that carry a plan/seat cost: steps + cost surfaced, explicit opt-in,
   never the default path. Zero paid dependencies on the default path.
4. **Bind the drain cadence** — default hourly, org override recorded in the binding. The
   drain funnels into the work-item queue capability's autonomous drain mode via the
   invocation-adapter seam — one entrypoint, no second dispatch mechanism; the seam's
   race-safe lease makes concurrent kicks harmless.
5. **Record execution surfaces** — EVERY kick/drain wiring records its named execution
   surface id, the same id the guardrail security binding's per-surface isolation entries
   key on. The recorded id is repo-local (agent-writable) convenience only: per the
   contract's execution-surface attestation rule, the admission/executor seam derives the
   ACTUAL surface identity from platform-attested runtime metadata and verifies it against
   the recorded id — a mismatch, an unattestable surface, or a surface without an L2+
   isolation binding fail-closes to human-gated. The slice states this next to every
   recorded id so no reader mistakes the record for the enforcement.
6. **Admission enforcement wiring** — every adapter shape points at the guardrail admission
   seam (the admission policy bound on the org's security governance surface). With NO
   admission binding present the wiring fail-closes: every signal enqueues human-gated,
   never dropped, never auto-dispatched. This slice wires the enforcement point; it never
   defines policy content.
7. **Record the binding** — the `triggers` section of the schema-versioned binding
   (additive, absent-section tolerance, no major bump), with these serialized keys:

   | Key | Value |
   |---|---|
   | `surfaces` | object keyed by surface id — each entry `{"class": "<surface-class token>", "transport": "push"\|"push-lifecycle"\|"poll", "scheduler_class": "ci-cron"\|"local-scheduler", "execution_surface": "<recorded execution-surface id>"}`; `scheduler_class` is REQUIRED on temporal surfaces (and only there) — the discriminator `signal.raw_link` form validation branches on; a `local-scheduler` surface using an org artifact store additionally declares `artifact_schemes` (array of URI schemes) — undeclared non-`file:`/non-`https:` schemes never conform. Any later additive section that records scheduling surfaces (routines) uses the same `surfaces` map shape, so envelope validation resolves `signal.source_surface` against every section uniformly |
   | `drain` | `{"cadence": "<schedule expression or token, default hourly>", "execution_surface": "<recorded execution-surface id>"}` |

8. **Conformance** — run
   [`scripts/check-signal-envelope.mjs`](../scripts/check-signal-envelope.mjs) against a queued
   item's body (with `--binding` pointing at the resolved binding) to verify the envelope
   marker record before declaring the wired state reached.
