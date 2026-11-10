# Scenario comparison

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
