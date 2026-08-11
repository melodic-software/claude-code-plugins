# Publisher profile — Anthropic docs

Publisher-specific configuration for `/knowledge:docpage-digest` runs against Anthropic
documentation properties (`platform.claude.com`, `code.claude.com`, `claude.com/blog`,
`anthropic.com/engineering` — hosts match with or without a leading `www.`; live engineering
links use `www.anthropic.com`). The pipeline engine in `SKILL.md` stays generic; everything here
is this publisher's own contract. A second publisher joins as a sibling profile file; engine
extraction waits for the third (Rule of Three).

## Fetch channel

- **Docs pages (`platform.claude.com/docs/...`, `code.claude.com/docs/...`):** append `.md` to
  the page URL for clean raw markdown. Channel verified working for the Opus 5 prompting guide
  (2026-07); **re-verify per doc** — precedent, not a guarantee. Fallback: fetch the rendered
  page and record the degradation.
- **Cite a LIVE page by anchor, never by line number.** These pages gain and lose rows between
  reads and the `.md` channel renumbers with them, so a `<page>.md:<line>` citation rots silently
  into a pointer at an unrelated row. Cite the heading, the table row's key, or the variable name —
  something the page itself carries. This repo has the measurement, from its own two reads of
  `env-vars.md`: 451 lines and 316 rows when the absence rule below was written, 458 lines and 315
  rows on 2026-08-10, so both a growth and a removal landed between them. The attested near-miss
  instance recorded as `env-vars.md:394` moved that way — 394 is `DISABLE_UPGRADE_COMMAND` today,
  and the row the instance describes (the only one on the page that both describes Claude Code's
  own retry behavior and names a model subject; the sibling
  `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` names none) is `FALLBACK_FOR_ALL_PRIMARY_MODELS`, at
  line 400 that day. Line numbers into an **archived snapshot** this pipeline captured are
  unaffected: that file is immutable, which is exactly what makes its line numbers citable.
- **Blog posts (`claude.com/blog/...`):** no raw-markdown channel known; fetch rendered and
  extract. Record the channel used. **Two extraction artifacts reproduce on this channel; record
  them, never repair them** — `source.*` is immutable, so the fix belongs in whatever reads the
  snapshot, not in the snapshot. (a) The animated hero heading collapses every space in the H1.
  Reconstruct the title from the canonical URL slug, which the checklist already records — but the
  slug recovers word boundaries only, never punctuation or casing
  (`claude-models-explained-choosing-the-best-model-for-your-use-case` cannot yield the colon in
  "Claude models explained: choosing the best model for your use case"), so a title recovered that
  way is labelled reconstructed. When the run also retained the rendered HTML, that file's
  `<title>`/`<h1>` carries the exact form — but nothing in the pipeline contracts such a file, so
  it is a bonus, not the method. (b) The reading-time widget splits its value and its unit onto
  separate physical lines, so neither line reads as a duration on its own. (Both observed
  identically in two runs, at each slice's `source.md:7`:
  `# Claudemodelsexplained:choosingthebestmodelforyourusecase` with the reading time at lines
  83/87, and `# BuildingverificationloopsinClaudeCodewithskills` with it at lines 45/49.)
- **PDFs (model/system cards):** download the original binary as `source.pdf` plus a text
  extraction as `source.txt`; both are originals, the extraction tooling is named in the
  checklist.
- **Absence-establishing fetches must be complete.** Any fetch that will support a negative claim —
  an `api-only` basis, a "no harness surface states this" finding — goes through the raw `.md`
  channel with `curl` and records the retrieved length; a rendered `WebFetch` of a long page returns
  a silent prefix with no truncation signal. The asymmetry is what makes this binding: a truncated
  fetch cannot fabricate a PRESENCE, only an ABSENCE. (Two runs asserted a false absence exactly
  this way. In the steering-thinking slice the orchestrator's *resolution* re-fetched the same page
  through the same channel and reproduced the blind spot instead of testing it —
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` sits at line 277 of a 451-line, 316-row page whose rendered fetch
  surfaced only roughly its first fifth.) This rule is the fleet-wide
  [fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis--the-fetch-route)'s
  rung 1, which the upstream-drift convention now owns for every surface; the asymmetry above stays
  here because it is this pipeline's reason for binding the rung to absence claims specifically.

## Archive-reading conventions

Some pages this publisher maintains are archives — dated entries accumulated over time rather than a
current statement, the [published system
prompts](https://platform.claude.com/docs/en/release-notes/system-prompts) being the standing case.
Everything inside a dated entry is scoped to that entry's date. Three further properties of such a
page are invisible from inside any single entry, and a digest that does not know them reads the
archive wrong in a way its own verification cannot catch:

- **A dated entry is not a content-change signal.** Two entries can be byte-identical and here two
  are: entries five days apart differ on zero lines across 100-line bodies, and the page carries no
  annotation explaining why the second one exists. Record the re-publication as what it is; never
  infer a revision, an intent, or a policy movement from the appearance of a new dated heading.
- **Absence of bold does not prove absence of change.** The page states that updates between
  versions are bolded, and that convention does not hold: one span of the archive carries zero bold
  markup across three dated entries that differ in three sentences plus a twelve-paragraph addition,
  and another entry marks one transition of three. Silent unbolded typo fixes and a silent removal
  were found the same way. Treat an unbolded inter-entry difference as an authoritative delta of
  equal standing to a bolded one, which means the deltas come from diffing entries, never from
  reading the markup.
- **Note a source artifact at the row; never silently repair it.** Typos, escaped markup and
  malformed auto-links are reproduced byte-exact so a verifier can tell faithful reproduction from
  digest transcription error. The two blog-channel extraction artifacts under **Fetch channel**
  above are this rule's standing instance. One exception, and it runs the other way: a downstream
  artifact reproducing a known-corrupt entry *for a reader* rather than for verification repairs the
  corruption and says that it did.

## Claude-Code-applicability filter (with teeth)

Anthropic docs mix API-surface guidance with harness-relevant guidance. Every digest tags each
claim's applicability (`cc-applicable` / `api-only` / `mixed`, or the tag-exempt disposition
below for material the vocabulary does not adjudicate), with evidence scaled to what the tag
asserts:

- **`cc-applicable` / `mixed` (positive claims):** verified against live code.claude.com docs at
  tag time — cite the URL consulted in the digest row. A positive tag assigned by inference,
  without a live-doc check, is additionally recorded as `unverified-inference` and becomes an
  interview question, never a silent fact. (This rule exists because inference has already produced a
  wrong tag once — the failure mode is real.)
- **`api-only` (a negative claim — "no harness surface exists" for the claim's own specific
  assertion; see the near-miss rule below):** absence cannot be proven from one page. Record the
  basis (the harness doc section(s) checked, or `unverified-inference` when
  none was); a contested or load-bearing `api-only` tag escalates to the interview rather than
  standing on an absence citation. **The basis records the exact command run and its raw result
  count**, not a prose summary of what was checked — an attested zero is not a reproducible zero,
  and a row that both performs an absence search and certifies its own result leaves a verifier
  nothing to replay. (One run produced eight fabricated absence bases before this rule was imposed;
  every one was caught against the corpus rather than by the producing agent — `llms.txt` asserted
  absent while present in 174 files, `thumbs` while `data-usage.md:28` states it, `knowledge cutoff`
  while `changelog.md:4820` states it.)
- **Every non-zero result names its match site(s).** A recorded count plus a filename histogram is
  still unfalsifiable: a reader who replays the command gets the same number and still cannot tell
  whether anyone read the matching lines. A row whose hit set was **sampled** rather than read in
  full states that scope at the row. (Adopted slice-wide as a ruling in the system-prompts run and
  still the most-violated rule in that slice; the cost is documented, not hypothetical — an
  undisclosed `settings.md:727` near-miss was exactly what the unread portion of a 199-line hit set
  contained.)
- **What falsifies `api-only`, and what only comes close — written down once, because the whole
  class of defects here is the boundary being re-derived per row.** `api-only` asserts no harness
  surface for **the claim's own specific assertion**, so only the corpus documenting *that
  assertion* falsifies it; topical overlap never does. Below that falsifying line sits the
  **near-miss** — a harness page covers the row's subject without stating the row's specific rule.
  The tag survives, the row MUST name the near-miss by page and line (the term this profile already
  uses of `settings.md:727` above), and an affirmative "no surface" or "undisclosed" phrasing in
  such a row is simply false and goes. Silence here was the largest MINOR class in the slice that
  measured it: one release-notes unit disclosed 24 near-miss rows on its own, and two sibling units
  in that slice raised the same boundary independently, one of them asking outright for a standing
  notation so a reader can tell "no surface at all" from "adjacent surface exists".
- **What a harness surface *is*, and three shapes that come close without falsifying it.**
  **[campaign-owned amendment]** A harness surface is a surface a user can reach. The following do
  **not** falsify `api-only`: (1) a **counterpart artifact** — the harness has a thing playing the
  same role, without referencing the claimed artifact; (2) a **same-workload mention** — a doc names
  a workload another guide teaches, with no shared guidance or cross-reference;
  (3) **[campaign-owned amendment] harness-internal recognition or support** — a harness doc names
  the subject in describing the harness's own internal behavior toward it, without exposing a
  user-reachable path to it (sole attested instance: retry/fallback, `env-vars.md`
  `FALLBACK_FOR_ALL_PRIMARY_MODELS`). Each such
  hit is disclosed as a near-miss per the rule above. Both labels are load-bearing, not decoration:
  shapes (1) and (2) carry an identical adjudication from two independent verification arms, but
  nothing in the corpus ever *defined* "harness surface", so an unlabelled definition would read as
  inherited when it is this choice — selection over support — being made. Sub-shape (3) stands on
  **one** attested instance against that two-instance base, and is enumerated no wider than that: a
  doc line describing some *other* model's tier is not harness-internal behavior toward the subject,
  fails (3)'s own test, and is disclosed as a near-miss without entering this list.
- **`tag-exempt (<sub-shape>)` — material the vocabulary does not adjudicate.** One disposition
  for rows carrying no guidance for ANY surface the applicability vocabulary adjudicates, with the
  sub-shape named at the row. Four sub-shapes: `consumer-surface` (a different product surface,
  e.g. claude.ai web/mobile), `archive-descriptive` (an archive's own apparatus and entry
  structure), `metadata` (dates, titles, version labels), `navigation-pointer` (links and
  cross-references). The disposition describes the material's genre and asserts nothing about
  harness applicability — it is not a positive tag and not a negative claim — so it owes no
  live-doc citation and no absence basis, and the near-miss disclosure burden never attaches.
  `api-only` remains reserved for rows that DO assert a harness absence for their own specific
  assertion.
- **`cc-applicable`/`mixed` boundary:** a claim that names an API surface (parameter, endpoint,
  SDK call, model ID) tags `mixed` even when its guidance transfers to the harness;
  `cc-applicable` is reserved for claims naming no API surface. **Bare names are not API
  surfaces:** a product name, display name, or docs-path slug never by itself triggers `mixed` —
  only the four surfaces above do. (Ratified from the de facto standard 15+ rows already stood
  on, applied in-slice by a cross-vendor retag; a tier-name line such as `changelog.md:961` is
  therefore a bare-name near-miss — disclosed per the near-miss rule — not an API surface and
  not a harness surface.)
- **Row-local, tag always present:** the evidence (a positive tag's live-doc URL, an `api-only`
  basis) appears in the claim's own row — "same basis as claim N" does not satisfy the contract —
  and every claim carries exactly one vocabulary tag: `unverified-inference` is an additional
  uncertainty marker, never a substitute for the tag. (Both rulings from the sonnet-5 guide
  slice's cross-vendor verification, where citation-by-reference and marker-as-tag were the
  dominant correction class.)
- **Row-local reachability — a cited site no recorded command produces has been asserted, not
  disclosed.** A `file.md:NN` in a row's evidence counts as disclosed only when some command
  recorded in that same row produces it; otherwise the row says so explicitly, and an explicit
  read-not-grepped note is the sanctioned form. Two corollaries the evidence forces: a `| wc -l`
  count produces no sites and cannot support a citation, and a site named from a sampled set records
  the narrower command that reaches it. (Three independent auditors raised this class separately — a
  corrector and both verification arms, each with its own instrument; arm A measured 57 citations
  across ~35 rows in one slice produced by no command in their own rows. Every cited line was read
  and found true, so the claims survived and the defect was the audit trail — which is precisely why
  no verifier's spot-check substitutes for the rule.)
- **Harness docs are their own live basis:** when the digested page is itself a live
  code.claude.com harness doc, intrinsic harness-guidance claims cite the canonical page URL +
  section as their row-local basis; the boundary rule still routes claims naming an API surface
  to `mixed`, and third-party APIs (e.g. the GitHub API) count as API surfaces — no vendor
  exemption. (From the best-practices slice: the third-party-API ruling is its cross-vendor
  finding; the own-basis rule was applied there and ratified by both re-verifications.)
- **Vendor-blog attestation:** a `claude.com/blog` page is marketing-adjacent vendor voice, not
  reference documentation. Any assertion of fact that exists ONLY in the blog (no harness or
  platform doc states the same assertion) — behavioral, performance, figure/percentage,
  comparative, frequency, methodological/definitional, positioning, or any other class; the
  list is illustrative, not exhaustive — additionally carries
  `vendor-claimed (blog, <fetch date> fetch)` beside its vocabulary tag — assertion-specific
  (related-property citations never exempt it), never co-occurring with a live-doc citation for
  the same assertion, and never deferred to the interview. The marker is an attestation note
  that composes with the tag and, where applicability itself is inferred, with
  `unverified-inference`. (Shape recommended by the context-engineering blog slice's handoff,
  exercised end-to-end and enforced by both verifiers on the models-explained slice.)

## Digest-agent model matching

A model-specific guide digests on the model it describes — the subject model recognizes its own
behavioral descriptions:

| Doc subject | Digest-agent model |
|---|---|
| Guide/card about a specific Claude model | The exact model version the doc describes, resolved to its pinned model ID — never an alias that can move to a newer snapshot, which would digest a historical guide on the wrong version. When no pinned ID is resolvable, omit the override (session default) |
| Cross-model or harness doc (best practices, effort, guardrails) | Session default (no override) |
| Non-Claude subject | Session default (no override) |

Pinned-vs-alias semantics are generation-dependent — since the 4.6 generation the dateless ID is
itself the pinned snapshot, while earlier models pin a dated snapshot and their dateless aliases
move — resolve them at spawn time against the live
[model IDs and versioning page](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions).

Every model-pinned spawn brief uses the conditional framing contract from `SKILL.md` Phase 3
("this brief assumes model X; if you are not X, note the mismatch and continue").

## Doc queue

Pending Anthropic docs for this pipeline. Verify each URL live at fetch time; remove entries as
their slices complete.

Thinking (completes the set's custody map — troubleshooting first):

- <https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting>
  — the harness documents this page's specific assertions on its own pages (`errors.md` documents
  thinking-configuration 400s; `prompt-caching.md` documents cache-miss causes), which is
  claim-level transfer under the falsifying rule above, not topical overlap; the digest still tags
  each claim against those pages individually — this entry pre-classifies none of them
- <https://platform.claude.com/docs/en/build-with-claude/thinking-tool-workflows>
  — the last uncovered page of the thinking doc set; two already-digested slices defer to it by
  anchor, so the marginal cost of the last page is the lowest it will ever be

Retention and ZDR (one topic slice, two lanes, drained as three page runs — one page per run, per
the engine; retention is org-level policy and the one topic queued here carrying compliance
weight, and both properties are already in scope):

- <https://platform.claude.com/docs/en/manage-claude/api-and-data-retention>
  — the API lane
- <https://code.claude.com/docs/en/data-usage>
  — the harness lane
- <https://code.claude.com/docs/en/zero-data-retention>
  — the harness lane's enterprise posture: ZDR is scoped to qualified accounts on Claude for
  Enterprise, which is the commitment a consuming setup needs stated rather than inferred

Agent SDK (one page — SDK docs are canonically harness docs, but queueing the rest of that doc set
is a separate scope decision nobody has taken):

- <https://code.claude.com/docs/en/agent-sdk/agent-loop>

Models:

- <https://platform.claude.com/docs/en/about-claude/models/overview>
  — the canonical model-fact freshness source; re-fetching this one page *is* the freshness check,
  where a release-notes corpus would grow monotonically and age entry by entry
- <https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5>
  — the launch source the corpus's own Fable 5 / Mythos 5 positioning claims rest on, and linked
  from the harness model-config doc's "Work with Fable 5"
- <https://platform.claude.com/docs/en/about-claude/models/whats-new-opus-5>
  — enqueued on custody grounds, not on a fleet-lane trigger that has not fired: the `playbooks`
  Opus 5 model-adaptation chapter cites this page as sole authority for three shipped claims —
  thinking on by default, the 400 returned when thinking is disabled above effort `high`, and the
  live effort-level enumeration that establishes the upstream Opus 5 prompting guide's own ladder
  statement as truncated — none of which the models `overview` page carries, so "the overview covers
  it canonically" is false for exactly the facts already cited. A custody fact about this one page,
  not a decision to start a release-notes corpus; `whats-new-sonnet-5` carries no such citations and
  stays deferred

Claude Code companion docs (digest in this order):

- <https://code.claude.com/docs/en/features-overview>
- <https://code.claude.com/docs/en/memory>
- <https://code.claude.com/docs/en/how-claude-code-works>

Blog posts:

- <https://claude.com/blog/the-advisor-strategy>
  — the harness advisor doc cites this post as its own "why"; digest it alongside
  <https://code.claude.com/docs/en/advisor> and
  <https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool> so one slice covers
  the concept's three surfaces
- <https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns>
  — the designated deep-dive for prompting the Claude 5 generation, already being read by local
  work without a custody record, applicability tags, or an attestation pass

Engineering posts:

- <https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents>
  — the cited best-practices source for custom agent evaluations, and methodology input to the
  deferred re-pin checklist and the eval-set gap

Deferred with trigger (not queued):

- <https://platform.claude.com/docs/en/build-with-claude/task-budgets> — api-only (the page
  states task budgets are not supported on Claude Code or Cowork; verified 2026-07-27); enqueue
  when harness support lands
- <https://code.claude.com/docs/en/context-window> — read against the 2026-07-31 harness snapshot
  rather than left untested: it documents behavior as the limit approaches (Claude Code compacts
  automatically) but never the `model_context_window_exceeded` stop reason, so it does not move the
  claim it was checked for; enqueue if the page starts documenting that stop reason's handling
- <https://platform.claude.com/docs/en/build-with-claude/fallback-credit> — the two API-side claims
  it would settle carry a weak, openly disclosed absence basis that nothing is built on; enqueue
  when an artifact actually depends on fallback-credit behavior
- <https://platform.claude.com/docs/en/about-claude/models/whats-new-sonnet-5> — release notes for a
  model the models `overview` page already covers canonically; enqueue when Sonnet 5 enters or
  materially changes a fleet lane
- <https://claude.com/blog/complete-guide-to-building-skills-for-claude> — a vendor-voice
  restatement of a schema whose first-party canons are already reachable, so digesting it adds
  attestation cost and no authority; enqueue for the first artifact that needs schema detail no
  first-party canon states

## Artifact targets

Interview-handoff dispositions for this publisher typically route to: per-model doctrine
chapters (a playbooks-style model-adaptation seam), instruction-audit rule rows (a
model-delta audit class), corpus graduation (a knowledge-corpus repository), or cross-slice
synthesis (a cross-model artifact spanning units and slices the per-unit digest fan-out cannot
reach — not per-model, not an audit rule row, not graduation of one slice; its host is
undecided). The handoff records the candidate target per finding; the interview decides.

## Hedge preservation, and the residual-risk footer

A source's own hedge travels with the content it qualifies. An artifact graduated from this
publisher preserves the hedge as the source states it — neither dropped as throat-clearing nor
widened past what the source claims. The footer below is the standing instance; the harness
best-practices material's "starting points, not set in stone" relativization is the second, and both
graduate under this one convention rather than each inventing its own.

**Residual-risk footer.** Every artifact derived from a guardrail page of this publisher carries
that page's OWN residual-risk sentence when the page states one, quoted rather than paraphrased —
a hedge scoped to one page's techniques never transfers to an artifact derived from a different
page. The standing instance, for artifacts derived from [Reduce
hallucinations](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations)
(verified 2026-08-03):

> Remember, while these techniques significantly reduce hallucinations, they don't eliminate them
> entirely. Always validate critical information, especially for high-stakes decisions.

Its scope is the source's own and stays unbroadened. It is about **hallucinations**, not errors,
regressions, or guardrail failures in general; and it names **no validator** — who or what validates
critical information is unstated in the source and stays unstated here. Widening the failure mode or
supplying a mechanism states something the source does not.

The footer attaches at this profile, not per artifact, because the profile is the seam every
guardrail slice of this publisher flows through. A graduated chapter or template **cites this
footer**; it never restates it.
