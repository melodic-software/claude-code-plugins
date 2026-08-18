# design-skill-integration

## Brief

### TLDR

Offer Claude Code's bundled `design` skill (Claude Design canvas preview — multi-artboard
`.dc.html` canvases published as editable Artifacts) as a presence-gated output option in
`prototype:explore-directions` and `visualization:visualize`, following the repo's seam-phrasing
convention, with all supporting surfaces (context spokes, discipline doc, READMEs, changelogs,
versions) updated. Decisions were interviewed, then adversarially validated by two independent
fresh-context validators against the shipped binary, official docs, and repo conventions
(research: `.work/design-skill-integration/RESEARCH.md`, verifier PASS).

### Goal

A user of either host skill in a session where the bundled `design` skill is present can choose
a design canvas as the visual output — hand-tweakable artboards published as an Artifact — while
every session where the skill is absent behaves exactly as today.

### Constraints

- **Presence-gated, always.** The bundled skill is a triple-gated research preview (server-side
  `tengu_ethereal_nova` flag + first-party context + Artifact `capabilities` support), absent
  from docs and changelog; no version floor is statable. Every reference carries gate + fallback
  per `docs/conventions/seam-phrasing/README.md`.
- **Two-state fallback branch (validator-required).** Attempt model invocation only where
  `design` is listed in the session's skill roster. Absent from the roster → the existing
  mechanism, silently (never suggest `/design`; that user does not have it). Listed but the
  invocation is refused (a future invocability gate — the `/verify` precedent) → suggest the
  user run `/design`.
- **Honest lifecycle wording (validator-corrected).** The offer site names the difference:
  a published, versioned, persistent Artifact — default-private, shareable with teammates at the
  user's choice — vs the repo's throwaway local/ephemeral HTML. Never "org-visible" (factually
  wrong: Artifacts start private). Never promise hand-editing unconditionally — saving is
  per-account; the degrade is view + PNG/PDF export.
- **Opt-in, never a silent default.** Existing mechanisms (HTML mockup substrate, current
  routing rows) remain the defaults; the canvas is an explicitly offered alternative.
- **Phrasing per host idiom.** `visualize`: capability-shaped routing row whose capability noun
  embeds the resolvable name ("a design-canvas capability — the bundled `design` skill, when
  available"), with `/design` named in the gate text. `explore-directions`: named-skill
  reference (bare `design`; no namespace exists for bundled skills).
- **Four-part volatility stamp per touched skill** (claim, basis, as-of date, observable
  trigger) per `docs/conventions/upstream-drift/README.md`; the trigger covers BOTH first
  official naming (changelog / commands reference) AND bundled-skill invocability changes.
- **No verbatim quotes from the X announcement** (SERP-captured, unverifiable from this
  container); phrasing derives from the skill's own roster description (Tier 0).
- **Bind-on-touch obligations honored:** `plugins/visualization/skills/visualize/`'s
  decision-matrix spoke owns rendering-surface facts (no restating in SKILL.md), and its
  pending canonical-name adoption note binds when the surface is edited.

### Acceptance criteria

1. `plugins/prototype/skills/explore-directions/SKILL.md` offers the canvas at the
   HTML-mockup substrate branch point as an explicit question/option; the HTML mockup substrate
   is kept alongside as the absence fallback (replace ruled out); the two-state fallback branch
   and lifecycle wording appear at the offer site; a four-part stamp is present.
2. `plugins/visualization/skills/visualize/SKILL.md` (+ its decision-matrix spoke) gains a
   form row for hand-tweakable visual layout routed to the existing artifact medium — no new
   `medium` config value — with capability-shaped phrasing, name embedded, gate + fallback, and
   a four-part stamp.
3. `plugins/prototype/context/discipline.md` carries a substrate-scoped exception so the
   canvas's persistent published Artifact (explicit user opt-in) does not contradict
   "no persistence by default / delete when done".
4. Both skills' frontmatter descriptions mention the canvas option in a minimal subordinate
   clause (no change to trigger intents).
5. Release mechanics per repo convention: semver bumps + changelog entries in both plugins,
   README substrate/media lists updated, marketplace version references consistent.
6. In a session without the `design` skill, both skills' instructions resolve to today's
   behavior with no reference to running `/design`.

### Captured assumptions

- The bundled skill is model-invocable where enabled (binary-verified v2.1.234: registration
  carries `userInvocable:!0`, no `disableModelInvocation`; both validators re-extracted this
  independently). Volatile axis — covered by the stamps' invocability trigger.
- Dead-text exposure is accepted: the option is latent (never broken) on Bedrock/GCP/Foundry/
  AWS, headless SDK/CI/MCP, flag-off accounts, and policy-disabled orgs; it is live in this
  org's cloud sessions today. Cost is one dormant conditional per site — the price seam-phrasing
  already accepts for dataviz/artifact-design/Miro gates.
- Q7, Q8, Q10 (description clauses, discipline.md exception shape, visualize taxonomy
  placement) were resolved with recommended answers under the user's standing
  "validate, then go with your recommendations" directive — overridable at PR review.

### Out-of-scope

- `ai-briefing:generate --format canvas`, `planning:prd` pitch view, event-storming degrade
  target — deferred post-V1 (each independently justified; prd's pitch view may be permanently
  out: its own text forbids an editor view).
- A shared design-canvas reference doc — extract only when a later pass takes the touched-site
  count past two (upstream-drift's repeated-derivation signal; shared repo docs are unreachable
  from independently installed plugins anyway).
- Any change to `${user_config.medium}` recognized values.

### Deferred questions

None — all ten register rows answered (see `.work/design-skill-integration/interview-checklist.md`).
