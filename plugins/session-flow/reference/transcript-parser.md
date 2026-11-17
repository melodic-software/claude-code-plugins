# Transcript parser

`<plugin-root>/scripts/parse_transcript.py` turns session transcripts, or sealed CI lane legs, into
metrics JSON. `<plugin-root>` is `${CLAUDE_PLUGIN_ROOT}`, resolved by the skill that reads this
file before any command below reaches the Bash tool. It is stdlib-only and reads every transcript
through the plugin's shared reader, `<plugin-root>/scripts/transcript_reader.py`.

## Interpreter

Pick an interpreter that is Python 3.10 or later; a bare `python` may be older. With none, skip the
parser and say why.

```bash
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 \
     && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PY="$c"; break
  fi
done
PARSER="<plugin-root>/scripts/parse_transcript.py"
```

## Forms

```bash
# One session:
"$PY" "$PARSER" --sessions "<session-id>" --base "$SESSION_DATA_DIR"

# Several sessions, ids space-separated or comma-joined (the first is the current one):
"$PY" "$PARSER" --sessions <sid1> <sid2> ... --base "$SESSION_DATA_DIR"

# A handoff chain, walked from its newest save-point (continuity gate below):
"$PY" "$PARSER" --chain-from "<newest handoff file>" --current-session "<session-id>" --base "$SESSION_DATA_DIR"

# Sealed CI lane legs, the paths <plugin-root>/scripts/lane_legs.py names:
"$PY" "$PARSER" --legs <leg.json.gz> [<leg.json.gz> ...]
```

`SESSION_DATA_DIR` resolves per `/session-flow:retro`'s "Paths". The handoff directory is
`<memory_dir>/handoffs/` (default `.work/handoffs/`); its newest file is the last
`*-handoff-*.md` in name order. With none, use the one-session form.

**Continuity gate.** Use `--chain-from` only when the newest handoff belongs to the current work:
this session resumed from it, this session wrote it, or its `topic` frontmatter and stated goal
clearly match the current task. A shared directory can hold save-points from finished or abandoned
tasks, and chaining from an unrelated one splices stale sessions into the aggregate. When
continuity is absent or unclear, use the one-session form.

## Contract

JSON on stdout: `status` and `summary`, then per session a `data` block (session info, turns,
tokens, tool usage and rejections, compactions, turn durations, stop reasons, files modified,
subagents, errors). The several-session and chain forms add `sessions`, an `aggregate` block and a
`chain_coverage` block; `--legs` adds `legs` and an `aggregate` block, with each leg's `data`
carrying `result` and `timing_source`. The script's docstring has every field. Exit codes: 0
success, 1 warning, 2 error.
