#!/usr/bin/env bash
# setup.sh — the deterministic half of /testing:setup.
#
# check prints four sections and changes nothing:
#   config        the resolved .claude/testing.yaml (scripts/resolve-config.sh)
#   lint          per language the repository's tracked test files use, whether
#                 its lint config turns on the rules that catch can't-fail tests.
#                 A missing rule is a FINDING; Bash, PowerShell and Go have no
#                 maintained rule. The reading is textual: a rule named in a
#                 lint config, or the plugin's recommended set referenced.
#   instruction   an optional line for CLAUDE.md or AGENTS.md, printed to paste;
#                 this script never edits either file
#   hook-entry    for each consumer glob no shipped hook row matches, a
#                 .claude/settings.json entry that runs test-scan on it
# apply writes <root>/.claude/testing.yaml from the answer flags, whole, and
# keeps it only when it resolves; it writes no other file, and refuses when
# .claude or .claude/testing.yaml is a symlink.
#
# Usage:
#   setup.sh check [--root <dir>]
#   setup.sh apply [--root <dir>] [--include <glob>]... [--exclude <glob>]...
#                  [--enable <id>]... [--disable <id>]... [--adapter-dir <dir>]...
#                  [--extend <id>.<field>=<value>]... [--rule <rule>=off|warn|error]...
#
# Exit: check 0 no finding, 1 a lint finding; apply 0 written; 2 usage error,
# no repository, or a config that does not resolve.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
RESOLVER="$PLUGIN/scripts/resolve-config.sh"
LOADER="$PLUGIN/skills/audit/scripts/adapter-load.awk"

die() {
  printf 'setup: %s\n' "$1" >&2
  exit 2
}

ACTION="${1:-}"
shift || true
ROOT=""
inc=() exc=() ena=() dis=() dirs=() ext=() rules=()
while [[ $# -gt 0 ]]; do
  [[ $# -gt 1 ]] || die "$1 needs a value"
  case "$1" in
  --root) ROOT="$2" ;;
  --include) inc+=("$2") ;;
  --exclude) exc+=("$2") ;;
  --enable) ena+=("$2") ;;
  --disable) dis+=("$2") ;;
  --adapter-dir) dirs+=("$2") ;;
  --extend) ext+=("$2") ;;
  --rule) rules+=("$2") ;;
  *) die "unknown argument '$1'" ;;
  esac
  shift 2
done
if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

# q <value>: a single-quoted YAML scalar.
q() { printf "'%s'" "${1//\'/\'\'}"; }
# flow <item>...: a one-line flow list of single-quoted scalars.
flow() {
  local s="" v
  for v in "$@"; do s+="${s:+, }$(q "$v")"; done
  printf '[%s]' "$s"
}

apply() {
  local d="$ROOT/.claude" f="$ROOT/.claude/testing.yaml" bak="" tmp y="" e id field r
  # A committed symlink would turn the write into one on the file it names.
  [[ ! -L "$d" && ! -L "$f" ]] || die "refusing to write through a symlink: $d or $f"
  [[ ! -e "$f" || -f "$f" ]] || die "$f is not a regular file"
  if [[ ${#ena[@]} -gt 0 || ${#dis[@]} -gt 0 ]]; then
    y+=$'adapters:\n'
    [[ ${#ena[@]} -gt 0 ]] && y+="  enable: $(flow "${ena[@]}")"$'\n'
    [[ ${#dis[@]} -gt 0 ]] && y+="  disable: $(flow "${dis[@]}")"$'\n'
  fi
  if [[ ${#inc[@]} -gt 0 || ${#exc[@]} -gt 0 ]]; then
    y+=$'paths:\n'
    [[ ${#inc[@]} -gt 0 ]] && y+="  include: $(flow "${inc[@]}")"$'\n'
    [[ ${#exc[@]} -gt 0 ]] && y+="  exclude: $(flow "${exc[@]}")"$'\n'
  fi
  [[ ${#dirs[@]} -gt 0 ]] && y+="adapter_dirs: $(flow "${dirs[@]}")"$'\n'
  if [[ ${#ext[@]} -gt 0 ]]; then
    y+=$'extend:\n'
    # One key per <id>.<field>, its items in flag order.
    declare -A items=()
    local keys=()
    for e in "${ext[@]}"; do
      [[ "$e" == *.*=* ]] || die "--extend takes <id>.<field>=<value>, got: $e"
      [[ -n "${items[${e%%=*}]+x}" ]] || keys+=("${e%%=*}")
      items[${e%%=*}]+="$(q "${e#*=}"), "
    done
    local last=""
    for e in "${keys[@]}"; do
      id="${e%%.*}" field="${e#*.}"
      [[ "$id" == "$last" ]] || y+="  $id:"$'\n'
      last="$id"
      y+="    $field: [${items[$e]%, }]"$'\n'
    done
  fi
  if [[ ${#rules[@]} -gt 0 ]]; then
    y+=$'rules:\n'
    for r in "${rules[@]}"; do
      [[ "$r" == *=* ]] || die "--rule takes <rule>=off|warn|error, got: $r"
      id="${r%%=*}"
      id="${id#testing/audit/}"
      [[ "$id" == rule-* ]] || id="rule-$id"
      y+="  $id: ${r#*=}"$'\n'
    done
  fi
  mkdir -p "$d" || die "cannot create $d"
  [[ "$(cd "$d" && pwd -P)" == "$(cd "$ROOT" && pwd -P)"/* ]] || die "$d resolves outside $ROOT"
  # Write beside the target and rename over it, so no write follows a link.
  if [[ -f "$f" ]]; then
    bak="$(mktemp "$d/.testing.yaml.XXXXXX")" || die "cannot create a temporary file in $d"
    cp -p "$f" "$bak" || die "cannot back up $f"
  fi
  tmp="$(mktemp "$d/.testing.yaml.XXXXXX")" || die "cannot create a temporary file in $d"
  # mktemp creates the file 0600; give it the mode a plain write would.
  chmod "$(printf '%o' $((0666 & ~0$(umask))))" "$tmp"
  printf '# Test-file scope and rule levels for the testing plugin (/testing:setup).\n%s' "$y" >"$tmp"
  mv -f "$tmp" "$f" || die "cannot write $f"
  if ! env -u CLAUDE_PROJECT_DIR bash "$RESOLVER" --root "$ROOT" --home "$ROOT/.claude/nonexistent-home" >/dev/null; then
    if [[ -n "$bak" ]]; then mv -f "$bak" "$f"; else rm -f "$f"; fi
    die "the answers do not resolve (see above); $f is unchanged"
  fi
  [[ -z "$bak" ]] || rm -f "$bak"
  printf 'wrote %s\n' "$f"
  cat "$f"
}

# --- check --------------------------------------------------------------------
check() {
  local cfg findings=0 langs tracked lint_files f
  printf '== config ==\n'
  cfg="$(bash "$RESOLVER" --root "$ROOT")" || die "the .claude/testing.yaml layers do not resolve (see above)"
  if [[ -z "$cfg" ]]; then
    printf 'no .claude/testing.yaml layer; the shipped adapters, globs and rule levels apply\n'
  else
    printf '%s\n' "$cfg"
  fi

  # Languages: the lexer language of every adapter whose files: glob matches a
  # tracked file.
  tracked="$(git -C "$ROOT" ls-files 2>/dev/null | tr -d '\r')"
  langs="$(awk -F'\t' '
    NR == FNR {
      if ($2 == "language") lang[$1] = $3
      if ($2 == "files") { g = $3; gsub(/\./, "[.]", g); gsub(/\*/, ".*", g); n++; re[n] = "^" g "$"; rid[n] = $1 }
      next
    }
    { b = $0; sub(/.*\//, "", b); for (i = 1; i <= n; i++) if (b ~ re[i]) seen[lang[rid[i]]] = 1 }
    END { for (l in seen) print l }' <(awk -f "$LOADER" "$PLUGIN"/skills/audit/adapters/*.yaml) - <<<"$tracked" | sort -u)"

  printf '\n== lint ==\n'
  lint_files=()
  while IFS= read -r f; do
    case "${f##*/}" in
    eslint.config.* | .eslintrc* | package.json | pyproject.toml | ruff.toml | .ruff.toml | *.csproj | Directory.Packages.props | Directory.Build.props | .editorconfig | *.globalconfig)
      [[ -f "$ROOT/$f" ]] && lint_files+=("$ROOT/$f")
      ;;
    *) ;;
    esac
  done <<<"$tracked"
  lint_text() { # lint_text <basename glob>...: the concatenated text of matching files
    local g p
    for p in ${lint_files[@]+"${lint_files[@]}"}; do
      for g in "$@"; do
        # shellcheck disable=SC2053 # the glob is a pattern on purpose
        [[ "${p##*/}" == $g ]] && cat "$p" && echo
      done
    done
  }
  report() { # report <lang> <rule> <PRESENT|FINDING> <detail>
    printf '%-7s %-40s %-8s %s\n' "$1" "$2" "$3" "$4"
    [[ "$3" == FINDING ]] && findings=$((findings + 1))
    return 0
  }
  [[ -n "$langs" ]] || printf 'no tracked test file matches a shipped adapter glob\n'

  local pkg eslint cs cfgtxt
  pkg="$(lint_text package.json)"
  eslint="$(lint_text 'eslint.config.*' '.eslintrc*' package.json)"
  cs="$(lint_text '*.csproj' Directory.Packages.props Directory.Build.props)"
  cfgtxt="$(lint_text .editorconfig '*.globalconfig')"
  # eslint_rule <lang> <framework dep> <plugin package> <rule>
  eslint_rule() {
    if grep -Eq "[\"']$4[\"'] *: *([\"']off[\"']|0)" <<<"$eslint"; then
      report "$1" "$4" FINDING "turned off in the ESLint config"
    elif grep -q "$4" <<<"$eslint"; then
      report "$1" "$4" PRESENT "named in the ESLint config"
    elif grep -q "$3" <<<"$eslint" && grep -q recommended <<<"$eslint"; then
      report "$1" "$4" PRESENT "$3 referenced with a recommended config, which turns it on"
    else
      report "$1" "$4" FINDING "add $3 and turn on $4 (it is in the plugin's recommended config)"
    fi
  }
  # dotnet_rule <rule> <analyzer package> <brought in by>
  dotnet_rule() {
    if grep -Eqi "dotnet_diagnostic\.$1\.severity *= *(none|silent|suggestion)" <<<"$cfgtxt"; then
      report cs "$1" FINDING "lowered below warning in .editorconfig or a .globalconfig"
    elif grep -Eqi "Include=\"($2|$3)\"" <<<"$cs"; then
      report cs "$1" PRESENT "$2 is referenced (directly or through $3)"
    else
      report cs "$1" FINDING "reference $2 so $1 runs at build time"
    fi
  }
  # ruff_rule <code> <on by default: 1|0>
  ruff_rule() {
    local sel ign s on=0
    sel="$(ruff_codes select)"
    ign="$(ruff_codes ignore)"
    if [[ -z "$sel" && "$2" -eq 1 ]]; then on=1; fi
    for s in $sel $(ruff_codes extend-select); do [[ "$s" == ALL || "$1" == "$s"* ]] && on=1; done
    for s in $ign; do [[ "$1" == "$s"* ]] && on=0; done
    if ((on)); then report python "ruff $1" PRESENT "selected in the ruff config"; else report python "ruff $1" FINDING "select $1 (or its prefix) in the ruff config"; fi
  }
  # ruff_codes <select|extend-select|ignore>: the quoted codes of that array.
  ruff_codes() {
    lint_text pyproject.toml ruff.toml .ruff.toml | awk -v k="$1" '
      $0 ~ "^[ \t]*" k "[ \t]*=[ \t]*\\[" { on = 1 }
      on { s = $0; while (match(s, /["'"'"'][A-Z]+[0-9]*["'"'"']/)) { print substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) }
           if ($0 ~ /\]/) on = 0 }'
  }

  local l
  for l in $langs; do
    case "$l" in
    js)
      grep -q '"jest"' <<<"$pkg" && eslint_rule js jest eslint-plugin-jest jest/valid-expect
      grep -q '"vitest"' <<<"$pkg" && eslint_rule js vitest @vitest/eslint-plugin vitest/valid-expect
      if grep -q '"@playwright/test"' <<<"$pkg"; then
        eslint_rule js playwright eslint-plugin-playwright playwright/missing-playwright-await
        eslint_rule js playwright eslint-plugin-playwright playwright/no-focused-test
      fi
      ;;
    cs)
      grep -Eqi 'Include="xunit' <<<"$cs" && dotnet_rule xUnit2021 xunit.analyzers 'xunit|xunit\.v3'
      grep -Eqi 'Include="NUnit"' <<<"$cs" && dotnet_rule NUnit2009 NUnit.Analyzers NUnit.Analyzers
      ;;
    python)
      # shellcheck disable=SC2143 # grep -q would SIGPIPE lint_text under pipefail
      if [[ -z "$(lint_text pyproject.toml ruff.toml .ruff.toml | grep -E '^\[(tool\.)?ruff|^(extend-)?select|^\[lint')" ]]; then
        report python ruff FINDING "no ruff config found; configure ruff with PLR0124, PT011 and F631"
      else
        ruff_rule PLR0124 1
        ruff_rule PT011 0
        ruff_rule F631 1
      fi
      ;;
    bash | pwsh | go) report "$l" "-" NONE "no maintained rule" ;;
    *) ;;
    esac
  done

  printf '\n== instruction ==\n'
  printf 'Optional. To paste into CLAUDE.md or AGENTS.md yourself; /testing:setup never edits them:\n'
  printf '  Tests must be able to fail: take every expected value from a spec, a bug report or a hand-computed literal, never from running the code under test; load the testing:test-value skill before writing or reviewing tests.\n'

  printf '\n== hook-entry ==\n'
  local globs=() g
  while IFS=$'\t' read -r key val; do [[ "$key" == hook.uncovered ]] && globs+=("$val"); done <<<"$cfg"
  if [[ ${#globs[@]} -eq 0 ]]; then
    printf 'none: every consumer test glob is covered by a shipped test-scan hook row\n'
  else
    printf 'The test-scan hook skips %s. Add this PostToolUse entry to .claude/settings.json to cover them;\n' "${globs[*]}"
    printf 'a settings hook gets no plugin variables, so it runs the highest installed version and passes --enabled;\n'
    printf 'with no installed copy that takes --enabled it says so on stderr and exits 0.\n'
    # Pinned to the marketplace this copy runs from, so another marketplace's
    # plugin named testing is never picked.
    local mkt='<marketplace>' rest="${PLUGIN#*/.claude/plugins/cache/}"
    # The name is spliced into shell code, so only a plain name is.
    if [[ "$rest" != "$PLUGIN" && "$rest" == */testing/* && "${rest%%/*}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
      mkt="${rest%%/*}"
    else
      printf 'This copy is not in the plugin cache under a plain marketplace name, so replace <marketplace> with the marketplace the testing plugin is installed from.\n'
    fi
    # shellcheck disable=SC2016 # the command is for the hook's shell, not this one
    local cmd='p=$(ls -d "$HOME/.claude/plugins/cache/'"$mkt"'"/testing/*/hooks/test-scan.sh 2>/dev/null | awk -F/ '"'"'{split($(NF-2),v,".");k=sprintf("%09d%09d%09d",v[1],v[2],v[3]);if(k>m){m=k;p=$0}}END{print p}'"'"'); if [ -n "$p" ] && grep -q -e --enabled "$p"; then exec bash "$p" --enabled; fi; echo "testing: no installed test-scan.sh under ~/.claude/plugins/cache/'"$mkt"'/testing takes --enabled; this settings hook did nothing" >&2'
    {
      for g in "${globs[@]}"; do
        jq -n --arg g "$g" --arg c "$cmd" '("Write", "Edit") | {type: "command", command: $c, if: "\(.)(\($g))", timeout: 10}'
      done
    } | jq -s '{hooks: {PostToolUse: [{matcher: "Write|Edit", hooks: .}]}}'
  fi
  ((findings == 0)) || return 1
}

case "$ACTION" in
check) check ;;
apply) apply ;;
*) die "usage: setup.sh check|apply [--root <dir>] (see the header)" ;;
esac
