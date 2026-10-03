# Changelog for the Rendered Views Convention

Notable changes to the rendered-views contract. The contract is not
versioned; this log records each change to it.

## The Claude-interactive tier opens to builder pages, 2026-10-03

- **`session-bridge` meets rule 9, and the triage board and plan view adopt the tier (#5868).** Every wait
  answer now carries the untrusted-content framing contract as its data note. The bridge's new view app
  hands the token only to same-origin page script, so it never enters the page's markup, ends itself and
  its token 600 seconds after the session's watcher last waited, and takes page
  actions holding only builder keys, row ids and the reader's notes. The builder's `--connect` adds one
  `connect-src` naming the loopback origin, which the validator checks. The tier stays closed to
  model-written pages. Rules 3 and 9 and View tiers record the change.
- **Rule 9's token wording states what the code does.** The token is minted per server run, and the
  server exits `IDLE_SECONDS` after the session's last wait (and on stop). The view app also matches
  its validators in full, so a trailing newline no longer passes, and refuses a data dir that is not
  owned by the user or is open to group or other.

## The digest lane is `review:explain-change`, 2026-10-03

- **`review:pr-explainer` is renamed `review:explain-change` (#1217).** The digest lane
  builds an interactive page through the shared builder from a checked-in template, ships
  `medium: file`, and keeps the planned `artifact` default behind its own review. The
  escape-helper bullet and the thin-skill example name the new lane.

## The first interactive emitter, 2026-10-03

- **`education:illustrate` replaces `education:eli5` on the escape-helper emitter list
  (#5858).** It builds its page through the shared builder's interactive profile, from a
  checked-in template plus the explainer model as JSON data, and writes the markdown
  record from the same model.

## The map-* skills offer views on the builder, 2026-10-03

- **The `architecture` `map-*` skills offer interactive views built by `lib/view-builder.mjs` (#5863).**
  One checked-in template plus the skill's JSON record as data, through the interactive profile, with the
  destination taken from the `medium` key. The markdown and the record stay the record.

## Post-mortem and blindspot views on the builder, 2026-10-03

- **`debugging:debug` and `discovery:blindspot` offer interactive views built by `lib/view-builder.mjs` (#5864).**
  Each view is a checked-in template plus the session's JSON as data, through the interactive profile, with
  the destination taken from the `medium` key. Log, error and repository text reaches the page only as data.

## Plan and brainstorm views move onto the builder, 2026-10-03

- **`planning:plan` and `planning:brainstorm` offer interactive views built by `lib/view-builder.mjs` (#5866).**
  Each view is a checked-in template plus the session's JSON as data, through the interactive profile, with the
  destination taken from the `medium` key. The model-written HTML offer in both skills is gone.

## The shared builder ships, 2026-10-02

- **`lib/view-builder.mjs` and `lib/view-runtime.js` implement both validator
  profiles (#5852).** The builder fills a report template's slots with escaped text,
  or puts an interactive page's data only in the JSON data block and inlines the
  runtime under a policy that pins it and the page's style by hash. It refuses any page
  that fails its profile. A lane whose context holds K2 text may now emit through it.
  Rule 7 records what publishing the sample showed: the artifact host wraps the page,
  so the page's policy meta is not applied there, and the host blocks downloads.
- **Six clarifications from the #5875 security review.** Rule 7 forbids the runtime
  from writing a data value to any attribute, URL, or selector. Rule 5 makes ids
  opaque tokens never derived from data and bans pre-filling a form control from
  data. Rule 4 allows `<a href="#id">` and a runtime-created `blob:` download anchor.
  Rule 2 says the runtime reads the data block only with `JSON.parse`. Rule 8 names
  the marker string for each profile and falls back to the report profile for any
  other. A record outside the repository keeps K0 or K1 only with a
  `content-class` provenance line, and a K0 or K1 page inlines its fonts and scripts.
- **Rule 5 refuses bindings outside page text.** No `data-rv-*` binding on `html`,
  `head`, `title`, `meta`, `style`, or `script`, and no content binding on a form
  control, so data cannot become CSS inside the artifact host, where the page's policy
  is not applied.

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
  intent-named skills allowed". The pull-request digest takes `medium: artifact`
  as its default once its own external-publication review signs off.
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

## Generated helper copies, 2026-10-02

- **Each adopting plugin's `lib/html-escape.mjs` is generated output (#5836).**
  `scripts/sync-shared-copies.sh` writes it from the canonical with a generated-file
  header and drift-gates it, replacing `scripts/sync-html-escape.sh` (ADR 0019,
  amended). No boundary-rule, genre, or cascade-key change.

## Sharing claim and chrome background, 2026-10-02

- **The sharing paragraph records the repository decision plus a pointer**, an as-of date and a
  recheck trigger, in place of the earlier "verified absent" claim. It states no upstream text.
- **The chrome's ivory background is the sanctioned default.** No skill's styles-to-leave-out
  list names a cream or off-white background; those lists name layout habits. Carve-outs for
  pull-request diffs, fetched content and other repositories' files now read "until the lane is
  wired through the escape helper", not "until the helper ships". No boundary-rule, genre, or
  cascade-key change.

## Education lanes on the escape helper, 2026-10-02

- **`education:eli5` and `education:teach` in codebase mode build their HTML with a checked-in
  builder (#5845).** Each routes every interpolated repository string through the synced
  `lib/html-escape.mjs` and stamps the generator marker. `education:eli5` joins the emitter list
  as an escape-helper lane; `education:teach` stays grandfathered for topic mode. No
  boundary-rule, genre, or cascade-key change.

## Three more lanes on the escape helper, 2026-10-02

- **`knowledge:video-digest`, `harness-ops:observability` and `event-storming:simulation` build
  their HTML with a checked-in builder (#5846).** Each routes every interpolated external string
  (fetched transcripts and titles, telemetry strings, board text) through the synced
  `lib/html-escape.mjs` and stamps the generator marker. The two that were grandfathered
  (`harness-ops:observability`, `event-storming:simulation`) leave that list; the escape-helper
  lanes are named in the emitters paragraph of the README. No boundary-rule, genre, or
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
