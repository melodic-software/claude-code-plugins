# Lightning style

Lightning is the interview's condensed style: every question prints as a condensed entry, so a
round reads as one short list, while every gate, the assumption sweep and the full final
confirmation still run. It changes how a round prints, never what is decided or checked.

## Turning it on and off

- `interview_style` resolves once, before round 1, per
  [`../../../reference/config.md`](../../../reference/config.md) "Convention-home keys", its user
  layer named in SKILL.md "Lightning prints condensed entries": `standard` (the default) or
  `lightning`.
- `lightning` as the first argument word turns it on for the session; the words after it route as
  they would without it (`/planning:interview lightning share <topic>`).
- Said mid-interview, "lightning", "go lightning" or "speed this up" turns it on and reprints the
  current round condensed; "stop lightning" turns it off for the rest of the session, over a
  `lightning` default too. Read a reply as the switch only when the phrase is the whole reply or
  opens it; a reply that discusses lightning is an answer.
- Write the resolved style to the ledger's `## Style` section (`- lightning` or `- standard`, with
  the round it took effect) the moment it is set or switched. On resume the ledger's style wins
  over a configured default that changed since.
- `lock` and `product` ignore lightning, the word and the setting: neither has rounds to condense.
- In a shared session only the host turns it on or off.

## What a lightning round prints

The round file stays the full block for every question ("Save the full block; print it at the
detail level"), so "more Q<N>", the round check and `/planning:audit-answers` read it unchanged.
The round you send is `round.sh show --level lightning --links "<citation_links>"`, pasted
verbatim; `question_detail` does not apply. Each question prints as:

- its title line; tag a major question in the topic, `(<topic>, major)`: the problem, intent,
  vision, goals, quality bar and every consequential question
  ([`../../../context/recommendation-basis.md`](../../../context/recommendation-basis.md));
  the user re-tags with "Q<N> is major" or "not major";
- the answer line: a few-word bold answer, its basis after a dash (the `Evidence:` line), then the
  alternatives' letters and short labels, `(or: a <label>, b <label>)`, lettered from (a) as in
  the full block;
- `Flips if:`, `Second view:` and `Departs from:` on their own indented lines, and each
  `Commits you to:` part on its own line with its own id;
- a discovery or withheld question's own `No recommendation:`, `Your answer settles:` or
  `Withheld:` line in place of the answer line.

Write each question so it prints well condensed: one decision per question, a recommended answer
of a few words, and a compound decision split into `Commits you to:` parts. The round ends with
`say "more Q<N>" for the full block.`

## Under lightning

- The round cap is 8 and a whole round goes in one message, whatever `questions_per_round` and
  `question_pacing` say; a request in the session still changes either, but never past 8 in a
  shared session. No `AskUserQuestion` cards.
- Lightning is the user's request for condensed restates ("A restated open question keeps the
  whole contract"): an unanswered or drift restate prints the condensed entry. The confirmation
  restatement and recap print in full.
- "Accept all" accepts major questions too; the read-back names each major question with its
  accepted answer.
- The answer-audit offer is unchanged.
