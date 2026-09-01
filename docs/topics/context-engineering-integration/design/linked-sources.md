# Linked sources: the nine first-party pages behind the context-engineering corpus

Durable reference for the nine first-party pages that the two primary context-engineering
articles link. Written so a future contributor can use their content without re-fetching and
re-reading all nine.

The two primary articles are:

- **P1**, "The new rules of context engineering for Claude 5 generation models", Thariq
  Shihipar (@trq212), 2026-07-24, published as an X Article
  (`https://x.com/trq212/article/2080710971228918066`) and mirrored on the Anthropic blog
  (`https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models`).
- **P2**, "Effective context engineering for AI agents", Anthropic engineering blog,
  2025-09-29 (`https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents`).

The nine pages are the corpus's tier-2 set, labelled T1 through T9. T1 and T2 are one content
node (the Fable field guide, published on both X and claude.com/blog), so this file carries
eight sections for nine tier-2 entries. T9 is itself a pair of docs pages, cited separately
inside its section.

## How this file was assembled, and what it is not

Two evidence layers stand behind every section:

1. **Structural notes**, fetched 2026-08-31. Heading outlines, link inventories, figure
   inventories, per-section gists, and a per-page "relevance hooks" pass tying each page to
   corpus themes. The relevance framing survives only in that layer, and is folded into the
   "Why it matters here" lines below.
2. **Fresh paragraph-grain sweeps**, fetched 2026-09-01. Raw-HTML or DOM-parsed reads with
   every figure viewed directly, verbatim quotes recovered, and a four-lens critical apparatus
   (assumptions, omissions, internal tensions) added per page.

The two layers were reconciled page by page. The fresh layer is authoritative on structural
facts and numbers for every page except two: on T7 the two layers disagree over whether the
article embeds an image at all, unresolved; on T8 the fresh layer dropped the byline and
publish date, which are restored below from the structural layer. Both layers live in the
session memory tier, which is gitignored and does not survive container recycling. This file
is the committed record of their content.

**This file is a source reference, not an analysis.** The assumption, omission, and tension
rows for these pages, and the adjudication of what each page does and does not establish, live
in `design/critical-apparatus.md` alongside this file. Do not duplicate those rows here; cite
that file instead.

**Snapshot discipline.** Every page below is a live vendor URL that can change without a
visible revision note. Fetch dates are given per page and are the honest currency stamp. T5 and
T7 are both known to have been edited in place after publication. When citing any of these
pages in a repo instruction surface, carry the fetch date, and treat the page's own dateline as
untrustworthy where noted.

---

## 1. T1 / T2. A field guide to Claude Fable 5: finding your unknowns

One essay on two publishing surfaces. Linked from P1 twice, as the "written previously"
reference and as the "Fable field guide".

**Citation, X surface (T1)**

- Title: "A Field Guide to Fable: Finding Your Unknowns"
- URL: `https://x.com/trq212/status/2073100352921215386`
- Author: Thariq (@trq212), Claude Code, Anthropic
- Published: 2026-07-03. Fetched 2026-08-31 via the xtomd markdown converter plus the
  fxtwitter JSON API (the API-level `article` object confirms it is an X Article, not a
  note-tweet or a reply chain).

**Citation, blog surface (T2)**

- Title: "A field guide to Claude Fable 5: Finding your unknowns"
- URL: `https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns`
- Author: Thariq Shihipar, member of technical staff, Anthropic
- Published: 2026-07-06. Category "Claude Code", reading time 5 min. Fetched 2026-08-31, and
  re-swept 2026-09-01 from raw HTML.

The two surfaces carry the same argument. The X version has native entityMap link provenance
and five images; the blog version has three content figures and a related-posts block. The
blog version's closing section cross-links P1 as the companion piece, so the two articles point
at each other.

**What the page contains**

Heading structure (blog surface): an unheaded opening that states the map/territory framing,
then H2 "Knowing your unknowns", H2 "Help Claude help you", H2 "Pre-implementation" over five
H3 techniques (Blind Spot Pass, Brainstorms and prototypes, Interviews, References,
Implementation Plans), H2 "During implementation" over H3 "Implementation notes", H2 "Post
implementation" over H3 "Pitches and explainers" and H3 "Quizzes", H2 "How this comes together:
launching Fable", and the closing H2 "Matching the Map and Territory". The published HTML also
carries an empty FAQ heading stub.

Mechanisms taught:

- **Map and territory.** The map is what you give Claude (prompts, skills, context); the
  territory is the codebase and the real world. The gap between them is what the article calls
  *unknowns*. Claim: Fable is the first model generation where output quality is bottlenecked
  by the author's ability to clarify unknowns rather than by model capability.
- **The four-quadrant unknowns taxonomy.** Known knowns, known unknowns, unknown knowns,
  unknown unknowns. Each pre-implementation technique is mapped to the quadrant it surfaces.
  Boris and Jarred (Jarred Sumner) are named and LinkedIn-linked as practitioners with few
  unknowns because they are deeply in sync with both codebase and model behavior.
- **The specificity dilemma.** Too-specific instructions make Claude follow orders past the
  point a pivot would serve better; too-vague instructions make it fall back on generic best
  practices. The offered fix is context about the human's own starting point, experience, and
  thought process, not more procedural instruction.
- **Blind Spot Pass**, for unknown unknowns: ask Claude, using that literal phrase, to name
  what you do not know you do not know, given who you are and your experience level.
- **Brainstorms and prototypes**, for unknown knowns (taste you would recognize but cannot
  specify): prototype cheaply, for example a static HTML mock before wiring state or a backend;
  open sessions with a brainstorm to avoid scoping too narrow or too wide; the worked example
  asks for roughly ten interventions ordered cheapest to most ambitious, reacted to by
  resonance, and for four wildly different directions rather than variations on one.
- **Interviews**: ask Claude to interview you one question at a time, prioritizing questions
  whose answer would change the architecture.
- **References**: when something cannot be described in words, point Claude at real source
  code, even in a different language, rather than at diagrams or screenshots, because source
  carries richer structural detail. The worked example maps a Rust crate's semantics onto
  TypeScript.
- **Implementation Plans**: ask for a plan that foregrounds the decisions most likely to change
  (data models, type interfaces, UX flows) and buries mechanical refactoring, allocating the
  reviewer's attention rather than the model's.
- **Implementation notes**: start a fresh session per plan carrying the planning artifacts, and
  keep a running `implementation-notes.md` where Claude logs deviations, defaulting to the
  conservative choice and continuing, so failures become learning for the next attempt.
- **Pitches and explainers**: bundle spec, prototype, and notes into one shareable document,
  on the theory that reviewers start with the same unknowns the author did.
- **Quizzes**: reading a diff gives only shallow understanding of behavior that depends on
  existing code paths, so have Claude generate a report plus a quiz over the change and treat
  passing it as a personal merge gate.
- **Worked case study**: editing Fable's own launch video end to end in Claude Code, including
  a transcription explainer to test feasibility, a Remotion caption prototype, and the
  color-grading pivot where the author asked Claude to *teach* him the domain rather than
  produce variants he could not evaluate.

**Why it matters here**

This is the first-party articulation of the over-specification failure mode that the repo's
unhobbling and instruction-audit work rests on, and its Interviews and Blind Spot Pass patterns
are the named upstream of interview-style and blindspot planning skills in this marketplace.

**Where the deep apparatus lives**

`design/critical-apparatus.md`. Note additionally that this page already has a dedicated repo
integration audit at `docs/topics/fable-field-guide-audit/`, which dispositions the article's
claims against the `fable-5` playbook and governs its own remediation ledger. That audit and
the critical apparatus are complementary: the audit is repo-facing, the apparatus is
article-facing.

---

## 2. T3. A harness for every task: dynamic workflows in Claude Code

Linked from P1 twice, as the source for the rubrics and verifier-agents claim and for dynamic
workflows themselves.

**Citation**

- Title: "A harness for every task: dynamic workflows in Claude Code" (the `<title>` tag adds
  the site suffix "| Claude by Anthropic")
- URL: `https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code`
- Authors: byline metadata credits Thariq Shihipar; the closing line credits "Thariq Shihipar
  and Sid Bidasaria, members of technical staff at Anthropic working on Claude Code"
- Published: June 2, 2026. Category "Claude Code", reading time 5 min. Fetched 2026-08-31 and
  re-swept 2026-09-01 from raw HTML, with all nine inline figures downloaded and viewed. No
  revision caveat: the two passes agree on date, byline, headings, and links.

**What the page contains**

Heading structure: H2 "Example prompts", H2 "How dynamic workflows work", H2 "Why dynamic
workflows", H2 "Dynamic vs static workflows", H2 "Helpful patterns when using dynamic
workflows" over six H3 patterns, H2 "Use cases" over ten H3 recipes, H2 "When not to use
dynamic workflows", H2 "Tips for building dynamic workflows" over four H3 tips (Prompting;
Combine with `/goal` and `/loop`; Token usage budgets; Saving and sharing dynamic workflows),
and H2 "A new starting point for discovery".

**The workflow API surface.** A dynamic workflow executes a JavaScript file with special
functions for spawning and coordinating subagents, plus standard JavaScript (JSON, Math, Array)
for data processing. The API itself appears only in Figure 1, never in prose. Three primitives:

```
agent(prompt, opts?): Promise<string | JsonSchema>

const bugs = await agent("audit auth.ts", {
  schema: BugList,          // JSON Schema -> validated JSON output
  model: "haiku",           // opus | sonnet | haiku. Omit = inherit
  isolation: "worktree",    // "worktree" (checkout) or "remote"
  agentType: "reviewer"     // custom / built-in subagent
})

parallel([ fns ])   // Fan out, run at once. Barrier - waits for all.
const all = await parallel(files.map(f => () => agent(f)))

pipeline(items, ...) // Each item streams through every stage. No barrier.
await pipeline(items, x => agent(draft(x)), d => agent(check(d)))
```

`prompt` is described as "the agent's only input, required". The workflow itself chooses each
agent's model and whether subagents run in their own worktree, so Claude controls both
intelligence level and isolation. Interrupted workflows resume where they left off. `pipeline`
is never exercised in the article's prose; its semantics exist only in that figure.

**The three named failure modes** of long single-context work, verbatim:

```
Agentic laziness refers to when Claude stops before finishing a particularly complex,
multi-part task and declares the job done after partial progress, for example addressing
35 of the 50 items in a security review.

Self-preferential bias refers to Claude's tendency to prefer its own results or findings,
especially when asked to verify or judge them against a rubric.

Goal drift refers to the gradual loss of fidelity to the original objective across many
turns, especially after compaction. Each summarization step is lossy, and details like
edge-case requirements or "don't do X" constraints can get lost.
```

The remedy offered for all three is the same structural move: subagents with their own context
windows and focused, isolated goals. The four task classes where single-context work breaks
down are named as long-running, massively parallel, highly structured, and adversarial.

**The six named patterns**, each quoted in full on the page and drawn as a 2x3 grid figure
titled "Six Workflow Patterns":

1. **Classify-and-act.** A classifier agent decides the task type and routes to different
   agents or behavior, or classifies at the end to determine output.
2. **Fan-out-and-synthesize.** Split into smaller steps, run an agent per step, then
   synthesize. Stated conditions: many small steps, or steps that benefit from a clean context
   window so they do not cross-contaminate. The synthesize step is explicitly a barrier that
   waits for all fan-out agents and merges their structured outputs, matching `parallel`.
3. **Adversarial verification.** For each spawned agent, run a separate agent to adversarially
   verify its output against a rubric or criteria. The figure shows one worker against three
   verifiers, so a panel is in scope.
4. **Generate-and-filter.** Overgenerate ideas, then filter by rubric or verification, dedupe,
   and return only the highest-quality tested ideas.
5. **Tournament.** Rather than dividing work, N agents attempt the same task by different
   approaches, and a judging agent compares pairwise until a winner emerges.
6. **Loop until done.** For work of unknown size, loop spawning agents until a stop condition
   (no new findings, no more errors in the logs) instead of a fixed number of passes. This is
   the direct structural counter to agentic laziness.

**The quarantine architecture for untrusted content** appears under the "Triaging at scale" use
case and is the page's prompt-injection defense:

```
A useful pattern for triage workflows is quarantine. This involves barring the agents that
read untrusted public content from taking high-privilege actions, which are instead done by
the agents in charge of acting on the information.
```

The accompanying figure draws it as privilege separation across a trust boundary: an untrusted
backlog feeds a dashed quarantine zone labelled "read-only tools, no privileges" holding one
reader agent per item plus a dedupe step; only a structured summary crosses into the trusted
zone, where "high-privilege tools live here" and an actor agent acts on summaries and never on
raw content, then either attempts a fix and opens a PR or escalates to a human. `/loop` runs it
continuously.

**Other named mechanisms and numbers.**

- Invocation: ask Claude for a workflow, or use the trigger word `ultracode`.
- Ten use cases: migrations and refactors (Bun's Zig-to-Rust rewrite is cited), deep research,
  deep verification (claim extractor, then per-claim checkers, then optional source auditors
  checking the checkers), sorting, memory and rule adherence, root-cause investigation,
  triaging at scale, exploration and taste, evals, and model and intelligence routing.
- Sorting: single-prompt sorting of 1000+ rows degrades and will not fit context. The stated
  method is a tournament, a pipeline of pairwise-comparison agents, or parallel bucket-ranking
  then merge, with the parenthetical methodological claim that comparative judgment is more
  reliable than absolute scoring. The deterministic loop holds the bracket, so only the running
  order stays in context. Every judging node in the figure is labelled "fresh agent".
- Memory and rule adherence: one verifier agent per rule with a clean context each, plus a
  skeptic-persona reviewer to cut false positives. The reverse direction mines sessions and
  code-review comments for repeated corrections, clusters them with parallel agents,
  adversarially verifies each candidate against the counterfactual "would this rule have
  prevented a real mistake?", and distills survivors into `CLAUDE.md`.
- Restraint: workflows may use significantly more tokens; the self-check is "does it really
  need more compute?", with the observation that most traditional coding tasks do not need a
  panel of five reviewers, cross-linked to the multi-agent post's claim that parallelism and
  specialization have to earn their coordination cost.
- Tips: token budgets are set in natural language ("use 10k tokens") and become a real cap;
  press `s` in the workflow menu to save; check workflows into `~/.claude/workflows` or ship
  them in a skill folder as `*.workflow.js` referenced from `SKILL.md`, prompting Claude to
  treat a shared workflow as a template rather than a script to run verbatim.
- The article's only concrete cost data lives inside the workflow-menu figure and appears
  nowhere in prose: `deep-research` at 22 agents / 1.1M tokens / 11m 3s, `review-changes` at
  14 agents / 482k tokens / 6m 12s, `find-flaky-tests` at 6 agents / 121k tokens / 1m 48s.

**Why it matters here**

This is the first-party source for adversarial verification, fan-out with an explicit barrier,
and orchestration restraint, all of which this marketplace's audit, review, and fan-out skills
implement; the quarantine architecture is the citable pattern for any skill that reads
untrusted content, and the rule-verifier recipe is a first-party workaround for `CLAUDE.md`
rules a model ignores.

**Where the deep apparatus lives**

`design/critical-apparatus.md`.

---

## 3. T4. Writing effective tools for agents, with agents

Linked from P2 as the tool-design guidance its tool-anatomy section leans on.

**Citation**

- On-page H1, verbatim: `Writing effective tools for agents — with agents`. The `<title>` tag
  differs, verbatim: `Writing effective tools for AI agents—using AI agents \ Anthropic`. Both
  passes report this mismatch identically. Quote whichever form the citation needs, but note
  that both carry a dash this repo's own prose style does not.
- URL: `https://www.anthropic.com/engineering/writing-tools-for-agents`
- Author: Ken Aizawa, with contributions credited by team in the Acknowledgements
- Published: Sep 11, 2025. Fetched 2026-08-31, re-swept 2026-09-01 from raw HTML with all eight
  content figures viewed. The 2026-09-01 sweep supersedes the earlier one: the first pass ran
  through a summarizing fetch channel that returned no body text for parts of "Looking ahead".

**What the page contains**

Heading structure: H2 "What is a tool?", H2 "How to write tools" over H3 "Building a
prototype", H3 "Running an evaluation" (with sub-steps "Generating evaluation tasks", "Running
the evaluation", "Analyzing results") and H3 "Collaborating with agents", H2 "Principles for
writing effective tools" over five H3 principles, H2 "Looking ahead", H2 "Acknowledgements".

Framing: a tool is a contract between deterministic software and a non-deterministic agent, so
tool design cannot copy conventional API or SDK conventions. Everything in the post is
inference-time and tool-side, footnoted as being beyond training the underlying models.

**The quantified results.** Both are held-out test-set bar charts, and the numbers exist only
in the figures:

- Slack tools: human-written MCP server **67.4%** test-set accuracy, Claude-optimized MCP
  server **80.1%**, a gain of 12.7 points. Figcaption: "Held-out test set performance of our
  internal Slack tools".
- Asana tools: human-written **79.6%**, Claude-optimized **85.7%**, a gain of 6.1 points.
  Figcaption: "Held-out test set performance of our internal Asana tools".

The article states it relied on held-out test sets to avoid overfitting to its training
evaluations, and that the improvements went beyond what expert implementations achieved,
whether written by researchers or generated by Claude. No task counts, error bars, model
identity, or train/test split are given.

**The `response_format` enum**, the article's flagship expressive-parameter example and its
only code block, verbatim:

```
enum ResponseFormat {
   DETAILED = "detailed",
   CONCISE = "concise"
}
```

The worked example is a Slack search call with `responseFormat: "detailed"` against
`responseFormat: "concise"` over the same 89 results. Detailed is **206 tokens** and carries
`thread_ts`, `channel_id`, and `user_id`; concise is **72 tokens** and carries only thread
content. The figcaption states the ratio directly: "In this example, we use ~1/3 of the tokens
with 'concise' tool responses." The stated reason detailed mode exists at all is that agents
sometimes need identifiers to chain calls, for example `search_user(name='jane')` feeding
`send_message(id=12345)`. The article suggests adding further formats "similar to GraphQL where
you can choose exactly which pieces of information you want to receive".

**Other mechanisms and numbers.**

- Prototype and connect: `claude mcp add <name> <command> [args...]` for Claude Code; Settings
  > Developer or Settings > Extensions for Claude Desktop.
- Evaluation loop: build realistic multi-step tasks with verifiable outcomes, avoid verifiers
  so strict they reject correct-but-differently-phrased answers, capture full transcripts, and
  feed them back to Claude Code for agent-driven refinement.
- Choosing tools: consolidate overlapping operations rather than exposing many narrow tools;
  the running example merges an availability check and event creation into one
  `schedule_event`.
- Namespacing: group by shared prefix or suffix (`asana_search`, `jira_search`); the article
  reports that prefix versus suffix choice measurably affected evaluation performance, so test
  both.
- Meaningful context: return high-signal fields (`name`, `image_url`, `file_type`) over
  low-level identifiers (`uuid`, `256px_image_url`, `mime_type`); resolving arbitrary
  alphanumeric UUIDs to semantically meaningful language, or even a 0-indexed scheme, is
  claimed to improve retrieval precision by reducing hallucinations. Response serialization
  (XML, JSON, Markdown) is stated to affect evaluation performance with no one-size-fits-all
  answer, because models perform better on formats resembling their training data.
- Token efficiency: pagination, range selection, filtering, and truncation with sensible
  defaults. The one hard number: "For Claude Code, we restrict tool responses to 25,000 tokens
  by default." Errors should be actionable and specific so the agent can self-correct; the
  article contrasts an unhelpful error figure against a helpful one.
- Tool descriptions: called one of the most effective levers, to be written as if onboarding a
  new employee, with Claude Sonnet 3.5's SWE-bench Verified results cited as partly
  attributable to description refinement.
- Figure-internal numbers, from the hero terminal transcript: accuracy 17/20 (85.0%), average
  task duration 15.77s, 1,219 lines written.

**Why it matters here**

This is the citable first-party basis for token-budgeted tool returns, consolidated tool sets,
and expressive parameters, all of which bear directly on how this marketplace's plugins define
MCP tools and shape tool output.

**Where the deep apparatus lives**

`design/critical-apparatus.md`.

---

## 4. T5. Building effective agents

Linked from P2 as the source of its workflow-versus-agent definition.

**Citation, and the revision caveat**

- On-page H1: "Building effective agents". The `<title>` tag reads "Building Effective AI
  Agents \ Anthropic".
- URL: `https://www.anthropic.com/research/building-effective-agents`
- Authors: the Acknowledgements read "Written by Erik S. and Barry Zhang." The original release
  credited Erik Schluntz; the live page shortens the surname.
- Dateline: "Published Dec 19, 2024". **Do not cite it by that dateline.** The page is silently
  revised in place. As fetched, it names Claude Haiku 4.5 and Claude Sonnet 4.5 and the Claude
  Agent SDK, all of which postdate December 2024, and its framework list has been swapped: the
  original named LangGraph and Amazon Bedrock's AI Agent framework, while the live page names
  the Claude Agent SDK, Strands Agents SDK by AWS, Rivet, and Vellum. **Cite it by fetch date:
  fetched 2026-09-01** (raw HTML, all eight figures viewed; an earlier structural pass ran
  2026-08-31 with matching results).
- The live page also carries an editorial update note, verbatim:

```
Note: Much of the tooling landscape described in this post has changed since December 2024.
For our current approach, see how we built Claude Managed Agents and the Managed Agents
documentation.
```

**What the page contains**

Heading structure, confirmed from raw HTML including anchor ids: H2 "What are agents?", H2
"When (and when not) to use agents", H2 "When and how to use frameworks", H2 "Building blocks,
workflows, and agents" over H3 "Building block: The augmented LLM", H3 "Workflow: Prompt
chaining", H3 "Workflow: Routing", H3 "Workflow: Parallelization", H3 "Workflow:
Orchestrator-workers", H3 "Workflow: Evaluator-optimizer" and H3 "Agents", then H2 "Combining
and customizing these patterns", H2 "Summary" over H3 "Acknowledgements", H2 "Appendix 1:
Agents in practice" over H3 "A. Customer support" and H3 "B. Coding agents", and H2 "Appendix
2: Prompt engineering your tools". "Agents" and "Acknowledgements" are H3s in the live markup
even though they read as top-level.

**The definitional split**, which P2 borrows: workflows are "systems where LLMs and tools are
orchestrated through predefined code paths", agents are "systems where LLMs dynamically direct
their own processes and tool usage, maintaining control over how they accomplish tasks".

**The workflow patterns**, each with its own diagram:

- **The augmented LLM**, the base unit: an LLM with retrieval, tools, and memory, which the
  model drives itself (writing its own search queries, picking tools, deciding what to retain).
  Guidance: tailor the augmentations, and give the model an easy, well-documented interface.
- **Prompt chaining**: a fixed sequence of LLM calls, each processing the prior output, with
  optional programmatic gates between steps. Trades latency for accuracy where a task
  decomposes cleanly.
- **Routing**: classify an input, send it down one of several specialized paths, so each path
  gets a targeted prompt. Includes routing easy queries to a cheaper model and hard ones to a
  larger one.
- **Parallelization**, in two variants: *sectioning* (independent subtasks run concurrently,
  then aggregated) and *voting* (the same task run several times, then combined or voted).
- **Orchestrator-workers**: "a central LLM dynamically breaks down tasks, delegates them to
  worker LLMs, and synthesizes their results", distinguished from parallelization because the
  subtasks are determined at run time from the input rather than fixed in advance.
- **Evaluator-optimizer**: one call generates, a second evaluates and gives feedback, looping
  until satisfied. Works where an evaluation criterion is clear and iterative feedback
  demonstrably helps.
- **Agents**: what emerges once the model reliably understands complex input, plans, uses
  tools, and recovers from errors. The compressed definition, which P2's lineage traces back
  to, is that agents are "typically just LLMs using tools based on environmental feedback in a
  loop".

The throughline is minimalism: find the simplest solution possible and increase complexity only
when needed, which "might mean not building agentic systems at all"; for many applications a
single optimized LLM call with retrieval and in-context examples is enough; agentic systems
trade latency and cost for task performance. The Summary states three design principles:
maintain simplicity, prioritize transparency by showing the agent's planning steps, and
carefully craft the agent-computer interface.

<!-- spellchecker:off -->
**The ACI appendix (Appendix 2)** is the origin of the agent-computer interface term. Its
content: tools deserve as much prompt-engineering attention as the rest of the prompt, because
there are many ways to specify the same action (a diff format versus a full file rewrite) and
some are much harder for a model to produce correctly. Practical guidance is to give the model
enough tokens to think before it commits, keep formats close to what occurs naturally in
internet text, and strip formatting overhead such as making the model count lines. It tells you
to invest in the ACI with the rigor of a human-computer interface: put yourself in the model's
shoes, write parameter names and descriptions as if writing an excellent docstring, test in the
workbench, and apply Poka-yoke mistake-proofing.
<!-- spellchecker:on -->
The cited case is the SWE-bench build, where
the team spent more time optimizing tools than the overall prompt, and fixed recurring
relative-filepath mistakes by requiring absolute filepaths. Appendix 1 names customer support
and coding agents as the two domains where agents demonstrably pay off, because those tasks
combine conversation and action, clear success criteria, feedback loops, and human oversight.

**Why it matters here**

This is the definitional ancestor for workflows versus agents and for orchestrator-workers, the
vocabulary this repo's orchestration and planning skills use, and Appendix 2 is the origin of
the tool-interface discipline that T4 later expands.

**Where the deep apparatus lives**

`design/critical-apparatus.md`, which also carries the tension between the page's
anti-framework stance and the framework list the revision inserted.

---

## 5. T6. How we built our multi-agent research system

Linked from P2 as its sub-agent architecture evidence base.

**Citation**

- Title: "How we built our multi-agent research system" (the `<title>` adds "\ Anthropic")
- URL: `https://www.anthropic.com/engineering/multi-agent-research-system`
- Authors, from the Acknowledgements: Jeremy Hadfield, Barry Zhang, Kenneth Lien, Florian
  Scholz, Jeremy Fox, and Daniel Ford. The heading is misspelled on the page, missing its
  second `d`.
<!-- spellchecker:off -->
  (Verbatim: "Acknowlegements".)
<!-- spellchecker:on -->
- Published: Jun 13, 2025. Fetched 2026-08-31 from raw HTML, re-swept 2026-09-01 with all three
  figures viewed. The two passes cross-validate closely and contradict nowhere.

**What the page contains**

Heading structure as it exists in the DOM, which is not normalized: every main-body section is
an H3 (Benefits of a multi-agent system; Architecture overview for Research; Prompt engineering
and evaluations for research agents; Effective evaluation of agents; Production reliability and
engineering challenges; Conclusion; the misspelled Acknowledgements heading noted above), and
only the trailing Appendix is an H2. There is no H4 anywhere.

**The token multipliers and the variance finding**, verbatim:

```
agents typically use about 4x more tokens than chat interactions, and multi-agent systems
use about 15x more tokens than chats
```

```
three factors explained 95% of the performance variance in the BrowseComp evaluation (which
tests the ability of browsing agents to locate hard-to-find information). We found that token
usage by itself explains 80% of the variance, with the number of tool calls and the model
choice as the two other explanatory factors.
```

The multipliers gate the economics: multi-agent systems require tasks whose value is high
enough to pay for the increased performance. The variance finding is used to validate
distributing work across agents with separate context windows to add capacity for parallel
reasoning. Adjacent claim: upgrading to Claude Sonnet 4 is a larger performance gain than
doubling the token budget on Claude Sonnet 3.7. The headline eval win: a multi-agent system
with Claude Opus 4 as lead and Claude Sonnet 4 subagents outperformed single-agent Claude Opus
4 by 90.2% on an internal research eval. Neither the internal eval nor the BrowseComp
regression is described methodologically, and the 90.2% figure's metric and denominator are
never defined.

Poor fits are named explicitly: domains requiring all agents to share context, or with many
inter-agent dependencies. Most coding tasks are the named counter-example, having fewer truly
parallelizable subtasks than research, with LLM agents not yet good at real-time delegation to
each other. Good fits are high-value tasks with heavy parallelization, information exceeding a
single context window, and many complex tool interfaces.

**Architecture**: an orchestrator-worker pattern where a lead agent coordinates and delegates
to parallel subagents, contrasted explicitly with static RAG's fixed similarity-chunk
retrieval. The lead agent persists its plan to Memory because context beyond 200,000 tokens
gets truncated. The figures show the lead agent's tool set as search tools plus MCP tools plus
memory plus `run_subagent` plus `complete_task`, with a separate CitationAgent inserting
citations into the finished report.

**Eight prompt-engineering principles**, all reproduced verbatim in the fresh sweep: think like
your agents (build step-by-step simulations in Console); teach the orchestrator to delegate
with full task specs (objective, output format, tool and source guidance, explicit boundaries,
with the semiconductor-shortage example showing what duplicated work looks like without them);
scale effort to query complexity with embedded rules (simple: 1 agent, 3-10 calls; comparisons:
2-4 subagents, 10-15 calls each; complex: 10+ subagents with divided responsibilities); treat
tool design and selection as critical, mitigating inconsistent MCP description quality with
explicit heuristics; let agents improve themselves, where a dedicated tool-testing agent's
rewritten description cut future task-completion time by 40%; start wide then narrow; guide the
thinking process using extended thinking as a controllable planning scratchpad and interleaved
thinking for subagents evaluating tool results; and use parallel tool calling, where 3-5
parallel subagents plus 3+ parallel tool calls each cut research time by up to 90%.

**The evaluation methodology**, which is the page's most transferable section:

- Multi-agent systems break the "same input, same expected path" assumption, because valid
  trajectories vary. Evaluate outcomes and reasonable process, not prescribed steps.
- Start evaluating immediately with small samples. About 20 queries representing real usage
  patterns sufficed early, because early-stage prompt tweaks can swing success rates from 30%
  to 80% and effect sizes that large are visible in a handful of cases. The named mistake is
  waiting to build hundreds of test cases first.
- LLM-as-judge against a rubric covering factual accuracy, citation accuracy, completeness,
  source quality, and tool efficiency. A single LLM call emitting a 0.0 to 1.0 score plus
  pass/fail was found most consistent and scales to hundreds of outputs.
- Human evaluation still catches what automation misses. The worked case: testers noticed early
  agents favored SEO content farms over authoritative sources such as academic PDFs, fixed by
  adding source-quality heuristics.
- Emergent behavior: small lead-agent prompt changes ripple unpredictably into subagent
  behavior, so the best prompts are collaboration frameworks (division of labor,
  problem-solving approach, effort budgets) rather than rigid instructions.

**Production engineering**: agents are stateful and errors compound, so the system uses durable
execution resumable from failure with retries and checkpoints rather than expensive restarts;
debugging needs full production tracing of decision patterns without inspecting conversation
contents, for privacy; deployment uses rainbow deployments (gradual traffic shift between
simultaneously running versions) because agents are almost continuously mid-process; and
synchronous subagent execution is named as a current bottleneck, with async execution flagged
as future work.

**The Appendix** adds three tips, each a bolded lead-in rather than a heading: end-state
evaluation for agents that mutate persistent state, judging the final state rather than tracing
the process, with discrete checkpoints for complex workflows; long-horizon conversation
management, where agents summarize completed phases into external memory, spawn fresh subagents
with clean context while preserving continuity through handoffs, and retrieve stored plans
rather than losing work at the context limit; and subagent output to a filesystem to avoid the
"game of telephone", where subagents persist artifacts externally and pass back lightweight
references instead of routing everything through the lead agent's conversation history.

**Why it matters here**

This is the only source in the set with cost data an "is fan-out worth it" argument can cite,
and it carries the spec-every-spawn and effort-scaling lessons this marketplace's orchestration
skills encode, plus an evaluation methodology directly reusable for skill evals.

**Where the deep apparatus lives**

`design/critical-apparatus.md`, including the tension between the page's own compression claim
and its Appendix's game-of-telephone framing of the same relay step.

---

## 6. T7. Managing context on the Claude Developer Platform

Linked from P2 as the product surface for its compaction and memory-tool claims.

**Citation, and the dating caveat**

- Title: "Managing context on the Claude Developer Platform" (the `<title>` adds "| Claude by
  Anthropic"). Dek: "Introducing context editing and the memory tool to help developers build
  more effective agents that handle long-running tasks."
- URL as linked: `https://www.anthropic.com/news/context-management`, which 308-redirects to
  `https://claude.com/blog/context-management`. Cite the resolved URL.
- Category "Product announcements", product "Claude Platform", reading time 5 min. No named
  author.
- Published: September 29, 2025. The page's embedded JSON-LD carries `datePublished` "Sep 29,
  2025" and `dateModified` "Jun 21, 2026", so the page was edited roughly eight to nine months
  after publication with no in-body revision note. Fetched 2026-08-31 and re-swept 2026-09-01.

**Resolved, in favor of the later sweep.** The two passes disagreed over whether the article
embeds any image: the 2026-09-01 sweep reported one diagram, the 2026-08-31 pass reported a
targeted `<img>` and `<figure>` search returning zero matches and concluded the page was
text-only. Settled 2026-09-01 by direct inspection of the retained HTML and of the image itself,
which is the evidence neither pass had: the page carries one content diagram at
`cdn.prod.website-files.com/.../8ad2952bc0513750088cdfd309ee83ba0fd15438-1920x800.webp`, titled
"Before context editing" over "After context editing". It shows a context window as a strip of
alternating tool-use and tool-result blocks; in the "after" strip the earliest pairs are
compressed to a fraction of their width and the reclaimed span is filled by a single green
"Available Context" block. The earlier pass's negative result came from searching a byline-to-
related-posts slice that excludes the figure's position. Treat a bounded-slice absence search as
evidence about the slice, never about the page.

**What the page contains**

Heading structure, four H2s: "Context windows have limits, but real work doesn't"; "Building
long-running agents"; "Performance improvements with context management"; "Getting started".

**Scope: this is API-only.** Everything described is a Claude Developer Platform primitive that
a calling application wires up. Context editing is an API parameter. The memory tool is
client-side: Claude emits tool calls, and the developer's own code hosts the file backend in
their infrastructure. Claude Code is not named anywhere on the page. Do not read this
announcement as evidence that any harness, Claude Code included, does context editing natively;
it substantiates only that the API-level building block exists. Availability at publication:
public beta, natively on the Claude Developer Platform and also through Amazon Bedrock and
Google Cloud Vertex AI.

**The two mechanisms**, verbatim on scope and trigger:

```
Context editing automatically clears stale tool calls and results from within the context
window when approaching token limits. As your agent executes tasks and accumulates tool
results, context editing removes stale content while preserving the conversation flow,
effectively extending how long agents can run without manual intervention.
```

```
The memory tool enables Claude to store and consult information outside the context window
through a file-based system. Claude can create, read, update, and delete files in a dedicated
memory directory stored in your infrastructure that persists across conversations.
```

What context editing clears, as literally stated, is tool calls and tool results only, never
user or assistant text turns. The trigger is "when approaching token limits", with no threshold
given. Claude Sonnet 4.5 is credited with built-in context awareness, tracking its own
remaining tokens. Three use cases pair the two mechanisms: coding (editing clears old file
reads and test results, memory keeps debugging insights and architectural decisions), research
(memory stores findings, editing drops old search results), and data processing (memory holds
intermediate results, editing clears raw data).

**The three figures, with their eval caveats:**

```
On an internal evaluation set for agentic search, we tested how context management improves
agent performance on complex, multi-step tasks. The results demonstrate significant gains:
combining the memory tool with context editing improved performance by 39% over baseline.
Context editing alone delivered a 29% improvement.
```

```
In a 100-turn web search evaluation, context editing enabled agents to complete workflows
that would otherwise fail due to context exhaustion - while reducing token consumption by 84%.
```

Caveats that must travel with those numbers: both evals are internal and named only
descriptively, with no linked benchmark, no methodology, no sample size, no metric definition,
and no stated model. The word "baseline" is never operationally defined. No memory-tool-alone
figure is given, so the reader cannot attribute the gap between 29% and 39% to memory. The 84%
figure carries no absolute token counts and no statement that output quality was held constant.
The relationship between the "internal evaluation set for agentic search" and the "100-turn web
search evaluation" is never stated.

**Why it matters here**

This is the primary source for the API-versus-harness boundary that this repo's context-budget
and memory guidance must not blur, and it is the citable anchor for tool-result clearing as the
lowest-risk context-reduction lever.

**Where the deep apparatus lives**

`design/critical-apparatus.md`.

---

## 7. T8. Memory and context management with Claude Sonnet 4.6 (cookbook)

Linked from P2 as the hands-on cookbook it closes with.

**Citation**

- Title: "Memory & context management with Claude Sonnet 4.6", rendered on the page in title
  case as "Memory & Context Management with Claude Sonnet 4.6 | Claude Cookbook". Normalize
  before quoting it as the exact title.
- URL: `https://platform.claude.com/cookbook/tool-use-memory-cookbook`. The `.md` twin at that
  path returns 404; this docs site does not serve one.
- Author: Alex Notov (@zealoushacker). Published May 22, 2025. Notebook source:
  `anthropics/claude-cookbooks/blob/main/tool_use/memory_cookbook.ipynb`. Categories: Tools,
  Agent Patterns.
- Fetched 2026-08-31, re-swept 2026-09-01. The byline and date above come from the earlier
  pass; the fresh sweep dropped them.

**What the page contains**

This is a notebook, not a prose doc. Section outline: Introduction: Why Memory Matters;
Prerequisites & Setup; Quick Start Examples (Setup Code, Example 1 Basic Memory Usage, Example
2 Cross-Conversation Learning, Example 3 Context Clearing While Preserving Memory); How It
Works (Memory Tool Architecture, Thinking Management, Understanding the Demo Code, What Claude
Actually Learns, Why This Matters); Use Cases; Best Practices & Security (Memory Management,
Path Traversal, Memory Poisoning); Real-World Applications; Sample Code Files; Helper
Functions; Conclusion & Next Steps.

The running scenario is one Code Review Assistant across three sessions: it diagnoses a race
condition in a threaded `WebScraper` and writes the pattern to `/memories/review.md`; a new
conversation reviews an unrelated async `AsyncAPIClient` and recognizes the same pattern by
reading memory first rather than re-deriving it; then a long multi-file session runs both
clearing strategies while the on-disk memory stays intact.

**The tool primitives.** The memory tool is client-side. Claude emits tool calls against a
`/memories` path space and the calling application executes them against real storage. Six
commands, each with an example payload:

```
view        {"command": "view", "path": "/memories"}
create      {"command": "create", "path": "/memories/notes.md", "file_text": "..."}
str_replace {"command": "str_replace", "path": "...", "old_str": "...", "new_str": "..."}
insert      {"command": "insert", "path": "...", "insert_line": 2, "insert_text": "..."}
delete      {"command": "delete", "path": "/memories/old.txt"}
rename      {"command": "rename", "old_path": "...", "new_path": "..."}
```

The implementation, including path validation, is deferred to a `memory_tool.py` the page never
reproduces.

**The combined API call shape**, as given for thinking plus tool-use context management:

```
client.beta.messages.create(
  betas=["context-management-2025-06-27"],
  model="claude-sonnet-4-6",
  tools=[{"type": "memory_20250818", "name": "memory"}],
  thinking={"type": "enabled", "budget_tokens": 10000},
  context_management={"edits": [
    {"type": "clear_thinking_20251015", "keep": {"type": "thinking_turns", "value": 1}},
    {"type": "clear_tool_uses_20250919",
     "trigger": {"type": "input_tokens", "value": 35000},
     "keep": {"type": "tool_uses", "value": 5}}
  ]},
  max_tokens=2048)
```

The beta header `context-management-2025-06-27` is required for both the memory tool and
context editing. `clear_thinking_20251015` requires extended thinking enabled in the same call
and must be listed first when combined with tool-use clearing; its `trigger` field is optional,
so clearing can be driven by `keep` alone, and `"keep": "all"` preserves every thinking block
for maximum cache hits. Example 3's demo values (trigger 5,000, keep 2, `budget_tokens` 1024)
are deliberately small; the page's production recommendation elsewhere is 30,000 to 40,000
input tokens.

**The token-threshold trace** from Example 3, the page's only numeric evidence: Review 1
(`data_processor_v1.py`) at 6,611 input tokens reports no clearing triggered; Review 2
(`sql_query_builder.py`) at 7,923 input tokens clears one thinking turn, saving 166 tokens;
Review 3 (`web_scraper_v1.py`) at 9,052 input tokens clears two thinking turns, saving 265
tokens. A post-hoc cell then walks the demo memory directory and shows `memories/review.md`
still present at 318 bytes, which is the point being demonstrated: context editing clears the
conversation's transient history, never the durable memory filesystem. Note that Review 1's
6,611 tokens already exceed the demo's own 5,000-token trigger while the transcript says no
clearing fired, so the reported behavior is self-contradictory on a literal read.

**The memory-poisoning threat list.** Two named security threats. *Path traversal* is one
sentence, "Always validate paths to prevent directory traversal attacks", with implementation
deferred to `memory_tool.py`. *Memory poisoning* is labelled a Critical Risk: memory files are
read back into Claude's context on later turns, so anything written into one is a
prompt-injection vector. Four named mitigations: content sanitization (filter dangerous
patterns before storing), memory scope isolation (per user, per project), memory auditing (log
and scan all memory operations), and prompt engineering (instruct Claude to ignore instructions
found inside memory content). Memory hygiene adds a do list (store task-relevant patterns not
conversation history, clear directory structure, descriptive filenames, periodic cleanup) and a
don't list (no secrets or PII, no unbounded growth, nothing indiscriminate).

**The stale supported-model lists.** The page gives two incompatible "Supported Models" lists
for what appears to be the same feature. Section 1 lists five: Opus 4.1 (`claude-opus-4-1`),
Opus 4 (`claude-opus-4`), Sonnet 4.6 (`claude-sonnet-4-6`), Sonnet 4 (`claude-sonnet-4`), and
Haiku 4.5 (`claude-haiku-4-5`). The Use Cases and Real-World Applications sections each repeat
a narrower two-model list, Opus 4.1 and Sonnet 4.6, with identical wording. The page never
explains whether the narrow list is a smaller capability subset or simply stale copy, and it
carries no "check the docs for the current list" caveat. Treat both lists as stale and verify
against current model docs before citing either.

Closing production guidance: start with a single `/memories/patterns.md`, set context-editing
triggers at 30,000 to 40,000 tokens for production, isolate memory per project. The page states
plainly that memory and context management are in beta.

**Why it matters here**

This is the worked example of the build-it-yourself side of the API-versus-harness axis, and
its memory-poisoning threat list is the citable basis for the security caveats this repo owes
any durable-memory or note-writing guidance.

**Where the deep apparatus lives**

`design/critical-apparatus.md`.

---

## 8. T9. The prompt-engineering docs pair

Linked from P2 as the prompt-engineering docs it positions itself against. This is two pages,
not one. The earlier structural pass covered only the first; both were swept 2026-09-01, and
the second contributes the overwhelming majority of the technique content.

**Citation, page 1 (the router)**

- Title: "Prompt engineering overview". Frontmatter description: "Learn when prompt engineering
  is the right solution, and find Claude prompting techniques and interactive tutorials."
- URL as linked:
  `https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview`, which
  301s then 307s to the canonical
  `https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview`. Cite the
  canonical form.
- No named author, no publication date (docs page). Fetched 2026-08-31 and 2026-09-01 through
  the `.md` channel.

**Citation, page 2 (the living reference)**

- Title: "Prompting best practices"
- URL:
  `https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices`
- No named author, no publication date. Fetched 2026-09-01 through the `.md` channel.

**What page 1 contains**

Four sections and no technique content at all: "Before prompt engineering" (assumes you already
have success criteria, an empirical test method, and a first-draft prompt; otherwise go build
evals first; links a Colab metaprompt notebook), "When to prompt engineer" (one sentence,
scoping the guide to criteria controllable through prompting and stating that switching models
can be the easier lever for latency or cost), "How to prompt engineer" (delegates everything to
page 2, which it calls "the living reference"), and "Prompt engineering tutorial" (two external
interactive tutorials). The classic ordered technique list has moved off this URL entirely. The
page never uses the term "context engineering", which is a verifiable absence worth recording
given that P2 cites this page.

**What page 2 contains**

The page names its audience models (Fable 5, Mythos 5, Opus 5, Opus 4.8, 4.7, 4.6, Sonnet 5,
Sonnet 4.6, Haiku 4.5) and organizes into model-specific guidance, techniques for all current
models, and migration considerations. Four model-specific sections (Fable 5, Sonnet 5, Opus 5,
Opus 4.8) are stubs that delegate to dedicated pages.

General principles: be clear and direct (the "brilliant but new employee" frame, and the golden
rule that a colleague with minimal context who would be confused signals a prompt Claude will
also find confusing); add context by explaining why an instruction matters, not just the
instruction; use examples effectively, named as few-shot or multishot, with 3 to 5 recommended
and an `<example>` / `<examples>` tag convention; structure prompts with XML tags, consistent
and descriptive, nested where content has natural hierarchy; give Claude a role via the system
prompt; long-context prompting for 20k+ token inputs, putting longform data at the top above
the query, with a reported quality gain of up to 30% from query-at-end, `<document>` /
`<document_content>` / `<source>` wrapping, and a ground-in-quotes-first pattern; model
self-knowledge; communication style and verbosity; format control (say what to do rather than
what not to do, XML format-indicator tags, match prompt style to desired output style, and a
detailed anti-markdown block); LaTeX output; and document creation.

Mechanism changes worth carrying:

- **Prefill deprecation.** Prefill on the last assistant turn is unsupported starting with
  Claude 4.6 models and Mythos Preview, returning a 400 error. Prefill on earlier turns and on
  pre-4.6 models is unaffected. Five migration sub-sections cover the former use cases: output
  formatting (move to Structured Outputs, or just ask, or tools plus enum for classification),
  eliminating preambles, avoiding bad refusals, continuations, and context hydration and role
  consistency (inject reminders in the user turn; for agentic systems hydrate via tools or
  during compaction).
- **Adaptive thinking replaces `budget_tokens`.** `thinking: {type: "adaptive"}` on Claude 4.6+
  and Mythos Preview lets the model decide when and how much to think, driven by `effort` and
  query complexity. A per-model default table follows: Opus 4.6 through 4.8 and Sonnet 4.6
  default off unless set; Opus 5 and Sonnet 5 default on, with Opus 5 disable-able only at
  effort <= high; Fable 5 and Mythos 5 are always on. Manual `budget_tokens` extended thinking
  is deprecated, still functional on Opus 4.6 and Sonnet 4.6 but returning a 400 error on
  Claude 4.7+. A migration code sample spans nine languages. Manual `<thinking>` / `<answer>`
  chain-of-thought is explicitly demoted to a fallback for when thinking is off.
- **The Opus 5 self-check reversal.** The page states as general good practice that you should
  ask Claude to self-check its work against test criteria, then immediately reverses it in the
  same paragraph: Opus 5 already self-verifies, and the old verification instructions should be
  **removed rather than rewritten**, because keeping them causes over-verification with a real
  token and latency cost. This is the sharpest instance of a pattern running through the whole
  page, where general advice is reversed for specific model generations. A related note flags
  Opus 4.5 as over-sensitive to the literal word "think" when thinking is disabled,
  recommending synonyms such as consider, evaluate, or reason through.

Agentic-systems content: context awareness is named as a capability present in Sonnet 5, Sonnet
4.6, Sonnet 4.5, and Haiku 4.5 (the list does not name Opus models), letting the model track
its remaining token budget, and the page recommends telling Claude explicitly that compaction
or external file saving is available in the harness or it may wrap up work prematurely near the
limit. Multi-window workflows get six numbered practices: a different first-window prompt that
sets up scaffolding versus later windows that iterate a todo list; a structured test file such
as `tests.json` with an explicit never-remove-or-edit-tests instruction; setup scripts such as
`init.sh` to avoid repeated rediscovery; preferring fresh context plus filesystem rediscovery
over compaction in some cases, with a prescriptive bootstrap; providing verification tools for
autonomous correctness checking; and an explicit "use your entire context budget, do not stop
early" instruction. State management recommends JSON for state data, freeform text for progress
notes, and git itself as a checkpoint log. Further sections cover balancing autonomy and safety
(confirm before destructive, hard-to-reverse, or externally visible actions, with an explicit
anti-shortcut clause against `--no-verify`), research methodology (define success criteria,
cross-source verification, structured hypothesis tracking with confidence levels), subagent
orchestration (latest models delegate proactively; Opus 4.6 has a strong predilection for
spawning subagents where a direct grep would be faster, and Opus 5 also delegates more readily,
so a damping prompt is given), and prompt chaining, notably short because adaptive thinking and
subagent orchestration now absorb most multistep reasoning.

Coding-specific tips: tool usage needs explicit direction to act, since "can you suggest
changes" may only get suggestions, and aggressive urgency language now risks over-triggering;
parallel tool calling is on by default and steerable in both directions; overthinking and
excessive thoroughness on Opus 4.6; reduced file creation; overeagerness and overengineering on
Opus 4.5 and 4.6; avoiding test hardcoding and helper-script workarounds; minimizing
hallucinations by requiring files be read before answering; vision improvements with a
crop-tool recommendation; and frontend design, with a detailed aesthetics block that names
specific cliches to avoid.

**Why it matters here**

This pair is the current first-party technique reference, and its prefill deprecation, adaptive
thinking migration, and per-model reversals are exactly the kind of drift that this repo's
instruction surfaces must be re-checked against; the Opus 5 self-check reversal is a concrete
worked case of an instruction that should be deleted rather than rewritten.

**Where the deep apparatus lives**

`design/critical-apparatus.md`.
