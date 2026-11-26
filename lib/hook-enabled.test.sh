#!/usr/bin/env bash
set -uo pipefail

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
  err="$(env -u "$option" HOME="$work/home" CLAUDE_PROJECT_DIR="$project" ${env[@]+"${env[@]}"} bash -c '. "$1" && shift && hook_enabled::resolve "$@"' _ "$lib" "$@" 2>&1 >/dev/null)"
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
check "a missing argument is a usage error" 2 "hook-enabled: usage: hook_enabled::resolve [--security] [--root DIR] [--home DIR] <plugin> <key> <true|false>" -- demo demo_enabled
check "--root with no value is a usage error" 2 "hook-enabled: --root requires a value" -- demo demo_enabled true --root

exit "$fails"
