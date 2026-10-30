#!/usr/bin/env bash
# Build block-cross-domain's identity-domain map from a machine profile.
#
#   identity-domains.sh --profile FILE|- [--data-dir DIR [--confirm] [--replace]]
#                       [--owner NAME=OWNER] [--marker NAME=TEXT]
#                       [--az-config-dir NAME=DIR]
#                       [--shared-exception FROM[,FROM...]:TO=PATH]
#
# FILE is a /harness-ops:machine-profile document: the stored profile.json or a
# saved `discover` output ("-" reads stdin). Each recorded identity domain whose
# tree is an absolute path with no wildcard becomes one map domain: the tree is
# its root under the profile's own os key, and a gh directory the profile
# records `set` is its gh_config_dir. A domain is named after its tree's last
# segment, with `-2`, `-3` added on a clash. The profile records no owners,
# identity markers, az directory or shared exceptions; the repeatable flags add
# them by domain name, and a value left unsupplied is left out of the map.
#
# A --shared-exception opens PATH, a directory of domain TO, to sessions in the
# FROM domains, one way: the map entry {path, from, to}. PATH must be TO's tree,
# or below it or below one of TO's owner directories under $HOME, and not below
# another domain's path nested there, compared as block-cross-domain.sh compares
# them; FROM must not list TO.
#
# Prints the map, and one note per tree skipped or value left out on stderr.
# With --data-dir, refuses when DIR already holds a different map, unless
# --replace, and reports a map that is already there unchanged. Writes
# DIR/identity-domains.json only with --confirm, and nothing else, anywhere.
#
# Exit: 0 ok, 1 refused (nothing written), 2 usage or missing tool.
set -uo pipefail

die() {
  echo "identity-domains.sh: $1" >&2
  exit "${2:-2}"
}

command -v jq >/dev/null 2>&1 || die "jq is required"

# The raw profile in; one object out: the map, the notes, and the refusals. The
# root and value rules are block-cross-domain.sh's own, so a map written here
# compiles there.
# shellcheck disable=SC2016  # jq source, not shell expansion
BUILD_JQ='
def oneline: type == "string" and length > 0 and (explode | all(. >= 32 and . != 127));
def oskey:
  if test("^Darwin") then "macos"
  elif test("^(MINGW|MSYS|CYGWIN)") then "windows"
  else "linux" end;
def absolute($os):
  if $os == "windows"
  then test("^[A-Za-z]:[\\\\/]+[^\\\\/]") or (test("^/[^/]") and (test("^/[A-Za-z][\\\\/]*$") | not))
  else test("^/[^/]") end;
def base: sub("[\\\\/]+$"; "") | split("/") | last | split("\\") | last
  | gsub("[^A-Za-z0-9_.-]"; "-") | if . == "" then "domain" else . end;
def fresh($taken):
  . as $b
  | if $taken[$b] then first(range(2; infinite) | "\($b)-\(.)" | select($taken[.] | not)) else $b end;
def fold($os):
  gsub("[\\\\/]+"; "/") | sub("(?<=.)/$"; "")
  | if $os == "windows" then ascii_downcase | sub("^/(cygdrive/|mnt/)?(?<d>[a-z])(?=/|$)"; "\(.d):")
    else sub("^/(cygdrive|mnt)/(?<d>[A-Za-z])(?=/|$)"; "\(.d | ascii_downcase):")
      | sub("^(?<d>[A-Z]):"; "\(.d | ascii_downcase):") end;
# The domain of the longest path in $paths ({d, v} objects) that holds or equals
# the input, else null.
def innermost($paths; $os):
  fold($os) as $q
  | [$paths[] | (.v | fold($os)) as $r | select($q == $r or ($q | startswith($r + "/"))) | {d, n: ($r | length)}]
  | max_by(.n) | .d;
($ARGS.positional | [range(0; length; 3) as $i | {k: .[$i][1:], n: .[$i + 1][1:], v: .[$i + 2][1:]}]) as $extra
| (try fromjson catch null) as $doc
| if ($doc | type) != "object" then {refused: ["the profile is not a JSON object"]}
  elif ($doc.domains | type) != "object" then {refused: ["the profile has no domains object"]}
  else
    ([$doc | .machine? | .facts? // [] | .[]? | objects | select(.key == "os" and (.value | oneline)) | .value][0]) as $osval
    | if $osval == null then {refused: ["the profile records no os fact, so the roots have no os key"]}
      else ($osval | oskey) as $os
      | [$doc.domains | to_entries[] | .key as $tree | .value
          | if ($tree | oneline | not) then {note: "skipped a tree that is not a one-line string"}
            elif ($tree | test("[*?\\[]")) then {note: "skipped tree \($tree): it holds a wildcard"}
            elif ($tree | absolute($os) | not) then {note: "skipped tree \($tree): it is not absolute below a filesystem root"}
            else {tree: $tree, base: ($tree | base), gh: ((.identity? | .gh_config_dir? | objects) // {})} end] as $rows
      | (reduce ($rows[] | select(has("tree"))) as $r ({taken: {}, out: []};
          .taken as $t | ($r.base | fresh($t)) as $n | .taken[$n] = true | .out += [$r + {name: $n}])
        | .out) as $kept
      | ($kept | map(.name)) as $names
      | ([$extra[] | select(.k != "shared-exception" and (.n as $n | $names | any(.[]; . == $n) | not))
          | "--\(.k) names domain \(.n), which the profile does not yield; its domains are \($names | join(", "))"]
        + [$extra[] | select(.v | oneline | not) | "a --\(.k) value is not a non-empty one-line string"]
        + [$extra[] | select(.k == "shared-exception") | .n as $n | .v as $p | ($n | split(":")) as $s
            | if ($s | length) != 2 or $s[0] == "" or $s[1] == "" then "--shared-exception takes FROM[,FROM...]:TO=PATH, not \($n)=\($p)"
              else ($s[0] | split(",")) as $from | $s[1] as $to
              | [$from[], $to | select(. as $d | $names | any(.[]; . == $d) | not)] as $unknown
              | if $unknown != [] then "--shared-exception names domain \($unknown[0]), which the profile does not yield; its domains are \($names | join(", "))"
                elif any($from[]; . == $to) then "--shared-exception \($n): FROM lists TO"
                elif ($p | oneline) and ($p | innermost([$kept[] | {d: .name, v: .tree}]
                    + [$extra[] | select(.k == "owner") | .n as $d | .v as $o | $home | select(. != "")
                        | {d: $d, v: "\(.)/src/github.com/\($o)"}, {d: $d, v: "\(.)/worktrees/github.com/\($o)"}]; $os) != $to)
                then "--shared-exception \($n): \($p) is not the tree of domain \($to), below it, or below one of its owner directories, outside every domain nested there"
                else empty end
              end]) as $bad
      | def given($k; $n): [$extra[] | select(.k == $k and .n == $n) | .v];
        def ghset: .gh.verdict == "set" and (.gh.value | oneline);
        if ($kept | length) == 0 then {refused: (["no identity domain in the profile has an absolute tree with no wildcard"] + $bad), notes: [$rows[] | .note // empty]}
        elif ($bad | length) > 0 then {refused: $bad, notes: [$rows[] | .note // empty]}
        else
          ($kept | map(
              .name as $n
              | {key: $n, value: (
                  {roots: {($os): [.tree]}}
                  + (given("owner"; $n) | if length > 0 then {owners: .} else {} end)
                  + (given("marker"; $n) | if length > 0 then {identity_markers: .} else {} end)
                  + (if ghset then {gh_config_dir: .gh.value} else {} end)
                  + (given("az-config-dir"; $n) | if length > 0 then {az_config_dir: last} else {} end))})
            | from_entries) as $domains
          | ([$extra[] | select(.k == "shared-exception") | (.n | split(":")) as $s
                | {path: .v, from: ($s[0] | split(",")), to: $s[1]}]
              | if length > 0 then {shared_exceptions: .} else {} end) as $shared
          | {map: ({domains: $domains} + $shared),
             notes: ([$rows[] | .note // empty]
               + [$kept[] | select(ghset | not)
                   | "domain \(.name): gh_config_dir left out; the profile records it \(.gh.verdict // "nowhere")"]
               + [$kept[] | "domain \(.name) is tree \(.tree)"]
               + [$kept[] | .name as $n
                   | [["owner", "owners"], ["marker", "identity_markers"], ["az-config-dir", "az_config_dir"]]
                   | map(select(given(.[0]; $n) | length == 0) | .[1])
                   | select(length > 0)
                   | "domain \($n): \(join(", ")) not in the profile and not supplied, so left out"]
               + (if $shared == {} then ["shared_exceptions were not supplied, so they are left out"] else [] end))}
        end
      end
  end
'

PROFILE="" DATA_DIR="" CONFIRM=0 REPLACE=0
# Flag, domain name, value triples for jq's --args. Each word carries a leading
# `:`, which BUILD_JQ strips, so a word that starts with `-` is never read as a
# jq option.
EXTRA=()
add_extra() { # FLAG NAME=VALUE
  [[ "$2" == ?*=* ]] || die "--$1 takes NAME=VALUE"
  EXTRA+=(":$1" ":${2%%=*}" ":${2#*=}")
}
while [[ $# -gt 0 ]]; do
  case "$1" in
  --profile | --data-dir | --owner | --marker | --az-config-dir | --shared-exception)
    [[ $# -ge 2 ]] || die "$1 needs a value"
    case "$1" in
    --profile) PROFILE="$2" ;;
    --data-dir) DATA_DIR="$2" ;;
    --owner) add_extra owner "$2" ;;
    --marker) add_extra marker "$2" ;;
    --az-config-dir) add_extra az-config-dir "$2" ;;
    --shared-exception) add_extra shared-exception "$2" ;;
    *) ;;
    esac
    shift 2
    ;;
  --confirm) CONFIRM=1; shift ;;
  --replace) REPLACE=1; shift ;;
  --help | -h)
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *) die "unknown argument $1 (see --help)" ;;
  esac
done

[[ -n "$PROFILE" ]] || die "--profile is required"
# shellcheck disable=SC2016  # a literal unresolved token
if [[ -n "$DATA_DIR" && "$DATA_DIR" == *'${'* ]]; then die "--data-dir is unresolved; pass the plugin data directory"; fi
((CONFIRM == 0)) || [[ -n "$DATA_DIR" ]] || die "--confirm needs --data-dir"

if [[ "$PROFILE" == "-" ]]; then
  RAW="$(cat)"
else
  [[ -r "$PROFILE" ]] || die "cannot read $PROFILE"
  RAW="$(cat -- "$PROFILE")"
fi

# MSYS_NO_PATHCONV=1 keeps Git Bash from rewriting the path values handed to jq.
OUT="$(MSYS_NO_PATHCONV=1 jq -c -R -s --arg home "${HOME:-}" "$BUILD_JQ" --args ${EXTRA[@]+"${EXTRA[@]}"} <<<"$RAW")" || die "jq could not build the map" 1
OUT=${OUT//$'\r'/}
jq -r '(.notes // [])[] | "note: \(.)"' <<<"$OUT" | tr -d '\r' >&2
REFUSED="$(jq -r '(.refused // [])[]' <<<"$OUT" | tr -d '\r')"
if [[ -n "$REFUSED" ]]; then
  printf 'identity-domains.sh: refused, nothing written:\n  %s\n' "${REFUSED//$'\n'/$'\n'  }" >&2
  exit 1
fi
MAP="$(jq '.map' <<<"$OUT" | tr -d '\r')"
printf '%s\n' "$MAP"

[[ -n "$DATA_DIR" ]] || exit 0
TARGET="${DATA_DIR%/}/identity-domains.json"
[[ ! -d "$TARGET" ]] || die "refused: $TARGET is a directory" 1
if [[ -e "$TARGET" ]]; then
  if [[ "$(jq -S -c . 2>/dev/null <"$TARGET" | tr -d '\r')" == "$(jq -S -c . <<<"$MAP" | tr -d '\r')" ]]; then
    echo "unchanged: $TARGET already holds this map" >&2
    exit 0
  fi
  ((REPLACE)) || die "refused: $TARGET holds a different map; re-run with --replace to overwrite it" 1
fi
if ((CONFIRM == 0)); then
  echo "dry run, nothing written. Re-run with --confirm to write $TARGET" >&2
  exit 0
fi
mkdir -p -- "$DATA_DIR" || die "cannot create $DATA_DIR" 1
TMP="$TARGET.tmp.$$"
if ! printf '%s\n' "$MAP" >"$TMP" || ! mv -f -- "$TMP" "$TARGET"; then
  rm -f -- "$TMP"
  die "could not write $TARGET" 1
fi
echo "wrote $TARGET" >&2
