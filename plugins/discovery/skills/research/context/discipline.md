# Research discipline — sources, recency, falsification, broad topics

Recipes and rationale behind the bars stated in the research skill's SKILL.md body, plus failure patterns observed in real sessions.

## Source tiers (canonical for this plugin)

| Tier | Source | Counts as |
|---|---|---|
| Tier 0 | Direct tool output captured this turn (`<bin> --help`, file Read, `gh api`, MCP tool result) | Strongest. Primary |
| Tier 1 | Official documentation **fetched this turn** with URL captured (vendor docs, GitHub source, language spec, RFC, upstream changelog) | Primary |
| Tier 2 | Secondary synthesized (AI-synthesis answers, Stack Overflow, recognized author blog, vetted vendor blog) | Secondary — corroborator only |
| Tier 3 | Synthesis without grounding (training-data recall, vague "I remember reading," subagent return without primary citation) | NOT acceptable for claim acceptance — must promote to Tier 0/1 first |

## Source-tier ratio (per claim)

Mandate: every accepted claim has **≥1 Tier 0/1 source PLUS ≥2 independent corroborators** of any tier.

**Anti-pattern:** three AI-synthesis citations of three different secondary blogs = 1 Tier 2 source, not 3. They're synthesizing from the same upstream pool. Count INDEPENDENT primary sources, not citation count.

**Tool-diversity per topic — MUST track in the evidence table.** Two sources both from one synthesis tool / both from one search engine / both from one author's blog network = 1 corroborator, not 2.

## Recency gate (for libraries, tools, CLIs, APIs)

Mandate: when the topic touches a library/tool/CLI/API/framework that ships releases, **one Phase 1 or Phase 2 query MUST fetch the LATEST upstream changelog or release notes this turn** and confirm the claims are current as of it. Acceptable forms: `gh api repos/<owner>/<repo>/releases/latest`, WebFetch on a raw `CHANGELOG.md` URL, the vendor's "What's New" page. The windows below bound how stale a cited doc may be before this cross-check is required — a stable project whose latest release is older than the window still passes once that release is confirmed to be the current one.

**Tightening tiers:**

| Topic class | Recency gate |
|---|---|
| Very active project (weekly releases, breaking changes, security-sensitive) | 14 days |
| Standard library / tool / CLI / API | 30 days |
| Architecture pattern / conceptual guide | 90 days |
| Foundational doctrine (DDD, SOLID, Hexagonal) | No recency gate — concepts don't drift |

**Major version bump invalidates prior docs.** When the upstream repo moved `x.y.z` → `(x+1).0.0` since the doc was last updated, treat ALL prior docs as suspect — including first-party docs, which routinely lag a major release. Re-verify every behavior claim against the new release notes regardless of doc age.

## Falsification step (mandatory Phase 2 query)

Mandate: **exactly one Phase 2 query MUST attempt to falsify the leading hypothesis** from Phase 1.

**Falsification query patterns:**

- For a claim "X is canonical": query `"X deprecated"` OR `"X replaced by"` OR `"X removed in version"` OR `"alternative to X"`
- For a claim "X supports Y": query `"X does NOT support Y"` OR `"X Y incompatible"` OR the upstream issue tracker for Y limitations
- For a claim "use X for Y": query `"why X is bad for Y"` OR `"X anti-pattern"` OR a recognized author's critique
- For a claim "the convention is X": fetch the upstream maintainer's own latest writing OR the project's own CHANGELOG to check whether the convention shifted

**Why mandatory, not advisory:** without an explicit "try to break it" step, every Phase 2 query confirms Phase 1 by accident. Confirmation bias is the default behavior — falsification has to be enforced. Falsification cannot be retroactive: it must be a deliberate "try to break this" query, not a query that happens to surface contradicting evidence.

## Broad-topic auto-detect

Mandate: when the research topic matches ANY of the triggers below, **double all phase minimums**:

| Trigger | Example topic |
|---|---|
| 2+ vendors / 2+ tools / 2+ products named | "tool A vs tool B vs tool C memory conventions" |
| 3+ proper-noun product names in topic | "ORM + event store + messaging library integration" |
| Comparison topic ("X vs Y", "X or Y", "best of X/Y/Z") | "identity server A vs identity server B" |
| Multi-platform topic ("works on Windows, macOS, Linux") | "polyglot version manager comparison" |
| Migration / rebrand / convention-change topic ("from X to Y", "replaces X", "deprecates X") | "config format X replaces format Y" |

**Doubled minimums:** 6+ queries per phase (was 3+), 12+ queries total (was 9+), 5+ distinct tool types across the topic (was 3+ per phase), 4+ independent Tier 0/1 sources per claim (was 1+).

**Why:** multi-vendor topics have N times more drift surface. Each vendor ships its own changelog cadence, docs site, and naming-convention shifts. Single-vendor minimums under-cover the cross-vendor edges where hallucinations concentrate.

## Query scaling — floors are not targets

The per-phase minimums (3+ standard, 6+ broad-topic) are FLOORS to start from, not targets to stop at. Models satisfice to stated numbers, so a flat "3 per phase" reliably produces exactly-3 shallow phases. The corrective: make the query count a FUNCTION of the open-question count.

| Phase | Query count |
|---|---|
| Phase 1 | ≥3 — broad seed; the floor genuinely applies because you don't yet know the gaps |
| Phase 2 | one per numbered gap + one per numbered conflict + the mandatory falsification query (≥3, no cap) |
| Phase 3 | one per remaining gap after Phase 2, against preferred-source / tool-ecosystem authorities (≥3) |
| Phase 4 | one per still-open gap or LOW-confidence claim, until all reach HIGH |

Depth scales to the topic's actual open-question surface, not to a higher flat floor. A simple topic with 3 gaps runs ~3 Phase 2 queries; a gnarly one with 9 gaps runs 9.

## Tool-ecosystem Phase 3 fallback

Mandate: when no preferred-source author covers the topic's domain (typical for tool-ecosystem topics — AI coding tools, MCP servers, CI-platform specifics), Phase 3 MUST cite all three:

1. **Official maintainer** — the vendor's own social / GitHub / blog
2. **Upstream repo changelog or releases** — `gh api repos/<owner>/<repo>/releases` OR a raw `CHANGELOG.md` fetch this turn
3. **One recognized industry authority** — a top-voted community post or well-known practitioner blog with the author named

Don't skip Phase 3 because "no preferred author exists."

## Primary-source-first protocol

The "top of Google" is a ranking artifact, not an authority signal — SEO content farms outrank authoritative sources. The defense: never let the SERP BE the source. Three steps per claim.

1. **Name the canonical home before searching** — the official docs site / repo / spec / changelog that OWNS the answer. If the consuming project ships a per-ecosystem source mapping or preferred-sources roster (check its `CLAUDE.md` and rules), use it; otherwise identify the ecosystem's official docs site, package registry, and upstream changelog yourself. Probe for a published doc-index first per "Machine-readable doc-index discovery" below, and walk the artifact ladder below before concluding the answer is not there.
2. **Fetch it directly** — with whatever direct-fetch tool is connected this session. Discover what's available from your tool list, the injected MCP server-instruction blocks, and the project's MCP registry; don't hard-depend on a specific server. Fetching the canonical home directly bypasses ranking entirely.
3. **Synthesis + SERP discover and corroborate only** — find the canonical home when unknown, surface independent corroborators. A synthesized answer points you AT the source; it is never the terminal source for an accepted claim.

**The same claim is published at several depths — walk the artifact ladder top-down.** A SEARCH order for locating a claim's specifics, not an authority order: the tier table above ranks authority, and the recency gate's changelog cross-check stays unconditional at every rung. (The doc-index probe below enumerates *pages*; this ranks *artifact classes*.) Step 1 is not satisfied until the topmost rung that exists for the claim has been fetched. Descend past a rung on exactly two grounds, each recorded: the probe showed it does not carry the claim, or the escalation ladder below failed on it — which makes it an enumerated Gap, not a silent descent. **"No deeper artifact exists" is an absence claim like any other** — unprobed, it is the assumption that produces the shallow walk this ladder exists to prevent, and it lets a landing page pass itself off as the top. Discovering a deeper rung and sourcing from a shallower one anyway is the same failure with a receipt attached. The ladder applies to every publisher's own artifacts — a vendor's, an OSS maintainer's, a standards body's.

1. The deepest technical artifact the vendor ships for that claim class — for a model / benchmark / eval claim, the **system or model card**, often a PDF; for a library-behavior claim, the source itself (per "Source code as spec"). Carries methodology, conditions, and per-run numbers. Many claim classes have no such artifact — then rung 2 is the top
2. Platform / API reference — normative behavior, parameters, limits
3. Product docs — feature-level description
4. Changelog / release notes — what changed, when
5. Announcement / news post — the **headline** number only
6. Third-party

**An announcement is the shallowest rung that still carries the claim.** It states the headline figure; the specific run, its conditions, and its methodology live at rung 1. Checking an announcement, an intro page, and a couple of searches — then reporting the figure as unsourced — is a ladder that was never walked.

**Authoritative is not a waiver for corroboration.** Even the canonical doc still needs ≥2 independent corroborators and a freshness check — first-party docs routinely lag major releases. When the topic post-dates a major version, cross-check the canonical doc against the upstream changelog/release and treat any lag as a conflict to resolve.

**Escalate on block, never downgrade.** A direct-fetch 403/429 means wrong fetcher, not vanished source. Escalation order: (1) a headless-browser URL reader if connected; (2) a managed scraping tool if available; (3) a synthesis tool forced to the blocked domain (domain-filter option). Only after those fail, fall back to secondary sources — and document the gap.

**A size failure is the same trigger.** Rung-1 artifacts can be large — a model card or spec PDF, but equally a long HTML specification, an API reference, or a source file — and an in-context fetcher may reject one with a content-length error (shape: `maxContentLength size of <N> exceeded`) or — the silent variant — truncate it: Claude Code's WebFetch documents truncating large pages to a fixed character limit, and names `curl` via Bash as the unprocessed-page path ([tools-reference](https://code.claude.com/docs/en/tools-reference#webfetch-tool-behavior), fetched 2026-07-24). Escalate by moving the fetch out of context, in three steps.

1. **Download** to the session's scratch dir with any available downloader, failing loudly on an HTTP error instead of saving the error body as the document:

   ```bash
   dir=$(mktemp -d "<scratch>/fetch-XXXXXX")
   url='<url>'
   curl -fsSL -D "$dir/headers" -o "$dir/<claim-slug>-<url-digest>" "$url"
   ```

   Four properties of that recipe are load-bearing, and each one is a failure someone has already shipped.

   **The URL is DATA, never command source — single-quote it.** `$(…)` and backticks are legal characters in a URL path, and inside *double* quotes the shell expands both before `curl` ever runs, so pasting a discovered link into a double-quoted string executes whatever a hostile page put in it. Single quotes suppress every expansion, which also covers the `&` that would otherwise be a control operator truncating the URL and running the remainder. Single quoting cannot carry a literal `'`, so percent-encode that one character as `%27` before the URL goes in the string. Never interpolate the raw link into the `curl` line itself.

   **Download extensionless; settle the type afterwards.** Naming the file by type up front is circular — the path has to exist before `curl` runs, but the type is only known from the response that same command produces, and `-D` writes headers, it cannot retroactively rename an already-chosen output path. Guessing `.pdf` mislabels an HTML spec or a source file and sends step 3 down the wrong branch; re-fetching to learn the type costs a second full transfer of a large or single-use signed download. So the artifact lands with no extension, `-D "$dir/headers"` captures the response headers from the one transfer, and step 2 branches on what the completed download actually is. Nothing needs renaming.

   **Uniqueness rides the DIRECTORY, not the filename.** Phases launch queries in parallel against a shared filesystem, so a fixed `doc` name lets one worker overwrite another's artifact mid-validation and cite the wrong document; a claim slug alone collides the moment one claim is chased across two URLs; and the full claim-plus-URL stem still collides when two parallel queries chase the same claim to the same URL. A per-invocation `mktemp -d` closes all three at once. It has to be the directory because BSD `mktemp(1)` replaces only *trailing* `X`s ("The template may be any file name with some number of `Xs` appended to it … The trailing `Xs` are replaced", <https://man.freebsd.org/cgi/man.cgi?query=mktemp&sektion=1>, fetched 2026-07-25) — a `…-XXXXXX.<ext>` template is an invalid-template error on macOS, and under `&&` chaining `curl` never runs, so a directly downloadable artifact gets escalated or filed as a Gap on the strength of a shell error. The stem survives on the filename for diagnosis only: it is what tells a later reader which claim and which URL a scratch directory holds.

   **`--fail` (`-f`) is not optional.** Without it a 4xx/5xx body lands as a "downloaded" file that then fails extraction and reads as an unreadable primary.

   Carry that exact allocated path through steps 2 and 3.
2. **Confirm the file IS the artifact before parsing it** — `--fail` cannot catch a protected endpoint that answers 200 with a login, consent, or bot-challenge page. **The recorded `Content-Type` is corroborating evidence, never the confirmation itself, and its absence is never a rejection.** It cannot confirm, because a login wall, a consent interstitial, a bot challenge, and the spec you wanted are all `text/html` — accepting the type as confirmation is exactly how a challenge page gets grepped as a reached source and yields a false absence. It equally cannot *refuse*: servers routinely ship a valid PDF or source archive as `application/octet-stream` or with no useful type at all, and treating that as a failed confirmation throws away a complete local download and sends the run back through fallbacks that will fail on the same large file — reporting as unreachable an artifact already sitting on disk. **A strong signature or artifact-specific marker confirms on its own**, whatever the server said the type was. Confirm against markers specific to the artifact — for a binary type its magic bytes (a PDF starts `%PDF-`); for a text-shaped one, content the real document must carry and a challenge page cannot: its expected title or top-level headings, the section the claim is being chased into. Then reject the challenge shapes affirmatively — a `<form>` asking for credentials, a consent banner, a CAPTCHA or bot-check body, a payload a small fraction of the artifact's plausible size. A mismatch, or a confirmation you cannot make, is a BLOCK, not a size failure: route it back through the escalation order above — all of it, in order — and do NOT count this recipe as having run.
3. **Extract, confirm the text is searchable, then cite** — branch on the type step 2 confirmed. An HTML, plain-text, or source artifact is **already searchable on disk**: grep it directly, and strip tags only if the markup drowns the match. Treating one as an unreadable binary is how a run reports "unreachable" about a complete document it already has. A binary artifact needs text out with whatever the machine has (for a PDF, probe for a local extractor such as `pdftotext`; else a PDF library in an available interpreter; else a connected parse/scrape tool that extracts server-side). An extractor exits 0 on a scanned or image-only PDF and returns nothing: **empty or garbled output is a FAILED extraction, not an empty document.** Check the text is usable before searching it — a plausible length for the artifact's size, expected headings present. If it is not, try another extractor, then OCR, then the escalation order above; grepping unusable text manufactures a false "not found" about a source nobody read. Only then grep and cite the section the claim lands in.

**"Unreachable" is reserved for exhaustion, and there are two ways to exhaust.** Extraction that failed after the escalation rungs also failed is one. Acquisition that failed through every rung is the other: a source that answers the direct fetch and every escalation fallback with a login, challenge, or block never yields an artifact to confirm, and once that full walk is recorded it is unreachable too — which is what lets criterion 9 descend past a genuinely protected rung and the Gap row name it. An unconfirmed download ALONE proves neither: it says nothing about the source until the escalation order has actually been walked. And the opposite mistake costs just as much: an artifact that WAS confirmed, extracted into usable text, and searched is a REACHED source even when the claim is not in it. It belongs in the checked set of the enumeration, and the finding is *"not found in [that artifact]"* — never "unreachable", which would file a source you read as one you never opened.

**Negative claims need the primary fetched this turn, and ship their enumeration.** "X is undocumented / removed / unsupported" requires fetching the canonical doc this turn and confirming absence — absence in training data ≠ absence in current docs. Never publish "unsourced" / "unsupported" / "not found" bare: publish the enumeration — *"not found in [the sources actually checked]; unchecked: [the sources not reached]"*. An absence claim is only as strong as the set it was checked against, and naming the unchecked set is what lets a reader close the gap in one step instead of a round trip.

## Machine-readable doc-index discovery

When the topic centers on a specific library / framework / site, probe for a published index BEFORE crawling by hand. **Probe-if-present**: absence is normal; fall through to the next. Each is a `{base}`-relative path on the canonical home.

| Probe | Path | Nature | Use for |
|---|---|---|---|
| `llms.txt` | `/llms.txt` (or `/.well-known/llms.txt`) | **Curated** markdown index — maintainer hand-pick, deliberately partial | Fast orientation + page prioritization; NOT completeness |
| `llms-full.txt` | `/llms-full.txt` | Full doc content inlined | One fetch for a deep read of the whole curated set |
| `sitemap.xml` | `/sitemap.xml` | **Exhaustive** — every URL (50k URL / 50 MB cap per file) | Completeness — enumerate ALL pages |
| `sitemap_index.xml` | root | Index of child sitemaps when the site exceeds the cap | Large sites — follow the index to each child |
| `robots.txt` `Sitemap:` directive | `/robots.txt` | Names the sitemap location when non-default | Locating a non-default sitemap |
| `.md` page variant | append `.md` to a page URL | **Platform-specific** — native on some doc platforms; absent elsewhere | Markdown of one page without an HTML parse — PROBE first |
| In-repo docs tree | `gh api repos/<owner>/<repo>/contents/docs` or `git ls-tree` | Tier-0 enumeration when docs live in a Git repo | Doc source is a repo, not a site |
| Changelog feed | RSS/Atom, or `CHANGELOG.md` / releases | Release/change stream | Feeds the Recency gate above |

**Curated ≠ exhaustive — the completeness trap.** `llms.txt` is the maintainer's hand-pick; using it alone for "go through every page" silently drops whatever was omitted. For full coverage, **sitemap enumerates, llms.txt prioritizes**.

## Source-quality red flags

Down-rank or refuse to cite:

- Domain names that aggregate / repackage other content (sites that summarize without primary research)
- "Top 10 best X" listicles with no author named
- Articles where every claim links to other listicles (no terminal primary source)
- Vendor-comparison pages on a vendor's own marketing site (marketing copy, not technical doc)
- "AI-generated content" markers / disclaimers — treat as Tier 3 unless verified against Tier 0/1

Prefer: the vendor's own `/docs` subdomain, GitHub source code, RFCs, language specs, vendor changelogs, recognized author personal blogs with author name + bio.

## Graceful degradation (missing tools)

If a required tool category is unavailable this session (no synthesis MCP server, no web access), don't lower the bar — substitute and document:

- Lost synthesis tool → substitute WebSearch + WebFetch + `gh api` for equivalent coverage
- Lost web access → flag the topic as `verification: incomplete — offline session`; do not edit code based on Tier 3 recall
- Document the gap in RESEARCH.md's `Gaps` section: which tool was unavailable, what alternative was used, residual risk

## Confidence calibration

The evidence-table `Confidence` column must be set per claim:

- **HIGH** — 3+ independent Tier 0/1 sources agree; recency gate passed; falsification query failed to find counter-evidence
- **MEDIUM** — 3+ sources agree but mix of Tier 0/1 + Tier 2; OR 2 Tier 0/1 + open falsification gap; OR primary source > 30d old without changelog cross-check
- **LOW** — fewer than 3 sources; OR sources conflict; OR Tier 2-only consensus; OR primary source > 90d old

Only HIGH-confidence claims are accepted (the outcome gate enforces this). A MEDIUM or LOW claim is a **Gap** — return to Phase 4 follow-up and iterate until HIGH, or report it as a gap; never a basis for code edits.

## Observed failure patterns

- **Synthesis tools give wrong versions.** AI-synthesis tools routinely assert wrong version numbers and hallucinate canonical conventions (a config path that "is canonical" but isn't). Always verify version-specific features empirically (`gh api repos/<owner>/<repo>/releases/latest`, an actual import/call test) — never trust secondary sources for version claims. A single direct fetch of the canonical doc falsifies this class.
- **Agent consensus can be unanimously wrong.** Multiple subagents agreeing is one source, not N — they share training priors. Verify claims empirically before shipping, especially env-var / tool-behavior claims.
- **Two sources can both be wrong.** Two sources parroting the same incorrect information is common. Count INDEPENDENT primary sources, not citation count.
- **Phases must be sequential.** Phase 2 MUST analyze Phase 1 results before launching. Running all phases in parallel produces redundant queries that miss the gaps Phase 1 would have revealed.
- **No parallel MCP calls to the same stdio server.** stdio transport serializes. Run queries sequentially within a server; parallelize across different servers/tools.
- **Subagent return = Tier 3 by default.** Even when a subagent's prompt mandates citation, the return is synthesis. Cited primary sources inside the return promote to Tier 1 once fetched/confirmed; bare claims stay Tier 3.
- **Cached doc URLs from prior turns are Tier 3, not Tier 1.** A fetch result from months ago that's now in the model's assumption set has aged out. Re-fetch on every research pass for the topic.
- **Convention / naming decisions need primary sources read directly** — synthesis summaries are insufficient when deciding on folder names, config patterns, or naming conventions; read 3+ primary sources.
