#!/usr/bin/env bash
# Portability-lint gate: skills declared ecosystem/forge/tracker-agnostic must
# not ship bare hardcoded stack/forge/branch/tracker defaults. The agnosticism
# contract lives in docs/PLUGIN-PHILOSOPHY.md (Design boundary,
# Two-lane convention posture, Cross-platform contract's declared-narrower-scope
# allowance); prose states it but cannot self-verify, so this gate turns the
# assertion into a mechanical check.
#
#   scripts/check-skill-portability.sh <base-ref>   gate skill files a PR changed
#   scripts/check-skill-portability.sh --all         audit every skill file
#   scripts/check-skill-portability.sh --paths F...   scan exactly these files
#
# WHAT is detected is data, not logic: the coupling tokens live in
# scripts/skill-portability-tokens.txt (override with SKILL_PORTABILITY_TOKENS),
# one ERE pattern per active line, so a reviewer re-catch is a one-line data edit
# and rollout stages one token-class at a time. HOW a legitimate hit is excused
# is this script's job.
#
# Scope declaration, resolved per the ratified declaration-first plan: no new
# frontmatter field. A skill is agnostic by default — the Design boundary already
# binds every plugin — so the gated set is "the skill files a change touches",
# exactly as the skill-quality gate scopes itself. A skill with an inherent,
# declared narrower scope (a genuinely forge- or ecosystem-locked capability
# under a neutral name) opts out with a reviewer-visible comment, reusing the
# annotated-exemption shape the silent-skip gate established rather than inventing
# a declaration mechanism.
#
# Changed-FILE (not whole-skill-dir) scoping keeps a PR responsible only for the
# files it actually edits, so enabling a token class never red-lines main: main's
# push event scans nothing (the self-test is the push path), and existing
# violations wait for the owning follow-up fix or the file's next edit.
#
# A token hit fails UNLESS one of three reviewer-visible escapes applies:
#   1. detection-first / presence-gated use — auto-recognized guard markers on
#      the hit line (an `origin/HEAD` / symbolic-ref / merge-base ladder that
#      falls back to origin/main is the CORRECT pattern, not a bare assumption);
#   2. a per-site recorded exemption `portability-ok: <reason>` on the hit line
#      or in the contiguous comment block directly above it;
#   3. a whole-file `portability-scope: <reason>` declaration anywhere in the
#      file (the inherent, declared narrower boundary).
#
# This is a grep-level tripwire, not a semantic proof. Guard markers are seeded
# for the one active class (branch/default-branch); enabling a further class
# revisits them here, proven against an `--all` audit first.
#
# Files scanned within a changed skill: *.md and *.sh, excluding *.test.sh (test
# fixtures), vendor/ (upstream-synced copies with their own drift gate), and
# evals/ (eval fixtures carry adversarial example prompts by design).
#
# Exit 0 = clean (or nothing in scope); 1 = one or more violations; 2 = usage /
# environment error (fail closed — never a silent skip).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

TOKENS="${SKILL_PORTABILITY_TOKENS:-scripts/skill-portability-tokens.txt}"
if [[ ! -f "$TOKENS" ]]; then
  printf 'Error: token list not found: %s\n' "$TOKENS" >&2
  exit 2
fi

usage() {
  printf 'usage: check-skill-portability.sh <base-ref> | --all | --paths FILE...\n' >&2
  exit 2
}

# is_scannable <path> — a skill file the gate authors are responsible for.
is_scannable() {
  local f="$1"
  case "$f" in
  */vendor/* | */evals/*) return 1 ;;
  *.test.sh) return 1 ;;
  *.md | *.sh) return 0 ;;
  *) return 1 ;;
  esac
}

# Resolve the file set for the requested mode.
files=()
if (($# == 0)); then
  usage
fi

mode="$1"
case "$mode" in
--all)
  shift
  (($# == 0)) || usage
  while IFS= read -r f; do
    is_scannable "$f" && files+=("$f")
  done < <(find plugins -type f -path 'plugins/*/skills/*' \( -name '*.md' -o -name '*.sh' \) | sort)
  ;;
--paths)
  shift
  (($# > 0)) || usage
  files=("$@")
  ;;
-*)
  usage
  ;;
*)
  # Changed-file mode: <base-ref>.
  base="$mode"
  shift
  (($# == 0)) || usage
  if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
    printf 'Error: base ref %s is not a valid commit\n' "$base" >&2
    exit 2
  fi
  # Diff on plugins/ then filter the skill path in-script: a `plugins/*/skills/`
  # git pathspec does not match under git's default (non-pathname) globbing.
  while IFS= read -r f; do
    case "$f" in
    plugins/*/skills/*) ;;
    *) continue ;;
    esac
    is_scannable "$f" || continue
    [[ -f "$f" ]] || continue # a rename-away/deletion leaves nothing to scan
    files+=("$f")
  done < <(git diff --name-only --diff-filter=d "$base" -- 'plugins/' | sort -u)
  ;;
esac

if ((${#files[@]} == 0)); then
  echo "No skill files in scope — nothing to gate."
  exit 0
fi

# scan_file <path> — print `LINE: token -> text` for each unexcused hit.
scan_file() {
  local file="$1"
  # A whole-file declared narrower scope (the inherent-boundary case) excuses
  # every hit in the file; the declaration is visible in the diff.
  if grep -qE 'portability-scope:' -- "$file"; then
    return 0
  fi
  awk '
    function is_annotated(l) { return l ~ /portability-ok:/ }
    function is_comment(l) { return l ~ /^[[:space:]]*#/ || l ~ /<!--/ }
    # Guard markers for the active branch class: a detection-first ladder or a
    # presence-gated use, which is the correct pattern, not a bare assumption.
    function is_guarded(l) {
      return l ~ /origin\/HEAD/ || l ~ /symbolic-ref/ || l ~ /merge-base/ ||
        l ~ /baseRefName/ || l ~ /[Ff]allback/ || l ~ /[Ff]alling back/ ||
        l ~ /-> *origin\// || l ~ /if installed/ || l ~ /if using/ ||
        l ~ /when installed/ || l ~ /when present/
    }
    # Pass 1: collect active ERE patterns from the token list.
    FNR == NR {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^#/) next
      patterns[++np] = line
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
          if (is_guarded(line)) continue
          printf "%d: %s -> %s\n", FNR, patterns[i], line
        }
      }
    }
  ' "$TOKENS" "$file"
}

violations=0
for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'Error: no such file: %s\n' "$file" >&2
    exit 2
  fi
  out="$(scan_file "$file")"
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
    echo "use is legitimate — make it detection-first/presence-gated, add a"
    echo "'portability-ok: <reason>' comment at the site, or declare an inherent"
    echo "narrower scope with 'portability-scope: <reason>' in the file."
  } >&2
  exit 1
fi
echo "No unexcused coupling tokens in ${#files[@]} skill file(s)."
