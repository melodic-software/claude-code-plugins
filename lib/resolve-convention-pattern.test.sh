#!/usr/bin/env bash
# Regression tests for lib/resolve-convention-pattern.sh — the shared commit/PR
# convention ENFORCEMENT-pattern resolver. Run: bash lib/resolve-convention-pattern.test.sh
# The resolver is POSIX sh: the cases run it under dash where installed, else
# sh, and one runs it under bash too.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resolve-convention-pattern.sh"
if SH="$(command -v dash)"; then
  echo "running the resolver under $SH"
else
  SH="sh"
  echo "note: dash is not on PATH, so the resolver runs under sh"
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}

# The canonical Conventional Commits ERE — kept in lockstep with the SUT header.
CC_ERE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'

TEAM_YAML="docs/conventions/source-control.yaml"
WELL_KNOWN="docs/conventions/source-control/commit-convention.yml"

# addfile <repo> <repo-relative path> <body>: write a file inside the repo.
addfile() {
  local d="$1" path="$2" body="$3"
  mkdir -p "$d/$(dirname "$path")"
  printf '%s\n' "$body" >"$d/$path"
}
# Both team files count only while git tracks them, so a case stages each one.
track() {
  git -C "$1" add -- "$2" 2>/dev/null || true
}
# newrepo [team yaml body]: an isolated git repo; a body becomes the tracked
# team file.
newrepo() {
  local d
  d="$(mktemp -d "$TEST_TMPDIR/repo.XXXXXX")"
  git -C "$d" init -q 2>/dev/null || true
  if [[ -n "${1:-}" ]]; then
    addfile "$d" "$TEAM_YAML" "$1"
    track "$d" "$TEAM_YAML"
  fi
  printf '%s' "$d"
}
# addyaml <repo> <body>: write the team file into an existing repo and track it.
addyaml() {
  addfile "$1" "$TEAM_YAML" "$2"
  track "$1" "$TEAM_YAML"
}
# addfolder <repo> <body>: write the folder-form file and track it.
addfolder() {
  addfile "$1" "$WELL_KNOWN" "$2"
  track "$1" "$WELL_KNOWN"
}
# sp <pattern>: a single-quoted subject_pattern line, the pattern as written.
sp() { printf "subject_pattern: '%s'" "$1"; }
run() { "$SH" "$SCRIPT" "$1" "${2:-subject_pattern}"; }
layer() { "$SH" "$SCRIPT" --layer "$1" "${2:-subject_pattern}"; }

# --- --help ---
out="$("$SH" "$SCRIPT" --help)"
assert_exit "--help exits 0" 0 $?
assert_eq "--help prints the header, not the linter directive" "yes|no" \
  "$(grep -q '^Usage:' <<<"$out" && echo yes || echo no)|$(grep -q 'shellcheck' <<<"$out" && echo yes || echo no)"

# --- Conventional Commits keyword expands to the canonical ERE ---
r="$(newrepo 'subject_pattern: Conventional Commits')"
assert_eq "CC keyword -> CC_ERE" "$CC_ERE" "$(run "$r")"
assert_eq "bash resolves it the same" "$CC_ERE" "$(bash "$SCRIPT" "$r" subject_pattern)"

# --- a comment header above the keys is inert ---
r="$(newrepo $'# source-control configuration\n#\n# Read by the source-control Claude Code plugin and the guardrails gate.\n\nsubject_pattern: Conventional Commits')"
assert_eq "comment header above the keys is inert" "$CC_ERE" "$(run "$r")"

# --- a custom ERE passes through unchanged ---
r="$(newrepo "$(sp '^[A-Z]+-[0-9]+: .+')")"
assert_eq "plain ERE unchanged" '^[A-Z]+-[0-9]+: .+' "$(run "$r")"

# --- an already-alternated ERE passes through unchanged ---
r="$(newrepo "$(sp '^(feat|fix): .+')")"
assert_eq "ERE alternation unchanged" '^(feat|fix): .+' "$(run "$r")"

# --- PCRE-only constructs are NOT translated -> no enforcement ---
# The resolver accepts POSIX ERE and rejects PCRE; a team writes [0-9] not \d.
#
# Every `\w`, `\s` and `\b` from here down is TEST DATA: a PCRE token written
# into a fixture config file and handed to the resolver so the case can assert
# the resolver REJECTS it. None is a pattern this suite passes to grep or sed, so
# none can behave differently on a BSD userland — and the shorthand cannot be
# spelled away, because the shorthand is the thing under test. Each hit carries
# its own `portability-ok:` marker rather than a whole-file declaration: the
# whole-file escape is reserved for the portability gate's own fixture corpus,
# and this file is the convention resolver's.
r="$(newrepo "$(sp '^(?:feat|fix): .+')")"
run "$r" >/dev/null 2>&1
assert_exit "(?: non-capturing group -> exit 1" 1 $?
r="$(newrepo "$(sp '^[A-Z]+-\d+: .+')")"
run "$r" >/dev/null 2>&1
assert_exit "\\d -> exit 1 (use [0-9])" 1 $?
r="$(newrepo "$(sp '^\w+\s: .+')")" # portability-ok: PCRE shorthand as fixture data
run "$r" >/dev/null 2>&1
assert_exit "\\w \\s -> exit 1" 1 $? # portability-ok: PCRE shorthand named in an assertion label

# --- lookahead has no ERE equivalent -> no enforcement, exit 1, empty stdout ---
r="$(newrepo "$(sp '^(?=.{1,50}$)\w+: .+')")" # portability-ok: PCRE shorthand as fixture data
out="$(run "$r")"
rc=$?
assert_exit "lookaround -> exit 1" 1 "$rc"
assert_eq "lookaround -> empty stdout" "" "$out"

# --- word-boundary \b is non-ERE -> no enforcement ---
r="$(newrepo "$(sp '^\bfeat: .+')")" # portability-ok: PCRE word boundary as fixture data
run "$r" >/dev/null 2>&1
assert_exit "\\b -> exit 1" 1 $? # portability-ok: PCRE word boundary named in an assertion label

# --- backreference is non-ERE -> no enforcement ---
r="$(newrepo "$(sp '^(\w+): \1')")" # portability-ok: PCRE shorthand as fixture data
run "$r" >/dev/null 2>&1
assert_exit "backref -> exit 1" 1 $?

# --- negated shorthand classes (\D \S \W) have no ERE spelling -> no enforce ---
r="$(newrepo "$(sp '^\D+: .+')")"
run "$r" >/dev/null 2>&1
assert_exit "\\D -> exit 1" 1 $?

# --- absolute anchors (\A \z \Z) are non-ERE -> no enforcement ---
r="$(newrepo "$(sp '\Afeat: .+\z')")"
run "$r" >/dev/null 2>&1
assert_exit "\\A \\z -> exit 1" 1 $?

# --- control-char escapes (\t \n ...) are non-ERE -> no enforcement ---
r="$(newrepo "$(sp '^\tJIRA-[0-9]+: .+')")"
run "$r" >/dev/null 2>&1
assert_exit "\\t -> exit 1" 1 $?

# --- an escaped backslash (\\d = literal, not the class) -> no enforcement ---
r="$(newrepo "$(sp '^foo\\d: .+')")"
run "$r" >/dev/null 2>&1
assert_exit "escaped backslash -> exit 1" 1 $?

# --- a \d/\w/\s shorthand INSIDE a bracket expression -> no enforcement ---
r="$(newrepo "$(sp '^[\w-]+: .+')")" # portability-ok: PCRE shorthand as fixture data
run "$r" >/dev/null 2>&1
assert_exit "shorthand inside bracket -> exit 1" 1 $?

# --- a pattern that does not compile as POSIX ERE -> no enforcement (net) ---
r="$(newrepo "$(sp '^[: .+')")"
out="$(run "$r")"
rc=$?
assert_exit "uncompilable ERE -> exit 1" 1 "$rc"
assert_eq "uncompilable ERE -> empty stdout" "" "$out"

# --- unresolved: no team file at all -> exit 1, NEVER the CC default ---
r="$(newrepo "")"
out="$(run "$r")"
rc=$?
assert_exit "no team file -> exit 1" 1 "$rc"
assert_eq "no team file -> empty (no CC fallback)" "" "$out"

# --- unresolved: file exists but key absent -> exit 1 ---
r="$(newrepo 'trailer_policy: none')"
run "$r" >/dev/null 2>&1
assert_exit "key absent -> exit 1" 1 $?

# --- pr_title_pattern deferral resolves the effective subject pattern ---
r="$(newrepo "$(sp '^ABC-[0-9]+: .+')"$'\npr_title_pattern: "Same as `subject_pattern`."')"
assert_eq "pr deferral -> subject" '^ABC-[0-9]+: .+' "$(run "$r" pr_title_pattern)"

# --- pr_title_pattern with its own value stands alone ---
r="$(newrepo "$(sp '^X: .+')"$'\npr_title_pattern: \047^PR: .+\047')"
assert_eq "pr explicit value" '^PR: .+' "$(run "$r" pr_title_pattern)"

# --- the retired markdown team file is not read ---
# Neither its `## <key>` H2 nor a `## convention_source` pointer enforces
# anything, even while git tracks the file and the file it points at.
r="$(newrepo "")"
addfile "$r" ".claude/source-control.md" $'## convention_source\nconventions.yml\n\n## subject_pattern\n^MD-[0-9]+: .+\n\n## pr_title_pattern\n^MDPR: .+'
addfile "$r" "conventions.yml" "$(sp '^POINTED-[0-9]+: .+')"
track "$r" ".claude/source-control.md"
track "$r" "conventions.yml"
out="$(run "$r" 2>"$TEST_TMPDIR/md.err")"
rc=$?
assert_eq "markdown: a tracked H2 and pointer are not enforced -> exit 1, silent" "1||" \
  "$rc|$out|$(<"$TEST_TMPDIR/md.err")"
run "$r" pr_title_pattern >/dev/null 2>&1
assert_exit "markdown: a tracked pr_title_pattern H2 is not enforced" 1 $?

# =====================================================================
# The folder-form file (docs/conventions/source-control/commit-convention.yml):
# flat-scalar YAML, read for a key the team file lacks, only while git
# tracks it.
# =====================================================================

# --- single-quoted YAML value resolves ---
r="$(newrepo "")"
addfolder "$r" $'# team commit convention\n'"$(sp '^SW2-[0-9]+: .+')"
assert_eq "folder form: quoted YAML subject" '^SW2-[0-9]+: .+' "$(run "$r")"
assert_eq "folder form: --layer names the folder form" "$WELL_KNOWN" "$(layer "$r")"

# --- double-quoted YAML value strips its quotes too ---
r="$(newrepo "")"
addfolder "$r" $'subject_pattern: "^DQ-[0-9]+: .+"'
assert_eq "folder form: double-quoted value" '^DQ-[0-9]+: .+' "$(run "$r")"

# --- unquoted YAML value passes through ---
r="$(newrepo "")"
addfolder "$r" $'subject_pattern: ^plain: .+'
assert_eq "folder form: unquoted value" '^plain: .+' "$(run "$r")"

# --- CC keyword works in the folder form exactly as in the team file ---
r="$(newrepo "")"
addfolder "$r" $'subject_pattern: Conventional Commits'
assert_eq "folder form: CC keyword -> CC_ERE" "$CC_ERE" "$(run "$r")"

# --- pr_title deferral marker works in the folder form ---
r="$(newrepo "")"
addfolder "$r" "$(sp '^N-[0-9]+: .+')"$'\npr_title_pattern: Same as `subject_pattern`.'
assert_eq "folder form: pr deferral -> subject" '^N-[0-9]+: .+' "$(run "$r" pr_title_pattern)"

# --- a key the folder form omits is unset -> no enforcement ---
r="$(newrepo "")"
addfolder "$r" "$(sp '^Y-[0-9]+: .+')"
run "$r" pr_title_pattern >/dev/null 2>&1
assert_exit "folder form: omitted key -> exit 1" 1 $?

# --- dialect: posix-ere (explicit) still resolves ---
r="$(newrepo "")"
addfolder "$r" $'dialect: posix-ere\n'"$(sp '^D-[0-9]+: .+')"
assert_eq "folder form: dialect posix-ere ok" '^D-[0-9]+: .+' "$(run "$r")"

# --- dialect other than posix-ere -> no enforcement ---
r="$(newrepo "")"
addfolder "$r" $'dialect: pcre\n'"$(sp '^\d+: .+')"
out="$(run "$r")"
rc=$?
assert_exit "folder form: dialect pcre -> exit 1" 1 "$rc"
assert_eq "folder form: dialect pcre -> empty stdout" "" "$out"

# --- comment and blank lines in the folder form are inert ---
r="$(newrepo "")"
addfolder "$r" $'# convention SSOT\n\n# see CONTRIBUTING.md\n'"$(sp '^C-[0-9]+: .+')"
assert_eq "folder form: comments/blanks inert" '^C-[0-9]+: .+' "$(run "$r")"

# --- CRLF line endings: each value loses its CR, the dialect and deferral included ---
r="$(newrepo "")"
addfolder "$r" $'dialect: posix-ere\r\nsubject_pattern: \047^CR-[0-9]+: .+\047\r\npr_title_pattern: Same as `subject_pattern`.\r'
assert_eq "folder form: CRLF subject" '^CR-[0-9]+: .+' "$(run "$r")"
assert_eq "folder form: CRLF pr deferral -> subject" '^CR-[0-9]+: .+' "$(run "$r" pr_title_pattern)"
r="$(newrepo "")"
addfolder "$r" $'subject_pattern: \047\047\r'
run "$r" >/dev/null 2>&1
assert_exit "folder form: CRLF empty key -> exit 1" 1 $?

# --- the first line carrying a key wins; an indented key is not a key ---
r="$(newrepo "")"
addfolder "$r" $'  subject_pattern: \047^indented: .+\047\nsubject_pattern: \047^first: .+\047\nsubject_pattern: \047^second: .+\047'
assert_eq "folder form: first key line wins, indented ignored" '^first: .+' "$(run "$r")"
r="$(newrepo "")"
addfolder "$r" $'subject_pattern:\nsubject_pattern: \047^later: .+\047'
run "$r" >/dev/null 2>&1
assert_exit "folder form: empty first key line fails closed despite a later value" 1 $?

# --- a final line with no newline is still read ---
r="$(newrepo "")"
mkdir -p "$r/$(dirname "$WELL_KNOWN")"
printf '%s' "subject_pattern: '^NONL: .+'" >"$r/$WELL_KNOWN"
track "$r" "$WELL_KNOWN"
assert_eq "folder form: final line without newline" '^NONL: .+' "$(run "$r")"

# --- an unreadable folder form says so on stderr (skipped where it stays readable, as root) ---
r="$(newrepo "")"
addfolder "$r" "$(sp '^U-[0-9]+: .+')"
chmod 000 "$r/$WELL_KNOWN"
if [[ -r "$r/$WELL_KNOWN" ]]; then
  echo "SKIP: unreadable folder-form case (the file stays readable to this user)"
else
  err="$(run "$r" 2>&1 >/dev/null)"
  rc=$?
  assert_exit "folder form: unreadable file -> exit 1" 1 "$rc"
  assert_eq "folder form: unreadable file -> stderr diagnostic" "yes" \
    "$([[ "$err" == *"cannot read $WELL_KNOWN"* ]] && echo yes || echo no)"
fi
chmod 644 "$r/$WELL_KNOWN"

# --- a present-but-EMPTY folder-form key fails closed ---
r="$(newrepo "")"
addfolder "$r" $'subject_pattern: \047\047'
out="$(run "$r")"
rc=$?
assert_exit "folder form: empty quoted key -> exit 1" 1 "$rc"
assert_eq "folder form: empty quoted key -> empty stdout" "" "$out"
r="$(newrepo "")"
addfolder "$r" $'subject_pattern:'
run "$r" >/dev/null 2>&1
assert_exit "folder form: bare empty key -> exit 1" 1 $?

# --- POLICY FLOOR: an untracked folder form is not a layer ---
r="$(newrepo "")"
addfile "$r" "$WELL_KNOWN" "$(sp '^untracked: .+')"
out="$(run "$r" 2>"$TEST_TMPDIR/untracked.err")"
rc=$?
assert_eq "folder form: an untracked file -> exit 1, silent" "1||" "$rc|$out|$(<"$TEST_TMPDIR/untracked.err")"

# --- symlink escapes are rejected (skipped where ln -s can't make symlinks) ---
outside="$TEST_TMPDIR/outside.yml"
printf '%s\n' "subject_pattern: '^outside: .+'" >"$outside"
r="$(newrepo "")"
mkdir -p "$r/$(dirname "$WELL_KNOWN")"
ln -s "$outside" "$r/$WELL_KNOWN" 2>/dev/null
if [[ -L "$r/$WELL_KNOWN" ]]; then
  track "$r" "$WELL_KNOWN"
  run "$r" >/dev/null 2>&1
  assert_exit "folder form: symlinked file rejected" 1 $?
  # A symlinked DIRECTORY segment escaping the repo is rejected too. The file is
  # tracked first, then its directory is swapped for the link, since git will
  # not add a path beyond a symlink.
  mkdir -p "$TEST_TMPDIR/outdir"
  printf '%s\n' "subject_pattern: '^outdir: .+'" >"$TEST_TMPDIR/outdir/commit-convention.yml"
  r="$(newrepo "")"
  addfolder "$r" "$(sp '^indir: .+')"
  rm -rf "${r:?}/$(dirname "$WELL_KNOWN")"
  ln -s "$TEST_TMPDIR/outdir" "$r/$(dirname "$WELL_KNOWN")" 2>/dev/null
  if [[ -L "$r/$(dirname "$WELL_KNOWN")" ]]; then
    err="$(run "$r" 2>&1 >/dev/null)"
    rc=$?
    assert_exit "folder form: symlinked dir segment rejected" 1 "$rc"
    assert_eq "folder form: symlinked dir segment -> the escape diagnostic" yes \
      "$([[ "$err" == *"resolves outside the repository root"* ]] && echo yes || echo no)"
  fi
else
  echo "SKIP: symlink cases (ln -s unavailable on this filesystem)"
fi

# =====================================================================
# Team YAML (docs/conventions/source-control.yaml) ahead of the folder form.
# Precedence, per key:
#   1. docs/conventions/source-control.yaml   (git-tracked)
#   2. docs/conventions/source-control/commit-convention.yml   (git-tracked)
# =====================================================================

# --- the YAML wins over the folder form ---
r="$(newrepo "")"
addfolder "$r" "$(sp '^old-folder: .+')"
addyaml "$r" $'pr_open_state: ready\n'"$(sp '^yaml-wins: .+')"
assert_eq "team yaml: wins over the folder form" '^yaml-wins: .+' "$(run "$r")"
assert_eq "team yaml: bash resolves it the same" '^yaml-wins: .+' "$(bash "$SCRIPT" "$r" subject_pattern)"
assert_eq "team yaml: --layer names the team yaml" "$TEAM_YAML" "$(layer "$r")"

# --- the folder form is read when the YAML lacks the key ---
r="$(newrepo "")"
addfolder "$r" "$(sp '^folder: .+')"
addyaml "$r" $'pr_open_state: ready'
assert_eq "team yaml lacks the key: the folder form supplies it" '^folder: .+' "$(run "$r")"
assert_eq "team yaml lacks the key: --layer names the folder form" "$WELL_KNOWN" "$(layer "$r")"

# --- neither file carries the key -> no enforcement ---
r="$(newrepo "")"
addfolder "$r" $'pr_title_pattern: \047^PR: .+\047'
addyaml "$r" $'pr_open_state: ready'
out="$(layer "$r")"
rc=$?
assert_eq "team yaml and folder form lack the key: exit 1, no layer" "1|" "$rc|$out"

# --- POLICY FLOOR: an untracked YAML is not a layer ---
r="$(newrepo "")"
addfolder "$r" "$(sp '^tracked-folder: .+')"
addfile "$r" "$TEAM_YAML" "$(sp '^untracked-yaml: .+')"
assert_eq "team yaml: an untracked file is ignored" '^tracked-folder: .+' "$(run "$r")"

# --- the CC keyword and the deferral marker work in the YAML ---
r="$(newrepo $'subject_pattern: Conventional Commits\npr_title_pattern: "Same as `subject_pattern`."')"
assert_eq "team yaml: CC keyword -> CC_ERE" "$CC_ERE" "$(run "$r")"
assert_eq "team yaml: pr deferral -> subject" "$CC_ERE" "$(run "$r" pr_title_pattern)"
assert_eq "team yaml: --layer for a deferral names the file holding pr_title_pattern" "$TEAM_YAML" \
  "$(layer "$r" pr_title_pattern)"

# --- a YAML deferral resolves subject_pattern per key, from the folder form ---
r="$(newrepo $'pr_title_pattern: "Same as `subject_pattern`."')"
addfolder "$r" "$(sp '^FS-[0-9]+: .+')"
assert_eq "team yaml: a deferral reads the folder-form subject_pattern the yaml lacks" '^FS-[0-9]+: .+' \
  "$(run "$r" pr_title_pattern)"

# --- a folder-form deferral resolves subject_pattern from the YAML ---
r="$(newrepo "$(sp '^YS-[0-9]+: .+')")"
addfolder "$r" $'pr_title_pattern: Same as `subject_pattern`.'
assert_eq "folder-form deferral: the effective subject_pattern comes from the yaml" '^YS-[0-9]+: .+' \
  "$(run "$r" pr_title_pattern)"

# --- a broken folder form never disables a key the YAML carries ---
r="$(newrepo "$(sp '^Y-[0-9]+: .+')")"
addfolder "$r" $'dialect: pcre\npr_title_pattern: \047^P: .+\047'
assert_eq "team yaml: a broken folder form does not disable a key the yaml carries" '^Y-[0-9]+: .+' "$(run "$r")"
run "$r" pr_title_pattern >/dev/null 2>&1
assert_exit "team yaml lacks the key: the broken folder form still fails closed" 1 $?

# --- fail closed: a YAML the parser rejects, never a folder-form fallback ---
r="$(newrepo $'subject_pattern: \047^unclosed: .+')"
addfolder "$r" "$(sp '^stale: .+')"
out="$(run "$r" 2>"$TEST_TMPDIR/yaml.err")"
rc=$?
assert_exit "team yaml: an unparsable file -> exit 1" 1 "$rc"
assert_eq "team yaml: an unparsable file -> empty stdout (no folder-form fallback)" "" "$out"
assert_eq "team yaml: the parse diagnostic names the file" yes \
  "$(grep -q 'source-control.yaml does not parse (line 1' "$TEST_TMPDIR/yaml.err" && echo yes || echo no)"
r="$(newrepo "$(sp '^a: .+')"$'\n'"$(sp '^b: .+')")"
run "$r" >/dev/null 2>&1
assert_exit "team yaml: a duplicate key -> exit 1" 1 $?

# --- fail closed: a present-but-empty YAML key ---
r="$(newrepo $'subject_pattern: \047\047')"
addfolder "$r" "$(sp '^stale: .+')"
out="$(run "$r")"
rc=$?
assert_exit "team yaml: empty quoted key -> exit 1" 1 "$rc"
assert_eq "team yaml: empty quoted key -> empty stdout (no folder-form fallback)" "" "$out"
r="$(newrepo $'pr_open_state: ready\nsubject_pattern:\n')"
addfolder "$r" "$(sp '^stale: .+')"
run "$r" >/dev/null 2>&1
assert_exit "team yaml: bare empty key -> exit 1" 1 $?
r="$(newrepo $'pr_title_pattern: "Same as `subject_pattern`."\nsubject_pattern: \047\047')"
addfolder "$r" "$(sp '^stale: .+')"
run "$r" pr_title_pattern >/dev/null 2>&1
assert_exit "team yaml: an empty subject_pattern behind a deferral -> exit 1" 1 $?
r="$(newrepo $'subject_pattern: [\047^a: .+\047, \047^b: .+\047]')"
addfolder "$r" "$(sp '^stale: .+')"
out="$(run "$r")"
rc=$?
assert_exit "team yaml: a list where one value belongs -> exit 1" 1 "$rc"
assert_eq "team yaml: a list where one value belongs -> empty stdout (no folder-form fallback)" "" "$out"
r="$(newrepo $'pr_open_state: ready\n"subject_pattern":')"
addfolder "$r" "$(sp '^stale: .+')"
run "$r" >/dev/null 2>&1
assert_exit "team yaml: a quoted bare key -> exit 1" 1 $?

# --- fail closed: a dialect other than posix-ere ---
r="$(newrepo $'dialect: pcre\n'"$(sp '^D-[0-9]+: .+')")"
out="$(run "$r")"
rc=$?
assert_exit "team yaml: dialect pcre -> exit 1" 1 "$rc"
assert_eq "team yaml: dialect pcre -> empty stdout" "" "$out"
r="$(newrepo $'dialect: posix-ere\n'"$(sp '^D-[0-9]+: .+')")"
assert_eq "team yaml: dialect posix-ere resolves" '^D-[0-9]+: .+' "$(run "$r")"

# --- fail closed: the parser is not beside the resolver ---
mkdir -p "$TEST_TMPDIR/lone"
cp "$SCRIPT" "$TEST_TMPDIR/lone/resolve-convention-pattern.sh"
r="$(newrepo "$(sp '^X-[0-9]+: .+')")"
out="$("$SH" "$TEST_TMPDIR/lone/resolve-convention-pattern.sh" "$r" subject_pattern 2>"$TEST_TMPDIR/lone.err")"
rc=$?
assert_exit "team yaml: no parser beside the resolver -> exit 1" 1 "$rc"
assert_eq "team yaml: no parser beside the resolver -> a diagnostic, not silence" yes \
  "$(grep -q 'yaml-subset.awk' "$TEST_TMPDIR/lone.err" && echo yes || echo no)"

# --- a symlinked YAML is rejected (skipped where ln -s can't make symlinks) ---
printf '%s\n' "subject_pattern: '^outside-yaml: .+'" >"$TEST_TMPDIR/outside-team.yaml"
r="$(newrepo "")"
mkdir -p "$r/docs/conventions"
ln -s "$TEST_TMPDIR/outside-team.yaml" "$r/$TEAM_YAML" 2>/dev/null
if [[ -L "$r/$TEAM_YAML" ]]; then
  track "$r" "$TEAM_YAML"
  out="$(run "$r")"
  rc=$?
  assert_exit "team yaml: a symlinked file -> exit 1" 1 "$rc"
  assert_eq "team yaml: a symlinked file -> empty stdout" "" "$out"
else
  echo "SKIP: symlinked team yaml (ln -s unavailable on this filesystem)"
fi

# =====================================================================
# The personal layer (docs/conventions/source-control.local.yaml): one
# operator's subject_pattern, read only while git ignores the file and only
# when the team layer supplies no subject_pattern. Never merged with a team
# pattern.
# =====================================================================

PERSONAL="docs/conventions/source-control.local.yaml"
# addpersonal <repo> <body> [gitignore|exclude|none]: write the personal file,
# ignored through .gitignore (the default) or .git/info/exclude, or not at all.
# core.excludesFile names a file that does not exist, so no global ignore rule
# on the machine running the suite can decide a case.
addpersonal() {
  local d="$1" how="${3:-gitignore}"
  git -C "$d" config core.excludesFile "$TEST_TMPDIR/no-global-excludes"
  addfile "$d" "$PERSONAL" "$2"
  case "$how" in
  gitignore) printf '%s\n' 'docs/conventions/**/*.local.*' >>"$d/.gitignore" ;;
  exclude)
    mkdir -p "$d/.git/info"
    printf '%s\n' "/$PERSONAL" >>"$d/.git/info/exclude"
    ;;
  *) ;;
  esac
}
P_BODY="$(sp '^PERSONAL-[0-9]+: .+')"

# --- the personal pattern is used when the team sets none ---
r="$(newrepo "")"
addpersonal "$r" "$P_BODY"
assert_eq "personal: used when the team sets none" '^PERSONAL-[0-9]+: .+' "$(run "$r")"
assert_eq "personal: bash resolves it the same" '^PERSONAL-[0-9]+: .+' "$(bash "$SCRIPT" "$r" subject_pattern)"
assert_eq "personal: --layer names the personal file" "$PERSONAL" "$(layer "$r")"
r="$(newrepo "")"
addpersonal "$r" "$P_BODY" exclude
assert_eq "personal: an entry in .git/info/exclude counts as ignored" '^PERSONAL-[0-9]+: .+' "$(run "$r")"
r="$(newrepo 'pr_open_state: ready')"
addpersonal "$r" "$P_BODY"
assert_eq "personal: used when the team yaml carries other keys only" '^PERSONAL-[0-9]+: .+' "$(run "$r")"
r="$(newrepo "")"
addpersonal "$r" $'subject_pattern: Conventional Commits'
assert_eq "personal: the CC keyword expands" "$CC_ERE" "$(run "$r")"

# --- a team pattern wins and the personal one is ignored when both exist ---
r="$(newrepo "")"
addpersonal "$r" "$P_BODY"
addyaml "$r" "$(sp '^TEAM-[0-9]+: .+')"
assert_eq "personal: the team yaml pattern wins over the personal one" '^TEAM-[0-9]+: .+' "$(run "$r")"
assert_eq "personal: --layer names the team yaml when both exist" "$TEAM_YAML" "$(layer "$r")"
r="$(newrepo "")"
addfolder "$r" "$(sp '^FOLDER-[0-9]+: .+')"
addpersonal "$r" "$P_BODY"
assert_eq "personal: a folder-form team pattern wins over the personal one" '^FOLDER-[0-9]+: .+' "$(run "$r")"
# A team value that cannot be enforced disables the gate; the personal pattern
# never stands in for it.
r="$(newrepo "")"
addpersonal "$r" "$P_BODY"
addyaml "$r" "$(sp '^(?:feat|fix): .+')"
out="$(run "$r" 2>/dev/null)"
rc=$?
assert_exit "personal: a non-ERE team pattern -> exit 1, the personal one not used" 1 "$rc"
assert_eq "personal: a non-ERE team pattern -> empty stdout" "" "$out"
r="$(newrepo "")"
addpersonal "$r" "$P_BODY"
addyaml "$r" $'subject_pattern: \047\047'
out="$(run "$r" 2>/dev/null)"
rc=$?
assert_exit "personal: an empty team key -> exit 1, the personal one not used" 1 "$rc"
assert_eq "personal: an empty team key -> empty stdout" "" "$out"
r="$(newrepo "")"
addpersonal "$r" "$P_BODY"
addfolder "$r" $'subject_pattern: \047\047'
out="$(run "$r" 2>/dev/null)"
rc=$?
assert_eq "personal: an empty folder-form key -> exit 1, the personal one not used" "1|" "$rc|$out"

# --- neither gives no enforcement, silently ---
r="$(newrepo "")"
out="$(run "$r" 2>"$TEST_TMPDIR/neither.err")"
rc=$?
assert_exit "personal: neither team nor personal -> exit 1" 1 "$rc"
assert_eq "personal: neither team nor personal -> empty stdout and stderr" "|" "$out|$(<"$TEST_TMPDIR/neither.err")"
r="$(newrepo "")"
addpersonal "$r" $'pr_open_state: ready'
out="$(run "$r" 2>"$TEST_TMPDIR/neither.err")"
rc=$?
assert_eq "personal: a personal file with no subject_pattern -> exit 1, silent" "1||" \
  "$rc|$out|$(<"$TEST_TMPDIR/neither.err")"

# --- pr_title_pattern never reads the personal file ---
r="$(newrepo "")"
addpersonal "$r" "$(sp '^P-[0-9]+: .+')"$'\npr_title_pattern: \047^P-[0-9]+: .+\047'
run "$r" pr_title_pattern >/dev/null 2>&1
assert_exit "personal: pr_title_pattern is not read from the personal file" 1 $?
addyaml "$r" $'pr_title_pattern: "Same as `subject_pattern`."'
run "$r" pr_title_pattern >/dev/null 2>&1
assert_exit "personal: a team deferral does not reach the personal subject_pattern" 1 $?

# --- a personal file git does not ignore is reported, not read ---
r="$(newrepo "")"
addpersonal "$r" "$P_BODY" none
out="$(run "$r" 2>"$TEST_TMPDIR/personal.err")"
rc=$?
assert_exit "personal: not ignored -> exit 1" 1 "$rc"
assert_eq "personal: not ignored -> empty stdout" "" "$out"
assert_eq "personal: not ignored -> the diagnostic says why" yes \
  "$(grep -q 'source-control.local.yaml is not ignored by git' "$TEST_TMPDIR/personal.err" && echo yes || echo no)"
r="$(newrepo "")"
addpersonal "$r" "$P_BODY"
git -C "$r" add -f -- "$PERSONAL"
out="$(run "$r" 2>"$TEST_TMPDIR/personal.err")"
rc=$?
assert_exit "personal: a tracked personal file -> exit 1 though .gitignore matches it" 1 "$rc"
assert_eq "personal: a tracked personal file -> empty stdout" "" "$out"

# --- fail closed: the personal file gets the team file's checks ---
r="$(newrepo "")"
addpersonal "$r" $'subject_pattern: \047^unclosed: .+'
out="$(run "$r" 2>"$TEST_TMPDIR/personal.err")"
rc=$?
assert_exit "personal: an unparsable file -> exit 1" 1 "$rc"
assert_eq "personal: the parse diagnostic names the personal file" yes \
  "$(grep -q 'source-control.local.yaml does not parse' "$TEST_TMPDIR/personal.err" && echo yes || echo no)"
r="$(newrepo "")"
addpersonal "$r" $'subject_pattern: \047\047'
out="$(run "$r" 2>"$TEST_TMPDIR/personal.err")"
rc=$?
assert_exit "personal: an empty key -> exit 1" 1 "$rc"
assert_eq "personal: the empty-key diagnostic names the personal file" yes \
  "$(grep -q "source-control.local.yaml carries 'subject_pattern'" "$TEST_TMPDIR/personal.err" && echo yes || echo no)"
r="$(newrepo "")"
addpersonal "$r" $'subject_pattern: [\047^a: .+\047, \047^b: .+\047]'
out="$(run "$r" 2>/dev/null)"
rc=$?
assert_eq "personal: a list where one value belongs -> exit 1, empty stdout" "1|" "$rc|$out"
r="$(newrepo "")"
addpersonal "$r" $'dialect: pcre\n'"$(sp '^P-[0-9]+: .+')"
run "$r" >/dev/null 2>&1
assert_exit "personal: dialect pcre -> exit 1" 1 $?
r="$(newrepo "")"
addpersonal "$r" "$(sp '^(?:feat|fix): .+')"
run "$r" >/dev/null 2>&1
assert_exit "personal: a non-ERE personal pattern -> exit 1" 1 $?
printf '%s\n' "subject_pattern: '^outside-personal: .+'" >"$TEST_TMPDIR/outside-personal.yaml"
r="$(newrepo "")"
addpersonal "$r" "$P_BODY"
rm -f "$r/$PERSONAL"
ln -s "$TEST_TMPDIR/outside-personal.yaml" "$r/$PERSONAL" 2>/dev/null
if [[ -L "$r/$PERSONAL" ]]; then
  out="$(run "$r" 2>"$TEST_TMPDIR/personal.err")"
  rc=$?
  assert_exit "personal: a symlinked file -> exit 1" 1 "$rc"
  assert_eq "personal: a symlinked file -> empty stdout" "" "$out"
  # The symlink check, not the ignore check, refused it.
  assert_eq "personal: a symlinked file -> the symlink diagnostic" yes \
    "$(grep -q "the personal file '$PERSONAL' is a symlink" "$TEST_TMPDIR/personal.err" && echo yes || echo no)"
else
  echo "SKIP: symlinked personal file (ln -s unavailable on this filesystem)"
fi

# --- --layer prints nothing when nothing is enforced ---
r="$(newrepo "")"
out="$(layer "$r")"
rc=$?
assert_exit "--layer, no tracked pattern -> exit 1" 1 "$rc"
assert_eq "--layer, no tracked pattern -> empty stdout" "" "$out"

# --- usage / invalid key ---
"$SH" "$SCRIPT" >/dev/null 2>&1
assert_exit "no args -> exit 2" 2 $?
"$SH" "$SCRIPT" --layer >/dev/null 2>&1
assert_exit "--layer with no args -> exit 2" 2 $?
"$SH" "$SCRIPT" "$TEST_TMPDIR" bogus_key >/dev/null 2>&1
assert_exit "invalid key -> exit 2" 2 $?

echo ""
echo "ran $CASE_NUM cases, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
