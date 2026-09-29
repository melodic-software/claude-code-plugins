#!/usr/bin/env bash
# Probe: a Windows exec-form hook must name a real executable and keep its args.
#
#   scripts/check-exec-form-windows-probe.sh
#
# Static half (every host): an exec-form hook (`args` present) whose `command`
# is a shebang script, a .cmd/.bat shim, a bare name that is not on the
# EXEC_NAME_ALLOWLIST of scripts/check-hook-exec-form.sh, or a bash.exe/sh.exe
# path fails. Shell form (no `args`) is not inspected. This script does not
# rewrite rows. A .sh path is not a legal `command`; the landed spelling is
# "node" plus hooks/exec-bash.mjs. Bare bash plus the script in args is the
# shape scripts/check-hook-exec-form.sh already rejects.
#
# Spawn half (Windows, or EXEC_FORM_WINDOWS_PROBE_FORCE=1): spawn node.exe with
# an args array and a stdin payload, with no shell. If the sentinel arg is
# missing or the process image is bash.exe, exit 1 and the fleet sweep stops
# (#90495: exec-form args dropped, the hook still routed
# through bash.exe). On any other host the spawn half prints a SKIP line and
# exits 0 when the spellings are clean. That skip is fail-soft: it does not
# show that #90495 is absent and it does not authorize converting .sh rows.
# EXEC_FORM_WINDOWS_PROBE_REQUIRE_SPAWN=1 turns a missing node.exe into a
# failure on a host where the spawn half runs (the Windows CI lane).
# EXEC_FORM_WINDOWS_PROBE_SIMULATE_DROP=1 omits the sentinel so the stop path
# can be tested.
#
# Launcher half (same condition as the spawn half, after it): a native node
# runs lib/exec-bash.mjs, the launcher every hook row goes through, with an
# explicit env object and a recording bash script, the way Claude Code runs a
# hook. It exits 1 when the argv token, the stdin payload, a backslash
# CLAUDE_PLUGIN_ROOT (in the env and in an argument) or the script's own exit 2
# does not come back through the launcher. On Windows it also exits 1 when the
# script does not run under Git Bash, when a launcher with no bash to find does
# not exit 1 on a first stderr line naming the script and saying it enforces
# nothing, or when Git's bin directory on PATH does not resolve bash. Off
# Windows those three checks are skipped and the rest run.
# EXEC_FORM_WINDOWS_PROBE_SIMULATE_LAUNCHER_DROP=1 makes the recording script
# exit 0 instead of 2 so the failure path can be tested.
#
# Live half (EXEC_FORM_WINDOWS_PROBE_LIVE=1, and a `claude` on PATH): one
# throwaway exec-form PreToolUse row under `claude -p`. Without that opt-in,
# or without `claude`, this half skips fail-soft with the same non-authorization.
#
# The four-part record is restated in docs/plugin-philosophy.md
# ("Windows exec-form probe") and in
# plugins/claude-config/skills/audit/reference/audit-checklist.md (Category D).
#   Claim: On Windows, exec form resolves `command` as an executable and spawns
#     it directly with `args` as the argument vector. There is no shell, so a
#     shebang is not honored, and `command` must be a real executable such as
#     a `.exe`. `.cmd` and `.bat` cannot be spawned. If that spawn drops `args`
#     or the image is bash.exe, the fleet sweep stops.
#   Basis: https://code.claude.com/docs/en/hooks "Exec form and shell form",
#     verbatim "On Windows, exec form requires `command` to resolve to a real
#     executable such as a `.exe`." Full raw hooks.md read 2026-09-28
#     (330813 bytes, SHA-256
#     57e3b47d55acfbae3dcdc112866c8c0f75528d8b5c4fca9bfcdaa904d4728218; the slug
#     is listed in https://code.claude.com/docs/llms.txt). The same section
#     says there is no shell and that `shell` is ignored when `args` is set.
#     https://github.com/anthropics/claude-code/issues/90495 (open).
#   As of: 2026-09-28.
#   Recheck: that Windows sentence changes, `shell` stops being ignored when
#     `args` is set, or #90495 closes.
#
# Exit 0 clean, 1 findings (including a reproduced args-drop), 2 environment or
# usage. Findings on stderr; the clean statement and SKIP lines on stdout
# (README.md, "The check-script contract"). An unparsable hook config is a
# finding (1), as in scripts/check-hook-exec-form.sh.
# shellcheck disable=SC2016
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/manifest-path-guard.sh
. scripts/lib/manifest-path-guard.sh || exit 2

if ! command -v jq >/dev/null 2>&1; then
  echo "check-exec-form-windows-probe: jq is required but not installed" >&2
  exit 2
fi

FRONTMATTER_READER="scripts/check-hook-exec-form-frontmatter.py"
REQUIREMENTS=".github/requirements-ci.txt"
pyyaml_pin="$(awk '/^pyyaml==/ {
  sub(/^pyyaml==/, "")
  sub(/[[:space:]\\].*$/, "")
  print
  exit
}' "$REQUIREMENTS" 2>/dev/null || true)"

reader_cmd=()
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
    reader_cmd=("$candidate")
    break
  fi
done
if ((${#reader_cmd[@]} == 0)) && [[ -n "$pyyaml_pin" ]] && command -v uv >/dev/null 2>&1; then
  reader_cmd=(uv run --quiet --no-project --with "pyyaml==$pyyaml_pin" python)
fi
if ((${#reader_cmd[@]} == 0)); then
  echo "check-exec-form-windows-probe: no python with PyYAML and no uv; the frontmatter surface cannot be read" >&2
  exit 2
fi

# One allowlist for bare names: the gate's own EXEC_NAME_ALLOWLIST line. A probe
# that cannot read it exits 2 rather than guess a second list.
GATE="scripts/check-hook-exec-form.sh"
allow_line="$(grep -E '^EXEC_NAME_ALLOWLIST=\([^)]*\)$' "$GATE" 2>/dev/null || true)"
exec_names=()
if [[ -n "$allow_line" && "$allow_line" != *$'\n'* ]]; then
  allow_line="${allow_line#EXEC_NAME_ALLOWLIST=(}"
  read -r -a exec_names <<<"${allow_line%)}"
fi
if ((${#exec_names[@]} == 0)); then
  echo "check-exec-form-windows-probe: cannot read exactly one EXEC_NAME_ALLOWLIST=(...) line from ${GATE}" >&2
  exit 2
fi

windows=0
case "${OSTYPE:-}" in
msys* | cygwin* | win32) windows=1 ;;
*) ;;
esac

errors=0
ok_rows=0
notes=()
note() { notes+=("$1"); }

flag() {
  local file="$1" where="$2" cmd="$3" why="$4"
  echo "EXEC-FORM WINDOWS: ${file}:${where}: exec-form command \"${cmd}\" ${why}" >&2
  errors=$((errors + 1))
}

# lower <string>
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# image_name <path>
# Node's process.execPath on Windows is a backslash path. ${path##*/} leaves
# C:\Program Files\nodejs\node.exe intact, so the spawn half reports that image
# as not node.exe and stops the fleet sweep.
image_name() {
  local base="${1##*/}"
  base="${base##*\\}"
  base="${base//$'\r'/}"
  lower "$base"
}

# allowed_name <command>: exact match, the way the gate compares.
allowed_name() {
  local name
  for name in "${exec_names[@]}"; do
    if [[ "$1" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

NOT_EXE_HINT='is not a real Windows executable (no shell and no shebang). Use "command": "node" with the script in args; a bash script goes through hooks/exec-bash.mjs.'

# consider <file> <where> <command>
consider() {
  local file="$1" where="$2" cmd="$3" base low
  # Git bash on Windows keeps a CR on jq's last TSV field, so "node" would
  # miss the exact match below and every real node row would be flagged.
  cmd="${cmd//$'\r'/}"
  cmd="${cmd%"${cmd##*[![:space:]]}"}"
  case "$cmd" in
  */* | *\\*)
    base="${cmd##*/}"
    base="${base##*\\}"
    low="$(lower "$base")"
    case "$low" in
    bash.exe | sh.exe)
      flag "$file" "$where" "$cmd" "names a shell image (${base}). Use \"command\": \"node\" with hooks/exec-bash.mjs and then the script; a machine-specific bash.exe path is not a portable exec-form row."
      ;;
    *.exe)
      ok_rows=$((ok_rows + 1))
      ;;
    *)
      flag "$file" "$where" "$cmd" "$NOT_EXE_HINT"
      ;;
    esac
    ;;
  *)
    # shellcheck disable=SC2310 # allowed_name is a pure loop test; it cannot fail unexpectedly
    if allowed_name "$cmd"; then
      ok_rows=$((ok_rows + 1))
    else
      flag "$file" "$where" "$cmd" "$NOT_EXE_HINT"
    fi
    ;;
  esac
}

JQ_EXEC_FORM='
  def render: map(if type == "number" then "[" + tostring + "]" else "." + . end) | join("");
  input_filename as $file
  | (__ROOT__) as $doc
  | ([[]] + [$doc | paths(objects)])[]
  | . as $p
  | ($doc | getpath($p)) as $o
  | select(($o | type) == "object")
  | select(($o | has("command")) and ($o | has("args")))
  | select(($o.command | type) == "string")
  | $file + "\t" + ($p | render) + "\t"
    + (if ($o.args | type) == "array" then "ROW" else "NOT-ARRAY" end)
    + "\t" + ($o.command | gsub("[\r\n\t]"; " "))
'

_consume_json_rows() {
  local prefix="$1" file path kind cmd
  while IFS=$'\t' read -r file path kind cmd; do
    [[ -n "$file" || -n "$path" || -n "$cmd" ]] || continue
    if [[ "$kind" == "NOT-ARRAY" ]]; then
      flag "$file" "${prefix}${path}" "$cmd" "has an args value that is not an array."
      continue
    fi
    consider "$file" "${prefix}${path}" "$cmd"
  done <<<"$2"
}

scan_json_files() {
  local root="$1" prefix="$2"
  shift 2
  (($#)) || return 0
  local prog out f
  prog="${JQ_EXEC_FORM//__ROOT__/$root}"
  if out="$(jq -r "$prog" "$@" 2>/dev/null)"; then
    _consume_json_rows "$prefix" "$out"
    return 0
  fi
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    if ! out="$(jq -r "$prog" "$f" 2>/dev/null)"; then
      echo "UNREADABLE HOOK CONFIG: ${f}: not parseable as JSON; this gate cannot clear it" >&2
      errors=$((errors + 1))
      continue
    fi
    _consume_json_rows "$prefix" "$out"
  done
}

JQ_MANIFEST='
  def render: map(if type == "number" then "[" + tostring + "]" else "." + . end) | join("");
  input_filename as $file
  | (.hooks | type) as $t
  | if $t == "object" then
      (.hooks) as $doc
      | ([[]] + [$doc | paths(objects)])[]
      | . as $p
      | ($doc | getpath($p)) as $o
      | select(($o | type) == "object")
      | select(($o | has("command")) and ($o | has("args")))
      | select(($o.command | type) == "string")
      | "E\t" + $file + "\t" + ($p | render) + "\t"
        + (if ($o.args | type) == "array" then "ROW" else "NOT-ARRAY" end)
        + "\t" + ($o.command | gsub("[\r\n\t]"; " "))
    elif $t == "string" then
      "P\t" + $file + "\t" + (.hooks | gsub("[\r\n\t]"; " "))
    elif $t == "array" then
      .hooks[] | select(type == "string") | "P\t" + $file + "\t" + gsub("[\r\n\t]"; " ")
    else
      empty
    end
'

MANIFEST_EXTRA=()

_queue_manifest_path() {
  local plugin="$1" manifest="$2" rel="$3" path
  manifest_path_guard::resolve_to path check-exec-form-windows-probe "$manifest" "$plugin" "$rel"
  [[ -f "$path" ]] || return 0
  MANIFEST_EXTRA+=("$path")
}

_consume_manifest_rows() {
  local rows="$1" kind file rest path form cmd rel plugin
  while IFS=$'\t' read -r kind file rest; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
    E)
      path="${rest%%$'\t'*}"
      rest="${rest#*$'\t'}"
      form="${rest%%$'\t'*}"
      cmd="${rest#*$'\t'}"
      if [[ "$form" == "NOT-ARRAY" ]]; then
        flag "$file" ".hooks${path}" "$cmd" "has an args value that is not an array."
      else
        consider "$file" ".hooks${path}" "$cmd"
      fi
      ;;
    P)
      rel="$rest"
      plugin="${file%/.claude-plugin/plugin.json}"
      _queue_manifest_path "$plugin" "$file" "$rel"
      ;;
    *) ;;
    esac
  done <<<"$rows"
}

scan_manifests() {
  (($#)) || return 0
  local out f
  MANIFEST_EXTRA=()
  if out="$(jq -r "$JQ_MANIFEST" "$@" 2>/dev/null)"; then
    _consume_manifest_rows "$out"
  else
    for f in "$@"; do
      [[ -f "$f" ]] || continue
      if out="$(jq -r "$JQ_MANIFEST" "$f" 2>/dev/null)"; then
        _consume_manifest_rows "$out"
      fi
    done
  fi
  ((${#MANIFEST_EXTRA[@]})) || return 0
  scan_json_files "." "" "${MANIFEST_EXTRA[@]}"
}

scan_frontmatter() {
  local out kind file line detail
  if ! out="$("${reader_cmd[@]}" "$FRONTMATTER_READER" plugins)"; then
    echo "check-exec-form-windows-probe: the frontmatter reader did not complete; this gate cannot clear plugins/" >&2
    exit 2
  fi
  while IFS=$'\t' read -r kind file line detail; do
    case "$kind" in
    V) consider "$file" "$line" "$detail" ;;
    X)
      echo "UNREADABLE FRONTMATTER: ${file}:${line}: ${detail}" >&2
      errors=$((errors + 1))
      ;;
    *) ;;
    esac
  done <<<"$out"
}

hook_jsons=()
manifests=()
for plugin in plugins/*/; do
  plugin="${plugin%/}"
  [[ -f "$plugin/hooks/hooks.json" ]] && hook_jsons+=("$plugin/hooks/hooks.json")
  [[ -f "$plugin/.claude-plugin/plugin.json" ]] && manifests+=("$plugin/.claude-plugin/plugin.json")
done
scan_json_files "." "" "${hook_jsons[@]}"
scan_manifests "${manifests[@]}"
scan_frontmatter

# --- spawn half -------------------------------------------------------------

resolve_node() {
  local candidate resolved base magic
  for candidate in node.exe node; do
    resolved="$(command -v "$candidate" 2>/dev/null || true)"
    [[ -n "$resolved" && -f "$resolved" ]] || continue
    base="$(lower "${resolved##*/}")"
    case "$base" in
    *.cmd | *.bat) continue ;;
    *) ;;
    esac
    if ((windows)); then
      magic="$(dd if="$resolved" bs=2 count=1 2>/dev/null || true)"
      [[ "$magic" == "MZ" ]] || continue
    fi
    printf '%s\n' "$resolved"
    return 0
  done
  return 1
}

run_spawn() {
  local node_exe="$1" payload sentinel js out got bytes exec_path image
  payload='{"probe":"exec-form"}'
  sentinel="exec-form-probe-sentinel-$$"
  js='const fs=require("fs"); let s=""; try { s=fs.readFileSync(0,"utf8"); } catch (e) { s=""; } process.stdout.write(JSON.stringify({execPath:process.execPath,argv:process.argv.slice(1),stdinBytes:Buffer.byteLength(s)}));'
  local -a args=("$node_exe" -e "$js" -- "$sentinel")
  if [[ "${EXEC_FORM_WINDOWS_PROBE_SIMULATE_DROP:-}" == 1 ]]; then
    args=("$node_exe" -e "$js")
  fi
  if ! out="$(printf '%s' "$payload" | "${args[@]}")"; then
    echo "SPAWN-PROBE: node exited non-zero while receiving an args array. Fleet sweep stopped." >&2
    return 1
  fi
  # jq -e would treat a false `any` as failure and hide a real args-drop.
  if ! got="$(jq -r --arg s "$sentinel" 'any(.argv[]; . == $s)' <<<"$out")" ||
    ! bytes="$(jq -r '.stdinBytes' <<<"$out")" ||
    ! exec_path="$(jq -r '.execPath' <<<"$out")"; then
    echo "SPAWN-PROBE: node did not return a probe record. Fleet sweep stopped." >&2
    return 1
  fi
  image="$(image_name "$exec_path")"
  if [[ "$got" != "true" || "$image" == "bash" || "$image" == "bash.exe" || "$image" == "sh" || "$image" == "sh.exe" ]]; then
    echo "ARGS-DROP: Windows exec-form spawn dropped args or routed through bash.exe (anthropics/claude-code#90495). Fleet sweep stopped." >&2
    return 1
  fi
  if [[ "$image" != "node" && "$image" != "node.exe" ]]; then
    echo "SPAWN-PROBE: process image is ${exec_path}, not node.exe. Fleet sweep stopped." >&2
    return 1
  fi
  if [[ "$bytes" != "${#payload}" ]]; then
    echo "SPAWN-PROBE: stdin payload was ${bytes} bytes, expected ${#payload}. Fleet sweep stopped." >&2
    return 1
  fi
  note "check-exec-form-windows-probe: spawn probe delivered the args array to ${image} (stdin ${bytes} bytes)."
  return 0
}

# The driver runs in node, so the launcher gets an explicit env object that no
# MSYS hop rewrites, and every comparison sees the exact strings the script
# saw. argv: launcher, script, token, script exit code, empty dir, Git bin dir.
# The last two are only used on Windows. Findings go to stderr and set the exit
# code; the clean statement goes to stdout.
launcher_driver_js() {
  cat <<'JS'
const { spawnSync } = require("child_process");
const path = require("path");
const [launcher, script, token, exitCode, emptyDir, gitBin] = process.argv.slice(2);
const win = process.platform === "win32";
const root = "C:\\probe root\\plugin";
const rootArg = root + "/hooks/guard.sh";
const payload = '{"probe":"launcher"}';
const problems = [];
const need = (ok, what) => { if (!ok) problems.push(what); };
const launch = (env, args, input) =>
  spawnSync(process.execPath, [launcher, script, ...args], { env, input, encoding: "utf8", timeout: 60000, windowsHide: true });
const firstLine = (r) => (r.stderr || "").split(/\r?\n/)[0];
const ctx = (r) => `exit ${r.status}${r.error ? ", " + r.error.message : ""}, first stderr line ${JSON.stringify(firstLine(r))}`;
const seen = (r) => Object.fromEntries((r.stdout || "").split(/\r?\n/).filter((l) => l.includes("="))
  .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));

const run = launch({ ...process.env, CLAUDE_PLUGIN_ROOT: root }, [token, rootArg, exitCode], payload);
const got = seen(run);
need(got.token === token, `the argv token did not reach the script (${ctx(run)}); exit 0 with no output means the launcher's main never ran`);
need(got.stdin === String(Buffer.byteLength(payload)), `the script read ${got.stdin} stdin bytes, expected ${Buffer.byteLength(payload)}`);
need(run.status === 2, `the script's own exit 2 came back as exit ${run.status}, so a blocking guard would stop blocking`);
need(got.rootenv === root, `CLAUDE_PLUGIN_ROOT reached the script as ${JSON.stringify(got.rootenv)}, expected ${JSON.stringify(root)}`);
need(got.rootarg === rootArg, `a script argument reached the script as ${JSON.stringify(got.rootarg)}, expected ${JSON.stringify(rootArg)}`);
if (win) {
  need(/^(MINGW|MSYS|CYGWIN)/.test(got.uname || ""), `the script ran under uname ${JSON.stringify(got.uname)}, not Git Bash`);
  const hidden = { SystemRoot: process.env.SystemRoot, ProgramFiles: emptyDir, "ProgramFiles(x86)": emptyDir, LOCALAPPDATA: emptyDir };
  const none = launch({ ...hidden, PATH: emptyDir }, [token, rootArg, exitCode], "");
  need(none.status === 1 && !none.stdout && firstLine(none).includes(path.basename(script)) && firstLine(none).includes("enforces nothing"),
    `with no bash to find the launcher must exit 1, write nothing to stdout and lead stderr with a line naming ${path.basename(script)} and saying it enforces nothing (${ctx(none)}, stdout ${JSON.stringify(none.stdout)})`);
  const viaPath = launch({ ...hidden, PATH: gitBin }, [token, rootArg, exitCode], payload);
  need(seen(viaPath).token === token, `with the fixed Git roots hidden the launcher did not find bash through PATH ${gitBin} (${ctx(viaPath)})`);
}
if (problems.length) {
  for (const p of problems) console.error(`LAUNCHER-PROBE: ${p}`);
  process.exitCode = 1;
} else {
  console.log("check-exec-form-windows-probe: launcher probe delivered argv, stdin, exit 2 and a backslash CLAUDE_PLUGIN_ROOT through lib/exec-bash.mjs" +
    (win ? ", and Git Bash identity, the no-bash failure line and the PATH lookup held." : " (Git Bash identity, the no-bash failure line and the PATH lookup are Windows-only and were skipped)."));
}
JS
}

run_launcher() {
  local node_exe="$1" tmp script launcher empty driver gitbin="" exit_code=2 token out rc=0
  launcher="$PWD/lib/exec-bash.mjs"
  if [[ ! -f "$launcher" ]]; then
    echo "LAUNCHER-PROBE: lib/exec-bash.mjs not found, so the launcher every hook row runs was not exercised and cannot clear a fleet sweep." >&2
    return 1
  fi
  if [[ "${EXEC_FORM_WINDOWS_PROBE_SIMULATE_LAUNCHER_DROP:-}" == 1 ]]; then
    exit_code=0
  fi
  token="exec-bash-probe-token-$$"
  tmp="$(mktemp -d)"
  script="$tmp/exec-bash-probe-guard.sh"
  empty="$tmp/empty"
  driver="$tmp/launcher-probe.cjs"
  mkdir "$empty"
  launcher_driver_js >"$driver"
  # Builtins and printf only, so it runs with nothing but bash on PATH.
  # uname is the one external, and a missing one shows up as an empty field.
  cat >"$script" <<'SH'
LC_ALL=C
IFS= read -r -d '' payload
printf 'token=%s\nrootarg=%s\nrootenv=%s\nstdin=%s\nuname=%s\n' \
  "$1" "$2" "${CLAUDE_PLUGIN_ROOT-}" "${#payload}" "$(uname -s 2>/dev/null)"
exit "$3"
SH
  if ((windows)); then
    gitbin="$(dirname "$BASH")"
    if ! out="$(bash scripts/emit-windows-path.sh "$script" "$launcher" "$empty" "$gitbin" "$driver")"; then
      rm -rf "$tmp"
      echo "LAUNCHER-PROBE: could not emit native paths for the launcher probe, so the launcher was not exercised and cannot clear a fleet sweep." >&2
      return 1
    fi
    {
      read -r script
      read -r launcher
      read -r empty
      read -r gitbin
      read -r driver
    } <<<"$out"
  fi
  if out="$("$node_exe" "$driver" "$launcher" "$script" "$token" "$exit_code" "$empty" "$gitbin")"; then
    note "$out"
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

spawn_active=0
if ((windows)) || [[ "${EXEC_FORM_WINDOWS_PROBE_FORCE:-}" == 1 ]]; then
  spawn_active=1
fi

if ((spawn_active)); then
  node_exe=""
  # shellcheck disable=SC2310 # resolve_node/run_spawn/run_launcher report their own failures; a miss is a skip or a finding, not an abort
  if node_exe="$(resolve_node)"; then
    # shellcheck disable=SC2310
    if ! run_spawn "$node_exe"; then
      errors=$((errors + 1))
    fi
    # shellcheck disable=SC2310
    if ! run_launcher "$node_exe"; then
      errors=$((errors + 1))
    fi
  elif [[ "${EXEC_FORM_WINDOWS_PROBE_REQUIRE_SPAWN:-}" == 1 ]]; then
    echo "SPAWN-PROBE: Windows exec-form spawn was required but no real node.exe was found on PATH. The spawn did not run, so it cannot clear a fleet sweep." >&2
    errors=$((errors + 1))
  else
    note "SKIP: Windows exec-form spawn and launcher probes: node.exe not on PATH. anthropics/claude-code#90495 was not exercised. A skip does not authorize converting .sh rows to exec form."
  fi
else
  note "SKIP: Windows exec-form spawn probe not exercised (OSTYPE=${OSTYPE:-unset}). A skip does not show that anthropics/claude-code#90495 is absent and does not authorize converting .sh rows to exec form."
fi

# --- live Claude Code half --------------------------------------------------

live_signature() {
  local text="$1"
  [[ "$text" == *eval_stdin* || "$text" == *"SyntaxError: Unexpected token"* || "$text" == *"bash.exe -c"* || "$text" == *'bash.exe" -c'* ]]
}

run_live() {
  local tmp script marker sentinel script_arg marker_arg settings claude_bin out rc seen bytes exec_path image
  tmp="$(mktemp -d)"
  sentinel="live-sentinel-$$"
  marker="$tmp/marker.json"
  script="$tmp/probe.cjs"
  cat >"$script" <<'JS'
const fs = require("fs");
const marker = process.argv[2];
const sentinel = process.argv[3];
let stdin = "";
try { stdin = fs.readFileSync(0, "utf8"); } catch (e) { stdin = ""; }
const argv = process.argv.slice(2);
fs.writeFileSync(marker, JSON.stringify({
  argv: argv,
  sentinelSeen: argv.includes(sentinel),
  stdinBytes: Buffer.byteLength(stdin),
  execPath: process.execPath
}));
JS
  script_arg="$script"
  marker_arg="$marker"
  if ((windows)); then
    if ! script_arg="$(bash scripts/emit-windows-path.sh "$script")" ||
      ! marker_arg="$(bash scripts/emit-windows-path.sh "$marker")"; then
      rm -rf "$tmp"
      note "SKIP: live Claude Code exec-form probe could not emit a native path for the probe script. A skip does not clear anthropics/claude-code#90495 and does not authorize a fleet sweep."
      return 0
    fi
  fi
  settings="$tmp/settings.json"
  if ! jq -n --arg script "$script_arg" --arg marker "$marker_arg" --arg sentinel "$sentinel" \
    '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"node",args:[$script,$marker,$sentinel],timeout:20}]}]}}' \
    >"$settings"; then
    rm -rf "$tmp"
    echo "LIVE-PROBE: could not write the live-probe settings file. Fleet sweep stopped." >&2
    return 1
  fi
  claude_bin="$(command -v claude)"
  set +e
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout 90 "$claude_bin" -p 'Run exactly this bash command and reply with its output: echo probe-ok' --settings "$settings" </dev/null 2>&1)"
    rc=$?
  else
    out="$("$claude_bin" -p 'Run exactly this bash command and reply with its output: echo probe-ok' --settings "$settings" </dev/null 2>&1)"
    rc=$?
  fi
  set -e
  if [[ -f "$marker" ]]; then
    seen="$(jq -r '.sentinelSeen' "$marker" 2>/dev/null || true)"
    bytes="$(jq -r '.stdinBytes' "$marker" 2>/dev/null || true)"
    exec_path="$(jq -r '.execPath' "$marker" 2>/dev/null || true)"
    image="$(image_name "$exec_path")"
    if [[ "$seen" == "true" && "$bytes" != "0" && "$bytes" != "null" && "$image" != "bash" && "$image" != "bash.exe" && "$image" != "sh" && "$image" != "sh.exe" ]]; then
      rm -rf "$tmp"
      note "check-exec-form-windows-probe: live probe delivered args and stdin to ${image}. This host did not reproduce anthropics/claude-code#90495. No .sh row was converted."
      return 0
    fi
    rm -rf "$tmp"
    echo "ARGS-DROP: live exec-form probe lost args, stdin, or the node image (anthropics/claude-code#90495). Fleet sweep stopped." >&2
    return 1
  fi
  # shellcheck disable=SC2310 # live_signature is a pure match; set -e staying off is the point of the test
  if live_signature "$out"; then
    rm -rf "$tmp"
    echo "ARGS-DROP: live exec-form probe reproduced args-drop (anthropics/claude-code#90495: hook still routed through bash, script never started). Fleet sweep stopped." >&2
    return 1
  fi
  rm -rf "$tmp"
  note "SKIP: live Claude Code exec-form probe did not observe a hook execution (claude exit ${rc}, no marker). A skip does not clear anthropics/claude-code#90495 and does not authorize a fleet sweep."
  return 0
}

if [[ "${EXEC_FORM_WINDOWS_PROBE_LIVE:-}" == 1 ]]; then
  if ((windows == 0)) && [[ "${EXEC_FORM_WINDOWS_PROBE_FORCE:-}" != 1 ]]; then
    note "SKIP: live Claude Code exec-form probe requested off Windows. anthropics/claude-code#90495 is a Windows hook-runner bug. A skip does not authorize a fleet sweep."
  elif ! command -v claude >/dev/null 2>&1; then
    note "SKIP: live Claude Code exec-form probe requested but claude is not on PATH. A skip does not clear anthropics/claude-code#90495 and does not authorize a fleet sweep."
  else
    # shellcheck disable=SC2310 # run_live returns 1 for a reproduced args-drop; that is a finding, not an abort
    if ! run_live; then
      errors=$((errors + 1))
    fi
  fi
else
  note "SKIP: live Claude Code exec-form probe not requested (EXEC_FORM_WINDOWS_PROBE_LIVE unset). A skip does not clear anthropics/claude-code#90495 and does not authorize a fleet sweep."
fi

if ((errors > 0)); then
  echo "check-exec-form-windows-probe: ${errors} finding(s). Fleet sweep of .sh rows stays stopped." >&2
  exit 1
fi

printf 'check-exec-form-windows-probe: %d exec-form row(s) name a real Windows executable.\n' "$ok_rows"
if ((${#notes[@]} > 0)); then
  printf '%s\n' "${notes[@]}"
fi
exit 0
