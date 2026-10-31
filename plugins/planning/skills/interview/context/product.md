# Product stress-test (`product`)

Read this before the first question when the action resolves to `product`. It runs an interview
about a product idea, a feature idea, or a pivot, until the idea either holds or breaks. Code got
cheap; knowing what to build, for whom, and why they would switch did not, so the questions go to
the person, never to an assessment of the pitch.

## What this action changes, and what still holds

This action keeps the interview's own rules except these five, which it replaces inside the action
only:

1. **Opening.** The first reply is the first question and nothing else. The Step 1 survey still
   runs, but its "Here is what I see" paragraph is not printed; its facts feed the questions. The
   round-1 quality-bar question, the starting-point intake and its routes, the problem-first
   question, and the early session-config recommendation do not run: the Reason to exist
   principles ask for the problem, and a session-config recommendation, when one fits, comes after
   the verdict.
2. **Pacing.** One question per turn, not a frontier round. The pre-round contradiction pass and
   the assumption sweep do not run; pushing on each answer before moving on does that work here.
3. **Recommendation.** Every question carries what a strong answer sounds like, with a `Basis:`
   line citing the principle it comes from (see "Question shape"). A strong answer is a standard
   for the user's own answer, not words put in their mouth, so the withheld-recommendation rule for
   idea-stage questions does not apply.
4. **Tone.** Blunt, per "How to run it". The user asked for the idea itself to be tested, so
   SKILL.md's supportive, not-adversarial stance governs every other action, not this one.
   `/planning:devils-advocate` still owns attacking a written plan.
5. **Output.** The verdict below, in place of a PLAN.md Brief or a shared-understanding summary.
   No ADR and no glossary write; the Step 3 confirmation gate and Step 5 handoff are replaced by
   "After the verdict".

Still in force: the ledger and its open-question register. Register each question at ask-time, check
every reply against the `open` rows, and leave every person's name and email out of the ledger and
the verdict (principle 4). When the interview ends, retire each row still `open` as `deferred` and
carry it into verdict item 6, with the resolution `carried into verdict item 6`, then run the
register gate (SKILL.md Step 3) before writing the verdict. A row's round field is its turn number
(`round <N>`). A fact the pitch, the repository or a lookup already answers is stated, never asked
(SKILL.md "Facts are yours; decisions are the user's"). Ask the user only where their judgment
decides: market research goes to `/discovery:research` (if enabled), and a pile of feedback is
summarized and categorized by the agent for the user to draw conclusions from, never put to the
user as questions.

## How to run it

**Never respond to an idea with an assessment, a plan, or praise.** Respond with the first question.

- **One question per turn.** Ask it, then stop and wait. Two questions at once let the user answer the easy one.
- **Every question carries a recommended answer**: what a strong answer sounds like, in one or two lines. The user can take it, reject it, or use it to see their gap. Without it the interview is a quiz; with it, it is a working session.
- **Every question comes from one of the twenty principles.** Ask in phase order: Reason to exist, then What to build, then How to test it, then How it wins. Inside a phase, ask the principle the idea looks weakest on. Skip a principle the pitch already answered concretely. Do not skip one because the user sounds confident.
- **Push on the answer before moving on.** "Everyone" is not a user. "It's better" is not a reason to switch. "They said it was too expensive" is a story; ask for the literal words. A feature list in answer to a question about a person is a dodge; ask about the person again.
- **A fatal answer stops the phase.** No named person with the problem (principle 4), or no reason to switch that would survive great distribution (principle 2), means nothing downstream matters yet. Say so plainly, and ask only about that gap. When it is filled, resume phase order. When the user decides to go find out, or the gap is still open at the fifteen-question cap, end the interview and write the verdict, with the gap as item 3 and its cheapest test.
- **Length**: at least two questions per phase, at most fifteen questions total. Then write the verdict. A fatal answer overrides the per-phase minimum for the phases it leaves unreached.
- Be blunt. No compliments on the idea, no softening. The user asked to be grilled.

## Question shape

```text
Q<N>: <one question, from one principle>
Strong answer: <what a strong answer sounds like, in one or two lines>
Basis: reference/product-principles.md, principle <n> (<its name from the index below>)
```

`Q<N>` numbers run on across turns and match the register rows. The `Basis:` line cites the
principle by number and name in place of the `Basis: verified` fact list and `Inference:` line: a
strong answer is a standard for the user's answer, not a claim about their situation, so it has no
fact to verify. A fact the question itself states, from the pitch, the repository or a lookup,
still carries its source.

## The verdict

When the interview ends, write this, and nothing else:

1. **The one good idea**, in one sentence. If you cannot write it, that is the verdict.
2. **The chain of must-be-trues**, at most four links, in order, with the link being tested right now marked.
3. **The biggest unanswered risk**, and the cheapest test that would answer it.
4. **This month**: what gets executed at 100%, and what gets deliberately half-built.
5. **Principles the idea currently violates**, by number, one line each.
6. **What the interview did not resolve**, so the user knows what they still owe themselves.

## The twenty principles

Read [`../reference/product-principles.md`](../reference/product-principles.md) before the first
question: each principle there gives its claim, reasoning, trap, and the questions to ask with
their strong-answer shapes. Cite a
principle by its number and the name below.

**Reason to exist**

- **1.** Find the workaround. The strongest signal that people want something is that they are already contorting themselves to get it. Build the clean path to a value they are already chasing, not a value you think they should want.
- **2.** Answer "why this instead of what came before". A digitized version of the old thing gives nobody a reason to switch. Take the category apart and rebuild it around what the new medium can do.
- **3.** Say the real motive out loud. Consumer products serve one of three: make or save money, find a mate, unplug. B2B tools sell a practice, and the buyer adopts it whether they know it or not. A team that will not say which it is cannot iterate toward it.
- **4.** Build for a named person with a specific bad feeling. Not an assumption-based persona, not a feature request. A first name, an email, and the moment in their week that made them swear never again. On calls, the goal is to feel as bad as they feel. The named person is a specific person you can find, standing for a findable segment; a persona built from research with real people is valid evidence, an assumption-based one is not. The name and email stay in the conversation and never go into an artifact.
- **5.** Treat what customers say as a signal, not a finding. People soften rejection. The founder's story about why they said no hardens into a fact the strategy gets built on, and it is at least a third likely you picked the fix you are best at rather than the true one.

**What to build**

- **6.** Your product has one good idea. Count the steps to it. Every product accumulates steps between hearing about it and feeling it. Value has to land in seconds, every tap is a miracle, and you relive the fresh install on a schedule because you always find something broken.
- **7.** Absorb fifty problems, ship one solution. Responding one-to-one to requests, complaints, and competitor features adds up to a horrible product. Inside every big general request is a concentrated pool of people who mean the same thing; solve that natively.
- **8.** Think a lot instead of swinging a lot. Being able to ship ten times more does not give you ten times as many good ideas. Everything you ship you support forever and every future feature has to live with it.
- **9.** Do less, and remove the switch. Do not design it if you can extend something that exists. Build primitives that compose rather than siloed experiences. A feature is truly for everyone only when it no longer needs a mode or a toggle; keep the default simple and the power reachable.
- **10.** Let the promise pick the extreme. State the one promise your product makes. Build the most extreme version along that trait, then the extreme in the other direction, and find where they meet. The biggest decision risk is that the right option was never in the set. The right amount is too much minus one.
- **11.** Refuse the requests that trade the user's day for the buyer's report. That is how incumbents get hated. Of the ten things a deal supposedly needs, three decide it; solve those far better than anyone.
- **12.** Design the system, not the mockup. Real content is ugly, uneven, and hostile. The product has to be good with input you do not control, so every design is reviewed with real data, never with the perfect comp.

**How to test it**

- **13.** Write the chain of must-be-trues, four links at most. Validate in that order. Execute at 100% only on the link under test and deliberately half-build the rest; each extra link is another place the product can die.
- **14.** Engineer out every excuse before the test. A test you can walk away from saying "maybe the execution was bad" was not a test. Manual seeding, hand-holding, live support: those are how you test, not how you grow, and the product has to grow on its own afterward or it did not work.
- **15.** Something workable at 10% of the time, released through widening circles. Declare the first version will not be great; that is what makes it cheap. Team first, then early access, then beta, then everyone. Race to the demo, and let the vocal users take over the roadmap from there.
- **16.** Fit is binary; if you are asking, you do not have it. Working products break every few days, force new metrics, and have people fighting to get in. And interrogate whether the project matters regardless of what the status reports say; a cancelled two-year project surprised everyone but the users it never had.

**How it wins**

- **17.** The better product loses to distribution, and positioning decides who helps you. Decide who brings the users or the supply before polishing another feature. Pick the go-to-market from whether the user and the buyer are the same person. Claim the territory nobody holds and larger players will advance you to serve themselves. Growth loops stay above board, because the internet gets even.
- **18.** Quality comes from irrational investments, and speed is not its opposite. About half of what a quality team does it did not strictly have to do, and that half is what users notice first. Speed is a symptom of competence; laziness in one place spreads to every place, and products now rot within a year.
- **19.** Technical moats are comically narrow; product moats last. Build what the technology cannot yet do knowing you will throw it away. A ten-thousand-line workaround for a platform flaw means you are building the wrong thing. Be precious only about what has hardened, and ask what happens the day the platform ships your feature.
- **20.** Sell a measurable outcome, and price on it if you can. Unattributable productivity is nearly impossible to sell; a job completed autonomously is self-evident. Usage does not correlate with value. Your most common support message is your monetization roadmap.

## When the user asks a question instead of pitching an idea

Answer from the twenty. State the principle, apply it to their case, and say which question they should now be able to answer. If the question falls outside these principles (pricing tables, org design, fundraising, engineering architecture), say the principles do not cover it and answer normally, without dressing the answer up as product doctrine.

## Scope

Decisions specific to the user's own business override them where the two disagree; use this action for the reasoning underneath the decision.

## After the verdict

Recommend, never auto-invoke:

- The idea holds and is user-facing, with its users or success measures still to write down: `/planning:prd`.
- The idea holds and the user wants to compare ways to build it: `/planning:brainstorm`.
- The idea holds and its engineering contract is next: `/planning:interview`.
- The verdict's cheapest test needs something built to react to: `/prototype:pressure-test` or `/prototype:explore-directions` (if enabled).
