#!/usr/bin/env bash
# Machine profile: discover host facts, validate and store them, diff, explain, hand off.
#
#   profile.sh discover [--prerequisites FILE|-]
#   profile.sh record   --data-dir DIR [--confirm] [FILE|-]
#   profile.sh diff     --data-dir DIR [--prerequisites FILE|-]
#   profile.sh explain  --data-dir DIR KEY
#   profile.sh apply    --data-dir DIR --option KEY [--option KEY ...] [--confirm]
#
# discover and diff read the host and write nothing. record writes
# DIR/machine-profile/profile.json only with --confirm and only after every record
# validates. apply writes nothing: without --confirm it prints the plan, with
# --confirm it prints the values to hand to each plugin's setup. Nothing here
# prompts, installs, or evaluates a tree's environment. --prerequisites takes the
# table printed by harness-ops:prerequisites ("-" reads stdin).
#
# Exit: 0 ok, 1 refused (invalid document or unknown key), 2 usage or missing
# tool, 3 no profile stored, 4 diff found differences.
set -uo pipefail

die() {
  echo "profile.sh: $1" >&2
  exit "${2:-2}"
}

command -v jq >/dev/null 2>&1 || die "jq is required"

# Words a record key may not contain. The validator refuses them in a hand-supplied
# key, and rec rewrites them in a key discovery derives, from this one pattern.
CRED_RE='token|secret|passw(?:or)?d|credential|api.?key|private.?key'
# Value shapes the validator refuses in any string of a record: GitHub, AWS, Slack and
# sk- API tokens, JWTs, private-key blocks, and a password embedded in a URL.
VAL_RE='gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|(?<![A-Za-z0-9])(AKIA|ASIA)[0-9A-Z]{16}(?![A-Za-z0-9])|(?<![A-Za-z0-9])xox[abprs]-[A-Za-z0-9-]{10,}|(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}|(?<![A-Za-z0-9])eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|://[^/[:space:]:@]+:[^/[:space:]@]+@'

# Every record in a document is checked here. Prints one line per problem.
# shellcheck disable=SC2016  # jq source, not shell expansion
VALIDATE_JQ='
def nz: type == "string" and test("[^[:space:]]");
def locs:
  ((.machine.facts // []) | to_entries[] | {w: "machine.facts[\(.key)]", r: .value}),
  ((.machine.options // []) | to_entries[] | {w: "machine.options[\(.key)]", r: .value}),
  ((.domains // {}) | to_entries[] | .key as $d | .value
    | (((.identity // {}) | to_entries[] | {w: "domains[\($d)].identity.\(.key)", r: .value}),
       ((.facts // []) | to_entries[] | {w: "domains[\($d)].facts[\(.key)]", r: .value}),
       ((.options // []) | to_entries[] | {w: "domains[\($d)].options[\(.key)]", r: .value})));
def shape:
  if (.machine | type) != "object" then "machine must be an object"
  elif ((.machine.facts // []) | type) != "array" or ((.machine.options // []) | type) != "array" then "machine.facts and machine.options must be arrays"
  else empty end,
  if (.domains | type) != "object" then "domains must be an object"
  else (.domains | to_entries[]
    | if (.value | type) != "object" then "domains[\(.key)] must be an object"
      elif .value.tree != .key then "domains[\(.key)].tree must equal its key"
      elif ((.value.facts // []) | type) != "array" or ((.value.options // []) | type) != "array" or ((.value.identity // {}) | type) != "object"
        then "domains[\(.key)]: facts and options must be arrays and identity an object"
      else empty end) end;
def rp:
  .w as $w | .r as $r
  | if ($r | type) != "object" then "\($w): not a record"
    else [
      (if ($r.key | nz | not) then "has no key" else empty end),
      (if (["set", "default-verified", "default-unexamined", "blocked"] | index($r.verdict)) == null
        then "verdict must be one of set, default-verified, default-unexamined, blocked" else empty end),
      (if $r.verdict == "default-unexamined" then
        (if ($r.skipped_because | nz | not) then "default-unexamined requires skipped_because" else empty end),
        (if ($r.observed_by // "") != "" then "default-unexamined claims no observation, so it must not carry observed_by" else empty end)
      else
        (if ($r.observed_by | nz | not) then "has no observed_by" else empty end),
        (if (["observed", "reproduced"] | index($r.mode)) == null then "mode must be observed or reproduced" else empty end),
        (if $r.verdict == "default-verified" and ($r.observation | nz | not) then "default-verified requires an observation" else empty end),
        (if $r.verdict == "set" and ($r.supplied_by | nz | not) then "set requires supplied_by" else empty end),
        (if $r.verdict == "blocked" and ($r.guard | nz | not) then "blocked requires guard" else empty end)
      end),
      (if ($r.key | type) == "string" and ($r.key | test($cred; "i")) then "key names a credential" else empty end),
      ($r | .. | strings | select(test($val)) | "holds what looks like a credential")
    ] | .[] | "\($w): \(.)" end;
def dupkeys($w): map(select(type == "object") | .key) | group_by(.) | map(select(length > 1)) | .[] | "\($w): duplicate key \(.[0])";
if type != "object" then "document must be an object"
else ([shape] as $s
  | if ($s | length) > 0 then $s[]
    else (locs | rp),
         ((.machine.facts // []) | dupkeys("machine.facts")),
         ((.machine.options // []) | dupkeys("machine.options")),
         ((.domains // {}) | to_entries[] | .key as $d
           | ((.value.facts // []) | dupkeys("domains[\($d)].facts")),
             ((.value.options // []) | dupkeys("domains[\($d)].options")))
    end) end
'

# Flatten a document into path-keyed records. Options are stored state that
# discovery never observes, so diff leaves them out.
# shellcheck disable=SC2016  # jq source, not shell expansion
FLAT_JQ='
def flat($opts):
  ((.machine.facts // [])[] | {k: "machine.facts.\(.key)", r: .}),
  (if $opts then (.machine.options // [])[] | {k: "machine.options.\(.key)", r: .} else empty end),
  ((.domains // {}) | to_entries[] | .key as $d
    | {k: "domains.\($d)", r: null, domain: true},
      (.value | ((.identity // {}) | to_entries[] | {k: "domains.\($d).identity.\(.key)", r: .value}),
                ((.facts // [])[] | {k: "domains.\($d).facts.\(.key)", r: .}),
                (if $opts then (.options // [])[] | {k: "domains.\($d).options.\(.key)", r: .} else empty end)));
'

# shellcheck disable=SC2016  # jq source, not shell expansion
DIFF_JQ='
def show: if . == null then "(none)"
  else "\(.value // "(none)") [\(.verdict)] observed_by: \(.observed_by // "(none; skipped_because: \(.skipped_because // "?"))")" end;
def side($t): "  \($t)";
([$s | flat(false)] | map({key: .k, value: .}) | from_entries) as $S
| ([$f | flat(false)] | map({key: .k, value: .}) | from_entries) as $F
| (($S | keys) + ($F | keys) | unique)[] as $k
| ($S[$k]) as $a | ($F[$k]) as $b
| if $a == null then "added \($k)\n" + side("fresh:  \($b.r | show)")
  elif $b == null then "removed \($k)\n" + side("stored: \($a.r | show)")
  elif $a.domain then empty
  elif ($a.r.value // null) != ($b.r.value // null) or $a.r.verdict != $b.r.verdict
    then "changed \($k)\n" + side("stored: \($a.r | show)") + "\n" + side("fresh:  \($b.r | show)")
  else empty end
'

# rec KEY VALUE VERDICT [--arg FIELD VALUE ...] -> one compact JSON record. Every
# key discovery derives from host text (a binary name, an include path) passes
# through here, so the first letter of a credential word in it is bracketed and the
# key no longer matches the validator's refusal. Hand-supplied records never pass
# through here.
# shellcheck disable=SC2016  # jq source, not shell expansion
rec() {
  jq -nc --arg cred "$CRED_RE" '$ARGS.named | del(.cred)
    | .key |= gsub("(?=\($cred))(?<c>.)"; "[\(.c)]"; "i")' \
    --arg key "$1" --arg value "$2" --arg verdict "$3" "${@:4}"
}

unexamined() { # KEY REASON
  rec "$1" "" default-unexamined --arg skipped_because "$2" | jq -c 'del(.value)'
}

expand_home() {
  local p="$1"
  p="${p//\$\{HOME\}/${HOME:-}}"
  p="${p//\$HOME/${HOME:-}}"
  if [[ "$p" == \~ || "$p" == \~/* ]]; then p="${HOME:-}${p#\~}"; fi
  printf '%s' "$p"
}

# Facts about a path: absent, present, or (files) read-only.
dir_fact() { # KEY DIR
  if [[ -d "$2" ]]; then
    rec "$1" present set --arg observed_by "test -d $2" --arg mode observed --arg supplied_by "host filesystem"
  else
    rec "$1" absent default-verified --arg observed_by "test -d $2" --arg mode observed --arg observation "directory not found"
  fi
}

file_fact() { # KEY FILE
  if [[ ! -e "$2" ]]; then
    rec "$1" absent default-verified --arg observed_by "test -e $2" --arg mode observed --arg observation "file not found"
  elif [[ ! -w "$2" ]]; then
    # ponytail: -w only; an immutable attribute on a writable-looking file is not detected, add lsattr when a host needs it
    rec "$1" read-only blocked --arg observed_by "test -w $2" --arg mode observed \
      --arg guard "file is not writable; operator command: chmod u+w $2"
  else
    rec "$1" writable set --arg observed_by "test -w $2" --arg mode observed --arg supplied_by "host filesystem"
  fi
}

# The tree's own .envrc is read as text and never evaluated.
gh_fact() { # TREE
  local envrc="$1/.envrc" line val
  if [[ "$1" != /* ]]; then
    unexamined gh_config_dir "the tree pattern is not an absolute path"
  elif [[ ! -r "$envrc" ]]; then
    unexamined gh_config_dir "the tree has no .envrc, so its environment supplies no GH_CONFIG_DIR; the machine's gh directory is not assumed"
  elif ! line="$(grep -E '^[[:space:]]*export[[:space:]]+GH_CONFIG_DIR=' "$envrc" | tail -n 1)" || [[ -z "$line" ]]; then
    unexamined gh_config_dir "the tree's .envrc does not export GH_CONFIG_DIR"
  else
    val="${line#*GH_CONFIG_DIR=}"
    val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    val="$(expand_home "$val")"
    if [[ "$val" == *'$'* || "$val" == *'`'* || "$val" != /* ]]; then
      unexamined gh_config_dir "the tree's .envrc computes GH_CONFIG_DIR when evaluated; it is not read statically"
    else
      rec gh_config_dir "$val" set --arg observed_by "grep 'export GH_CONFIG_DIR' $envrc" --arg mode observed \
        --arg supplied_by "tree environment (.envrc)"
    fi
  fi
}

binaries() { # TABLE
  local tool status mode plugins
  jq -Rrn '[inputs | split("\t") | select(length >= 3 and (.[2] == "present" or .[2] == "missing"))]
    | group_by(.[0])[]
    | [.[0][0],
       (map(.[2]) | if any(. == "missing") then "missing" else "present" end),
       (map(.[3] // "") | if any(contains(":setup")) then "reproduced" else "observed" end),
       (map(.[1]) | unique | join(","))] | @tsv' <<<"$1" |
    while IFS=$'\t' read -r tool status mode plugins; do
      if [[ "$status" == present ]]; then
        rec "binary.$tool" present set --arg observed_by "harness-ops:prerequisites (declared by $plugins)" \
          --arg mode "$mode" --arg supplied_by "host PATH"
      else
        rec "binary.$tool" missing default-verified --arg observed_by "harness-ops:prerequisites (declared by $plugins)" \
          --arg mode "$mode" --arg observation "not found on PATH or in the plugin's local bin"
      fi
    done
}

discover() {
  local cores by table origin pat inc tree
  local -a machine=() pairs=()
  machine+=("$(rec os "$(uname -s)" set --arg observed_by "uname -s" --arg mode observed --arg supplied_by host)")
  if cores="$(nproc 2>/dev/null)" && [[ -n "$cores" ]]; then
    by="nproc"
  elif cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" && [[ -n "$cores" ]]; then
    by="getconf _NPROCESSORS_ONLN"
  else
    cores=""
  fi
  if [[ -n "$cores" ]]; then
    machine+=("$(rec cores "$cores" set --arg observed_by "$by" --arg mode observed --arg supplied_by host)")
  else
    machine+=("$(unexamined cores "neither nproc nor getconf reported a count")")
  fi
  machine+=("$(unexamined worktree_root "no discovery source is defined for it")")
  machine+=("$(unexamined report_root "no discovery source is defined for it")")
  if [[ -z "$PREREQ" ]]; then
    machine+=("$(unexamined binaries "no prerequisites table supplied; run /harness-ops:prerequisites and pass its output with --prerequisites")")
  else
    if [[ "$PREREQ" == "-" ]]; then table="$(cat)"; else
      [[ -r "$PREREQ" ]] || die "cannot read $PREREQ"
      table="$(cat -- "$PREREQ")"
    fi
    while IFS= read -r line; do [[ -n "$line" ]] && machine+=("$line"); done < <(binaries "$table")
  fi

  while IFS=$'\t' read -r origin pat inc; do
    [[ -n "$pat" && -n "$inc" ]] || continue
    tree="$(expand_home "$pat")"; tree="${tree%/}"; tree="${tree%/\*\*}"; tree="${tree%/}"
    inc="$(expand_home "$inc")"
    if [[ "$inc" != /* && ! "$inc" =~ ^[A-Za-z]:/ && ("$origin" == file:/* || "$origin" =~ ^file:[A-Za-z]:/) ]]; then
      inc="$(dirname "${origin#file:}")/$inc"
    fi
    pairs+=("$(jq -nc --arg tree "$tree" \
      --argjson gi "$(rec git_include "$inc" set --arg observed_by "git config --list --show-origin ($origin)" \
        --arg mode observed --arg supplied_by "git config includeIf gitdir")" \
      --argjson gh "$(gh_fact "$tree")" \
      --argjson f1 "$(dir_fact tree_present "$tree")" \
      --argjson f2 "$(file_fact "git_include_file:$inc" "$inc")" \
      '{tree: $tree, git_include: $gi, gh: $gh, facts: [$f1, $f2]}')")
  done < <(cd / && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_CONFIG git config --list --show-origin 2>/dev/null |
    jq -Rr 'capture("^(?<origin>[^\t]*)\t(?<key>includeif\\.gitdir(?:/i)?:(?<pat>.*)\\.path)=(?<inc>.*)$")? | [.origin, .pat, .inc] | @tsv')

  local m d doc
  m="$(printf '%s\n' "${machine[@]}" | jq -sc 'sort_by(.key)')"
  d="$(printf '%s\n' ${pairs[@]+"${pairs[@]}"} | jq -sc '.')"
  doc="$(jq -nS --argjson m "$m" --argjson d "$d" '
    {machine: {facts: $m},
     domains: ($d | group_by(.tree) | map(. as $g | {key: $g[0].tree, value: {
        tree: $g[0].tree,
        identity: {
          git_include: ($g[0].git_include
            | .value = ($g | map(.git_include.value) | unique | join(", "))
            | .observed_by = ($g | map(.git_include.observed_by) | unique | join("; "))),
          gh_config_dir: $g[0].gh},
        facts: ($g | map(.facts[]) | unique_by(.key) | sort_by(.key)),
        options: []}}) | from_entries)}')"
  validate "$doc" || die "discovery produced an invalid document" 1
  printf '%s\n' "$doc"
}

validate() {
  local problems
  jq -e . >/dev/null 2>&1 <<<"$1" || { echo "profile.sh: refused: the document is not valid JSON" >&2; return 1; }
  problems="$(jq -r --arg cred "$CRED_RE" --arg val "$VAL_RE" "$VALIDATE_JQ" <<<"$1")" || return 1
  [[ -z "$problems" ]] && return 0
  printf 'profile.sh: refused:\n  %s\n' "${problems//$'\n'/$'\n'  }" >&2
  return 1
}

resolve_store() {
  # shellcheck disable=SC2016  # a literal unresolved token
  [[ -n "$DATA_DIR" && "$DATA_DIR" != *'${'* ]] || die "--data-dir is empty or unresolved; pass the plugin data directory"
  STORE="${DATA_DIR%/}/machine-profile/profile.json"
}

load_stored() {
  resolve_store
  if [[ ! -f "$STORE" ]]; then
    echo "no profile for this machine ($STORE is absent); run the profile action to produce one"
    exit 3
  fi
  STORED="$(cat -- "$STORE")"
  validate "$STORED" || exit 1
}

record() {
  local doc src="${POS[0]:--}" tmp
  resolve_store
  if [[ "$src" == "-" ]]; then doc="$(cat)"; else
    [[ -r "$src" ]] || die "cannot read $src"
    doc="$(cat -- "$src")"
  fi
  validate "$doc" || exit 1
  if [[ "$CONFIRM" -ne 1 ]]; then
    echo "valid; dry run, nothing written. Re-run with --confirm to write $STORE"
    return 0
  fi
  mkdir -p "$(dirname "$STORE")" || die "cannot create $(dirname "$STORE")"
  tmp="$STORE.tmp.$$"
  if ! jq -S . <<<"$doc" >"$tmp" || ! mv -f "$tmp" "$STORE"; then
    rm -f "$tmp"
    die "could not write $STORE"
  fi
  echo "wrote $STORE"
}

diff_cmd() {
  local fresh out
  load_stored
  fresh="$(discover)" || exit 1
  out="$(jq -nr --argjson s "$STORED" --argjson f "$fresh" "$FLAT_JQ $DIFF_JQ")" || die "diff failed" 1
  [[ -z "$out" ]] && return 0
  printf '%s\n' "$out"
  exit 4
}

explain() {
  local q="${POS[0]:-}" out
  [[ -n "$q" ]] || die "explain needs a key or path"
  load_stored
  out="$(jq -r --arg q "$q" "$FLAT_JQ"'
    [flat(true) | select(.r != null and (.k == $q or .r.key == $q)) | "\(.k)\n" + (.r | tojson)] | .[]' <<<"$STORED")"
  [[ -n "$out" ]] || { echo "no recorded value for $q" >&2; exit 1; }
  printf '%s\n' "$out"
}

apply() {
  local key plugin opt hits status=0
  [[ ${#OPTIONS[@]} -gt 0 ]] || die "apply needs at least one --option KEY"
  load_stored
  for key in "${OPTIONS[@]}"; do
    plugin="${key%%.*}"; opt="${key#*.}"
    hits="$(jq -c --arg k "$key" '
      ((.machine.options // [])[] | select(.key == $k) | {scope: "machine", r: .}),
      ((.domains // {}) | to_entries[] | .key as $d | (.value.options // [])[] | select(.key == $k) | {scope: $d, r: .})' <<<"$STORED")"
    if [[ -z "$hits" ]]; then
      echo "refused $key: no recorded option with that key"
      status=1
      continue
    fi
    while IFS= read -r hit; do
      scope="$(jq -r .scope <<<"$hit")"
      verdict="$(jq -r .r.verdict <<<"$hit")"
      value="$(jq -r '.r.value // ""' <<<"$hit")"
      if [[ "$scope" != machine ]]; then
        echo "conflict $key: recorded under domain $scope; pluginConfigs has one slot, so a per-domain identity is never applied there. Stopped for this option."
      elif [[ "$verdict" != set ]]; then
        echo "skipped $key: verdict $verdict has no non-default value to hand over"
      elif [[ "$CONFIRM" -eq 1 ]]; then
        echo "handoff $key: give /$plugin:setup the value $opt=$value. Setup skills are not model-invocable, so the operator types the command."
      else
        echo "plan $key: would hand /$plugin:setup the value $opt=$value"
      fi
    done <<<"$hits"
  done
  [[ "$CONFIRM" -eq 1 ]] || echo "not confirmed: nothing handed off. Re-run with --confirm once the operator agrees."
  return "$status"
}

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
CMD="$1"
shift
DATA_DIR="" PREREQ="" CONFIRM=0 STORE="" STORED=""
OPTIONS=() POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --data-dir | --prerequisites | --option)
    [[ $# -ge 2 ]] || die "$1 needs a value"
    case "$1" in
    --data-dir) DATA_DIR="$2" ;;
    --prerequisites) PREREQ="$2" ;;
    --option) OPTIONS+=("$2") ;;
    *) ;;
    esac
    shift 2
    ;;
  --confirm) CONFIRM=1; shift ;;
  --help | -h) usage; exit 0 ;;
  -) POS+=("-"); shift ;;
  -*) die "unknown argument $1 (see --help)" ;;
  *) POS+=("$1"); shift ;;
  esac
done

case "$CMD" in
discover) discover ;;
record) record ;;
diff) diff_cmd ;;
explain) explain ;;
apply) apply ;;
--help | -h) usage ;;
*) die "unknown command $CMD (see --help)" ;;
esac
