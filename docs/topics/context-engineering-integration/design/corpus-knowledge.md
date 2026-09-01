# Context-engineering corpus knowledge

The durable record of the two-article context-engineering corpus this repo ingested on
2026-08-31 and 2026-09-01: what the sources say, in their own words where the wording is
load-bearing; the facts that exist only in their figures; the upstream facts the run settled
against current documentation; the custody findings about the sources themselves; and an honest
accounting of what was verified and what was not.

The ingestion produced byte-verified digest slices, a fresh unbiased sweep, and reconciliation
tables in the session's memory tier, which is gitignored and does not survive the container.
This file is the graduation of that work: it inlines the substance rather than pointing at
artifacts a future reader cannot open. Where an in-session artifact is named below, it is named
only to record how a fact was produced, never as a path to follow.

Companion documents in this repo: `docs/topics/context-engineering-integration/PLAN.md` (the
signed-off decision contract this corpus fed) and `docs/topics/context-engineering-claude-5/`
(the earlier plan built on P1 alone, which never engaged P2).

## Contents

- [1. What the corpus is](#1-what-the-corpus-is)
- [2. P1: the new rules of context engineering](#2-p1-the-new-rules-of-context-engineering)
- [3. P2: effective context engineering for AI agents](#3-p2-effective-context-engineering-for-ai-agents)
- [4. Figure-borne facts](#4-figure-borne-facts)
- [5. Settled upstream facts](#5-settled-upstream-facts)
- [6. Custody findings (CF-1 to CF-7)](#6-custody-findings-cf-1-to-cf-7)
- [7. Coverage accounting and residue](#7-coverage-accounting-and-residue)

## 1. What the corpus is

### Primary sources

**P1. "The new rules of context engineering for Claude 5 models"**
Thariq (Thariq Shihipar, `@trq212`), member of technical staff at Anthropic, published as a
personal X Article on 2026-07-24.
<https://x.com/trq212/article/2080710971228918066> (status form:
<https://x.com/trq212/status/2080710971228918066>).
Blog twin, the same content on a first-party surface, carrying the 80% figure in its page
description: <https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models>.
Venue matters: this is a personal post by an Anthropic employee, not an Anthropic docs
property. Five digest units over a 119-line markdown channel; four body figures plus a cover,
recoverable only from the fxtwitter JSON channel.

**P2. "Effective context engineering for AI agents"**
Anthropic Applied AI team: Prithvi Rajasekaran, Ethan Dixon, Carly Ryan, and Jeremy Hadfield,
with contributions from Rafi Ayub, Hannah Moran, Cal Rueb, and Connor Jennings; support from
Molly Vorwerck, Stuart Ritchie, and Maggie Vo. Published 2025-09-29 (recovered from the
rendered metadata in the retained HTML snapshot; the markdown channel carries no date).
<https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>.
Six digest units over a 75-line markdown channel; two content figures that survive only as
image URLs in the HTML. P1 links this post as its definition of "context engineering"; P2
predates it by ten months.

### The nine linked first-party pages

| # | URL | Role |
|---|---|---|
| T1 | <https://x.com/trq212/status/2073100352921215386> | X-native surface of the Fable field guide, 2026-07-03; the same essay as T2, one content node |
| T2 | <https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns> | "A Field Guide to Fable: Finding Your Unknowns", 2026-07-06 (modified 2026-08-03); the designated deep dive on prompting the Claude 5 generation, and the piece P1 hands off to |
| T3 | <https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code> | "A harness for every task: dynamic workflows", 2026-06-02 (Shihipar, Bidasaria); the mechanism behind P1's rubrics and verifier-agents claim, and the target of P1's tree-of-files link |
| T4 | <https://www.anthropic.com/engineering/writing-tools-for-agents> | "Writing effective tools for agents", 2025-09-11 (Ken Aizawa); the tool-design guidance P2's anatomy section leans on |
| T5 | <https://www.anthropic.com/research/building-effective-agents> | "Building effective agents", nominally 2024-12-19; P2's workflow-versus-agent definition source, and a silently revised page (see CF-1) |
| T6 | <https://www.anthropic.com/engineering/multi-agent-research-system> | "How we built our multi-agent research system", 2025-06-13; the evidence base for sub-agent architecture, including the token-economics numbers |
| T7 | <https://www.anthropic.com/news/context-management> | Context-management product announcement, Sonnet 4.5 launch window; the product surface behind P2's compaction and memory-tool claims |
| T8 | <https://platform.claude.com/cookbook/tool-use-memory-cookbook> | Memory cookbook, 2025-05-22 (Alex Notov); the hands-on cookbook P2 closes with, now struck as a model-list authority (see CF-5) |
| T9 | <https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/overview> | Prompt-engineering overview plus its "Prompting best practices" page; the docs P2 positions itself against, and the carrier of a documented generational reversal (see CF-6) |

### Corpus timeline

| Date | Item |
|---|---|
| 2024-12-19 (nominal) | T5 "Building effective agents"; the live page has been silently revised since |
| 2025-05-22 | T8 memory cookbook |
| 2025-06-13 | T6 multi-agent research system |
| 2025-09-11 | T4 writing effective tools for agents |
| 2025-09-29 | **P2** "Effective context engineering for AI agents" |
| Sonnet 4.5 launch window | T7 context-management announcement |
| 2026-06-02 | T3 dynamic workflows |
| 2026-07-03 and 2026-07-06 | T1 and T2, two surfaces of the Fable field guide |
| 2026-07-24 | **P1** "The new rules of context engineering for Claude 5 models" |
| undated, living | T9 prompt-engineering overview and best-practices pages |

## 2. P1: the new rules of context engineering

Quotes below are byte-exact from the P1 markdown channel as verified in-session by two
independent arms plus a scripted fence gate. Curly quotes, doubled spaces, and comma placement
inside backticks are reproduced from the source, not typos introduced here.

### 2.1 The framing: prompt versus assembled context

Context engineering is defined by enumerating the surfaces that assemble it, and separated from
prompting by a generality premise: a prompt is written for one request, context is amortized
across many and must be written without knowing the request.

```
But when you send a message to Claude, the prompt is only a small part of the context it gets. Much of your context is assembled from your system prompt, Skills, CLAUDE.md files, memory, and other sources. We call this context engineering, and it makes a big impact on the results you generate when using Claude Code or in building your own agents.
```

```
Unlike a prompt, context is used generally across many requests, so it cannot be as specific.  How do you build these general prompts and guidance for Claude, especially when you don’t know what a user’s prompt might be?
```

The headline empirical claim, and the only number in the article's body text:

```
This can be surprisingly difficult as Claude’s own capabilities evolve. Most recently, we noticed a large jump in the way we prompt the newest generation of Claude models. We removed over 80% of Claude Code’s system prompt for models like Claude Opus 5 and Claude Fable 5 with no measurable loss on our coding evaluations.
```

Read the scope literally: no measurable loss on that team's coding evaluations, for Claude
5-generation models. Section 5 records what official surfaces do and do not corroborate.

The tooling handoff, stated twice in the article:

```
Here’s what we’ve learned about prompting this new class of models, and how you can utilize it to update your context engineering. We’ve put these best practices in `claude doctor`, use the command /doctor in Claude Code to rightsize your skills, and CLAUDE.md files.
```

### 2.2 Unhobbling: over-constraint as a joint product of surfaces

The diagnosis names three surfaces at once, and the evidence offered is transcript reading of
Anthropic's own internal use.

```
Overall, we found that we were over-constraining Claude Code, both through our system prompt and in our CLAUDE.md files and skills.
```

```
For example, when we read transcripts of our own internal usage of Claude Code, we see several conflicting messages in a single request like “leave documentation as appropriate,” or “DO NOT add comments” as our system prompt, skills, and user requests clash with each other.
```

The cost is not a wrong answer, it is deliberation spent reconciling:

```
Generally, Claude can interpret the user’s intent to get to the right answer, but Claude must think more carefully about these overlapping and conflicting messages before deciding what to do.
```

```
And while these constraints were once needed to avoid worst case scenarios, we have since found we can delete many of them and let the model use surrounding context and judgement instead.
```

CLAUDE.md's role narrows because other surfaces now exist:

```
Additionally, Claude Code now has many more tools. Claude used to rely on CLAUDE.md as a source of memory, information, and guidance. Now we have memory, artifacts, and skills, which Claude can use to create new ways of loading and sharing context across sessions.
```

The load-bearing thesis the article never states, flagged in the fresh pass as a true gap: its
logic only coheres if constraining the *interface* (an enum, a one-line behavioral rule) is good
while constraining the *behavior space* (worked examples, categorical prohibitions) is bad. An
enum is a harder constraint than an example, so "less constraint" is not the actual principle.

### 2.3 The six then to now reversals

The section premise:

```
There were a number of previous context engineering best practices that had become myths.
```

The six pairs, as rendered in the strikethrough table figure: Give Claude Rules to Give Claude
Judgement; Give Claude Examples to Design Interfaces; Put it all upfront to Use Progressive
Disclosure; Repeat Yourself to Simple Tool Descriptions; Memory in Claude.MDs to Auto-memory;
Simple Specs to Rich References.

**1. Rules to judgement.** Early Claude Code shipped strong, sometimes-wrong rules to avoid
worst cases such as deleting files.

```
When we first rolled out Claude Code, we needed to be sure that Claude avoided worst case scenarios, such as deleting files. This meant we would give particularly strong guidance that might not always be true,
```

```
Still, without these guardrails for older models, the comments Claude wrote would be incorrect in many cases and we had to accept this tradeoff. But newer models have better judgement and can handle these decisions well without explicit rules.
```

The worked pair, both quoted from Claude Code's system prompt. Old:

```
In code: default to writing no comments. Never write multi-paragraph docstrings or multi-line comment blocks — one short line max. Don't create planning, decision, or analysis documents unless the user asks for them — work from conversation context, not intermediate files.
```

New:

```
Write code that reads like the surrounding code: match its comment density, naming, and idiom.
```

**2. Examples to interface design.**

```
The number one rule for tool usage was to give Claude examples on how to use them. With our newest models, we’ve found that giving examples actually constrains them to a certain exploration space.
```

```
Instead of using examples, think more about the design of your tools, scripts and files- what parameters does Claude have and how can they be more expressive?
```

```
For example, in the Todo tool example, just listing status as an enumeration between pending, in_progress, and completed, hints to Claude about how to use it. The instruction on keeping one item in_progress helps define our requested behavior.
```

**3. Upfront to progressive disclosure.**

```
Since then, Claude Code has gotten very competent at using progressive disclosure- loading the right context at the right times. For example, we moved verification and code review into their own skills that Claude Code could selectively call.
```

```
But progressive disclosure is not just for skills, we also use it for tools. Some of our tools are ‘deferred loading,’ which means the agent must search for their full definitions using ToolSearch before using them. This allows us to have more tools (such as our Task tools) that don’t take up context until they’re needed.
```

```
The same can be applied to your own CLAUDE.md and Skill.md files. A common myth is that you want to make these a central repository for every known practice that you *might* run into, because Claude would not find it otherwise. Instead, consider having a tree of files that can be loaded at the right time.
```

**4. Repetition to simple tool descriptions.**

```
Earlier Claude models could sometimes need repeated instructions or be more likely to listen to instructions at the end of their context window than at the start. This meant our system prompt would sometimes have references to tools in the main system prompt as well as instructions in the tool description.
```

```
We found we could delete these repeat examples and put instructions on how to use tools in the tool descriptions rather than the system prompt.
```

Note what "simple tool descriptions" actually means in practice: consolidation into a single
richer description surface, not a smaller total. The after panel of the TodoWrite figure still
carries a behavioral rule.

**5. CLAUDE.md memory to auto-memory.**

```
We used to encourage users to save things to Claude’s memory, by using the # hotkey to write to their CLAUDE.md automatically. Instead, Claude now automatically saves memories that are relevant to the work and to you.
```

The source says "Instead", which supersedes the encouragement rather than announcing a removal.
Upstream has since removed the hotkey outright; see section 5.

**6. Simple specs to rich references.**

```
But we’ve found that Claude can handle increasingly more complicated references. Instead of simple markdown files, Claude can reference HTML artifacts created by our new artifacts feature.
```

```
You may also give Claude references in the form of code. A spec may also be a detailed test suite, or a function in a different codebase that Claude might port.
```

```
Rubrics are another form of references. Rubrics allow Claude to try and verify your taste in a particular field (e.g. what does a good API design look like) by using dynamic workflows and spinning up verifier agents with those rubrics.
```

### 2.4 Per-surface placement guidance

The article's placement section walks four surfaces. In the source each heading runs into its
body across a line break, so the quoted lines below literally begin with two asterisks.

**System prompt.**

```
**A system prompt is heavily tied to the product context. It tells Claude what product it’s operating in and what it’s doing. For Claude Code, you will likely never modify this, but if you are building your own agent harness, this is where you should spend a lot of time.
```

**CLAUDE.md.**

```
**Keep your CLAUDE.md lightweight and briefly describe what your repo is for, but spend most of the tokens on gotchas inside of the codebase. For example, you may organize your code to keep types in one monolithic file and nowhere else. Avoid stating ‘the obvious’ things Claude should know by looking at your file system or your repo.
```

```
Use progressive disclosure for more details, for example if you have several unique instructions on how to verify your work, create a verification skill and reference it from your CLAUDE.md.
```

"Lightweight" and "spend most of the tokens" pull against each other on the page. The resolution
the reconciliation settled on is composition, not weight: derivable content out, tribal
knowledge in.

**Skills.**

```
**Think of skills as lightweight guides to let Claude find information when needed. Avoid making them overconstrained, except in highly important areas.
```

```
For long skills, try and use progressive disclosure as much as possible- divide it into many files and split them out.
```

```
It’s best when skills encode particular opinions, knowledge, or best practices that are particular to you, your team, or product.
```

The carve-out, "except in highly important areas", is undefined in the source and is the
calibration knob everything downstream turns on: it is what separates a legacy worst-case
guardrail (delete) from a genuine team convention (keep).

**References.**

```
**You can @ mention files to include them as references. References allow Claude to refer to in-depth information about the current plan.
```

```
This might be in specs files, mockups, or even entire codebases. Generally you should prefer files that are in code as it provides clear, high-fidelity instructions to Claude in a language it knows very well. For example, a HTML mockup of a design will generally produce better results than a description of the design or a screenshot.
```

### 2.5 The close

```
Across your system prompt, skills, and CLAUDE.md files, you may need to simplify just like we did.
```

```
We rolled out a new command called `claude doctor,` which will help you do this automatically as well.
```

```
For more details on prompting more advanced models specifically, check out our Fable field guide.
```

The comma inside the backticks is in the source. The "Fable field guide" anchor links to T2.

### 2.6 Unstated preconditions the article inherits

Recorded because any guidance derived from P1 inherits them silently.

- "Match the surrounding code" presumes a coherent surrounding idiom. In a legacy or multi-team
  codebase the rule points at noise.
- "Design your interfaces" presumes you own the interfaces. A reader consuming third-party MCP
  servers or vendored tools cannot discharge it.
- Code-form references (test-suite specs, HTML mockups) presume authoring capacity a reader may
  not have, leaving prose as the only spec they can produce.
- "No measurable loss" presumes an eval harness. Most readers have none, so the article's own
  evidence standard is unavailable to them, and it offers no failure signal and no rollback
  criterion for a deletion that goes too far.
- Security is absent. Deleting guardrails routes decisions through "surrounding context and
  judgement", which makes malicious surrounding context an input to judgment, and the one named
  worst case (file deletion) is never re-secured.
- Shared-surface governance is absent. The article's "you" is singular, while CLAUDE.md and
  skills are team artifacts, and conflicting teammate preferences are exactly the conflict class
  the article opens with.

## 3. P2: effective context engineering for AI agents

### 3.1 Definitions

```
Context refers to the set of tokens included when sampling from a large-language model (LLM).
```

```
The engineering problem at hand is optimizing the utility of those tokens against the inherent constraints of LLMs in order to consistently achieve a desired outcome.
```

```
Effectively wrangling LLMs often requires thinking in context — in other words: considering the holistic state available to the LLM at any given time and what potential behaviors that state might yield.
```

The dual definition that separates the two disciplines:

```
Prompt engineering refers to methods for writing and organizing LLM instructions for optimal outcomes (see our docs for an overview and useful prompt engineering strategies). Context engineering refers to the set of strategies for curating and maintaining the optimal set of tokens (information) during LLM inference, including all the other information that may land there outside of the prompts.
```

The enumerated context state, usable as a coverage checklist:

```
However, as we move towards engineering more capable agents that operate over multiple turns of inference and longer time horizons, we need strategies for managing the entire context state (system instructions, tools, Model Context Protocol (MCP), external data, message history, etc).
```

Why it is a loop rather than an authoring task:

```
An agent running in a loop generates more and more data that could be relevant for the next turn of inference, and this information must be cyclically refined. Context engineering is the art and science of curating what will go into the limited context window from that constantly evolving universe of possible information.
```

```
In contrast to the discrete task of writing a prompt, context engineering is iterative and the curation phase happens each time we decide what to pass to the model.
```

The coinage of the term is credited to Karpathy and the agent definition to Simon Willison, but
both credits exist only as link anchors rather than named attributions in the text (CF-3).

### 3.2 The attention budget and context rot: the mechanism

This is the post's load-bearing model and the reason every other technique in it exists.

```
Studies on needle-in-a-haystack style benchmarking have uncovered the concept of context rot: as the number of tokens in the context window increases, the model’s ability to accurately recall information from that context decreases.
```

```
While some models exhibit more gentle degradation than others, this characteristic emerges across all models.
```

```
Context, therefore, must be treated as a finite resource with diminishing marginal returns.
```

```
Like humans, who have limited working memory capacity, LLMs have an “attention budget” that they draw on when parsing large volumes of context. Every new token introduced depletes this budget by some amount, increasing the need to carefully curate the tokens available to the LLM.
```

The stated causes, in the post's order: architecture, training distribution, and the cost of the
usual mitigation.

```
This attention scarcity stems from architectural constraints of LLMs. LLMs are based on the transformer architecture, which enables every token to attend to every other token across the entire context. This results in n² pairwise relationships for n tokens.
```

```
Additionally, models develop their attention patterns from training data distributions where shorter sequences are typically more common than longer ones. This means models have less experience with, and fewer specialized parameters for, context-wide dependencies.
```

```
Techniques like position encoding interpolation allow models to handle longer sequences by adapting them to the originally trained smaller context, though with some degradation in token position understanding.
```

The shape of the resulting failure, which is the operationally important part:

```
These factors create a performance gradient rather than a hard cliff: models remain highly capable at longer contexts but may show reduced precision for information retrieval and long-range reasoning compared to their performance on shorter contexts.
```

A gradient means every token costs some recall precision well below the window limit, and the
failure is silent: missed instructions and forgotten constraints, not an overflow error.

One dissent is recorded from the fresh pass and left unresolved: the n² paragraph describes the
mechanism by which every pair *is* attended, so the causal work in this chain is actually done
by the softer training-distribution and position-encoding claims, and dense attention is
assumed rather than argued. Cite the section as a mechanism sketch, not as a proof.

### 3.3 The guiding principle and altitude calibration

```
Given that LLMs are constrained by a finite attention budget, good context engineering means finding the smallest possible set of high-signal tokens that maximize the likelihood of some desired outcome.
```

Restated in the conclusion as the portable takeaway:

```
the guiding principle remains the same: find the smallest set of high-signal tokens that maximize the likelihood of your desired outcome.
```

Altitude, defined by its two failure modes, is how that principle gets applied to a system
prompt:

```
System prompts should be extremely clear and use simple, direct language that presents ideas at the right altitude for the agent. The right altitude is the Goldilocks zone between two common failure modes. At one extreme, we see engineers hardcoding complex, brittle logic in their prompts to elicit exact agentic behavior. This approach creates fragility and increases maintenance complexity over time. At the other extreme, engineers sometimes provide vague, high-level guidance that fails to give the LLM concrete signals for desired outputs or falsely assumes shared context. The optimal altitude strikes a balance: specific enough to guide behavior effectively, yet flexible enough to provide the model with strong heuristics to guide behavior.
```

An altitude review therefore cuts in both directions: brittle if-else branching is a defect, and
so is mechanism-free vagueness.

Structure advice, with the hedge that must travel with it:

```
We recommend organizing prompts into distinct sections (like <background_information>, <instructions>, ## Tool guidance, ## Output description, etc) and using techniques like XML tagging or Markdown headers to delineate these sections, although the exact formatting of prompts is likely becoming less important as models become more capable.
```

```
Regardless of how you decide to structure your system prompt, you should be striving for the minimal set of information that fully outlines your expected behavior. (Note that minimal does not necessarily mean short; you still need to give the agent sufficient information up front to ensure it adheres to the desired behavior.)
```

```
It’s best to start by testing a minimal prompt with the best model available to see how it performs on your task, and then add clear instructions and examples to improve performance based on failure modes found during initial testing.
```

Minimal is a signal-density target, not a length cap, and the iteration loop is minimal first,
then additions driven by observed failures rather than by speculation.

### 3.4 Tools and examples

```
Because tools define the contract between agents and their information/action space, it’s extremely important that tools promote efficiency, both by returning information that is token efficient and by encouraging efficient agent behaviors.
```

```
One of the most common failure modes we see is bloated tool sets that cover too much functionality or lead to ambiguous decision points about which tool to use. If a human engineer can’t definitively say which tool should be used in a given situation, an AI agent can’t be expected to do better.
```

The few-shot paragraph, which is the exact claim P1 later reverses for Claude 5 models:

```
Providing examples, otherwise known as few-shot prompting, is a well known best practice that we continue to strongly advise. However, teams will often stuff a laundry list of edge cases into a prompt in an attempt to articulate every possible rule the LLM should follow for a particular task. We do not recommend this. Instead, we recommend working to curate a set of diverse, canonical examples that effectively portray the expected behavior of the agent. For an LLM, examples are the “pictures” worth a thousand words.
```

Closing guidance across all components:

```
Our overall guidance across the different components of context (system prompts, tools, examples, message history, etc) is to be thoughtful and keep your context informative, yet tight.
```

### 3.5 Just-in-time retrieval and metadata as signal

```
Since we wrote that post, we’ve gravitated towards a simple definition for agents: LLMs autonomously using tools in a loop.
```

```
Rather than pre-processing all relevant data up front, agents built with the “just in time” approach maintain lightweight identifiers (file paths, stored queries, web links, etc.) and use these references to dynamically load data into context at runtime using tools. Anthropic’s agentic coding solution Claude Code uses this approach to perform complex data analysis over large databases. The model can write targeted queries, store results, and leverage Bash commands like head and tail to analyze large volumes of data without ever loading the full data objects into context. This approach mirrors human cognition: we generally don’t memorize entire corpuses of information, but rather introduce external organization and indexing systems like file systems, inboxes, and bookmarks to retrieve relevant information on demand.
```

The post says teams are *augmenting* embedding-based retrieval with just-in-time strategies, not
replacing it. Both the slice summary and its index shaded that into replacement and the
reconciliation flagged it, so do not cite this post as taking an anti-embeddings position.

Metadata is itself a behavioral signal, which makes tree hygiene a form of context engineering:

```
Beyond storage efficiency, the metadata of these references provides a mechanism to efficiently refine behavior, whether explicitly provided or intuitive. To an agent operating in a file system, the presence of a file named test_utils.py in a tests folder implies a different purpose than a file with the same name located in src/core_logic/ Folder hierarchies, naming conventions, and timestamps all provide important signals that help both humans and agents understand how and when to utilize information.
```

```
Letting agents navigate and retrieve data autonomously also enables progressive disclosure—in other words, allows agents to incrementally discover relevant context through exploration. Each interaction yields context that informs the next decision: file sizes suggest complexity; naming conventions hint at purpose; timestamps can be a proxy for relevance. Agents can assemble understanding layer by layer, maintaining only what's necessary in working memory and leveraging note-taking strategies for additional persistence.
```

The trade-off is stated plainly, and so is the hybrid default:

```
Of course, there's a trade-off: runtime exploration is slower than retrieving pre-computed data. Not only that, but opinionated and thoughtful engineering is required to ensure that an LLM has the right tools and heuristics for effectively navigating its information landscape. Without proper guidance, an agent can waste context by misusing tools, chasing dead-ends, or failing to identify key information.
```

```
In certain settings, the most effective agents might employ a hybrid strategy, retrieving some data up front for speed, and pursuing further autonomous exploration at its discretion. The decision boundary for the ‘right’ level of autonomy depends on the task. Claude Code is an agent that employs this hybrid model: CLAUDE.md files are naively dropped into context up front, while primitives like glob and grep allow it to navigate its environment and retrieve files just-in-time, effectively bypassing the issues of stale indexing and complex syntax trees.
```

```
Given the rapid pace of progress in the field, "do the simplest thing that works" will likely remain our best advice for teams building agents on top of Claude.
```

### 3.6 The long-horizon triad

```
Long-horizon tasks require agents to maintain coherence, context, and goal-directed behavior over sequences of actions where the token count exceeds the LLM’s context window.
```

```
To enable agents to work effectively across extended time horizons, we've developed a few techniques that address these context pollution constraints directly: compaction, structured note-taking, and multi-agent architectures.
```

Waiting for bigger windows is explicitly not the answer: the post argues that windows of all
sizes stay subject to context pollution and relevance concerns wherever the strongest
performance is wanted. Note that "context pollution" is used as a term of art and never defined.

**Compaction.**

```
Compaction is the practice of taking a conversation nearing the context window limit, summarizing its contents, and reinitiating a new context window with the summary. Compaction typically serves as the first lever in context engineering to drive better long-term coherence.
```

```
In Claude Code, for example, we implement this by passing the message history to the model to summarize and compress the most critical details. The model preserves architectural decisions, unresolved bugs, and implementation details while discarding redundant tool outputs or messages. The agent can then continue with this compressed context plus the five most recently accessed files. Users get continuity without worrying about context window limitations.
```

```
For engineers implementing compaction systems, we recommend carefully tuning your prompt on  complex agent traces. Start by maximizing recall to ensure your compaction prompt captures every relevant piece of information from the trace, then iterate to improve precision by eliminating superfluous content.
```

```
An example of low-hanging superfluous content is clearing tool calls and results – once a tool has been called deep in the message history, why would the agent need to see the raw result again? One of the safest lightest touch forms of compaction is tool result clearing, most recently launched as a feature on the Claude Developer Platform.
```

The post's own caveat sits right next to its confidence, and any compaction guidance that drops
it inherits the technique without its central risk. Paraphrased from the source's two adjacent
sentences: compaction is described as distilling the window in a high-fidelity manner with
minimal performance degradation, and then, immediately after, as an art of selecting what to
keep versus what to discard, because overly aggressive compaction loses subtle but critical
context whose importance only becomes apparent later.

**Structured note-taking.**

```
Structured note-taking, or agentic memory, is a technique where the agent regularly writes notes persisted to memory outside of the context window. These notes get pulled back into the context window at later times.
This strategy provides persistent memory with minimal overhead. Like Claude Code creating a to-do list, or your custom agent maintaining a NOTES.md file, this simple pattern allows the agent to track progress across complex tasks, maintaining critical context and dependencies that would otherwise be lost across dozens of tool calls.
```

The evidence is Claude playing Pokémon, which matters because it is a non-coding domain and
because the structure was not imposed:

```
Claude playing Pokémon demonstrates how memory transforms agent capabilities in non-coding domains. The agent maintains precise tallies across thousands of game steps—tracking objectives like "for the last 1,234 steps I've been training my Pokémon in Route 1, Pikachu has gained 8 levels toward the target of 10." Without any prompting about memory structure, it develops maps of explored regions, remembers which key achievements it has unlocked, and maintains strategic notes of combat strategies that help it learn which attacks work best against different opponents.
```

The design test that follows is reset survival: the value appears when the agent reads its own
notes after a context reset and continues.

```
As part of our Sonnet 4.5 launch, we released a memory tool in public beta on the Claude Developer Platform that makes it easier to store and consult information outside the context window through a file-based system. This allows agents to build up knowledge bases over time, maintain project state across sessions, and reference previous work without keeping everything in context.
```

That sentence is time-scoped to late September 2025. Section 5 records the current status.

**Sub-agents.**

```
Sub-agent architectures provide another way around context limitations. Rather than one agent attempting to maintain state across an entire project, specialized sub-agents can handle focused tasks with clean context windows. The main agent coordinates with a high-level plan while subagents perform deep technical work or use tools to find relevant information. Each subagent might explore extensively, using tens of thousands of tokens or more, but returns only a condensed, distilled summary of its work (often 1,000-2,000 tokens).
```

```
This approach achieves a clear separation of concerns—the detailed search context remains isolated within sub-agents, while the lead agent focuses on synthesizing and analyzing the results. This pattern, discussed in How we built our multi-agent research system, showed a substantial improvement over single-agent systems on complex research tasks.
```

The 1,000 to 2,000 token condensed return is the concrete fan-out contract in this corpus: wide
exploration allowed, narrow return required. What the post does not carry is the cost side. T6
supplies it (roughly 4x chat token usage per agent, roughly 15x for multi-agent systems, with
token usage explaining most of the eval variance), and T3's megatoken cost figures corroborate.
Cite T6 whenever the fan-out contract is adopted.

**Choosing between the three.**

```
The choice between these approaches depends on task characteristics. For example:
- Compaction maintains conversational flow for tasks requiring extensive back-and-forth;
- Note-taking excels for iterative development with clear milestones;
- Multi-agent architectures handle complex research and analysis where parallel exploration pays dividends.
```

### 3.7 Self-obsolescence

The post hedges its own durability, and P1 is the operationalization of that hedge.

```
The techniques we've outlined will continue evolving as models improve.
```

```
We're already seeing that smarter models require less prescriptive engineering, allowing agents to operate with more autonomy.
```

```
But even as capabilities scale, treating context as a precious, finite resource will remain central to building reliable, effective agents.
```

The durable layer is therefore the principle (smallest set of high-signal tokens, context as a
finite resource); the technique layer is expected to relax, and did, one generation later.

### 3.8 The generational reversal, stated plainly

P2 says few-shot examples remain strongly advised, with a caution against edge-case laundry
lists. P1, ten months later and for the Claude 5 generation, says examples constrain the model
to a certain exploration space and should be replaced by interface design. Same publisher
lineage, deliberate reversal, and the clearest instance of the corpus's own advice-shelf-life
theme. Where the two conflict for Claude 5-generation targets, P1 governs on technique and P2
remains the principles layer. Note also that the reversal is not total: P2's own objection is to
edge-case enumeration, which is closer to P1's position than the headline pairing suggests.

## 4. Figure-borne facts

These facts exist in no text anywhere: not in the markdown channel, not in the HTML, not in the
alt text. They are readable only by opening the figures. A text-only ingestion of this corpus
loses them, which is why CF-2 treats figure-only evidence as systemic rather than incidental.

**The TodoWrite before-size (P1, figure 3).** The before panel labels the old TodoWrite tool
description as approximately 9,100 characters of when-to-use lists and worked examples. The
after panel shows a short description beginning "Create and update a task list for the current
session…", a status field rendered as the three enum values pending / in_progress / completed,
and the callout "only one task in_progress at a time". This is the article's only quantification
of what interface design replaces, and the body text carries no number at all. Always attribute
it to the figure.

**The six-layer context stack (P1, figure 4).** Six stacked boxes, top to bottom: "Your prompt"
(highlighted), "References" (subtitled "@-mentioned files, specs, mockups, codebases,
artifacts"), "System prompt", "Claude.MDs", "Skills", "Memory". Two things follow. First, Memory
appears as a sixth surface that the body's per-surface section never covers, so the stack is a
wider taxonomy than the prose. Second, the figure visually subordinates the system prompt, which
the body calls the highest-investment surface for harness builders, a tension worth knowing
before reproducing the diagram.

**The prompt-versus-context curation loop (P2, figure 1).** The left panel shows prompt
engineering for single-turn queries: a context window holding a system prompt and a user
message, run through the model to produce one assistant message. The right panel shows context
engineering for agents: a larger pool of possible context (docs, tools, a memory file,
comprehensive instructions, domain knowledge, message history) passes through an explicit
"Curation" step into the context window each turn, the model emits an assistant message or a
tool call, and the tool call's result flows back into the message history pool for the next
cycle. The figure is the visual counterpart of the cyclical-refinement and per-turn-curation
claims. The fresh pass read it as additionally asserting lossiness, since the candidate pool
holds visibly more items than the window, meaning most candidate context should not enter.

**The three calibration prompts (P2, figure 2, "Calibrating the system prompt").** A horizontal
gradient bar, red at both ends and green in the centre, labeled "Too specific", "Just right",
"Too vague", with three prompt cards beneath. These are the post's only complete worked system
prompts, its centerpiece pedagogy, and they exist purely as pixels: the HTML carries only alt
text and a CDN URL.

- *Too specific* is a numbered procedure for a bakery support agent: classify intent into a
  five-value enum, branch per value, then an "exhaustive list" of escalation cases that trails
  off into an ellipsis, a "5/7 of the following requirements" fraction over an elided list, a
  numbered step with no text, and nested ellipses at three levels. The card argues by absurdity
  that enumeration cannot close.
- *Just right* opens by naming the role and scope ("customer support agent for Claude's
  Bakery"), states the tools available and the goal, then gives a four-step response framework
  (identify the core issue, gather necessary context with tools, provide clear resolution,
  confirm satisfaction) and six guidelines: prefer the simplest solution that fully addresses
  the issue, check order status before suggesting next steps, call the human_assistance tool
  when uncertain, call it for legal issues, health and allergy emergencies, and out-of-policy
  financial adjustments, and acknowledge frustration or urgency with appropriate empathy. It is
  the concrete image of "specific enough to guide behavior, flexible enough to leave
  heuristics".
- *Too vague* is a single sentence: solve customer issues "in a manner consistent with the
  principles and essence of the company brand", escalate to a human if needed. It is the
  falsely-assumed-shared-context failure mode made concrete, and its own comma splice reads as
  part of the caricature.

A full verbatim transcription of all three cards was produced in-session by the fresh pass,
independently re-verified against the image by a second reader, with one systematic
normalization (the figure renders curly quotation marks, the transcription uses straight ones),
and merged into the P2 digest slice. That slice lived in the memory tier and is gone. Anyone
needing the exact wording again must re-transcribe from the figure on the live P2 page; the
summaries above are what survives here.

## 5. Settled upstream facts

Verified against current first-party documentation on 2026-09-01. Recency anchor for all of
them: Claude Code changelog v2.1.252, fetched that day.

**The `#` memory hotkey is removed, not merely de-emphasized.** Changelog v2.0.70: "Removed #
shortcut for quick memory entry (tell Claude to edit your CLAUDE.md instead)". It was added in
v0.2.54 and appears in no current memory, commands, or interactive-mode page. P1's "Instead"
posture, written when the mechanism still existed, aged into outright removal within weeks,
which makes it the fastest-aging claim in the corpus. Auto memory is documented and on by
default.

**`/doctor`'s documented behavior, per `commands.md`.** The in-session `/doctor` (alias
`/checkup`) is a full setup checkup that diagnoses issues and can fix them: installation health,
duplicate or leftover installs, PATH problems, settings files it cannot parse, unused skills, MCP servers
and plugins measured against their context cost, slow hooks, and a release-channel version
check. On CLAUDE.md it deduplicates local files against checked-in ones, trims checked-in files
by cutting content Claude could derive from the codebase, and migrates the always-loaded
remainder into skills and nested CLAUDE.md files that load on demand. It reports findings first
and asks for confirmation before changing anything. From the terminal, `claude doctor` prints
read-only installation diagnostics without starting a session. The full checkup arrived in
v2.1.205 and the CLAUDE.md trim check requires v2.1.206 or later. Two scope corrections to P1's
pointer: no official doc uses the word "rightsize", and no doc describes `/doctor` rewriting or
simplifying skill *content*. The skills check is unused-skill detection by context cost, so
"rightsize your skills" overstates what the documented checks do.

**Memory tool and context editing, and what Claude Code exposes.** The memory tool
(`memory_20250818`, client-side) requires no beta header, and current docs state it is available
on all Claude 4 and later models. Context editing is still beta (header
`context-management-2025-06-27`), with strategies `clear_tool_uses_20250919` and
`clear_thinking_20251015`, documented as available on all supported Claude models. Claude Code
the harness exposes neither API mechanism natively: its documented analogues are its own
file-based auto memory and its own client-side compaction (`/compact`, auto-compact). No
code.claude.com page documents `memory_20250818` or `context_management` in the harness. When
citing supported models, use the platform.claude.com memory-tool page and the code.claude.com
context-window page; both of T8's contradictory model lists are stale (CF-5).

**The 80% figure has no official carrier.** No Anthropic docs surface, engineering blog page,
claude.com blog page, or Claude Code changelog entry carries "removed over 80% of Claude Code's
system prompt with no measurable loss". It is vendor-staff voice on a personal channel, plus the
claude.com blog twin of the same article, which carries the figure in its page description.
Simon Willison independently relays the same figure from a Claude Code team conversation, and
all press coverage traces back to the 2026-07-24 article. Directional, non-numeric official
corroboration does exist: changelog v2.1.154, "The lean system prompt is now the default for all
models except Haiku, Sonnet, and Opus 4.7 and earlier". Annotate the claim as OPINION-tier, cite
both carriers, and pair it with v2.1.154 rather than presenting it as a measured result.

## 6. Custody findings (CF-1 to CF-7)

The corpus's findings about its own sources. These are properties of the source material, so
they stay true regardless of what this repo decides to build.

**CF-1. Silent post-publication revision.** T5's live page is revised after publication with no
visible changelog: it now names Haiku 4.5, Sonnet 4.5, and the Agent SDK, none of which existed
at its nominal December 2024 date. Any citation of it must be snapshot-dated, never "the Dec
2024 post".

**CF-2. Figure-only evidence is systemic, not incidental.** Across the corpus the quantitative
core lives in images: P1's approximately 9,100-character TodoWrite before-size and its six-layer
context stack; P2's three worked bakery prompts and its curation feedback loop; T3's entire
workflow API surface (`agent(prompt, {schema, model, isolation, agentType})`, `parallel`,
`pipeline`) plus its megatoken cost data; T4's held-out accuracy numbers (67.4 to 80.1 percent,
79.6 to 85.7 percent) and its error-design pattern; T5's visual grammar distinguishing
programmatic from LLM aggregation. A text-only ingestion of this corpus loses all of it.

**CF-3. Provenance stripping.** P2 credits the coinage of "context engineering" to Karpathy and
its agent definition to Simon Willison only through link anchors. Text extraction drops the
anchors, which silently re-attributes both to Anthropic's voice. Any quotation pipeline reading
the markdown channel alone will misattribute.

**CF-4. Link defects cluster.** The literal text "CLAUDE.md" autolinks to a dead
`http://claude.md` in both primaries, apparently the same CMS behavior. P2 additionally carries
a self-link mislabeled as the Sonnet 4.5 announcement, and scheme-inconsistent http links. None
were repaired in the snapshots; they are recorded as source artifacts.

**CF-5. Cookbook and announcement defects.** T8 carries two contradictory supported-model lists
(five models in one place, two in another) and a log line inconsistent with its own stated
clearing threshold, so it is struck as a model-list authority. T7's evaluation claims (39
percent, 29 percent, 84 percent) name no eval and decompose nothing, and its "beyond any fixed
limit" framing oversells the mechanism: the limit is untouched, the workable length is extended.

**CF-6. The generational reversal is now in official reference docs.** T9's second page
documents stripping self-check guidance entirely for Opus 5, alongside four model-specific
delegate pages. The corpus's advice-shelf-life thesis is therefore not just a blog-versus-blog
phenomenon; it is instantiated in first-party reference documentation, which means "the docs
say" is itself model-generation-scoped.

**CF-7. Venue error in the prior plan.**
`docs/topics/context-engineering-claude-5/design/official-corroboration.md` opens by calling P1
"a post on Anthropic's Claude blog". It is a personal X Article by an Anthropic employee. The
consequence is bounded, since that file's per-claim verdicts already treat unconfirmed claims as
OPINION-tier, but the wording inflates the venue's authority. The finding was flagged for that
plan's owner and deliberately not edited from the corpus run.

## 7. Coverage accounting and residue

### How the corpus was verified

Both primaries went through the same pipeline: an immutable snapshot of the original, a
heading-and-figure inventory, one digest agent per unit, then verification. Every quoted claim
sits in a column-0 fence asserting source-verbatim bytes, and two scripted gates
(`check-fences-exact.py`, `check-snippets.py`) check every fence against the snapshot. Both
slices passed those gates, replayed on 2026-08-31. Claim counts: P1 carries 37 verbatim claim
rows across five digests (5 + 5 + 15 + 9 + 3), P2 carries 59 across six (5 + 6 + 10 + 11 + 20 +
7).

Each slice ran two verification arms with the production rationale withheld, judging on-disk
state only, with every audited file's sha256 recorded and matched against a pinned manifest. Arm
B was meant to be cross-vendor; no cross-vendor verifier was installed in the session, so it
degraded to a second same-vendor adversarial refuter, and the degradation is recorded in the
verdict header rather than passed off as independence. Treat the agreement of the two arms as
weaker evidence than a true cross-vendor pass. Arm findings drove correction rounds: P2's round
two discharged all seven distinct MAJOR findings from both arms and was re-verified clean; P1's
corrections were re-verified against a re-pinned manifest, including an independent replay of
the link-anchor derivation from the article's entityMap, which produced exactly the six anchor
and URL pairs the inventory claimed, with none missing and none invented.

A separate fresh unbiased pass was then ordered, with ten workers barred from reading any
earlier layer, sweeping every source at paragraph grain with a four-lens critical apparatus
(concepts, assumptions, omissions, tensions). Reconciliation then adjudicated every fresh row
against the verified slices and the prior repo plans, one verdict per row.

### The verdict counts

P1: 130 fresh rows (90 concept, 13 assumption, 15 omission, 12 tension) yielded 83
covered-by-both-layers, 17 covered-by-digest, 8 covered-by-plan, 10 thin, and 12 gaps. All 90
concept rows were covered at least thinly, and every gap is a fresh-angle critique rather than
missing article content. Two conflicts surfaced: the venue error (CF-7, flagged) and an index
gloss calling the `#` hotkey "deprecated" where the source says only "Instead" (fixed). No
disagreement was found on any quoted byte, figure content, number, link target, or section
boundary.

P2: 171 fresh rows (129 concept, 14 assumption, 16 omission, 12 tension) yielded 117 covered, 21
thin, and 33 gaps, of which only three are content gaps: the bakery-prompt transcriptions and
the compaction caveat. The rest are critical apparatus, 18 of 26 critique rows, which is the
honest characterization of the slice layer: faithful on what the post says, largely silent on
its tensions and unstated preconditions. Three conflicts: the recoverable publication date
(fixed), the augment-versus-replace shading on just-in-time retrieval (recorded in 3.5), and one
interpretive disagreement about whether the why-it-matters section establishes a mechanism or
assumes one (left open, recorded in 3.2). The reconciliation also established by bounded grep
that the prior plan in `docs/topics/context-engineering-claude-5/` never cited, corroborated
against, or even linked P2: zero hits for the URL, "context rot", "attention budget",
"karpathy", or any anthropic.com URL. P2 was net-new to this repo's knowledge work.

Nine tier-2 pages were swept at paragraph grain by the fresh pass, producing between 16 and 76
concept rows each. Where their earlier structural notes and the fresh sweep disagree, the fresh
sweep governs on structure and content, with two exceptions retained as complements: the
structural notes' relevance-hook sections, which have no fresh equivalent, and T8's byline.

### What "fully accounted for" means here

Every paragraph of both primaries is covered, or explicitly classified thin or gap, with
row-level citations. Every figure in the corpus was viewed by a worker or the orchestrator,
described, and, for both primaries and T7, archived or resolution-logged. Every inline link in
both primaries was extracted from the entityMap or DOM with anchors verified. Every linked
first-party page was deep-swept with the four-lens apparatus. Prior repo work was engaged and
diffed in both directions, with conflicts adjudicated: two fixed, three flagged with named
owners.

### The residue, stated honestly

- **Referenced-external sources are cataloged, not digested.** None were fetched or verified, so
  claims resting on them rest on the primaries' characterization of them: the Karpathy coinage
  tweet (<https://x.com/karpathy/status/1937902205765607626>), the context-rot benchmark study
  (<https://research.trychroma.com/context-rot>), the human working-memory paper
  (<https://journals.sagepub.com/doi/abs/10.1177/0963721409359277>), the transformer paper
  (<https://arxiv.org/abs/1706.03762>), the position-interpolation paper
  (<https://arxiv.org/pdf/2306.15595>), an attention explainer
  (<https://huggingface.co/blog/Esmail-AGumaan/attention-is-all-you-need>), Willison's
  tools-in-a-loop definition (<https://simonwillison.net/2025/Sep/18/agents/>), the Pokémon
  stream (<https://www.twitch.tv/claudeplayspokemon>), and the MCP intro
  (<https://modelcontextprotocol.io/docs/getting-started/intro>). The context-rot study is the
  one that matters most: it is the empirical basis for the mechanism in 3.2, and this corpus
  never checked it.
- T3's ten use-case subsections were absorbed at row grain, but any videos or GIFs they contain
  were not played.
- Reply threads and social context around the X article were never in scope.
- P2's three calibration prompts are carried verbatim in appendix A below, transcribed from the
  figure image and independently re-verified against it by a second reader.
- Verification independence is degraded, not absent: both arms on both slices were same-vendor.

## Appendix A. The three calibration prompts, verbatim

P2's centerpiece pedagogy exists only as pixels in its figure 2 ("Calibrating the system
prompt"): the page's HTML carries the alt text and a CDN URL, nothing more. The transcription
below was taken from the figure image and then independently re-verified against that image by
a second reader, who confirmed it faithful with one systematic normalization: the figure renders
curly quotation marks, the transcription uses straight quotes. Layout, left to right: a
gradient bar of discrete cells, red at both ends and green in the centre, labeled "Too
specific", "Just right", "Too vague", with a marker dropping from each label to its card.

These are figure pixels rather than page bytes, so no byte-exactness gate covers them and none
should be claimed for them.

### Card 1, "Too specific"

```text
You are a helpful assistant for Claude's Bakery.
You must respond to the name Claude.
For every user request you MUST FOLLOW THESE STEPS:

1. Identify the user intent as one of the following: ["incident_resolution", "general_inquiry", "order_resubmission", "account_maintenance", "requires_escalation"]
2.
    - if user intent is "incident_resolution", ask 3 followup questions to gather information, then always call the resolve tool
    - if user intent is "general_inquiry", do not ask followup questions and answer in one shot
    - if user intent ...
    - ...
3. Here is an exhaustive list of cases that should be tagged as "requires_escalation":
    - If the intent is incident_resolution but the user is in a different country
    - If the user left a physical belonging in the store
    - ...
4. Once you've ruled out escalation scenarios you should consider all the tools at your disposal.
5. If the user_request contains an order_id you should tag the user intent as "order_resubmission", unless the user meets 5/7 of the following requirements:
    - User is asking for time update
    - User is asking for location update
    - ...
6. If the user wants to request a new order, but they already have another order in flight, you should follow these 5 steps of the resolution procedure:
    - (1) Call check_order tool to see where the current order is
    - ...
...
```

The caricature is structural: an "exhaustive" list that trails into an ellipsis, a fraction
over an elided set, a numbered step with no text, ellipses nested three deep. Enumeration
cannot close, which is the card's argument.

### Card 2, "Just right"

```text
You are a customer support agent for Claude's Bakery.
You specialize in assisting customers with their orders and basic questions about the bakery. Use the tools available to you to resolve the issue efficiently and professionally.

You have access to order management systems, product catalogs, and store policies. Your goal is to resolve issues quickly when possible. Start by understanding the complete situation before proposing solutions, ask follow-up questions if you do not understand.

Response Framework:
1. Identify the core issue - Look beyond surface complaints to understand what the customer actually needs
2. Gather necessary context - Use available tools to verify order details, check inventory, or review policies before responding
3. Provide clear resolution - Offer concrete next steps with realistic timelines
4. Confirm satisfaction - Ensure the customer understands the resolution and knows how to follow up if needed

Guidelines:
- When multiple solutions exist, choose the simplest one that fully addresses the issue
- If a user mentions an order, check its status before suggesting next steps
- When uncertain, call the human_assistance tool
- For legal issues, health/allergy emergencies, or situations requiring financial adjustments beyond standard policies, call the human_assistance tool
- Acknowledge frustration or urgency in the user's tone and respond with appropriate empathy
```

Note what the middle card does not do: it names no intent enum, no branch table, and no
exhaustive case list. It states a role, the tools, a goal, an ordered framework, and the
escalation conditions, then leaves the judgment to the model.

### Card 3, "Too vague"

```text
You are a bakery assistant, you should attempt to solve customers issues in a manner consistent with the principles and essence of the company brand. Escalate to a human if needed.
```

The card's own comma splice and "customers issues" read as part of the caricature. "Principles
and essence of the company brand" is the falsely-assumed shared context the post warns about,
made concrete.
