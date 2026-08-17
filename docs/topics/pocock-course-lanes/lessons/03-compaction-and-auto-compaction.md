<!-- AI Hero course lesson (Matt Pocock, aihero.dev) — framing around his MIT-licensed
 mattpocock/skills. Committed to this WORKING branch at the user's direction (2026-08-17) as
 lane source material; lives in the topic slice and is PRUNED with it in the final PR per the
 contract-slice lifecycle — never merges to the default branch. -->

# Compaction

When building features with an [agent](https://www.aihero.dev/ai-coding-dictionary/agent), you eventually reach the end of the "[smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone)" - the part of the [context window](https://www.aihero.dev/ai-coding-dictionary/context-window) where your [model](https://www.aihero.dev/ai-coding-dictionary/model) works best. What happens next?

If you continue in that same [session](https://www.aihero.dev/ai-coding-dictionary/session), results [degrade](https://www.aihero.dev/ai-coding-dictionary/attention-degradation) slowly. The agent sends all previous [tokens](https://www.aihero.dev/ai-coding-dictionary/token) with every request. Those tokens are cheaper because they've been [cached](https://www.aihero.dev/ai-coding-dictionary/cache-tokens), but you're still operating in a higher latency, less capable environment.

More importantly: how many of those tokens are actually useful? A lot of them are just noise from the work itself - file reads, file writes, files in different states as you move through the project.

## The Naive Solution: Starting Fresh

One option is to totally [clear](https://www.aihero.dev/ai-coding-dictionary/clearing) the [context](https://www.aihero.dev/ai-coding-dictionary/context) and start a new session. But this comes with a hidden cost.

When you clear the context, the agent loses crucial understanding from the initial conversation. It has to re-explore and re-establish everything it knew before. You might prompt it like this:

```
we are going to do QA on the stuff that's literally just been worked on.
Can you go and explore it so you understand the reasons behind its existence?
```

The agent will do that exploration, but it's also lost some of the crucial reasoning from your initial conversation.

It can re-explore the code and re-read what you built, but that re-exploration is lossy - you've lost a lot of the actual _why_ behind what you constructed.

## Introducing Compaction

This is where [**compaction**](https://www.aihero.dev/ai-coding-dictionary/compaction) comes in. Instead of clearing the context entirely, compaction takes the context from your current session, squeezes it down, and seeds a fresh session with it.

Think of it like a [hand-off](https://www.aihero.dev/ai-coding-dictionary/handoff) between sessions that you control - similar to using a [sub-agent](https://www.aihero.dev/ai-coding-dictionary/subagent), but in reverse. The session history is summarized, then it seeds a fresh session you can continue working from.

| Approach                 | Tokens | Quality                     | Downsides                                       |
| ------------------------ | ------ | --------------------------- | ----------------------------------------------- |
| Continue current session | 156k+  | Full context, lots of noise | High latency, dumb zone results                 |
| Clear and start fresh    | ~5k    | Clean slate                 | Must re-explore everything, lossy understanding |
| Compaction               | ~28k   | Summarized context          | Lossy compression, secondary source             |

Compaction saves re-exploration. Without it, you'd spend a ton of tokens just re-discovering context you'd already established.

## How Compaction Works in Practice

In your agent, you run the `/compact` command with a summarization instruction:

```
/compact Yeah, we're going to do some QA in this area.
```

This instruction matters. The thing doing the summarization is a language model, so it needs context to highlight relevant information. Your instruction doesn't need to be detailed - one sentence is often enough.

When you launch the compaction, the agent shows a UI where it's compacting the conversation.

Here's a useful tip: you can queue messages inside the compaction UI. Once compaction finishes, your queued message runs automatically - no need to sit around waiting.

### What Gets Preserved

When compaction finishes, it outputs a summary with several key elements:

- **Primary request and intent** - what you originally asked for
- **Full agreed [spec](https://www.aihero.dev/ai-coding-dictionary/spec)** - all the decisions you confirmed
- **Key technical concepts** - important domain knowledge
- **File references** - pointers to critical files, plus some files retained verbatim
- **Errors and fixes** - what went wrong and how you solved it
- **Problem solving** - your approach and reasoning
- **All user messages** - everything you said
- **Pending tasks** - work still to do

Here's what the token compression looks like:

From the original session with ~156,000 tokens, the compaction summary reduced it to around 28,300 tokens. That 150k becomes 30k - giving you plenty of room back in the smart zone.

```
Model: claude-opus-4
Tokens: 28.3k / 1m (3%)

| Category                | Tokens | Percentage |
|-------------------------|--------|------------|
| System prompt           | 2.9k   | 0.3%       |
| System tools            | 4.5k   | 0.5%       |
| Messages                | 20.7k  | 2.1%       |
| Free space              | 971.7k | 97.2%      |
```

For example, a line from the summary might read:

```
- app/lib/comments.ts (new): MIN_COMMENT_LENGTH = 1,
  MAX_COMMENT_LENGTH = 5000 (client-safe, mirrors ratings.ts)
```

This is extremely dense compression of everything you did in that previous session.

## The Trade-off: Information Loss

Compaction isn't without downsides. Think of it using historical terms:

- The [**primary source**](https://www.aihero.dev/ai-coding-dictionary/primary-source) is your initial session - the record from people there at the time
- The **secondary source** is the summary - a historical summary, which is lossy compression of the primary source

Compaction is the first hand-off mechanism you've seen that preserves context between sessions. But all hand-off mechanisms suffer from the same issue: whenever you create a secondary source, you lose information.

However, you're gaining efficiency. Here's the trade-off:

| Approach                      | Information | Noise | Maneuverability |
| ----------------------------- | ----------- | ----- | --------------- |
| Primary source (continue)     | Full        | Lots  | Limited         |
| Secondary source (compaction) | Lossy       | Less  | More room       |

If you continue with the primary source, you have all the information but probably along with a lot of noise. If you use the secondary source, you have more room to maneuver and less space being used up, but you might lose some of the nuances from the primary source.

## When Compaction Shines

However, in the exact situation where you want to do QA on a finished piece of work, compaction is a cast-iron great place to use it. You're not re-implementing. You're not making architectural decisions. You're validating something that's already complete.

This is an introduction to compaction. You'll see how it compares to clearing and other mechanisms in upcoming lessons.

<Quiz>
  <QuizQuestion data={{
    id: "compaction-summary-is-a-secondary-source",
    question: "You compact a 156k-token session down to 28k and carry on working. What is now true of the detail from before the compaction?",
    correct: "lossy",
    answer: "Compaction squeezes the session rather than storing it, so nothing is retrievable in full afterwards. Old tokens being cheap because they are cached describes staying in the same session, which is the option you just left. And compaction writes no file - it seeds a fresh session in memory."
  }} />
  <QuizQuestion data={{
    id: "compact-instruction-steers-the-summary",
    question: "You are about to compact so the next session can QA a finished feature. What do you actually type?",
    correct: "with-reason",
    answer: "The thing writing the summary is a language model, so a bare /compact leaves it guessing which parts matter - and by the time you explain, the squeeze has happened. Pasting the full spec is wasted effort, since one sentence is enough. Clearing throws away the reasoning and forces lossy re-exploration."
  }} />
</Quiz>

# Auto-Compaction

You might be wondering: what happens if you try to push past the [context window](https://www.aihero.dev/ai-coding-dictionary/context-window) limit? Opus 4.8, which is what we're using, has 1 million [tokens](https://www.aihero.dev/ai-coding-dictionary/token) of context. What happens if you go for 1 million and 1?

If you send a [request](https://www.aihero.dev/ai-coding-dictionary/model-provider-request) to Anthropic that has 1,000,001 tokens in it, you will get an error. The [model](https://www.aihero.dev/ai-coding-dictionary/model) simply cannot process that many tokens.

Your [agent](https://www.aihero.dev/ai-coding-dictionary/agent) has built-in protections against hitting this hard limit. When you get to a certain point, it will [automatically compact](https://www.aihero.dev/ai-coding-dictionary/autocompact) your [session](https://www.aihero.dev/ai-coding-dictionary/session).

## Finding Auto-Compact in Your Agent

You can see this setting in your agent by typing the `/config` command and then searching for `auto-compact`. The matching settings appear at the top.

The relevant configuration shows:

```
Auto-compact: true
```

with a description: "Automatically compact conversation when context fills"

Auto-compaction exists in every single agent [harness](https://www.aihero.dev/ai-coding-dictionary/harness), because every harness has this problem. Every harness has a window in which, if you hit it, the system will pause your session and automatically compact what's in there.

You used to be able to see this by typing `/context` to view the autocompact buffer inside the context breakdown. But it appears that teams have made it slightly more obscure.

## Customizing the Auto-Compact Window

One interesting thing you can do is customize the auto-compact window itself. Inside your `~/.claude/settings.json` file, you can adjust when auto-compaction fires:

```json
{
  "autoCompactWindow": 250000
}
```

If you want it to automatically compact after 250,000 tokens, you can totally do that. The setting accepts values from 100,000 to 1,000,000 tokens.

## The Promise: Context Management Goes Away

The promise of auto-compaction is really quite nice. Imagine a world where you didn't have to think about phase boundaries at all, didn't have to think about the [smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone), didn't have to think about [context](https://www.aihero.dev/ai-coding-dictionary/context) at all.

This decision tree would simply not be needed:

- Continue the session
- Clear the session
- Hand it off
- Spawn a subagent
- Compact

You would just auto-compact at the right moments. In fact, you will see a lot of people online saying that auto-compaction just handles all of their problems for them.

## Why Auto-Compaction Is Actually Really Difficult

However, it turns out that auto-compaction is an incredibly difficult problem to solve. And it's really, really painful to get wrong.

### Compacting in the Middle of a Phase Is Dangerous

Think back to a typical session with a [grilling](https://www.aihero.dev/ai-coding-dictionary/grilling) phase and an implementation phase, separated by a phase boundary.

If someone forced you to put in a compact somewhere in this session, you would probably say that the safest place to do it would be at the phase boundary, between grilling and implementation.

But what would happen if you compacted in the middle of a grilling session? You'd be working with only a summary of what had been done before. What I've found when this has occasionally happened is that the agent really does lose its way quite often and just forgets stuff you were talking about just before.

The same is true in implementation, and it's often worse:

- The agent will often lose its way completely
- The second half of the implementation phase will use a totally different coding style from the first part
- It will lose its train of thought and forget features it was supposed to implement

### You Lose Control of the Handoff

There's another problem: when you automatically compact, there's no opportunity for you to say what you should compact and what the intention of the next session is going to be.

The little summarization notes that you pass to the [handoff document](https://www.aihero.dev/ai-coding-dictionary/handoff-artifact) or you pass to `/compact` are really key for getting it to compact the correct things. Auto-compaction gives you no equivalent hook.

## The Better Approach: Human Control

So will mid-phase compacting always be bad? Probably not, although it feels like it's going to be a hard problem no matter what the model is. It's a very tricky, difficult problem to solve.

My attitude in general is to increase the skill of the human instead of increasing the demand on the harness and the model. I tend to prefer the human having control of this decision tree, rather than just passing it off to the agent.

It's a one-time learning curve that the human has to go through, and it will just get you better and better results the better you get at it. More of your sessions are going to be in the smart zone and you're going to have better control.

## The Real Rule

In my opinion, if you're hitting the auto-compact buffer, if you're automatically compacting, then something is probably going wrong.

Instead, you should be in control. You should be the one deciding whether you continue the session, clear the session, hand it off, spawn a subagent, or compact.

When you own that decision, you get better code.

<Quiz>
  <QuizQuestion data={{
    id: "autocompact-firing-is-a-smell",
    question: "Halfway through implementing a feature, your session pauses and compacts itself. What should you take from that?",
    correct: "too-late",
    answer: "The harness did rescue you, but it compacted mid-phase, which is where the agent most often loses the thread. Raising the auto-compact window only moves when that happens rather than adding capacity, and the model is not the thing that failed - the phase boundary went unclaimed."
  }} />
  <QuizQuestion data={{
    id: "mid-phase-compaction-loses-the-thread",
    question: "A compaction has to happen somewhere in a session that runs grilling then implementation. Where does it do the least damage?",
    correct: "boundary",
    answer: "Cutting into implementation is often the worst case: the second half comes back in a different coding style and forgets features it was meant to build. Cutting into grilling makes the agent forget what you were discussing moments earlier. And the summary is lossy, so where it lands genuinely matters."
  }} />
  <QuizQuestion data={{
    id: "autocompact-window-is-configurable",
    question: "You want your agent to compact automatically at 250,000 tokens rather than wherever it currently fires. What do you change?",
    correct: "setting",
    answer: "autoCompactWindow is the setting that moves the trigger, and it accepts anything from 100,000 up to 1,000,000 tokens. No such compactThreshold key controls this, /compact only compacts on demand rather than setting a future trigger, and switching auto-compact off removes the automatic behaviour instead of moving it."
  }} />
</Quiz>
