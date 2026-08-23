# shellcheck shell=bash
# Shared dead-code candidate shapes and detector plumbing for
# /code-tidying:audit-dead-code (sourceable; not invoked directly).
# Shape definitions and default tiers: the skill's SKILL.md "Candidate shapes and default tiers".
#
# A CANDIDATE is a symbol or file a detector could not see a reference to. It is
# not a verdict: the model adjudicates candidates into dead / uncertain / alive
# against dynamic-usage evidence, and only the first two are ever re-emitted as
# records. The tier a shape carries here is the candidate's PRIOR, set from the
# measured precision of the lane that produced it, never from a per-finding guess.
#
# Every parser rejects a line it does not recognize rather than coercing it: a
# detector that changed its output format must surface as drift (T3), because
# both knip and vulture can print a non-finding on stdout in exact finding shape.

# ---------------------------------------------------------------------------
# Excerpt / shape vocabulary
# ---------------------------------------------------------------------------

# Tabs are collapsed to spaces because every internal record this skill passes
# between stages is tab-separated; an excerpt carrying a raw tab would split a
# field.
dc_trim_excerpt() {
  local line="$1"
  line="${line//$'\r'/}"
  line="${line//$'\t'/ }"
  line="${line#"${line%%[![:space:]]*}"}"
  if ((${#line} > 120)); then
    line="${line:0:117}..."
  fi
  printf '%s' "$line"
}

# Default tier per shape. T1 = high-confidence candidate, T2 = uncertain
# candidate, T3 = detector drift (an output line no parser recognized). The `*)`
# arm and the driver's own `*)` counter arm must agree: anything unmapped is T3.
dc_shape_tier() {
  case "$1" in
  py-unreachable | go-unused-unexported | unreferenced-symbol) printf '1' ;;
  ts-unused-file | ts-unused-export | ts-unused-type | ts-unused-enum-member | py-unused-symbol) printf '2' ;;
  *) printf '3' ;;
  esac
}

# Directories whose contents are never scanning INPUT. `evals/fixtures` matches
# the policy this repository's ruff.toml already sets: a detector corpus is not
# the consumer's code. The reference SEARCH is a separate scope and is not
# filtered by this — a reference from anywhere still saves a symbol.
dc_is_excluded_path() {
  case "/$1" in
  */evals/fixtures/* | */node_modules/* | */.venv/* | */venv/* | */.git/* | \
    */dist/* | */build/* | */vendor/* | */.next/* | */__pycache__/*) return 0 ;;
  *) ;;
  esac
  return 1
}

# In-skill fallback glob table. A consumer repo that ships
# .claude/ecosystems/<eco>.yaml has richer globs; this table is the common path
# because most repos do not. `install-hint` is deliberately not consumed — it
# names an ecosystem's lint tools, never a dead-code detector.
dc_lang_of_path() {
  case "${1,,}" in
  *.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs) printf 'ts' ;;
  *.py) printf 'py' ;;
  *.go) printf 'go' ;;
  *.sh | *.bash) printf 'shell' ;;
  *.ps1 | *.psm1) printf 'pwsh' ;;
  *) printf 'other' ;;
  esac
}

dc_dir_nonempty() {
  local d="$1" entry
  [[ -d "$d" ]] || return 1
  for entry in "$d"/* "$d"/.[!.]*; do
    [[ -e "$entry" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Binary resolution — locate, then PROVE by invocation
# ---------------------------------------------------------------------------

# Resolve a repository-local pinned binary without invoking a package runner.
# npm creates an extensionless POSIX shim in node_modules/.bin alongside its
# Windows .cmd launcher; uv/venv creates one in .venv/bin. Walk upward from a
# start directory to the repo root so a monorepo workspace install is visible,
# follow symlinks with a hop cap, and require the PHYSICAL target to stay inside
# the repository. That rejects a checked-in or replaced .bin symlink escaping
# the repository trust boundary. Modeled on resolve_repo_markdownlint() in
# plugins/markdown-format/hooks/markdown-format.sh, widened from node_modules to
# the repo root because a .venv shim resolves into .venv/lib, not node_modules.
#
# This is a LOCATOR only. Measured: `command -v rust-analyzer` succeeds while
# invocation fails (a rustup shim), so presence is proven by dc_binary_invocable.
dc_resolve_local_binary() {
  local name="$1" start_dir="$2" repo_root="$3"
  local root_physical dir dir_physical parent candidate target link target_dir depth sub
  root_physical="$(cd -P -- "$repo_root" 2>/dev/null && pwd -P)" || return 1
  dir="$start_dir"
  while [[ -n "$dir" ]]; do
    for sub in node_modules/.bin .venv/bin venv/bin; do
      candidate="$dir/$sub/$name"
      [[ -f "$candidate" && -x "$candidate" ]] || continue
      target="$candidate"
      depth=0
      while [[ -L "$target" ]]; do
        depth=$((depth + 1))
        ((depth <= 32)) || return 1
        link="$(readlink "$target" 2>/dev/null)" || return 1
        case "$link" in
        /*) target="$link" ;;
        [A-Za-z]:[\\/]*)
          command -v cygpath >/dev/null 2>&1 || return 1
          target="$(cygpath -u "$link" 2>/dev/null)" || return 1
          ;;
        *) target="$(dirname -- "$target")/$link" ;;
        esac
      done
      if [[ -f "$target" && -x "$target" ]]; then
        target_dir="$(cd -P -- "$(dirname -- "$target")" 2>/dev/null && pwd -P)" || true
        if [[ -n "$target_dir" ]]; then
          target="$target_dir/$(basename -- "$target")"
          case "$target" in
          "$root_physical"/*)
            printf '%s' "$candidate"
            return 0
            ;;
          *) ;;
          esac
        fi
      fi
    done
    dir_physical="$(cd -P -- "$dir" 2>/dev/null && pwd -P)" || true
    if [[ -n "$dir_physical" && "$dir_physical" == "$root_physical" ]]; then
      break
    fi
    parent="$(dirname -- "$dir")"
    [[ "$parent" == "$dir" ]] && break
    dir="$parent"
  done
  return 1
}

# Repo-local first, PATH second: a pinned devDependency is the version that
# matches the project it is about to judge.
dc_locate_binary() {
  local name="$1" start_dir="$2" repo_root="$3" found
  if found="$(dc_resolve_local_binary "$name" "$start_dir" "$repo_root")"; then
    printf '%s' "$found"
    return 0
  fi
  if found="$(command -v -- "$name" 2>/dev/null)"; then
    printf '%s' "$found"
    return 0
  fi
  return 1
}

# Presence proof. A locator hit is a filename; only a successful invocation is
# evidence the tool runs here.
dc_binary_invocable() {
  local bin="$1"
  shift
  "$bin" "$@" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Detector output parsers — each rejects what it does not recognize
# ---------------------------------------------------------------------------

# vulture emits `<path>:<line>: <kind> <detail> (NN% confidence)`. Measured:
# handed a non-.py file it emits a PARSE ERROR in exactly that shape on stdout
# with exit 0, so the kind gate below is the only thing separating a finding
# from a parse error. Anything outside unused|unreachable|unsatisfiable is drift.
# Returns 0 with `<file><TAB><line><TAB><shape><TAB><excerpt>` in the named
# variable, 1 when the line is drift.
dc_parse_vulture_line() {
  local line="${1//$'\r'/}" out_var="$2"
  local re='^(.+):([0-9]+):[[:space:]](unused|unreachable|unsatisfiable)[[:space:]](.*)$'
  local shape
  [[ $line =~ $re ]] || return 1
  case "${BASH_REMATCH[3]}" in
  unused) shape='py-unused-symbol' ;;
  *) shape='py-unreachable' ;;
  esac
  printf -v "$out_var" '%s\t%s\t%s\t%s' \
    "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$shape" \
    "$(dc_trim_excerpt "${BASH_REMATCH[3]} ${BASH_REMATCH[4]}")"
}

# gopls check emits `<path>:<line>:<col>: <message>` on stdout. Returns
# 0 = a candidate, 1 = drift (not a diagnostic at all), 2 = a diagnostic this
# lane does not own (an exported symbol, or any non-unused hint). The
# unexported-only filter is the lane's DECLARED coverage, not a defect.
dc_parse_gopls_line() {
  local line="${1//$'\r'/}" out_var="$2"
  local re='^(.+):([0-9]+):([0-9]+):[[:space:]](.*)$'
  local rest name
  [[ $line =~ $re ]] || return 1
  rest="${BASH_REMATCH[4]}"
  case "$rest" in
  *"is unused"* | *"unused "*) ;;
  *) return 2 ;;
  esac
  name="${rest%% is unused*}"
  name="${name##* }"
  name="${name#\"}"
  name="${name%\"}"
  case "$name" in
  [A-Z]*) return 2 ;;
  *) ;;
  esac
  printf -v "$out_var" '%s\t%s\t%s\t%s' \
    "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" 'go-unused-unexported' \
    "$(dc_trim_excerpt "$rest")"
}

# A gopls run whose module graph did not resolve prints an import error on
# stdout, suppresses its hints, and still exits 0 — false NEGATIVES, the
# opposite of knip's unrestored false positives.
dc_gopls_stdout_is_degraded() {
  case "${1//$'\r'/}" in
  *"could not import"* | *"no required module provides"* | *"cannot find module"* | \
    *"missing go.sum entry"* | *"is not in std"*) return 0 ;;
  *) ;;
  esac
  return 1
}

# knip --reporter json, scanned tolerantly on stdin. Emits
# `<file><TAB><line><TAB><shape><TAB><name>` rows on stdout; exits 1 when it
# recognized nothing, which the driver reads as "parsed nothing", never as
# "clean".
#
# Tolerance rules, deliberate because the JSON shape is version-coupled:
#   - a bare string element of `files` is a file path;
#   - a bare string element of `exports` / `enumMembers` is a symbol name;
#   - a bare string element of `types` is IGNORED — knip uses that array to list
#     which issue types a record carries, so its strings are category labels,
#     not unused type symbols;
#   - an OBJECT element of any of the four is read through its `name` / `symbol`
#     key (and its `line` key when present), which is how a type symbol is
#     recognized.
# Class members are not read: knip 6.32.2 rejects `--include classMembers`
# outright, so there is nothing to parse.
dc_parse_knip_json() {
  awk '
  function shape_for(k) {
    if (k == "files") return "ts-unused-file"
    if (k == "exports") return "ts-unused-export"
    if (k == "types") return "ts-unused-type"
    if (k == "enumMembers") return "ts-unused-enum-member"
    return ""
  }
  function emit(k, nm, ln,   sh, f) {
    sh = shape_for(k)
    if (sh == "" || nm == "") return
    f = (k == "files") ? nm : (curfile == "" ? "-" : curfile)
    if (ln == "") ln = "0"
    printf "%s\t%s\t%s\t%s\n", f, ln, sh, nm
    emitted++
  }
  function elemstr(k, s) {
    if (k == "types") return
    emit(k, s, "")
  }
  function setfield(k, s) {
    if (k == "file") curfile = s
    else if (k == "name" || k == "symbol") oname[depth] = s
  }
  {
    L = length($0)
    for (i = 1; i <= L; i++) {
      c = substr($0, i, 1)
      if (instr) {
        if (esc) { buf = buf c; esc = 0; continue }
        if (c == "\\") { esc = 1; continue }
        if (c == "\"") { instr = 0; str = buf; have = 1; continue }
        buf = buf c
        continue
      }
      if (c ~ /^[0-9]$/) { num = num c; continue }
      if (num != "") {
        if (stack[depth] == "o" && key == "line") oline[depth] = num
        num = ""
      }
      if (c == "\"") { instr = 1; buf = ""; continue }
      if (c == ":") { if (have) { key = str; have = 0 } ; continue }
      if (c == "[") { have = 0; depth++; stack[depth] = "a"; skey[depth] = key; key = ""; continue }
      if (c == "]") {
        if (have) { if (stack[depth] == "a") elemstr(skey[depth], str); have = 0 }
        if (depth > 0) depth--
        continue
      }
      if (c == "{") {
        depth++; stack[depth] = "o"; skey[depth] = key; key = ""
        oname[depth] = ""; oline[depth] = ""
        continue
      }
      if (c == "}") {
        if (have) { setfield(key, str); have = 0 }
        if (depth > 1 && stack[depth] == "o" && stack[depth - 1] == "a" && oname[depth] != "")
          emit(skey[depth - 1], oname[depth], oline[depth])
        if (depth > 0) depth--
        continue
      }
      if (c == ",") {
        if (have) {
          if (stack[depth] == "a") elemstr(skey[depth], str)
          else setfield(key, str)
          have = 0
        }
        continue
      }
    }
  }
  END { exit(emitted > 0 ? 0 : 1) }
  '
}

# A knip run is DEGRADED when it wrote an ERROR: line to stderr. Measured: that
# line goes to stderr, which --reporter json discards, and an unrestored run
# MANUFACTURES unused-file findings rather than failing. `unresolved` and
# `unlisted` are NOT a restore signal — measured byte-identical restored vs
# unrestored — so they are never read here.
dc_knip_stderr_is_degraded() {
  local err_file="$1" line
  [[ -s "$err_file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    case "$line" in
    *"ERROR:"*) return 0 ;;
    *) ;;
    esac
  done <"$err_file"
  return 1
}

# knip evaluates a repository-controlled JS/TS config module through jiti. That
# is a disclosed exception to the never-execute-project-code rule, narrower than
# a build, and every run that loads one says so in the report.
dc_knip_config_module() {
  local root="$1" name
  for name in knip.config.ts knip.config.js knip.config.mjs knip.config.cjs knip.ts knip.js; do
    if [[ -f "$root/$name" ]]; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# grep lane — the portable reference-search floor
# ---------------------------------------------------------------------------

# Emit `<line><TAB><name><TAB><text>` for every symbol DEFINITION in one file.
# The extractor set is this lane's declared coverage: shell functions and
# PowerShell functions. Names under three characters are dropped — at that
# length the reference search is noise, not evidence.
dc_symbol_defs() {
  local file="$1" lang="$2"
  local line name num=0
  local sh_paren='^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_:.-]*)[[:space:]]*\(\)[[:space:]]*\{'
  local sh_kw='^[[:space:]]*function[[:space:]]+([A-Za-z_][A-Za-z0-9_:.-]*)'
  local ps_kw='^[[:space:]]*[Ff]unction[[:space:]]+([A-Za-z_][A-Za-z0-9_-]*)'
  while IFS= read -r line || [[ -n "$line" ]]; do
    num=$((num + 1))
    line="${line//$'\r'/}"
    name=""
    if [[ "$lang" == 'shell' ]]; then
      if [[ $line =~ $sh_paren ]]; then
        name="${BASH_REMATCH[2]}"
      elif [[ $line =~ $sh_kw ]]; then
        name="${BASH_REMATCH[1]}"
      fi
    elif [[ $line =~ $ps_kw ]]; then
      name="${BASH_REMATCH[1]}"
    fi
    [[ -n "$name" ]] || continue
    ((${#name} >= 3)) || continue
    printf '%s\t%s\t%s\n' "$num" "$name" "$(dc_trim_excerpt "$line")"
  done <"$file"
}
