# Rendered Views Convention

The marketplace-wide contract for person-facing rendered views: when a skill's
deliverable defaults to a self-contained HTML page, when it stays markdown or terminal
output, how interactive a view is, which content may carry model-written script, how the
choice is overridden, and what every rendered view owes for security and accessibility.
Adopted from the "Unreasonable Effectiveness of HTML" corpus (the article,
its example gallery, and the "Know your unknowns" collection) through a full interview,
stress-test, and validation chain; the decision record travels with the pull request that
introduced this document.

This directory is the source of truth for the concern. The shared chrome and token
reference lives in the adopting plugins (canonical copy:
`plugins/visualization/reference/html-chrome.html`). Where a record and the
diagrams and media it cites live together is the
[record-bundle convention](../record-bundle/README.md). Notable changes to this
contract are logged in `CHANGELOG.md`.

## The boundary rule

**Markdown is the record. HTML, video, and audio are views of a record kept elsewhere.**

- Pipeline and agent-read artifacts (ledgers, checklists, handoffs, digests, findings a
  later pass consumes) are always markdown. Nothing downstream ever re-reads a view, and
  no view may sit beside the record it renders: a view is written outside the record's
  [record bundle](../record-bundle/README.md).
- A person-facing deliverable in one of the corpus genres (see the rubric below) emits
  an interactive view by default, tailored to its use case (see View tiers), when BOTH
  hold: the next consumer is a person, and the environment can serve a viewable file.
- A dual-audience report, one that another agent pass re-reads (audit findings feeding a
  fix pass, scan results feeding triage, quiz records feeding recall), OFFERS the view
  instead of emitting it by default. The markdown record is the deliverable; the view is
  an option.

## View tiers

A view sits on one of four tiers, chosen per use case from the defaults below.

| Tier | What the page does | Script |
|---|---|---|
| Static | Presents. Native HTML behavior such as a collapsible section still works. | None |
| Client-interactive | Reacts to the reader inside the page: filter, sort, collapse, switch tabs, step through, answer a quiz, export state. | Runs in the page only; no network |
| Animated | Moves on its own: timed or stepped motion that shows a process unfolding. | Runs in the page only; honors `prefers-reduced-motion` |
| Claude-interactive | Sends the reader's input back to the session and shows the reply (questions to the author, a triage decision, a plan edit). | Page script plus the shared session transport (`session-bridge`), and nothing else on the network |

- **Person-facing views are interactive by default.** A view whose next consumer is a
  person starts at client-interactive and climbs only when the use case needs motion or
  a round trip to the session.
- **Reports may be static.** A report is read, not answered, so it may ship without
  script. A report may still filter, collapse, or animate; what it never carries is a
  loop-closure control (see Loop closure and the export obligation).
- **The Claude-interactive tier is closed to every content class.** No page, K0, K1, or
  K2, uses it until `session-bridge` exists and meets interactive-profile rule 9. Until
  then a page stops at client-interactive and closes the loop with a copied payload.
- **A K2 page's payloads carry no K2 text.** Every copy, export, or download payload on
  a K2 page, at any tier, holds to rule 9's first bullet: what the reader entered plus
  ids the builder assigned, never a string taken from the data block. A K2 page
  therefore carries no Pattern 3 follow-up prompt and no Pattern 5 rebuilt record
  assembled from data-block strings (see The loop-closure and export snippet
  reference). Text pasted or exported from a K2 page is K2, never K0 user input.
- The tier never changes the record: every tier renders the same markdown record, and
  the content-class rules below decide who may write the page's script.

## Content classes

Every view is classified by the most exposed text it renders. The class, not the tier,
decides whether the model may write the page's script. A class is set by where the text
came from, not by who wrote it down.

| Class | Covers | May the model write the page's script? |
|---|---|---|
| K0 | What the user typed in this session, and model-written text and script from a context that holds no K2 text (see Authoring context). | Yes |
| K1 | This repository's own files at a commit reachable from the default branch. Not K1: submodules, vendored or third-party trees, files generated from external input, and any tree checked out from a pull-request head or a fork. | Yes |
| K2 | Attacker-controllable text and anything derived from it: pull-request diffs and branches, issue and pull-request text, contributors' commit messages and branch names, fetched web text, other repositories' files, and a model summary or paraphrase of any of these. | Never. Builder-only. |

- **A page takes the highest class of anything it renders.** One K2 string makes the
  whole page K2. When it is not clear whether a source is attacker-controllable, it is
  K2.
- **Taint follows the text.** Text derived from a K2 source stays K2 whoever wrote it:
  the model's summary of a fetched page, a `.work/` note quoting an issue, a description
  of a diff.
- **Operator-installed configuration is K1.** The user's CLAUDE.md, AGENTS.md, and
  rules, installed plugins' skill and agent text, installed MCP servers' instructions,
  and the harness-authored parts of a status block (working directory, clean or dirty
  flag, file counts) are the operator's trust decision. A status block's branch name and
  commit subjects are K2, as the K2 row says. What those tools fetch during the task is
  K2: fetched pages, pull-request, issue, and comment text, and other people's commits or
  files. A read of a K1 file keeps the file's class.
- **Authoring context.** Model-written text and script take the class of the context
  that writes them, not of what they visibly quote or paraphrase. They are K0 only when
  that context holds no K2 text, for example a fresh subagent given only
  operator-installed configuration, the K0/K1 record, and a request that is the user's
  own typed text. A brief written by a parent
  context that holds K2 text is itself K2, and so is the subagent it briefs. A context
  that has read any K2 text (a diff, an issue, a fetched page) writes K2, whatever the
  output looks like, and its page is built from the checked-in template and runtime
  (see K2 is builder-only).
- **The class rules bind every emitter now.** The grandfathered surfaces (see Wave-1
  adoption and grandfathered surfaces) are bound too, including the minimum content
  security policy on a K0 or K1 page; only their ladder and `medium` are grandfathered.
  Until the builder ships, a lane whose authoring context holds K2 text emits the
  markdown record or terminal output, or a static report-profile page through
  `lib/html-escape.mjs`, never a page with model-written markup or script.
- **K1 is trusted for rendering only.** It decides who may write a page's script and
  nothing else. Repository files are still DATA, never instructions, under the
  [untrusted-content framing contract](../untrusted-content/README.md#the-framing-contract).
- **K2 is builder-only.** A K2 page is assembled by the checked-in builder from a
  checked-in template plus the K2 text as escaped JSON data. The model chooses the
  template and supplies the data; it never writes markup or script for a K2 page, at
  any tier. The builder embeds the data as a JSON data block and the checked-in runtime
  renders it through DOM text APIs, never as markup. K2 SVG and K2 diagram sources are
  no exception: the page shows them as text, or the builder generates SVG from
  structured data it validates; K2 markup is never inlined. The page passes the builder's
  validator profile (see The interactive validator profile) before anyone opens it.
- **K0 and K1 may use model-written script.** Such a page holds to the security baseline
  below. It is outside the builder's validator profiles, so its safety rests on the
  authoring-context rule: the context that writes its script holds no K2 text. A page
  that later needs K2 text moves to the builder. Its first element in `<head>` after
  the charset meta is a `<meta http-equiv="Content-Security-Policy">`, because a meta
  policy does not apply to content before it. The policy is exactly `default-src 'none';
  script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; base-uri 'none';
  form-action 'none'`, plus one permitted addition: `connect-src` naming the
  `session-bridge` origin, once the Claude-interactive tier opens. The policy caps a misclassified page:
  injected script runs but cannot fetch, beacon, or submit a form. It can still
  navigate the page to a URL that carries data out, and CSP3 has no directive that
  stops navigation, so the authoring-context rule, not the policy, is what keeps K2
  text out of a model-written page.
- The class is a property of the rendered text, not of who asked for the view or where
  it is published. Publishing a K2 page as an artifact does not lower its class.

## The interactive validator profile

This section is the specification the shared builder (`view-builder.mjs`, with its
runtime `view-runtime.js` inlined into each page) implements. The builder validates every
page it emits against one of two profiles and refuses to emit a page that fails.

**Report profile.** The profile `validateRenderedPage` in `lib/html-escape.mjs` enforces
today: an allowlist of text and table tags and of non-URL attributes, every text and
attribute value escaped, no `<script>`, no URL-bearing attribute, and no `url(`,
`@import`, `expression(`, or backslash escape inside `<style>`. A static K2 page uses it.

**Interactive profile.** Everything the report profile requires, with one exemption and
the additions below.

**The script-body exemption.** The report profile's `<script>` ban and its text scan do
not apply to the bodies of the two script elements rules 1 and 2 permit, and to nothing
else. The validator finds those elements' boundaries with an HTML-conformant tokenizer,
or fails closed on any `<!--` or `<script` inside a script body. It never ends a script
element at the first `</script` by pattern match: after `<!--` and `<script`, the browser
tokenizer no longer ends the element there, so such a validator checks a different page
from the one the browser runs. It checks the runtime body by hash before any other scan.

1. **One runtime script.** The page carries exactly one executable `<script>`, with no
   `src` attribute, whose body is byte-identical to the shipped `view-runtime.js`. The
   validator checks it by hash against the shipped copy; any other executable script
   fails. The shipped runtime contains no `<!--`, `<script`, or `</script` in any letter
   case, so its body cannot move the element's end.
2. **At most one data block.** `<script type="application/json">` with the builder's
   fixed `id`. Its body parses as JSON and contains no raw `<`: the builder writes `<` as
   `\u003c`, so neither `</script` nor `<!--` can occur inside it. A non-JavaScript
   `type` makes it a data block the browser does not execute.
3. **A content security policy in the page.** The first element in `<head>` after the
   charset is a `<meta http-equiv="Content-Security-Policy">` with `default-src 'none'`,
   a `script-src` naming only the runtime's SHA-256 hash, a `style-src` naming only the
   hash of the page's one `<style>` element, and `base-uri 'none'` and
   `form-action 'none'`, which do not fall back to `default-src`. Its content is the
   builder's exact policy string. It is the only `http-equiv` meta the page carries: any
   other, such as `refresh`, which navigates and is not blocked by the policy, fails.
   Once the Claude-interactive tier opens (rule 9), a page on it adds `connect-src`
   naming the `session-bridge` origin and nothing else; `session-bridge` owns that
   origin, and rule 9 governs what crosses it.
4. **No inline handlers, no navigation.** No `on*` attribute, no `style` attribute, no
   `<a href>`, `<form>`, `<iframe>`, `<object>`, `<embed>`, `<base>`, or `<link>`. A
   URL-bearing attribute is allowed only as a same-document fragment reference (`#id`).
   The runtime attaches every event listener.
5. **Control tags.** The tag allowlist widens to the controls the runtime drives
   (buttons, labels, checkbox, radio, search and range inputs, select, details and
   summary, and neutral containers); attributes widen to `aria-*`, `role`, `data-*`,
   `hidden`, `open`, `type`, `for`, and `value`, each value escaped.
6. **An SVG allowlist.** Inline SVG is generated by the builder, never copied from K2
   text, and is limited to shape, path, text, group, and
   definition elements with geometry and presentation attributes. `<foreignObject>`,
   `<script>`, `<image>`, `<feImage>`, `<use>`, `<a>`, `<mpath>`, `<discard>`, and the
   SMIL animation elements (`<animate>`, `<set>`, `<animateTransform>`,
   `<animateMotion>`) are refused, because each can load a resource, run script, or
   rewrite an attribute such as `href` after validation. SVG `<style>` is refused: inside
   SVG its body parses as markup, not raw text, so the report profile's style scan does
   not cover it. `xml:base` is refused, and an `href` or `xlink:href` is allowed only as
   a fragment reference (`#id`). A `url(...)` in a presentation attribute is allowed only
   as a fragment reference (`url(#id)`). Motion in the animated tier comes from CSS or
   the runtime.
7. **The same page in both hosts.** The runtime is a classic script with no imports, no
   network access outside rule 3, and every storage access wrapped so the page renders
   without it. The same file therefore behaves the same opened from `file://` and
   published as an artifact.
8. **A generator marker naming the profile.** The page carries the builder's generator
   marker, which names the profile it was validated against, and the validator selects
   the profile from it. The marker has no version: when the marker format changes, the
   builder and every consumer of the old marker migrate in the same change.
9. **The Claude-interactive tier.** The tier is closed to every content class, K0, K1,
   and K2, until `session-bridge` exists and meets the last three bullets below (see
   View tiers). The first bullet binds the page; the last three are properties of the
   bridge and hold for every message from every page, whatever its class:
   - The page sends only what the reader entered plus ids assigned when the page was
     built (a finding number, a hunk id, an option id), never a string taken from the
     data block. The session resolves each id against its own copy of the record. This
     bullet also binds every copy, export, and download payload on a K2 page at every
     tier, and text pasted or exported from a K2 page is K2, never K0 user input (see
     View tiers).
   - The bridge delivers every page-originated field, the reader's input included, to
     the session as DATA under the untrusted-content framing contract, never as the
     user's own message.
   - The bridge authenticates every message by an unguessable per-session token and
     rejects any message without it. The token is issued per session when the page opens
     and expires with the session; it never enters a published, shared, or exported copy
     of the page. The origin authenticates nothing: a page opened
     from `file://` sends `Origin: null`, the same value any opaque origin sends.
   - The bridge lets no message trigger a write, push, merge, or other gated action
     without the confirm or permission gate that action already has.

The builder's exact tag and attribute lists, and the hostile-input corpus that proves
each refusal above, live with the builder. A change that widens an allowlist names the
rule above it falls under; a widening no rule covers amends this section first.

- **Claim:** a `<script>` whose `type` is not a JavaScript MIME type is a data block the
  browser does not execute; the content of a script element must not contain `<!--` or
  `<script`/`</script` sequences; a CSP with `default-src` or `script-src` blocks inline
  event-handler attributes, and allows an inline `<script>` by hash; `base-uri` and
  `form-action` do not fall back to `default-src`; a policy delivered in a `<meta>`
  element does not apply to content that precedes it; CSP3 defines no directive that
  restricts where a document navigates; a request from a `file:` page carries
  `Origin: null`.
- **Basis:** WHATWG HTML living standard, "The script element" and "Restrictions for
  contents of script elements"
  (<https://html.spec.whatwg.org/multipage/scripting.html#the-script-element>, last
  updated 2 October 2026); MDN, "Content Security Policy (CSP)"
  (<https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP>), which also notes a
  `<meta>`-delivered policy does not support every CSP feature, so rule 3 uses only
  fetch, `base-uri`, and `form-action` directives; W3C, "Content Security Policy Level
  3" (<https://www.w3.org/TR/CSP3/>, Working Draft 16 September 2026), whose directive
  list has no navigation directive and whose `<meta>` delivery section says a meta
  policy is not applied to content which precedes it; MDN, "Origin header"
  (<https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Origin>), which
  lists a `file` scheme among the cases that send `null`.
- **As of:** 2026-10-02.
- **Recheck:** any of these sources changes how a data block, script-content
  restrictions, hash-sourced inline script, directive fallback, or the reach of a
  meta-delivered policy are defined, CSP
  gains a navigation directive, browsers stop sending `Origin: null` from `file:`
  pages, or the builder's first release finds a host where rule 7 does not hold.

## Choosing the rung: text, diagram, page, or video

Each rung up costs more tokens, more generation time, and more of the reader's
attention. Climb only when the rung below loses something the reader needs.

- **Text** (the terminal reply, or the markdown record alone) when the answer is a
  decision, a value, a command, or a short list the reader acts on where they are
  reading. Most answers stop here.
- **A diagram in the record** when the content is a structure that prose has to
  serialize: a graph of dependencies, a sequence of calls, a state machine, a hierarchy.
  The diagram's source lives in the record's bundle, so the record still carries it
  without any view.
- **A page** when the reader has to explore, compare, or answer: filter a long list,
  set options side by side, walk a risk map, answer a quiz, or pick and send a choice
  back. The genre rubric below still decides whether the deliverable gets a page lane.
- **A video or narrated audio** when the meaning is in time-ordered motion the reader
  will watch rather than scan: an algorithm stepping through its state, a flow of
  requests over time. It is the costliest rung and always a view: the record carries the
  same content as text and diagrams.

Accessibility is a standing reason to step back down a rung; see Accessibility floor.

## Reachability and preference

Reachability constrains; preference selects within reachable rungs; every degrade is
visible and names its cause.

| Environment | Reachable rungs |
|---|---|
| Local interactive session | published artifact, local file, terminal |
| Remote or web session | published artifact, a file sent to the user, terminal |
| CI or non-interactive run | terminal or the record only, no view emitted |

A skill that cannot serve its preferred rung says so and names the layer or environment
fact that decided the outcome, rather than silently printing a dead file path.

## Default ladder and its reconciliation

The shipped default ladder for existing emitting surfaces stays **published artifact,
then local file, then terminal**, exactly as those surfaces and their evals ship today.
Two sentences reconcile this with the local-first residence decision:

1. Local-first governs NEW rendered-view lanes and any operator's personal environment:
   the native Artifact disable switches (`enableArtifact: false` in settings, the
   `CLAUDE_CODE_DISABLE_ARTIFACT=1` environment variable, or a `permissions.deny`
   `Artifact` rule) are the sanctioned day-one flip that turns every ladder local, with
   zero plugin changes.
2. The existing emitting surfaces are grandfathered on the shipped ladder until the
   priced fleet sweep deliberately migrates them (tracked as a deferred-work issue).

One new lane is an exception to sentence 1, recorded here: the pull-request digest
lane (`review:pr-explainer` today, `review:explain-change` once #5835 C1 lands) takes
`medium: artifact` as its default only after that lane's own external-publication
review signs off. An operator who wants the digest local sets `medium: file`
in their personal layer (`~/.claude/rendered-views.md` or the repo overlay); the
cascade below resolves it like any other key.

Rendered views are untracked by default; publishing anywhere else is optional and
configured, never the default, except for the digest's planned `artifact` default.

A plan that depends on sharing or editing a rendered view across accounts or subscriptions
does not assume it works: it checks the live Share dialog first.

- **Pointer**: for artifact sharing and its permissions, see
  <https://code.claude.com/docs/en/artifacts#share-an-artifact>.
- **As of**: 2026-10-02 (Claude Code v2.1.287)
- **Recheck trigger**: a Claude Code version bump, or a plan about to rely on cross-account or
  cross-subscription sharing or editing (present or absent).

## Genre rubric and stopping rule

A skill's deliverable is in scope for an HTML-view lane only when it falls in one of the
corpus genres:

exploration grids and option spreads; plans presented for approval; code-review
explainers; reports, status, and post-mortems; research and concept explainers; decks;
custom throwaway editors; unknowns-lifecycle artifacts (blindspot passes, interviews,
comprehension quizzes).

The stopping rule: a lane is added per skill, by a change that names the genre the
deliverable belongs to and applies the dual-audience test above. A deliverable that fits
no genre gets no lane, and a genre argument is settled by this list, amended here first.
The instruction-size budget: an HTML-view lane (ladder, chrome citation, escaping note)
adds at most 40 lines to a SKILL.md; the cascade wiring adds at most 30. A lane that
cannot fit the budget is a design smell, not a reason to raise the budget silently.

## Corpus distillate

Retained here because the working session's corpus artifacts are ephemeral; this is the
distillate future adoption waves need.

Genre taxonomy (gallery): exploration and planning; code review and understanding;
design; prototyping; illustrations and diagrams; decks; research and learning; reports;
custom editing interfaces. Lifecycle taxonomy (unknowns collection): pre-implementation,
during, post-implementation.

The nine cross-cutting pattern families verified across all 31 corpus demos:

1. One design-token system corpus-wide (the palette and stacks the shared reference
   carries).
2. Absolute self-containment: zero external links, scripts, or images in every demo.
3. A loop-closure family with escalating payloads: numbered resonate tokens, chip-built
   replies, generated follow-up prompts, accept/correct sign-offs, live-state exports;
   absent by design in the writeup/report genre.
4. Identical clipboard boilerplate in every interactive page (shared-helper candidate,
   deferred with the loop-closure issue).
5. Prompt provenance split by genre: exploratory pages embed their generating prompt,
   reportive pages do not.
6. Badge and taxonomy vocabularies invented per page, never shared.
7. A JS-necessity spectrum from zero-script reports to simulation-grade editors.
8. Accessibility explicitly deferred in the corpus's prototypes (why this repo ships a
   floor instead).
9. The unknowns lifecycle maps one-to-one onto this marketplace's existing skill lanes.

Named costs the corpus itself records: more tokens, two to four times the generation
time, and noisy diffs under version control; the offer-not-emit rule and untracked
residence are how this convention prices them.

## Wave-1 adoption and grandfathered surfaces

Wave-1 adopter (cascade wiring plus chrome citation): `visualization:visualize`.

Current emitters, grandfathered on their shipped ladder and `medium` only, since the
content-class rules bind them now (see Content classes): `adhd:clarify`,
`architecture:improve`, `education:teach` (topic mode),
`prototype:explore-directions`, `prototype:pressure-test`, `machine-health:audit`,
`planning:interview` (and planning's other rendered views),
`overengineering:audit`, `ai-briefing:generate`,
`visualization:visualize`.

Emitters on the escape-helper gate (the third bullet of the security baseline), each building
its page with a checked-in builder: `education:eli5`, `education:teach` (codebase mode),
`knowledge:video-digest`, `harness-ops:observability`, `event-storming:simulation`. They left the
grandfathered list when they moved onto it.

Retrofit list (existing lanes rendering untrusted-ish content, aligned to the security
baseline by the tracked retrofit issue, not silently): `adhd:clarify`,
`architecture:improve`. Both were retrofitted by #3609: each HTML lane repeats the
baseline's rules in its own instruction text (a skill runs where this file is not on
disk) and keeps only additions specific to that surface. `architecture:improve` also
carries the third bullet's exception: the escape helper has shipped
(`lib/html-escape.mjs`), and wiring that lane through it remains the retrofit, so
another repository's files are still not rendered to HTML. `visualization:visualize`
keeps the same carve-out. The first two bullets are registered as the `rendered-views-security-baseline` clause in
`scripts/contract-clause-registry.json`, so `scripts/check-contract-clause-coverage.py`
holds each inline copy to every one of them.

## Security baseline (wave-1 skeleton)

Instruction-level discipline for a lane that is not on the helper: markup linting
validates syntax, not escaping. A lane that renders attacker-controlled input uses
the checked-in helper in the third bullet instead of this skeleton alone.

- Everything interpolated into a rendered view is untrusted DATA: escape `&`, `<`, `>`, <!-- contract-restatement-begin: rendered-views-security-baseline -->
  `"`, and `'` in text and attribute positions; never interpolate unescaped content into
  `<script>` or `<style>`; never build event-handler attributes from input.
- Views are self-contained: no external requests, no remote scripts, assets inline. <!-- contract-restatement-end: rendered-views-security-baseline -->
- A lane that renders attacker-controlled input (a PR diff, fetched web content, another
  repo's files) MUST NOT ship on this skeleton alone. It routes every interpolated
  string through `lib/html-escape.mjs` (the same path inside each adopting plugin,
  generated and drift-gated by `scripts/sync-shared-copies.sh`). The page carries the generator marker
  `validateRenderedPage` checks, so a page assembled without the helper is detectable.
  `/review:pr-explainer` and `/education:quiz-me` are on that gate. Such a lane is K2 (see
  Content classes); the shared builder carries the same helper and adds the interactive profile.
- Escaping reaches text and quoted-attribute positions and nothing else. A value that
  lands in URL position (`href`, `src`, `action`, `formaction`, SVG `xlink:href`) is
  checked against a scheme allowlist BEFORE it is escaped: `javascript:` and `data:`
  carry none of the escaped characters, so they pass through escaping unchanged and
  still execute. An export builds a `Blob` and an object URL rather than concatenating
  content into a `data:` URL, and reduces any filename it puts in a `download`
  attribute to an allowlisted character set. Working helpers for all three positions
  are in the loop-closure snippet reference below.

Checked-in `.html` assets are validated by `scripts/check-html-assets.sh` (registration
manifest plus pinned htmlhint), wired into CI. Markup linting still validates syntax
rather than escaping, so an asset whose job is to carry copied helpers also carries a
behavioral suite: `scripts/check-loop-closure-helpers.test.sh` executes the shipped
helpers of the loop-closure reference and fails on a dropped case that lints clean.

## Accessibility floor

The floor (contrast pairings, focus visibility, color-scheme and reduced-motion behavior,
keyboard reach) lives in the shared chrome reference and is provisional until the
design-system vertical revisits it cross-genre. Accessibility is a named, sanctioned
reason to prefer markdown over a rendered view: when a reader's tooling or needs make the
markdown record the better deliverable, flipping back is conformant, not a deviation.

## Loop closure and the export obligation

A rendered view that only shows things makes the reader retype what they picked, which is
a dead end. Loop closure is the family of patterns that hands the reader a terse payload to
give back; export is the pattern that gets live page state off the page.

**When a view owes an export.** A custom editor always ends with one: a view that lets a
person change state and then offers no way to get that state out has thrown the work
away. A view that asks the reader to choose, rank, accept, or correct owes a loop-closure
payload for the same reason. A view that only presents owes neither.

**Where the family belongs.** Editors, explorations and option spreads, and
unknowns-lifecycle pages. It is excluded from the writeup and report genre by design,
which is a decision the corpus already made, not an omission: a report is read, not
answered, and a lane that bolts a resonate token onto a post-mortem is contradicting the
genre rather than improving it. A dual-audience report whose markdown record is the
deliverable stays on that record.

**Why the payloads stay terse.** The artifact is still on screen while the reader
answers, so the agent re-anchors by number or token rather than by a restated body. A
payload that repeats the page's content back is not a richer loop closure, it is the
pattern broken.

The five escalating payload shapes, cheapest first: numbered resonate tokens;
chip-assembled replies; generated follow-up prompts; accept-and-correct sign-off tokens;
live-state exports. A view may carry more than one, and adding a rung the reader did not
need is overproduction: this section names an obligation, not a floor to hit on every
page. On a K2 page every payload carries only reader input and builder-assigned ids
(see View tiers), so a K2 page has no generated follow-up prompt and no export rebuilt
from data-block strings.

## The loop-closure and export snippet reference

Canonical copy: `plugins/visualization/reference/html-loop-closure.html`, carried and
shared on the same terms as the chrome reference below (byte-identical copy at
`reference/html-loop-closure.html` in a second adopting plugin, registered in
`scripts/cross-plugin-source-registry.txt` in that same change; unregistered while only
one plugin carries it). It holds the four shared helpers every pattern is built from,
including the clipboard boilerplate each interactive page otherwise duplicates, and one
runnable demo per payload shape.

It is reference material, not a skill: it owns no page shape, and each adopting lane
keeps its own layout, vocabulary, and genre. Adopting it is a per-lane change, and this
convention's instruction-size budget applies to the lines a lane adds for it.

## The shared chrome reference

Canonical copy: `plugins/visualization/reference/html-chrome.html`. A second adopting
plugin copies it byte-identical to the same path within its own root
(`reference/html-chrome.html`) and registers the cluster in
`scripts/cross-plugin-source-registry.txt` in the same change; the drift checker rejects
a registration while only one plugin carries the file, which is why the first adoption
ships unregistered by design. Skills cite the reference inline by role (their plugin's
own copy), never by a repository path an installed consumer cannot resolve.

The chrome's ivory page background (`--ivory`) is the sanctioned default background for a
view built on it, so no skill's "styles to leave out" list names a cream or off-white
background. Those lists name layout habits (italic accent words in headings, numbered
section labels, pill-shaped buttons, a hero banner). A lane that departs from the
chrome's palette declares its own background instead of banning this one.

## The `rendered-views` cascade concern

The cross-plugin output-format preference rides the
[config-cascade convention](../config-cascade/README.md); this section is the concern's
owner declaration.

- **Surface**: `.claude/rendered-views.md`, in all three layers (user-global
  `~/.claude/rendered-views.md`, team `.claude/rendered-views.md`, overlay
  `.claude/rendered-views.local.md`).
- **Keys** (per-key override, declared here per the contract): `medium`, one of `auto`,
  `terminal`, `file`, `artifact`; the preferred rung for rendered views, applied within
  reachability. Future keys are added here first. A lane's shipped default for `medium`
  is the last tier of the ladder below; the digest's planned `artifact` default (see
  Default ladder and its reconciliation) is one such default once it ships, and any layer
  that sets `medium` overrides it.
- **No policy-floor class**: every key is a taste dial over deliverable presentation; a
  personal value weakens nothing another surface depends on (the `ai-slop` precedent).
  The default direction holds: the team layer refines user-global, the overlay is the
  operator's per-repo trump, and the user's global preference governs wherever no repo
  layer speaks.
- **Tier ladder across mechanisms**: explicit argument, then the plugin's own `userConfig`
  dial, then this cascade surface, then the shipped default. Plugin `userConfig` dials
  are never keys in this surface; a layer declaring one is reported as an inert unknown
  key (the `bugs` partition precedent).
- **Resolution**: per the contract's algorithm (anchor at the repo root, read every layer
  that exists, report which layer supplied each value, degrade soft and visibly on a
  malformed or absent layer).

## Template vendoring posture

**Decision.** Do not vendor the 31 html-effectiveness corpus templates (20 gallery +
11 unknowns). The derived chrome and token reference
(`plugins/visualization/reference/html-chrome.html`) is the sanctioned shared piece.
Per-genre page-shape is served by pointers to the public gallery, not by copies in
this tree.

A future lane that must vendor a single page states which source it took and
carries the matching notice:

| Source | License signal |
|---|---|
| Live gallery pages | `Copyright 2026 Anthropic PBC / SPDX-License-Identifier: Apache-2.0` header comments |
| `anthropics/html-effectiveness` | MIT, no per-file headers |

Both are permissive; mixing them in one file without naming the source is the
defect this posture prevents. The wave-1 chrome reference is a **derived** token
system (not a copied page) and already carries that split in its header comment.

`plugins/*/skills/*/vendor/**` is excluded from the ai-slop audit by rule. That
exclusion is not a reason to vendor: a vendored page would escape style audit,
which is another cost of copying.

- **Claim:** whole-page vendoring of the 31 corpus templates is declined;
  pointers plus the derived chrome reference are the posture.
- **Basis:** #3608 (byte-verified license split; every demo is self-contained;
  gallery uses fictional Acme data; wave-1 already carries derived tokens).
  Public gallery: <https://thariqs.github.io/html-effectiveness>. Official
  templates: <https://github.com/anthropics/html-effectiveness>.
- **As of:** 2026-09-28.
- **Recheck:** a lane that cannot cite a public page-shape and must ship a
  checked-in HTML page of its own, or a license change on either source.

## What this convention does not do

- It never makes a view the record: the markdown record stays authoritative everywhere.
- It adds no generic HTML skill, one whose job is "make a page" for any content. Thin
  intent-named skills are allowed: a skill named for what the reader is trying to do
  (`review:pr-explainer` explains a pull request) may emit a view as its deliverable,
  owning its genre's page shape and reusing the shared builder and chrome.
  `visualization:visualize` stays a router that owns no craft.
- It does not migrate the grandfathered surfaces' ladder or `medium`: that sweep is
  priced and tracked separately, gated on the userConfig smoke test. The content-class
  rules already bind them.
- It does not vendor the 31 corpus templates: see Template vendoring posture.
