# Composing the statusline edit

Reference detail for step 7 of `check` in
[`../SKILL.md`](../SKILL.md). Step 7 prints the applicable statusline edit for the settings file
that owns the effective command (resolved in step 3), marked clearly as the operator's to apply.
The wiring target is always the shim's fixed path, never `${CLAUDE_PLUGIN_ROOT}`, which is
version-pinned and belongs in no operator file. Printing an edit at all is forbidden in the
branches step 3 already suppressed, because printing it here would recommend the exact
ineffective remediation those branches exist to withhold.

## Contents

- [Unwrap before you compose](#unwrap-before-you-compose)
- [The edit blocks](#the-edit-blocks)
- [The shell-syntax guard](#the-shell-syntax-guard)
- [Sibling shims compose by nesting](#sibling-shims-compose-by-nesting)
- [Windows note](#windows-note)

## Unwrap before you compose

`<current statusline command>` below means the operator's OWN
renderer, never the raw effective `command` string. Recover it by peeling off the wrapping this
skill itself prints, applying BOTH rules repeatedly until a pass strips nothing:

1. **Guard-shim prefixes**. Every leading `bash <path>/context-guard/bin/statusline-shim.sh` and
   `bash <path>/rate-limit-guard/bin/statusline-shim.sh`, in whatever order they appear, plus any
   legacy `bash <plugin-cache>/…/statusline-tee.sh` prefix.
2. **A generated `sh -c` adapter**, when what remains is EXACTLY `sh -c '<single-quoted string>'`
   with nothing after the closing quote, AND, once that string is unescaped, ANY of the following
   holds, that is an adapter a previous run printed, not the renderer. Unescape it back: drop the
   leading `sh -c` and the outer quotes, then replace every `'\''` with `'`.

   - **A. It is itself EXACTLY `sh -c '<single-quoted string>'`, nothing after the closing
     quote.** A nested `sh -c` is always a layer some run added: an operator's own renderer is at
     most one `sh -c` deep. Apply the same strictness here as to the outer shape, so two readers
     peel the same number of layers.
   - **B. It begins with a guard-shim prefix from rule 1.** This skill never puts a shim inside
     an adapter, and an operator would not write one inside their own `sh -c`. Leaving it sealed
     there hides it from rule 1, which strips only LEADING prefixes, and the composed wiring then
     names that shim a second time.
   - **C. It is a command the guard below would send for wrapping.** That is the only shape this
     skill's own adapter ever carries.

   Branches A and B must NOT inherit the guard's top-level scoping. Their evidence is the shape
   of the carried string, not the syntax in it. Absent all three, the `sh -c` was written by the
   operator and must be preserved: peeling `sh -c 'ulimit -n'` to `ulimit -n` would leave the
   shim `exec`-ing a shell builtin that no longer has a shell, and the statusline would exit 127
   instead of rendering. A trailing word (`sh -c '…' extra`) makes it a real command, not an
   adapter. Leave that alone too.

   One shape stays ambiguous on purpose: a single `sh -c` over a merely-quoted command, which a
   version of this skill that wrongly counted quoting as a trigger also emitted. Nothing in it
   distinguishes that from an operator's own, so it is preserved. The cost is one spurious shell
   per refresh; peeling on a guess costs a broken statusline.

One pass is not enough: an operator may already carry several layers from earlier reruns, and a
single peel over three layers leaves two.

Substituting the raw string instead is what produces `context → rate → rate → renderer` when the
sibling plugin was configured first, or a doubled self-wrap on a re-run: each duplicated tee runs
and writes on EVERY refresh and costs another 0.6–0.9 s (below). Skipping rule 2 compounds the
shell-syntax guard instead, the leftover adapter still contains shell syntax, so it is wrapped in
ANOTHER `sh -c` layer, one more on every run. Unwrapping both makes the printed edit idempotent:
re-running `check` on already-correct wiring prints byte-identical wiring, with exactly one shim
invocation per plugin and at most one `sh -c` layer.

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

## The shell-syntax guard

The wrapped form passes the user's command as ARGV, the shell that runs
the `statusLine` command splits the whole line into words and consumes its quotes, and the shim
`exec`s those words unchanged. It therefore only works for plain `executable arg…` commands. Test
the UNWRAPPED renderer, never the raw effective `command` string, the rules above run first.
Print the shell-wrapped variant instead when EITHER of these holds:

- It carries, UNQUOTED, at the top level, shell syntax no ARGV word can express: an inline env
  assignment like `THEME=dark my-statusline`, a redirection, or any control operator (`|`, `|&`,
  `&&`, `||`, `;`, `&`, a newline).
- **Its command word is not an executable**, a shell builtin, function, or alias, which `exec`
  cannot run because there is no file to exec. `ulimit '-n'` is the standing example: `ulimit`
  exists only as a builtin, so the plain wrapped form reaches `exec ulimit -n` and the statusline
  dies with exit 127 on every refresh. Resolve it the way the shim will: `type -P <word>` finding nothing while `type -t <word>` reports `builtin`, `function`, or
  `alias` is the test, not by matching a hardcoded list of builtin names.

  This trigger is load-bearing precisely because it is *not* about syntax. Such a renderer often
  carries none at all, and before the guard was scoped to real syntax the bare presence of quotes
  wrapped it by accident. That accident was doing real work, and dropping it without this
  replacement is what turns a working statusline into exit 127.

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/context-guard/bin/statusline-shim.sh sh -c '<escaped renderer>'"
  }
}
```

`<escaped renderer>` is that same unwrapped renderer, POSIX-escaped for single-quote
embedding: replace every `'` in it with `'\''` before substituting (then JSON-escape the whole
`command` string as usual). Show the final, fully escaped line, never hand the operator a
template with raw quotes left to fix. Verify your printed edit round-trips: run
`printf '%s\n' '<escaped renderer>'` and confirm the output matches the renderer
byte-for-byte. The single-quoted argument reproduces exactly the quoting context the emitted
`sh -c '<escaped renderer>'` uses; a double-quoted wrapper would instead let the outer shell
expand any `$(...)` or backticks in the operator's own renderer before the check ever ran.

**Syntax inside a quoted argument does not count, and bare quoting is never itself a trigger.**
The quotes make it one ordinary ARGV word that reaches the renderer intact through the plain
wrapped form. So an operator's own `sh -c '<string>'`, the one shape rule 2 preserves, is
ALREADY a plain `executable arg…` command: `sh` is the executable, `-c` and the carried string
are two ordinary ARGV words. Substitute it VERBATIM.

For an input that is ITSELF `sh -c '<string>'`, rule 2 and this guard therefore never both wrap
it, and leave exactly one layer: rule 2 peels every generated layer before the guard runs, and
what rule 2 preserves is a renderer this guard declines. Do not generalize that to a layer count
for every input, the guard adds whatever the renderer genuinely needs, which is NONE for a plain
command and ONE for top-level syntax, and that one is a layer more when the operator's own
`sh -c` sits inside it. `sh -c 'ulimit -n' && echo ok` correctly prints TWO: the `&&` cannot be an
ARGV word, so the adapter is mandatory, and peeling the inner `sh -c` would strand the builtin.
What is invariant is that peel and wrap are inverses, which is what makes a re-run byte-identical
at whatever count the renderer needs. Firing on the quotes instead is what turned an operator's
`sh -c 'ulimit -n'` into `sh -c 'sh -c '\''ulimit -n'\'''`, one more shell on every refresh and
the same compounding rule 2 exists to prevent.

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

The shell-syntax guard applies UNCHANGED to this form: `<current statusline command>` is the
innermost ARGV here too, so run the same test above on the same unwrapped renderer and substitute
whichever of the two forms it selects, never the raw string. Substituting `THEME=dark my-statusline` raw
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
