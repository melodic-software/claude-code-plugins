# debugging

A Claude Code plugin that debugs **observed failures** via a disciplined
six-phase loop. Observed failures include a wrong UI, a bad log line, a
performance regression, a screenshot of a bug, or a production symptom.
It is the discipline that separates a fixed
bug from a lucky one: no phase proceeds without a fast, deterministic,
agent-runnable pass/fail signal.

Invoke it with `/debugging:debug <bug description>`, or let Claude reach for it
when you describe broken behavior with no pre-existing reproduction.

## The six phases

1. **Build a tight feedback loop**, the load-bearing work. A fast, deterministic
   signal that says "bug present / bug fixed". Ten construction strategies, from a
   failing test to a human-in-the-loop script.
2. **Reproduce**. Run the loop; confirm it shows *the* failure the user described.
3. **Hypothesise**. Generate 3-5 ranked, falsifiable hypotheses before testing any.
4. **Instrument**. One probe per prediction, one variable at a time; tagged debug
   logs that clean up with a single grep. A dedicated performance branch.
5. **Fix + regression test**. Test at a *correct seam* first; if none exists, that
   absence is itself the finding.
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
