# Composing the statusline edit

Reference detail for step 7 of `check` in
[`../SKILL.md`](../SKILL.md). Step 7 prints the applicable statusline edit for the settings file
that owns the effective command (resolved in step 3), marked clearly as the operator's to apply.
The wiring target is always the shim's fixed path, never `${CLAUDE_PLUGIN_ROOT}`, which is
version-pinned and belongs in no operator file. Printing an edit at all is forbidden in the
branches step 3 already suppressed, because printing it here would recommend the exact
ineffective remediation those branches exist to withhold.

## Contents

- [Unwrap and wrap rules](#unwrap-and-wrap-rules)
- [The edit blocks](#the-edit-blocks)
- [Sibling shims compose by nesting](#sibling-shims-compose-by-nesting)
- [Windows note](#windows-note)

## Unwrap and wrap rules

Read [`unwrap-before-compose.md`](unwrap-before-compose.md) now, before composing. It owns
the peel rules and the shell-syntax guard, shared byte-identical with rate-limit-guard.
Composing without those rules double-wraps a sibling tee and stacks another `sh -c`
layer on every re-run. The JSON blocks below are this plugin's printed paths only.

## The edit blocks

Wrapping an existing statusline command (preserve the user's unwrapped command verbatim as the
trailing arguments):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh <current statusline command>"
  }
}
```

No statusline configured (standalone minimal statusline):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh"
  }
}
```

When the shared guard selects the shell-wrapped form:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c '<escaped renderer>'"
  }
}
```

## Sibling shims compose by nesting

Sibling tees compose by nesting, each through its OWN shim, the tees are transparent wrappers,
so the innermost command still owns stdout and the exit code. Print this form only when
`rate-limit-guard` is installed AND its shim is already present at
`~/.claude/rate-limit-guard/bin/statusline-shim.sh`. The sibling shim is written by
`/rate-limit-guard:setup apply`, which the operator may not have run yet. Naming a path that
does not exist reintroduces exactly the failure this wiring exists to remove, because `bash
<missing-path>` exits 127 before the operator's renderer ever runs. When the sibling plugin is
installed but its shim is absent, print the single-shim form above and say that
`/rate-limit-guard:setup apply` followed by a re-run of this check yields the combined wiring:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh <current statusline command>"
  }
}
```

The shell-syntax guard in [`unwrap-before-compose.md`](unwrap-before-compose.md) applies
UNCHANGED to this form: `<current statusline command>` is the innermost ARGV here too, so run
that test on the same unwrapped renderer and substitute whichever of the two forms it selects,
never the raw string. Substituting `THEME=dark my-statusline` raw
makes `THEME=dark` the executable, which fails `command not found` (127) instead of setting the
variable. The shim paths are the only part that nests; the innermost substitution rule never
changes:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh sh -c '<escaped renderer>'"
  }
}
```

State the measured cost with the combined form: each tee adds roughly 0.6–0.9 s per statusline
refresh on Windows/Git Bash (process-spawn bound), on top of the operator's own statusline
command. `refreshInterval` sets how often that runs; the statusline is not on the input path, so
the cost is display latency, not typing latency.

## Windows note

The command must run under Git Bash. `bash` is invoked explicitly for exactly
that reason (the script's stated shell requirement); with Git Bash absent Claude Code routes
statusline commands through PowerShell and this wiring does not apply (statusline reference,
"Windows configuration"). State this with the printed edit: the wiring is applied ONCE and
survives every later plugin update, because the shim, not the version-pinned cache path, is
what the settings file names.
