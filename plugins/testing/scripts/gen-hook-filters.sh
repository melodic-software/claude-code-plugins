#!/usr/bin/env bash
# gen-hook-filters.sh: write hooks/hooks.json from the adapters' files: globs.
#
# The test-weaken (PreToolUse) and test-scan (PostToolUse) hooks start only for
# paths an `if` row matches, and those rows must list exactly the test-file
# globs the scanner claims, so they are generated from one source, the same
# for both events: the union of every shipped adapter's files: list,
# deduplicated and sorted. An `if` holds one rule and names one tool, so each
# glob gets a Write row and an Edit row: an Edit(...) row does not match a
# Write call (the `if` probe, below). A glob with no slash matches the basename at any
# depth (gitignore syntax). The task-end judge's background job (async) takes
# the same PostToolUse rows; its Stop and SessionStart entries have no `if`.
# The Stop entry runs with asyncRewake, so the turn ends without waiting for
# it; it judges a finished subagent's writes with the parent's. asyncRewake:
# https://code.claude.com/docs/en/hooks#command-hook-fields (as of 2026-10-11;
# recheck when that section changes whether an asyncRewake hook runs in the
# background).
#
# PostToolUse also gets one Bash row with no `if`: a Bash `if` matches
# the command string, not the files the call changed (the bashEditDiff
# probe, below), so test-scan-bash.sh filters the payload's changed files by
# the same globs.
# The `if` probe: https://github.com/melodic-software/claude-code-plugins/blob/9a0d6f5cf47098fa73bb4b8bb41336be1945c70e/docs/specs/tautological-tests/probes.md#if-row-matching-and-hook-input-claude-code-21284-wsl2-2026-09-28
# (as of 2026-09-28; recheck when a Claude Code release note changes how a
# hook's `if` rule matches a tool call).
# The bashEditDiff probe: https://github.com/melodic-software/claude-code-plugins/blob/9a0d6f5cf47098fa73bb4b8bb41336be1945c70e/docs/specs/tautological-tests/probes.md#basheditdiff-claude-code-21285-wsl2-2026-09-30
# (as of 2026-09-30; recheck when a Claude Code release note changes what a
# Bash `if` rule matches or which changed files a Bash hook payload lists).
# Its launcher flag --skip-unless-stdin-contains bashEditDiff skips the bash
# start on a payload with no Bash change diff, the case the script itself
# exits on first; the row is advisory, so the flag's fail-open stall is safe.
# The judge has no Bash row: test-scan records a Bash-written test file like
# any other write, and the Stop hook judges what no background job did.
#
# Usage: gen-hook-filters.sh [--check]
#   (no arg)  rewrite hooks/hooks.json
#   --check   exit 1 when hooks/hooks.json differs from what would be written
# Exit: 0 written or in sync; 1 drift; 2 setup failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT="$ROOT/skills/audit"
OUT="$ROOT/hooks/hooks.json"

globs="$(awk -f "$AUDIT/scripts/adapter-load.awk" "$AUDIT"/adapters/*.yaml |
  awk -F'\t' '$2 == "files" { print $3 }' | LC_ALL=C sort -u)" || exit 2
[[ -n "$globs" ]] || {
  echo "gen-hook-filters: no files: globs in $AUDIT/adapters" >&2
  exit 2
}

# The task-end judge (test-judge*.sh) needs test-scan's session state, so its
# rows are gated on both options. Its PostToolUse job runs async on the same
# `if` rows as test-scan and gets no timeout; Stop's 240 s sits above the
# hook's own 180 s bound. A timeout is written only where Claude Code enforces
# one, per https://code.claude.com/docs/en/hooks#run-hooks-in-the-background
# (as of 2026-10-11; recheck when that section changes which background hooks
# have their timeout enforced).
json="$(jq -R . <<<"$globs" | jq -s '. as $globs |
  def cmd($gates; $flags; $script): {
    type: "command",
    command: "node",
    args: (["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs"] + ($gates | map("--require-true", .)) + $flags
      + ["${CLAUDE_PLUGIN_ROOT}/hooks/\($script)"])
  };
  def cmd($gates; $script): cmd($gates; []; $script);
  def rows($script; $extra): [{
    matcher: "Write|Edit",
    hooks: [$globs[] as $g | ("Write", "Edit") | {if: "\(.)(\($g))"} as $if
      | cmd(["TEST_GUARDS_ENABLED"] + (if $extra.async then ["TEST_JUDGE_ENABLED"] else [] end); $script) + $if + $extra]
  }];
  def judge($script; $extra): [{hooks: [cmd(["TEST_GUARDS_ENABLED", "TEST_JUDGE_ENABLED"]; $script) + $extra]}];
  # The node-notice row runs without node, so it is shell form; the prerequisites convention owns it,
  # including the matcher that skips compaction.
  def notice: [{matcher: "startup|resume|clear|fork", hooks: [{type: "command",
    command: "sh \"${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.sh\" node-notice /testing:check; ${PPID:+exit}; powershell -NoProfile -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.ps1\" node-notice /testing:check",
    timeout: 10, statusMessage: "Checking that node is on PATH..."}]}];
  {
    description: "Names what a Write or Edit to a test file removes and scans the written file, or a test file a Bash call changed, for tests that cannot fail (opt-in: test_guards_enabled); a task-end judge asks where each new test'"'"'s expected value came from (opt-in: test_judge_enabled, which needs test_guards_enabled).",
    hooks: {
      PreToolUse: rows("test-weaken.sh"; {timeout: 10, statusMessage: "Checking the edit for removed assertions or skipped tests..."}),
      PostToolUse: (rows("test-scan.sh"; {timeout: 10, statusMessage: "Scanning the test file for tests that cannot fail..."})
        + [{matcher: "Bash", hooks: [cmd(["TEST_GUARDS_ENABLED"]; ["--skip-unless-stdin-contains", "bashEditDiff"]; "test-scan-bash.sh")
            + {timeout: 10, statusMessage: "Scanning test files the command changed..."}]}]
        + rows("test-judge-bg.sh"; {async: true})),
      Stop: judge("test-judge.sh"; {asyncRewake: true, timeout: 240, statusMessage: "Collecting the test judge'"'"'s verdicts..."}),
      SessionStart: (judge("test-judge-start.sh"; {timeout: 30}) + notice)
    }
  }')" || exit 2

if [[ "${1:-}" == --check ]]; then
  if [[ "$json" != "$(cat "$OUT" 2>/dev/null)" ]]; then
    echo "gen-hook-filters: $OUT is out of date; run plugins/testing/scripts/gen-hook-filters.sh" >&2
    exit 1
  fi
  exit 0
fi
printf '%s\n' "$json" >"$OUT"
