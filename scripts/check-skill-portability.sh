#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2
# shellcheck source=lib/token-scan.sh
. "$SCRIPT_DIR/lib/token-scan.sh" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

TOKENS_SRC="${SKILL_PORTABILITY_TOKENS:-scripts/skill-portability-tokens.txt}"
# shellcheck disable=SC2034 # TOKENS_ACTIVE is set by load_active and read by its EXIT trap
TOKENS_ACTIVE='' TOKENS=''
token_scan::load_active "$TOKENS_SRC" TOKENS_ACTIVE TOKENS || exit 2

usage() {
  printf 'usage: check-skill-portability.sh <base-ref> | --all | --paths FILE...\n' >&2
  exit 2
}

is_scannable() {
  local f="$1"
  case "$f" in
  */vendor/* | */evals/*) return 1 ;;
  *.test.sh) return 1 ;;
  *.md | *.sh) return 0 ;;
  *) return 1 ;;
  esac
}

files=()
if ! gate_entry::classify "$@"; then
  usage
fi

case "$GE_MODE" in
all)
  while IFS= read -r f; do
    is_scannable "$f" && files+=("$f")
  done < <(find plugins -type f -path 'plugins/*/skills/*' \( -name '*.md' -o -name '*.sh' \) | sort)
  ;;
paths)
  files=("${GE_PATHS[@]}")
  ;;
base)
  changed=()
  gate_entry::collect_changed changed "$GE_REF" -- 'plugins/'
  for f in ${changed[@]+"${changed[@]}"}; do
    case "$f" in
    plugins/*/skills/*) ;;
    *) continue ;;
    esac
    is_scannable "$f" || continue
    [[ -f "$f" ]] || continue
    files+=("$f")
  done
  ;;
*)
  printf 'Error: unrecognized gate mode: %s\n' "$GE_MODE" >&2
  gate_entry::finish 2
  ;;
esac

if ((${#files[@]} == 0)); then
  echo "No skill files in scope — nothing to gate."
  gate_entry::finish 0
fi

scan_file() {
  local file="$1"
  if grep -qE '^[[:space:]]*(#|((>|[-*+]|[0-9]+[.)])[[:space:]]+)*<!--)[[:space:]]*portability-scope:' -- "$file"; then
    return 0
  fi
  local awk_file
  # awk reads an operand shaped name=value as an assignment, not a file:
  # https://pubs.opengroup.org/onlinepubs/9799919799/utilities/awk.html
  awk_file="$(token_scan::awk_operand "$file")"
  awk '
    function is_annotated(l) { return l ~ /portability-ok:[[:space:]]*[^[:space:]#<\-]/ }
    # Block-level only: a content line that merely happens to carry an inline
    # HTML comment marker (e.g. prose with `<!-- note -->` mid-line) must NOT
    # count as a comment line for pending_annot carry-forward purposes — only a
    # line whose `<!--` opens at the start (after optional whitespace) is a
    # genuine dedicated comment line. See #611.
    #
    # A block comment nested inside Markdown list/blockquote containers
    # (`- <!--`, `> <!--`, `1. <!--`, nested combinations like `> - <!--`)
    # still qualifies: the opener is the first content of its container, so the
    # line is dedicated to the comment. Each container marker must be followed
    # by whitespace, which keeps the #611 mid-sentence shape (any real prose
    # before the `<!--`) rejected. See #1342.
    function is_comment(l) {
      return l ~ /^[[:space:]]*#/ ||
        l ~ /^[[:space:]]*((>|[-*+]|[0-9]+[.)])[[:space:]]+)*<!--/
    }
    # Guard markers for the active branch class: branch-detection evidence ONLY
    # — a symbolic-ref / merge-base / origin/HEAD / PR-baseRefName resolution
    # command (or a `-> origin/` symbolic-ref target) co-located on the hit line.
    # The resolution command IS the evidence; prose alone is not. So the bare
    # word "fallback" / "falling back" is NOT a marker (an unrelated "as a
    # fallback, run git diff origin/main" imposes main with no resolution
    # evidence), nor is optional-dependency presence prose ("if using",
    # "when present"). A bare default whose resolution evidence is not
    # co-located on the line must flag — a reviewer cannot see it is guarded
    # either; a legitimately split-across-lines ladder uses the per-site
    # portability-ok escape. A future class needing other markers adds them
    # here when it is enabled.
    #
    # Takes the matched PATTERN too, so a marker guards only the class that
    # authored it — the same is_guarded(l, p) shape check-shell-portability.sh
    # already uses. Without that scoping every marker is global, and the first
    # additional class to go active inherits branch-detection evidence as a
    # blanket excuse: `git ls-remote --symref origin HEAD` resolving the
    # default branch would also excuse a bare `git push origin` on the same
    # line, which is a different coupling with different resolution evidence
    # (branch.<name>.remote / @{upstream}). That is the false green the token
    # file staged-class preamble forbids, so the scoping lands with the class
    # set that made it reachable rather than with the class that trips over it.
    #
    # Stack/ecosystem class (#714, Stage 3) markers are CONSUMER-SEAM evidence:
    # the ecosystem has to come from the consuming project, not from the skill.
    # Two shapes qualify, both co-located on the hit line so a reviewer sees the
    # evidence in the diff:
    #   1. a userConfig read (`${user_config.<key>}`) — the consumer supplies
    #      the stack, which is the seam this class exists to force. Anchored to
    #      the read syntax, not the bare word: prose ABOUT a userConfig seam is
    #      not a seam. Scoped to the ecosystem LITERALS; the architecture token
    #      takes shape (2) alone, for the reason recorded at
    #      is_architecture_pattern below.
    #   2. a neutral `<placeholder>` AND an explicit illustration lead (`e.g.`,
    #      `for example`, `such as`). The portable idiom already used across
    #      this corpus is a placeholder followed by a multi-ecosystem example
    #      run — `<build-command>  # e.g. dotnet build / npm run build / cargo
    #      build` — where the ecosystem token illustrates the placeholder
    #      instead of being the value the skill ships.
    # BOTH halves of (2) are required, and that is the whole guard. A
    # placeholder alone would excuse `run dotnet build in <repo-root>`, which
    # ships the stack and merely parameterizes the path; an illustration lead
    # alone would excuse `e.g. run dotnet build`, the bare hardcode wearing a
    # hedge. That generic hedge is exactly what the token file staged-class
    # preamble forbids as a guard, so neither half is admitted on its own.
    #
    # Deliberately NOT a marker: "another ecosystem is named on the same line".
    # A multi-ecosystem enumeration with no placeholder and no illustration lead
    # (`.csproj`, `package.json`, `pyproject.toml`, and equivalents) is the
    # dominant residual shape in the corpus and reads as correct, but a
    # co-occurrence test cannot tell it from a line that hardcodes one stack and
    # merely mentions another. It uses the per-site portability-ok escape until
    # someone brings evidence for a tighter rule.
    #
    # Class membership is tested with index() on literal fragments, never with a
    # regex match against the pattern text. The argument here is a PATTERN, so a
    # regex test reads its metacharacters as syntax: `p ~ /[Dd]otnet/` asks for a
    # D-or-d followed by "otnet" and therefore does NOT match the pattern STRING
    # `[Dd]otnet`, whose `d` is followed by `]otnet`. That silently returns 0 for
    # every member and the whole class goes unguarded while the tests that only
    # check flagging still pass. The branch class above escapes its
    # metacharacters for the same reason; index() removes the trap instead of
    # re-solving it per pattern. Fragments are chosen to be metacharacter-free in
    # the pattern text, so each one survives however its pattern is escaped.
    #
    # A fragment also has to be UNIQUE to its pattern, not merely present in it.
    # `\.NET` is the literal as the staged pattern spells it; a bare `NET` is a
    # substring of `NETRC`, `CONNECT`, and `INTERNET`, so a future token class
    # carrying that trigram would silently inherit the consumer-seam guard of
    # this class, and a real violation of it could be excused by an unrelated
    # userConfig read. assert_staged pins the pattern spelling verbatim, so the
    # fragment and the pattern it selects cannot drift apart.
    function is_ecosystem_pattern(p) {
      return index(p, "otnet") || index(p, "\\.NET") ||
        index(p, "csproj") || index(p, "sln") || index(p, "razor") ||
        index(p, "lazor") || index(p, "C#") || index(p, ".cs(")
    }
    # Architecture vocabulary is guarded by the illustration shape ALONE — never
    # by a userConfig read. The token file entry for it names exactly two
    # escapes, a `portability-scope` declaration and the
    # placeholder-plus-illustration shape, and a userConfig read is neither: the
    # class-wide marker reaching this token was an accident of class membership.
    # It excused an architecture hardcode whenever ANY unrelated setting was read
    # on the line — `Read ${user_config.test_command}, then place handlers per
    # Clean Architecture` — a false green on the one token in this class that is
    # ACTIVE. Evidence has to parameterize the coupling it excuses, and no
    # userConfig KEY NAME can be trusted to prove that for an architecture.
    function is_architecture_pattern(p) { return index(p, "Clean Arch") }
    # Shared by both branches so the two cannot drift apart. The placeholder is
    # lowercase-hyphenated by corpus convention, which includes single-letter CLI
    # operands (`<n>`, `<s>`); uppercase `<SCREAMING-CASE>` is deliberately not
    # accepted, because nothing in this corpus uses it and admitting it would
    # widen the guard past every shape under test.
    #
    # KNOWN RESIDUAL, admitted deliberately: inline HTML shares this spelling
    # space, so `See the <a> docs, e.g. run dotnet build` satisfies both halves
    # with no real seam. One line of text cannot separate the two here — `<b>`,
    # `<i>`, `<p>`, `<s>`, and `<n>` are all genuine CLI operands in this corpus,
    # so a minimum length rejects real placeholders, and a tag denylist
    # enumerates instances of an open-ended shape while leaving `<var>` or any
    # invented token. This is the same limit the token file records for the
    # multi-ecosystem enumeration, and it takes the same remedy — a per-site
    # portability-ok — until someone brings evidence for a tighter rule.
    function is_illustrated_placeholder(l) {
      return l ~ /<[a-z][a-z0-9-]*>/ && l ~ /(e\.g\.|for example|such as)/
    }
    function is_guarded(l, p) {
      if (p ~ /origin\/\(main\|master\)/) {
        return l ~ /origin\/HEAD/ || l ~ /symbolic-ref/ || l ~ /merge-base/ ||
          l ~ /baseRefName/ || l ~ /-> *origin\//
      }
      if (is_architecture_pattern(p)) {
        return is_illustrated_placeholder(l)
      }
      if (is_ecosystem_pattern(p)) {
        return l ~ /[$]\{user_config\./ || is_illustrated_placeholder(l)
      }
      return 0
    }
    # Pass 1: load the token list. It arrives PRE-FILTERED — trimmed, no blanks,
    # no comment lines — because scripts/lib/read-list.sh resolved it in the
    # shell (#3161). Stripping here too would re-create the private copy of the
    # comment rule that extraction removed, and would apply the wrong one: an
    # inline `#` is DATA in an ERE.
    FNR == NR {
      patterns[++np] = $0
      next
    }
    # Pass 2: scan the target file.
    {
      line = $0
      annotated_above = pending_annot
      if (is_comment(line)) {
        if (is_annotated(line)) pending_annot = 1
      } else {
        pending_annot = 0
      }
      for (i = 1; i <= np; i++) {
        if (line ~ patterns[i]) {
          if (is_annotated(line) || annotated_above) continue
          if (is_guarded(line, patterns[i])) continue
          printf "%d: %s -> %s\n", FNR, patterns[i], line
        }
      }
    }
  ' "$TOKENS" "$awk_file"
}

violations=0
for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'Error: no such file: %s\n' "$file" >&2
    exit 2
  fi
  out="$(scan_file "$file")" || {
    printf 'Error: gate scanner failed on %s — failing closed\n' "$file" >&2
    exit 2
  }
  if [[ -n "$out" ]]; then
    while IFS= read -r v; do
      echo "COUPLING: ${file}:${v}" >&2
      violations=$((violations + 1))
    done <<<"$out"
  fi
done

if ((violations > 0)); then
  {
    echo
    echo "A skill declared ecosystem/forge/tracker-agnostic must not hardcode a"
    echo "stack/forge/branch/tracker default. Resolve the coupling, or — when the"
    echo "use is legitimate — co-locate the branch-resolution command on the"
    echo "line (detection-first), add a"
    echo "'portability-ok: <reason>' comment at the site, or declare an inherent"
    echo "narrower scope with 'portability-scope: <reason>' in the file."
  } >&2
  gate_entry::finish 1
fi
echo "No unexcused coupling tokens in ${#files[@]} skill file(s)."
gate_entry::finish 0
