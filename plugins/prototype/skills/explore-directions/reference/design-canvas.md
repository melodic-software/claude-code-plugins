# Design-canvas alternative (bundled `design` skill, run by the person)

When the intent selector lands on the HTML mockup substrate, tell the user before building that
the design canvas is an alternative they can run themselves, using the suggest sentence in the
[SKILL.md](../SKILL.md) section "Boundary, the bundled `design` skill". The bundled `design` skill
is reserved for the person to run; this skill never invokes it and never switches silently. This
skill builds the HTML mockup either way:

- **HTML mockup (built either way)**, the throwaway `file://` page [SKILL.md](../SKILL.md)
  describes; nothing persists.
- **Design canvas**, run by the user as `/design <scope>`: it drafts the variants as artboards on
  one canvas, published as a Claude Design Artifact. Name the lifecycle difference in the offer:
  the canvas is a published, persistent Artifact. Default-private, shareable with teammates at
  the user's choice. Unlike the throwaway local mockup, losing variants persist on it unless the
  user deletes or re-seeds the canvas. The user edits artboard elements in a desktop browser,
  edits save automatically, and each artboard exports as PNG or PDF. These user-run, hand-editable
  artboards have no structured decision capture; [review mode](../SKILL.md#review-mode) collects
  per-screen decisions from several reviewers and reads back a compiled report.

The capture discipline is unchanged either way: record the winning-variant key and notes in
your durable answer; the canvas may live on under the user's account, but nothing tracked in
the repo references it. The surface facts and their verified-on record live in
[bundled-design.md](bundled-design.md).

**Verification record, `design`.** Claim: the bundled `design` skill registers as
model-invocation-disabled, user-invocable, and gated, and settings can remove it
(`disableBundledSkills`, or a `skillOverrides` entry naming `design`). Basis: a binary extraction
of Claude Code 2.1.285 on 2026-09-29 (the `design` registration reads `model_invocable` false,
`user_invocable` true, `gated` true); the `disableBundledSkills` and `skillOverrides` rows on
<https://code.claude.com/docs/en/settings-reference>, fetched that day; the canvas gates per
[bundled-design.md](bundled-design.md). As of 2026-09-29. Recheck when a
release makes the `design` registration model-invocable, changes its description (the identity
string the offer quotes), changes its gating, or splits or merges its registrations.
