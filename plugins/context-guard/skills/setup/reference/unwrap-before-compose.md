# Unwrap before you compose: the statusline wiring transform

The shared, plugin-name-free half of the two statusline guard plugins' compose
rules. The hub setup skill supplies every concrete shim path for the printed
edit. These rules target machine-scope surfaces under `~/.claude/` and are
deduplicated here.

`scripts/compose-statusline-wiring.sh` is the whole transform. Run it and
substitute what it prints. Never peel or wrap by hand: the composed value has to
be byte-identical across re-runs, and a hand-composed edit double-wraps a
sibling tee and stacks another `sh -c` layer every time, at a further 0.6 to
0.9 s per refresh for each duplicated tee.

## Invocation

Feed it the effective `statusLine` value resolved in the settings-scope step,
and one `--wrap` per shim the wiring should carry, outermost first:

```bash
jq '.statusLine' ~/.claude/settings.json |
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/compose-statusline-wiring.sh" \
    --wrap 'bash ~/.claude/<this plugin>/bin/statusline-shim.sh' --block --explain
```

`--command '<string>'` replaces the piped JSON when the operator quoted their
command in chat rather than pointing at a settings file.

## Contract

Arguments:

| Argument | Effect |
|---|---|
| `--wrap <prefix>` | A shim prefix the composed wiring carries, outermost first, repeatable. Each value is `bash` plus a path ending in `/statusline-shim.sh`. |
| `--command <string>` | The current `statusLine` command as a raw string, instead of JSON. |
| `--input <file>` | Read the current `statusLine` value as JSON from a file. |
| `-` | Read that JSON from stdin. This is the default. |
| `--block` | Print a paste-ready `{ "statusLine": ... }` settings fragment. |
| `--command-only` | Print the bare composed command string. |
| `--explain` | Write the recovered renderer, the layers peeled, and the wrap decision to stderr. |

`--explain` writes four `key: value` lines to stderr and leaves stdout alone. Those lines are
where a report's reasons come from, so quote them rather than re-deriving the same facts:

```text
renderer: THEME=dark my-statusline
layers-peeled: 3
wrap: shell (unquoted top-level shell syntax)
idempotent: yes
```

`wrap:` is `standalone`, `plain`, or `shell`, each followed by its reason in parentheses. The
four reasons are `no statusline configured`, `command word resolves as an executable`,
`unquoted top-level shell syntax`, and `command word is a builtin, not an executable` (with
`function` or `alias` in place of `builtin` where that is what the command word resolved to).
`layers-peeled: 0` means the value carried no wrapping from an earlier run.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | Composed. The value is on stdout. |
| 1 | A round-trip check failed. One line names the check on stderr and stdout stays empty. |
| 2 | Usage error: unknown argument, missing `--wrap`, or a `--wrap` prefix the peel would not recognize. |
| 3 | The input could not be read, parsed as JSON, or scanned, which includes unbalanced quoting in the current command. |
| 4 | jq is required for the selected input or output mode and is not on PATH. |

A non-zero exit is never something to work around by composing the edit by
hand. Report the reason it printed and stop: exit 2 means the invocation named
a prefix the next run would not peel, and exit 3 means the current `statusLine`
is a command no shell would run, which is a finding for the operator rather
than an input to wrap.

## What the script decides, and what you still do

The script owns the arithmetic. It peels every shim prefix and every adapter a
previous run generated, decides whether the recovered renderer needs an `sh -c`
adapter, escapes it, and asserts before printing that re-composing its own
output reproduces it byte for byte. `--explain` reports each of those decisions
so the report can name the reason rather than the result alone.

Three judgments stay with the skill, because none of them is a function of the
command string:

- **Which `--wrap` prefixes to pass.** Every shim the wiring should carry has to
  be listed, because the peel strips every shim prefix it finds. Name a sibling
  plugin's shim only when that shim is present on disk: `bash <missing-path>`
  exits 127 and takes the whole statusline down before the operator's renderer
  runs.
- **Which settings file the edit targets**, and whether the branches the check
  already suppressed forbid printing an edit at all.
- **Whether the composed value differs from what is already configured.**
  Identical means the wiring is already correct and there is nothing to apply,
  not a change to present.

## The one shape that stays ambiguous

A single `sh -c` over a merely-quoted command is preserved rather than peeled.
Nothing in it distinguishes an adapter a previous run generated from an
operator's own, and `sh -c 'ulimit -n'` peeled to `ulimit -n` would leave the
shim `exec`-ing a shell builtin that no longer has a shell, so the statusline
exits 127 instead of rendering. The cost of preserving is one spurious shell per
refresh; peeling on a guess costs a broken statusline. Report the preserved
layer as the operator's own renderer, because that is how the script treats it.
