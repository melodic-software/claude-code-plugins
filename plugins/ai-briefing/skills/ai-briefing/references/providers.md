# Provider Registry & Query Templates

This file maps each provider category to its Twitter/X handles, query templates, and changelog URLs — the collection-wave scaffolding. The authoritative handle registry for a run is the active profile's `following-list.json`; this file organizes the per-bucket query/changelog templates around it.

## Coverage rule — web-research depth = Twitter depth (all 13 buckets)

Every bucket below gets at minimum **1 Perplexity query + 1 WebSearch per run**, regardless of whether handles are listed. Twitter alone misses court news (Legal), chip launches and procurement deals (Compute), regulator filings, datacenter announcements, and city-expansion news (Real-world AI). Web-research-FIRST buckets:

- **Legal & regulatory** — court filings, opinions, AG actions
- **Compute & Infrastructure** — chip launches, hyperscaler deals, datacenter capacity
- **Real-world AI** — robotaxi/AV expansion, humanoid production cadence
- **Microsoft** — M365 release notes, learn.microsoft.com changelogs (handles are corp-only, low signal)

Twitter-FIRST buckets (handle-rich): Anthropic, OpenAI, Google, Cursor, xAI, Meta, DeepSeek, Other — but still web-research-mandatory each run.

## 13-bucket canonical order

1. Anthropic
2. OpenAI
3. Google
4. Cursor
5. xAI / Grok
6. Meta / Llama
7. DeepSeek
8. Microsoft
9. Compute & Infrastructure
10. Real-world AI
11. Legal & regulatory
12. Other
13. EXTRAS (Robotics + Flair)

## Anthropic

**Twitter/X handles** (refreshed 2026-05-05 from live following list):

@bcherny, `@_catwu`, @trq212, @noahzweben, @katelyn_lesse, @felixrieseberg, @lydiahallie, @sidbid, @dmwlff, @gabemulley, @adocomplete, @dickson_tsai, @amorriscode, @The_Whole_Daisy, @jarredsumner, @swac, @martinamps, @AnthropicAI, @claudeai, @ClaudeCodeLog, @AmandaAskell, @DarioAmodei, @DanielaAmodei, @alexalbert__, @jackclarkSF, @nottombrown, @ch402, @mikeyk, @janleike, @EvanHub, @EthanJPerez, @TrentonBricken, @esindurmusnlp, @saffronhuang, @AlexTamkin, @katchu11, @RobertJBye, @angjiang, @TheAmolAvasare, @TheRohanVarma, @indexingai, @AISecurityInst, @Linatawfik9

**Web-research-only watchlist** (no active Twitter — query by name in Perplexity/WebSearch each run):

- **Ami Vora** — CPO, Anthropic. Handle `@asvora` exists but dormant for Anthropic posts; rely on web-research instead. Watch for product-strategy announcements, exec interviews, Labs reorg news.
- **Dianne Na Penn** — Product Lead, Research at Anthropic (no Twitter found). Watch for research-product announcements, model launch posts, Anthropic blog co-author bylines.

**Topics:** Claude, Claude Code, Claude Cowork, Claude Desktop, model releases, API changes, safety research, interpretability, alignment, societal impacts, computer use, agent skills, MCP, hooks, scheduled tasks

**Perplexity query template:**

```
What have Anthropic and the Claude Code team (@bcherny, @trq212, `@_catwu`, @noahzweben, @felixrieseberg, @katelyn_lesse) announced or posted about Claude, Claude Code, or Anthropic products in the last {timeframe}? Also surface any statements, interviews, or product announcements from Anthropic exec/product leadership: Ami Vora (CPO), Dianne Na Penn (Product Lead, Research), Mike Krieger (Labs). Include model releases, feature launches, API/Platform changes, developer tools updates. Include tweet/post URLs where possible.
```

**WebSearch query templates** (run BOTH each run):

```
Anthropic Claude Code announcements {timeframe} site:x.com OR site:anthropic.com OR site:code.claude.com
```

```
"Ami Vora" OR "Dianne Penn" OR "Katelyn Lesse" Anthropic {timeframe}
```

**Changelog URLs:**

- https://code.claude.com/docs/en/changelog
- https://docs.anthropic.com/en/docs/about-claude/models
- https://platform.claude.com/docs/en/release-notes/overview

**RSS / blog feeds (preferred over WebFetch — deterministic, dated):**

<!-- RSS coverage may shrink as providers stop publishing feeds — verify with `curl -sI` before re-introducing dead-flagged endpoints. Removed 2026-05-13 audit: anthropic.com/news/rss.xml + anthropic.com/research/rss.xml (both 404). HTML fallback per SKILL.md line 618 covers the gap; collection waves still surface Anthropic content via WebFetch on https://www.anthropic.com/news. -->

- https://red.anthropic.com/feed.xml — Anthropic Red (cybersecurity research)

**GitHub repos to check:**

- `anthropics/claude-code` — Claude Code CLI releases
- `anthropics/anthropic-sdk-python` — Python SDK releases
- `anthropics/anthropic-sdk-typescript` — TypeScript SDK releases
- `anthropics/claude-agent-sdk-python` — Agent SDK Python
- `anthropics/claude-agent-sdk-typescript` — Agent SDK TypeScript

## OpenAI

**Twitter/X handles** (refreshed 2026-05-05):

@sama, @gdb, @thsottiaux, @romainhuet, @dkundel, @OpenAI, @OpenAIDevs, @simpsoka, @steipete, @aidotengineer, @embirico

**Topics:** GPT models, Codex, ChatGPT features, API changes, Sora, safety, developer tools, o-series reasoning models

**Perplexity query template:**

```
What has OpenAI announced in the last {timeframe}? Include GPT model releases, Codex updates, ChatGPT features, API changes, developer tools. Include Sam Altman (@sama), Thibault Sottiaux (@thsottiaux) posts. Include tweet/post URLs.
```

**WebSearch query template:**

```
OpenAI GPT Codex ChatGPT announcements {timeframe} site:x.com OR site:openai.com
```

**Changelog URLs:**

- https://openai.com/blog
- https://platform.openai.com/docs/changelog
- https://help.openai.com/en/articles/6825453-chatgpt-release-notes
- https://developers.openai.com/codex/changelog
- https://alignment.openai.com/

**RSS / blog feeds:**

- https://openai.com/blog/rss.xml — OpenAI news + product launches
<!-- openai.com/research/rss.xml removed 2026-05-13 audit (404); HTML fallback on https://openai.com/research covers the gap. -->

**GitHub repos to check:**

- `openai/openai-agents-js` — Agents SDK TypeScript (Sandbox Agents, etc.)
- `openai/openai-agents-python` — Agents SDK Python
- `openai/codex` — Codex CLI
- `openai/openai-python` — Python SDK
- `openai/openai-node` — Node SDK

## Google

**Twitter/X handles** (refreshed 2026-05-05):

@JeffDean, @OfficialLoganK, @Google, @GoogleAIStudio, @GoogleDeepMind, @Engineering

**Topics:** Gemini models, AI Studio, DeepMind research, Search AI, Google Cloud AI, Vertex AI

**Perplexity query template:**

```
What has Google announced about Gemini, AI Studio, Google AI, and DeepMind in the last {timeframe}? Include model releases, developer tools, API changes. Include Jeff Dean (@JeffDean), Logan Kilpatrick (@OfficialLoganK) posts. Include URLs.
```

**WebSearch query template:**

```
Google Gemini AI DeepMind announcements {timeframe} site:x.com OR site:blog.google OR site:developers.googleblog.com
```

**Changelog URLs:**

- https://blog.google/technology/ai/
- https://developers.googleblog.com/
- https://ai.google.dev/gemini-api/docs/changelog
- https://deepmind.google/discover/blog/

**RSS / blog feeds:**

- https://blog.google/technology/ai/rss/ — Google AI blog
- https://blog.google/technology/developers/rss/ — Developer blog
- https://blog.google/products/google-cloud/rss/ — Google Cloud (TPU, Vertex)
<!-- deepmind.google/discover/blog/rss.xml removed 2026-05-13 audit (404); HTML fallback on https://deepmind.google/research/publications/ covers the gap. -->

**GitHub repos to check:**

- `google/generative-ai-js` — Generative AI JS SDK
- `google/generative-ai-python` — Generative AI Python SDK
- `google-deepmind/gemma` — Open Gemma releases
- `google-gemini/cookbook` — Gemini cookbook updates

## Cursor

**Twitter/X handles** (refreshed 2026-05-05):

@leerob, @cursor_ai

**Topics added 2026-05-05:** Cursor Security Review (always-on per-PR + scheduled scanner — competing with Claude Security beta), Cursor SDK + Composer 2 token-priced, Cloud Agents API v1.

**Topics:** Cursor IDE, Composer, agent development, plugins, JetBrains integration, model support, automations

**Perplexity query template:**

```
What has Cursor (Anysphere) announced in the last {timeframe}? Include Cursor IDE updates, Composer changes, new features, plugins, model support. Include Lee Robinson (@leerob) posts. Include URLs.
```

**WebSearch query template:**

```
Cursor IDE announcements {timeframe} site:x.com OR site:cursor.com
```

**Changelog URLs:**

- https://cursor.com/blog
- https://cursor.com/changelog

**RSS / blog feeds:**

- https://cursor.com/changelog/rss.xml — Cursor changelog (fallback to HTML if 404)
<!-- cursor.com/blog/rss.xml removed 2026-05-13 audit (404); changelog feed above covers product news; HTML fallback on https://cursor.com/blog covers editorial. -->

**GitHub repos to check:**

- `cursor/cursor` — Cursor IDE releases (private — public mirror via blog)
- `getcursor/cursor` — community mirror

## Microsoft

**Twitter/X handles** (added 2026-05-05; @mariorod1 added 2026-05-06):

@Microsoft, @MSFTCopilot, @MicrosoftAI, @satyanadella, @MSFT365, @MicrosoftLearn, @mariorod1 (GitHub CPO), @code (cross-listed under Other for VS Code)

**Topics:** Microsoft 365 Copilot (Word/Excel/PowerPoint/Outlook/Teams), Copilot Studio (multi-agent orchestration), Agent 365, M365 E7 Frontier Suite, GitHub Copilot (CLI, agents, metered AI billing — Mario Rodriguez voice), Azure AI / Azure OpenAI, Bing Chat, Power Platform AI, Phi models, Microsoft Build conference

**Perplexity query template:**

```
What has Microsoft announced about Copilot, Microsoft 365 Copilot, Copilot Studio, Agent 365, Azure AI, GitHub Copilot, or Microsoft AI in the last {timeframe}? Include feature releases, model updates (GPT-5.x in M365), enterprise SKU changes, multi-agent capabilities, GitHub Copilot CLI/agents updates and Mario Rodriguez (@mariorod1) posts on GitHub product direction. Include URLs.
```

**WebSearch query template:**

```
Microsoft Copilot 365 Azure AI announcements {timeframe} site:microsoft.com OR site:techcommunity.microsoft.com OR site:learn.microsoft.com
```

**Changelog URLs:**

- https://learn.microsoft.com/en-us/microsoft-365/copilot/release-notes — M365 Copilot release notes
- https://devblogs.microsoft.com/microsoft365dev/ — M365 Copilot dev blog (replaces techcommunity.microsoft.com/category/microsoft365copilotblog — restructured 2026)
- https://www.microsoft.com/en-us/microsoft-copilot/blog — Copilot blog
- https://www.microsoft.com/en-us/microsoft-365/roadmap — M365 roadmap
- https://learn.microsoft.com/en-us/power-platform/release-plan/ — Power Platform / Copilot Studio release plan
- https://github.blog/changelog/ — GitHub Copilot changelog

**RSS / blog feeds:**

<!-- techcommunity.microsoft.com/category/microsoft365copilotblog/feed removed 2026-05-13 audit (HTTP 400 — no working feed at that path after 2026 restructure); devblogs.microsoft.com/feed/ covers the gap. -->
- https://www.microsoft.com/en-us/microsoft-copilot/blog/rss/ — Copilot blog feed (verify; 403 anti-bot — lychee `--accept` covers)
- https://devblogs.microsoft.com/feed/ — DevBlogs (Azure SDK, etc.)
- https://github.blog/changelog/feed/ — GitHub blog/changelog

**GitHub repos to check:**

- `microsoft/vscode` — VS Code (Copilot updates) — also tracked under Other
- `microsoft/semantic-kernel` — Semantic Kernel SDK
- `microsoft/autogen` — AutoGen multi-agent framework
- `microsoft/ai-agents-for-beginners` — official agents tutorials

**Visual Studio (full IDE — distinct from VS Code):**

VS 2026 ships Copilot agent surfaces that lag VS Code by ~1 release. Track separately:

- https://learn.microsoft.com/en-us/visualstudio/releases/2026/release-notes — VS 2026 release notes (Copilot Chat / Agent Mode / IntelliCode AI)
- https://devblogs.microsoft.com/visualstudio/feed/ — VS DevBlog feed
- @VisualStudio (X handle) — VS team announcements

**Augment Code GitHub repo to check:**

- `augmentcode/auggie` (CLI) — verify before scan
- VS Code Marketplace `augment.vscode-augment` — pull manifest version diff

## Compute & Infrastructure

**Twitter/X handles:**

@nvidia, @nvidiaaiDev, @AMD, @intel, @Microsoft (Azure compute), @awscloud, @googlecloud (TPU)

**Topics:** GPU/TPU/NPU chip launches, hyperscaler GPU procurement, datacenter / power capacity, RAM/HBM supply, model-training cost trends, inference cost reductions, chip-export policy, energy costs of AI

**Why we track this:** compute is the binding constraint on AI scale (Stargate, Anthropic-Google $40B). Chip and power-cost shifts directly change "pragmatic use of AI" economics for our workflows.

**Perplexity query template:**

```
What major AI chip, GPU, datacenter, or compute infrastructure announcements happened in the last {timeframe}? Include NVIDIA (Vera Rubin, Blackwell, GTC), AMD (Instinct MI series, Helios), Intel, hyperscaler GPU procurement deals, datacenter power capacity, training/inference cost changes. Include URLs.
```

**WebSearch query template:**

```
NVIDIA AMD Intel AI chip GPU datacenter compute announcement {timeframe}
```

**Changelog URLs:**

- https://blogs.nvidia.com/ — NVIDIA blog (GTC, product launches)
- https://ir.amd.com/news-releases — AMD press (newsroom URL retired 2026; investor-relations feed is canonical)
- https://newsroom.intel.com/ — Intel newsroom

**Signal level:** generally **medium** unless a launch redefines cost/$ frontier (e.g. Vera Rubin's 10× inference token cost reduction = HIGH).

## Real-world AI

**Twitter/X handles:**

@Tesla, @elonmusk (xAI separately), @Waymo, @cruise, @bostondynamics, @1x_tech, @figure_robot, @nuro, @aurora_inno

**Topics:** autonomous vehicles (robotaxi launches, fleet sizes, expansion cities), humanoid robotics shipping cadence, AI in cars / phones / homes / wearables, drone/delivery autonomy, real-world AI deployments at scale

**Why we track this:** "AI in everyday life" — the user-facing edge of AI deployment. Robotaxis, autonomous trucking, AI-in-phones, smart-home agents reveal what's leaving research and entering everyday life.

**Perplexity query template:**

```
What major real-world AI deployments happened in the last {timeframe}? Focus on autonomous vehicles (Tesla Robotaxi, Waymo, Cruise expansion + city launches), humanoid robotics production scaling (Figure, Atlas, Neo), AI in consumer hardware (phones, cars, smart home). Include URLs.
```

**WebSearch query template:**

```
robotaxi autonomous vehicle Tesla Waymo humanoid robot launch {timeframe}
```

**Signal level:** **high** for production launches and city expansions; **medium** for prototypes/demos.

## Legal & regulatory

**Why we track:** lawsuits and regulatory actions move the AI cost/access frontier. Musk v. Altman, copyright suits against Meta/OpenAI, state-level Character.AI suits all reshape what's permissible. ALWAYS web-search this — Twitter alone misses court filings and judicial opinions.

**Web research is mandatory** — news sites cover legal developments better than Twitter. Use parallel WebSearch + Perplexity per topic.

**Perplexity query template:**

```
What major AI-industry legal, regulatory, or lawsuit developments happened in the last {timeframe}? Include Musk v. Altman / OpenAI trial, copyright suits (Meta-Llama, OpenAI-publishers, Character.AI), state attorneys general actions, FTC/DOJ investigations, antitrust, EU AI Act enforcement, training-data IP rulings. Include URLs to primary news coverage.
```

**WebSearch query template:**

```
"AI lawsuit" OR "AI ruling" OR "AI antitrust" OR "OpenAI court" OR "Meta AI lawsuit" {timeframe}
```

**Sources to prioritize:** TechCrunch, CNBC, CNN Business, MIT Technology Review, Washington Post Tech, The Verge, Ars Technica, Reuters, Bloomberg.

## Other

**Twitter/X handles** (refreshed 2026-05-05):

@karpathy, @swyx, @simonw, @Vtrivedy10, @latentspacepod, @enesakar, @nikitabier, @petergyang, @minchoi, @natbat, @beepytown, @firecrawl, @vercel, @bunjavascript, @LangChain, @LangChain_JS, @LangChain_OSS, @code, @TechCrunch, @GithubProjects, @cognition, @scale_ai, @datasetteproj, @dagster, @temporalio, @upstash, @context7ai, @augmentcode, @poolsidehq, @replit, @lovable_dev, @v0, @windsurf_ai, @*samirism, @huntlovell, @marc_krenn, @supertommy, @ColtonOrtolf, @TheCodeMan*_, @Dave_DotNet, @nickchapsas, @mjovanovictech, @gsferreira, @martinfowler, @amantinband, @dxtipshq, @dracan, @CHBernasconiC, @usebrilliant, @henrythe9ths

**Coding-agent vendors to track per audit 2026-05-06** (added high_signal_required candidates): @augmentcode (Auggie CLI + Remote Agent + Augment Agent — large-codebase coding agent), @cognition (Devin Terminal/Shell/Security), @poolsidehq (Laguna open-weight models), @replit (Agent + cloud), @lovable_dev (full-stack vibe code), @v0 (Vercel), @windsurf_ai (Codeium IDE).

**Removed (unfollowed since last refresh):** @rohanvarma → @TheRohanVarma (handle change), @jmtrivedi, @mavi888uy (low AI signal), @nikolasklein, @XEng (account renamed to @Engineering)

**Topics:** AI developer tools, coding agents, AI startups, infrastructure, competitive landscape, Replit, Perplexity, Cloudflare, Vercel AI, n8n, X/Twitter engineering, VS Code, GitHub

**Perplexity query template:**

```
What are the most significant AI developer tool announcements in the last {timeframe}? Include Replit, Perplexity, Cloudflare AI, Vercel, and other AI companies — NOT Anthropic, OpenAI, Google, or Cursor (covered separately). Include URLs.
```

**WebSearch query template:**

```
AI developer tools announcements {timeframe} -anthropic -openai -google -cursor
```

**RSS / blog feeds:**

<!-- bun.sh/blog/rss.xml + vercel.com/blog/feed.xml removed 2026-05-13 audit (both 404); HTML fallbacks on https://bun.com/blog and https://vercel.com/blog cover the gap. -->
- https://blog.langchain.dev/rss/ — LangChain blog
- https://code.visualstudio.com/feed.xml — VS Code blog (Copilot/MCP)
- https://blog.cloudflare.com/rss/ — Cloudflare AI / Workers AI
- https://www.firecrawl.dev/blog/rss.xml — Firecrawl blog
<!-- blog.cognition.ai/rss.xml removed 2026-05-13 audit (DNS/cert failure, no feed published); HTML fallback on https://cognition.ai/blog covers the gap. -->
- https://huggingface.co/blog/feed.xml — HuggingFace blog

**GitHub repos to check:**

- `oven-sh/bun` — Bun runtime releases
- `langchain-ai/langgraph` — LangGraph releases
- `langchain-ai/langchain` — LangChain core
- `microsoft/vscode` — VS Code releases (Copilot updates)
- `vercel/ai` — Vercel AI SDK
- `firecrawl/firecrawl` — Firecrawl releases
- `cognition-ai/devin` — Devin (if public)
- `mendableai/firecrawl` — alt firecrawl repo

## EXTRAS

No specific account handles — broad discovery queries for fun/novel AI items.

**Perplexity query template:**

```
What are the most interesting and unusual AI developments in the last {timeframe} that aren't product announcements? Include robotics, brain emulation, games using AI, science breakthroughs enabled by AI, novel applications. Fun and surprising items preferred. Include URLs.
```

**WebSearch query template:**

```
AI robotics science games novel applications breakthroughs {timeframe}
```

### EXTRAS — Flair (fun videos, holiday-themed, meme content)

The user runs an internal AI meeting and wants the deck to break up dense content with one short "flair" slide of fun AI items — viral AI-generated videos, science breakthroughs (e.g. fly-brain emulation), surprising real-world AI moments. Holiday tie-ins are great (May 4 = Star Wars).

**Always include a Flair slide** when generating slides. Even a placeholder with a curate-your-own slot is better than skipping — the user often curates their own at meeting time.

**Holiday tie-in calendar (auto-detect by date proximity):**

| Date | Theme | Search hooks |
|---|---|---|
| Jan 1 | New Year | "AI year-in-review", "AI predictions {year}" |
| Feb 14 | Valentine's | "AI chatbot girlfriend", "AI dating apps" |
| Mar 14 | Pi Day | "AI math", "Pi calculation AI" |
| Mar 17 | St Patrick's | "AI Irish", "Guinness AI ad" |
| Apr 1 | April Fools | "AI April Fools prank" |
| May 4 | Star Wars Day | "AI Star Wars", "AI Mandalorian", "AI lightsaber" |
| Jun 14 | Flag Day | (skip unless something genuinely AI) |
| Jul 4 | July 4 | "AI fireworks", "AI patriotic" |
| Oct 31 | Halloween | "AI horror", "AI costume", "AI haunted house" |
| Nov 28 | Thanksgiving | "AI Thanksgiving", "AI turkey" |
| Dec 25 | Christmas | "AI Christmas", "AI Santa", "AI carol" |

When run-window crosses a holiday, prioritize themed flair items.

**Discovery queries:**

```
Perplexity: What viral or funny AI-generated videos, memes, or pop-culture AI moments happened around {timeframe}? Especially {holiday-near-date} themed (e.g. Star Wars on May 4, Halloween on Oct 31, Pi Day on Mar 14). Include creator/source URLs.

WebSearch: viral AI generated video {timeframe} {holiday-name}
```

**Apolitical-flair gate:** drop politician deepfakes, partisan campaign AI memes, partisan policy threads. KEEP brand parodies (PETA-style), fan-art trailers (Wes Anderson Star Wars), science weirdness (fly-brain emulation), real-world AI moments. Heuristic per SKILL.md "Apolitical filter".

**Signal:** **low** — purely for delivery flair. Don't fact-check exhaustively; focus on shareable URLs and 1-line summaries.

## Dev-tools priority list

Engineering audience cares about "what is new in MY TOOL?" — not "what is new from this VENDOR?" When emitting the **Dev Tools — Release Walk** section, walk per-tool in this priority order. Each tool gets its own subsection with chronological version-by-version breakdown.

```
dev_tools_priority = [
  "claude-code",     // heavy use — every version + rate-limit changes
  "cursor",          // heavy use — every IDE release + cloud agents
  "codex",           // heavy use — CLI stable + alpha cadence
  "github-copilot",  // some use — M365 wave + Visual Studio integration
  "augment-code",    // some use — Auggie CLI + Remote Agent + Augment Agent
]
```

**Per-tool vendor coverage minimum** (every meeting must surface at least one item or "no notable items this window"):

| Tool | Surfaces to check |
|---|---|
| **claude-code** | `code.claude.com/docs/en/changelog`, GH `anthropics/claude-code` releases, @ClaudeCodeLog tweets, rate-limit updates, security advisories |
| **cursor** | `cursor.com/changelog`, @cursor_ai tweets, IDE x.y release notes, Cloud Agents API + SDK changes |
| **codex** | `developers.openai.com/codex/changelog`, GH `openai/codex` releases, @OpenAIDevs Codex-CLI tweets, alpha cadence |
| **github-copilot** | `github.blog/changelog/`, M365 monthly wave, VS 2026 release notes, Mario Rodriguez (@mariorod1) posts |
| **augment-code** | GH `augmentcode/auggie` releases, VS Code marketplace `augment.vscode-augment` manifest, @augmentcode tweets |

**Rule of thumb:** if a dev-tool ships >1 release in the window, surface BY VERSION (chronological) not lumped. The audience question is "what shipped Tuesday?" — not "what did Anthropic do this month?".

## Breaking & Deprecated keywords

Items mentioning any of these keywords get pulled into the `## Breaking & Deprecated` section parallel to `## Patterns`. Surfaces engineering-team risks: known breakages, EOL announcements, security CVEs.

```
breaking_keywords = [
  "deprecated",
  "deprecation",
  "EOL",
  "end of life",
  "end-of-life",
  "breaking change",
  "breaking changes",
  "security advisory",
  "CVE-",
  "removed",
  "no longer supported",
  "sunsetting",
  "discontinued",
  "migration required",
]
```

**Categorization at S4 step:** when an item's body or title contains any keyword (case-insensitive), tag with `category: "breaking-deprecated"` in addition to its provider category. emit-slides-data emits a dedicated `## Breaking & Deprecated` slide if ≥1 item is tagged.

**Apolitical filter still applies** — political-only deprecation (e.g., regulatory ban on a model in a region purely due to politics) follows the same heuristic.

## Beta → GA tracker

Track release-state transitions across meetings. Schema field `release_state` per item:

| State | Meaning |
|---|---|
| `research-preview` | Anthropic research preview, OpenAI research preview, etc. |
| `beta` | Closed/private beta, waitlist required |
| `public-beta` | Open access, marked beta in product |
| `GA` | General availability, no beta marker |
| `deprecated` | Announced for removal, EOL date set |

When a tracked item's `release_state` changes meeting-over-meeting (e.g., `beta → GA`), surface as a one-line `[STATE: beta → GA]` prefix on the headline. Adoption decisions key on this.

**Where it lives:** `seen-items.json` per-item field. Set at S4 categorize step from body-text scan + Wave 2 web-research enrichment.

## Cost impact summary

Per-item `cost_impact` field captures the engineering-team budget effect:

| Value | Use when |
|---|---|
| `+$N/seat/month` | Per-seat price increase (e.g., Cursor Pro $20/mo) |
| `-$N/seat/month` | Per-seat price decrease |
| `+$N/MTok input` | Token-pricing increase |
| `-$N/MTok output` | Token-pricing decrease |
| `rate_limit_doubled` | Limit-quota change without dollar swing |
| `unchanged` | No cost impact |
| `unknown` | Pricing not announced or paywalled |

**Aggregate at meeting end:** "Net cost impact this window: -$N/seat (mostly Claude Code rate-limit doubling)." Sum across positives and negatives, surface in EXTRAS or as last bullet of last news slide.

## Audience segments

For per-segment customization (per-team slide cuts at meeting end), tag items with `segment_tags`:

| Tag | Audience |
|---|---|
| `python` | Python team — langchain, vercel-ai-python, FastAPI, Django, Pyright |
| `dotnet` | .NET team — Aspire, Microsoft / VS / GitHub Copilot, Semantic Kernel, AutoGen |
| `frontend` | Frontend team — Vercel, v0, Brilliant, Figma, Lovable, Replit, Cursor |
| `cli` | CLI users — Claude Code, Codex CLI, Auggie, Aider |
| `all` | Everyone — model releases, Claude.ai web changes, regulatory |

Items can carry multiple tags. Per-segment slides at meeting end ("For Python team:", "For .NET team:") let segment leads skim only their slice.

## Recheck cadence

| Trigger | Action |
|---|---|
| New dev tool gets 3+ mentions in window | Promote to `dev_tools_priority` list above |
| Vendor stops shipping for 2 consecutive meetings | Demote from priority list, note in next meeting's "no notable items" line |
| Breaking-keyword false-positive rate >20% | Audit + refine keyword list |
| `release_state` field used <30% of items | Audit S4 enrichment step — Wave 2 web-research not extracting state |

---

## Per-provider HIGH/MED priority table

Used by S4 categorize + SKILL.md standing default #16 "Tooling-first surfacing". Audience is engineering team thinking about pragmatic AI-in-development; they care about features they can use next week, not alignment papers or geographic expansion.

| Provider | HIGH = lead with | MED = demote to |
|---|---|---|
| **Anthropic** | Claude Code releases (CLI + Desktop), Claude.ai web portal (Routines, Cowork, Dispatch, Skills, Charts/Diagrams), API+SDK changes, Managed Agents, ant CLI, Claude Design, Plugins/Connectors, Skills marketplace, Security beta, Financial Services agents | Mythos / MSM / Sandbagging / Sycophancy research, valuation rounds, JVs, geographic expansion (Sydney/NEC), Snap CEO quotes, alignment research |
| **OpenAI** | Codex CLI releases (stable + alpha cadence), Codex desktop super-app updates, Codex plugins (Build Web Apps, Figma, Codex-in-CC), Codex `/goal` `/auto-review` features, Agents SDK (TS+Python), GPT model releases, ChatGPT app launches (Etsy, Workspace Agents), Responses API features, Realtime API | Notion/Blueprint benchmarks, alignment retros, Stargate compute, DevDay contests, `codex for X` posts, Musk-Altman trial |
| **Cursor** | IDE x.y releases (Composer, Bugbot, Tiled Layout, Voice STT, Interactive Canvases, Multitask, Worktrees, Multi-root Workspaces), SDK + Cloud Agents API + cloud sandboxes, Security Review GA, Team Marketplace, Model controls + spend mgmt, CI auto-fix | Discount campaigns, conference booths |
| **Google** | Gemini API releases (Webhooks, File Search, Search Grounding), AI Studio Vibe Coding + edit modes, Gemini Enterprise Agent Platform, TPU launches, Workspace Agents (Chat/Docs/Sheets), Skills in Chrome | I/O countdown contests, Pomelli marketing tool, Google Finance moments |
| **xAI / Grok** | Grok model releases (4.x → 5), Grok Voice updates, Grok API pricing changes, CarPlay / mobile / xAI console, X ad platform AI integration | Musk roadmap promises, Colossus 2 capex |
| **Meta / Llama** | Llama model releases (5.x), Meta AI app updates, AI Studio for WhatsApp/IG, multimodal additions, open-weight changes | Copyright lawsuits (still report, but MED), training-data disputes |
| **DeepSeek** | V-series releases, R-series reasoning models, terminal/CLI agents (TUI), open-weight licensing changes | Pricing wars commentary |
| **Microsoft (folded into Other)** | M365 Copilot release wave (mobile redesign, image editing, Notebooks, model choice), Copilot Studio multi-agent + A2A protocols, **Visual Studio 2026** updates (distinct from VS Code), GitHub Copilot changelog, VS Code 1.x releases (Copilot CLI, Skill Context, MCP Apps), Phi model releases | Build conference promos, partner showcases |
| **Other (dev tools)** | **Augment Code** (Auggie CLI, Remote Agent, Augment Agent — large-codebase coding agent), Cognition Devin (Terminal/Shell/Security), Bun runtime upgrades, LangGraph/LangChain releases, Vercel `ai@x.y` SDK + framework adapters, Firecrawl SDK + features, Replit / Bolt / Lovable / v0 releases, Poolside model drops, JetBrains AI updates | Conference tours, accelerator winners, valuations |
| **Compute & Infrastructure (folded into Other MED)** | Chip launches WHEN they directly drop $/token (NVIDIA Rubin GA, Groq 3 LPU GA), 1GW datacenter completions, hyperscaler capex when it materially shifts cloud pricing | Roadmap announcements without ship dates, financial projections |
| **Real-world AI (folded into EXTRAS or Other MED)** | Production-scale humanoid deployments, Robotaxi service launches by city, AR/VR headset launches with on-device AI | Speculative roadmaps, single-demo videos |
| **Legal & regulatory (folded into respective provider MED)** | Material rulings (verdict, injunction, settlement), regulator filings with industry-wide impact (EU AI Act enforcement) | Trial play-by-play, motion practice |

**Rule of thumb:** if the engineering team can't try it / install it / call it / configure it within a week, it's not HIGH — even if it's strategically interesting. Move to MED with a one-line context.
