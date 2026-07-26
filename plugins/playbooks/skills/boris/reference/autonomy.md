# Autonomy & Opus 4.7 Era — Sections 61–77

Tips from Boris Cherny's Parts 10–12 threads (Apr 14 – May 12, 2026): Opus 4.7 launch, scheduled/event-driven runs, context hygiene, autonomous workflows, `claude agents` control plane, `/goal` Ralph-loop completion conditions.

## 61. Routines — Scheduled & Event-Driven Claude Code

Configure a routine once (prompt, repo, connectors), and it runs on a schedule, from an API call, or in response to a GitHub event. Runs on Anthropic infrastructure — no laptop needed.

Triggers:

- **Schedule** — cron expression
- **GitHub event** — PR opened/merged, release published, issue opened
- **API** — POST to a webhook URL with token

Connectors: GitHub, Linear. Each routine gets its own API endpoint — point alerts, deploy hooks, or internal tools at Claude directly.

Use cases: POST oncall alert payload to routine's webhook, Claude finds owning service and posts triage summary. PR quality checks on opened PRs. Release notes on release-published events.

Research preview announced Apr 14, 2026.

Source: [@claudeai status 2044095086460309790](https://x.com/claudeai/status/2044095086460309790)

## 62. Rewind Over Correcting

The single habit that signals good context management is rewind, not correction.

When Claude goes down a wrong path, don't type "that didn't work, try X instead." That keeps the failed attempt in context, pollutes the window. Instead:

- Double-tap Esc (or run `/rewind`)
- Jumps back to a previous message, drops everything after it
- Re-prompt with what you learned: "use approach C, not A/B"

The math:

- Correcting: context = file reads + failed attempt + correction + fix
- Rewinding: context = file reads + one informed prompt + fix

Also: `"summarize from here"` has Claude summarize learnings into a handoff message before rewinding — a note from the next iteration of Claude to its past self.

Source: [@trq212 status 2044548257058328723](https://x.com/trq212/status/2044548257058328723)

## 63. /compact vs /clear — Know the Difference

Two ways to shed weight from a long session. Feel similar; behave very differently.

**/compact — lossy LLM summary:**

- Claude summarizes the conversation, replaces history with the summary
- Cheap, keeps momentum, details can be fuzzy
- You're trusting Claude to decide what mattered
- Steer with a hint: `/compact focus on the auth refactor, drop the test debugging`

**/clear — hand-written brief:**

- You write down what matters ("we're refactoring the auth middleware, constraint is X, files are A and B, we've ruled out approach Y")
- Precise. You decide what carries forward
- More work, but context is exactly what you chose

Rule of thumb: genuinely new task → `/clear`. Related task where you still need some context → `/compact` with a hint.

Bad compact warning: autocompact fires mid-task and can summarize wrong things (e.g. finishes summarizing a debugging thread right before you ask about a different warning it glossed over). Proactive `/compact <hint>` avoids this.

Source: [@trq212 status 2044548257058328723](https://x.com/trq212/status/2044548257058328723)

## 64. Lower Your Auto-Compact Threshold

Context rot — model performance degrading as context grows — kicks in around 300–400k tokens on the 1M context model. Set autocompact threshold to force earlier compaction, effectively lowering your context window.

```bash
# 400k is Thariq's recommended compromise
CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 claude
```

Why this works: stays below the rot zone while still getting most of the 1M benefit. Context windows are a hard cutoff — near the end, you're forced to compact. Forcing it earlier means compaction happens while the model is still sharp.

Pair with proactive `/compact <hint>` when you feel bad-compact risk.

Docs: [Claude Code settings](https://code.claude.com/docs/en/settings)
Source: [@trq212 status 2044548257058328723](https://x.com/trq212/status/2044548257058328723)

## 65. Delegation over Guidance (Opus 4.7)

Mental model shift from Cat Wu (Apr 16, 2026) on Opus 4.7 in Claude Code:

> "The model performs best if you treat it like an engineer you're delegating to, not a pair programmer you're guiding line by line."

**Old workflow:** describe step, watch output, correct, describe next step. High interrupt frequency. Always in the loop.

**New workflow:** write a crisp brief, launch Claude, come back when it's done (or asks a real question). Fewer interruptions, more autonomous runs, higher quality output.

When Claude asks too many clarifying questions or goes off-track, that's usually a signal your brief was incomplete — not that the model needs more hand-holding. Invest in the upfront brief (see tip 66), let Opus 4.7 do its thing.

Source: [@_catwu status 2044808533905178822](https://x.com/_catwu/status/2044808533905178822)

## 66. Full Task Context Upfront

The delegation model (tip 65) only works if Claude has what it needs. Cat's second tip:

> "Give Claude Code your full task context upfront: goal, constraints, acceptance criteria in the first turn."

The three things to include:

- **Goal** — what success looks like in plain language
- **Constraints** — non-goals, things not to touch, perf/API contracts
- **Acceptance criteria** — how you'll verify the work is done right

Example:

```text
Goal: add rate limiting to the /api/login endpoint

Constraints:
- don't modify the DB schema
- keep the existing auth flow unchanged
- use Redis (already configured)

Acceptance criteria:
- 5 req/min per IP, returns 429 on limit
- existing tests still pass
- new test case for the rate-limit behavior
```

With all three, Claude plans around the full problem space. With just "add rate limiting," it makes assumptions you'll correct later — every correction costs context.

Source: [@_catwu status 2044808533905178822](https://x.com/_catwu/status/2044808533905178822)

## 67. xhigh — New Default Effort for Opus 4.7

Opus 4.7 in Claude Code defaults to `xhigh` — a new effort level beyond the low/medium/high/max scale tip 34 describes. Model reasons longer before acting, pairing with the delegation shift: think harder once, rather than iterate fast and bounce back to you.

```bash
# check or change the effort level
$ /effort
```

**Why xhigh is the new default:** xhigh effort + full-context brief = one-shot completion of bigger tasks than previous Opus models could handle. The default change signals Opus 4.7 is expected to run more autonomously — benefits from more reasoning tokens upfront.

Drop it down for speed over depth, or leave it alone for most work. Available through `/effort` like other levels.

Source: [@_catwu status 2044808533905178822](https://x.com/_catwu/status/2044808533905178822)

## 68. Auto Mode + Parallel Claudes (Opus 4.7)

Opus 4.7 loves complex, long-running tasks — deep research, refactoring code, building complex features, iterating until it hits a performance benchmark. Previously you babysat permission prompts or used `--dangerously-skip-permissions`.

Auto mode routes permission prompts to a model-based classifier. Safe = auto-approved. No more babysitting.

**The real unlock:** run more Claudes in parallel. Once a Claude is cooking, switch focus to the next. Auto mode + worktrees = a fleet of autonomous Claudes, each on its own task.

Shift-tab in the CLI, dropdown in Desktop or VSCode. Available for Max, Teams, Enterprise.

Source: [@bcherny status 2044847849662505288](https://x.com/bcherny/status/2044847849662505288)

## 69. /fewer-permission-prompts — Tune Your Allowlist

Skill scans session history for common safe bash and MCP commands that triggered repeated permission prompts. Recommends commands to add to your permissions allowlist.

```bash
/fewer-permission-prompts
```

Tune permissions to avoid unnecessary prompts, especially without auto mode.

Source: [@bcherny status 2044847851591856461](https://x.com/bcherny/status/2044847851591856461)

## 70. Recaps — Know What Happened While You Were Away

Shipped alongside Opus 4.7. Recaps are short summaries of what an agent did and what's next. Useful when returning to a long-running session after minutes or hours.

Example:

```text
recap: Fixing the post-submit transcript shift bug.
The styling-flash part is shipped as PR #29869 (auto-merge on).
Next: I need a screen recording of the remaining horizontal rewrap
on cc -c to target that separate cause.
```

Pairs naturally with auto mode — launch Claude, switch focus, come back, see what happened immediately. Disable in `/config`.

Source: [@bcherny status 2044847853030580247](https://x.com/bcherny/status/2044847853030580247)

## 71. Focus Mode — See Only the Final Result

Boris: "I've been loving the new focus mode in the CLI, which hides all the intermediate work to just focus on the final result. The model has reached a point where I generally trust it to run the right commands and make the right edits. I just look at the final result."

```bash
/focus
```

Toggle on/off. Natural complement to auto mode — one removes permission prompts, other removes visual clutter.

Source: [@bcherny status 2044847855006024147](https://x.com/bcherny/status/2044847855006024147)

## 72. Effort Mastery — xhigh, max, and Adaptive Thinking

Opus 4.7 uses adaptive thinking instead of fixed thinking budgets. Model decides when thinking is beneficial — less overthinking, smarter resource use.

Boris's setup: "I use xhigh effort for most tasks, and max effort for the hardest tasks."

The effort scale: low → medium → high → xhigh → max (Speed ← → Intelligence)

**Key detail:** Max applies only to current session. All other effort levels (including xhigh) are sticky and persist for next session too.

To steer thinking without changing effort level:

- Harder problems: "Think carefully and step-by-step before responding; this problem is harder than it looks."
- Save tokens: "Prioritize responding quickly rather than thinking deeply. When in doubt, respond directly."

`/effort` to set your level.

Source: [@bcherny status 2044847856872546639](https://x.com/bcherny/status/2044847856872546639)

## 73. /go — Verify, Simplify, Ship

"Give Claude a way to verify its work. This has always been a way to 2-3x what you get out of Claude, and with 4.7 it's more important than ever."

Boris's workflow: "Many of my prompts look like 'Claude do blah blah /go'."

`/go` is a skill that has Claude:

1. Test itself end-to-end using bash, browser, or computer use
2. Run the /simplify skill
3. Open a PR

Verification by domain: backend → start server/service end-to-end; frontend → Claude Chromium extension; desktop apps → computer use.

"For long running work, verification is important because that way when you come back to a task, you know the code works."

Source: [@bcherny status 2044847858634064115](https://x.com/bcherny/status/2044847858634064115)

## 74. What Changed from 4.6 — Three Behavioral Shifts

Upgrading from 4.6? Three changes matter. Don't assume old habits carry over.

**1. Calibrated response length.** Shorter answers for simple queries, longer for open-ended analysis. Want specific length or style? Say so explicitly.

**2. Less automatic tool usage.** 4.7 reasons more instead of immediately calling tools. Provide explicit guidance on when and why to use tools if Claude isn't reaching for the right ones.

**3. More judicious subagent spawning.** 4.7 doesn't fan out on its own as much. For "refactor across 40 files" tasks, explicitly request parallel subagents. Anti-pattern: don't spawn subagents for refactoring a single visible function.

Source: [claude.com blog — best-practices-for-using-claude-opus-4-7-with-claude-code](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)

## 75. Task Completion Notifications

Auto mode + focus mode = less time watching Claude work. Set up notifications so you know when it finishes:

- **Sound alert** — ask Claude to play a sound when done
- **Stop hook** — trigger a Slack message, system notification, or custom action
- **iTerm2 notifications** — native terminal alerts
- **Recaps** — when you check back, recaps tell you what happened (see tip 70)

Full Opus 4.7 workflow: start Claude in auto mode with focus on. Runs autonomously, verifies via `/go`, notifies when done. You review the recap and the PR.

Source: [claude.com blog — best-practices-for-using-claude-opus-4-7-with-claude-code](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)

## 76. Agent View — One List of All Your Sessions

Native control plane for managing multiple Claude Code sessions. Shipped May 11, 2026 as a research preview. Run `claude agents` from a root code directory; tracks every session under that root, groups them by **needs input**, **working**, **completed**.

```bash
# launch the control plane from your root code dir
claude agents

# from any CLI session, hit <- to register it with the control plane
```

**Setup pattern (Thariq, Cat Wu):** start `claude agents` in a high-level directory containing all your repos. Thariq uses `~/Projects`. Every session launched under that root gets tracked.

**Operational tips (Dickson Tsai):**

- New sessions inherit the directory your cursor is on — start a session in any repo in one keystroke
- Renaming is critical for keeping view scannable as sessions pile up. Use `/rename` or set up `UserPromptSubmit` hook to auto-rename

**Why this matters:** productized version of Tip 1 (parallel execution via worktrees). Same productivity goal — many concurrent sessions — but with first-class tooling instead of manual terminal tabs and shell aliases.

Boris's framing: *"The best way to level up from 1 agent => many agents. No more cycling between terminal tabs."* Thariq: *"kind of like tmux built for CC."*

Sources:

- [@bcherny status 2053982327123132846](https://x.com/bcherny/status/2053982327123132846)
- [@trq212 status 2053979505346425179](https://x.com/trq212/status/2053979505346425179)
- [@_catwu status 2053999857799672111](https://x.com/_catwu/status/2053999857799672111)
- [@dickson_tsai status 2054008483402694807](https://x.com/dickson_tsai/status/2054008483402694807)

## 77. /goal — Keep Claude Working Until the Condition Is Met

Surfaced by @ClaudeDevs on May 12, 2026, described as "shipped recently" (exact ship date pending changelog confirmation). `/goal` sets a completion condition. Claude keeps working until condition is true. Every time it tries to stop, model checks the condition against the transcript. Not done — keeps going. Done — you get a "Goal achieved" summary.

```bash
# set a completion condition
/goal all tests in test/auth pass and the lint step is clean
```

**How it works:** the Ralph loop, built into Claude Code. Each stop attempt is intercepted; model self-checks against your condition before exiting. Loop only breaks when condition is satisfied.

**Companion tools (already in this skill):**

- `/loop` (tip 31, 48) — runs Claude on repeat. Good for iterative refactors, cleanups, burning down a backlog.
- `/schedule` (tip 43, 48) — kicks off Claude on a cadence. Nightly test runs, morning triage, weekly cleanup.
- `Stop` hook (tip 7, 13, 24) — programmatic control over when Claude can finish. Run your test suite, hit a CI endpoint, gate on anything.
- Auto mode (tip 42, 68) — lets Claude work uninterrupted without permission prompts.

**Pairs with Tip 76 (Agent View):** agent view runs many sessions at once; `/goal` makes each finish what it started. Worktrees (tip 1) + auto mode (tip 68) + `/goal` approximates an autonomous fleet that doesn't need babysitting.

Docs: "Keep Claude working toward a goal" at code.claude.com.

Source: [@ClaudeDevs status 2054351031279186040](https://x.com/ClaudeDevs/status/2054351031279186040)
