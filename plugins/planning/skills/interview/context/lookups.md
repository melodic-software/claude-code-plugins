# Gap triage, lookups and held questions

Read this after the Step 1 survey, before round 1, and again whenever a lookup starts or returns.
It is the one home for the gap triage, the intake round, when a lookup runs and what it is
handed, which questions wait for one, when the passes around the interview run, and what a
returned fact that contradicts an answer does.
`<plugin-root>` is the placeholder SKILL.md "Spoke paths" defines.

## Gap triage before round 1

List every unknown the task depends on and sort each into exactly one kind:

- **Lookup:** a fact a source can answer, by the self-answer step
  ([`self-answer.md`](../../../context/self-answer.md)). It is never asked: it runs as "When a
  lookup runs" below says, and its result is stated with its source.
- **Discovery question:** what only the user knows and no evidence can propose: the problem and
  why it matters to them, who it is for, what is in and out of scope, where they start, where it
  heads, and the quality bar when the request does not state it and the survey holds no evidence
  for one. It is asked open (SKILL.md "A discovery question carries no recommendation").
- **Decision question:** a choice with a live alternative, asked with a recommendation once the
  discovery answers and lookups it rests on are in.

A decision the evidence leaves one viable answer is settled by evidence, not asked (SKILL.md "Record
the evidence-settled decisions as facts"), except the quality bar, which is always asked. An unknown that needs a fact before it is a
choice is a lookup now and a decision question once the lookup returns.

A doubt that a solution the request names, beside its stated problem, will cover that problem is
none of the three kinds: it goes under the Brief's `### Captured assumptions` with the condition
that would revisit it, per [`problem-framing.md`](../../../context/problem-framing.md) "Prescribed
solution", and is never a question in any round.

## The intake round

When the triage leaves discovery questions, round 1 is the intake round. It asks only those, each
registered `open` with `kind:: discovery`, and keeps the round header and the closing probe of any
round. Decision questions wait for round 2, because their recommendations rest on the intake
answers. The one exception is the quality bar when the survey holds evidence for one: it goes out
in round 1 as a decision question beside the intake questions (SKILL.md "Ask the quality bar in
round 1"), and round 1 stays the intake round for every other rule.

The problem questions of [`problem-framing.md`](../../../context/problem-framing.md) are intake
questions, asked in this round in discovery shape:

- A request that names a solution and no problem: its problem question is the rethink-or-accept
  question of "Prescribed solution" there, asked open: its title asks what problem the work
  solves, its Context names the prescribed solution and states no inferred problem for the user
  to confirm, and its `Your answer settles:` line says the answer decides whether to rethink the approach
  against that problem or accept the named solution. This is how "an attended run always asks" is met under the intake round, never by a
  second question.
- A stated problem whose evidence is only `reported`: one question asks the user to confirm the
  restated problem and to give the last concrete instance, what it cost and who hit it, as
  "Reported-only evidence" there says.

Three things still go out in round 1 and are not intake questions:

- a routing suggestion: brainstorm, prd or blindspot by SKILL.md "Intake the starting point", and
  the wayfind question of [`routing.md`](routing.md) "Round 1". Each is one plain line after the
  round's questions and before the closing probe, naming the skill, why, with its evidence label
  and source, and what yes does: `Suggested next: /planning:prd, because who uses this and how
  success is measured are not settled (your request). Say yes to run it first.` It is never a
  `My recommendation:` block, which an intake round shows only for the quality bar; the wayfind line is still
  registered at ask-time;
- a candidate for an unknown Problem field, drawn from the repository, the conversation or a
  lookup, stated with its source and a request to confirm or correct it ([`problem-framing.md`](../../../context/problem-framing.md) "Candidates
  for an unknown field");
- a fact a lookup settled, stated with its source.

When the triage leaves no discovery question (the request already states the problem, the users
and the scope), there is no intake round: round 1 is the first decision round. An empty intake
round asks nothing, so it is never sent.

## When a lookup runs and what it is handed

Each lookup is named by what it reads:

- **The repository:** `/discovery:explore` through the Skill tool when that skill is listed;
  otherwise Grep, Read and Glob inline.
- **Anything else** (vendor docs, a standard, current practice): `/discovery:research` when that
  skill is listed; otherwise a web search and fetch inline.
- **A live system** (a database, a tracker, a service): read it directly through its CLI or MCP
  tool.

A lookup one Grep or Read settles runs inline at once, whatever it reads.

Dispatch the triage's lookups before round 1 is sent, so they run while the user answers it. A
lookup a later round needs is dispatched when that round is drafted. Run at most one dispatch per
lookup skill at a time: group the lookups for one skill into one brief, and a lookup needed while
that skill's dispatch is running joins the next brief, sent when the running one returns.

Hand each brief:

- each question the lookup feeds, in words, and what about it the result would settle;
- the constraint ledger verbatim (SKILL.md "Composed artifacts are candidates");
- the settled decisions it must respect, each with its answer;
- what to return: each fact with its source, a `file:line` or a URL read in that run.

Never hand it the Brief to read as its scope, or a draft recommendation: the lookup finds facts,
and the recommender ([`../../../agents/interview-recommender.md`](../../../agents/interview-recommender.md))
draws the recommendation from them.

With no explore or research skill listed, the lookup is an inline read done before the round is
sent, so no question waits for it.

## Held questions

A question whose answer, recommendation or option set a running lookup could change is held until
that lookup returns. A lookup the user says is running elsewhere (another session, a colleague
checking) holds the same way. Ask every other question now: the hold never holds the round
([`loop.md`](loop.md) "Out-of-band drift").

A held question takes no id and no register row while it waits: the round header's `Open:` line
names it in plain words with what it waits on (`Open: the alert threshold, waiting on the
principle map`; SKILL.md "The round header"), in every round until the lookup returns. It is not
asked and gets no recommendation until then; then it is asked in full in the next message that
presents questions, which opens the next round, in the place [`loop.md`](loop.md) "Rounds" item 2
gives it, taking its `Q<N>` and its `open` row there, and leaves the `Open:` line.

A recommendation is never shown before its facts are in. A draft recommendation with no fact to
cite, or a consequential one whose `Basis:` fails the re-grounding check (SKILL.md Step 2,
"Re-ground open recommendations before they are shown"), holds its question for a lookup; one no
lookup can settle is asked withheld (SKILL.md "A withheld question carries no recommendation
marker"). A quick environment read that settles it runs inline and holds nothing.

## Passes around the interview

New work starts at the interview, and every other pre-planning pass runs from it, in one session:

- **Before round 1:** only what the starting point calls for, as a routing suggestion of the
  intake round that the user takes or leaves: `/discovery:blindspot` for territory new to the user,
  `/planning:brainstorm` or a prototype skill for an idea with no direction, `/planning:prd` for
  product work whose users or success measures are unsettled. A pass the user ran before invoking
  the interview is a settled upstream artifact the survey reads.
- **During the rounds:** explore and research only as lookups (above); a prototype as the
  mid-interview detour of [`composition.md`](composition.md) "Mid-interview composition".
- **After the confirmation gate:** `/planning:prd` when the confirmed understanding still leaves
  product intent unsettled, otherwise the SKILL.md "Next" routes. The interview routes no explore or
  research pass after the Brief, since its facts came in as lookups; design and plan run their own
  when their questions need one.

No pass clears the context before the next one; `/session-flow:workflow` decides when a session
hands off.

## A returned fact that contradicts an answer

A fact from any source (a lookup's return, the user relaying one, a later read) that contradicts an
`answered` row reopens that row under its own number. Never change the answer yourself, and never
ask the question again under a new id:

1. Write the fact and its source on one line to `<memory_dir>/<topic-slug>/reopen-Q<N>.txt`.
2. Run, on one line: `bash "<plugin-root>/surface/round.sh" reopen --ledger <memory_dir>/<topic-slug>/interview-checklist.md Q<N> --round <R> --fact-file <memory_dir>/<topic-slug>/reopen-Q<N>.txt`,
   `<R>` being the round that asks it again. It sets the row `open` with `reopened::`, moves the
   old answer and the fact to the ledger's `## Reopened answers`, and writes `recheck:: Q<N>` on
   every row whose `depends::` reaches it, printing `marked Q<M>` for each.
3. Ask `Q<N>` first in round `<R>`, its Context showing the old answer and the contradicting fact
   with its source, and name each marked row by id and plain name as resting on it, to be
   rechecked once `Q<N>` is answered again.
4. Once the user has reconfirmed or changed a marked row, run
   `bash "<plugin-root>/surface/round.sh" reopen --ledger <memory_dir>/<topic-slug>/interview-checklist.md --rechecked Q<M>`.
   The register gate blocks while any `recheck::` tag remains.

With no Bash, make the same ledger edits by hand, by the rules of `reopen` in
[`../../../surface/README.md`](../../../surface/README.md). A fact that contradicts the
recommendation of a question not yet answered is loop.md "Out-of-band drift" outcome 2, not a
reopen.
