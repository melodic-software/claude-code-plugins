# audit-pass: Phase 1 liveness sources

This file owns the per-source detail behind Phase 1's liveness rule: which sources a model-driven run
can actually reach, which are out of reach and why, what each reachable source establishes, and the
three coverage losses the run names in `skipped` rather than absorbs. The rule itself, that a
liveness claim carries its basis and that the report marks a single-sourced one, stays in Phase 1 of
[`../SKILL.md`](../SKILL.md), as do the output-style resolution and shadowed-definition rules.

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md).

## Which sources this run can reach

**Liveness sources are the ones this run can actually reach, and a source it cannot reach is named
rather than required.** The decisive constraint is that `/context`, `/memory`, `/skills`, `/hooks`,
`/permissions`, and `/status` are **built-in interactive commands, not Skills**, so a model-driven
run has no way to invoke one and no channel to read its output. Requiring them made the inventory's
two-source rule ceremonial: every one of them resolves to unavailable, so every memory-layer claim
was single-sourced anyway while the report presented a two-source design.

> **Verified 2026-09-13**, Claude Code 2.1.268. **Claim:** those six are built-in commands with no
> model-invocable form; model invocation of built-ins has been *removed* upstream rather than added
> to, `/verify` and `/deep-research` being the worked cases. **Basis:**
> [slash commands](https://code.claude.com/docs/en/slash-commands) plus the installed binary's own
> command surface. **Recheck trigger:** a release note or the slash-commands page granting any of
> those six a model-invocable or non-interactive form, at which point it returns as a source.

## The sources Phase 1 takes

So Phase 1 takes the sources it can hold:

- **The harness-injected instruction block itself.** For the memory layer this is better than a
  summary of it, because it is the loaded **text**: what a `/memory` listing would have summarized is
  present verbatim in the session, so the memory-layer liveness question is answered from the
  content rather than from a report about it.
- **The settings cascade, read directly.** Every scope's settings file, on the precedence order
  `audit-permission-state` owns. It derives what is configured; it does not observe what loaded, and
  the inventory says which of the two a row is.
- **MCP server status, non-interactively.** `/mcp` is **not** swept in with the interactive six. The
  `claude mcp` subcommand group is non-interactive and prints configured servers with their
  connection state, so the MCP half of the inventory keeps a real source.

  > **Verified 2026-09-13**, Claude Code 2.1.268. **Claim:** `claude mcp list` lists configured MCP
  > servers, health-checking approved ones and marking unapproved `.mcp.json` servers as pending
  > approval; `claude mcp get <name>` prints one server's detail. **Basis:** `claude mcp --help` on
  > the installed 2.1.268 binary, plus
  > [the MCP page](https://code.claude.com/docs/en/mcp). **Recheck trigger:** the `claude mcp`
  > subcommand list changes, or `list` stops reporting connection state.
- **`InstructionsLoaded`, probed.** It is more available than an "events already fired" reading
  suggests, and the distinction is per `load_reason` rather than per event.

  > **Verified 2026-09-13**, Claude Code 2.1.268. **Claim:** `InstructionsLoaded` fires on lazy
  > loads as well as at startup, carrying `load_reason` values including `session_start`,
  > `nested_traversal`, `path_glob_match`, `include`, and `compact`, with `file_path` alongside
  > `parent_file_path`. **Basis:** [hooks reference](https://code.claude.com/docs/en/hooks), plus
  > first-party measurement in this marketplace. **Recheck trigger:** the hooks reference changes
  > the event's payload fields or its `load_reason` set.

  Only the `session_start` half is out of reach at dispatch time, because those events fired before
  this skill was invoked. A **wired** hook still observes every lazy load for the rest of the
  session, and observes them inside subagents too. So the probe has three outcomes, not two:
  **present and covering startup** (a recorded payload set for this session exists and is fresh:
  ground truth for the memory layer); **present for lazy loads only** (a producer is wired but the
  startup events are gone: mid-run loads are ground truth and the startup set is marked
  single-sourced); and **absent**, the ordinary case, since this plugin wires no such hook and the
  one optional producer in this marketplace is a no-op without a telemetry sink.

## What is lost, and named rather than absorbed

**What is genuinely lost is named in `skipped`, never absorbed.** Three losses, each stated as what
the run could not observe rather than left to read as coverage:

- **Per-skill listing-budget drops.** They come from a decay-weighted usage score no reachable source
  exposes, so the pass cannot say which skill descriptions were dropped from the listing.
- **Custom-agent registration liveness**, which degrades from observed to **configured-not-observed**:
  the inventory can say an agent is defined and cannot say the session registered it.
- **The clean-room comparison.** Relocating `CLAUDE_CONFIG_DIR` and diffing a bare session is what
  attributed an observed behavior to local configuration rather than to a harness default. Without
  it the precedence order still *derives* which surface should win, and derivation is not
  observation. The report says which it did.

**Neither the injected block nor the settings cascade observes `managed-settings.json`'s `claudeMd`
key**, a limitation of these sources rather than a claim about the harness: probe for it and name it
in `skipped`.
