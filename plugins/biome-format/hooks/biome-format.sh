#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint JS/TS/JSX/JSON files via Biome.
# Triggered on Write|Edit of *.ts, *.tsx, *.js, *.jsx, *.mjs, *.cjs, *.mts,
# *.cts, *.json, *.jsonc files.
#
# ADVISORY: always exits 0. `biome check --write` applies safe fixes, formatting,
# and import sorting; residual Biome diagnostics (errors and, via
# --error-on-warnings, warnings) surface via additionalContext but never block
# the edit. A commit hook or CI is the hard gate.
#
# Opt-in: Biome runs ONLY when a biome.json or biome.jsonc config governs the
# edited file — found by walking up from the file to the repo root. A repo that
# has not adopted a Biome config is left untouched rather than rewritten to
# Biome's built-in defaults, so the plugin never imposes a style it did not
# choose. The Biome binary is resolved from the repo's own node_modules (or PATH)
# — never downloaded.

set -uo pipefail

# Kill switch FIRST, before any library is sourced: a disabled hook must not
# pay to parse hook-utils.sh to learn it is off. Same predicate as
# hook::is_enabled; scripts/check-killswitch-hoist.sh pins the two together.
[[ "${CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
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

# The SessionStart compact|clear row: the model lost the reports with its
# context, so the findings sent this session are sent again.
if [[ "${1:-}" == --reset-digests ]]; then
  hook::buffer_stdin_to INPUT && hook::findings_digest_reset "$INPUT"
  exit 0
fi

# The whole prologue: the start stamp, the buffered payload, the jq-free
# applicability filter, the jq gate, the parsed path with its basename and
# directory, the file-anchored repo root (which bounds the biome-config opt-in
# walk below), and the telemetry-only TOOL and FILE_REL behind the sink opt-in.
# Exits 0 itself on every path this hook has nothing to do on — including a
# Write or Edit of any other file class, which it decides before the jq gate so
# such an edit never triggers the jq notice.
hook::begin biome-format PostToolUse \
  '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.mts' '*.cts' '*.json' '*.jsonc'

# Every arm exits through hook::finish, which takes the rewrite disclosure
# (settling data.changed and releasing the guard's snapshot), emits telemetry
# with that verdict, and emits the one JSON document — in that order.
emit_skipped() {
  hook::finish skipped findings array '[]'
}

# Existence check only, no canonicalization: git already answers an absolute
# path, and the config walk accepts a relative fallback hint as it stands.
FILE_DIR_POSIX=""
[[ -d "$FILE_DIR" ]] && FILE_DIR_POSIX="$FILE_DIR"
root=""
[[ -d "$REPO_ROOT" ]] && root="$REPO_ROOT"

# Consumer opt-in: a Biome configuration that governs the edited file. Walk up
# from the file's directory to the repo root, recording the TOPMOST config dir
# (closest to the repo root). Biome discovers its configuration from the CWD
# upward — not from the target file — and a "root" config orchestrates any nested
# (`"root": false`) configs beneath it, so running from the topmost config's
# directory is the correct, monorepo-safe CWD. Absence of any config is the
# opt-out: the file is left untouched.
#
# Only the canonical names are accepted, NOT the hidden .biome.json/.biome.jsonc
# variants: hidden-config loading was added in Biome 2.4, so on an older Biome
# this gate would fire while Biome's own discovery ignored the dotted file and
# reformatted with built-in defaults — the exact silent wrong-config reformat the
# opt-in exists to prevent. Gating on the names every supported Biome discovers keeps
# the gate in lockstep with discovery across versions. Dotted-config support is
# deferred behind a Biome>=2.4 probe.
#
# `topmost` is what makes this the root config rather than the closest one, and
# the walk's ceiling is the repo root: with none that resolves it fails closed
# (hook::walk_up_to) and the file is left alone, rather than being reformatted
# under a config from above the repository.
# shellcheck disable=SC2329  # invoked by name, as hook::walk_up_to's predicate
biome_config_here() {
  local name
  for name in biome.json biome.jsonc; do
    [[ -f "$1/$name" ]] && return 0
  done
  return 1
}
CONFIG_DIR=""
hook::walk_up_to CONFIG_DIR "$FILE_DIR_POSIX" "$root" biome_config_here topmost ||
  emit_skipped

# A file the repository gitignores is neither rewritten nor reported unless
# biome_format_lint_gitignored is set: a rewrite there has no `git checkout`
# to undo it. Biome skips an ignored path itself only when the consumer's
# config enables vcs.useIgnoreFile, which is off by default.
hook::gitignored_out_of_scope "${CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_LINT_GITIGNORED:-false}" "$FILE" &&
  emit_skipped

# Resolve the Biome binary from the repo's own install (node_modules/.bin/biome,
# walking up from the file) or PATH — never `npx`, which would download Biome on
# a per-edit hook. Absent -> skip (the repo opted into config but Biome is not
# installed; nothing to run).
BIOME_BIN=""
# shellcheck disable=SC2329  # invoked by name, as hook::walk_up_to's predicate
biome_local_bin_here() {
  [[ -f "$1/node_modules/.bin/biome" ]] || return 1
  BIOME_BIN="$1/node_modules/.bin/biome"
  return 0
}
# shellcheck disable=SC2034  # the caller reads BIOME_BIN, which the predicate sets
node_modules_dir=""
hook::walk_up_to node_modules_dir "$FILE_DIR_POSIX" "$root" biome_local_bin_here || true
if [[ -z "$BIOME_BIN" ]]; then
  # `command -v` is a builtin; the resolved path is not captured because the
  # later exec looks the name up on PATH itself.
  command -v biome >/dev/null 2>&1 && BIOME_BIN=biome
fi

# The repo opted in via a Biome config but no binary is available → visible
# once-per-session skip notice, not a silent gap (dim-9 doctrine).
if [[ -z "$BIOME_BIN" ]]; then
  BIOME_MODEL="" BIOME_USER=""
  if hook::prereq_notice_to BIOME_MODEL BIOME_USER biome "$INPUT"; then
    hook::emit_skip_notice PostToolUse "$BIOME_MODEL" "$BIOME_USER"
  fi
  emit_skipped
fi

# Pass the file as a path relative to CONFIG_DIR (the CWD Biome runs in) so the
# reporter echoes the path as given (e.g. src/app.ts), which the findings parse
# below strips. CONFIG_DIR and FILE_DIR_POSIX both come from
# `pwd`, so the prefix strip compares the same form; CONFIG_DIR is an ancestor of
# the file, so it always matches. Falls back to the absolute path if it does not.
BIOME_ARG="$FILE"
if [[ -n "$FILE_DIR_POSIX" ]]; then
  _file_posix="$FILE_DIR_POSIX/$FILE_BASE"
  _rel="${_file_posix#"$CONFIG_DIR"/}"
  [[ "$_rel" != "$_file_posix" ]] && BIOME_ARG="$_rel"
fi

# Run Biome from the governing config's directory (CWD-anchored discovery).
# `check` = format + lint + import sorting; --write applies safe fixes;
# --error-on-warnings makes residual warnings (not just errors) exit non-zero so
# they surface as advisory context. --reporter=concise prints one line per
# diagnostic (path, line, column, rule and message) instead of the verbose
# default boxes.
#
# BIOME_CONFIG_PATH is unset for this command: Biome reads it as a config-path
# override, so a stray user- or project-level export would make Biome format the
# edit with an unrelated config even though the gate keyed on the repo's own
# biome.json (verified empirically). Unsetting it keeps the discovered CONFIG_DIR
# config authoritative — consistent with the in-tree opt-in this plugin is built
# on (an out-of-tree config has no in-tree biome.json, so the gate skips anyway).
# Content-mutation disclosure (#1596): Biome may auto-fix and/or reformat layout
# the user did not request. Name the rewrite on the user channel; stay silent
# when the file is unchanged. Snapshot lifecycle and single-document
# composition live in the shared rewrite-guard lib (#3406, #3409): the
# disclosure is TAKEN once after the check runs and composed into the exiting
# arm's one JSON document, never emitted mid-run as a second document.
BIOME_REWRITE_MESSAGE="biome-format: reformatted $FILE_BASE."
hook::rewrite_guard_begin "$FILE"

BIOME_CTX=""
FINDINGS_JSON='[]'
if OUTPUT=$(cd "$CONFIG_DIR" && env -u BIOME_CONFIG_PATH "$BIOME_BIN" check --write --error-on-warnings --reporter=concise "$BIOME_ARG" 2>&1); then
  # Clean: the disclosure is the whole document, or there is none. The empty
  # set clears the delta record, so findings that come back are sent again.
  hook::findings_to BIOME_CTX "" "" --delta "$INPUT" "$FILE"
  hook::finish --disclose "$BIOME_REWRITE_MESSAGE" ok findings array '[]'
fi

# Non-zero exit. The concise reporter prints one `<mark> <path>:<line>:<col>:
# <rule>: <message>` line per diagnostic; their presence is the unambiguous
# signal that Biome made a lint/format judgment with residual findings. Surface
# just those lines, without the mark and the path the heading names, and not the
# summary footer. Status "ok" — the linter RAN and produced a judgment
# (findings live in data.findings), mirroring the bash-format model where status
# reflects whether the tool ran, not whether it was clean.
FINDINGS=""
while IFS= read -r _line; do
  [[ "$_line" =~ ^[^[:space:]]+\ (.*)$ && "${BASH_REMATCH[1]}" == "$BIOME_ARG:"* ]] || continue
  FINDINGS+="${BASH_REMATCH[1]#"$BIOME_ARG:"}"$'\n'
done <<<"$OUTPUT"
if [[ -n "$FINDINGS" ]]; then
  # --delta sends a finding set once per (session, agent, file).
  # The heading names the config-relative path, or the basename when that did
  # not resolve; never the absolute path the tool is handed as a fallback.
  BIOME_SHOWN="$BIOME_ARG"
  [[ "$BIOME_ARG" == "$FILE" ]] && BIOME_SHOWN="$FILE_BASE"
  hook::findings_to BIOME_CTX "biome-format: $BIOME_SHOWN has findings:" \
    "$FINDINGS" FINDINGS_JSON --max 20 --delta "$INPUT" "$FILE"
  # Findings AND a rewrite disclosure compose into one document (#3406).
  hook::finish --context "$BIOME_CTX" --disclose "$BIOME_REWRITE_MESSAGE" \
    ok findings array "$FINDINGS_JSON"
fi

# No findings, but the file was deliberately ignored by the consumer's Biome
# config (or a built-in default ignore such as node_modules). Biome exits 1 with
# "No files were processed in the specified paths." — this is the repo's opt-out,
# not a finding and not a break, so skip silently without nagging via context.
# (Biome 2.x respects files.includes ignores even for explicitly-passed paths.)
if grep -qE 'No files were processed|provided but ignored' <<<"$OUTPUT"; then
  # An ignored file was not rewritten, so the disclosure is empty and this
  # emits nothing; the disclosure is still passed so a surprising rewrite
  # would be disclosed rather than swallowed.
  hook::finish --disclose "$BIOME_REWRITE_MESSAGE" skipped findings array '[]'
fi

# Biome broke for non-lint reasons (config parse error, panic, ENOENT) — no
# judgment was made. Surface the diagnostic via additionalContext (NOT stderr —
# an advisory hook's exit-0 stderr can trip a false "Hook Error" label). Record
# as "skipped" (the linter never ran), the same status as the no-config /
# no-binary paths.
[[ -n "$OUTPUT" ]] || OUTPUT="biome exited non-zero with no output"
hook::findings_to BIOME_CTX "biome-format: biome failed on $FILE_BASE:" \
  "$OUTPUT" --max 10 --delta "$INPUT" "$FILE"
# The --write pass may already have rewritten the file before Biome broke, so
# the disclosure composes with the tool-break context as one document.
hook::finish --context "$BIOME_CTX" --disclose "$BIOME_REWRITE_MESSAGE" \
  skipped findings array '[]'
