# Context Engineering for Claude 5 Models — Sections 110–115

Thariq Shihipar's *"The new rules of context engineering for Claude 5 generation models"* (Part 22, July 24, 2026), landing alongside the Opus 5 launch. Tuning Claude Code for this generation, the team removed over 80% of the system prompt with no measurable loss on coding evals. The through-line: stop over-constraining the model and let judgement work.

## 110. Give Judgement, Not Rules

Older models needed rigid guardrails against worst-case behavior — but a rule that is right 90% of the time is wrong the other 10%. Newer models read the surrounding context and decide, so hard rules were swapped for judgement. The comment guidance is the cleanest example: the rule form was "default to writing no comments, one short line max"; the judgement form is "write code that reads like the surrounding code: match its comment density, naming, and idiom." The rule was wrong everywhere comments *were* wanted; judgement handles both cases with no special case for either. Worth a mirror — most CLAUDE.md files are still walls of hard rules. Updates Section 88.

## 111. Design Interfaces, Not Examples

The old first rule for tools was to supply worked examples. With the newest models examples backfire: they fence Claude into the exploration space you happened to demonstrate. Design the interface instead and let expressive parameters teach usage. TodoWrite ships no walkthrough — its shape teaches: a `status` parameter restricted to `pending`, `in_progress`, or `completed`, plus one constraint that only one item may be `in_progress`. The enum hints at the lifecycle, the constraint defines the behavior, and no example is needed. Ask the same of your own tools, scripts, and files: how could the parameters be more expressive?

## 112. Progressive Disclosure Over Front-Loading

Don't cram everything a request *might* need into the prompt; load context at the moment it is relevant. The same principle runs through three layers: verification and code-review steps moved out of the always-on system prompt into skills Claude calls selectively; some tools use deferred loading, where the agent searches for the full definition before use so the tool costs no context until needed; and CLAUDE.md and skills work better as a tree of files loaded at the right time than as one central repository of everything.

And stop repeating yourself. Older models leaned on repetition and end-of-context reminders, so instructions got duplicated across the system prompt and the tool description. Newer models don't need it — put tool instructions in the tool description only.

## 113. Auto-Memory & Rich References

**Memory:** hand-saving context to CLAUDE.md with the `#` hotkey is no longer the mechanism — Claude automatically saves memories relevant to the work and to you and loads them across sessions. Memory, artifacts, and skills now share the job CLAUDE.md used to do alone.

**References got richer.** A spec no longer means a markdown file, and code-shaped references carry the highest fidelity: an HTML artifact beats a screenshot or a description; a function in another codebase is a portable spec; a detailed test suite is a spec that verifies itself; and a rubric encodes your taste for verifier agents in a dynamic workflow to check against.

## 114. Applying It to Your Own Context

The stack Claude assembles for a request, and what belongs in each layer: **your prompt** (the one specific thing you want now); **references** (@-mentioned files, specs, mockups, codebases, artifacts); the **system prompt** (product-tied — spend real time here only if you are building your own harness); **CLAUDE.md** (lightweight: what the repo is for, and the gotchas — skip the obvious and push detail into skills); **skills** (lightweight guides for your opinions and practices, avoiding over-constraint outside high-stakes areas); and **memory** (now automatic). When you cannot tell what to cut, `claude doctor` rightsizes skills and CLAUDE.md automatically — the context-engineering twin of `/checkup` (Section 104).

## 115. Opus 5 — And the Model That's Hardest to Inject

Opus 5 landed the same day: state of the art on coding and knowledge-work evals. Boris led not with the eval scores but with prompt-injection resistance — it is Anthropic's least prompt-injectable model yet, and layering strong model alignment, prompt-injection probes, and auto mode drives attack success to roughly zero. That is the foundation the new rules stand on: judgement-based context engineering only works if the model can be trusted to reconcile conflicting, attacker-adjacent context safely. Pairs with Section 90.
