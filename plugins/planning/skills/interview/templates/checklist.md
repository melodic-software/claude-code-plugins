# /planning:interview Checklist

Copy the `Planning version:` line, `## Steps` and `## Open-question register` into `<memory_dir>/<topic-slug>/interview-checklist.md` (default `.work/`; the topic's memory slice). Tick each step as it completes; a resuming session reads the unticked boxes to know where to continue.

Every other section is added when its first entry is written, never as an empty heading, under the heading and in the line shape below; the rules for each are in `context/loop.md` unless named otherwise:

- `## Constraint ledger`: one line per constraint, `C<N> | confirmed|inherited | <constraint> | <source>`, numbered contiguously ("Constraint ledger").
- `## Starting point`: one line, what the user disclosed at intake about where they start (SKILL.md "Intake the starting point"); `/planning:wayfind chart` carries it into its map's Notes (`context/routing.md` "The handoff to wayfind").
- `## Problems`: one line per problem the questions serve, `P<n> | <one-line problem> | proposed|agreed`, numbered from P1 (`context/routing.md` "Problems").
- `## Terminology matrix`: a `| Term | Definition | Source | Status |` table, one row per sourced term the rounds rely on, `proposed` until the user confirms its restatement, then `agreed` ("Terminology matrix").
- `## Glossary lookup`: one line for the glossary read, naming the glossary and the terms it held or lacked, or `none found` with the paths searched, or `off (domain_docs)`. The Step 4 cross-check fails without it.
- `## Self-answered facts`: one line per decision or fact settled without asking, `F<N> | answered-from-<tag> | <question> | <fact> | <basis>`; it takes no `Q<N>` ("Self-answer gate").
- `## Assumption sweep`: before each sweep, `sweep <M> | register through Q<N>`; then one line per item, `S<N> | sweep <M> | <category> | <class> | <source> | <disposition>`, the `S<N>` ids running on across sweeps and identical items merged (`context/assumption-sweep.md` "Disposition"); a sweep that returned nothing gets `none`.
- `## ADR outcomes`: one line per answered decision, `Q<N> (<decision>) | record: <why>` or `| declined: <reason>` (or `| ADR candidate, not checked`); a closing `every other decision | declined: <reason>` line covers the rest (SKILL.md "ADR outcome lines"). The Step 4 cross-check fails on an answered row no line covers.
- `## Round counts`: `round <N> | opened <a> | closed <s>`, written by `round.sh next-id --round` and `scope-check`, one line per round, never by hand.
- `## Reopened answers`: `Q<N> | round <N> | was: <old answer> | fact: <the fact and its source>`, written by `round.sh reopen` (`context/lookups.md`).
- `**Session shorthand:**`: one `<term>: <definition>` line per coinage ("Session-shorthand glossary").

Each line in those sections is an unfenced `- ` list item.

Planning version: <the `version` in `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`>

## Steps

- [ ] Step 1: Survey before you ask. Read existing context, the topic's memory slice, conversation history; identify what's already settled
- [ ] Step 1.5: Auto-detect (default action only). If intent already crisp from survey, route to direct synthesis (skip Q&A loop); `lock` and `scope` skip it
- [ ] Step 2: Drive the rounds loop. Before round 1, sort every unknown into a lookup, a discovery question or a decision question (`context/lookups.md`); an intake round asks only the discovery questions, open, plus the quality bar as a decision question when the survey holds evidence for one. Each round asks up to `questions_per_round` ready questions as one numbered set in **inline prose** (`AskUserQuestion` only via the `use_ask_user_question` opt-in; `lock` asks only its one problem question), ids from `round.sh next-id`, recommendations from one blind `interview-recommender` dispatch, questions a running lookup could change held; order rounds by blast radius. Skipped when auto-detect routes to direct synthesis
- [ ] Step 2 exit: Assumption sweep (`auto` with a register, the `auto` Mixed path included; not `lock`, not a ship-it exit). Once no open question remains ready to ask, a fresh-context sub-agent reports every undecided detail, hidden default, contradiction, unasked inherited constraint, hedged or free-text row, coined term, and unstated value, and the disposition pass filters them: each becomes a register row at the next `Q<N>` or a stated fact, and an `open` row returns the run to Step 2; every item is recorded in `## Assumption sweep` with its disposition (`context/assumption-sweep.md`). When skipped, tick the box anyway with `SKIPPED: <reason>` appended (for example `SKIPPED: lock`, `SKIPPED: ship-it`): the `--procedure` gate fails on an unchecked `Step <N> exit` box and needs the `## Assumption sweep` section for a ticked one without that marker
- [ ] Step 3: Recognize the stop condition. The open-question register grades clean (`check-open-questions.sh` exits 0; skipped only when the run asked no question at all and so wrote no register), no question is left to ask (every unknown the task depends on resolved or captured as a named assumption) and the user has confirmed the restated shared understanding, which carries the register recap and the `--procedure` check's result (`auto`, direct synthesis included; `lock` confirms the problem with one question, registered like any row; its invocation confirms the rest)
- [ ] Step 4: Persist the Brief. Engineering: write the PLAN.md Brief section with goal + constraints + acceptance criteria + captured assumptions; general: write the shared-understanding summary, never a Brief (the Q&A path persists each answer as it locks in, so the session can continue elsewhere at any round boundary with nothing lost)
- [ ] Every round boundary: bigger-than-you-thought check (`context/routing.md`). The `Wayfind:` line `round.sh` prints when the last two rounds each opened more questions than they closed → recommend `/planning:wayfind chart`; a worsened context zone with no such fog → recommend routing the continuation with `/session-flow:workflow`, never wayfind; at the confirmation, topics left over → one line suggesting `/planning:wayfind chart`. Recommend only; the user decides
- [ ] Step 5: Hand off. Engineering: recommend the next skill (`/planning:design` for engineering-internal, since exploration and research ran as lookups during the interview; chain after `/planning:prd` for product-driven); general: deliver the summary and stop, no pipeline handoff. Both: recommend model / effort / advisor per the live-doc-sourced session-config guidance (never a pinned model name). Engineering configures the **downstream execution session** it hands off to; general/terminal configures the **current/next session**, applied now (nothing downstream exists), first surfaced early, post-survey, so it could shape the rounds themselves; here refresh it and, if raised only now, offer to re-evaluate the result under the raised config

## Open-question register

**Write a row the moment a round is asked, before any reply arrives.** The register is a byproduct of asking, not of resolving: a question that only lands on disk once it is answered cannot record the failure of never being answered. Only a question put to the user takes a `Q<N>`: a fact or an evidence-settled decision is an `F<N>` line, a held question takes its id when it is asked, and a sweep item keeps its `S<N>` until it becomes a question. Statuses: `open` | `discussing` (the user asked to talk it through; blocks like `open`; `context/loop.md` "Discussing") | `answered` | `deferred` | `withdrawn` | `blocked` | `superseded-by-plan` (set by `/planning:plan` when a plan change displaces an answer, resolution `plan proposes: <new>; was: <old>`; not terminal; row shape and how it clears: `context/loop.md` "Superseded by plan"). `Q<N>` matches the terminal numbering and runs continuously across rounds; an intended gap needs a hand-written `- gap | Q<a>-Q<b> | <why these ids have no row>` line in this section. A resolution may end in tags, in this order: `kind:: discovery`, `problem:: P<n>`, `depends:: Q<a>, Q<b>`, `reopened:: round <N>` and `recheck:: Q<a>` (`round.sh reopen` writes the last two), and `topic:: <plain words>`, the topic the question's title names, on every row (rules: `context/loop.md` "Register tags").

Each `Commits you to:` part of a recommendation is a row of its own with `(part of Q<N>)` in the question field, numbered right after its headline when asked with it, and at the next free id when registered after later ids exist. Resolution rules: `context/loop.md` "Commitment rows"; late numbering: "Commitment rows written after later ids exist". On the page surface, the parts are the question's `commits` entries instead (see `context/loop.md` "Commitment parts on the page"). The page exports each row's resolution as named fields and every older grammar still imports (`context/surface.md` "Start and stop").

Register rows are unfenced `- Q<N>` list items. A fenced block in this section is the schema illustration, not data: the gate ignores fenced rows by design. Replace the example rows with this run's questions, deleting them before the first `round.sh next-id` or `scope-check` call, since both count every row they find; keep every live row unfenced and in this section, above any heading (a sub-heading ends the section, and the gate fails a row outside it).

- Q1 | answered | round 1 | Who can write comments? | enrolled + instructor + admin; topic:: permissions
- Q2 | open | round 1 | What content format? | topic:: content
- Q3 | deferred | round 2 | Moderation model? | post-V1, also in the Brief's Deferred questions; topic:: moderation

```text
- Q1 | answered | round 1 | Who can write comments? | enrolled + instructor + admin; topic:: permissions
- Q2 | open | round 1 | What content format? | topic:: content
- Q3 | deferred | round 2 | Moderation model? | post-V1, also in the Brief's Deferred questions; topic:: moderation
```

Gate twice, and a non-zero exit halts either time:

```bash
# Step 3, before locking the Brief (it is not written yet).
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" \
  --ledger <memory_dir>/<topic-slug>/interview-checklist.md --procedure

# Step 4, right after writing the Brief (engineering sessions only).
# On a page-surface run, add: --surface '<data_dir>'
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" \
  --ledger <memory_dir>/<topic-slug>/interview-checklist.md --procedure \
  --brief <memory_dir>/<topic-slug>/PLAN.md
```
