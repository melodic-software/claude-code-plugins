# Design-canvas alternative (bundled `design` skill, run by the person)

When the intent selector lands on the HTML mockup substrate, tell the user before building that
the design canvas is an alternative they can run themselves, using the suggest sentence in the
[SKILL.md](../SKILL.md) section "Boundary" (`design` row). The bundled `design` skill
is reserved for the person to run; this skill never invokes it and never switches silently. This
skill builds the HTML mockup either way:

- **HTML mockup (built either way)**, the throwaway `file://` page [SKILL.md](../SKILL.md)
  describes; nothing persists.
- **Design canvas**, run by the user as `/design <scope>`: it drafts the variants as artboards on
  one canvas, published as a Claude Design Artifact. Name the lifecycle difference in the offer:
  unlike the throwaway local mockup, the canvas persists, losing variants included, unless the
  user deletes or re-seeds it. How a canvas is shared, edited and exported is
  [Artifacts § Draft a design canvas](https://code.claude.com/docs/en/artifacts#draft-a-design-canvas).
  These user-run, hand-editable
  artboards have no structured decision capture; [review mode](../SKILL.md#review-mode) collects
  per-screen decisions from several reviewers and reads back a compiled report.

The capture discipline is unchanged either way: record the winning-variant key and notes in
your durable answer; the canvas may live on under the user's account, but nothing tracked in
the repo references it. The surface facts and their verified-on record live in
[bundled-design.md](bundled-design.md).
