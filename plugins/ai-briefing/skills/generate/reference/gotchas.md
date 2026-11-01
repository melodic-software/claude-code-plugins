# Gotchas for /ai-briefing:generate

Load when a build or bookmark command picks the wrong data directory or profile, or a bookmarked
read returns items already briefed.

- The Bash tool's environment does not carry this plugin's `CLAUDE_PLUGIN_DATA`, and another
  plugin's SessionStart hook can export its own data directory under that name; the build uses an
  inherited value only when it names ai-briefing. That is why the hub's launch line and the
  bookmark script's `--data-dir` pass it on every launch. Basis: the plugins reference,
  <https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>,
  verified 2026-10-07; recheck when that table lists the Bash tool among the processes that
  receive the variables.
- The profile is set per launched process, never as a global export in the consumer's shell
  profile, because a global export pins one profile for every session and every other tool on that
  machine, including runs that asked for a different one.
- The next read starts at the bookmark date itself, so items published later that day are not
  skipped; seen-item and canonical-URL deduplication (Default run step 5) absorbs any item a wider
  window re-reads.
