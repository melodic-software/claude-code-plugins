#!/bin/sh
# POSIX sh until check-lib.sh, sourced first, has it running under bash.
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail
rt="$here/resolve-tool.sh"
[[ -f "$rt" ]] || rt="$here/../lib/git-hooks/resolve-tool.sh"
# shellcheck source=../../../lib/git-hooks/resolve-tool.sh
. "$rt" || exit 1
# shellcheck source=markdown-gates.sh
. "$here/markdown-gates.sh" || exit 1
# shellcheck source=adapters.sh
. "$here/adapters.sh" || exit 1

resolve=()
if [[ "${1:-}" == --resolve ]]; then
  shift
  for f in "$@"; do
    [[ "$f" == /* ]] || f="$PWD/$f"
    resolve+=("$f")
  done
  set -- --resolve
fi
checks_init pre-commit "$@" || exit 0
if [[ " $CHECKS_ARGS " == *" --resolve "* ]]; then
  rt_print format "$PWD" ${resolve[@]+"${resolve[@]}"}
  exit 0
fi
[[ "$CHECKS_MODE" == pre-commit ]] || exit 0

candidates=()
while IFS= read -r -d '' f; do
  rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

# shellcheck disable=SC2086 # the config names split on spaces
checks_refuse_config_drift $RT_DRIFT_CONFIGS -- "${candidates[@]}" || exit 1
rt_group format "$PWD" "${candidates[@]}"
((RT_GN)) || exit 0

runs=()
tool_failed=0
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  rt_require
  case $? in
  0) runs[i]=1 ;;
  2) runs[i]=0 tool_failed=1 ;;
  *) runs[i]=0 ;;
  esac
done

refused=0
for ((i = 0; i < RT_GN; i++)); do
  ((runs[i])) || continue
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    if [[ -f "$f" && ! -L "$f" ]] && checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done
done
((refused)) && exit 1

has_mkdir=0
command -v mkdir >/dev/null 2>&1 && has_mkdir=1
has_ln=0
command -v ln >/dev/null 2>&1 && has_ln=1
mf_mkdir() {
  if ((has_mkdir)); then
    mkdir -p "$1"
  else
    node -e 'require("fs").mkdirSync(process.argv[1], { recursive: true })' "$1"
  fi
}
mf_symlink() {
  if ((has_ln)); then
    ln -s "$1" "$2"
  else
    node -e 'require("fs").symlinkSync(process.argv[1], process.argv[2])' "$1" "$2"
  fi
}

US=$'\x1f'
RS=$'\x1e'
mf_yes="$US" mf_no="$US"
mf_nm_ok() {
  local nm=node_modules
  [[ "$1" == . ]] || nm="$1/node_modules"
  [[ "$mf_yes" == *"$US$1$US"* ]] && return 0
  [[ "$mf_no" == *"$US$1$US"* ]] && return 1
  if [[ -d "$nm" && ! -L "$nm" && -z "$(git ls-files -- ":(literal)$nm" 2>/dev/null)" ]] &&
    git check-ignore -q "$nm/.cache" 2>/dev/null; then
    mf_yes+="$1$US"
    return 0
  fi
  mf_no+="$1$US"
  return 1
}
mf_base() {
  local d
  md_config_state "$1" .
  d="${MD_NEAREST%/*}"
  [[ "$d" == "$MD_NEAREST" ]] && d=.
  d="${d#./}"
  while :; do
    MF_BASE="$d"
    mf_nm_ok "$d" && return 0
    [[ "$d" == . ]] && break
    if [[ "$d" == */* ]]; then d="${d%/*}"; else d=.; fi
  done
  MF_BASE=""
}

proot="$(pwd -P)"
mf_bases=() spines=() checks=() mirrors=() made=() mf_status=0
trap 'mf_status=$?; for m in ${made[@]+"${made[@]}"}; do rm -rf -- "${m:?}"; done; checks_finish "$mf_status" || exit 1' EXIT
gcopies=()
pairs="$CHECKS_TMP/pairs"
: >"$pairs"
written=()
for ((i = 0; i < RT_GN; i++)); do
  gcopies[i]=""
  ((runs[i])) || continue
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    mf_base "$f"
    for ((k = 0; k < ${#mf_bases[@]}; k++)); do
      [[ "${mf_bases[k]}" == "$MF_BASE" ]] && break
    done
    if ((k == ${#mf_bases[@]})); then
      mf_bases[k]="$MF_BASE" spines[k]="$US.$US" checks[k]="$US"
      mirrors[k]="$CHECKS_TMP/mirror$k"
      if [[ -n "$MF_BASE" ]] && cache="$MF_BASE/node_modules/.cache/markdown-format" && cache="${cache#./}" &&
        mf_mkdir "$cache" 2>/dev/null && m="$(mktemp -d "$PWD/$cache/format.XXXXXX" 2>/dev/null)"; then
        made+=("$m")
        mirrors[k]="$m"
      fi
    fi
    checks[k]+="$f$US"
    gcopies[i]+="$k$RS$f$US"
    printf '%s\0%s\0' "$k" "$f" >>"$pairs"
    written+=("$f")
    d="$f"
    while [[ "$d" == */* ]]; do
      d="${d%/*}"
      [[ "${spines[k]}" == *"$US$d$US"* ]] || spines[k]+="$d$US"
    done
  done
done

((${#written[@]})) || exit "$tool_failed"

mf_link() {
  local r="${1#./}"
  [[ -e "$mirror/$r" || -L "$mirror/$r" || "$checked" == *"$US$r$US"* ]] && return 0
  case "$r" in *.md | *.mdc | *.markdown) return 0 ;; *) ;; esac
  [[ "$r" == */* ]] && mf_mkdir "$mirror/${r%/*}"
  mf_symlink "$PWD/$r" "$mirror/$r"
}
for ((k = 0; k < ${#mf_bases[@]}; k++)); do
  mirror="${mirrors[k]}" spine="${spines[k]}" checked="${checks[k]}"
  configs=()
  rest="${spine#"$US"}"
  while [[ -n "$rest" ]]; do
    d="${rest%%"$US"*}"
    rest="${rest#*"$US"}"
    mf_mkdir "$mirror/$d"
    mf_nm_ok "$d" && mf_link "$d/node_modules"
    for name in $RT_DRIFT_CONFIGS .gitignore; do
      [[ -f "$d/$name" ]] || continue
      mf_link "$d/$name"
      [[ "$name" == .gitignore ]] || configs+=("$d/$name")
    done
  done
  if ((${#configs[@]})); then
    MD_MODULES=() MD_TRUST_BLOCK=""
    md_collect_modules "$proot" "${configs[@]}" || :
    for m in ${MD_MODULES[@]+"${MD_MODULES[@]}"}; do
      mf_link "${m#"$proot"/}"
    done
  fi
  rest="${checked#"$US"}"
  while [[ -n "$rest" ]]; do
    f="${rest%%"$US"*}"
    rest="${rest#*"$US"}"
    cat -- "$f" >"$mirror/$f"
  done
done

out="$CHECKS_TMP/markdownlint"
: >"$out"
rc=0
for ((k = 0; k < ${#mf_bases[@]}; k++)); do
  for ((i = 0; i < RT_GN; i++)); do
    copies=()
    rest="${gcopies[i]:-}"
    while [[ -n "$rest" ]]; do
      e="${rest%%"$US"*}"
      rest="${rest#*"$US"}"
      [[ "${e%%"$RS"*}" == "$k" ]] && copies+=("${mirrors[k]}/${e#*"$RS"}")
    done
    ((${#copies[@]})) || continue
    rt_use "$i"
    RT_DIR="${mirrors[k]}"
    rt_run "${copies[@]}" >>"$out" 2>&1
    one=$?
    ((one > rc)) && rc=$one
  done
done

if ((rc > 1)); then
  printf 'markdown-format: markdownlint-cli2 failed:\n' >&2
  cat "$out" >&2
  exit 1
fi

checks_changed_lines || exit 1
node -e '
const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const rangesPath = process.argv[1];
const pairsPath = process.argv[2];
const mirrors = process.argv.slice(3);

const rangesByFile = new Map();
const rangesText = fs.readFileSync(rangesPath, "utf8");
for (const line of rangesText.split(/\r?\n/)) {
  if (!line) continue;
  const parts = line.split("\t");
  if (parts.length < 3) continue;
  const file = parts[0];
  const s = Number(parts[1]);
  const e = Number(parts[2]);
  let list = rangesByFile.get(file);
  if (!list) {
    list = [];
    rangesByFile.set(file, list);
  }
  list.push([s, e]);
}

function splitLines(buf) {
  if (buf.length === 0) return [];
  const lines = [];
  let start = 0;
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] === 0x0a) {
      lines.push(buf.subarray(start, i + 1));
      start = i + 1;
    }
  }
  if (start < buf.length) lines.push(buf.subarray(start));
  return lines;
}

function overlaps(ranges, oldStart, oldCount) {
  if (!ranges || ranges.length === 0) return false;
  const lo = oldCount === 0 ? (oldStart === 0 ? 1 : oldStart) : oldStart;
  const hi = oldCount === 0 ? oldStart + 1 : oldStart + oldCount - 1;
  for (const [s, e] of ranges) {
    if (lo <= e && hi >= s) return true;
  }
  return false;
}

const rawPairs = fs.readFileSync(pairsPath).toString("utf8");
const tokens = rawPairs.split("\0");
for (let idx = 0; idx + 1 < tokens.length; idx += 2) {
  const k = Number(tokens[idx]);
  const rel = tokens[idx + 1];
  if (!rel) continue;
  const origPath = path.resolve(rel);
  const fmtPath = path.join(mirrors[k], rel);
  const origBuf = fs.readFileSync(origPath);
  const fmtBuf = fs.readFileSync(fmtPath);
  if (origBuf.equals(fmtBuf)) continue;

  const r = cp.spawnSync(
    "git",
    ["-c", "core.quotePath=false", "diff", "--no-index", "--no-color", "--no-ext-diff", "--no-textconv", "-U0", "--text", "--", origPath, fmtPath],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }
  );
  if (r.error || (r.status !== 0 && r.status !== 1)) {
    process.stderr.write("markdown-format: git diff failed for " + rel + "\n");
    process.exit(2);
  }

  const hunks = [];
  let left = 0;
  let right = 0;
  for (const line of r.stdout.split("\n")) {
    if (left > 0 || right > 0) {
      const c = line[0];
      if (c === "-") { left--; continue; }
      if (c === "+") { right--; continue; }
      if (c === " ") { left--; right--; continue; }
      if (c === "\\") continue;
    }
    const m = /^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@/.exec(line);
    if (m) {
      const oldStart = Number(m[1]);
      const oldCount = m[2] === undefined ? 1 : Number(m[2]);
      const newStart = Number(m[3]);
      const newCount = m[4] === undefined ? 1 : Number(m[4]);
      hunks.push({ oldStart, oldCount, newStart, newCount });
      left = oldCount;
      right = newCount;
    }
  }
  if (hunks.length === 0) {
    process.stderr.write("markdown-format: failed to parse diff hunks for " + rel + "\n");
    process.exit(2);
  }

  const origLines = splitLines(origBuf);
  const fmtLines = splitLines(fmtBuf);
  const ranges = rangesByFile.get(rel);
  const outChunks = [];
  let cursor = 0;
  let applied = 0;
  let skipped = 0;

  for (const h of hunks) {
    if (!overlaps(ranges, h.oldStart, h.oldCount)) {
      skipped++;
      continue;
    }
    applied++;
    const cut = h.oldCount === 0 ? h.oldStart : h.oldStart - 1;
    const ncut = h.newCount === 0 ? h.newStart : h.newStart - 1;
    for (let j = cursor; j < cut; j++) outChunks.push(origLines[j]);
    for (let j = ncut; j < ncut + h.newCount; j++) outChunks.push(fmtLines[j]);
    cursor = cut + h.oldCount;
  }

  if (skipped > 0) {
    const noun = skipped === 1 ? "hunk" : "hunks";
    process.stderr.write("markdown-format: " + rel + ": skipped formatting drift on untouched lines (" + skipped + " " + noun + ")\n");
  }
  if (applied > 0) {
    for (let j = cursor; j < origLines.length; j++) outChunks.push(origLines[j]);
    const mergedBuf = Buffer.concat(outChunks);
    if (!mergedBuf.equals(origBuf)) fs.writeFileSync(origPath, mergedBuf);
  }
}
' "$CHECKS_TMP/ranges" "$pairs" "${mirrors[@]}"
apply_rc=$?
if ((apply_rc != 0)); then
  checks_tool_failed node "$apply_rc" 'applying formatted hunks'
  exit 1
fi

checks_restage "${written[@]}"
exit "$tool_failed"
