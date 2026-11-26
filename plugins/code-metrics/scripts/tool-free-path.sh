#!/usr/bin/env bash
# shellcheck shell=bash

_CM_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CM_LADDER="${_CM_SCRIPTS_DIR}/collector-ladder.tsv"
_CM_COLLECTORS="${_CM_SCRIPTS_DIR}/collectors"

_cm_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3; else echo python; fi
}

cm_ladder_tools() {
  awk -F'\t' '
    !/^#/ && NF >= 3 && $3 != "none" && $3 != "n/a" && $3 != "deferred" && !seen[$3]++ {
      print $3
    }
  ' "$_CM_LADDER"
}

cm_ladder_path_bins() {
  "$(_cm_python)" -I - "$_CM_LADDER" "$_CM_COLLECTORS" <<'PY' | sed $'s/\r$//'
import ast
import os
import sys

RESERVED = {"none", "n/a", "deferred"}
ladder, collectors_dir = sys.argv[1], sys.argv[2]
tools = []
with open(ladder, encoding="utf-8") as handle:
    for raw in handle:
        if raw.startswith("#") or not raw.strip():
            continue
        parts = raw.rstrip("\n").split("\t")
        if len(parts) >= 3 and parts[2] not in RESERVED and parts[2] not in tools:
            tools.append(parts[2])

bins = set(tools)
for tool in tools:
    adapter = os.path.join(collectors_dir, f"{tool}.py")
    if not os.path.isfile(adapter):
        continue
    with open(adapter, encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=adapter)
    constants = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
            if (
                isinstance(target, ast.Name)
                and isinstance(node.value, ast.Constant)
                and isinstance(node.value.value, str)
            ):
                constants[target.id] = node.value.value
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if not (isinstance(func, ast.Attribute) and func.attr == "which" and node.args):
            continue
        arg = node.args[0]
        if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
            bins.add(arg.value)
        elif isinstance(arg, ast.Name) and arg.id in constants:
            bins.add(constants[arg.id])
for name in sorted(bins):
    print(name)
PY
}

_cm_is_python_interp() {
  case "$1" in
    python|python[0-9]|python[0-9].*|python3|python3.*|pypy|pypy3|pypy3.*) return 0 ;;
    *) return 1 ;;
  esac
}

_cm_nonmutating_python() {
  local exe="$1" resolved
  resolved="$("$exe" -I -c 'import os, sys; print(os.path.realpath(sys.executable))' 2>/dev/null)" || return 1
  [[ -n "$resolved" && -f "$resolved" && -x "$resolved" ]] || return 1
  printf '%s\n' "$resolved"
}

cm_fill_tool_free_path() {
  local dest="$1"
  local name dir exe target resolved
  mkdir -p "$dest"
  declare -A skip=()
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    skip["$name"]=1
  done < <(cm_ladder_path_bins)
  local IFS=':'
  local -a path_dirs
  read -r -a path_dirs <<<"$PATH"
  for dir in "${path_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    for exe in "$dir"/*; do
      [[ -f "$exe" && -x "$exe" ]] || continue
      name="${exe##*/}"
      [[ -n "${skip[$name]:-}" ]] && continue
      [[ -e "$dest/$name" ]] && continue
      target="$exe"
      if _cm_is_python_interp "$name"; then
        resolved="$(_cm_nonmutating_python "$exe")" && target="$resolved"
      fi
      MSYS=winsymlinks:nativestrict ln -s "$target" "$dest/$name"
    done
  done
}

cm_resolvable_ladder_collectors() {
  local dest="$1"
  local py
  py="$(_cm_python)"
  local name tool adapter
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    PATH="$dest" command -v "$name" >/dev/null 2>&1 && printf '%s\n' "$name"
  done < <(cm_ladder_path_bins)
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    adapter="$_CM_COLLECTORS/$tool.py"
    [[ -f "$adapter" ]] || continue
    grep -q 'shutil.which' "$adapter" || continue
    if PATH="$dest" "$py" "$adapter" probe >/dev/null 2>&1; then
      printf '%s\n' "$tool"
    fi
  done < <(cm_ladder_tools)
}
