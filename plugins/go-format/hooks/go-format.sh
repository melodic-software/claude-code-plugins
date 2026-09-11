#!/usr/bin/env bash
# PostToolUse hook: auto-format and manage imports for Go files via goimports.
# Triggered on Write|Edit of *.go files.
#
# ADVISORY: always exits 0. `goimports -w` rewrites the file in place;
# a residual syntax error goimports cannot parse surfaces via
# additionalContext but never blocks the edit. A commit hook or CI is the
# hard gate.
#
# UNCONDITIONAL — no consumer-config opt-in gate, unlike the sibling
# ruff-format/typos-format/dotnet ecosystem entry. goimports' own docs state
# it "formats your code in the same style as gofmt so it can be used as a
# replacement for your editor's gofmt-on-save hook" — an explicit official
# statement of intent for exactly this per-file/on-save scenario, and it has
# no meaningful config-divergence axis when left unconfigured (unlike
# ruff/dotnet format, whose underlying tools DO have configurable, genuinely
# divergent output).
#
# GENERATED-FILE GUARD: goimports has zero awareness of Go's own
# `// Code generated ... DO NOT EDIT.` convention — empirically confirmed it
# rewrites such files with no warning. Generated Go files (protobuf, mockgen,
# sqlc, stringer, wire output) are common; this hook skips any file whose
# leading comment/blank-line block (scanned below) contains that marker,
# mirroring the precision `--force-exclude` gives Ruff/typos for free via
# consumer config (this hook has no config to consult, so the marker check
# is the equivalent guard).
#
# The goimports binary is resolved from PATH only — never downloaded. Go
# binaries are conventionally `go install`ed to $GOPATH/bin, which a
# developer adds to PATH themselves; there is no per-project virtualenv
# concept in Go the way ruff-format walks a .venv.

set -uo pipefail

# Kill switch FIRST, before any library is sourced: a disabled hook must not
# pay to parse hook-utils.sh to learn it is off. Same predicate as
# hook::is_enabled; scripts/check-killswitch-hoist.sh pins the two together.
[[ "${CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$HOOK_DIR/rewrite-guard.sh"

# The whole prologue: the start stamp, the buffered payload, the jq-free
# applicability filter, the jq gate, the parsed path with its basename and
# directory, the file-anchored repo root, and the telemetry-only TOOL and
# FILE_REL behind the sink opt-in. Exits 0 itself on every path this hook has
# nothing to do on — including a Write or Edit of anything but a Go file, which
# it decides before the jq gate so a non-Go edit never triggers the jq notice.
hook::begin go-format PostToolUse '*.go'

# Every arm exits through hook::finish, which takes the rewrite disclosure
# (settling data.changed and releasing the guard's snapshot), emits telemetry
# with that verdict, and emits the one JSON document — in that order.
emit_skipped() {
  hook::finish skipped findings array '[]'
}

# Generated-file guard: skip files carrying Go's canonical generated-code
# marker — goimports itself has no awareness of this convention (empirically
# confirmed it rewrites such files silently). Go's own convention (`go help
# generate`, verified live: "This line must appear before the first
# non-comment, non-blank text in the file") does not restrict "comment" to
# `//` style — a `/* ... */` block comment (e.g. a conventional block
# license header) is a comment for this purpose too, so it must not end the
# leading-block scan early. Scan the file's leading comment/blank-line run,
# tracking open `/* */` blocks, and stop only at the first line that is
# genuinely neither blank, a `//` comment, nor inside/starting a `/* */`
# block (e.g. `package foo`). A trailing CRLF `\r` and a leading UTF-8 BOM
# are stripped per line so a Windows-checked-out or BOM-prefixed file still
# matches. (The marker itself can only ever appear on a `//`-prefixed line —
# `^// Code generated .* DO NOT EDIT\.$` — never inside a `/* */` block, so
# block-comment lines are only ever scanned-through, not matched against.)
#
# APPROXIMATION: this string-match scan is a deliberate stand-in for Go's own
# `ast.IsGenerated`, which classifies a *parsed* `*ast.File` (via `go/parser`).
# The two cannot be made equal by adding patterns — the gap is structural, so
# exotic shapes (unusual build-tag/comment interleavings, nested block
# comments, atypical Unicode whitespace) can keep surfacing indefinitely. That
# is tolerable because the guard is advisory (see ADVISORY, top of file): an
# unhandled shape only means goimports reformats a generated file — visible in
# the diff, no gate broken. So no further pattern patches are planned unless a
# *real-world* generated file is observed defeating this scan; a synthetic
# counter-example alone is not enough. The actual structural fix, should a real
# case ever warrant it, is to shell out to the `go` toolchain (`go/parser` plus
# the real `ast.IsGenerated` logic) instead of extending this matcher — not
# done here because it would add per-edit latency and a hard `go`-toolchain
# dependency this hook otherwise keeps optional (only `-local` grouping needs
# `go`).
GENERATED=0
IN_BLOCK=0
while IFS= read -r _line || [[ -n "$_line" ]]; do
  _line="${_line%$'\r'}"
  _line="${_line#$'\xEF\xBB\xBF'}"
  if [[ $IN_BLOCK -eq 1 ]]; then
    [[ "$_line" == *'*/'* ]] && IN_BLOCK=0
    continue # still inside (or just closed) a block comment: keep scanning
  fi
  [[ -n "${_line//[[:space:]]/}" ]] || continue # blank line (any whitespace, incl. tabs): keep scanning the leading block
  # Trimmed only for comment-shape classification (an indented `//`/`/*`
  # still counts as "still within the leading comment block") — the marker
  # regex itself stays column-0-anchored, matching Go's own convention.
  _trimmed="${_line#"${_line%%[![:space:]]*}"}"
  if [[ "$_line" == //* ]]; then
    if [[ "$_line" =~ ^//\ Code\ generated\ .*\ DO\ NOT\ EDIT\.$ ]]; then
      GENERATED=1
      break
    fi
    continue # a different // comment line: still within the leading block
  fi
  if [[ "$_trimmed" == //* ]]; then
    continue # an indented // comment line: still within the leading block
  fi
  if [[ "$_trimmed" == /\** ]]; then
    [[ "$_trimmed" == *'*/'* ]] || IN_BLOCK=1 # opens a block comment spanning further lines
    continue                                  # an indented /* ... */ comment (single- or multi-line): still within the leading block
  fi
  break # first non-comment, non-blank line: leading block ended, marker absent
done <"$FILE"
[[ $GENERATED -eq 1 ]] && emit_skipped

# Resolve the goimports binary from PATH — never downloaded.
# `command -v` is a builtin; capturing it with `$( )` was a leftover subshell
# just to learn the path. The later exec looks the name up on PATH itself.
GOIMPORTS_BIN=""
command -v goimports >/dev/null 2>&1 && GOIMPORTS_BIN=goimports

if [[ -z "$GOIMPORTS_BIN" ]]; then
  if hook::notice_once "go-format-goimports" "$INPUT"; then
    GO_NOTICE=""
    hook::tool_missing_notice_to GO_NOTICE \
      "go-format: no 'goimports' binary found on this hook's PATH — format/import-fix skipped for this edit" \
      matching ". Install: go install golang.org/x/tools/cmd/goimports@latest"
    hook::emit_skip_notice PostToolUse "$GO_NOTICE"
  fi
  emit_skipped
fi

# Auto-derive goimports' -local grouping prefix from the edited file's own
# module path (`go list -m`, which walks up to the nearest go.mod using
# Go's own module resolution — more robust than hand-parsing the module
# directive). Without -local, goimports lumps a repo's own internal
# packages into the same group as third-party imports; a repo that already
# formats with -local (a common Go convention, e.g. wired into its own CI
# or editor config) would have this hook re-collapse that grouping on every
# edit — empirically confirmed this materially changes output when a
# third-party import is also present. Deriving the LOCAL prefix from the
# file's own module path (self-grouping) requires no new consumer-config
# surface, so it stays within the unconditional/no-opt-in design while
# covering the single most common -local use case. `go` absent, the file
# outside any module, or any other resolution failure all degrade to no
# -local flag (goimports' plain default grouping), never a hard stop.
LOCAL_PREFIX=""
if command -v go >/dev/null 2>&1; then
  LOCAL_PREFIX="$(cd "$FILE_DIR" 2>/dev/null && go list -m 2>/dev/null)" || LOCAL_PREFIX=""
  [[ "$LOCAL_PREFIX" == "command-line-arguments" ]] && LOCAL_PREFIX=""
fi
GOIMPORTS_ARGS=(-w -l)
[[ -n "$LOCAL_PREFIX" ]] && GOIMPORTS_ARGS+=(-local "$LOCAL_PREFIX")

# Content-mutation disclosure (#1596): goimports rewrites imports and layout
# only; name the rewrite on the user channel and stay silent on no-op paths.
# Snapshot lifecycle and single-document composition live in the shared
# rewrite-guard lib (#3405, #3409).
GO_REWRITE_MESSAGE="go-format: reformatted $FILE_BASE via goimports (imports and layout only)."
hook::rewrite_guard_begin "$FILE"
# -w writes the fix in place; -l (combined with -w) lists the changed
# filename on stdout, which this hook doesn't need (a successful autofix
# carries no advisory noise, same posture as a successful ruff/typos fix
# pass — only a genuine syntax error below produces a finding). Verified
# empirically (goimports v0.48.0): -l ALWAYS exits 0, even when it lists a
# file — there is no exit-1-style "findings" signal like ruff/typos have.
# Non-zero exit (verified: 2, with a parseable message on stderr) occurs
# only on a genuine parse/syntax error — captured via command substitution
# (stdout discarded, stderr redirected to fd1) the same way every sibling
# hook in this repo captures tool output, rather than a temp file. `--`
# ends flag parsing before $FILE — defense-in-depth against a path that
# happens to start with `-` being misread as a flag by Go's flag package.
STDERR=$("$GOIMPORTS_BIN" "${GOIMPORTS_ARGS[@]}" -- "$FILE" 2>&1 >/dev/null)
RC=$?

if [[ $RC -eq 0 ]]; then
  # Clean, or fixed silently (formatting/import changes carry no advisory
  # noise — same posture as a successful ruff/typos autofix pass): the
  # disclosure is the whole document, or there is none.
  hook::finish --disclose "$GO_REWRITE_MESSAGE" ok findings array '[]'
fi

if [[ $RC -eq 2 && -n "$STDERR" ]]; then
  # goimports ran and produced a judgment: the file has a syntax error it
  # cannot parse. This is a finding, not a tool break — mirrors how
  # ruff-format surfaces a mid-edit syntax error as a finding.
  GO_CTX=""
  FINDINGS_JSON='[]'
  hook::findings_to GO_CTX \
    "go-format: $FILE_BASE has a syntax error goimports could not parse (advisory):" \
    "$STDERR" FINDINGS_JSON
  # Findings AND a rewrite disclosure compose into one document (#3406 class).
  hook::finish --context "$GO_CTX" --disclose "$GO_REWRITE_MESSAGE" \
    ok findings array "$FINDINGS_JSON"
fi

# goimports broke for non-syntax reasons (internal error, unexpected exit
# code) — no judgment was made. Surface the diagnostic via additionalContext
# (NOT stderr — an advisory hook's exit-0 stderr can trip a false "Hook
# Error" label). Record as "skipped" (the tool never ran to judgment).
GO_CTX=""
hook::findings_to GO_CTX \
  "go-format: goimports failed for $FILE_BASE (no diagnostics; tool break, not a finding):" \
  "$STDERR"
# goimports may have written the file before breaking, so the disclosure is
# still owed and composes with the tool-break context as one document; the take
# inside hook::finish is also what records that rewrite in data.changed.
hook::finish --context "$GO_CTX" --disclose "$GO_REWRITE_MESSAGE" \
  skipped findings array '[]'
