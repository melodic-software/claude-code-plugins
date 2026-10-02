# Changelog for the Rendered Views Convention

Notable changes to the rendered-views contract. The contract is not
versioned; this log records each change to it.

## Tiers and content classes, 2026-10-02

- **Views gain tiers, content classes, and a validator profile (#5851).** Four
  tiers (static, client-interactive, animated, Claude-interactive), with
  person-facing views interactive by default and reports allowed to stay static.
  Content classes K0 (session-authored) and K1 (this repo's default-branch files)
  may use model-written script under a minimum CSP; K2 (attacker-controllable
  text, and anything derived from it) is builder-only: a checked-in template plus
  escaped JSON data. Model-written text and script are K0 only when the context
  that writes them holds no K2 text; otherwise the page is K2. The class rules
  bind every emitter now, grandfathered ones included; only their ladder and
  `medium` stay grandfathered. Until the builder ships, a lane whose authoring
  context holds K2 text emits the markdown record, terminal output, or a static
  report-profile page through `lib/html-escape.mjs`. The interactive
  validator profile is specified for the shared builder, with an exact
  script-body exemption, `base-uri` and `form-action` set to `'none'`, named SVG
  refusals, and a Claude-interactive rule whose framing, token, and gate bullets
  bind `session-bridge` for every message from every page. The
  Claude-interactive tier is closed to every class until `session-bridge` exists
  and meets that rule; the per-session token, not the origin, authenticates a
  page, since a `file://` page sends `Origin: null`. New rung guidance says when
  text beats a diagram, a page, or a video.
- **Three amendments.** The boundary rule now names video and audio as views and
  emits person-facing views interactive by default; dual-audience reports still
  offer. The generator-skill ban becomes "no generic HTML skill; thin
  intent-named skills allowed". The pull-request digest ships `medium: artifact`
  as its default.
- **Record bundle.** The new
  [record-bundle convention](../record-bundle/README.md) holds a record with its
  diagrams and media; views are written outside it. Its links stay inside the
  bundle, and an externally sourced SVG or diagram source in it is K2 and is
  never inlined as markup in a view.
- **Fourth security review.** Every copy, export, and download payload on a K2
  page holds to rule 9's first bullet (reader input plus builder-assigned ids,
  no Pattern 3 prompt or Pattern 5 record built from data-block strings), and
  text pasted or exported from a K2 page is K2. K2 SVG and diagram sources
  render as text or as builder-generated SVG, never as inlined markup. A
  subagent's request is K0 only when it is the user's own typed text; a brief
  from a parent context holding K2 text is K2. The K0/K1 meta CSP is the first
  element after the charset meta, and its policy is exact plus one permitted
  `connect-src` addition.
- **Fifth security review.** Operator-installed configuration is K1: the
  user's CLAUDE.md, AGENTS.md, and rules, installed plugins' skill and agent
  text, installed MCP servers' instructions, and harness status blocks. What
  those tools return during the task is K2. The fresh-subagent K0 example now
  counts that configuration as part of a K2-free context.

## Sharing claim and chrome background, 2026-10-02

- **The sharing paragraph records the repository decision plus a pointer**, an as-of date and a
  recheck trigger, in place of the earlier "verified absent" claim. It states no upstream text.
- **The chrome's ivory background is the sanctioned default.** No skill's styles-to-leave-out
  list names a cream or off-white background; those lists name layout habits. Carve-outs for
  pull-request diffs, fetched content and other repositories' files now read "until the lane is
  wired through the escape helper", not "until the helper ships". No boundary-rule, genre, or
  cascade-key change.

## Escape helper, 2026-09-28

- **The wave-2 escape helper shipped (#3605).** `lib/html-escape.mjs` is the
  canonical copy, synced into each adopting plugin at `lib/html-escape.mjs` and
  drift-gated by `scripts/sync-html-escape.sh`. Emitted pages carry a generator
  marker that `validateRenderedPage` checks. `/review:pr-explainer` is the first
  lane on that gate. Existing carve-outs that still do not render another
  repository's files stay in place until those lanes are wired through the
  helper. No boundary-rule, genre, or cascade-key change.

## Template vendoring, 2026-09-28

- **Whole-page vendoring of the 31 html-effectiveness corpus templates is
  declined (#3608).** The derived chrome/token reference remains the sanctioned
  shared piece. Per-genre page-shape is a pointer to the public gallery. A
  future single-page vendor must name which source it took (gallery Apache-2.0
  headers vs `anthropics/html-effectiveness` MIT) and carry the matching
  notice. No boundary-rule, genre, or cascade-key change.
