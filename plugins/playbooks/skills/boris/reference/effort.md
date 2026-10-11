# Spending Your Effort: Sections 125–130

Thariq's *"Using Claude Code: Spending your effort"* (Part 25, September 25, 2026), written for Opus 5.5 and Fable 5.1 after many user questions about what effort is and when to use which level. He drew on the evals and his own runs. The levels, their defaults, and which models accept them change between releases; for the current set, see [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level) (as of 2026-10-11; recheck on a new model release or when that section changes). Pairs with Section 72 (Boris's April 2026 effort habits on Opus 4.7).

## 125. What Effort Is

*"Effort gives the model an approximation of how much compute you want it to spend on the task."* His analogy is a time budget handed to a person: given 12 hours you try very hard; given 1 hour you deliver the best version that fits and expect to iterate; or you push back that it needs 3. Higher effort means Claude takes more independent action for judgment and verification: more edge-case testing, more of its own decisions.

Two details from the article: he says the newest models respond to effort without breaking the prompt cache in Claude Code, so he varies it to the task or mid-conversation with `/effort`; and his Terminal-Bench 3.0 chart shows each step up raising both pass rate and tokens per attempt.

## 126. Pick Effort by the Job

Thariq's rule of thumb:

| Situation | Level |
|---|---|
| Sketching, brainstorming, an easy change, staying in the loop | low |
| Regular feature work | medium |
| Bugs in a brownfield codebase, edge cases, verification matters | high |
| Hard work handed off end to end, or hunting security vulnerabilities | max |

He uses low much more when he wants to stay in the loop, and max almost only when he wants zero input. His four levels leave out xhigh, which Section 72 records Boris using for most tasks on Opus 4.7; for Opus 5.5 and Fable 5.1, Thariq puts regular feature work at medium.

## 127. Effort Sets How Much Claude Decides

The same underspecified prompt ("build a personal fitness and workout tracker app") on Opus 5.5 took 1.5 minutes at low (a log and a simple graph) and 67 minutes at max (with a heat chart): more effort, more finished work, and more choices made on your behalf. A lightly specified redesign gave the same idea at every level, a rough sketch at low and a polished mockup with walkthroughs at max; he preferred low there, to see Claude's vision quickly. With a detailed spec from an interview, the levels behaved much more alike. The level depends on how in the loop you want to be. Pairs with Section 97 (interviews).

## 128. Interview, Build Low, Verify High

His feature loop: give Claude a spec and have it interview you for missing details, implement on low, review that it got the gist and iterate on low, then verify and test on high. Low keeps you in the loop while you check direction; high is where verification and edge-case testing pay off.

## 129. Effort Catches Edge Cases, Not Wrong Calls

*"Higher effort is best for tasks with lots of hidden edge cases."* On an HTML sanitizer task, Fable 5.1 went from 1 of 5 at low (one pass, one hand-written test page) to 5 of 5 at xhigh (adversarial self-review, reading the parser's source, an XSS test suite, a fuzzer). Across Terminal-Bench 3.0, Fable 5.1 at max cut "missed a case" failures from 59 to 24 but "made the wrong call" only from 133 to 107. Effort buys thoroughness, not a better approach; a wrong approach needs a better spec or a person in the loop. He adds that most tasks don't need that level.

## 130. Where Effort Pays Off

By problem area, Fable 5.1 gained most from effort in security (64% to 87%) and hardware (34% to 75%), and least in operations (12% to 22%), where the chart notes that rulebook-style work stays low. Three Opus 5.5 tasks failed every attempt at low and mostly passed at high, because high reproduced the bug first, tested against a reference or brute-force solver, or tried two data preparations and investigated why the results differed. His note on the last: with a user in the loop, Claude might have asked how to set up the problem; without one, high effort does better.
