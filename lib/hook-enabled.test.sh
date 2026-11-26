#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
project="$work/project"
conf="$project/docs/conventions/demo.yaml"
mkdir -p "$project/docs/conventions" "$project/settings" "$work/home/docs/conventions" "$work/other/docs/conventions" "$work/docs/conventions"
option="CLAUDE_PLUGIN_OPTION_DEMO_ENABLED"
lib="$HERE/hook-enabled.sh"
installed="$work/config/plugins/cache/market/demo/1.0.0/lib/hook-enabled.sh"
settings="$work/config/settings.json"
mkdir -p "${installed%/*}"
cp "$lib" "$installed"
fails=0

repo() {
  rm -f "$conf"
  (($# == 0)) || printf '%s\n' "$@" >"$conf"
}

check() {
  local name="$1" want="$2" want_err="$3" err code
  shift 3
  local -a env=()
  while [[ "$1" != -- ]]; do
    env+=("$1")
    shift
  done
  shift
  # shellcheck disable=SC2016
  err="$(env -u "$option" HOME="$work/home" CLAUDE_PROJECT_DIR="$project" ${env[@]+"${env[@]}"} bash -c '
    . "$1" && shift || exit 2
    [[ -z "${TEST_CWD-}" ]] || cd "$TEST_CWD" || exit 2
    hook_enabled::_managed_files() {
      local f
      _HOOK_ENABLED_MANAGED_FILES=()
      _HOOK_ENABLED_MANAGED_OWNER_CHECK="${TEST_OWNER_CHECK:-1}"
      for f in ${TEST_MANAGED-}; do _HOOK_ENABLED_MANAGED_FILES+=("$f"); done
    }
    hook_enabled::resolve "$@"' _ "$lib" "$@" 2>&1 >/dev/null)"
  code=$?
  if [[ "$code" == "$want" && "$err" == "$want_err" ]]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (exit $code, want $want; stderr '$err', want '$want_err')" >&2
    fails=1
  fi
}

guard() {
  local name="$1" want="$2" home="$3" root="$4" code
  # shellcheck disable=SC2016
  HOME="$home" bash -c '. "$1" && hook_enabled::_no_repository_layer "$2"' _ "$HERE/hook-enabled.sh" "$root"
  code=$?
  if [[ "$code" == "$want" ]]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (exit $code, want $want)" >&2
    fails=1
  fi
}

dropped() {
  printf 'hook-enabled: demo_enabled: dropped "%s" from %s; only an unquoted true or false is read' "$1" "$2"
}

repo "demo_enabled: true"
check "user false over repository true: off" 1 "" "$option=false" -- demo demo_enabled true
repo "demo_enabled: false"
check "user true over repository false: on" 0 "" "$option=true" -- demo demo_enabled false
check "user unset, repository false: off" 1 "" -- demo demo_enabled true
check "an empty option counts as unset" 1 "" "$option=" -- demo demo_enabled true
repo "demo_enabled: true"
check "user unset, repository true: on" 0 "" -- demo demo_enabled false

repo
check "both unset: plugin default true" 0 "" -- demo demo_enabled true
check "both unset: plugin default false" 1 "" -- demo demo_enabled false

repo "demo_enabled: false"
check "an invalid option is named and dropped; the repository decides" 1 "$(dropped yes "$option")" "$option=yes" -- demo demo_enabled true
repo 'demo_enabled: "false"'
check "a quoted repository value is named and dropped; the default decides" 0 "$(dropped '"false"' "$conf")" -- demo demo_enabled true
repo "demo_enabled:"
check "an empty repository value is named and dropped" 1 "$(dropped "" "$conf")" -- demo demo_enabled false
repo "demo_enabled: TRUE"
check "a capitalized repository value is named and dropped" 1 "$(dropped TRUE "$conf")" -- demo demo_enabled false

repo $'demo_enabled: false   # off for this repository\r'
check "a trailing comment and CRLF are read past" 1 "" -- demo demo_enabled true
repo "other:" "  demo_enabled: false"
check "a nested key is not the setting" 0 "" -- demo demo_enabled true
repo "demo_enabled_extra: false"
check "a longer key is not the setting" 0 "" -- demo demo_enabled true
repo "demo_enabled: false" "demo_enabled: true"
check "the first top-level line decides" 1 "" -- demo demo_enabled true

repo "demo_enabled: false"
check "security: a repository false is ignored" 0 "" -- --security demo demo_enabled true
repo "demo_enabled: true"
check "security: an environment false is ignored; the guard stays on" 0 "" "$option=false" -- --security demo demo_enabled true
check "security: a repository true turns the guard on" 0 "" -- --security demo demo_enabled false
check "security: an environment true turns the guard on" 0 "" "$option=true" -- --security demo demo_enabled false
repo "demo_enabled: false"
check "security: an environment false and a repository false still leave the guard on" 0 "" "$option=false" -- --security demo demo_enabled true
repo
check "security: an environment false falls to a plugin default of false" 1 "" "$option=false" -- --security demo demo_enabled false
repo "demo_enabled: false"
check "security: an invalid option falls past the ignored repository false" 0 "$(dropped 1 "$option")" "$option=1" -- --security demo demo_enabled true

user_setting() {
  printf '{"pluginConfigs": {"demo@market": {"options": {"demo_enabled": %s}}}}\n' "$1" >"$settings"
}
lib="$installed"
from_settings="pluginConfigs[\"demo@market\"] in $settings"
repo "demo_enabled: true"
user_setting false
check "security: the user's own settings false turns the guard off over a repository true" 1 "" -- --security demo demo_enabled true
check "security: the user's own settings false wins over an environment true" 1 "" "$option=true" -- --security demo demo_enabled true
check "a settings false is not read without --security" 0 "" -- demo demo_enabled true
user_setting '"false"'
check "security: a settings string false turns the guard off" 1 "" -- --security demo demo_enabled true
user_setting true
repo "demo_enabled: false"
check "security: the user's own settings true keeps the guard on" 0 "" "$option=false" -- --security demo demo_enabled false
user_setting '"no"'
check "security: an invalid settings value is named and dropped; an environment false stays ignored" 0 "$(dropped no "$from_settings")" "$option=false" -- --security demo demo_enabled true
printf '{"pluginConfigs": {"other@market": {"options": {"demo_enabled": false}}}}\n' >"$settings"
check "security: another plugin's settings entry is not the user layer" 0 "" -- --security demo demo_enabled true
printf 'not json\n' >"$settings"
check "security: an unreadable settings file leaves the user layer unset" 0 "" -- --security demo demo_enabled true
rm -f "$settings"
check "security: no settings file leaves the guard on" 0 "" "$option=false" -- --security demo demo_enabled true
user_setting false
lib="$HERE/hook-enabled.sh"
check "security: a library outside the install cache reads no settings layer" 0 "" -- --security demo demo_enabled true
rm -f "$settings"

managed_setting() {
  printf '{"pluginConfigs": {"demo@market": {"options": {"demo_enabled": %s}}}}\n' "$2" >"$1"
  chmod 666 "$1"
}
lib="$installed"
managed="$work/managed/managed-settings.json"
dropin="$work/managed/managed-settings.d/50-team.json"
mkdir -p "${dropin%/*}"
repo
user_setting false
managed_setting "$managed" true
check "security: a managed true beats the user's own settings false" 0 "" "TEST_MANAGED=$managed" -- --security demo demo_enabled true
check "security: a managed true beats a user false and an environment false" 0 "" "TEST_MANAGED=$managed" "$option=false" -- --security demo demo_enabled false
user_setting true
managed_setting "$managed" false
check "security: a managed false from a file others can write is named and skipped" 0 "hook-enabled: demo_enabled: skipped false from $managed; a managed file that turns a guard off must be root-owned and writable by no one else" "TEST_MANAGED=$managed" -- --security demo demo_enabled false
check "security: a managed false from an administrator-only path beats the user's own settings true" 1 "" "TEST_MANAGED=$managed" TEST_OWNER_CHECK=0 -- --security demo demo_enabled true
managed_setting "$managed" true
managed_setting "$dropin" false
check "security: a later managed drop-in overrides the primary file" 1 "" "TEST_MANAGED=$managed $dropin" TEST_OWNER_CHECK=0 -- --security demo demo_enabled true
user_setting false
check "security: a skipped managed false leaves the primary's true in force" 0 "hook-enabled: demo_enabled: skipped false from $dropin; a managed file that turns a guard off must be root-owned and writable by no one else" "TEST_MANAGED=$managed $dropin" -- --security demo demo_enabled false
managed_setting "$managed" '"no"'
user_setting false
check "security: an invalid managed value is named and dropped; the user's settings decide" 1 "$(dropped no "pluginConfigs[\"demo@market\"] in $managed")" "TEST_MANAGED=$managed" -- --security demo demo_enabled true
printf '{"pluginConfigs": {"other@market": {"options": {"demo_enabled": true}}}}\n' >"$managed"
check "security: another plugin's managed entry is not the managed layer" 1 "" "TEST_MANAGED=$managed" -- --security demo demo_enabled true
managed_setting "$managed" true
check "a managed value is not read without --security" 1 "" "TEST_MANAGED=$managed" "$option=false" -- demo demo_enabled true
lib="$HERE/hook-enabled.sh"
rm -f "$settings" "$managed" "$dropin"

clone="$work/clone"
clone_conf="$clone/docs/conventions/demo.yaml"
config="$work/claude"
user_file="$config/settings.json"
home_file="$work/home/.claude/settings.json"
mkdir -p "$clone/docs/conventions" "$clone/sub/dir" "$config" "${home_file%/*}" "$work/nogit"
git -c init.defaultBranch=main init -q "$clone"
in_clone=("TEST_CWD=$clone/sub/dir" "CLAUDE_CONFIG_DIR=$config" "GIT_CEILING_DIRECTORIES=$work")
from_user="pluginConfigs[\"demo@*\"] in $user_file"
clone_repo() {
  rm -f "$clone_conf"
  (($# == 0)) || printf '%s\n' "$@" >"$clone_conf"
}
git_user() {
  printf '{"pluginConfigs": {%s}}\n' "$1" >"$user_file"
}
repo "demo_enabled: true"
clone_repo "demo_enabled: true"
git_user '"demo@market": {"options": {"demo_enabled": false}}'
check "git hook: the user's settings false over a repository true: off" 1 "" "${in_clone[@]}" -- --git-hook demo demo_enabled true
clone_repo "demo_enabled: false"
git_user '"demo@market": {"options": {"demo_enabled": true}}'
check "git hook: the user's settings true over a repository false: on" 0 "" "${in_clone[@]}" -- --git-hook demo demo_enabled false
rm -f "$user_file"
check "git hook: no settings file leaves the user layer unset; the top-level repository file decides" 1 "" "${in_clone[@]}" -- --git-hook demo demo_enabled true
clone_repo "demo_enabled: true"
git_user '"other@market": {"options": {"demo_enabled": false}}'
check "git hook: no entry for the plugin leaves the user layer unset" 0 "" "${in_clone[@]}" -- --git-hook demo demo_enabled false
clone_repo
repo "demo_enabled: false"
check "git hook: both unset gives the plugin default; CLAUDE_PROJECT_DIR is not read" 0 "" "${in_clone[@]}" -- --git-hook demo demo_enabled true
clone_repo "demo_enabled: false"
git_user '"demo@market": {"options": {"demo_enabled": "no"}}'
check "git hook: an invalid settings value is named and dropped" 1 "$(dropped no "$from_user")" "${in_clone[@]}" -- --git-hook demo demo_enabled true
git_user '"demo@market": {"options": {"demo_enabled": 0}}'
check "git hook: a number in settings is named and dropped" 1 "$(dropped 0 "$from_user")" "${in_clone[@]}" -- --git-hook demo demo_enabled true
rm -f "$user_file"
check "git hook: a relative GIT_DIR at the top level, as git runs a hook, finds the repository file" 1 "" "TEST_CWD=$clone" GIT_DIR=.git "CLAUDE_CONFIG_DIR=$config" -- --git-hook demo demo_enabled true
clone_repo "demo_enabled: true"
git_user '"demo@market": {"options": {"demo_enabled": false}}, "demo@other": {"options": {"demo_enabled": true}}'
check "git hook: marketplaces that disagree are named and skipped" 0 "hook-enabled: demo_enabled: skipped $from_user; entries for more than one marketplace set different values" "${in_clone[@]}" -- --git-hook demo demo_enabled true
git_user '"demo@market": {"options": {"demo_enabled": false}}, "demo@other": {"options": {"demo_enabled": false}}'
check "git hook: marketplaces that agree set the user layer" 1 "" "${in_clone[@]}" -- --git-hook demo demo_enabled true
rm -f "$user_file"
check "git hook: CLAUDE_PLUGIN_OPTION is not the user layer" 0 "" "${in_clone[@]}" "$option=false" -- --git-hook demo demo_enabled false
printf '{"pluginConfigs": {"demo@market": {"options": {"demo_enabled": false}}}}\n' >"$home_file"
check "git hook: with no CLAUDE_CONFIG_DIR the settings come from HOME/.claude" 1 "" "TEST_CWD=$clone/sub/dir" CLAUDE_CONFIG_DIR= -- --git-hook demo demo_enabled true
rm -f "$home_file"
check "git hook: outside a repository no repository layer is read" 0 "" "TEST_CWD=$work/nogit" "CLAUDE_CONFIG_DIR=$config" "GIT_CEILING_DIRECTORIES=$work" -- --git-hook demo demo_enabled true
clone_repo "demo_enabled: false"
check "git hook security: a repository false is ignored" 0 "" "${in_clone[@]}" -- --security --git-hook demo demo_enabled true
clone_repo "demo_enabled: true"
git_user '"demo@market": {"options": {"demo_enabled": false}}'
check "git hook security: the user's settings false turns the guard off" 1 "" "${in_clone[@]}" -- --security --git-hook demo demo_enabled true
managed_setting "$managed" true
check "git hook security: a managed true beats the user's settings false" 0 "" "${in_clone[@]}" "TEST_MANAGED=$managed" -- --security --git-hook demo demo_enabled false
repo
rm -f "$user_file" "$managed" "$clone_conf"

trace="$work/strace.log"
traced() {
  rm -f "$trace"
  strace -f -qq -o "$trace" -e trace=clone,clone3,fork,vfork,execve "$@" >/dev/null 2>&1
}
trace_clones() {
  grep -E '^[0-9]+ +(clone|clone3|fork|vfork)\(' "$trace" 2>/dev/null | grep -vc CLONE_THREAD
}
trace_execs() {
  local n
  n="$(grep -cE '^[0-9]+ +execve\(' "$trace" 2>/dev/null)"
  echo $((${n:-0} - 1))
}

budget() {
  local name="$1" max="$2" want="$3" code clones execs
  shift 3
  local -a env=()
  while [[ "$1" != -- ]]; do
    env+=("$1")
    shift
  done
  shift
  rm -f "$trace"
  # shellcheck disable=SC2016
  env -u "$option" HOME="$work/home" CLAUDE_PROJECT_DIR="$project" ${env[@]+"${env[@]}"} \
    strace -f -qq -o "$trace" -e trace=clone,clone3,fork,vfork,execve bash -c '
    . "$1" && shift || exit 2
    [[ -z "${TEST_CWD-}" ]] || cd "$TEST_CWD" || exit 2
    hook_enabled::resolve "$@"' _ "$lib" "$@" >/dev/null 2>&1
  code=$?
  clones="$(trace_clones)"
  execs="$(trace_execs)"
  if [[ "$code" == "$want" ]] && ((execs >= 0 && clones <= max && execs <= max)); then
    echo "PASS: spawn budget: $name ($clones forks, $execs execs, budget $max)"
  else
    echo "FAIL: spawn budget: $name (exit $code, want $want; $clones forks and $execs execs, budget $max)" >&2
    fails=1
  fi
}

printf 'x\n' >"$work/probe.txt"
if ! command -v strace >/dev/null 2>&1; then
  echo "SKIP: strace not on PATH; the spawn budget cases did not run"
elif ! traced bash -c "v=\$(cat '$work/probe.txt')" || (($(trace_clones) < 1)); then
  echo "SKIP: strace saw no fork in a probe that forks; the spawn budget cases did not run"
else
  lib="$HERE/hook-enabled.sh"
  repo "demo_enabled: false"
  budget "a Claude Code hook starts no process" 0 1 -- demo demo_enabled true
  lib="$installed"
  repo "demo_enabled: true"
  user_setting false
  budget "--security from the install cache starts uname and jq" 2 1 -- --security demo demo_enabled true
  rm -f "$settings"
  lib="$HERE/hook-enabled.sh"
  clone_repo "demo_enabled: true"
  git_user '"demo@market": {"options": {"demo_enabled": false}}'
  budget "--git-hook starts git and jq" 2 1 "${in_clone[@]}" -- --git-hook demo demo_enabled true
  budget "--git-hook --security starts git, uname and jq" 3 1 "${in_clone[@]}" -- --security --git-hook demo demo_enabled true
  repo
  rm -f "$user_file" "$clone_conf"
fi

repo
printf 'demo_enabled: false\n' >"$project/settings/demo.yaml"
check "--home names the convention home" 1 "" -- --home settings demo demo_enabled true
printf 'demo_enabled: false\n' >"$work/other/docs/conventions/demo.yaml"
check "--root names the project root" 1 "" -- --root "$work/other" demo demo_enabled true
check "no project root reads no repository layer" 0 "" CLAUDE_PROJECT_DIR= -- demo demo_enabled true
printf 'demo_enabled: false\n' | tee "$work/home/docs/conventions/demo.yaml" >"$work/docs/conventions/demo.yaml"
check "a project root at HOME reads no repository layer" 0 "" CLAUDE_PROJECT_DIR="$work/home" -- demo demo_enabled true
check "a project root above HOME reads no repository layer" 0 "" CLAUDE_PROJECT_DIR="$work" HOME="$work/home" -- demo demo_enabled true

guard "a Windows project root at HOME reads no repository layer" 0 /d/Code/me "D:\\Code\\me\\"
guard "a Windows drive root above HOME reads no repository layer" 0 /d/Code/me "D:\\"
guard "a Windows project root below HOME reads its repository layer" 1 /d/Code/me "D:\\Code\\me\\Proj"
guard "a project root beside HOME reads its repository layer" 1 /srv/me /srv/me2

repo
ln -s "$work/other/docs/conventions/demo.yaml" "$conf"
check "a symlinked repository file is named and skipped" 0 "hook-enabled: demo_enabled: skipped $conf; a symlink, and the repository layer reads only regular files" -- demo demo_enabled true

check "a key without _enabled is a usage error" 2 'hook-enabled: key "demo" is not a snake_case <name>_enabled key' -- demo demo true
check "a default other than true or false is a usage error" 2 'hook-enabled: demo_enabled: plugin default "on" is not true or false' -- demo demo_enabled on
check "a plugin name with a slash is a usage error" 2 'hook-enabled: plugin name "../demo" is not a plain name' -- ../demo demo_enabled true
check "a missing argument is a usage error" 2 "hook-enabled: usage: hook_enabled::resolve [--security] [--git-hook] [--root DIR] [--home DIR] <plugin> <key> <true|false>" -- demo demo_enabled
check "--root with no value is a usage error" 2 "hook-enabled: --root requires a value" -- demo demo_enabled true --root

exit "$fails"
