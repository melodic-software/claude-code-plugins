<!-- AI Hero course lesson (Matt Pocock, aihero.dev) — framing around his MIT-licensed
 mattpocock/skills. Committed to this WORKING branch at the user's direction (2026-08-17) as
 lane source material; lives in the topic slice and is PRUNED with it in the final PR per the
 contract-slice lifecycle — never merges to the default branch. -->

# Why Plan Mode Sucks

In our previous lesson, we saw how an [agent](https://www.aihero.dev/ai-coding-dictionary/agent) behaves under normal conditions. The results were not great. What really troubled me was the pattern: the agent prompted, explored the codebase, then immediately began implementing.

There was no verification with us about whether it was building the right thing. There was no attempt at alignment between the AI and us.

In that run, we were actually lucky. The agent built the thing we wanted pretty well. There were some issues and a critical bug, but it worked. However, this rush to create an asset is really dangerous in AI and something I always try to slow down.

## Plan mode: a buffer between exploration and implementation

Most agents ship with something called [**plan mode**](https://www.aihero.dev/ai-coding-dictionary/agent-mode). The intention of plan mode is to have a planning [session](https://www.aihero.dev/ai-coding-dictionary/session) before any work is done. This planning session creates a plan document that you read, review, and then decide whether to continue (maybe with modifications). Only when you're happy with the plan do you proceed.

Let me show you how this works in practice.

```bash
npm run reset
```

This resets the codebase to the main branch, clearing out the existing course rating implementation from the previous lesson.

Next, I'll open up the agent and enable plan mode by cycling through the [permission modes](https://www.aihero.dev/ai-coding-dictionary/permission-mode) using `shift+tab` until the input footer reads "plan mode on".

Now I'll paste in the original prompt:

```
I would like to create a course review system where students can review courses by leaving a star rating. We don't want to add written reviews, just star rating. These reviews will then be visible everywhere that courses are visible. We want to show the average rating on the courses in the list page and on the course page itself.
```

After submitting, the agent should explore the codebase to understand the structure, then come back with a plan. This plan mode acts like a little buffer between exploration and implementation. A moment where we can align before continuing.

## The plan it generates

Now the agent has finished exploration and is writing the plan. This is roughly how most agents handle plan mode. The behavior is similar across different tools.

I can view the plan by typing `/plan`:

This gives me a quite detailed output of everything the agent is going to do, along with some key decisions:

- **One user per rating per course** - makes sense
- **Averages are computed on read** - looks fine
- **Empty state:** courses with zero ratings show "No ratings yet" rather than zero stars - makes sense
- **Who can rate:** enrolled users only - makes sense

## The critical issue: plan mode is still rushing

Here's the problem: instead of rushing to create an implementation, the agent rushed to create a plan which reads exactly like the implementation would.

It's given me the exact implementation it's going to do:

- Database table structure
- Service names and functions
- Component names
- Route modifications
- Testing strategy

It's still rushing to create an asset. The plan is the asset now, not the code.

## The root cause: sycophantic trait of agents

This feeling of premature completion, of rushing to get to the end, is a [sycophantic](https://www.aihero.dev/ai-coding-dictionary/sycophancy) trait of agents. When you tell it you want to produce something, it will go produce that thing.

It won't necessarily stop to make sure it's done the legwork to ensure you're aligned on how it should look.

This is really bad because it leads to a failure mode that happens constantly: the agent builds the wrong thing.

On a relatively simple feature like course ratings, it doesn't matter too much. But on a more complicated feature, it really matters.

## What this means in practice

Imagine if a human developer behaved this way. They just said, "Yes, I know how to build that," and they went ahead and did it. There would be no alignment whatsoever. There would be no sense of a shared understanding being developed.

In the book ["The Design of Design"](https://www.amazon.co.uk/Design-Essays-Computer-Scientist/dp/0201362988) by Frederick P. Brooks Jr. (the author of "The Mythical Man-Month"), there's a concept called the [**design concept**](https://www.aihero.dev/ai-coding-dictionary/design-concept).

A design concept is not an asset. It's the concept floating around in the room when humans are designing something. Everyone has a slightly different idea of it, but as conversations develop and you work towards understanding what you're building, everything starts to sharpen.

In both plan mode and the version we saw before, there's no design concept here. There's no moment to check in with each other to make sure we're actually aligned on what we're building.

We got an okay result the first time we ran it, but I guarantee on more complex features, this would quickly go wrong.

## A different approach

The approach I've designed tries to sidestep this issue. It takes away the sycophantic asset rush. What you end up with, I hope, is a feeling of greater alignment with the agent - like you're both on the same page.

I'm going to explain that in the next lesson.

<Quiz>
  <QuizQuestion data={{
    id: "plan-mode-rushes-to-an-asset",
    question: "You run a feature request in plan mode. The agent explores, then hands back a plan naming the database table, the service functions, the components and the testing strategy. What is wrong with that?",
    correct: "asset-rush",
    answer: "The agent did explore first, and the plan is anything but vague - it is extremely specific, and you are free to modify it before continuing. That specificity is the problem: the decisions are already made and written down before any shared understanding was built with you."
  }} />
  <QuizQuestion data={{
    id: "sycophancy-drives-premature-completion",
    question: "You name a thing you want, and the agent goes and produces it without ever stopping to check that you agree on what it should look like. Which agent trait is this?",
    correct: "sycophancy",
    answer: "Nothing here is invented, so it is not hallucination. The behaviour is consistent rather than varying run to run, so it is not non-determinism, and it shows up immediately rather than after a long session, so it is not focus fading. It is the agent agreeing and delivering instead of aligning."
  }} />
  <QuizQuestion data={{
    id: "design-concept-is-not-an-asset",
    question: "You and a colleague talk a feature through until you both picture it the same way, and nothing is written down. What do you have?",
    correct: "design-concept",
    answer: "A spec and a plan are both assets - the thing here is deliberately not one. Nor is it worthless for being unwritten: the sharpening of that shared picture through conversation is exactly the step plan mode skips when it jumps straight to a document."
  }} />
</Quiz>
