#!/usr/bin/env bash
# GENERATED from lib/telemetry-body-gate.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.

# shellcheck disable=SC2034 # TBG_* results are read by the sourcing script
unset CDPATH

tbg_has_name() { [[ "$2" == "$1" || "$2" == "$1"-* ]]; }
tbg_canon_dir() {
  local d="$1" out
  [[ "$d" == -* ]] && d="./$d"
  [[ -d "$d" ]] && out="$(CDPATH='' cd -P -- "$d" 2>/dev/null && pwd -P && printf x)" || return 1
  out="${out%x}"
  out="${out%$'\n'}"
  [[ "$out" == /* && "$out" != *$'\n'* ]] || return 1
  printf '%s\n' "$out"
}
tbg_safe_dir() {
  local plugin="$1" dir="${2:-${CLAUDE_PLUGIN_DATA:-}}" seg home
  TBG_SAFE=""
  if [[ -z "$dir" ]]; then
    TBG_ERR="no safe body dir: pass --body-dir with this plugin's data dir"
    return 1
  fi
  seg="${dir%/}"
  seg="${seg##*/}"
  if ! tbg_has_name "$plugin" "$seg"; then
    TBG_ERR="no safe body dir: --body-dir (or CLAUDE_PLUGIN_DATA) must be this plugin's data dir, whose last segment names $plugin"
    return 1
  fi
  if ! TBG_SAFE="$(tbg_canon_dir "$dir")" || [[ -z "$TBG_SAFE" || ! -d "$TBG_SAFE" ]]; then
    TBG_SAFE=""
    TBG_ERR="the safe body dir does not exist"
    return 1
  fi
  if ! tbg_has_name "$plugin" "${TBG_SAFE##*/}"; then
    TBG_SAFE=""
    TBG_ERR="no safe body dir: the --body-dir (or CLAUDE_PLUGIN_DATA) resolves to a dir whose last segment does not name $plugin"
    return 1
  fi
  home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
  home="${home:-${HOME:-}}"
  [[ -d "$home" ]] && { home="$(tbg_canon_dir "$home")" || home=""; }
  if [[ "$home" != /* ]]; then
    TBG_SAFE=""
    TBG_ERR="cannot resolve the home dir to check the safe body dir against it"
    return 1
  fi
  if [[ "$TBG_SAFE" == / || "$home" == "$TBG_SAFE" || "$home" == "$TBG_SAFE"/* ]]; then
    TBG_SAFE=""
    TBG_ERR="the safe body dir must not be /, the home dir, or an ancestor of it"
    return 1
  fi
}

tbg_read_body() {
  local file="$1" canon opened parent leaf
  TBG_COPY=""
  if [[ -L "$file" ]]; then
    TBG_ERR="the body file must not be a symlink"
    return 1
  fi
  if [[ ! -e "$file" ]]; then
    TBG_ERR="the body file does not exist"
    return 2
  fi
  leaf="${file##*/}"
  if [[ "$file" == */* ]]; then parent="${file%/*}"; else parent=.; fi
  if [[ -z "$leaf" || "$leaf" == . || "$leaf" == .. || "$leaf" == *$'\n'* ]] ||
    ! parent="$(tbg_canon_dir "${parent:-/}")" || [[ -z "$parent" ]]; then
    TBG_ERR="the body file must resolve under the safe body dir"
    return 1
  fi
  canon="${parent%/}/$leaf"
  if [[ ! -f "$canon" || "$canon" != "$TBG_SAFE"/* ]]; then
    TBG_ERR="the body file must resolve under the safe body dir"
    return 1
  fi
  if [[ -z "$(find "$canon" -prune -links 1 2>/dev/null)" ]]; then
    TBG_ERR="the body file must not be a hard link"
    return 1
  fi
  if [[ -L "$canon" ]] || ! exec 9<"$canon"; then
    TBG_ERR="cannot open the body file"
    return 1
  fi
  if [[ -e /proc/self/fd/9 ]]; then
    opened="$(readlink -- /proc/self/fd/9)"
    if [[ "$opened" != "$TBG_SAFE"/* ]]; then
      exec 9<&-
      TBG_ERR="the body file must resolve under the safe body dir"
      return 1
    fi
  fi
  if ! TBG_COPY="$(mktemp "$TBG_SAFE/.body.XXXXXX")" || ! cat <&9 >"$TBG_COPY"; then
    exec 9<&-
    TBG_ERR="cannot copy the body file"
    return 1
  fi
  exec 9<&-
}

tbg_instance() {
  local file="$TBG_SAFE/lane-instance" tmp=""
  TBG_INSTANCE=""
  if [[ ! -L "$file" && ! -e "$file" ]]; then
    TBG_INSTANCE="lane-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
    if tmp="$(mktemp "$TBG_SAFE/.lane-instance.XXXXXX" 2>/dev/null)" &&
      printf '%s\n' "$TBG_INSTANCE" >"$tmp" && ln -n -- "$tmp" "$file" 2>/dev/null &&
      [[ -f "$file" && ! -L "$file" ]]; then
      rm -f -- "$tmp"
      return 0
    fi
    [[ -n "$tmp" ]] && rm -f -- "$tmp"
    [[ -e "$file" || -L "$file" ]] || {
      TBG_ERR="cannot store the lane instance; this run would write under an id the next run cannot find"
      TBG_INSTANCE=""
      return 1
    }
  fi
  if [[ -L "$file" || ! -f "$file" ]]; then
    TBG_INSTANCE=""
    TBG_ERR="the stored lane-instance is a symlink or not a file; delete it to make a new one"
    return 1
  fi
  TBG_INSTANCE="$(head -c 64 -- "$file" 2>/dev/null | tr -d '\r\n')"
  if [[ ! "$TBG_INSTANCE" =~ ^lane-[0-9a-f]{8}$ ]]; then
    TBG_INSTANCE=""
    TBG_ERR="the stored lane-instance is malformed; delete it to make a new one"
    return 1
  fi
}

tbg_check_instance() {
  local hit
  if ! hit="$(printf '%s' "$2" | tbg_scan "$1")"; then
    TBG_ERR="the lane-instance scan could not run"
    return 1
  fi
  if [[ -n "$hit" ]]; then
    TBG_ERR="the lane instance is withheld from the public marker: $hit; unset lane_instance (and drop lane_instance from a resumed state block) so the stored random id is used"
    return 1
  fi
}

tbg_scan() {
  # shellcheck disable=SC2016 # JavaScript, not shell
  node --input-type=module -e 'const { pathToFileURL } = await import("node:url");
const { readFileSync } = await import("node:fs");
const gate = await import(pathToFileURL(process.argv[2]).href);
const bytes = readFileSync(0);
const { block, warn } = gate.scanLeak(bytes);
const text = bytes.toString("utf8");
const q = String.fromCharCode(39);
const secret = block ?? (warn ? gate.WARN_ONLY : gate.URL_CREDENTIALS[1].test(text) ? gate.URL_CREDENTIALS[0] : null);
const machine = secret ? null : gate.findMachine(text.replace(/\/home\/runner\//g, "/"));
process.stdout.write(
  secret
    ? `it matches the leak-scan rule ${q}${secret}${q}; a real credential must be rotated`
    : machine
      ? `it names a machine path or hostname (${machine[0]}); remove it`
      : "",
);' leak-scan "$1" 2>/dev/null
}
