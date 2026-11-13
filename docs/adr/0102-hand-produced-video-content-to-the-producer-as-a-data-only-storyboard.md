# Hand produced-video content to the producer as a data-only storyboard

- Status: accepted
- Date: 2026-11-13
- Refs: owner decision of 2026-11-13 (design thread T2, "go with recommendations")

## Context

The review plugin's reviewer-media skill turns a pull request into a narrated video, and `education:illustrate` will
feed the same producer. The producer, `explainer-video:produce`, renders with a still-frame renderer
(Chromium over HTML templates) or with manim. The content comes from pull request text, diffs and file
names, which are untrusted: any of it can carry markup.

## Decision

Callers hand the producer a `storyboard.json`, version 1:

- `{version: 1, title, chapters[{id, title}], moments[Moment]}`, with
  `Moment = {id, chapter, template, data, narration, covers[]}`.
- `template` names a frame template: `title`, `code-hunk`, `diagram`, `before-after`, `risk-map`,
  `also-changed` or `screenshot`. `data` is plain JSON that the template escapes; no caller writes
  markup.
- One moment is one narration paragraph and one held frame.
- The producer rejects at parse time an unknown template, an undeclared chapter, empty narration on
  any template but `title`, and an `also-changed` moment with empty `covers`.
- A `screenshot` moment needs a frame-text sidecar, or the producer refuses it, so the secret scan has
  text to read.
- The renderer is chosen by configuration, never by the storyboard.

### One-way doors

The storyboard is a public contract between plugins. A later change is additive under `version: 1`;
a breaking change needs `version: 2` and a new record.

## Considered options

- **Storyboard carries pre-rendered HTML per moment.** Rejected: every caller would write markup from
  pull request text, so escaping would move to each caller, and manim cannot consume HTML.

## Consequences

- Escaping lives once, in the frame templates (`lib/media-render/media_templates/`).
- Any producer caller, present or future, needs only the JSON contract, not the renderer.

## Revisit triggers

- A caller needs a moment shape that no template and no `data` field can express.
