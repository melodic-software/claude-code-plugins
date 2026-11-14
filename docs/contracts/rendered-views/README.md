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
reference lives in the adopting plugins (canonical copy: `lib/html-chrome.html`). Where a record and the
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
- **The Claude-interactive tier is open only to builder pages.** `session-bridge` meets
  interactive-profile rule 9, so a page of any class reaches it when the shared builder
  built it with `--connect` and the bridge's view app serves it
  (`lib/session-bridge/README.md`, "The view app"). A model-written K0 or K1 page does not
  use it: it stops at client-interactive and closes the loop with a copied payload. A
  builder page with no live session says so and keeps its copy and save controls. One
  checked-in page is the exception: the ui-feedback host page frames a model-written K0 or
  K1 page in a sandbox and sends the person's notes itself
  ([ui-feedback, "Trust rules"](../ui-feedback/README.md#trust-rules)). The framed page
  still carries no `connect-src` and sends nothing to the session.
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
- **A record outside the repository carries its class.** A record kept in a memory-tier
  or plugin data directory is not K1, so without a marker it is K2. It keeps K0 or K1
  only when the lane that wrote it put a provenance line in it,
  `<!-- content-class: K0 -->` or `<!-- content-class: K1 -->`, which states that the
  writing context held no K2 text. A lane that cannot state that writes no marker. A
  marker is the writer's claim, not proof: a record that quotes a K2 surface is K2
  whatever its marker says.
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
- **The class rules bind every emitter**, including the minimum content security policy
  on a K0 or K1 page (see Wave-1 adoption and grandfathered surfaces for each emitter's
  `medium` handling). A lane whose authoring context holds K2 text emits the markdown record or terminal
  output, or a page built by the shared builder (`lib/view-builder.mjs`, report or
  interactive profile) or by `lib/html-escape.mjs`, never a page with model-written
  markup or script.
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
  form-action 'none'`, with no `connect-src`: the Claude-interactive tier is open to
  builder pages only (see View tiers). The policy caps a misclassified page:
  injected script runs but cannot fetch, beacon, or submit a form. It can still
  navigate the page to a URL that carries data out, and CSP3 has no directive that
  stops navigation, so the authoring-context rule, not the policy, is what keeps K2
  text out of a model-written page. The policy also blocks the web fonts and CDN
  scripts the Artifact host otherwise allows, so a K0 or K1 page inlines everything it
  uses.
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
   `type` makes it a data block the browser does not execute. The runtime reads it
   only as `JSON.parse` of the element's text; nothing evaluates it.
3. **A content security policy in the page.** The first element in `<head>` after the
   charset is a `<meta http-equiv="Content-Security-Policy">` with `default-src 'none'`,
   a `script-src` naming only the runtime's SHA-256 hash, a `style-src` naming only the
   hash of the page's one `<style>` element, and `base-uri 'none'` and
   `form-action 'none'`, which do not fall back to `default-src`. Its content is the
   builder's exact policy string. It is the only `http-equiv` meta the page carries: any
   other, such as `refresh`, which navigates and is not blocked by the policy, fails.
   A Claude-interactive page (rule 9) adds one last directive, `connect-src` naming the
   `session-bridge` origin `http://127.0.0.1:<port>` and nothing else; the builder writes
   it from `--connect`, the validator refuses any other `connect-src`, and the runtime
   reaches only that origin. `session-bridge` owns that origin, and rule 9 governs what
   crosses it.
4. **No inline handlers, no navigation.** No `on*` attribute, no `style` attribute, no
   `<form>`, `<iframe>`, `<object>`, `<embed>`, `<base>`, or `<link>`. A URL-bearing
   attribute is allowed only as a same-document fragment reference (`#id`): `<a
   href="#id">` is allowed, and an `<a href>` with any other value fails. The runtime
   attaches every event listener. It may create a `blob:` download anchor when the
   reader exports; that anchor is never in the built markup.
5. **Control tags.** The tag allowlist widens to the controls the runtime drives
   (buttons, labels, checkbox, radio, search, text and range inputs, textarea, select,
   details and summary), neutral containers, and text-level elements; attributes widen
   to `aria-*`, `role`, `data-*`, `hidden`, `open`, `type`, `for`, `value`,
   `placeholder`, `checked`, `min`, `max`, and `step`, each value escaped.
   - **Ids are opaque.** Every `id`, `for`, `value`, and `data-*` value is a token
     matching `^[a-z0-9-]{1,32}$` from the checked-in template, or one the runtime
     builds from a template key and a list position. None is derived from data, such as
     a file path from a pull request, so no payload can carry data text in an id.
   - **No pre-fill from data.** Data never fills a form control: the validator refuses
     a content binding (`data-rv-text`, `data-rv-count`, `data-rv-each`) on an input,
     textarea, select, or option, and the runtime skips those elements and never sets a
     control's value from the data block. What a payload carries as the reader's input
     is what the reader entered.
   - **No binding outside page text.** The validator refuses every `data-rv-*`
     attribute on `<html>`, `<head>`, `<title>`, `<meta>`, `<style>`, and `<script>`,
     and the runtime skips those elements, so data never becomes CSS, metadata, or code.
   - **Two client-only bindings.** A `button[data-rv-theme]` (`system`, `light` or
     `dark`, the shared chrome's toggle) sets or clears `data-theme` on the root element
     and `aria-pressed` on the toggle's buttons; system, the default, follows the
     reader's color-scheme preference, and nothing is stored. An `option[data-rv-shows]`
     of a `select[data-rv-choice]` names the example blocks (`data-rv-example`) it
     selects: picking it shows them and hides the blocks the select's other options
     name (the redraw binding). Both act on template tokens only, never on data, and
     make no network call.
   - **One builder-written title.** The single exception is the page title. Given a
     `title`, the builder replaces the text of the one `<title>` in the template's
     `<head>` with that string as escaped plain text: format characters such as bidi
     overrides are dropped, whitespace and control characters collapse to single spaces,
     and the text is cut to 80 characters. A blank title keeps the template's text. The
     builder refuses a title for a template with no such element or with more than one. The runtime and validator
     still refuse every binding on `<title>`, so the builder is the only writer.
     An emitter passes its record's title, which may be K2 (a pull request's title, a
     fetched page's subject), so the page is named for its record, not its template. The
     page already shows the same text as its heading. Escaping is the control here: the
     title is not a security boundary (rule 7).
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
   published as an artifact. Apart from the builder-written title (rule 5), data
   reaches the page only through `textContent`: the
   runtime never sets `href`, `src`, `xlink:href`, `style`, an `on*` handler, or any
   other attribute from a data value, and never uses one as a URL or a selector.
   - **The artifact host does not apply the page's policy.** It wraps the page in its
     own document, so the page's `<head>` content, the policy meta included, lands in
     the host's `<body>`, and a browser ignores a policy meta there. The host's own
     policy governs instead. The builder's validation and the runtime's text-only
     rendering are the controls that hold in both hosts: both refuse bindings on
     `<style>`, `<head>`, `<meta>`, `<title>`, `<html>`, and form controls, so data stays
     body text the host's policy cannot be asked to police. The page's policy is defense
     in depth that holds from `file://`. The host also blocks any download the page starts
     itself and gives the page no sign that it did, so the runtime removes every
     `data-rv-download` button except on `file://`, the session bridge on `127.0.0.1`, and a
     page served top-level over `https:` (a page host that allows downloads; see The `hosted`
     medium), never says a file was saved, and shows every payload as selectable text when the
     reader copies or saves.
   - **Basis:** the builder's sample page, published 2026-10-02 and read back: the
     stored page sits inside the host's `<body>`. In headless Chromium, the same page
     wrapped that way ran a runtime that did not match its hash; unwrapped, from
     `file://`, the policy blocked it (`lib/view-builder.test.sh`). The download block:
     the [artifacts docs](https://code.claude.com/docs/en/artifacts#offer-a-file-download),
     fetched 2026-10-04, and the HTML
     [download algorithm](https://html.spec.whatwg.org/multipage/links.html#downloading-hyperlinks),
     which returns without an error when the document's downloads are sandboxed.
   - **Recheck:** the artifact host stops wrapping pages, lets a page declare its own
     policy, or lets a page start its own download.
8. **A generator marker naming the profile.** The page carries the builder's generator
   marker, which names the profile it was validated against, and the validator selects
   the profile from it: `rv-gen:view-builder-interactive` selects the interactive
   profile, and any other page, including one stamped `rv-gen:escape-helper-v1` or
   carrying no marker, is judged by the report profile, so an unknown marker fails
   closed. A marker proves no provenance; the structural scan decides. When the marker
   format changes, the builder and every consumer of the old marker migrate in the same
   change.
9. **The Claude-interactive tier.** The tier opens to a page only while `session-bridge`
   meets the last three bullets below; it meets them now, and its README's "Rendered-views
   rule 9" table says how. A change that breaks one closes the tier again (see View
   tiers). The first bullet binds the page; the last three are properties of the
   bridge and hold for every message from every page, whatever its class:
   - The page sends only what the reader entered plus ids assigned when the page was
     built (a finding number, a hunk id, an option id), never a string taken from the
     data block. The session resolves each id against its own copy of the record. This
     bullet also binds every copy, export, and download payload on a K2 page at every
     tier, and text pasted or exported from a K2 page is K2, never K0 user input (see
     View tiers). One exception, for model-written pages only: a note the ui-feedback host
     page sends about a model-written K0 or K1 page it frames may carry a text quote taken
     from that page (`anchor.textQuote`: the selected text and a little visible text either
     side, limits in `lib/ui-feedback/note.schema.json`), so the session can find the text
     again. The quote is data everywhere: the host page keeps it only when the note schema
     admits it and renders it through `textContent`, the bridge validates it again and
     delivers it under the framing contract below, and the session quotes it, never acts on
     it ([ui-feedback, "Trust rules"](../ui-feedback/README.md#trust-rules)). A K2 page never
     uses the host page.
   - The bridge delivers every page-originated field, the reader's input included, to
     the session as DATA under the untrusted-content framing contract, never as the
     user's own message.
   - The bridge authenticates every message by an unguessable per-session token and
     rejects any message without it. The token is minted per server run; the server exits
     `IDLE_SECONDS` after the session's last wait (and on stop), which ends the token. It
     never enters a published, shared, or exported copy of the page. The origin authenticates nothing: a page opened
     from `file://` sends `Origin: null`, the same value any opaque origin sends.
   - The bridge lets no message trigger a write, push, merge, or other gated action
     without the confirm or permission gate that action already has.

The builder's exact tag and attribute lists live in `lib/view-builder.mjs`, and the
hostile-input corpus that proves each refusal above, with the runtime's sink lint, lives
in `lib/view-builder.test.sh`. Each adopting plugin carries a generated copy of both
library files (see `scripts/shared-copies.txt`). A change that widens an allowlist
names the rule above it falls under; a widening no rule covers amends this section
first.

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
  pages, or another host turns out to treat the page differently from the two rule 7
  names.

## Choosing the form: text, diagram, page, or video

Each form down this list costs more tokens, more generation time, and more of the
reader's attention. Take the next form only when the one before it loses something the
reader needs.

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
  requests over time. It is the costliest form and always a view: the record carries the
  same content as text and diagrams.

Accessibility is a standing reason to step back to a cheaper form; see Accessibility floor.

## Reachability and the fallback chain

Reachability constrains the choice and preference selects within it. Every fall is visible and names its cause. There is
one fallback chain, owned by the medium registry (`lib/view-registry.mjs`): **published artifact,
then local file, then terminal**. A view that cannot be served on its preferred medium steps down
that chain to the first reachable one. `hosted` is read as `artifact` except in a lane registered
as hosted-capable (only `/review:explain-change` today); there, a page that cannot reach the host
steps to `artifact` first. Each medium's entry in the registry owns its own reachability check, so
no skill lists conditions in its prose.

| Environment | Reachable media |
|---|---|
| Local interactive session | published artifact, local file, terminal |
| Remote or web session | published artifact, a file sent to the user, terminal |
| CI or non-interactive run | terminal or the record only, no view emitted |

Every view lane prints one report line, `view: <medium> (<what decided it>)`, then one line per
notice. What decided it is `argument`, `userConfig`, `team`, `personal override`, `plugin
default`, or `fell back: <medium> unreachable: <reason>`, so a skill never prints a dead file path
without saying why.

## Shipped fallback chain and its reconciliation

The shipped fallback chain for the existing emitting surfaces that publish
(`adhd:clarify`, `visualization:visualize`) stays **published artifact, then local file,
then terminal**, exactly as those surfaces and their evals ship today; the other existing
emitters keep the local default each one ships.
Two sentences reconcile this with the local-first residence decision:

1. Local-first governs NEW rendered-view lanes and any operator's personal environment:
   the native Artifact disable switches (`enableArtifact: false` in settings, the
   `CLAUDE_CODE_DISABLE_ARTIFACT=1` environment variable, or a `permissions.deny`
   `Artifact` rule) are the sanctioned day-one flip that makes the local file the first
   reachable medium for every lane, with zero plugin changes.
2. An existing publishing surface starts at the published artifact only by default: each one
   reads `medium` from the argument and the cascade first (see Wave-1 adoption and
   grandfathered surfaces).

One new lane is an exception to sentence 1, recorded here: the pull-request digest
lane (`/review:explain-change`) ships `medium: artifact` as its default. Its page is
built only by the shared builder from a checked-in template, and the artifact stays
private to the reader until they share it. The default publishes only a public
repository's diff with no credential-shaped hunk; any other diff falls back to `file`
and the reader is told to set the review plugin's `medium` option to `artifact` to publish it
anyway. An operator who wants the digest local sets that option to `file`, or `medium: file` in a
personal override; the resolver below decides it like any other value.

The deck lane (`/visualization:present`) is the second exception: a deck exists only as an
Artifact made from the account's Slides type, so it publishes behind the same gate (see
Artifact types), and anything the gate keeps local stays the markdown outline.

The planning views are the third exception: the brainstorm, design and plan views
(`/planning:brainstorm`, `/planning:design`, `/planning:plan`) ship `medium: artifact` as the
planning lane's default. Each page is built only by the shared builder from a checked-in template
(`plugins/planning/scripts/build-view.mjs`), and it publishes behind the same gate as the digest:
the default publishes only a public repository's record with nothing credential-shaped in it, and
any other record falls back to `file` with the reader told how to publish it anyway. The planning
plugin's PRD and interview views are not part of this exception and stay local files.

Rendered views are untracked by default; publishing anywhere else is optional and
configured, never the default, except for the digest's, the deck's and the planning views'
`artifact` default. A
shared page host is one such configured place: `medium: hosted`, honored only by the digest lane
(see The `hosted` medium).

A plan that depends on sharing or editing a rendered view across accounts or subscriptions
does not assume it works: it checks the live Share dialog first.

- **Pointer**: for artifact sharing and its permissions, see
  <https://code.claude.com/docs/en/artifacts#share-an-artifact>.

## Artifact types

A claude.ai Artifact type is a ready-made page that takes content as data, such as the Slides
type for decks. A producer uses a type instead of the shared builder when all three hold:

- The deliverable is the genre the type was made for: a deck uses the Slides type.
- The view is meant to be published: a type exists only as an Artifact on claude.ai.
- The type renders its content from a closed format, so the session writes data and never script.

Otherwise the producer builds a local page with the shared builder, or keeps the markdown record.
Rules for a producer on a type:

- **The record stays markdown.** The type's data files are the view. They are written in a scratch
  folder outside any working tree and outside the record's bundle, then sent to the Artifact.
- **Types are per account.** The producer finds the type at run time through the Artifact tool's
  `quickstart` and never hard-codes a type URL. With no such type, or no Artifact tool, it delivers
  the markdown record and says why: that is the fallback.
- **Content classes still bind.** K2 text enters the type's store as escaped text only. The
  producer's check script holds a K2 deck to an allowlist of text and layout elements, attributes,
  and uploaded image sources, read by a quote-aware tokenizer that refuses whatever it cannot parse,
  so no live embed, script, link, inline SVG, CSS function, or image taken from the source is sent.
- **The publish gate decides first.** `lib/publish-gate.mjs` (shared with `/review:explain-change`)
  runs before the type's create call, which already publishes the title, so the create call takes
  the title the gate read. The check script resolves the medium itself through the shared
  resolver, not the model: only an `artifact` choice from a scope a checked-out branch cannot write
  (the argument, the plugin's `medium` option, or an untracked, gitignored personal override)
  publishes as is. Otherwise the producer names the destination ("a private Artifact on
  claude.ai") and keeps the view local when the source repository is not `PUBLIC` or any file looks
  like a credential, naming the plugin's `medium` option set to `artifact` as the opt-in.
- **A design system is optional.** It is used only when the user names one or the `quickstart`
  attaches the account's default.

Producers on a type: `/visualization:present` (Slides).

## The `hosted` medium

`medium: hosted` sends a built page to a shared page host the operator runs, through the
`pages-publish` command, so a page can be opened from any account or machine. The operator installs
`pages-publish` and its configuration; the plugins hold no host name, token, or vendor detail.

- **One lane publishes hosted.** `/review:explain-change` is the only lane that calls the gate and
  `pages-publish` for `hosted`. Every other reader of the `medium` key, `/visualization:present` and
  every lane that does not call the gate included, treats `hosted` as `artifact`, so one personal
  value serves every lane.
- **Only scopes a checked-out branch cannot write select it**: the argument, the plugin's `medium`
  option, or an untracked, gitignored personal override. A team `docs/conventions/rendered-views.yaml`
  that says `hosted` is reported and ignored.
- **The destination never depends on the preference.** Which host a page reaches is the gate's
  decision alone, whichever layer chose `hosted`; no layer can skip a check or force the public
  host. The gate starts from `public` and only lowers it:
  - a credential-shaped line refuses the upload, and the page stays a local file;
  - a repository that is not `PUBLIC` (`UNKNOWN` included), or a machine path or hostname in the
    page, sends it to the private host, which asks the reader to sign in.
- **The gate reads the bytes that leave.** It scans the built page, with the strings in its data
  block decoded so escaping cannot split a credential, not the diff the page was made from.
- **Only the listed shapes are caught.** The credential and machine-path patterns live in
  `lib/publish-gate.mjs` (`SECRET_PATTERNS`, `MACHINE_PATTERNS`). A miss proves nothing: a
  credential or path in a shape the list does not name passes.
- **Three layers check a hosted page.** The plugin gate checks repository visibility, credentials,
  and machine paths and hostnames. `pages-publish` checks the builder stamp, the temp-directory
  rule, credentials, and machine paths and hostnames before any network call. The host's upload
  route checks credentials, and machine paths and hostnames on the public host, on every upload and
  is the layer that binds, because its upload token can be used without `pages-publish`.
- **Repository visibility is checked only by the plugin gate.** The publish script looks it up
  itself through the REST API (`gh api repos/<owner>/<repo>`), never from a caller's argument, and
  a failed or unexpected lookup counts as not public. The page bytes carry no
  repository identity, so `pages-publish` and the host cannot refuse a public upload of a page made
  from a private repository when a caller skips the gate.
- **The page id lives in the plugin's data directory**, in
  `hosted/<owner>__<repo>__<pr>.json` holding `pages-publish`'s JSON line, so a rebuild of the same
  pull request's page replaces it. When the returned id differs from the sidecar's, the
  lane writes the new sidecar with the old id listed under `stale`, then deletes it from the old
  host; an id whose delete fails stays under `stale` and is retried on the next publish. A replace
  that fails (exit 6, as when the page was deleted outside the lane) is retried once without
  `--id`, and the new id is handled like any other changed id.
- **The save button stays on a top-level https page**, because the host's policy allows downloads.
  A framed page, such as an Artifact, still loses it (Security baseline, rule 7).

### The `pages-publish` command

The contract every `pages-publish` implementation meets. The lane runs it with an argument vector,
never through a shell string.

```text
pages-publish <file> --visibility public|private [--id <id>]
pages-publish --delete <id> --visibility public|private
```

- `<file>` must be a regular file under the OS temp directory and carry a builder stamp,
  `<!-- rv-gen:<name> sha256:<64 hex> -->`; otherwise exit 3.
- It scans the bytes it will send: a credential-shaped line exits 4 with no network call and
  names the pattern label and line on stderr, never the match; a machine path or hostname forces
  `private`.
- It reads its endpoints and secret names from a configuration file at a fixed path under the
  account's passwd home directory, never from the run-time environment. It sends credentials to
  the host only through standard input, never the argument vector.
- `--id` replaces that page. When the visibility it sends differs from the one the id was
  published under (forced private, or the public host answering that the page must be private),
  it drops `--id` and creates a new page; the caller deletes the old id.
- The upload is `Content-Type: text/html; charset=utf-8`.
- On success it prints one JSON line on stdout, `{"id": "<22 characters>", "visibility":
  "public"|"private", "url": "https://..."}`, and exits 0. `--delete` exits 0 when the page is gone.
- Exit codes: 0 done, 2 usage, 3 not a stamped page under the temp directory, 4 credential-shaped
  content, 5 configuration missing or unsafe, 6 upload or HTTP failure.

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
The instruction-size budget: an HTML-view lane (medium selection, chrome citation, escaping note)
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

Wave-1 adopter (cascade wiring plus chrome citation): `visualization:visualize`. Second chrome
adopter, citing its own byte-identical copy: `adhd:clarify`.

Emitters that resolve `medium` through the shared resolver (see The `rendered-views` settings),
keeping their shipped default only when no scope sets it: `adhd:clarify`. Its output prints the
resolver's report line and notices.

`architecture:improve` resolves `medium` through the shared resolver (lane `architecture`, see
"The `rendered-views` settings") and publishes nothing: `terminal` skips the HTML report and leaves
the candidate artifact; every other value writes the local report.

Emitters that resolve `medium` from the argument, then the cascade, and publish nothing themselves.
None has a `medium` option, so no
plugin dial sits between the argument and the cascade. Each names the source of `medium`, or
"shipped default", and keeps its shipped behavior when no layer sets one:

- `education:teach` (topic mode): `terminal` writes `lesson.md`; `file` keeps the host-aware
  format choice and drops the artifact-share offer; `artifact` and `hosted` keep the offer.
- `prototype:explore-directions`: the mockup stays a local file at every value; `terminal` and
  `file` drop the design-canvas offer, since the canvas is published.
- `prototype:pressure-test`: `terminal` picks the terminal app; `file`, `artifact` and `hosted`
  override nothing, so the audience routing still picks the shell, and an HTML demo stays a local
  file. An explicit shell request still wins.
- `planning:interview`'s read-only decision table, `planning:prd`'s pitch view and
  `planning:design`'s topology view (`plugins/planning/reference/rendered-view.md`, "Other optional
  views"): `terminal` writes no file; every other value writes the local file.
- `overengineering:audit`: `terminal` drops the offer to render the findings through
  `visualization:visualize`; `file` keeps the offer and passes `file` to it; a value from the
  `--medium` argument keeps the offer and passes that value to it; every other value keeps the
  offer and leaves the medium to `visualization:visualize`.
- `ai-briefing:generate`: only `--format` selects HTML or PPTX, so no layer starts the build; the
  briefing stays markdown under every layer.
- `codebase-health:audit` (genre: reports; dual-audience, since its findings feed a fix pass):
  `terminal` drops the offer to render the report through `visualization:visualize`; `file` keeps
  the offer and passes `file` to it; a value from the `--medium` argument keeps the offer and
  passes that value to it; `artifact` or `hosted` from the team layer keeps the offer and passes
  `file` to it, so a team layer cannot publish; every other value keeps the offer and leaves the
  medium to `visualization:visualize`.

`visualization:visualize` reads the argument, its `medium` option and the cascade (the Wave-1
adopter above). `machine-health:audit` writes no model-written view: its report is markdown, and
its decision page is on the shared builder (below). Every surface the grandfathered list named has
left it, and the list is empty.

Emitters on the escape-helper gate (the third bullet of the security baseline), each building
its page with a checked-in builder: `education:teach` (codebase mode),
`knowledge:video-digest`, `harness-ops:observability`, `event-storming:simulation`. They left the
grandfathered list when they moved onto it.

Emitters on the shared builder (`lib/view-builder.mjs`, interactive profile): `education:illustrate`
(`plugins/education/skills/illustrate/scripts/build-explainer.mjs`), which has left the grandfathered
set and defaults to a local `file`, then `terminal`, publishing an artifact only when an argument or
a layer asks for one; `planning:brainstorm`, offering its view from a checked-in template plus the
session's JSON as data, and `planning:plan` and `planning:design`, offering views of PLAN.md and of its
`## Design` section, each kind an entry in the
builder's view-kind registry rendered through `render(laneId, kind, record)`
(`plugins/planning/scripts/build-view.mjs`); `debugging:debug` (post-mortem) and `discovery:blindspot`, built
the same way (`plugins/debugging/scripts/build-view.mjs`, `plugins/discovery/scripts/build-view.mjs`); and the
`architecture` `map-*` skills, each offering a view of its JSON record from one checked-in template
(`plugins/architecture/scripts/build-view.mjs`); and the `machine-health:audit` decision page, which
its orchestrator builds for each run from `latest.json`
(`plugins/machine-health/skills/audit/scripts/build-checkup-view.mjs`), with a copied payload that
`machine-health:setup picks` resolves against the run's id map; and `work-items:morning-brief`
(genre: reports and status), which builds its status page from the printed brief
(`plugins/work-items/skills/morning-brief/scripts/build-brief-view.mjs`) and resolves `medium` from
the cascade, defaulting to a local `file`; `artifact` or `hosted` from the team layer keeps the page local.

Assessed under the genre rubric and given no lane:

- `education:explain`: a concept explainer, but its answer is short text the reader uses where they
  read, the cheapest form. Its page and video views already exist as `education:illustrate` and
  `explainer-video:produce`.
- `knowledge:docpage-digest`, `knowledge:distill` and `knowledge:absorb-upstream`: each delivers a
  record a later pass reads (a knowledge slice with its interview handoff, skill reference files,
  a tracked `docs/upstream` record). The next consumer is that pass, not a person, so no genre
  applies. `knowledge:video-digest` is on the escape-helper gate (above).
- `knowledge:course-digest` (genre: reports, for `repo-candidates.md` and `action-items.md`;
  dual-audience, since each action item needs research before adoption): the person works the
  report in the markdown itself, ticking `action-items.md`'s checkboxes, so a page would be a
  read-only second copy and the text form loses nothing. Its course directory (transcripts,
  frames, module summaries) is a digest, which is always markdown. The course is paid content
  kept in a private work root, so a view of it could never publish.
- `knowledge:map-corpus` (genre: plans presented for approval, for its Phase 3 map approval;
  dual-audience, since later phases re-read the approved `link-map.json`): the person approves or
  narrows a map of at most `max_resources` in-corpus rows (default 30), shown as tallies, the
  in-corpus list with reasons, bounds and batch plan, which the text form serves without loss.
  `queue.json` lists the URLs handed to the `knowledge:docpage-digest` runs; it is a record, so
  it gets no view. `mapper-handoff.md` (genre: reports) goes to `planning:interview` when that
  plugin is installed, and its read-only decision table (above) is the view of what comes next;
  otherwise the person reads it directly. It is a short markdown summary of tallies, `uncertain`
  verdicts with evidence, companion and external lists, and drop candidates, so the text form
  serves those drop decisions without loss.
- `testing:audit`: the scanner's output, presented as the script prints it: one rule-tagged
  `path:line` row per finding and a coverage block. Its gate (`--check`) and its fix-pass file
  (`--persist-findings`) are separate script modes. The text form loses nothing a page would add.

Emitters through an Artifact type (see Artifact types): `/visualization:present`, a deck made from
the account's Slides type, gated by `plugins/visualization/skills/present/scripts/check-deck.mjs`.

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
  `/education:quiz-me` is on that gate, and `/review:explain-change` builds through the
  shared builder. Such a lane is K2 (see Content classes); the shared builder carries the
  same helper and adds the interactive profile.
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

### Documented escape exceptions

Two emitters stay off `lib/html-escape.mjs`. Each is held to the baseline above by other means.

- **Python emitters.** `plugins/planning/surface/exporters.py`, `plugins/planning/surface/interview_server.py`
  and `plugins/pixel-art/scripts/gallery.py` escape with the stdlib `html.escape`,
  which replaces `&`, `<`, `>`, `"` and `'`, the same five characters the helper does. The helper is
  a JavaScript module and these emitters run in Python, so a shared Python helper would be a second
  copy of the same five-character table. `quote=True` is the default in Python 3, so the
  one-argument call escapes the same five. The URL-position rule still applies: `interview_server.py` checks
  an image `src` against a `data:image/` or `http(s)` prefix before it escapes it. A new Python
  emitter uses `html.escape` and never passes `quote=False`.
- **`/playbooks:repo-sweep` page.** `render.sh` splices one JSON document into the template's
  `<script type="application/json">` block and rewrites every `<` in it to the six characters backslash, `u003c`. In a data
  block the only way out is a `</script>` sequence, and with no `<` left in the text none can form.
  That escape parses back to `<` in `JSON.parse`. The template renders the parsed values with
  `textContent` only, so nothing from the JSON is read as markup. The splice must stay at exactly
  one token inside a non-executing data block; JSON placed in an executable script block, or
  rendered through `innerHTML`, goes through the helper instead.

## Accessibility floor

The floor (contrast pairings, focus visibility, color-scheme and reduced-motion behavior,
keyboard reach) lives in the shared chrome reference, as the web instance of the
medium-neutral floor `/user-interface:design` applies to every interface. Accessibility is a named, sanctioned
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
live-state exports. A view may carry more than one, and adding a shape the reader did not
need is overproduction: this section names an obligation, not a floor to hit on every
page. On a K2 page every payload carries only reader input and builder-assigned ids
(see View tiers), so a K2 page has no generated follow-up prompt and no export rebuilt
from data-block strings.

### Reply-affordance rule

**The rule.** A generated review artifact ends with a structured reply affordance: a
machine-legible way for the human's reaction to become the next prompt: steal/skip
choices, a chip-filled reply template, a decisions table, a confirmation token. Default
with judgment: apply it to artifacts that exist to collect a decision; skip it for purely
informational output. In session contexts that render artifacts (the `artifact-design`
built-in skill's territory), the affordance rides the artifact; in plain chat it is a
reply template in the closing message.

**Who is bound.** Skills that generate decision-collecting artifacts cite this section
instead of restating it.

**Conformance** = the template blocks in `prototype:explore-directions` (structured
steal/graft capture and the assembled-reply template) and `prototype:pressure-test` (the
validation answer set). Fleet audits check those surfaces against this section.

### Export-button rule

**The rule.** Every interactive HTML artifact our skills emit ends with a control that
copies the state the user built out as text they can paste into the session or commit. For
the author's version of this rule, see S2, section "Custom editing interfaces"
([source list](../../finding-your-unknowns.md#sources-and-citation-shape)). The doctrine
recurs three times independently in the corpus; it is what keeps a throwaway editor inside
the agent loop instead of becoming a dead end.

**Who is bound.** Skills that emit interactive HTML artifacts cite this section.

**Conformance** = the same template blocks named in the
[reply-affordance rule](#reply-affordance-rule); the export button is the HTML-artifact form
of the reply affordance.

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

Canonical copy: `lib/html-chrome.html`. `scripts/sync-shared-copies.sh` generates each
adopting plugin's `reference/html-chrome.html` from it, with the generated-file header after
the doctype; edit the canonical, then rerun the script. An adopting plugin registers its copy
in `scripts/shared-copies.txt` and its path in `scripts/check-html-assets.sh`. The
visualization, adhd and planning plugins carry it. Skills cite the reference inline by role
(their plugin's own copy), never by a repository path an installed consumer cannot resolve.

The chrome is one for every page family: the system/light/dark toggle (system by default,
`button[data-rv-theme]`), the comment box (`textarea[data-rv-note]` under a labeled
heading), and the accessibility floor. A page offers no other theme choice: no team or user
theme override, no accent or palette picker. A built view copies the chrome's toggle and
comment markup and its `rv-chrome` style rules verbatim, and its plugin's tests compare them
with the plugin's copy of the chrome.

The chrome's ivory page background (`--ivory`) is the sanctioned default background for a
view built on it, so no skill's "styles to leave out" list names a cream or off-white
background. Those lists name layout habits (italic accent words in headings, numbered
section labels, pill-shaped buttons, a hero banner). A lane that departs from the
chrome's palette declares its own background instead of banning this one.

## The `rendered-views` settings

The cross-plugin `medium` preference rides the
[config-cascade convention](../config-cascade/README.md) on the ADR 0075 scopes; this section is
the concern's owner declaration. One resolver, `lib/view-settings.mjs`, applies it for every view
lane. A skill runs its `resolve` command and never reads the files itself.

- **Scopes**: the argument, the lane plugin's `medium` userConfig option, the team file
  `docs/conventions/rendered-views.yaml`, and the personal override
  `docs/conventions/rendered-views.local.yaml`, both in the repository's convention home. The
  resolver reads each scope's own value with the cascade's file reader and schema check
  (`readLayers` in `lib/config-cascade.mjs`), never the merged result, so a lower scope's local
  value survives a higher scope's publishing one.
- **Keys**: `medium`, one of `auto`, `terminal`, `file`, `artifact`, `hosted`. `auto` is no
  preference: it resolves exactly as unset. Future keys are added here first.
- **Precedence and the publish trust walk.** `medium` chooses whether a view leaves the machine,
  so precedence alone does not decide it:
  1. The argument decides alone.
  2. Otherwise a `terminal` or `file` value from any scope keeps the view local. When several
     scopes set one, ADR 0075 precedence names the one used: personal override, then team, then
     userConfig.
  3. Otherwise the first publishing value (`artifact`, `hosted`) from a trusted scope wins: the
     personal override, only while it is untracked and gitignored with no symlink, submodule or
     tracked entry on its path, then userConfig. A team file never publishes, because a checked-out
     branch can write it.
  4. With no scope deciding, the lane's own default applies. It ships with the installed plugin,
     which a checked-out branch cannot write, so a publishing default counts; it never counts as a
     scope in step 2. The publish gate still checks content under a default: only steps 1 and 3
     make a choice the gate takes as explicit.

  An invalid value is reported and ignored without dropping another scope's value. This is not
  plain ADR 0075 precedence: under it a personal `artifact` would override a team `file`.
- **Team file from a git ref.** A lane that must not let a checked-out branch configure it
  (`/review:explain-change`) reads the team file from a named commit (`--team-ref`), never the
  working tree. A ref that names no commit reads no team file and says so.
- **Retired files.** `~/.claude/rendered-views.md`, `.claude/rendered-views.md`,
  `.claude/rendered-views.local.md` and a fenced config block in
  `docs/conventions/rendered-views.md` never give a publishing value. A retired file's `terminal`
  or `file` value keeps the view local only when no scope sets one, naming that file; when several
  retired files set one, `.claude/rendered-views.local.md`, then `.claude/rendered-views.md`, then
  the fenced block, then `~/.claude/rendered-views.md` names the one used. Each gives one notice
  per lane plugin per project, naming its value and where to set it instead: the team file or the
  personal override, and for the user file the personal override, else the plugin's `medium`
  option. A notice repeats only when the file changes. The shown-once
  state lives in each plugin's data directory, keyed by project identity
  ([plugin-data report keying](../plugin-data-report-keying/README.md), rule 1), and is written
  atomically.
- **Resolution**: `view-settings.mjs resolve --lane <id> --option <user_config.medium>
  [--argument <medium>] [--team-ref <ref>]` prints the resolution as one JSON line (`preferred`,
  `medium`, `decidedBy`, `notices`), then the report line (see Reachability and the fallback
  chain). Each lane registers once in the medium registry with its view kinds, whether it is
  hosted-capable, and its default.

## Template vendoring posture

**Decision.** Do not vendor the 31 html-effectiveness corpus templates (20 gallery +
11 unknowns). The derived chrome and token reference
(`lib/html-chrome.html`) is the sanctioned shared piece.
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
- **Recheck:** a lane that cannot cite a public page-shape and must ship a
  checked-in HTML page of its own, or a license change on either source.

## What this convention does not do

- It never makes a view the record: the markdown record stays authoritative everywhere.
- It adds no generic HTML skill, one whose job is "make a page" for any content. Thin
  intent-named skills are allowed: a skill named for what the reader is trying to do
  (`/review:explain-change` explains a pull request) may emit a view as its deliverable,
  owning its genre's page shape and reusing the shared builder and chrome.
  `visualization:visualize` stays a router that owns no craft.
- It does not vendor the 31 corpus templates: see Template vendoring posture.
