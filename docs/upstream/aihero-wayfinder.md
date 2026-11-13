# Upstream source: AI Hero Cohort 005, Workshop 3 "Wayfinder" (Matt Pocock)

This page records what this repository takes from, adapts, already has, or rejects in the
**Wayfinder** workshop of Matt Pocock's AI Hero cohort (Cohort 005): ten lessons (The Limits of One
Session; Charting the Way; Chart the Map; Grilling Ticket; Grilling Ticket 2; Task Ticket;
Prototype Ticket; Finish the Map; Spec to Implement; Grill vs Wayfinder vs Ship First). The
workshop teaches charting a too-big, still-foggy effort as a map of decision tickets on the issue
tracker and working it one decision at a time. Our counterpart is
[`/planning:wayfind`](../../plugins/planning/skills/wayfind/SKILL.md). Rows hold our decisions and
our own descriptions of each idea, under the upstream-drift convention's
[What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe). The
course is paid and account-gated, so no lesson text is recorded or linked here; the skills it
teaches are public and versioned in [mattpocock/skills](https://github.com/mattpocock/skills),
whose record is [mattpocock-skills.md](mattpocock-skills.md). Earlier course units have their own
records: [aihero-course.md](aihero-course.md), [aihero-shipping-course.md](aihero-shipping-course.md)
and [aihero-domain-language.md](aihero-domain-language.md).

- **Pointer**: when a row needs the upstream mechanism, fetch the public skills it rests on live:
  [`wayfinder`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/wayfinder),
  [`prototype`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/prototype),
  [`research`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/research),
  [`wizard`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/wizard),
  [`to-spec`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/to-spec),
  [`to-tickets`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/to-tickets),
  [`implement-spec`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/implement-spec)
  and
  [`grill-with-docs`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/grill-with-docs).
- **As of**: 2026-11-13
- **Recheck trigger**: a mattpocock/skills changeset naming one of those units, checked as
  [mattpocock-skills.md](mattpocock-skills.md) describes. Course page updates are not observable
  events; the skills-repo changeset stream is the proxy, as in
  [aihero-shipping-course.md](aihero-shipping-course.md).

**Decision ids.** `Q<n>` is an owner decision from the workshop's interview register (rounds L01 to
L10, 2026-11-11 to 2026-11-13). The register is not committed; each row names the decisions and the
pull request that landed them. A row with no id carries no decision from this workshop's register; it
records how the idea compares with what we already have.

**Landed** means merged unless marked open. As of 2026-11-13,
[#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (wayfind charting,
working and closing; held with `do-not-merge` for one before/after eval over the stacked wayfind
changes),
[#15823](https://github.com/melodic-software/claude-code-plugins/pull/15823) (interview and routing)
and [#15824](https://github.com/melodic-software/claude-code-plugins/pull/15824) (container label)
are open. "Not landed" marks a decided change with no pull request yet.

## Attribution table

Disposition is `take`, `adapt`, `already have` or `reject`, with the reason. The upstream-problem
cells are **Inference** throughout: the lesson pages that state them are paid and not linked.

### Lesson 1: The Limits of One Session

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Planning becomes the constraint once agents build | Treats planning capacity, not build capacity, as what limits throughput | Building from a clear idea is cheap, so the plan sets the pace | The constraint is the human hand-off of intent and vision during planning, plus review of what comes out | **take**, restated: planning with a human in the loop is the constraint; agent verification and low-risk auto-merge serve the review end; keeping agents saturated goes to the lanes workshops | none |
| A long interview fills one session | One interview runs out of room, compaction drops answers, and halves split across sessions lose their cross-links | Rich answers vanish once a session compacts | Our interview writes a ledger in the memory slice from its first round, so a compacted interview resumes from the file ([`interview/SKILL.md`](../../plugins/planning/skills/interview/SKILL.md)) | **already have** (Q300): the interview keeps its fog and question-count wayfind triggers; size alone routes to the continuation router ([`routing.md`](../../plugins/planning/skills/interview/context/routing.md)) | none |
| Planning fidelity | Ranks planning artifacts from talk to working code by how concrete they are | Cheap agent prototypes make higher fidelity affordable earlier | Our planning skills had no name for it | **take** (Q301): wayfind names fidelity; each item is settled with the cheapest artifact that answers its question, never below the level that answers nothing | [#15396](https://github.com/melodic-software/claude-code-plugins/pull/15396) |
| Appetite bounds the solution | Fixes how much an effort is worth and shapes the solution to fit | Scope grows to fill whatever time a plan allows | The Brief recorded an appetite nothing downstream read | **adapt** (Q302): plan and brainstorm fit the approach to the appetite and cut scope; plan review asks whether the plan is within appetite; no numeric budget | [#15396](https://github.com/melodic-software/claude-code-plugins/pull/15396) |
| A multi-session planner for unknown unknowns | His skill's purpose | Some efforts cannot be planned in one sitting | Same | **already have**: `/planning:wayfind` with its too-big AND foggy trigger; the interview stays the entry, which lesson 10 also recommends | none |

### Lesson 2: Charting the Way

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| The map is one tracker issue indexing child decision tickets | Each decision lives on its own child; the map summarizes and links | A plan spread over files has no single place to see state | Same | **already have**: wayfind's map issue and its Decisions-so-far pointer index ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md), "Chart mode" step 3) | none |
| A label of its own for maps | Marks map issues apart from other containers | Maps must be found without reading every issue | Our container label marked spec containers and maps alike, so lists mixed them | **adapt** (Q310): maps carry `wayfind: map`; `work-map` becomes `spec-container` | [github-iac#865](https://github.com/melodic-software/github-iac/pull/865), [#15824](https://github.com/melodic-software/claude-code-plugins/pull/15824) (open) |
| Name the destination first; for code, a spec | The end product shapes every ticket | Without a destination the map drifts | Same | **already have**: [`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Chart mode" step 2 names and confirms it; the first question is sharpened under Q323 (lesson 3) | none |
| Fog of war against a sharp question | Only what can be phrased becomes a ticket; the rest is fog | Early on most decisions cannot be seen yet | Same | **already have**: [`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "The fog test" | none |
| Frontier: open, unblocked, unclaimed; claim by assignment | Picks the next ticket from the dependency graph | Parallel sessions need a safe pick | Same | **already have**, with a lease on the claim (`/work-items:track start`; [`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Work mode" steps 3 and 4) | none |
| Typed tickets; research runs in the background | Ticket type picks the session's method | Different questions need different methods | Same | **already have**, five types including design ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Work mode" step 5); our prototype plugin covers his prototype type (Q314) and `/discovery:research` his research type (Q315) | none |
| Two ways in: a prompt charts, a ticket link works that ticket | One command serves both modes | Inference: the user should not have to name the mode | Ours needed an explicit `chart` or `work` | **adapt** (Q313): an item link routes to that item, other text charts, and a bare call with an open map lists the frontier, recommends one and waits | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Bold the terms an agent anchors on | Emphasizes key terms in skill bodies | Inference: agents latch onto the marked terms | Asked across all skills | **reject** (Q312): instruction rules are stated in plain words without emphasis markers ([ADR 0098](../adr/0098-state-instruction-rules-in-plain-words-without-emphasis-markers.md)) | [#15430](https://github.com/melodic-software/claude-code-plugins/pull/15430) |
| Tracker conventions written into the agent instructions file | His setup step stores tracker settings in AGENTS.md | Agents need the tracker setup at hand | Ours keep settings in convention files, with AGENTS.md holding pointers only | **reject**: settings stay in `docs/conventions/work-items.yaml`; the legacy JSON binding was retired across readers (Q316) | [#15459](https://github.com/melodic-software/claude-code-plugins/pull/15459) |
| His names: wayfinder, ticket, grilling | Names the skill and its parts | n/a | "Item" matches `work-items`; "grilling" was rejected in Workshop 2 | **reject**: keep wayfind, decision item and interview | none |
| User-only invocation | The model cannot start the skill | Inference: avoid accidental charting | Ours is model-invocable, with the interview as the entry | **reject**: keep model invocation (Workshop 2 precedent) | none |

### Lesson 3: Chart the Map

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Propose the whole map, then create it on one yes | Shows the full map before any issue exists | A wrong map is costly to undo on the tracker | Ours confirms only the destination, then creates items unchecked | **adapt** (Q320) | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| A short map | Fog as labeled bullets, Notes as standing constraints, ticket bodies as the question alone | A long map is hard to scan and work | Our first real map carried a long Notes section, fog as one paragraph and item bodies with recommendations | **adapt** (Q325) | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| A ticket is a topic for one session | Groups related questions under one ticket | Inference: one-question tickets bloat the map | Ours charted one item per yes/no question | **adapt** (Q328): items are topics; sharp questions that already carry a recommendation are asked in one interview round before the map is created | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Ask what done looks like | Pulls the destination out of the user, a spec for code | Inference: users rarely state the end product | Ours asked for a destination without proposing a kind | **adapt** (Q323): chart's first question recommends a spec (PRD) for a coding effort | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| "I don't know" is an answer | The agent looks things up instead of guessing | Agents fill gaps with confident guesses | Same risk in our chart | **adapt** (Q324): unknowns are sorted into a research item, an interview item or fog; research comes first | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Lean on the glossary while charting | The survey reads the domain glossary | Inference: terms settle faster | Chart's survey did not name the glossary or tracker conventions | **adapt** (Q326) | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Say early that this is a map | Flags a foggy, multi-area request as map work at the start | A session sinks time before switching | Our interview offered wayfind only after rounds showed fog | **adapt** (Q322): the interview offers wayfind in round 1 when the request already shows it; wayfind's description stops calling itself never the first step | [#15823](https://github.com/melodic-software/claude-code-plugins/pull/15823) (open), [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Research findings in a sourced file on a throwaway branch | A resolution comment summarizes and links the file | Agents need the findings, kept apart from product code | Ours told research to use the dossier branch but no step copied the file there | **adapt** (Q321, Q362): a numbered step copies findings to the map's one dossier branch, a folder per item, pushed with fetch, rebase and retry; no branch per ticket | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Research tickets start in the background after charting | Fires research subagents at once | Research answers sharpen later tickets | Same | **already have**: parallel research burn-down and `wayfind_research_start` ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Work mode" step 4, "Settings") | none |
| Glossary decisions during charting | Settles domain names in the charting interview | Inference: names drift otherwise | Same | **already have**: the interview writes the glossary through [`ubiquitous-language`](../../plugins/domain-driven-design/skills/ubiquitous-language/SKILL.md) | none |
| Notes name the default skills per ticket type | Every session reads the same constraints and skills | Inference: sessions diverge without shared rules | Same | **already have**: the map's Notes list the skills every session consults ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Chart mode" step 3, "Work mode" step 5) | none |
| Other automation leaves map tickets alone | n/a (found on our first map) | n/a | Our intake lane commented on map items and labeled them for triage | **adapt** (Q327): intake triage and admission skip map issues and `wayfind:` items | [#15670](https://github.com/melodic-software/claude-code-plugins/pull/15670), [#15762](https://github.com/melodic-software/claude-code-plugins/pull/15762) |
| A script replays tracker state per lesson | Teaching mechanism | n/a | none | **reject**: course mechanics | none |

### Lesson 4: Grilling Ticket

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Fresh session per ticket; claim first; read the code before asking | Each ticket starts clean | Inference: a full context degrades answers | Same | **already have**: one item per session, claimed through `/work-items:track start` ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Work mode" step 4); the interview resolves facts from the code before asking ([`interview/SKILL.md`](../../plugins/planning/skills/interview/SKILL.md)) | none |
| Confirm, comment, close, one-line pointer | The resolution is restated, posted and indexed | The decision must outlive the session | Ours had the sequence but no shape for the result or the report | **adapt** (Q334): the resolution is the agreed result as a table with out of scope, deferred items, glossary changes and what later items inherit; the work report lists the closed item, the new map line, new items and what is now unblocked | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| A resolution clears some fog and adds new fog | Charts newly sharp tickets | The map grows as it is worked | Same | **already have**: [`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Work mode" step 6 | none |
| Several people on one map | Unblocked tickets run in parallel | Inference: a team shares one map | Our human-item cap counts per map across every session, so a team works one human item at a time | **adapt** (Q330): `wayfind_hitl_concurrency` counts per assignee, default 1 | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Re-read the map before editing it | Picks up another session's edits | Concurrent sessions overwrite each other | Not stated in our graduate step | **adapt** (Q331): read right before each edit, read back after | [#15371](https://github.com/melodic-software/claude-code-plugins/pull/15371) |
| Resume with the skill and the next ticket link | The handoff carries almost nothing | The map already holds the state | Our handoff wrote a full save-point | **adapt** (Q332): wayfind ends each item with a clear-and-resume line naming the next item; the handoff gains a short form when a tracker item holds the state | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open), [#15823](https://github.com/melodic-software/claude-code-plugins/pull/15823) (open) |
| Domain terms need their qualifier | The agent qualified a term only when asked | A bare term collides with another concept | Same risk in our interview | **adapt** (Q333): the interview proposes a qualified name when a term clashes with a code or glossary concept | [#15823](https://github.com/melodic-software/claude-code-plugins/pull/15823) (open) |

### Lesson 5: Grilling Ticket 2

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| A decision stays provisional until its prototype passes | A prototype ticket carries pass checks, a fail action and a fallback | A choice made at too low a fidelity can be wrong | No provisional state and no prototype item shape | **adapt** (Q340) | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Ask what the prototype must prove; split by question | Smaller prototype tickets run at once | One broad prototype answers nothing well | Our interview did not ask it | **adapt** (Q341) | [#15823](https://github.com/melodic-software/claude-code-plugins/pull/15823) (open) |
| The interview decides the graph's shape | Edges follow real dependencies | Inference: invented order blocks parallel work | Same | **already have**: chart wires an edge only where one decision gates another ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Chart mode" step 4) | none |
| Say why a decision needs no glossary change or ADR | Names the skip | Inference: silent skips look like omissions | Same | **already have**: the interview's closing restatement carries one ADR verdict line per decision, naming the admission-test part it passes or fails ([`interview/SKILL.md`](../../plugins/planning/skills/interview/SKILL.md), "ADR verdicts") | none |

### Lesson 6: Task Ticket

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Human-only setup goes to a generated wizard | The agent writes a script the person runs | Some setup only a person can do | No wayfind route named our wizard | **adapt** (Q350): task items for human-only setup route to `/wizard:generate`; the resolution records names and locations, never values | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| Secrets never reach the agent | The person enters them; the agent checks they work | Secrets in the model's context can leak | Same | **already have**: wizard prompts read only from the terminal device and the agent never runs the script ([`wizard/generate/SKILL.md`](../../plugins/wizard/skills/generate/SKILL.md)) | none |
| A long pasted key is cut off | n/a (seen in his run) | n/a | Our template read secrets with no length check | **adapt** (Q351, Q352): warn at the terminal line limit and offer a one-line file; multi-line keys are stored by path | [#15370](https://github.com/melodic-software/claude-code-plugins/pull/15370) |
| A fixed wizard library with record-keeping inputs | The agent only scopes the stages | Inference: generated scripts stay consistent | Ours had the library but no record-only input | **adapt** (Q353): record-only inputs | [#15808](https://github.com/melodic-software/claude-code-plugins/pull/15808) |
| The person clicks through a vendor console | A wizard guides every console step | The person gets lost mid-console | Same | **adapt** (Q354): an opt-in stage where the agent drives a visible browser in an isolated profile for non-secret configuration; sign-up, billing and key pages stay with the person; no PowerShell port | [#15808](https://github.com/melodic-software/claude-code-plugins/pull/15808) |
| Prove the setup worked | The agent tests the keys with a real call | A wizard can finish while the setup is broken | Ours did not require it | **adapt** (Q355): `--dry-run`, a read-back after each write, a harmless API call to prove credentials, a one-step manual fix when one stage fails | [#15808](https://github.com/melodic-software/claude-code-plugins/pull/15808) |
| Where each secret lands | n/a (owner question) | n/a | The destination was fixed | **adapt** (Q356): ask when the repository gives no signal; flag temporary keys for deletion; no key-vault writer yet | [#15808](https://github.com/melodic-software/claude-code-plugins/pull/15808) |

### Lesson 7: Prototype Ticket

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Prototype code on a branch out of main; verdict in a comment | Agents can read it without taking it for product code | Prototype code must not leak into the product | Our prototype evidence was not tied to the map's branch or its resolution | **adapt** (Q360, Q362): files go to the map's dossier branch, a folder per item; the verdict goes in the resolution comment | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open, wayfind side); prototype side not landed |
| The person found the prototype's bugs | n/a (seen in his run) | n/a | Our prototype skills handed over unproven builds | **take** (Q363): the agent proves the prototype from a clean state and hands an ordered check list | [#15794](https://github.com/melodic-software/claude-code-plugins/pull/15794) |
| Prototype items have never been used here | n/a | n/a | No map item here has carried the prototype type, and no eval routes one | **adapt** (Q361): one wayfind eval case routing a prototype item | not landed |
| Iterate until the decisions show; spend freely | Treats prototype sessions as token-heavy by design | Inference: fidelity is the point | Our prototype skills end on a durable note | **reject**: no change | none |
| Prototype against the vendor's real dev environment | Uses real sandbox keys | Inference: integration questions need the real service | Our prototypes bind invented data | **already have**: both prototype skills bind synthetic data only ([`explore-directions`](../../plugins/prototype/skills/explore-directions/SKILL.md), [`pressure-test`](../../plugins/prototype/skills/pressure-test/SKILL.md)) | none |

### Lesson 8: Finish the Map

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| A map is not done while fog remains | A last round clears the leftover fog | Deleted fog hides open questions | Our closure checked items, not the fog section | **adapt** (Q370): closure offers a mop-up interview item; an entry may be ruled out of scope explicitly | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |
| A later ticket amends an earlier decision in place | The old ticket records the amendment | Inference: one place per decision | Ours opens a superseding item and never edits the old one | **reject**: keep supersession, a fuller audit trail ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Work mode" step 7) | none |
| Out of scope is bounded to this version | A later map can bring it back | Inference: scope stays honest | Same | **already have**: the map's Out-of-scope section holds scope decisions, never fog ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Chart mode" step 3) | none |
| A whole-effort requirement becomes a Notes rule | Standing constraints live in Notes | Every session must honor it | Same | **already have**: the map's Notes ([`wayfind/SKILL.md`](../../plugins/planning/skills/wayfind/SKILL.md) "Chart mode" step 3), held to standing constraints by Q325 | none |
| Several prototype variants | Compares a few layouts at once | Inference: one variant anchors the user | Same | **already have**: [`/prototype:explore-directions`](../../plugins/prototype/skills/explore-directions/SKILL.md) builds three by default | none |
| Seeded data and list behaviors in the mockup | n/a (owner's take on his mockup) | n/a | Our mockups had no data controls | **adapt** (Q371): seed, clear and reset controls; pagination, filter and sort as toggles only when a list is in scope | [#15794](https://github.com/melodic-software/claude-code-plugins/pull/15794) |
| Feedback pinned to elements inside the prototype | n/a (owner's take) | n/a | Notes could pin only to a variant or screenshot | **adapt** (Q372): a picker for an element, text or region, a notes panel, local delivery, configurable prototype levels | not landed |
| How long the extra branches live | n/a (not stated upstream) | n/a | Ours deletes the dossier branch at map close, breaking a spec's links to its evidence | **adapt** (Q381): the branch lives until the destination's container closes; the closing comment names it | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open) |

### Lesson 9: Spec to Implement

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Map to spec to tickets to implementation | Compresses the map into a spec before ticketing | A map is too dense for an implementer | A build-set map closed straight to decompose; prd and plan could not read a map | **adapt** (Q380, Q384): build-set maps close to `/planning:plan`, then decompose; prd and plan accept a map issue as source; decompose attaches native sub-issues for a tracker source; the worker brief gains a test-first line; no new spec skill | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open, Q380), [#15805](https://github.com/melodic-software/claude-code-plugins/pull/15805) (Q384) |
| Bare issue numbers in a spec | n/a (seen in his spec) | n/a | Our real-ids rule lived in wayfind only | **adapt** (Q382): it covers prd, plan publish and decompose tracker text | [#15805](https://github.com/melodic-software/claude-code-plugins/pull/15805) |
| One command implements the whole spec in parallel | Fans tickets out to parallel agents | Inference: finish fast | Ours lands one item at a time | **already have**: [`/work-items:ship`](../../plugins/work-items/skills/ship/SKILL.md) `run`; decompose's closing line says when to run it and when to leave items for the lanes (Q385) | [#15805](https://github.com/melodic-software/claude-code-plugins/pull/15805) |

### Lesson 10: Grill vs Wayfinder vs Ship First

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| A start-of-session decision tree | A tiny diff ships; anything else starts with an interview; a map grows out of it | Inference: starting with a map that turns out simple is hard to undo | Same order already adopted | **already have**: route choice in [`/session-flow:workflow`](../../plugins/session-flow/skills/workflow/SKILL.md); Q391: no user-scope text, the interview states the quick-change skip and runs explore and research itself | [#15823](https://github.com/melodic-software/claude-code-plugins/pull/15823) (open, Q391) |
| When to graduate to a map | The session fills up or the fog grows | Same | Same | **already have**: the interview's fog trigger ([`routing.md`](../../plugins/planning/skills/interview/context/routing.md); Q300) | none |
| One home for route choice | n/a | n/a | The interview's routing and a docs page restated parts of it | **adapt** (Q390): route choice lives only in `/session-flow:workflow`; the others point to it | [#15823](https://github.com/melodic-software/claude-code-plugins/pull/15823) (open) |
| His names for the routes | Names each branch of the tree | n/a | Ours say "quick change" and "escalate" | **reject**: keep ours | none |

### Follow-ups decided in the rounds

| Follow-up | Disposition (decisions) | Landed |
|---|---|---|
| Run the plan reviewer subagent only for high or critical blast radius, a stress-test trigger or a request | **adapt** (Q303 to Q308): on low-risk plans a pre-registered before/after eval met neither loss condition but did not show non-inferiority, so the owner waived the no-loss rule for that cut only ([result](https://github.com/melodic-software/claude-code-plugins/pull/15398#issuecomment-6809407661), [re-run on frozen graders](https://github.com/melodic-software/claude-code-plugins/pull/15465#issuecomment-6811701254)); the reviewer stays on medium-risk plans, which the eval did not measure | [#15398](https://github.com/melodic-software/claude-code-plugins/pull/15398), [#15465](https://github.com/melodic-software/claude-code-plugins/pull/15465) |
| Apply the model guidance against over-verification to research | **adapt** (Q329): wayfind runs map research at `light`; a separate change proposes `light` as the research default behind a pre-registered eval | [#15784](https://github.com/melodic-software/claude-code-plugins/pull/15784) (open, wayfind side); research default not landed |

### Handed elsewhere

- Review lanes enforcing the glossary's rejected words, and agents running a failing command
  themselves (Q383): later workshops.
- Planning enough work to keep agents busy: the lanes workshops.

## License notice

The course is paid content under its provider's terms; no lesson text, caption, image or code is
copied here. The public skills repository reads MIT on the host and in
[mattpocock-skills.md](mattpocock-skills.md); no text or code from it is copied either.

- **Pointer**: when a license question arises, read the skills repository's
  [LICENSE](https://github.com/mattpocock/skills/blob/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/LICENSE).
- **As of**: 2026-11-13
- **Recheck trigger**: the skills repository's license file changes.
