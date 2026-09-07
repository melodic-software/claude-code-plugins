#!/usr/bin/env bash
# comment-tooling-probe.sh — report which comment-analysis layer this machine can run.
#
# Probes the environment rather than reading a config file, because environment
# presence is the fact the skill actually needs and it stays true across
# convention churn. A consumer repo's .claude/ecosystems/<eco>.yaml enriches the
# picture where it exists, but audit-dead-code already established that most
# repos ship none, and its `install-hint` names lint tools rather than analysis
# tools, so it cannot answer this question.
#
# Usage: comment-tooling-probe.sh [--json]
#
# Output: one row per layer — name, status, and the capability its absence costs.
# Always exits 0: a missing layer is a downgrade, never a failure.
set -u

JSON=0
[[ "${1:-}" == "--json" ]] && JSON=1

have() { command -v "$1" >/dev/null 2>&1; }
pyhas() { python3 -c "import $1" >/dev/null 2>&1; }

# Layer, probe result, and what is lost without it.
rows=""
add_row() { rows="${rows}${1}\t${2}\t${3}\t${4}\n"; }

if have scc; then
  add_row count scc present "-"
else
  add_row count scc absent "The per-file complexity estimate the ranking uses. Census lines and bytes then come from pygments; with pygments absent too, the census and the ranking cannot run at all (exit 3)."
fi

if pyhas pygments; then
  add_row extract pygments present "-"
else
  add_row extract pygments absent "Per-comment byte counts and the token estimate, and correct extraction of trailing, block and heredoc-adjacent comments. With scc absent too, the census and the ranking cannot run at all (exit 3): a line-prefix grep is never substituted, because it counts heredoc bodies and string data as comments."
fi

TS_LANGS=""
for m in tree_sitter_python tree_sitter_c_sharp tree_sitter_typescript tree_sitter_bash tree_sitter_javascript tree_sitter_yaml; do
  pyhas "$m" && TS_LANGS="${TS_LANGS}${TS_LANGS:+,}${m#tree_sitter_}"
done
if pyhas tree_sitter && [[ -n "$TS_LANGS" ]]; then
  add_row attach "tree-sitter($TS_LANGS)" present "-"
else
  add_row attach tree-sitter absent "Knowing what a comment is attached to. Without it the exported-symbol exemption is a text-prefix heuristic instead of a parse fact."
fi

if have ruff; then
  add_row commented-out ruff present "-"
else
  add_row commented-out ruff absent "Precise commented-out-code detection in Python (ERA001). Falls back to model judgement."
fi

# Probe `ast-grep`, NEVER `sg`. Both meanings of `sg` are live: shadow-utils
# ships /usr/bin/sg (a symlink to newgrp) and ast-grep historically installed
# its own now-deprecated `sg` shim, so on a machine carrying both, PATH order
# alone decides which one answers, silently and wrongly.
if have ast-grep; then
  add_row rules ast-grep present "-"
else
  add_row rules ast-grep absent "Declarative comment triage: kind/precedes/inside rules classify attachment without bespoke code. Falls back to walking the parse tree directly."
fi

if [[ "$JSON" -eq 1 ]]; then
  printf 'layer\ttool\tstatus\tcost\n%b' "$rows" |
    awk -F'\t' 'NR>1 && NF>=4 {
      gsub(/"/,"\\\"",$4)
      printf "%s{\"layer\":\"%s\",\"tool\":\"%s\",\"status\":\"%s\",\"cost\":\"%s\"}", (n++?",":"["), $1,$2,$3,$4
    } END { print (n?"]":"[]") }'
else
  printf 'layer\ttool\tstatus\tcost-if-absent\n'
  printf '%b' "$rows"
fi
exit 0
