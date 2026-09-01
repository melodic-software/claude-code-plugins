# Critical apparatus: what the context-engineering corpus assumes, omits, and contradicts

## 1. What this layer is

The corpus's two primary sources (P1, the trq212 X article "The new rules of context
engineering for Claude 5 models", 2026-07-24; P2, the Anthropic engineering post "Effective
context engineering for AI agents", 2025-09-29) plus nine linked pages were absorbed twice.
The first pass produced faithful digests: what each source says. This layer is the second
pass, and it records what each source rests on, leaves out, and says against itself. It was
produced by a fresh unbiased paragraph-grain sweep whose workers were barred from reading the
existing digests, four lenses per source (concept inventory, implicit assumptions, omissions
and glosses, internal tensions), followed by bidirectional reconciliation: every fresh row
adjudicated against the prior digests and the in-flight
`docs/topics/context-engineering-claude-5/` plan (COVERED / THIN / GAP), plus a reverse check
for prior-layer content the fresh pass missed. The sweep and its reconciliations lived in the
session memory tier, which is gitignored and gone; the row IDs below (`P1-A01`, `P2-T08`,
`T6-T05`) are provenance labels carried into this doc, not links to anything readable. The
sweep produced 318 apparatus rows across ten sources; 142 are carried here, merged into the
entries below, and 176 were dropped as trivia or as concerns another repo doc already owns.

Reconciliation's headline finding: the digests were faithful on what the sources say (115 of
129 P2 concept rows covered; all 90 P1 concept rows covered at least thinly) and nearly silent
on the critical apparatus (8 of 12 P2 tension rows and 10 of 14 P2 assumption rows were
outright GAPs). An interview or a repo check run only from the digests would under-challenge
the sources. That asymmetry is why this file exists.

Use it as follows: before turning any corpus claim into repo doctrine, find the claim's row
here and discharge the guardrails in section 5.

## 2. Per source

### 2.1 P1, "The new rules of context engineering for Claude 5 models" (X article)

Carried: 36 of 40 apparatus rows, as 19 entries. Dropped: the cover-art description, the
give-versus-let wording variance (`P1-T02`), the missing before/after CLAUDE.md artifact
(`P1-O08`, already answered by that plan's `design/official-corroboration.md` include and
exclude table), the abandoned rubrics thread (`P1-O14`), and img4's visual subordination of
the system prompt (`P1-T09`).

| Rows | Claim | Why it matters for adoption |
|---|---|---|
| A01, A03, O02, O12 | The 80% deletion was validated on Anthropic's internal coding evals, and the reader is told to simplify the same way with no eval harness of their own and no recipe for building one. | "No measurable loss" is unfalsifiable for a reader who cannot measure; any repo check derived from the article inherits an evidence standard the repo has to supply itself. |
| A02, O03 | Every "Now" column is gated to the frontier Claude 5 generation, and the article concedes the old rules were correct for older models, yet offers no migration or version-gating technique for one CLAUDE.md serving a mixed fleet. | Guidance adopted repo-wide reaches whatever model a contributor is running; a generation-gated claim adopted ungated is actively wrong for part of the fleet. |
| A04, O07, O15 | Progressive disclosure assumes the retrieval step reliably fires, counts only the saved upfront tokens, and never states a window budget; a skill or file that is never loaded is an invisible failure. | This repo's own conventions load on demand, and that trigger does not fire inside subagents or after a compaction. Deferral moves cost, it does not delete it. |
| A05, O10 | Product surfaces are named by their state on one day, and `claude doctor` is twice recommended as a trimmer of instruction files with no description of its criteria or failure modes. | The corpus's fastest-aging claim (the `#` memory hotkey) went from "de-emphasized" in the article to removed in Claude Code v2.0.70 within weeks. Cite the changelog, not the article, for any product behavior. |
| A06 | "Match the surrounding code" presumes the surrounding code is coherent enough to be a signal. | In a legacy or multi-team tree the new rule points at noise where the old absolute rule at least gave a deterministic answer. A check that recommends replacing an absolute with a judgment call needs this precondition. |
| A08, O13 | Conflicting instructions are resolved by deleting one, never by establishing precedence between layers, and the article's own figure shows a stack whose ordering is never given a meaning. | Deletion and precedence are different remedies with different blast radii. The official layering rules (CLAUDE.md additive, skills and subagents and MCP override by name, hooks merge) answer this and the article does not. |
| A09, O06, T11 | Auto-memory is celebrated as a new always-on, model-curated context source in the same piece that diagnoses ambient context conflict, with no accuracy, staleness, inspection, or pruning story, and no hygiene entry in the closing playbook. | The article's own diagnosis applies to its own recommendation. Anything adopting auto-memory needs the audit surface the article omits. |
| A10 | Rich references ("a spec may be a detailed test suite", an HTML mockup over a description) presume the author has the skill and time to produce code-form artifacts. | For many contributors prose is the only spec they can write. A check demanding code-form references is undischargeable for them. |
| A12 | Clean layer separation is assumed: users do not touch the system prompt, builders own it. | The middle audience is real here: output styles, `--append-system-prompt`, agent definitions, and plugins all reach the system prompt. Neither column of the article's advice is addressed to them. |
| A13 | The article diagnoses exactly one failure direction, over-constraint, and never addresses under-specification. | Read as license, "delete, simplify, trust judgment" produces the vagueness failure. The replacement for a deleted rule should still encode its intent. |
| O01 | No detection story for judgment failure: no monitoring signal, no transcript-review recipe packaged as reader advice, no rollback criterion for reinstating a deleted rule. | This is the missing half of the deletion advice, and the direct input to the repo's deletion-evidence threshold question. |
| O04 | Security is entirely absent. Removing guardrails and routing decisions through "surrounding context and judgement" makes malicious surrounding context the judgment input; the one named worst case (deleting files) appears as historical motivation and is never re-secured. | Highest-stakes gap in the whole corpus. Filed as the G-SEC cluster; see section 5, guardrail 6. |
| O05 | CLAUDE.md and skills are shared team artifacts; the article addresses a singular "you" and never says who owns a gotcha or how teammates' conflicting preferences get reconciled. | Conflicting teammate preferences are precisely the conflict class the article opens with. A cross-surface conflict check can surface whose instruction wins but cannot decide it. |
| O11 | The choice is framed as prose rule versus model judgment; hooks, permission systems, and CI never appear, despite shipping in the same product. | The third option is often the right one. The official boundary is explicit: a rule in CLAUDE.md is a request, a PreToolUse hook is enforcement. |
| T01, T03 | The anti-example article persuades by example throughout, and its "simple tool descriptions" heading actually prescribes moving behavioral rules into descriptions; the after-figure still carries a rule. | The rules were relocated and compressed, not deleted. A repo check that scored description simplicity would penalize the article's own recommended output. |
| T04 | Examples are condemned for constraining the exploration space, then an enum is praised precisely because it "hints to Claude about how to use it". An enum is a harder constraint than an example. | The load-bearing distinction is never stated. See section 4. |
| T05, O09 | "Avoid making them overconstrained, except in highly important areas" re-admits the whole disease in six words, and "highly important" is never characterized. | Any reader can classify their pet rules as highly important and change nothing; equally, a trimming pass has no principled stopping point. This is the load-bearing calibration knob and it is undefined. |
| T07 | The article's own history reverses twice on intermediate files: the old system prompt forbade planning documents, plan mode then relied on markdown plan files, and the new advice enriches persistent references further. Presented as linear progress. | Direct evidence that a rule stated with confidence in one generation is reversed in the next. Treat the current column as dated, not as settled. |
| T08, T10 | "Keep your CLAUDE.md lightweight" sits beside "spend most of the tokens on gotchas", and "cannot be as specific" as a prompt sits beside a highly specific gotcha prescribed for CLAUDE.md. | The real rule is composition, not weight: derivable content out, tribal knowledge in; general in applicability, precise in wording. Quoting "lightweight" alone imports a rule the article does not give. |
| A07, A11, T06, T12 | Routed to the cross-source section: interface ownership (3.5), efficiency evidence versus correctness rhetoric (3.3), and the figure that retracts the body's evidence (3.4). | |

### 2.2 P2, "Effective context engineering for AI agents" (Anthropic engineering post)

Carried: 39 of 42 rows, as 18 entries. Dropped: the best-model-first budget assumption
(`P2-A06`), the measurable-outcome assumption (`P2-A08`), and the human-analogy-both-ways
observation (`P2-T09`). Note that this post was never engaged by the prior
`context-engineering-claude-5` plan at all (grep-verified during reconciliation: zero hits for
its title, URL, "context rot", or "attention budget"), so its apparatus is entirely net-new to
the repo.

| Rows | Claim | Why it matters for adoption |
|---|---|---|
| A01 | Context rot is established by one third-party needle-in-a-haystack benchmark and then generalized to every model, every task type, and the future. No first-party measurement appears anywhere in the post. | The corpus's most-cited mechanism rests on the thinnest evidence in it. Cite it as directional, not as measured. |
| A02, A03, T07 | The n-squared attention paragraph reads as rigor, but n-squared is the mechanism by which every pair is attended; the actual causal claims (training-distribution skew, position encoding) are the soft ones next door, and the dense-attention premise is silently assumed. | The digests called this section mechanism rather than assertion, and the fresh pass disputes exactly that. Do not cite this paragraph as the documented mechanism for degradation. |
| A05, O05, O01, O16, T01 | The whole methodology presumes an evaluation loop, "high-signal" is the load-bearing adjective and is never measured, no threshold in the post is quantified (compaction fill fraction, "tight", example counts, toolset size), and "context pollution" is introduced and never defined. | Two engineers can follow this post and build opposite systems, both claiming compliance. Any repo check derived from it must supply the threshold the post withholds. |
| A07 | Metadata as signal and progressive disclosure presume a well-organized information environment: meaningful names, honest timestamps, sane hierarchies. | In messy trees the same mechanism feeds the agent misleading signals. The precondition is the thing to check before adopting the technique. |
| A09, O03, O07 | Persistent notes and file-based memory get no staleness model, no provenance or integrity check, and no security framing at all; the words injection and trust do not appear. | Notes re-entering context are the vector by which a one-time injection becomes permanent. G-SEC again, and the reason a notes-file convention needs an owner before it needs a template. |
| A10, O02, O11, T11 | Sub-agents are recommended with no cost or latency criterion, no method for briefing them, no way to detect a silently dropped detail, and directly after a section warning that agents misuse tools and chase dead ends. | The post's own linked multi-agent case reports roughly 15x the token use of chat. A fan-out norm with a return-size figure but no cost criterion is half a contract. |
| A11, T02 | The post repeatedly teaches a technique and predicts its obsolescence in the same breath ("likely becoming less important as models become more capable"), then insists the principle is permanent without arguing why the principle survives what the techniques do not. | Everything in this corpus has a shelf life the corpus itself announces. Date and scope every derived rule. |
| A12 | Every worked example is an Anthropic product and the closing advice is scoped to teams building on Claude; transferability is asserted only implicitly. | Fine for this repo, which is Claude-specific, but it bounds any claim of general agent-design authority. |
| A13, O14 | The centerpiece figure's "just right" prompt is asserted by color: no eval, no failure-mode comparison, no evidence the middle prompt beats the left one, and the altitude calibration is demonstrated only on a mid-stakes assistant domain. | The post's flagship pedagogy teaches an aesthetic, not a test. Do not import "just right" as a standard. |
| O06 | Just-in-time retrieval, compaction, and tool-result clearing all rewrite or reorder context, which invalidates prefix caches, a platform feature with a direct price. The post's economics never mention caching. | Token efficiency measured per turn can be a cost regression per cache lifetime. The cookbook page has the same hole (`T8-O7`). |
| O08, T04 | "Do the simplest thing that works" sits atop a second half that is a catalog of non-simple machinery, and the post gives no negative guidance anywhere: no when-not-to, no when an agent is the wrong tool. | Its own predecessor is known for exactly that guidance. Adopting the machinery without the trigger economics is how a repo accretes always-on cost. |
| O09 | The move from embedding retrieval to just-in-time retrieval is presented as field convergence with no benchmark and no note of where embeddings still win. Note the verb: the post says teams are augmenting retrieval systems, and the digests shaded that into replacement. | Downstream artifacts citing the digest would overstate the post's anti-embeddings position. Quote the verb. |
| O10 | Notes, compacted summary, and live context can disagree, and the post never says which wins or how they compose, though real systems run all three at once. | A stale note against a fresh summary is a concrete failure this repo would hit in the first week. |
| O12 (with `T4-O009`) | Tool schemas and MCP servers occupy context before the first turn, and neither post gives a tool-count threshold or a pruning method. | The standing cost of a toolset is the part a per-turn token analysis never sees. |
| O13, T05 | Few-shot examples are strongly advised while edge-case lists are condemned, the distinction ("diverse, canonical" versus "laundry list") is aesthetic rather than operational, and the post's own methodology (add examples for observed failure modes) is precisely how laundry lists accrete. There is no versioning or regression discipline to catch it. | See 3.1. This is the internal half of the corpus's sharpest cross-source reversal. |
| O15 (with `T5-A013`) | All long-horizon advice assumes an autonomous run: checkpoints, human review, and approval gates are absent, while the older linked post insists agents add most value where they integrate meaningful human oversight. | Two sources in one corpus, opposite defaults, no reconciliation. Pick the default deliberately and record why. |
| T03 | Exploration is championed, then conceded to be slower and error-prone and dependent on thoughtful engineering, and the resolution offered is hybrid, depending on the task. | The recommendation dissolves at the moment of decision, which is the moment a repo check has to act. |
| T06 | Degradation is argued as real and universal, then hedged as a gradient rather than a hard cliff with models remaining highly capable at long contexts. Both directions are kept. | Enough alarm to motivate the discipline, enough reassurance to protect the long-context claim. Quote whichever you like, which is the problem. |
| T10 | The post warns against hardcoded brittle scaffolds while its flagship example, Claude Code, drops CLAUDE.md files into context up front (the post's own adverb is "naively") and ships a fixed five-most-recent-files constant in its compaction. | Anthropic's exemplar deviates from the post's aesthetic and the deviation is flagged, never reconciled. This repo's CLAUDE.md is loaded the same way. |
| T12 | The term's coiner and the agent definition's source are credited only as unlabeled hyperlink anchors, so a text-only reader receives both framings in Anthropic's voice. | Provenance is stripped by any extraction. Re-attach it when quoting. |
| A04 | Routed to 3.5 (interface and harness ownership). | |

### 2.3 The nine linked pages

Carried: 67 of 236 rows. These pages were absorbed for mechanism, so most of their apparatus
is page-local trivia; what survives is the rows that bite a repo decision. The tier-2
structural notes taken earlier had no assumptions, omissions, or tensions section at all, so
every row here is net-new relative to that layer.

**Agents judging agents (T3 dynamic workflows, T4 writing tools, T6 multi-agent research).**

| Rows | Claim | Why it matters for adoption |
|---|---|---|
| T3-T001 | The model is trusted to write its own harness in the same article whose "why" section documents that model's agentic laziness, self-preferential bias, and goal drift. Harness-writing is never explained as exempt. | If the failure modes motivate the harness, they apply to the harness author too. |
| T3-T004, T3-A003, T6-A05, T6-T06 | Self-preferential bias is defined as the model preferring its own findings, especially when judging against a rubric, and the mitigation offered (a separate context window) is assumed to neutralize a bias described as belonging to the model. Elsewhere agents rewrite their own tool descriptions, in a post warning that bad descriptions send agents down wrong paths. Judge alignment with human judgment is asserted, never shown. | Every verifier and rubric pattern in this repo rests on this assumption. Separate context is a mitigation, not a proof. |
| T3-T007 | Lossy summarization is the bug that workflows exist to fight (goal drift) and the safety mechanism of the quarantine pattern (pass the structured summary only). | The same mechanic cannot be both without a stated boundary. |
| T3-T002 | Dynamic beats static because static must handle all edge cases, and then the article recommends freezing dynamic workflows into files and shipping them as skills, which makes them static again. The patch offered is to prompt the model to treat the skill as a template. | This marketplace ships skills. The tension is ours, not theirs. |
| T3-A010, T3-O009 | A workflow shipped inside a skill is presented purely as a benefit (anyone who installs the skill runs the same workflow), with no review step and no statement of what the executing sandbox can reach. | G-SEC. Distribution-channel trust is assumed. |
| T3-A007, T6-A07, T6-O03 | Token count is treated as the only cost axis: a figure shows 1.1M-token runs without comment, and multi-agent economics are given as multiples (roughly 4x for agents, 15x for multi-agent) with no dollar or latency figure anywhere. | Fan-out advice with no cost model is how a repo ships an expensive default. |
| T6-T08 | Multi-agent is pitched as a vital way to scale performance in the same section that concedes it is uneconomical except for high-value parallelizable tasks and unfit for most coding. | That is a niche, not a scaling law. It bounds every fan-out recommendation derived from this page. |
| T6-T05 | The lead agent's compression of subagent findings is the architecture's benefit in the body and a game of telephone causing information loss in the appendix, which recommends bypassing the coordinator. | The corpus contains its own refutation of the relay it recommends. |
| T6-T02, T6-T03 | Parallelism is credited with up to 90% time cuts while execution is conceded to be synchronous, so one slow subagent blocks the system; and heuristics-not-rigid-rules sits beside hard numeric scaling rules embedded in the prompts. | Both are places where the stated principle and the shipped artifact disagree. |
| T4-O004 | The headline gains (67.4% to 80.1%, 79.6% to 85.7%) prove the optimization loop works and never say which principle produced them: naming, descriptions, response format, or consolidation. | The numbers license the loop, not the individual principles the page teaches. Do not cite them for a specific rule. |
| T4-T001 | Consolidate multiple operations into one tool, and give every tool a clear distinct purpose, with no stated boundary between healthy consolidation and purpose blurring. | The boundary is exactly what a tool-design check would need. |
| T4-T003 | Agent feedback is the improvement engine and is declared unreliable in the same section ("LLMs don't always say what they mean"); the mitigation is manual transcript reading. | The optimization signal and the thing you cannot trust are the same channel. |
| T4-T007 | Tokens are scarce in tool responses (a 25,000-token cap, concise by default) and freely spent on chain-of-thought and interleaved thinking to raise effective intelligence, with no accounting for the trade. | Token thrift is a per-surface policy in this corpus, never a budget. |

**Human in the loop and workflow design (T2 field guide, T5 building effective agents).**

| Rows | Claim | Why it matters for adoption |
|---|---|---|
| T2-A008, T2-A011 | The workflow assumes the operator can recognize what they want when shown candidates, and can judge the quality of Claude's teaching in exactly the domains where they by definition lack knowledge. | The field-guide audit reached the same finding independently: the playbook assumes an evaluation function it never tests. Convergence from two directions is the strongest signal in the corpus. |
| T2-A003 | Implementation notes are assumed complete and honest, and a quiz authored by the agent that made the change is assumed to cover the genuinely risky parts. | Self-report plus self-authored assessment is the weakest verification shape available, and it is the only merge gate the guide offers. |
| T2-A010 | On mid-run deviation the agent picks the conservative option and continues without checking in. | The rule is magnitude-blind and unbounded. This is the audit's one source-weaker verdict: the repo's replan threshold already names the article's failure mode. |
| T2-A002, T2-A006 | Every practice ends in a human reaction step, and the guide is written in the first person singular with teammates appearing only as post-hoc reviewers. | Synchronous single-operator assumptions do not survive contact with a fleet or a background session. |
| T2-O004 | Nothing verifies the code. Tests, CI, and review never appear; the only merge gate is a human passing a comprehension quiz. | Comprehension is not authorization. Any adoption needs the verification floor the guide omits. |
| T2-O005, T2-T005 | Implementation notes exist so the next attempt can learn, are declared temporary, and have no channel into the durable map of skills and context. | The practice discards the knowledge it was created to capture. Found independently by the audit as a homeless-ownership problem. |
| T2-T001 | The guide warns that over-specific prompts make the model follow instructions when a pivot would be better, and delivers that warning through highly prescriptive exemplars, with no rule for which details are safe to pin. | Same shape as `P1-T01`. The corpus repeatedly violates its own anti-specificity advice in its exemplars. |
| T2-T004 | Mechanical refactoring is delegated sight unseen before implementation, and after implementation nothing merges until the human answers perfectly on everything that happened, including that trusted work. | Two trust postures, no principle separating them. |
| T2-T007, T2-O003 | Two definitions of "unknown" are stitched together (a map-territory gap, and the operator's awareness states), and no criteria are given for skipping the practices on small or well-known work. | The repo's own framing already unified the two definitions, which is why the audit never noticed the stitch. Trigger economics is the deepest treatment in any layer, and it is the repo's, not the article's. |
| T5-T001 | Agents are "just LLMs using tools in a loop" and implementation is called straightforward, while the appendix reports more time was spent optimizing tools than the overall prompt. | The loop is simple; making it work is not. The simplicity claim undersells where the engineering lives. |
| T5-T002 | The post recommends using LLM APIs directly and warns that frameworks obscure the underlying prompts, and the current page opens that same section by listing four frameworks including Anthropic's own SDK. | The tension was sharpened by a silent revision, not by the original text. |
| T5-T003, T5-T004 | The workflow-versus-agent binary is undercut by the post's own flagship example, which embeds fixed gates inside an agent loop; and the evaluator-optimizer workflow, the one most prone to non-termination, is given no stopping condition while the agents section prescribes maximum iterations. | If you adopt the taxonomy, adopt it as a continuum with an explicit iteration cap. |
| T5-T005 | Agents are ideal for scaling in trusted environments precisely because humans are out of the loop, and the appendix says agents add most value where they integrate meaningful human oversight. | Unreconciled, and it is the decision a repo has to make first. |
| T5-O015, T5-T008 | The page reads "Published Dec 19, 2024" while quoting model names and an SDK that postdate publication, and the framework list was changed after publication with no inline changelog. | Quoting "the December 2024 post" from this URL quotes a silently updated text. This is live evidence for the repo's deferred content-hashing reopen trigger. |
| T5-A001, T5-O007 | The reader is assumed to control the whole stack, and prompt injection is out of scope even though the examples include tools that issue refunds and agents that operate computers. | Ownership precondition (3.5) and G-SEC. |

**Platform and reference surfaces (T7 platform announcement, T8 cookbook, T9 prompting docs).**

| Rows | Claim | Why it matters for adoption |
|---|---|---|
| T7-T002 | The announcement claims agents can handle workflows extending beyond any fixed limit, while the mechanism it describes clears content when approaching token limits. What is extended is turn count, not the limit. | A within-window pruning mechanism described in unbounded language. Do not import the phrasing. |
| T7-T001, T7-A005, T7-O001, T7-O002 | The 39% combined and 29% context-editing-alone figures never isolate memory alone, the baseline is never operationally defined, and the 84% token reduction is given without absolute counts, cost, or a statement that quality was held constant. | The two-part framing's implicit symmetry is unsupported by its own numbers. |
| T7-T004 | An unqualified superlative sits directly beside data-flavored claims sourced to an unnamed internal evaluation set, with nothing distinguishing marketing assertion from benchmarked assertion. | Same page, two evidence tiers, no visual or rhetorical separation. Tier them yourself. |
| T7-O004, T8-T1 | Model scoping is unclear or self-contradictory: the announcement names only one model, and the cookbook gives two incompatible supported-model lists for the same feature (five models in one section, two in two others). | Both cookbook lists are stale as of the corpus pass: the memory tool needs no beta header and spans all Claude 4 and later models, and Claude Code exposes neither the memory tool nor context editing natively. Do not cite the cookbook as a model-list source. |
| T8-T2 | A worked transcript logs 6,611 input tokens against a stated 5,000-token trigger and reports that no clearing was triggered, with no explanation. | The corpus's only end-to-end trace of the mechanism does not match its own configuration on a literal read. |
| T8-A008, T8-O1 | Prompt-injection mitigation is "instruct Claude to ignore instructions in memory", offered without the standard caveat about prompt-based defenses, and the entire security implementation is named but never shown while non-security code is fully reproduced. | G-SEC. The security half of the page is the half you cannot read. |
| T8-A007, T8-T3 | Every demo constant is a teaching value to be rescaled by qualitative pointers, and production trigger guidance appears twice in different forms (a 30k to 40k prose range and a hardcoded 35000). | Copy a constant from this page and you have copied a demo. |
| T9-T002 | The general instruction to have Claude self-check against test criteria is immediately reversed for one model generation: remove these instructions rather than rewriting them, because they now cause over-verification. | The cleanest example in the corpus of a technique inverting within one model generation. See guardrail 1. |
| T9-O001 | Neither prompting page mentions context engineering by that term or a close synonym anywhere. | The corpus's central vocabulary is absent from the vendor's own prompting reference. Treat the term as a house coinage, not documented doctrine. |
| T9-T004, T9-T005, T9-A002, T9-A007 | The overview presents the best-practices page as the living reference and that page immediately fans back out to four further per-model pages; prompting and model choice are framed as alternative remedies on one page and as coupled on the other; and phrases like "Claude's latest models" are used dozens of times and enumerated never. | Any pointer chain into the vendor prompting docs terminates at a hub, not an answer, and the answer that matters is per-model. |
| T9-T001 | "Be clear and direct" because the model will not infer beyond what you ask, alongside repeated claims that the newest models proactively infer intent and delegate without instruction. | The general principle is really a safety default for cases the proactive behavior misses, which the page never says. |

## 3. Cross-source tensions

These are the disagreements that survive merging, where two sources in one corpus say
different things and a repo decision has to pick.

### 3.1 The few-shot reversal (P2 against P1)

P2 (September 2025) strongly advises few-shot examples, asking for a diverse set of canonical
examples rather than an exhaustive edge-case list. P1 (July 2026) puts examples in the "Then"
column and interfaces in the "Now" column, on the grounds that examples constrain the
exploration space. The same corpus therefore advises and deprecates the same technique eleven
months apart, and neither source acknowledges the other on this point.

Three facts constrain the resolution. First, P1's claim is generation-scoped, and P1 concedes
the old rules were right for the older models. Second, the vendor's own prompting
documentation still recommends examples, and the examples-harm claim appears on no official
surface; the corroboration pass found it unsupported. Third, P2's internal tension
(`P2-T05`, `P2-O13`) shows the advice was already unstable: the distinction between canonical
examples and a laundry list is aesthetic, and the post's own iterate-on-failures methodology
is exactly how laundry lists accrete.

Resolve it per model generation, not by publication date. On the generation P1 addresses,
prefer an interface constraint (an enum, a schema, a typed return) over a worked example
wherever an interface can carry the same information, and keep examples for what no interface
can carry: format, tone, and judgment calls with no enumerable range. On older or mixed fleets
keep the canonical examples, because that is the regime P2 measured and P1 concedes. In both
cases the deciding evidence is your own eval, because neither article supplies one.

### 3.2 Compaction: high fidelity against its own caveat

P2 calls compaction high fidelity and claims minimal performance degradation, then admits one
paragraph later that a piece of context's importance often becomes apparent only later
(`P2-T08`, `P2-A14`). Fidelity cannot be judged at compaction time by a summarizer that does
not yet know what will matter, so the confidence claim and the epistemic admission cannot both
be fully true. The post also never addresses what repeated compaction does (summaries of
summaries), how to detect a bad compaction after the fact, or how to recover once the
discarded history is gone (`P2-O04`). The platform announcement overstates in the same
direction (`T7-T002`), and the cookbook's own trace does not match its configured trigger
(`T8-T2`).

For adoption: carry the caveat with the technique, always. A compaction or context-editing
recommendation that cites the fidelity claim without the later-importance admission has
inherited half a source. Both sentences travel together or neither does.

### 3.3 Efficiency evidence, correctness rhetoric

The measured claims in this corpus are efficiency claims. P1's 80% is a token-reduction claim
scoped to Anthropic's coding evals with no measurable loss reported on those evals
(`P1-O02`), and its own supporting sentence says the model can interpret intent and reach the
right answer but must think more carefully when instructions conflict (`P1-T06`), which is a
reasoning-tax argument, not a wrongness argument. The rhetoric wrapped around it is a
correctness rhetoric: myths, unhobbling, guidance that is wrong. T7's percentages carry the
trappings of measurement with no methodology (`T7-O001`). T6's headline 90.2% never defines
its metric or denominator (`T6-O01`). T4's gains prove a loop, not a principle (`T4-O004`).

For adoption: separate the two before deriving anything. An efficiency delta licenses "this is
cheaper", never "the old rule was wrong". The repo's evidence tiering already has a place for
the middle case: the 80% figure appears on no official surface, but the changelog's
lean-system-prompt default is directional corroboration, so it is an opinion-tier claim with a
directional annotation, and the magnitude stays vendor voice.

### 3.4 The figure that retracts the body

P1's body presents its conflicting-instruction example as observed, from reading transcripts of
internal usage. The figure rendering those same quotes carries a footnote:

```
Illustrative examples, not verbatim quotes from any real prompt, skill, or user request.
```

The article's only transcript evidence is retracted by its own figure, and a careful reader
cannot tell whether the opening diagnosis rests on data or on invention (`P1-T12`). The figure
layer is doing this work in both directions across the corpus: T3's only cost numbers (22
agents, 1.1M tokens, 11m3s) exist solely inside an image, T4's headline percentages are chart
content, and P2's centerpiece worked prompts exist only as pixels.

For adoption: never cite a body claim without checking the figure, and never cite a figure
number without checking whether the body states it. Where the two disagree, the corpus gives no
rule for which wins, so record both.

### 3.5 The interface-ownership precondition

Four sources independently assume the reader owns the surfaces the advice acts on: P1 tells you
to redesign tool parameters (`P1-A07`), P2 assumes you decide what enters context each turn and
can implement compaction (`P2-A04`), T4 assumes you own tool names, schemas, response formats,
and error text (`T4-A002`), and T5 assumes you control the whole stack down to the API calls
(`T5-A001`). None addresses the reader consuming third-party MCP servers, vendored tools, or
someone else's harness, and none offers a fallback.

For adoption: this is the precondition that decides whether a derived check is dischargeable. A
check telling a contributor to redesign a third-party tool's parameters cannot be satisfied, and
should not be written. Filed as the G-PRECOND cluster with `P1-A06` (coherent surrounding idiom)
and `P1-A10` (capacity to author code-form references).

## 4. The unstated thesis

The fresh pass identified one proposition that P1 never states and without which its own
argument does not cohere:

> Constraining the interface is good. Constraining the behavior space by example is bad.

Read P1 without it and three of its moves are contradictions. It condemns examples for
constraining the exploration space, then praises an enum precisely because it hints at how the
model should use a tool, and an enum is a harder constraint than an example (`P1-T04`). It
titles a section "simple tool descriptions" and then prescribes moving behavioral rules into
those descriptions, whose after-state still carries a rule (`P1-T03`). It is an anti-example
article that persuades entirely by example, and its most memorable example is an example about
not using examples (`P1-T01`). Read it with the thesis and all three resolve: an enum is
interface, a consolidated description is interface, and a worked example is behavior space. The
same thesis reconciles the field guide's parallel violation (`T2-T001`, prescriptive exemplars
delivering anti-specificity advice), and it is the coherent version of P2's
canonical-versus-laundry-list distinction, which P2 leaves as taste.

Two consequences follow, and both matter more than the thesis itself.

First, the thesis inverts the corpus's own advice about deletion. If the goal is to constrain
the interface, the answer to a prose rule is usually to move it into a schema, an enum, a type,
a hook, or a permission, not to delete it. P1 frames the choice as prose rule versus model
judgment and never mentions the third option even though the product ships it (`P1-O11`), and
the official boundary is explicit that a rule in prose is a request while a PreToolUse hook is
enforcement.

Second, the thesis is only available to a reader who owns the interface, which is 3.5. Where
you do not own it, the corpus's advice reduces to deleting the rule and hoping, which is
precisely the case its security omission (`P1-O04`) leaves unaddressed.

Filed as the G-THESIS cluster. Its immediate use is as design rationale wherever a repo check
recommends replacing prose guidance with something else: the something else should be an
interface where one exists, and the rationale should say so.

## 5. Adoption guardrails

Apply these before turning any corpus claim into repo doctrine. Each is distilled from the rows
above and names them, so a contributor can check the reasoning rather than take the rule on
faith.

1. **Name the generation.** Every technique in this corpus is model-generation-gated, and the
   corpus contains one technique reversed within a generation (`T9-T002`) and one reversed
   across generations (`P1-A02`, section 3.1). Record which model a claim was measured on and
   which models your fleet runs. A generation-gated claim adopted ungated is wrong for part of
   the fleet, and the source will tell you so if you read its concession.
2. **Ask what was measured, then bound the claim to it.** An efficiency delta licenses a cost
   argument, never a correctness argument (3.3). Scope each claim to the eval it came from:
   coding evals for P1, search and browse benchmarks for T6, one third-party needle benchmark
   for `P2-A01`. Where no vendor surface carries the figure, it stays opinion-tier, with a
   directional annotation if a changelog corroborates the direction.
3. **Do not adopt a deletion without a detection and a rollback.** The corpus recommends
   removing guardrails and supplies no monitoring signal, no failure-detection recipe, and no
   criterion for reinstating a rule (`P1-O01`, `P1-A13`). Consequential deletions need ledger
   evidence in the repo's existing grammar; trivial ones do not. If you cannot say how you
   would notice the deletion was wrong, you are not ready to make it.
4. **Discharge the ownership and environment preconditions.** Before writing a check, ask
   whether the reader owns the interface (3.5), whether the surrounding code is coherent enough
   to be a signal (`P1-A06`), whether the tree is organized enough for metadata to inform rather
   than mislead (`P2-A07`), and whether the reader can author the artifact the advice presumes
   (`P1-A10`). A check that cannot be discharged should not ship.
5. **Price the whole loop, not the upfront tokens.** Progressive disclosure adds retrieval turns
   and can silently fail to fire (`P1-A04`, `P1-O07`); fan-out costs multiples, not deltas
   (`T6-A07`, `T3-A007`); every context rewrite invalidates a prefix cache (`P2-O06`, `T8-O7`);
   and the toolset itself has a standing cost (`P2-O12`).
6. **Never route an injection-sensitive or destructive action through judgment alone.** The
   corpus's largest shared hole is security: guardrail deletion with malicious surrounding
   context as the judgment input (`P1-O04`), persistent notes as an injection that survives
   resets (`P2-A09`, `P2-O03`), a prompt-based injection defense offered without caveat
   (`T8-A008`), and skill-distributed executable workflows assumed safe (`T3-A010`). Any
   judgment-delegating rewrite in these areas needs an enforcement-layer backstop, which is the
   third option `P1-O11` omits. Tracked as G-SEC.
7. **Prefer an interface to a rule, and precedence to deletion.** Section 4 for the first half;
   `P1-A08` and `P1-O13` for the second. Where two surfaces conflict, the official layering
   rules already say how they compose, and establishing precedence keeps the guardrail that
   deletion discards.
8. **Read the figure and the body against each other.** The corpus's only transcript evidence is
   retracted in a footnote (3.4), and several of its only numbers exist nowhere but inside
   images. Cite neither layer alone.
9. **Date, scope, and pin the citation.** Pages in this corpus are revised silently (`T5-O015`,
   `T5-T008`), features named in them are removed within weeks of publication, and both cookbook
   model lists were stale by the time of the pass. Cite the changelog or the reference page for
   product behavior, and cite the article only for its argument.
10. **When two corpus sources disagree, do not resolve by date.** The newer source wins only
    where the difference is genuinely generation-gated and the source says so. Otherwise the
    disagreement is an open question for your own eval, and the honest artifact records both
    positions (3.1; `P2-O15` against `T5-A013`).

A last item that is not a rule but a posture. The digest layer of this corpus is faithful and
the sources are useful; nothing here argues against adopting their techniques. It argues against
adopting them as gospel, because on the evidence assembled above the sources do not hold
themselves to that standard either.
