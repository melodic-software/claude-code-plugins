# Reject the three unused official plugin components, each with a recheck trigger

- Status: accepted
- Date: 2026-07-12

## Decision

The three unused official plugin components raised as adoption candidates on this date, evaluated
against the enforcement hierarchy (default **REJECT** unless the value is concrete and not already
covered by an existing mechanism). This is that evaluation, not an index of every component the
marketplace does not use — the [component-stances table](../PLUGIN-PHILOSOPHY.md#component-stances) is
that index, and it carries a stance for components never raised here. Facts verified fresh
2026-07-12 per `CLAUDE.md` "Fresh-docs mandate". Verdict for all three: **REJECT now**, each with an
explicit recheck trigger — no implementation issues emitted (zero accepted).

- **Monitors** (`monitors/monitors.json` / `experimental.monitors`) — **REJECT.** Both candidates are
  either already covered or not concrete: a PR/CI watch duplicates `/source-control:pull-request monitor`
  and a consumer's channel-mode PR watch (no gap), and a claude-ops collector-health watch carries no
  concrete recurring pain that outweighs adopting an `experimental.*` component whose manifest schema may
  change between releases (and which is skipped on the hosts / telemetry-disabled configs where the
  Monitor tool is unavailable). **Recheck trigger:** monitors leave the `experimental` key AND a concrete
  recurring in-session watch need surfaces for a shipped plugin, scoped via the documented `when:
  "on-skill-invoke:<skill-name>"` monitor field so it starts only on demand rather than at session
  start. Upstream:
  <https://code.claude.com/docs/en/plugins-reference#monitors>,
  <https://code.claude.com/docs/en/tools-reference#monitor-tool>.
- **`bin/`** (executables added to the Bash tool `PATH`) — **REJECT** as a marketplace-wide adoption.
  Plugin-owned scripts already ship via `${CLAUDE_PLUGIN_ROOT}/scripts/` invoked by full path (the
  established pattern — see "Shared tools and scripts seam" above); `bin/` adds only bare-command-on-`PATH`
  invocation, which risks name collisions with the consumer's own commands, so it earns its place only
  where a script is meant to be run as a bare command by the consumer. The one live candidate — the
  knowledge plugin's extraction tooling — is owned by its publish issue #1373; the `bin/`-vs-`scripts/`
  call belongs there, not duplicated here. **Recheck trigger:** a shipped plugin has a script the consumer
  invokes as a bare command (not an internal helper). Upstream:
  <https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout>.
- **`subagentStatusLine`** (plugin `settings.json`) — **REJECT.** Purely cosmetic: it re-formats the
  subagent panel row with no functional capability, so it does not clear the default-REJECT bar; its
  richest inputs (per-row model + context-window size for a context percentage) additionally require a
  recent Claude Code minimum. Candidate home was claude-ops. **Recheck trigger:** a concrete operational
  need for custom subagent-row data during orchestration, not a presentation preference. Upstream:
  <https://code.claude.com/docs/en/statusline#subagent-status-lines>,
  <https://code.claude.com/docs/en/plugins-reference#standard-plugin-layout>.
