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

[`unwrap-before-compose.md`](unwrap-before-compose.md) owns the transform, shared byte-identical
with rate-limit-guard, and `scripts/compose-statusline-wiring.sh` performs it. Run the script over
the effective value resolved in step 3 and substitute what it prints:

```bash
jq '.statusLine' <the settings file that owns the effective command> |
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/compose-statusline-wiring.sh" \
    --wrap 'bash ~/.claude/context-guard/bin/statusline-shim.sh' --block --explain
```

Read that reference for the argument and exit-code contract and for the three judgments the script
does not make. Composing by hand instead double-wraps a sibling tee and stacks another `sh -c`
layer on every re-run. The JSON blocks below are this plugin's printed paths only; the script emits
whichever of them the current value selects.

## The edit blocks

The angle-bracket placeholders below show each form's shape. The script fills them and prints the
finished `command` string; substituting into one by hand is the arithmetic it exists to replace.

Wrapping an existing statusline command (the script substitutes the operator's own renderer,
recovered by the peel, as the trailing arguments):

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

When the script selects the shell-wrapped form, `<escaped renderer>` is already escaped in its
output and needs no further editing:

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

The combined form is one invocation, not a second transform: pass both shims as `--wrap` prefixes
in the order they nest, this plugin's first.

```bash
jq '.statusLine' <the settings file that owns the effective command> |
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/compose-statusline-wiring.sh" \
    --wrap 'bash ~/.claude/context-guard/bin/statusline-shim.sh' \
    --wrap 'bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh' --block --explain
```

Naming only one shim drops the other, because the peel strips every shim prefix it finds. The shim
paths are the only part that nests; whether the innermost command takes an `sh -c` adapter is the
same decision the script already made:

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
statusline commands through PowerShell and this wiring does not apply. The routing claim is
verified 2026-09-06 against Claude Code 2.1.263 and the statusline reference
(<https://code.claude.com/docs/en/statusline>, "Windows configuration": Claude Code runs status
line commands through Git Bash when Git Bash is installed, or through PowerShell when Git Bash is
absent). Recheck when that section stops naming both shells, or when a release note names
statusline routing on Windows. State this with the printed edit: the wiring is applied ONCE and
survives every later plugin update, because the shim, not the version-pinned cache path, is
what the settings file names.
