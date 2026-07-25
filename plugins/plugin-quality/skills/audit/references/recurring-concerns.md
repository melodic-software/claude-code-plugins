# Recurring concerns — the reusable plugin-audit checklist

These are design failure modes that recur across Claude Code plugin components. Walk every one each
audit; each has bitten a real plugin. Grow this list as new patterns surface.

## 1. Silent bypass surfaces (highest value)

A guard is only as good as its coverage. Find the paths where it *doesn't* fire.

- **Tool-matcher coverage.** Hooks match on tool name (e.g. `matcher: "Bash"`). If the same action
  can be issued through a *different* tool (a PowerShell tool on Windows, a different shell tool),
  the guard is silently bypassed. Enumerate every tool that can perform the gated action and check
  the matcher covers them.
- **Direct-path bypass.** A skill that enforces a convention only at draft time enforces nothing if
  the user runs the underlying command directly. Ask: what happens if I bypass the skill entirely?
- **Fail-open vs fail-closed.** When a prerequisite is missing (no `jq`, empty stdin, parse error),
  does the guard fail open (allow) or closed (block)? Is that the right default for its purpose?

## 2. Enforcement scope & who it fires for

- **Plugin-enablement probes.** If a hook gates its behavior on whether a plugin is "enabled", does
  it resolve enablement the way Claude Code actually does — merged across user-global + project +
  local scopes? A probe that only checks project scope false-negatives for the common global
  install. Verify against real resolution, not the code's assumption.
- **User-gated by default.** Guardrails a user adds should default to firing only for that user (and
  their agents) — never surprise-blocking teammates who didn't opt in. Prefer mechanisms invisible
  to uninvolved parties (machine-local git hooks, user-scope config) with a clean migration path to
  shared enforcement later. Flag anything that imposes on non-adopters by default.

## 3. Enforcement tiers — what CAN vs CANNOT be gated

- **Mechanics** (verifiable command shape, e.g. message-on-stdin): hook-enforceable → gate it.
- **Declarative conventions** (a subject/title matches a pattern): hook-enforceable by inspecting
  content → gate it if the plugin claims to enforce it; a config file that's only read at draft
  time is not enforcement.
- **Process** (rebase happened, triage occurred, footer assembled): NO command signature → NOT
  hook-enforceable. Advisory is the correct ceiling; the fix is making the advisory reliably fire,
  not hard-blocking. Never hard-block a command that has a documented legitimate direct use.

## 4. SSOT / DRY / drift

- Does the same fact (a regex, a convention, a path) live in multiple hand-maintained places? Name
  the single origin. A plugin config that *mirrors* a consuming repo's own instructions or hooks is
  a drift risk unless one derives from the other.
- Prefer a decoupled, tool-agnostic single source of truth that multiple consumers point at over a
  per-tool copy. For machine-readable-yet-human-first data, a small flat-scalar YAML beats
  frontmatter-in-markdown (brittle for shell) and beats a tool-specific config that traps the value
  in a language (e.g. a regex inside a JS parserPreset a shell hook can't read).
- Where a contract file explicitly declares an inline-floor rule (consumers copy named values
  verbatim), check the copies actually match — byte-identity drift between a writer's contract and
  a consumer's inlined constants is a silent split-brain.

## 5. Coupling & portability

- **`.claude/` coupling.** Is an artifact under `.claude/` because it must be, or just by default?
  `.claude/` is not write-protected and not special for storage — a tool-agnostic doc other tools
  should consume doesn't belong there. Ask whether the path should be configurable.
- **Single-plugin artifact in a shared repo.** A committed file only one plugin reads is inert (and
  confusing) for everyone else. Make it self-describing, or make its location configurable, or
  derive it from an existing shared source.
- **Hardcoded consumer specifics.** A reusable plugin must not bake in one machine's paths, one
  org's repo names, or one project's conventions — those belong in the consumer's own config
  layers.

## 6. Cross-platform

- Shell assumptions: bash heredocs, `$VAR`, forward vs back slashes, `~` vs `%USERPROFILE%`,
  case-sensitivity. Do error messages hand the user a remediation they can actually paste on their
  platform (Windows/PowerShell vs POSIX)?
- Path matching: drive letters, trailing slashes, symlink resolution, case-insensitive matches.

## 7. Escape hatches

- Every deterministic gate needs a clean, documented bypass for when the gate itself is buggy
  (`--no-verify`, an env-var skip, removing an untracked file). A gate with no escape hatch is a
  lockout waiting to happen. Confirm one exists and is discoverable.

## 8. Observability & failure reporting

- When the guard degrades (missing dependency, timeout), does it surface that to the user, or
  silently disable itself? A silently-skipped guard is a defect — it should be visible.
