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
  surfaced only roughly its first fifth.)

## Claude-Code-applicability filter (with teeth)

Anthropic docs mix API-surface guidance with harness-relevant guidance. Every digest tags each
claim's applicability (`cc-applicable` / `api-only` / `mixed`), with evidence scaled to what
the tag asserts:

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
  user-reachable path to it (sole attested instance: retry/fallback, `env-vars.md:394`). Each such
  hit is disclosed as a near-miss per the rule above. Both labels are load-bearing, not decoration:
  shapes (1) and (2) carry an identical adjudication from two independent verification arms, but
  nothing in the corpus ever *defined* "harness surface", so an unlabelled definition would read as
  inherited when it is this choice — selection over support — being made. Sub-shape (3) stands on
  **one** attested instance against that two-instance base, and is enumerated no wider than that: a
  doc line describing some *other* model's tier is not harness-internal behavior toward the subject,
  fails (3)'s own test, and is disclosed as a near-miss without entering this list.
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
| Guide/card about a specific Claude model | The exact model version the doc describes, resolved to a full model ID — never a bare family alias, which resolves to the current family model and would digest a historical guide on the wrong version. When no exact-version ID is resolvable, omit the override (session default) |
| Cross-model or harness doc (best practices, effort, guardrails) | Session default (no override) |
| Non-Claude subject | Session default (no override) |

Every model-pinned spawn brief uses the conditional framing contract from `SKILL.md` Phase 3
("this brief assumes model X; if you are not X, note the mismatch and continue").

## Doc queue

Pending Anthropic docs for this pipeline. Verify each URL live at fetch time; remove entries as
their slices complete.

Thinking (completes the set's custody map — troubleshooting first):

- <https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting>
  — the harness carries a parallel troubleshooting surface (`errors.md`, `prompt-caching.md`), so
  this page's transfer to the harness is demonstrated rather than conjectured; digesting it is what
  lets the corpus state the mapping instead of guessing at it
- <https://platform.claude.com/docs/en/build-with-claude/thinking-tool-workflows>
  — the last uncovered page of the thinking doc set; two already-digested slices defer to it by
  anchor, so the marginal cost of the last page is the lowest it will ever be

Retention and ZDR (one slice, two lanes — retention is org-level policy and the one topic queued
here carrying compliance weight; both properties are already in scope, so the slice costs one
fetch):

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
- <https://platform.claude.com/docs/en/about-claude/models/whats-new-opus-5> — release notes for a
  model the models `overview` page already covers canonically; enqueue when Opus 5 enters or
  materially changes a fleet lane
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
