#!/usr/bin/env bash
# GENERATED from lib/telemetry-body-gate.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# telemetry-body-gate.sh: the body-file checks every lane telemetry upsert shares
# (work-items, harness-ops lanes, source-control babysit-loop). Sourced, not run.
#
# Lane prompts drive the upserts and the comment they write is public, so a
# prompt-injected --body-file or --body-dir must not be able to post a credential
# file. Each function returns non-zero with the reason in TBG_ERR; the caller maps
# that to its own exit code. No message carries an absolute path or a match.
# Needs bash 4.1+ and GNU realpath (-e).

# shellcheck disable=SC2034 # TBG_* results are read by the sourcing script
unset CDPATH

# tbg_safe_dir PLUGIN [DIR]: the canonical safe body dir, in TBG_SAFE. DIR, else
# an inherited CLAUDE_PLUGIN_DATA, counts only when its last path segment names
# PLUGIN (a plugin data dir is <plugin>-<marketplace>), so neither a caller-chosen
# dir nor another plugin's exported data dir widens it; and never when it is /,
# the home dir, or an ancestor of the home dir. The name is checked again on the
# canonical path, so a symlink named for PLUGIN that points elsewhere is refused.
# The home dir is the account's passwd entry, so an overridden HOME cannot move
# it; $HOME is only the fallback where getent is missing.
tbg_has_name() { [[ "$2" == "$1" || "$2" == "$1"-* ]]; }
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
  if ! TBG_SAFE="$(realpath -e -- "$dir" 2>/dev/null)" || [[ ! -d "$TBG_SAFE" ]]; then
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
  home="$(realpath -m -- "${home:-${HOME:-/}}" 2>/dev/null)" || home="/"
  if [[ "$TBG_SAFE" == / || "$home" == "$TBG_SAFE" || "$home" == "$TBG_SAFE"/* ]]; then
    TBG_SAFE=""
    TBG_ERR="the safe body dir must not be /, the home dir, or an ancestor of it"
    return 1
  fi
}

# tbg_read_body FILE: copy FILE, which must resolve under TBG_SAFE, to a private
# file named in TBG_COPY, made in TBG_SAFE so TMPDIR need not be writable (the
# caller removes it). Returns 2 when FILE does
# not exist, 1 on any other refusal. The leaf is canonicalized with realpath, so
# no `cd` (and no CDPATH or option-shaped parent) is involved. The file is then
# opened once, and on Linux the open descriptor's own path is checked again, so a
# swap between the realpath check and the open is caught. Without /proc (macOS)
# only the realpath check stands, and that swap window stays open.
tbg_read_body() {
  local file="$1" canon opened fd
  TBG_COPY=""
  if [[ -L "$file" ]]; then
    TBG_ERR="the body file must not be a symlink"
    return 1
  fi
  if ! canon="$(realpath -e -- "$file" 2>/dev/null)"; then
    TBG_ERR="the body file does not exist"
    return 2
  fi
  if [[ ! -f "$canon" || "$canon" != "$TBG_SAFE"/* ]]; then
    TBG_ERR="the body file must resolve under the safe body dir"
    return 1
  fi
  if ! exec {fd}<"$canon"; then
    TBG_ERR="cannot open the body file"
    return 1
  fi
  if [[ -e "/proc/self/fd/$fd" ]]; then
    opened="$(readlink -- "/proc/self/fd/$fd")"
    if [[ "$opened" != "$TBG_SAFE"/* ]]; then
      exec {fd}<&-
      TBG_ERR="the body file must resolve under the safe body dir"
      return 1
    fi
  fi
  if ! TBG_COPY="$(mktemp "$TBG_SAFE/.body.XXXXXX")" || ! cat <&"$fd" >"$TBG_COPY"; then
    exec {fd}<&-
    TBG_ERR="cannot copy the body file"
    return 1
  fi
  exec {fd}<&-
}

# tbg_instance: the lane-instance fallback, in TBG_INSTANCE: a random lane-<hex>
# id made once and kept in TBG_SAFE/lane-instance, so it is stable across
# restarts and distinct per machine without publishing the hostname in the public
# marker. A symlinked or malformed stored id is refused and never echoed. A new id
# is written to a temp file and hard-linked into place, which never overwrites.
tbg_instance() {
  local file="$TBG_SAFE/lane-instance" tmp=""
  TBG_INSTANCE=""
  if [[ ! -L "$file" && ! -e "$file" ]]; then
    TBG_INSTANCE="lane-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
    if tmp="$(mktemp "$TBG_SAFE/.lane-instance.XXXXXX" 2>/dev/null)" &&
      printf '%s\n' "$TBG_INSTANCE" >"$tmp" && ln -T -- "$tmp" "$file" 2>/dev/null; then
      rm -f -- "$tmp"
      return 0
    fi
    [[ -n "$tmp" ]] && rm -f -- "$tmp"
    # Another run may have stored one first; read that one below.
    [[ -e "$file" || -L "$file" ]] || {
      TBG_ERR="cannot store the lane instance; this run would write under an id the next run cannot find"
      TBG_INSTANCE=""
      return 1
    }
  fi
  if [[ -L "$file" ]]; then
    TBG_INSTANCE=""
    TBG_ERR="the stored lane-instance is a symlink; delete it to make a new one"
    return 1
  fi
  TBG_INSTANCE="$(head -c 64 -- "$file" 2>/dev/null | tr -d '\r\n')"
  if [[ ! "$TBG_INSTANCE" =~ ^lane-[0-9a-f]{8}$ ]]; then
    TBG_INSTANCE=""
    TBG_ERR="the stored lane-instance is malformed; delete it to make a new one"
    return 1
  fi
}

# tbg_scan GATE: read the body on stdin and print why it is withheld, empty when
# clean: a scanLeak block, its plain-assignment warning or URL userinfo
# credentials (a credential, which must be rotated), or a findMachine hit (a home path, a fleet or private
# hostname, which only needs removing). A GitHub-hosted runner's home dir
# reveals nothing, so it is not a machine path. GATE is the plugin's generated
# copy of lib/publish-gate.mjs. Non-zero when the scan cannot run; never prints
# the match.
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
