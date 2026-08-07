# Finding Your Unknowns — Sections 96–99

Thariq Shihipar's field guide (Part 18, July 3, 2026): the map — your prompts, skills, and context — is not the territory the work happens in, and the gap between them is your *unknowns*. Organized before / during / after implementation.

## 96. The Four Unknowns — The Map Is Not the Territory

When Claude hits an unknown it decides from its best guess of what you wanted. Thariq: Fable is the first model where work quality is bottlenecked by your ability to clarify its unknowns. The Rumsfeld matrix applied to prompting: **known knowns** (what's in your prompt), **known unknowns** (what you know to ask about), **unknown knowns** (too obvious to write down, but you'd recognize it), **unknown unknowns** (what you never considered).

The best agentic coders have relatively few unknowns — they know what they want in detail and are in sync with both the codebase and the model's behavior — but they also *assume* unknowns exist. Reducing and planning for them is a learnable skill, not a talent.

## 97. Finding Unknowns Before Implementation

Most unknowns are cheapest to find before any code is written:

- **Blind spot pass** — ask Claude to surface your unknown unknowns and explain them, giving it context on who you are and what you already know.
- **Brainstorms and prototypes** — for unknown knowns (criteria you only recognize on sight, such as visual design), a reactable HTML artifact beats a description.
- **Interviews** — after brainstorming, have Claude interview you one question at a time, prioritizing questions whose answers would change the architecture.
- **References** — the best reference is source code. Point the model at a folder or a module and it reads the underlying code, not a screenshot of it.
- **Implementation plans** — ask for a plan that leads with what's most likely to change (data model, type interfaces, user-facing decisions) and buries the mechanical refactoring.

## 98. Finding Unknowns During Implementation

Planning never removes every unknown unknown; an edge case mid-run can force a different tack. Have the agent keep a temporary `implementation-notes.md` logging the decisions it makes and the deviations it takes, picking the conservative option and continuing rather than stopping. This is Section 89's move (write it down, don't re-prompt) applied mid-run: what the agent learns becomes next run's map instead of evaporating with the session.

## 99. Finding Unknowns After Implementation

Once the work lands the remaining unknowns belong to your reviewers and to your own future self:

- **Pitches and explainers** — package the prototype, the spec, and the implementation notes into one shareable doc and lead with the demo. Reviewers start with the unknowns you started with; answer them up front.
- **Quizzes** — after a long session the diff gives only light understanding. Have Claude quiz you on the change and merge only when you pass.

The capstone: the Fable launch video was edited entirely by Claude Code, in a domain the author was not expert in, by running this loop — start from what you know, have Claude explain and *teach* the parts you don't, and prototype rather than guess.
