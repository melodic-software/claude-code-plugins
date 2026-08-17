<!-- AI Hero course lesson (Matt Pocock, aihero.dev) — framing around his MIT-licensed
 mattpocock/skills. Committed to this WORKING branch at the user's direction (2026-08-17) as
 lane source material; lives in the topic slice and is PRUNED with it in the final PR per the
 contract-slice lifecycle — never merges to the default branch. -->

# Handing Off

<CommitMap>
  <Commit id="handoff-skill">Start the lesson: the `/handoff` skill added to `.agents/skills/`</Commit>
</CommitMap>

In the previous exercise, I showed you how [compaction](https://www.aihero.dev/ai-coding-dictionary/compaction) works: you take one [session](https://www.aihero.dev/ai-coding-dictionary/session)'s [primary source](https://www.aihero.dev/ai-coding-dictionary/primary-source), summarize it into a [secondary source](https://www.aihero.dev/ai-coding-dictionary/secondary-source), and seed a new session with it.

Compaction, though, has some constraints. It can only compact within the same directory, and it can only compact within the same [agent](https://www.aihero.dev/ai-coding-dictionary/agent).

For instance, if we did some implementation with Claude and wanted to [hand off](https://www.aihero.dev/ai-coding-dictionary/handoff) to another AI agent like Codex to review it, how would we do that with compaction? We can't.

## The /handoff skill

There is one way to do it though, and I encounter this situation so often that I made a [skill](https://www.aihero.dev/ai-coding-dictionary/skill) for it.

The theory is straightforward: instead of compacting inside the agent (in memory), you create a `handoff.md` file, a markdown file. That markdown file is totally portable. You can do anything you like with it.

- Feed it into Codex
- Pass it to an agent in another directory
- Send it to a colleague
- Use it to hand off a side task you discovered mid-feature

One really great situation is when you're working on a feature, you notice a random bug that's unrelated to what you're building, and you want to fix it later in a separate session. You can just create a [handoff artifact](https://www.aihero.dev/ai-coding-dictionary/handoff-artifact) and come back to it.

### Looking at the skill

First, run `npm run reset` and choose the handoff skill lesson from the list.

If we look inside the skill directory, we have a `/handoff` skill. Like most of my skills, it's pretty short.

```markdown
Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.
```

One useful feature here is that it saves to the temporary directory of the user's OS. This means these handoff documents are designed to be ephemeral. They're not going to be saved locally in your project, and they won't be stored in any memory. They will be deleted when your computer resets, or whenever the OS decides to clear the temporary directory.

(OS stands for operating system: Windows, Mac, Linux, whatever.)

## Using handoff in practice

Let me show you how this works. I'm going to resume a previous session and work with the star rating review system.

We're at around 89k [tokens](https://www.aihero.dev/ai-coding-dictionary/token), which might be a good moment to hand off. To use the `/handoff` skill, I'm going to run the command and pass it a reason:

```
/handoff pass to Codex to review
```

Just like with compact, we give the `/handoff` skill a reason for the handoff. This tells it the purpose of the next session.

It comes back and [requests permission](https://www.aihero.dev/ai-coding-dictionary/permission-request) to write to the temporary directory. Perfect.

Now we can see the handoff file. It's a really nice, detailed secondary source of all the things we might need to review. It looks fairly similar to the compacted documents we saw before: nice and detailed, with lots of file references and everything else.

The handoff document includes:

- What the feature is
- Files to review (with git status / git diff instructions)
- Key decisions or bugs fixed mid-session
- Known pre-existing issues (not part of this change)
- Verification already done
- Project conventions the diff should conform to
- Review angles worth probing
- Suggested skills for the next session

The way I would seed this into a new session is to open it in a separate window. I've just run `/clear`, so I've got a totally empty session. Now I can use the `@` symbol to reference the file:

```
@/tmp/handoff-course-star-ratings-review.md
```

Once this gets seeded, it gets immediately read into the [context window](https://www.aihero.dev/ai-coding-dictionary/context-window) and it's ready for review.

I'll just cancel out of that because I don't actually want it to do the review right now.

## /handoff vs. Compact

That's how the `/handoff` skill works. It's really nice for:

- Passing work to separate agents
- Saving a document you can send to a colleague
- Handing off to another agent in a different repo to fix a bug you encountered

It's just like compaction, except a little bit more flexible and a little bit more involved.

I wouldn't say that handoff is a total replacement for compaction. Here's when to use each:

| When                                             | Use                                                                |
| ------------------------------------------------ | ------------------------------------------------------------------ |
| Staying in the same directory                    | Compaction                                                         |
| Retaining context of the previous conversation   | Compaction                                                         |
| Don't care about retaining previous conversation | Compaction (especially because you can queue up messages after it) |
| Passing to a different agent                     | `/handoff`                                                         |
| Handing off to another repo                      | `/handoff`                                                         |
| Sending to a colleague                           | `/handoff`                                                         |

Compaction is still really good. `/handoff` is nice too, but the linking to the next conversation is a little bit more involved, and it's only really useful if you're getting something out of it.

We're going to do a full comparison in the next lesson. Nice work, and I'll see you there.

<Quiz>
  <QuizQuestion data={{
    id: "handoff-crosses-agent-boundaries",
    question: "You have just implemented a feature with Claude, and you want Codex to review it. How do you carry the context across?",
    correct: "handoff-file",
    answer: "Compaction only works inside the same agent and the same directory, so it cannot reach Codex at all. Letting Codex explore alone hands it the code but none of the decisions or bugs already found. A summary committed into the project would linger there - the handoff is written outside the workspace on purpose."
  }} />
  <QuizQuestion data={{
    id: "handoff-artifact-is-ephemeral",
    question: "The handoff skill asks permission to write its document. Where does that file go, and how long does it survive?",
    correct: "os-temp",
    answer: "These documents are meant to be disposable, so nothing is added to the project and nothing is written into memory for later sessions to pick up. Nor is any permanent copy kept anywhere - the file dies when your machine resets or the OS clears its temporary directory."
  }} />
</Quiz>
