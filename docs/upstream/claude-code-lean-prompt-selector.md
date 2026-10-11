# Probed behavior: which models already default to the lean system prompt

No docs page says which models Claude Code gives the lean system prompt by default. The
context-budget `simple-system-prompt` lever needs that answer to explain a measured zero:
`CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` changes nothing on a model that is already lean. This record
is the probe the lever points at, in the probed-behavior form of the
[upstream-drift convention](../conventions/upstream-drift/README.md#required-parts).

## Decision

The audit still measures on the consumer's session model and reports the delta; it does not
branch advice on model. This probe only explains a zero, so a stale reading here mislabels a
zero's cause and never changes a recommendation.

## Probe

Read the selector and the model capability table from the installed binary:

```bash
B="$(perl -MCwd -e 'print Cwd::abs_path(shift)' "$(command -v claude)")"
grep -ao 'function [A-Za-z_$]*([a-z]){let [a-z]=[A-Za-z_$]*([a-z]),[a-z]=[A-Za-z_$]*([a-z],"lean_prompt",[a-z]);.\{0,400\}' "$B"
perl -0777 -ne 'for (split /\{id:"/) { next unless /^(claude-[a-z0-9-]+)",family:.*?capabilities:\[([^\]]*)\]/s;
  print "$1 ", ($2 =~ /"lean_prompt"/ ? "lean_prompt" : "-"), "\n" }' "$B" | sort -u
```

The first command prints the selector function; the second lists every model in the capability
table and whether its capability list carries `lean_prompt`.

## Observation (Claude Code 2.1.296, 2026-10-10)

The selector reads a model's `lean_prompt` capability first and falls back to its legacy
model-id list only for a model without that capability entry. In the capability table,
`claude-haiku-5-5` carries `lean_prompt` and `claude-haiku-4-5` does not, so a Haiku 5.5 session
is already lean and a Haiku 4.5 session gets the full prompt.

- **Pointer**: when a `simple-system-prompt` delta needs explaining, rerun the probe above against
  the installed binary.
- **As of**: 2026-10-10 (Claude Code 2.1.296).
- **Recheck trigger**: a Claude Code release whose changelog names the system prompt,
  `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` or a new model; or the probe's first command printing nothing
  (the selector changed shape).
