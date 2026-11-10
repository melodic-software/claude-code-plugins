# Scenario comparison and scenario walk

Use it when two or more candidate terms or models compete for one question (one term or two, a
status field or separate entities, where a lifecycle starts), and whenever the user asks for one on
any question. Domain experts and developers settle a model faster by saying concrete cases out loud
in each candidate's words than by comparing definitions.

## Shape

Put it in the question's Context block, before the recommendation:

```markdown
| Scenario | Candidate A: one term "Refund" | Candidate B: "Refund Request" and "Refund" |
|---|---|---|
| A learner asks for money back, support declines | "The refund was declined" | "The refund request was declined; no refund exists" |
| Support approves and the payment provider fails | "The refund failed" | "The refund failed" |
```

Then three short lines:

- **Helps:** the scenarios where a candidate says something the other cannot, or says it more
  clearly.
- **No difference:** the scenarios where both read the same.
- **Cost:** what each candidate adds (another term, another table, a migration, a word users see).

## Rules

- Three to six scenarios, drawn from the code, the request and the user's own examples; cite each
  source the way the Context block does. Invent one only to probe an edge, and say it is invented.
- One column per candidate, named with the words the candidate uses; never a column for an option
  nobody proposed.
- The comparison is evidence for the recommendation, not a second verdict: the `My recommendation:`
  line still decides, and its reason names the rows that decided it.
- On the page and on a card the table goes in the question's context; a card that cannot hold a
  table carries the three lines only.

## Scenario walk

A walk settles terms or a model that are still unsettled, one concrete case at a time, when there is
no set of candidates to compare yet.

### When to offer it

Offer it, never force it, in one line that names the unclear term, when:

- the user says something is unclear, confusing, woolly, gnarly or similar; or
- a question the interview is about to ask depends on a term the glossary does not define (read it
  through `/domain-driven-design:ubiquitous-language lookup` when that plugin is installed), or on a
  term used with two meanings.

For example: "'Booking' is used for both the held slot and the paid visit. Walk through a few
scenarios?" A declined offer is not asked again for that term.

### Shape

Number the scenarios `S1`, `S2`, and so on within one question, and put them in that question's
Context; a topic whose whole Context is its set of scenarios is one question too. Each scenario opens
with `S<N>:`, is concrete (named people, amounts, days or dates), states the outcome it tests, and
ends with its own recommendation and the term or rule that answer forces:

```markdown
S1: Priya holds a physio slot for Tuesday 10:00 and pays the 40.00 deposit; on Monday she moves it
to Thursday. Tests: is the moved visit the same booking?
(a) The same booking, rescheduled. (b) The booking is cancelled and a new one made.
Recommend (a): forces "reschedule" as an action on a booking, and the deposit stays with it.
```

The scenarios are cases built to test the terms, so the comparison's "invent only to probe an edge"
rule does not apply to them. The per-scenario picks roll up into the question's one
`My recommendation:` line ("(a) for each", or the picks listed) with its `Basis:`; the scenario
options stand in for the question's `Alternatives:`. A walk is asked in prose, never on a card.

The user answers per scenario ("S3: a"). With two walks in one round, the answer names the question
too ("Q12 S3: a").

### Recording

- The resolutions go in the resolution field of that question's register row, one per scenario
  (`S1: a, reschedule; S2: b`), with no `|` in them. A scenario gets no register row of its own, and
  its id is not the assumption sweep's `S<N>`.
- An agreed term goes to the glossary through SKILL.md's inline vocabulary update, under
  `domain_docs` like any resolved term.
- When `/visualization:visualize` is available, offer once per walk an opt-in diagram of the terms
  and their relationships; the glossary text stays the source of truth.
