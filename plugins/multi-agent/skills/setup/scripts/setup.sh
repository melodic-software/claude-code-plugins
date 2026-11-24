#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/../../.."
ROUTE="$SCRIPT_DIR/../../route/scripts/route.sh"
RESOLVER="$PLUGIN_DIR/scripts/resolve-roles.sh"
PARSER="$PLUGIN_DIR/scripts/yaml-subset.awk"
# shellcheck source=../../../lib/config-root.sh
. "$PLUGIN_DIR/lib/config-root.sh"

usage() {
  cat <<'EOF'
setup.sh: inspect or write one layer of the multi-agent role map.

  setup.sh check [session=<alias>]
      The resolved map through the route wrapper (JSON on stdout, notes on
      stderr), then one row on the personal override's gitignore state, a
      WARN row for each retired team file still present and one for each
      old user or personal file.
  setup.sh apply --layer user|team|local [--write] <key>=<value> ...
      Merges the pairs into that layer's existing keys. `<key>=` with no
      value removes the key. Without --write it prints the target path and a
      diff and writes nothing; with --write it writes, then reads the file
      back. The candidate is resolved before anything is written: a key the
      resolver would reject or ignore stops the run with exit 1. user and
      local are refused while that layer's old file exists.
  setup.sh apply --migrate [--write]
      Moves each old file into its new location: ~/.claude/multi-agent.yaml
      to the user file, <root>/.claude/multi-agent.local.yaml to local and
      <root>/.claude/multi-agent.yaml to team. A key the new file already
      sets keeps its value; every other key of the old file is added.
      Without --write it prints each move and a diff; with --write it
      writes the new file, reads it back, resolves the layers, and only
      then deletes the old file.

Layers (reference/config.md):
  user   the file the role_map_file userConfig option names (--user-file);
         refused while the option is unset
  team   <root>/<home>/multi-agent.yaml, <home> being the convention home the
         repository binds, else docs/conventions. While that file is absent,
         the keys of a retired team file (the config block in
         docs/conventions/multi-agent.md, else .claude/multi-agent.yaml),
         which the resolver no longer reads, seed it; that file is left as
         it is, and check names it.
  local  <root>/<home>/multi-agent.local.yaml
team and local are refused unless lib/config-root.sh classifies <root> as repo.
A layer file is rewritten whole, so comments in it are not kept.

--user-file <f> takes the role_map_file option's value; empty or an
unsubstituted ${user_config.role_map_file} means unset. Options for tests:
--root <dir> (default CLAUDE_PROJECT_DIR, else the git toplevel), --home
<dir> (default $HOME).

Exit: 0 done (or nothing to change); 1 the candidate does not resolve
cleanly, or the existing layer does not parse; 2 usage error or a refused layer.
EOF
}

die() {
  printf 'setup: %s\n' "$1" >&2
  exit 2
}

ACTION="${1:-check}"
[[ $# -gt 0 ]] && shift
if [[ "$ACTION" == -h || "$ACTION" == --help ]]; then
  usage
  exit 0
fi
LAYER="" WRITE=0 MIGRATE=0 ROOT="" HOME_DIR="${HOME:-}" USER_FILE=""
SESSION=() PAIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --layer | --root | --home | --user-file)
    [[ $# -gt 1 ]] || die "$1 needs a value"
    case "$1" in
    --layer) LAYER="$2" ;;
    --root) ROOT="$2" ;;
    --user-file) USER_FILE="$2" ;;
    *) HOME_DIR="$2" ;;
    esac
    shift
    ;;
  --write) WRITE=1 ;;
  --migrate) MIGRATE=1 ;;
  session=*) SESSION=("$1") ;;
  *=*) PAIRS+=("$1") ;;
  *) die "unknown argument '$1'" ;;
  esac
  shift
done
[[ -n "$ROOT" ]] || ROOT="$(config_root_resolve)"
CLASS="$(HOME="$HOME_DIR" config_root_classify "$ROOT")"
[[ "$USER_FILE" == "\${user_config."* ]] && USER_FILE=""
[[ -n "$HOME_DIR" && "$USER_FILE" == \~/* ]] && USER_FILE="$HOME_DIR/${USER_FILE#\~/}"
[[ -z "$USER_FILE" || "$USER_FILE" == /* ]] ||
  die "the role_map_file option '$USER_FILE' is not an absolute path; set an absolute path in /config"
LOCATE=(--root "$ROOT" --home "$HOME_DIR")
[[ -n "$USER_FILE" ]] && LOCATE+=(--user-file "$USER_FILE")
OLD_USER=""
[[ -n "$HOME_DIR" ]] && OLD_USER="$HOME_DIR/.claude/multi-agent.yaml"
OLD_LOCAL="$ROOT/.claude/multi-agent.local.yaml"
SET_OPTION="set the role_map_file option in /config to the file that should hold it"
OLD_USER_SAME=0
[[ -n "$USER_FILE" ]] && config_root_paths_same "$OLD_USER" "$USER_FILE" && OLD_USER_SAME=1
NAME_OUTSIDE="the role_map_file option names the old file $OLD_USER; name a file outside ~/.claude"

old_beside() {
  [[ -e "$1" || -L "$1" ]] && ! config_root_paths_same "$1" "$2"
}

check() {
  local home
  "$ROUTE" all "${SESSION[@]+"${SESSION[@]}"}" "${LOCATE[@]}" || return
  if [[ "$CLASS" != repo ]]; then
    printf 'INFO personal-override: not applicable at a %s root\n' "$CLASS"
  else
    home="$(convention_home)"
    if git -C "$ROOT" check-ignore -q "$home/multi-agent.local.yaml"; then
      printf 'PASS personal-override: %s/multi-agent.local.yaml is gitignored\n' "$home"
    else
      printf 'WARN personal-override: %s/multi-agent.local.yaml is not gitignored; the recommended line is %s/**/*.local.*\n' "$home" "$home"
    fi
  fi
  old_rows
  if [[ "$CLASS" == repo ]]; then retired_rows; fi
}

old_rows() {
  local new_local
  if [[ -n "$OLD_USER" && -f "$OLD_USER" ]]; then
    if ((OLD_USER_SAME)); then
      printf 'WARN user-config: %s, then run apply --migrate\n' "$NAME_OUTSIDE"
    elif [[ -n "$USER_FILE" ]]; then
      printf 'WARN user-config: %s is an old path; apply --migrate moves its keys into %s and deletes it\n' "$OLD_USER" "$USER_FILE"
    else
      printf 'WARN user-config: %s is an old path; %s, then run apply --migrate\n' "$OLD_USER" "$SET_OPTION"
    fi
  fi
  [[ "$CLASS" == repo ]] || return 0
  new_local="$ROOT/$(convention_home)/multi-agent.local.yaml"
  if old_beside "$OLD_LOCAL" "$new_local"; then
    printf 'WARN personal-override: %s is an old path; apply --migrate moves its keys into %s and deletes it\n' \
      "$OLD_LOCAL" "$new_local"
  fi
}

retired_rows() {
  local md="$ROOT/docs/conventions/multi-agent.md" yaml="$ROOT/.claude/multi-agent.yaml"
  local target seeds=0 manual link
  target="$ROOT/$(convention_home)/multi-agent.yaml"
  [[ -f "$target" ]] || seeds=1
  manual="copy any key still wanted into $target, then delete it"
  if [[ -f "$md" ]] && link="$(symlink_in "$md")"; then
    if ((seeds)); then
      printf 'WARN team: apply --layer team refuses %s while %s is absent, since %s is a symlink; replace or delete the symlink\n' "$md" "$target" "$link"
      seeds=0
    fi
  elif [[ -f "$md" ]] &&
    [[ "$(awk -v BLOCK=1 -f "$PARSER" "$md" 2>/dev/null)" == block$'\t'* ]]; then
    if ((seeds)); then
      printf 'WARN team: the config block in %s is no longer read; the first apply --layer team copies its keys into %s, then delete the block\n' "$md" "$target"
      seeds=0
    else
      printf 'WARN team: the config block in %s is no longer read; %s\n' "$md" "$manual"
    fi
  fi
  if [[ -L "$yaml" ]]; then
    printf 'WARN team: %s is a symlink and no longer read; delete it\n' "$yaml"
  elif [[ -e "$yaml" ]] && ! config_root_paths_same "$yaml" "$target"; then
    if ((seeds)) && link="$(symlink_in "$yaml")"; then
      printf 'WARN team: %s is no longer read, and apply --layer team refuses it while %s is absent, since %s is a symlink; %s\n' "$yaml" "$target" "$link" "$manual"
    elif link="$(symlink_in "$yaml")"; then
      printf 'WARN team: %s is no longer read, and apply --migrate refuses it, since %s is a symlink; %s\n' "$yaml" "$link" "$manual"
    else
      printf 'WARN team: %s is no longer read; apply --migrate moves its keys into %s and deletes it\n' "$yaml" "$target"
    fi
  fi
}

render() {
  LC_ALL=C sort -t $'\t' -k1,1 | awk -F '\t' '
    BEGIN { print "schema: 1"; prev_depth = 0 }
    {
      n = split($1, p, ".")
      c = 0
      while (c < n - 1 && c < prev_depth && p[c + 1] == pp[c + 1]) c++
      for (i = c + 1; i < n; i++) printf "%" (2 * (i - 1)) "s%s:\n", "", p[i]
      if (n == 3 && p[1] == "vendors" && p[2] == "tiebreak" && p[3] ~ /^[0-9]+$/) {
        printf "%" (2 * (n - 1)) "s- %s\n", "", $2
      } else {
        printf "%" (2 * (n - 1)) "s%s: %s\n", "", p[n], $2
      }
      prev_depth = n - 1
      for (i = 1; i <= n; i++) pp[i] = p[i]
    }'
}

convention_home() {
  local out
  out="$(bash "$PLUGIN_DIR/lib/resolve-convention-home.sh" --root "$ROOT" 2>/dev/null)" && printf '%s' "$out" ||
    printf 'docs/conventions'
}

# A repository can commit a symlink at a team or local path, or at a legacy
# file that seeds one; reading or writing through it would reach a file
# outside the repository. Refuse <path> when it, or a directory above it
# inside the repository, is a symlink.
refuse_symlink() {
  local link
  link="$(symlink_in "$1")" && die "refusing $1: $link is a symlink"
  return 0
}

# Print the first symlink among <path> and the directories above it inside
# the repository; status 1 when there is none.
symlink_in() {
  local p="$1"
  while [[ "$p" == "$ROOT"/* ]]; do
    if [[ -L "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
    p=$(dirname "$p")
  done
  return 1
}

make_tmp() {
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
}

check_candidate() {
  rm -rf "${tmp:?}/repo" "${tmp:?}/home"
  mkdir -p "$tmp/repo/docs/conventions" "$tmp/home"
  git -C "$tmp/repo" init -q
  printf '%s\n' "$1" >"$tmp/repo/docs/conventions/multi-agent.local.yaml"
  if ! "$RESOLVER" --root "$tmp/repo" --home "$tmp/home" all >/dev/null 2>"$tmp/notes" ||
    [[ -s "$tmp/notes" ]]; then
    printf 'setup: the layer would not resolve cleanly; nothing written:\n' >&2
    sed 's/^resolve-roles: personal-override/  candidate/; s/^resolve-roles: /  /' "$tmp/notes" >&2
    exit 1
  fi
}

apply() {
  ((MIGRATE)) && {
    migrate
    return
  }
  local target existing="" records body old_label seed="" seed_block=0
  local legacy_md="$ROOT/docs/conventions/multi-agent.md" legacy_yaml="$ROOT/.claude/multi-agent.yaml"
  case "$LAYER" in
  user)
    [[ -n "$USER_FILE" ]] || die "the user layer is the file the role_map_file option names; $SET_OPTION"
    ((!OLD_USER_SAME)) || die "$NAME_OUTSIDE, then run apply --migrate"
    [[ -z "$OLD_USER" || ! -f "$OLD_USER" ]] ||
      die "$OLD_USER is the old user file; run apply --migrate first, so the user layer has one home"
    target="$USER_FILE"
    ;;
  team | local)
    [[ "$CLASS" == repo ]] ||
      die "the $LAYER layer is not applicable at a $CLASS root; run from the repository, or use --layer user"
    if [[ "$LAYER" == local ]]; then
      target="$ROOT/$(convention_home)/multi-agent.local.yaml"
      ! old_beside "$OLD_LOCAL" "$target" ||
        die "$OLD_LOCAL is the old personal file; run apply --migrate first, so the local layer has one home"
    else
      target="$ROOT/$(convention_home)/multi-agent.yaml"
      if [[ ! -f "$target" ]]; then
        if [[ -f "$legacy_md" ]] && refuse_symlink "$legacy_md" &&
          [[ "$(awk -v BLOCK=1 -f "$PARSER" "$legacy_md")" == block$'\t'* ]]; then
          seed="$legacy_md" seed_block=1
        elif [[ -f "$legacy_yaml" ]]; then
          refuse_symlink "$legacy_yaml"
          seed="$legacy_yaml"
        fi
      fi
    fi
    ;;
  "") die "apply needs --layer user|team|local" ;;
  *) die "unknown layer '$LAYER' (user, team or local)" ;;
  esac
  [[ "$LAYER" == user ]] || refuse_symlink "$target"
  ((${#PAIRS[@]})) || die "apply needs at least one <key>=<value>"

  local source_file="$target"
  [[ -f "$target" ]] || source_file="$seed"
  if [[ -n "$source_file" && -f "$source_file" ]]; then
    if [[ "$source_file" == "$seed" && "$seed_block" == 1 ]]; then
      records="$(awk -v BLOCK=1 -f "$PARSER" "$source_file")"
    else
      records="$(awk -f "$PARSER" "$source_file")"
    fi || {
      printf 'setup: %s does not parse (%s); fix or remove it before apply\n' \
        "$source_file" "$(awk -F '\t' '$1=="error"{print "line " $2 ": " $3}' <<<"$records")" >&2
      exit 1
    }
    existing="$(awk -F '\t' '$1!="schema" && $1!="block"' <<<"$records")"
  fi

  local pair key value tb_i tb_item tb_parts
  for pair in "${PAIRS[@]}"; do
    key="${pair%%=*}" value="${pair#*=}"
    [[ "$key" =~ ^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$ && "$key" != schema ]] || die "invalid key '$key'"
    [[ "$value" != *[$'\t\n\r#']* ]] || die "invalid value for $key"
    if [[ "$key" =~ ^verification(_skills\.[^.]+)?$ ]]; then
      [[ "$LAYER" == team ]] || die "$key is read from the team layer only"
      [[ -z "$value" || "$value" =~ ^(off|light|standard|strict)$ ]] ||
        die "$key: '$value' is not off, light, standard or strict"
    elif [[ "$key" =~ ^verification ]]; then
      die "invalid key '$key'"
    fi
    if [[ "$key" == vendors.tiebreak ]]; then
      existing="$(awk -F '\t' '$1!="vendors.tiebreak" && $1!~/^vendors\.tiebreak\./' <<<"$existing")"
      if [[ -n "$value" ]]; then
        [[ "$value" != ,* && "$value" != *, && "$value" != *,,* ]] ||
          die "invalid value for $key"
        tb_i=0
        tb_parts=()
        IFS=',' read -ra tb_parts <<<"$value"
        for tb_item in "${tb_parts[@]}"; do
          existing+=$'\n'"vendors.tiebreak.$tb_i"$'\t'"$tb_item"
          tb_i=$((tb_i + 1))
        done
      fi
      continue
    fi
    existing="$(awk -F '\t' -v k="$key" '$1!=k' <<<"$existing")"
    [[ -n "$value" ]] && existing+=$'\n'"$key"$'\t'"$value"
  done
  body="$(grep -v '^$' <<<"$existing" | render)"

  make_tmp
  check_candidate "$body"

  printf '%s\n' "$body" >"$tmp/new"
  : >"$tmp/old"
  old_label=/dev/null
  [[ -f "$target" ]] && cp "$target" "$tmp/old" && old_label="$target"

  if cmp -s "$tmp/old" "$tmp/new"; then
    printf 'unchanged: %s\n' "$target"
    return 0
  fi
  if ((!WRITE)); then
    printf 'would write: %s (%s layer)\n' "$target" "$LAYER"
    grep -q '#' "$tmp/old" &&
      printf 'note: the file is rewritten whole; its comments are not kept\n'
    grep -q '^  frontier_guard: false$' "$tmp/new" &&
      printf 'note: fanout.frontier_guard false lets fan-out stages run on a frontier session model\n'
    diff -u --label "$old_label" --label "$target" "$tmp/old" "$tmp/new"
    return 0
  fi
  mkdir -p "$(dirname "$target")" || die "cannot create $(dirname "$target")"
  if ! { cp "$tmp/new" "$target.tmp.$$" && mv -f "$target.tmp.$$" "$target"; }; then
    rm -f "$target.tmp.$$"
    die "cannot write $target"
  fi
  printf 'wrote: %s (%s layer)\n' "$target" "$LAYER"
  printf 'stored:\n'
  awk -f "$PARSER" "$target" |
    awk -F '\t' '$1!="block" { print "  " $1 ": " $2 }'
}

records_of() {
  local r
  if ! r="$(awk -f "$PARSER" "$1")"; then
    printf 'setup: %s does not parse (%s); fix or remove it before apply\n' \
      "$1" "$(awk -F '\t' '$1=="error"{print "line " $2 ": " $3}' <<<"$r")" >&2
    return 1
  fi
  awk -F '\t' '$1!="schema" && $1!="block"' <<<"$r"
}

sorted_records() { grep -v '^$' <<<"$1" | LC_ALL=C sort; }

resolved_roles() {
  local json cut=',"layers":'
  json="$("$RESOLVER" "${LOCATE[@]}" all 2>/dev/null)" || return 1
  json="${json%%"$cut"*}"
  printf '%s' "${json//user-global/user-config}"
}

migrate() {
  local found=0 old_team="$ROOT/.claude/multi-agent.yaml" home
  ((${#PAIRS[@]} == 0)) || die "apply --migrate takes no <key>=<value>"
  make_tmp
  if [[ -n "$OLD_USER" && -f "$OLD_USER" ]]; then
    found=1
    if [[ -z "$USER_FILE" ]]; then
      printf 'skip: %s stays until the user layer has a new home; %s, then rerun apply --migrate\n' "$OLD_USER" "$SET_OPTION"
    elif ((OLD_USER_SAME)); then
      printf 'skip: %s, then rerun apply --migrate\n' "$NAME_OUTSIDE"
    else
      move_file user "$OLD_USER" "$USER_FILE"
    fi
  fi
  if [[ "$CLASS" == repo ]]; then
    home="$(convention_home)"
    if old_beside "$OLD_LOCAL" "$ROOT/$home/multi-agent.local.yaml"; then
      found=1
      move_file local "$OLD_LOCAL" "$ROOT/$home/multi-agent.local.yaml"
    fi
    if old_beside "$old_team" "$ROOT/$home/multi-agent.yaml"; then
      found=1
      move_file team "$old_team" "$ROOT/$home/multi-agent.yaml"
    fi
  fi
  ((found)) || printf 'nothing to migrate: no old file found\n'
}

move_file() {
  local layer="$1" old="$2" new="$3" old_recs new_recs="" merged key value kept body
  local label=/dev/null live=0 before="" back
  if [[ "$layer" != user ]]; then
    refuse_symlink "$old"
    refuse_symlink "$new"
  fi
  old_recs="$(records_of "$old")" || exit 1
  if [[ -f "$new" ]]; then
    new_recs="$(records_of "$new")" || exit 1
  elif [[ "$layer" != team ]]; then
    live=1
  fi
  merged="$new_recs"
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    if [[ "$layer" != team && "$key" == verification* ]]; then
      printf 'note: %s in %s is read from the team layer only, so it is not carried; set it with apply --layer team\n' "$key" "$old"
      continue
    fi
    if kept="$(awk -F '\t' -v k="$key" '$1==k { print $2; found=1 } END { exit !found }' <<<"$new_recs")"; then
      [[ "$kept" == "$value" ]] ||
        printf 'kept: %s: %s from %s (the old file says %s)\n' "$key" "$kept" "$new" "$value"
      continue
    fi
    merged+=$'\n'"$key"$'\t'"$value"
  done <<<"$old_recs"
  body="$(grep -v '^$' <<<"$merged" | render)"
  ((live)) || check_candidate "$body"

  printf '%s\n' "$body" >"$tmp/new"
  : >"$tmp/old"
  [[ -f "$new" ]] && cp "$new" "$tmp/old" && label="$new"
  if ((!WRITE)); then
    printf 'would move: %s into %s (%s layer), then delete %s\n' "$old" "$new" "$layer" "$old"
    grep -q '#' "$old" "$tmp/old" &&
      printf 'note: the new file is written whole; comments in either file are not kept\n'
    diff -u --label "$label" --label "$new" "$tmp/old" "$tmp/new"
    return 0
  fi

  ((live)) && before="$(resolved_roles)"
  mkdir -p "$(dirname "$new")" || die "cannot create $(dirname "$new")"
  if ! { cp "$tmp/new" "$new.tmp.$$" && mv -f "$new.tmp.$$" "$new"; }; then
    rm -f "$new.tmp.$$"
    die "cannot write $new"
  fi
  back="$(records_of "$new")" || exit 1
  if [[ "$(sorted_records "$back")" != "$(sorted_records "$merged")" ]]; then
    printf 'setup: %s does not read back the keys written; %s is kept\n' "$new" "$old" >&2
    exit 1
  fi
  if ((live)) && [[ "$(resolved_roles)" != "$before" ]]; then
    printf 'setup: %s does not resolve the values %s did; both are kept\n' "$new" "$old" >&2
    exit 1
  fi
  rm -f -- "$old" || die "wrote $new, but cannot delete $old"
  printf 'moved: %s into %s (%s layer); deleted %s\n' "$old" "$new" "$layer" "$old"
}

case "$ACTION" in
check) check ;;
apply) apply ;;
*) die "unknown action '$ACTION' (check or apply)" ;;
esac
