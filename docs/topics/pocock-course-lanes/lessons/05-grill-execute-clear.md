<!-- AI Hero course lesson (Matt Pocock, aihero.dev) — framing around his MIT-licensed
 mattpocock/skills. Committed to this WORKING branch at the user's direction (2026-08-17) as
 lane source material; lives in the topic slice and is PRUNED with it in the final PR per the
 contract-slice lifecycle — never merges to the default branch. -->

# The Grill-Execute-Clear Loop

<CommitMap>
  <Commit id="grill-me-skill">Start the lesson: the `/grill-me` skill added to `.agents/skills/`</Commit>
  <Commit id="lesson-comments">See my solution: lesson comments built from the grilled spec</Commit>
</CommitMap>

Before you start building features, you need to understand what you're building. Most developers skip this step and rush straight into coding, which leads to wasted time and solutions that don't quite fit the problem.

The `/grill-me` [skill](https://www.aihero.dev/ai-coding-dictionary/skill) forces you to pause. It interviews you relentlessly until you reach a shared understanding of what you're trying to build. Only then do you implement.

This is the grill-execute-clear loop. You [grill](https://www.aihero.dev/ai-coding-dictionary/grilling) until you understand. You execute the solution. You [clear](https://www.aihero.dev/ai-coding-dictionary/clearing) your mind and move to the next feature.

## The Grilling Skill

The grilling skill works by building a design tree. Every decision branches into the decisions that hang off it.

It asks questions in rounds. The frontier is every decision whose prerequisites are already settled. The skill asks the whole frontier at once, then waits for your answers.

As you answer, the frontier expands. New questions unlock. Previously blocked decisions become answerable.

The [session](https://www.aihero.dev/ai-coding-dictionary/session) ends when the frontier is empty: every branch visited, nothing left silently assumed. Only then should you implement.

## Your Task

Build lesson comments for the course platform. Students and instructors should be able to comment on individual lesson pages.

Imagine browsing to a lesson like "Connecting to a Database" or "CRUD Operations". On that page, students should be able to ask questions, share insights, and discuss the lesson content with other students and instructors.

This is deliberately open-ended, just like the previous exercise with course star ratings. But this time, instead of rushing to implement, you're going to use `/grill-me` to explore the feature space first.

The skill will ask you questions like:

- Who can comment? Only enrolled students? Instructors too?
- Can users edit or delete their own comments?
- Should comments be threaded, or flat?
- Do comments need moderation?
- Should users get notifications when someone replies?

You might not have thought about all of these. That's the point. The grilling process surfaces the decisions you need to make before you write any code.

## Steps To Complete

### Get the Skill

- [ ] Run `npm run reset` to pull in the `/grill-me` skill

This brings the repository up to the current lesson's commit, which includes the grilling skill in your `.agents/skills/` directory.

### Invoke the Skill

- [ ] Clear your terminal and run your [agent](https://www.aihero.dev/ai-coding-dictionary/agent)

In your agent [harness](https://www.aihero.dev/ai-coding-dictionary/harness), you'll invoke the skill differently depending on your setup. In agent code, it's typically `/` followed by the skill name.

- [ ] Type `/` to open the skill picker, then select `grill-me`

This invokes the grilling skill and puts you into interview mode.

### Start the Discussion

- [ ] Write a loose, non-comprehensive prompt about lesson comments

You don't need to be thorough here. The agent will ask clarifying questions.

```
/grill-me
I want to add comments to lessons so students can ask questions and discuss.
```

This kicks off a discussion. The agent will start building the design tree and asking about the decisions that hang off this feature.

### Work Through the Grilling

- [ ] Answer each round of questions as the agent asks them

The agent will ask multiple questions per round. Answer them all before the next round begins. Your answers reshape the design tree and unlock new questions.

- [ ] Keep going until the frontier is empty

When the agent says the session is done and you've reached a shared understanding, you're ready to implement.

This might take many rounds. That's the point. You're thinking through the problem before you code it.

### Implement the Feature

- [ ] Once you have a shared understanding, implement lesson comments

Now that you know what you're building, write the code.

- [ ] Test your implementation in the browser

Students and instructors should be able to comment on lesson pages. The comments should persist and be visible to other users.

### Verify Your Work

- [ ] Run the app and navigate to a lesson page

Pick a course you're enrolled in. Find a lesson like "Connecting to a Database" or "CRUD Operations".

- [ ] Add a comment as a student

Your comment should appear on the page.

- [ ] Switch users and verify the comment is visible

The comment you added should be visible when you switch to a different user and return to the same lesson.
