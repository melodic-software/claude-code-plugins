# Source — "A field guide to Claude Fable 5: Finding your unknowns"

- URL: <https://claude.com/blog/a-field-guide-to-claude-fable-finding-your-unknowns>
- Author: Thariq Shihipar, member of technical staff, Anthropic
- Published: July 6, 2026
- Captured: 2026-07-24 (curl + tag-strip; site chrome removed, body text verbatim; markdown
  formatting reconstructed — emphasis, list markers, heading levels). Unedited capture:
  `raw-capture.txt` (article body is lines 179-291).

Section IDs (S1–S14) are the audit units referenced by the task list.

---

## S1 — Map and territory (opening frame)

When working with Claude Code, I'm often reminded of the difference between the map and the territory.

The map, a representation of the work to be done, is my prompts and skills and context, it's what I give Claude. The territory is where the work needs to happen, the codebase, the real world, its actual constraints.

The difference between the map and the territory is what I call unknowns. When Claude runs into an unknown, it needs to make a decision based on its best guess of what I want. The more work being done, the more unknowns Claude might run into.

Claude Fable is the first model where I find the quality of the work is bottlenecked by my ability to clarify its unknowns.

Importantly, just planning ahead isn't always enough. You can find unknowns deep in implementation, or your unknowns may point you to the fact that you should actually be solving the problem in a different way altogether.

I've found that working with Fable is an iterative process of discovering my unknowns before, during, and after implementation.

## S2 — Knowing your unknowns (the four quadrants)

What are your unknowns? When I come to Claude with a problem I tend to break it down in 4 ways:

- **Known Knowns**: This is essentially what is in my prompt. What do I tell the agent that I want?
- **Known Unknowns**: What haven't I figured out yet, but I'm aware that I haven't?
- **Unknown Knowns**: What's so obvious I'd never write it down, but would recognize it if I saw it?
- **Unknown Unknowns**: What haven't I considered at all? What knowledge am I not aware of? Do I know how good something can be?

## S3 — Unknown-reduction is the skill

The best agentic coders have relatively few unknowns. Watching someone like Boris or Jarred prompt, it is obvious to me that they know what they want in-detail. They are deeply in-sync with both the codebase and the model behaviors.

But they also assume unknowns. In many ways, reducing and planning for your unknowns is the skill of agentic coding. But luckily, this is a skill you can improve at, by working with Claude.

## S4 — Help Claude help you (specificity balance, discovery accelerator, starting point)

Instructing Claude is a delicate balance. If you are too specific, Claude will follow your instructions even when a pivot may be more appropriate. If you are too vague, Claude will often make choices and assumptions based on industry best practices that may not be a fit for your task.

When you don't account for your unknowns, you fail both ways. You don't know when the path will be filled with obstacles, and you don't know when the path will be clear, but you still want Claude to veer.

Claude can help you discover your unknowns faster. It can search through your codebase and the internet extremely quickly, and it knows much more about the average topic than you. It can also iterate from failure faster.

The most important part of this process is to give Claude context about your starting point. For example, tell it where you are in your thought process; disclose your experience with the problem and codebase; and let it work with you like a thought partner.

In this article I detail some of the patterns I use to uncover these unknowns including:

Pre-implementation:

- Blind spot pass
- Brainstorms and prototype
- Interviews
- References
- Implementation plan

During implementation:

- Implementation notes

Post implementation:

- Pitches and explainers
- Quizzes

## S5 — Pre-implementation: Blind Spot Pass

When starting work, one of the most useful things you can do is understand your blind spots. For example, if you're writing a feature in a new part of the codebase, or using Claude to help you with unfamiliar work like iterating on a design, you're likely to have a lot of unknown unknowns.

You may not know what questions to ask, what good looks like, what historical work has been done, or what potholes to avoid.

In these situations, you can ask Claude to help you find your unknown unknowns and explain them to you. I like to use the literal words "blind spot pass" and "unknown unknowns." Giving it context on who you are and what you know is usually important for Claude to understand the best way to start collaborating with you.

Example prompts:

- "I'm working on adding a new auth provider but I know nothing about the auth modules in this codebase. Can you do a blind spot pass to help me figure out my relevant unknown unknowns and help me prompt you better."
- "I don't know what color grading is but I need to grade this video. Can you teach me to understand my unknown unknowns about color grading, so that I can prompt better?"

## S6 — Pre-implementation: Brainstorms and prototypes

When I'm working in an area with a lot of unknown knowns, involving criteria I only know to define when I see it, I like to ask Claude to brainstorm and prototype with me.

It's extremely valuable to identify and verbalize unknown knowns early during prototyping, because finding them out during implementation can be (relatively) expensive. Small changes in a feature or spec can cause drastically different implementations in code, and it can be more difficult for your agent to revert previous changes.

For example, you may just want to see how a button added to a frame looks without having to wire up a backend route or maintaining additional state in the frontend.

Another example is visual design, which for me, is something that is difficult to articulate, but I know what I want when I see it. In these cases, I'll ask for several design approaches to an artifact.

I also start almost every coding session with an exploration or brainstorming phase. This helps me start with intent to define the project's scope. Claude often finds high-value approaches I would have missed, and sometimes misses the forest through the trees. Brainstorming prevents me from setting too narrow or too wide a scope.

Example prompts:

- "I want a dashboard for this data but I have no visual taste and don't know what's possible. Make me an HTML page with 4 wildly different design directions so I can react to them."
- "Before wiring anything up, make a single HTML file mocking the new editor toolbar with fake data. I want to react to the layout before you touch the real app."
- "Here's my rough problem: users churn after onboarding. Search the codebase and brainstorm 10 places we could intervene, from cheapest to most ambitious. I'll tell you which ones resonate."

## S7 — Pre-implementation: Interviews

Once I've done sufficient brainstorming, I likely still have unknowns.

In this case, I ask Claude to interview me about any unknowns or ambiguities. When asking Claude to interview you, try and give it context about your problem to guide its questions.

Example prompt:

- "Interview me one question at a time about anything ambiguous, prioritize questions where my answer would change the architecture."

## S8 — Pre-implementation: References

Sometimes you can't describe what you want in detail. For example, you might not have the language or it might be so complicated that it would take you quite a while.

In this case, the best approach is a reference. While you can include diagrams, documentation or pictures, the absolute best reference is source code.

If you have a library that implements something in a certain way or a design component you really like, just point Fable at the folder and tell it what to look for, even if it's in a different language. This provides Claude much richer detail around the markup and structure, compared to for example a screenshot.

Example prompts:

- "This Rust crate in vendor/rate-limiter implements the exact backoff behavior I want. Read it and reimplement the same semantics in our TypeScript API client."

## S9 — Pre-implementation: Implementation Plans

When I think I'm ready to implement, I tend to ask Claude to put together an implementation plan for me to review. The plan focuses on the parts that might be most likely to change such as data models, type interfaces, or UX flows. This allows Claude to surface things I might actually need to alter.

Example prompt:

- "Write an implementation plan in HTML, but lead with the decisions I'm most likely to tweak with: data model changes, new type interfaces, and anything user-facing. Bury the mechanical refactoring at the bottom, I trust you on that part."

## S10 — During implementation: Implementation notes

Once I am satisfied with my plan, I make a new session and pass any artifacts to the prompt. This gives Claude a fresh context window but with all of the information it compiled from your planning. For example, I might pass in a spec file and a prototype and ask an agent to implement it.

But the truth is that no matter how much planning you do, there are always unknown unknowns lurking. The agent may find during its work that it needs to take a different tack due to an edge case it found in the code.

I ask Claude Code to keep a temporary 'implementation-notes.md' (or .html) file where it keeps track of decisions it makes so we can learn for our next attempt.

Example prompt:

- "Keep an implementation-notes.md file. If you hit an edge case that forces you to deviate from the plan, pick the conservative option, log it under 'Deviations', and keep going."

## S11 — Post implementation: Pitches and explainers

One of the most important parts of shipping something is getting buy-in and approvals. Building pitch and explainer artifacts in the final document helps:

- Accelerate understanding when reviewers start with the same unknowns you did
- Accelerate approvals when experts want to see you accounted for the unknowns and common failure points they would have anticipated

Example prompt:

- "Package the prototype, the spec, and the implementation notes into a single doc I can drop in Slack to get buy-in. Lead with the demo GIF."

## S12 — Post implementation: Quizzes

After a long working session, Claude might have accomplished a lot more than I realized. Reading the code diffs can only give me a light understanding of what happened, since much of the behavior will depend on existing code paths.

Asking Claude to quiz me about the change after giving me a bunch of context helps me understand what happens. I only merge after I pass the quiz perfectly.

Example prompt:

- "I want to make sure I understand everything that's happened in this change. Give me a HTML report on the changes for me to read and understand with context, intuition, what was done, etc. and a quiz at the bottom on the changes that I must pass."

## S13 — How this comes together: launching Fable (worked example)

The launch video for Fable was edited end-to-end using Claude Code. This was a new domain for me and I'm by no means an expert.

So I started with what I did know. I knew that Claude could use code to edit videos and transcribe them, but I wasn't sure if it was accurate enough. I then asked Claude to explain to me how transcription like Whisper worked, and whether I would be able to accurately cut out things like ums or large pauses using ffmpeg.

I wanted Claude to create a UI that was timed with the words I was saying, but wasn't sure it was possible so I asked Claude to create a prototype video using Remotion and a transcription to see if it would work.

Finally, the video itself looked a bit muted, which I knew was the result of color grading but I didn't really know what color grading was. My first pass attempt was to try and get Claude to do a few variations to pick, but I realized that I didn't know what "good" looked like when it came to color grading. So instead, I asked Claude to teach me about color grading to discover my unknowns.

## S14 — Matching the Map and Territory (closing claims)

The better models get, the more you can achieve with the right approach. When a long-horizon task comes back wrong, it's likely you need to spend more time defining your unknowns or creating an implementation plan that allows for you and Claude to adapt through them.

Every explainer, brainstorm, interview, prototype, and reference is a cheap way to find out what you didn't know before it gets expensive to fix.

So start your next project by asking Claude to help you find your unknowns.

This article was written by Thariq Shihipar, member of technical staff, Anthropic.
