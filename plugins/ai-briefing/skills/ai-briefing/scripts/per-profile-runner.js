#!/usr/bin/env node
// Per-profile runner — invocable stage CLI for the AI briefing per-profile
// 6-stage state machine. The main interactive Claude Code session orchestrates
// the loop and feeds chrome MCP captures into this CLI between stages.
//
// Architecture (Option A): main session drives chrome MCP because plugin-defined
// MCP servers (claude-in-chrome) do NOT load in `claude -p` subprocesses
// (code.claude.com/docs/en/mcp-servers#plugin-provided-mcp-servers). Stages S3
// (synthesize) + S4 (categorize) still spawn `claude -p` subprocesses — pure
// text in/out, no MCP needed, empirically working.
//
// Subcommand reference: run with --help (printUsage below is the SSOT).
// stdout = single-line JSON. Logs/progress to stderr. Errors → JSON {error: msg} stdout + exit non-zero.
// Exit codes: 0 success, 1 paused, 2 hard fatal, 3 completed-with-failed.

import { SUBCOMMANDS } from "./lib/per-profile-commands.js";
import { exitWith } from "./lib/runner-context.js";

function parseFlags(argv, startAt = 3) {
  const flags = {};
  for (let i = startAt; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const eq = a.indexOf("=");
    if (eq > 0) flags[a.slice(2, eq)] = a.slice(eq + 1);
    else flags[a.slice(2)] = true;
  }
  return flags;
}

function emitErr(msg) {
  process.stderr.write(`${String(msg)}\n`);
}

function printUsage() {
  process.stderr.write(`per-profile-runner.js — AI briefing per-profile stage CLI

Subcommands:
  init [--scope=<all|all-non-skip|high|test>] [--cutoff=<ISO>]
       [--anti-bot-cap=N] [--with-replies-medium] [--no-replies] [--dry-run] [--force]
  next-handle [--resume=<run-id>]
  commit-s1 --index=N --captures=<file> [--resume=<run-id>]
  synthesize --index=N [--resume=<run-id>]
  categorize --index=N [--resume=<run-id>]
  commit-and-checkoff --index=N [--resume=<run-id>]
  mark-failed --index=N --stage=<S1|S3|S4|orchestration> --error=<msg> [--resume=<run-id>]
  status [--resume=<run-id>]
  summary [--resume=<run-id>]
  retry-failed [--resume=<run-id>]
  resume-paused [--resume=<run-id>]   reset anti-bot navs + status=in_progress for paused runs
  detect-resume                       no flags. Returns latest in_progress/paused run summary OR {noActiveRun:true}
  grok-check                          probe Grok Build install/auth (optional tooling; exit 0 always)
  abandon [--resume=<run-id>] [--reason=<msg>]   mark in_progress/paused run as abandoned (frees init w/o --force)

Output: stdout = single-line JSON. Logs / progress to stderr. Errors → JSON {error:msg} stdout + non-zero exit.
Exit codes: 0 success, 1 paused, 2 hard fatal, 3 completed-with-failed.
`);
}

async function main() {
  const argv = process.argv;
  const sub = argv[2];

  if (!sub || sub === "-h" || sub === "--help" || sub === "help") {
    printUsage();
    exitWith(sub ? 0 : 1);
  }

  if (sub.startsWith("--")) {
    printUsage();
    exitWith(2, {
      error:
        "Flags require a subcommand (e.g. init, next-handle, commit-s1). Run with --help for the subcommand list.",
    });
  }

  const fn = SUBCOMMANDS[sub];
  if (!fn) {
    printUsage();
    exitWith(2, { error: `Unknown subcommand: ${sub}` });
  }
  const flags = parseFlags(argv);
  const result = await fn(flags);
  exitWith(result.code, result.payload);
}

main().catch((err) => {
  emitErr(`Hard fatal: ${err.message}`);
  emitErr(err.stack || "");
  exitWith(2, { error: err.message });
});
