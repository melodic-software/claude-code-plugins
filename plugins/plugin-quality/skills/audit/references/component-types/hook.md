# Auditing a hook

PreToolUse / PostToolUse / lifecycle hook scripts. Growable — add cases as you find them.

## Read first

- `hooks/hooks.json` — which events, which `matcher` (tool-name regex), which scripts, timeouts.
- The script itself + any shared utility script it sources.
- The plugin's `userConfig` for kill switches / allow-lists that gate the hook.

## Check

- **Matcher coverage** — does the matcher cover every tool that can perform the gated action?
  (Bash-only matchers miss a PowerShell/other-shell tool → silent bypass.)
- **Exit-code semantics** — PreToolUse: 0 allow, 2 block; PostToolUse: 2 shows stderr to Claude.
  Does the script use them correctly, and fail closed where blocking matters? Verify the semantics
  against the current hooks reference, not memory.
- **Fail-open vs fail-closed** on missing deps (jq), empty/timed-out stdin, parse errors.
- **Enablement/scope probe** — if it self-disables based on plugin enablement or settings, does it
  read the *merged effective* scopes (user-global + project + local), not just one?
- **Content vs mechanic** — does it inspect the payload it claims to (subject text, args), or only
  a surface marker?
- **Escape hatch** — documented bypass for when the hook is buggy?
- **Cross-platform** — remediation messages runnable on the user's shell; path/quoting assumptions.
- **Observability** — degraded state surfaced, not silently skipped.

## Reproduce

Trigger the tool call the hook matches (and one it *should* match but might not), through each
relevant tool, and confirm block/allow behavior empirically.
