# debugging

A Claude Code plugin that debugs **observed failures** via a disciplined
six-phase loop. Observed failures include a wrong UI, a bad log line, a
performance regression, a screenshot of a bug, or a production symptom.
It is the discipline that separates a fixed
bug from a lucky one: no phase proceeds without a fast, deterministic,
agent-runnable pass/fail signal.

Invoke it with `/debugging:debug <bug description>`, or let Claude reach for it
when you describe broken behavior with no pre-existing reproduction.

## Skills

| Skill | Use it for |
|---|---|
| `/debugging:debug` | A failure you can see: reproduce it with a loop, rank and probe the causes, then fix it with a regression test and clean up. |
| `/debugging:analyze-profile` | A CPU profile, heap snapshot or performance trace: read it down to a file:line cause with no fix, or record one first with your approval. Needs Python 3.10 or later. |

## The six phases

1. **Build the reproduction loop**, where most of the effort goes. One quick command
   that gives the same pass or fail for this bug on every run. Ten kinds of loop,
   ranked from a failing test down to a script a person runs by hand.
2. **Reproduce**. Run the loop; confirm it shows *the* failure the user described.
3. **Hypothesize**. Rank three to five candidate causes, each with a prediction a
   test could disprove, before the first test runs.
4. **Instrument**. Each probe checks one prediction and changes one thing; each
   temporary log line carries the session marker that Phase 6 searches for.
   Slowdowns are measured against a baseline instead.
5. **Fix + regression test**. The test comes first, at a *correct seam*; when no such seam
   exists, the missing seam is reported as the finding.
6. **Cleanup + post-mortem**. Remove instrumentation, verify the original repro is
   gone, and capture what would have prevented the bug.

## Works in any repo

- **Self-contained.** The methodology, the per-ecosystem debugging reference, the
  phase checklist, and the human-in-the-loop script template all ship inside the
  plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`.
- **Graceful degrade.** Where a phase mentions an adjacent capability, such as a
  test-investigation routine, a TDD helper, a headless-browser driver, an
  architecture-audit agent, an issue tracker, or an outcome verifier, it is treated as
  **optional**: if your environment provides it, the skill uses it; otherwise it
  proceeds with self-contained inline guidance. No phase blocks on a missing tool.
- **Reads your conventions, assumes none.** Test naming, module layout, banned APIs,
  and where working notes live come from your own project's `CLAUDE.md`, its
  `.claude/rules/` project rules, and tool config.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install debugging@melodic-software
```

## Configuration

This plugin has no `userConfig`. The phase checklist is a bundled template you copy
into your own working-notes location (or track inline); nothing is written to shared
plugin storage.

## License

MIT (SPDX-License-Identifier: MIT).
