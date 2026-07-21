#!/usr/bin/env bash
# PostToolUse hook: verify CLI flags in newly-written shell/PowerShell/markdown
# files against `<bin> [<subcmd>...] --help` output via the bundled
# lib/verification/verify-cli-flag.sh.
# Triggered on Write|Edit of *.sh, *.bash, *.ps1, *.psm1, *.md files.
#
# Catches subagent / training-recall hallucinations — a CLI flag written AS a
# command that does not exist in the binary's actual --help output.
#
# Subcommand-aware + code-span-scoped: each `--flag` is bound to the bin heading
# its OWN command span and verified against `<bin> [<subcmd>...] --help` (the
# verifier accepts a subcommand chain). For markdown, only code is scanned —
# inline-code spans + fenced code blocks — because a flag is a real
# copy/paste/exec hazard only when written AS a command. This eliminates two
# false-positive classes a naive line-scan produces: subcommand-flag blindness
# (checking `<bin> --help` only) and cross-pairing a bin with every `--flag` on
# a line.
#
# NON-BLOCKING (advisory): exits 0 with hookSpecificOutput additionalContext
# on unknown flags (exit 1 stderr is not shown to the agent per hook contract).
#
# Per-binary opt-out via the cli_flag_verify_skip_bins userConfig option (e.g. for
# extension-heavy CLIs like gh where --help is non-exhaustive). Disable entirely
# with the cli_flag_verify_enabled userConfig option set to false.

set -uo pipefail

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "CLI_FLAG_VERIFY"

# jq is required to parse the tool payload. Fail OPEN when it is absent, but make
# the degraded state visible rather than silently disabling the hook.
if ! command -v jq >/dev/null 2>&1; then
  echo "guardrails/cli-flag-verify: jq not found on PATH — hook disabled (install jq to enable)." >&2
  exit 0
fi

hook::ctx_reset

# Bundled verifier — resolved under the plugin root (CC sets CLAUDE_PLUGIN_ROOT;
# the BASH_SOURCE fallback keeps the contract tests working when it is unset).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERIFIER="$PLUGIN_ROOT/lib/verification/verify-cli-flag.sh"

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; empty
# or timed-out stdin skips this advisory hook. Pipe the buffered payload into
# hook::read_file_path so its jq no longer reads the inherited fd0 directly.
INPUT=$(hook::buffer_stdin) || exit 0
FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
IS_MD=false
case "$FILE" in
*.md) IS_MD=true ;;
*.sh | *.bash | *.ps1 | *.psm1) ;;
*) exit 0 ;;
esac

# Diff-scope: verify only the content THIS tool call wrote, never re-read the
# whole file from disk. An Edit's pre-existing lines outside the changed hunk are
# not this call's claims; scanning the whole file re-flags an unknown flag on
# every later unrelated edit. Edit -> the changed hunk (new_string); Write -> the
# full payload content (a PostToolUse Write payload cannot distinguish a new file
# from an overwrite, so "whole-file only for new files" degrades to whole-content
# here — still the payload, never disk). The live matcher is Write|Edit; any
# other tool carries nothing this call wrote that we can scope a scan to.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null | tr -d '\r')
case "$TOOL" in
Edit) SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | tr -d '\r') ;;
Write) SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null | tr -d '\r') ;;
*) exit 0 ;;
esac
[[ -n "$SCAN_CONTENT" ]] || exit 0

[[ -x "$VERIFIER" ]] || exit 0 # Verifier not present — fail open, don't block

# Repo root for telemetry data.file + relative sink resolution (file-anchored).
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"

# Known binaries to check. Override via the cli_flag_verify_bins userConfig option.
# `git` and `npx` are intentionally EXCLUDED — both are unreliable `--help`
# flag lists whose residuals are all real-flag false positives:
#   - `git <subcmd> --help` routes to the man page (or a short synopsis under
#     timeout), not a parseable per-subcommand flag list, AND the flaky output
#     poisons the 24h --help cache → persistent FPs.
#   - `npx <pkg> --help` runs an ARBITRARY package's help (reliability is the
#     package's, not npx's) and an uninstalled `<pkg>` can trigger a network
#     fetch. Working cases produce no residual (invisible benefit); failing
#     cases produce visible FPs — same shape that excludes git.
# Re-add either via the env var if it ever ships a stdout-parseable flag list.
DEFAULT_BINS="claude gh dotnet docker npm kubectl terraform az aws"
BINS_RAW="${CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS:-$DEFAULT_BINS}"
# Normalize: comma OR space separated → space separated.
BINS="${BINS_RAW//,/ }"

# Per-binary opt-outs. Comma-separated. Common case: gh extensions, docker plugin
# subcommands where --help is not exhaustive.
SKIP_RAW="${CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS:-}"
SKIP="${SKIP_RAW//,/ }"

is_skipped() {
  local bin="$1" skip
  for skip in $SKIP; do
    [[ "$bin" == "$skip" ]] && return 0
  done
  return 1
}

# Emit candidate command fragments (one per line) from the scanned payload
# content ($SCAN_CONTENT — the changed hunk for Edit, full content for Write).
#   - Markdown: scan CODE only — inline-code spans (one combined grep, then
#     strip the delimiting backticks) + fenced code-block bodies. Fenced content
#     carries no inline backticks, so the inline grep naturally excludes it.
#   - Shell/PowerShell: every line is code.
# Fence state is derived from the hunk alone, so a fence-straddling markdown edit
# can misclassify in EITHER direction (a hunk inside a block whose ``` markers
# fall outside it reads as prose and is under-scanned; a hunk that opens with a
# closing ``` can over-scan). The convention trades this whole-file context away
# for diff-scope precision; this fence-straddling residual is accepted, not
# reconstructed. A distinct residual — an Edit hunk that is a bare flag fragment
# with no binary in the changed region — IS recovered downstream by
# reconstruct_partial_edit, which pulls bounded on-disk context so a swapped-in
# unknown flag is not missed.
emit_fragments() {
  if [[ "$IS_MD" == "true" ]]; then
    # Inline-code spans (strip the delimiting backticks).
    # shellcheck disable=SC2016  # backticks are literal ERE/sed data, not expansions
    printf '%s' "$SCAN_CONTENT" | grep -oE '`[^`]+`' 2>/dev/null | sed -E 's/^`+//; s/`+$//'
    # Fenced code-block bodies, skipping in-fence comment lines (a backtick-
    # wrapped example inside a `#` comment would otherwise split into a segment).
    printf '%s' "$SCAN_CONTENT" | awk '
      /^[[:space:]]*```/ { f = !f; next }
      /^[[:space:]]*~~~/ { f = !f; next }
      f && $0 !~ /^[[:space:]]*#/ { print }
    ' 2>/dev/null
  else
    # Shell/PowerShell: every non-comment line is code. Drop full-line comments
    # BEFORE separator-splitting — otherwise a backtick-wrapped CLI example in a
    # comment is split on its backticks into a spurious bin-led command segment
    # (the comment's leading `#` lands in a different segment). `|| true`: grep
    # exits 1 when every line is a comment.
    printf '%s' "$SCAN_CONTENT" | grep -vE '^[[:space:]]*#' 2>/dev/null || true
  fi
}

# Split fragments into command segments on shell command separators and
# command-substitution / subshell boundaries, one segment per line. `$(` is
# rewritten first so its `(` isn't double-counted by the class below.
split_segments() {
  sed -E 's/\$\(/\n/g; s/(\|\||&&|[;|&`()])/\n/g'
}

# Populate CANDIDATES with "bin|subcmd-chain|flag" keys. The chain is the
# non-flag tokens between the bin and the first long flag (short options are
# skipped, not chain-breaking); every long flag in the segment binds to it.
declare -A CANDIDATES=()

extract_candidates() {
  local seg
  while IFS= read -r seg; do
    local -a toks=()
    read -ra toks <<<"$seg"
    ((${#toks[@]})) || continue

    # Skip leading command wrappers + env-assignment prefixes to reach the bin.
    local idx=0 lead
    while ((idx < ${#toks[@]})); do
      lead="${toks[idx]#[\`\'\"\(\!]}"
      case "$lead" in
      sudo | command | env | time | exec | xargs | then | do | else | "!")
        ((idx++))
        continue
        ;;
      *)
        if [[ "$lead" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
          ((idx++))
          continue
        fi
        break
        ;;
      esac
    done
    ((idx < ${#toks[@]})) || continue

    # Candidate bin: strip surrounding quotes/parens/backticks/bang.
    local bin="${toks[idx]}"
    bin="${bin#[\`\'\"\(\!]}"
    bin="${bin%[\`\'\"\):;,]}"
    [[ " $BINS " == *" $bin "* ]] || continue
    is_skipped "$bin" && continue

    # Walk remaining tokens: collect the subcommand chain (real-subcommand-shaped
    # tokens before the first long flag) + every long flag bound to that chain.
    #   - `--` ends option parsing — everything after is program args, not flags.
    #   - A short option before the subcommand is skipped (it does not break the
    #     chain); after the subcommand it ends the chain.
    #   - A non-subcommand-shaped token (path, var, csproj, value) is skipped but
    #     does NOT end the chain — a positional can sit mid-chain (e.g.
    #     `dotnet list <SLN> package`). Only shaped lowercase words join the chain,
    #     keeping junk out of the verified `<bin> <chain> --help` invocation.
    local -a chain=() seg_flags=()
    local chain_done=0 k tk fl ct
    for ((k = idx + 1; k < ${#toks[@]}; k++)); do
      tk="${toks[k]}"
      case "$tk" in
      --)
        break
        ;;
      --*)
        chain_done=1
        fl="${tk%%=*}" # drop =VALUE
        if [[ "$fl" =~ ^(--[a-zA-Z][a-zA-Z0-9-]*) ]]; then
          fl="${BASH_REMATCH[1]}"
          case "$fl" in
          --help | --version) ;;
          *) seg_flags+=("$fl") ;;
          esac
        fi
        ;;
      -?*)
        # short option: before the subcommand, skip it (chain keeps looking);
        # after the subcommand, options have begun → chain ends.
        ((chain_done == 0 && ${#chain[@]} > 0)) && chain_done=1
        ;;
      *)
        ct="${tk%[\`\'\"\):;,]}"
        ct="${ct#[\`\'\"\(]}"
        # A second known bin starts a NESTED command whose flags are not this
        # bin's — `docker run <img> dotnet restore --force-evaluate`,
        # `xargs gh issue … --json`. Everything from here belongs to it; stop.
        [[ " $BINS " == *" $ct "* ]] && break
        # Only shaped lowercase words join the chain; a non-shaped positional
        # (path, csproj, var, SLN file) is skipped without ending the chain so
        # `dotnet list <SLN> package --flag` still resolves the full subcommand.
        if ((chain_done == 0)) && [[ "$ct" =~ ^[a-z][a-z0-9-]*$ ]] && ((${#chain[@]} < 4)); then
          chain+=("$ct")
        fi
        ;;
      esac
    done

    ((${#seg_flags[@]})) || continue
    local chainstr="${chain[*]}" f
    for f in "${seg_flags[@]}"; do
      CANDIDATES["$bin|$chainstr|$f"]=1
    done
  done < <(emit_fragments | split_segments)
}

extract_candidates

# Partial-replacement context reconstruction (Edit only). When an Edit's hunk is
# a bare flag fragment — a flag token swapped in with no binary/subcommand in the
# changed region — the diff-scoped scan finds no command candidate and would
# silently miss a genuinely-introduced unknown flag. Recover bounded context:
# pull from the on-disk file only the lines carrying one of the hunk's flag
# tokens (the edit has already been applied by PostToolUse time, so the swapped-in
# flag is on disk), scan those, and keep only candidates whose flag appears in the
# hunk. The flag-token filter is what preserves the diff-scope contract: a
# pre-existing unrelated flag sharing one of those lines never re-fires. The
# anchor is the flag token, not the line — a bare-flag hunk carries no positional
# information — so a hunk flag that also occurs on an untouched line is scanned
# there too; only a DIFFERENT pre-existing flag is excluded.
reconstruct_partial_edit() {
  [[ "$TOOL" == "Edit" && -f "$FILE" ]] || return 0
  # Trigger only when the hunk produced no command candidate; a full-command hunk
  # already scans correctly and must not re-scan from disk.
  ((${#CANDIDATES[@]} == 0)) || return 0
  local -a hunk_flags=()
  mapfile -t hunk_flags < <(
    printf '%s' "$SCAN_CONTENT" |
      grep -oE '(^|[[:space:]])--?[A-Za-z0-9][A-Za-z0-9-]*' 2>/dev/null |
      sed -E 's/^[[:space:]]*//' | sort -u
  )
  ((${#hunk_flags[@]})) || return 0
  local tok ctx="" lines
  for tok in "${hunk_flags[@]}"; do
    lines=$(grep -F -- "$tok" "$FILE" 2>/dev/null)
    [[ -n "$lines" ]] && ctx+="$lines"$'\n'
  done
  ctx=$(printf '%s' "$ctx" | grep -vE '^[[:space:]]*$' | head -20)
  [[ -n "$ctx" ]] || return 0
  SCAN_CONTENT="$ctx"
  extract_candidates
  local key flag t keep
  for key in "${!CANDIDATES[@]}"; do
    flag="${key##*|}"
    keep=0
    for t in "${hunk_flags[@]}"; do
      [[ "$flag" == "$t" ]] && {
        keep=1
        break
      }
    done
    ((keep)) || unset 'CANDIDATES[$key]'
  done
}

reconstruct_partial_edit

# Verify each unique (bin, chain, flag). Collect failures (keys, formatted later).
FAILURES=()
for key in "${!CANDIDATES[@]}"; do
  bin="${key%%|*}"
  rest="${key#*|}"
  chainstr="${rest%|*}"
  flag="${rest##*|}"
  # Skip if binary not on PATH (verifier exit 2). Avoids spurious failures on
  # systems missing tools the file references for documentation purposes.
  command -v "$bin" >/dev/null 2>&1 || continue
  read -ra chainarr <<<"$chainstr"
  "$VERIFIER" --quiet "$bin" "${chainarr[@]}" "$flag" 2>/dev/null
  rc=$?
  # Exit 1 = flag absent (likely hallucinated); 2 = unverifiable, treat as
  # neutral (don't flag — could be tool not on this machine, transient
  # --help failure, or a subcommand whose --help is not parseable). Only
  # collect exit-1 cases as failures.
  if [[ "$rc" -eq 1 ]]; then
    FAILURES+=("$key")
  fi
done

# Build the telemetry findings array + repo-relative file path, both gated on a
# wired sink so the unwired default path spawns no telemetry-only subprocess.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local file_rel="$FILE" findings_json="[]"
  if command -v cygpath >/dev/null 2>&1; then
    local _file_lm _root_lm
    _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
    _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
    [[ -n "$_file_lm" && -n "$_root_lm" ]] && file_rel="${_file_lm#"$_root_lm"/}"
  else
    file_rel="${FILE#"$REPO_ROOT"/}"
  fi
  # Redaction: if the path could not be made repo-relative, emit the basename
  # only — never an absolute path (it would embed the developer's username).
  case "$file_rel" in
  /* | [A-Za-z]:*)
    file_rel="${file_rel##*/}"
    file_rel="${file_rel##*\\}"
    ;;
  *) ;;
  esac
  if ((${#FAILURES[@]} > 0)); then
    local f raw="" bin rest chainstr flag disp
    for f in "${FAILURES[@]}"; do
      bin="${f%%|*}"
      rest="${f#*|}"
      chainstr="${rest%|*}"
      flag="${rest##*|}"
      [[ -n "$chainstr" ]] && disp="$bin $chainstr $flag" || disp="$bin $flag"
      raw+="$disp"$'\n'
    done
    findings_json=$(printf '%s' "$raw" | jq -R . | jq -s . 2>/dev/null) || findings_json="[]"
  fi
  local data
  data=$(jq -n --arg file "$file_rel" --argjson findings "$findings_json" \
    '{tool:"",file:$file,findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "cli-flag-verify" "PostToolUse" "ok" "$start" "$data" "$REPO_ROOT"
}

if ((${#FAILURES[@]} > 0)); then
  hook::ctx_append "cli-flag-verify: ${#FAILURES[@]} unknown flag(s) in $FILE"
  hook::ctx_append "Possible hallucination — verify against the binary's actual --help output:"
  for f in "${FAILURES[@]}"; do
    bin="${f%%|*}"
    rest="${f#*|}"
    chainstr="${rest%|*}"
    flag="${rest##*|}"
    if [[ -n "$chainstr" ]]; then
      disp="$bin $chainstr $flag"
      helpref="$bin $chainstr --help"
    else
      disp="$bin $flag"
      helpref="$bin --help"
    fi
    hook::ctx_append "  UNKNOWN_FLAG: $disp (not found in '$helpref')"
    hook::ctx_append "    fix:   run '$helpref' and confirm the flag exists"
    hook::ctx_append "    skip:  add $bin to the guardrails cli_flag_verify_skip_bins option"
  done
  hook::ctx_append ""
  hook::ctx_append "Subagent / training-recall flag claims are unverified — confirm"
  hook::ctx_append "against the binary's --help before relying on the flag."
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0
