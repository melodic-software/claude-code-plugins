#!/usr/bin/env bash
# PostToolUse hook: verify `/<plugin>:<skill>` references written to markdown
# resolve to a skill that exists in the working tree.
# Triggered on Write|Edit of *.md files.
#
# Catches subagent / training-recall hallucinations — a slash-command reference
# written AS a capability that does not exist, or one left behind by a rename.
# Sibling of cli-flag-verify and stale-path-verify: same defect class, third
# oracle.
#
# ENFORCEABILITY TIER: Detect-then-judge — ADVISORY PLUS A HUMAN VERDICT, never
# an auto-fix. Globbing a plugins tree is exact only inside a marketplace repo
# that owns the referenced plugin. In a consuming repo the reference may name a
# plugin from another marketplace, or one the operator has simply not installed,
# and this hook cannot distinguish that from a hallucination. Per the org
# convention on enforceability tiers, that means the finding is a prompt for a
# human decision, not a determination. The plugins-root gate below is what keeps
# the noise inside the one context where the oracle is meaningful.
#
# PLUGINS-ROOT GATE: the hook does nothing unless the file being written lives in
# a repo with a `plugins/` directory containing at least one `.claude-plugin/`,
# `.codex-plugin/` or `.cursor-plugin/` manifest — i.e. a marketplace repo.
# Outside one there is no local authority to resolve a reference against, so
# the guard stays silent rather than guessing.
#
# PLUGIN-SCOPE GATE: within a marketplace repo, a reference is only adjudicated
# when its PLUGIN half resolves locally. `/some-other-marketplace:thing` is left
# alone; `/guardrails:nonexistent` is reported, because this repo owns
# `guardrails` and can therefore say the skill is not there.
#
# NON-BLOCKING (advisory): exits 0 with hookSpecificOutput additionalContext.
#
# Disable with the skill_reference_verify_enabled userConfig option set to false.

set -uo pipefail

start=${EPOCHREALTIME:-}

[[ "${CLAUDE_PLUGIN_OPTION_SKILL_REFERENCE_VERIFY_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary skill-reference-verify PostToolUse open 0
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

hook::ctx_reset

hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PostToolUse" guardrails "$INPUT"

FILE=""
hook::read_file_path_to FILE "$INPUT" || exit 0
case "$FILE" in
*/CHANGELOG.md | CHANGELOG.md) exit 0 ;;
*.md) ;;
*) exit 0 ;;
esac

FILE_DIR="${FILE%/*}"
[[ "$FILE_DIR" == "$FILE" ]] && FILE_DIR="."
[[ -n "$FILE_DIR" ]] || FILE_DIR=/
REPO_ROOT="" REPO_ROOT_RESOLVED=1
hook::repo_root_to REPO_ROOT "$FILE_DIR" || REPO_ROOT_RESOLVED=0
PLUGINS_DIR="$REPO_ROOT/plugins"

[[ -d "$PLUGINS_DIR" ]] || exit 0
shopt -s nullglob
manifests=()
declare -A manifest_dirs=()
for m in "$PLUGINS_DIR"/*/.claude-plugin/plugin.json "$PLUGINS_DIR"/*/.codex-plugin/plugin.json \
  "$PLUGINS_DIR"/*/.cursor-plugin/plugin.json; do
  pdir="${m%/.*-plugin/plugin.json}"
  [[ -n "${manifest_dirs[$pdir]:-}" ]] && continue
  manifest_dirs[$pdir]=1
  manifests+=("$m")
done
shopt -u nullglob
((${#manifests[@]} > 0)) || exit 0

# Diff-scope: verify only the content THIS tool call wrote, never re-read the
# whole file from disk.
#
# Every payload field this hook can need, in ONE jq process (hook::jq_fields),
# not three — a jq spawn is fork() emulation on Windows Git Bash. Both per-tool
# content fields and replace_all are fetched together because selecting between
# them would cost another process; jq reads the same envelope either way, and the
# tool-specific choice happens below in the shell. `replace_all` keeps its
# `// false | tostring` INSIDE the filter: hook::jq_fields wraps each filter in
# `// ""`, and jq's `//` treats the boolean false as empty, so a bare
# `.tool_input.replace_all` would come back "" instead of "false". That is kept
# for parity with the pre-conversion output, not because a branch depends on it
# — every consumer below tests `== "true"`, which "" and "false" fail alike.
# Failure semantics are unchanged: a missing jq or an unparsable payload yields
# rc 1 here, which exits 0 exactly as the unmatched-TOOL case did —
# hook::require jq above has already made the degraded state visible once per
# session and agent.
hook::jq_fields "$INPUT" '.tool_name' '.tool_input.new_string' \
  '.tool_input.content' '.tool_input.replace_all // false | tostring' \
  '[(.tool_response | objects | .structuredPatch)[]?.lines[]?
    | select(type == "string" and startswith("+")) | .[1:]] | join("\n")' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
EDIT_WROTE_LINES=""
REPLACE_ALL=false
case "$TOOL" in
Edit)
  SCAN_CONTENT="${HOOK_JQ_FIELDS[1]}"
  REPLACE_ALL="${HOOK_JQ_FIELDS[3]}"
  case "$REPLACE_ALL" in
  true | false) ;;
  *)
    exit 0
    ;;
  esac
  EDIT_WROTE_LINES="${HOOK_JQ_FIELDS[4]}"
  ;;
Write) SCAN_CONTENT="${HOOK_JQ_FIELDS[2]}" ;;
*) exit 0 ;;
esac
[[ -n "$SCAN_CONTENT" ]] || exit 0

srv_git_dir_to() {
  local g="$REPO_ROOT/.git" line
  if [[ -d "$g" ]]; then
    printf -v "$1" '%s' "$g"
    return 0
  fi
  if [[ -f "$g" ]]; then
    IFS= read -r line <"$g" || return 1
    line=${line%$'\r'}
    [[ "$line" == 'gitdir:'* ]] || return 1
    line=${line#gitdir:}
    line=${line#"${line%%[![:space:]]*}"}
    if [[ "$line" != /* && "$line" != [A-Za-z]:[/\\]* ]]; then
      line="$REPO_ROOT/$line"
    fi
    printf -v "$1" '%s' "$line"
    return 0
  fi
  return 1
}

declare -A PLUGIN_DIR=() PLUGIN_SKILL_PATHS=()
PLUGIN_INDEX_BUILT=0
build_plugin_index() {
  ((PLUGIN_INDEX_BUILT)) && return 0
  PLUGIN_INDEX_BUILT=1
  local m pdir pname paths line body git_dir="" cache_file="" use_cache=0 i start last
  local -a rows=() hdr=()
  local -A seen=()
  if srv_git_dir_to git_dir; then
    cache_file="$git_dir/guardrails-skill-index"
  fi
  if [[ -n "$cache_file" && -f "$cache_file" ]]; then
    mapfile -t hdr <"$cache_file"
    start=$((${#manifests[@]} + 2))
    last=$((${#hdr[@]} - 1))
    if [[ "${hdr[0]-}" == "${#manifests[@]}" ]]; then
      use_cache=1
      for ((i = 0; i < ${#manifests[@]}; i++)); do
        [[ "${hdr[i + 1]-}" == "${manifests[i]}" ]] || use_cache=0
        [[ "$cache_file" -nt "${manifests[i]}" ]] || use_cache=0
      done
      [[ "${hdr[${#manifests[@]} + 1]-}" == '---' ]] || use_cache=0
      ((last >= start)) && [[ "${hdr[last]}" == "end $((last - start))" ]] || use_cache=0
      if ((use_cache && last > start)); then
        rows=("${hdr[@]:start:last-start}")
        for line in "${rows[@]}"; do
          [[ "$line" == "end "[0-9]* ]] && use_cache=0
        done
      fi
    fi
  fi
  if ((!use_cache)); then
    rows=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      rows+=("$line")
    done < <(
      jq -r '[input_filename, (.name // "" | tostring),
              ((.skills // null) | if . == null then ""
                elif type == "array" then map(tostring) | join("\u001f")
                else tostring end)] | join("\u001e")' "${manifests[@]}" 2>/dev/null
    )
    if [[ -n "$cache_file" ]]; then
      printf -v body '%s\n' "${#manifests[@]}" "${manifests[@]}" '---' ${rows[@]+"${rows[@]}"}
      printf '%send %d\n' "$body" "${#rows[@]}" 2>/dev/null >"$cache_file" || :
    fi
  fi
  for line in ${rows[@]+"${rows[@]}"}; do
    [[ -n "$line" ]] || continue
    IFS=$'\x1e' read -r m pname paths <<<"$line"
    m="${m//$'\r'/}"
    [[ -n "$m" ]] || continue
    m="${m%[/\\]plugin.json}"
    m="${m%[/\\].*-plugin}"
    m="${m##*/}"
    m="${m##*\\}"
    pdir="$PLUGINS_DIR/$m"
    pname="${pname//$'\r'/}"
    [[ -n "$pname" ]] || pname="${pdir##*/}"
    PLUGIN_DIR["$pname"]="$pdir"
    paths="${paths//$'\r'/}"
    PLUGIN_SKILL_PATHS["$pname"]="${paths//$'\x1f'/$'\n'}"
    seen["$pdir"]=1
  done
  for m in "${manifests[@]}"; do
    pdir="${m%/.*-plugin/plugin.json}"
    [[ -n "${seen[$pdir]:-}" ]] && continue
    pname=$(jq -r '.name // empty' "$m" 2>/dev/null | tr -d '\r')
    [[ -n "$pname" ]] || pname="${pdir##*/}"
    PLUGIN_DIR["$pname"]="$pdir"
    PLUGIN_SKILL_PATHS["$pname"]=$(
      jq -r '.skills // empty | if type == "array" then .[] else . end' "$m" 2>/dev/null | tr -d '\r'
    )
  done
}

skill_frontmatter_name() {
  sed -n '1,40p' "$1" 2>/dev/null |
    sed -nE 's/[[:space:]]+#.*$//; s/^name:[[:space:]]*"?'"'"'?([A-Za-z0-9_-]+)"?'"'"'?[[:space:]]*$/\1/p' |
    head -1
}

# The directories a plugin's skills are loaded from: the conventional `skills/`,
# plus every path its manifest declares, plus the plugin root when the manifest
# declares nothing and the root itself is the skill.
#
# All three shapes follow the plugin manifest reference rather than recall: we
# resolve declared paths against the plugin root, read `.` and `./` as the root
# itself, add them to the default `skills/` scan, and take the root as the
# skill only under the single-skill condition. That condition is honored as
# written rather than widened, because widening it would suppress the advisory
# for a command Claude Code does not actually offer. Pointers:
# https://code.claude.com/docs/en/plugins/manifest-reference#path-rules,
# https://code.claude.com/docs/en/plugins/manifest-reference#how-each-key-combines-with-its-default-location,
# https://code.claude.com/docs/en/plugins/manifest-reference#standard-layout.
#
# Call as: skill_roots <plugin-dir> <declared-paths> -> $roots
# shellcheck disable=SC2154  # roots is the caller's frame, per the call contract
skill_roots() {
  local pdir="$1" declared="$2" rel
  roots=("$pdir/skills")
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    rel="${rel#./}"
    rel="${rel%/}"
    if [[ -z "$rel" || "$rel" == "." ]]; then roots+=("$pdir"); else roots+=("$pdir/$rel"); fi
  done <<<"$declared"
  [[ -z "$declared" && ! -d "$pdir/skills" && -f "$pdir/SKILL.md" ]] && roots+=("$pdir")
  return 0
}

skill_resolves() {
  local pdir="$1" skill="$2" declared="$3" root sd sdir fname
  local -a roots=()
  skill_roots "$pdir" "$declared"
  for root in "${roots[@]}"; do
    if [[ -f "$root/$skill/SKILL.md" ]]; then
      fname=$(skill_frontmatter_name "$root/$skill/SKILL.md")
      [[ -z "$fname" || "$fname" == "$skill" ]] && return 0
    fi
    if [[ -f "$root/SKILL.md" ]]; then
      fname=$(skill_frontmatter_name "$root/SKILL.md")
      sdir="${root%/}"
      [[ "${fname:-${sdir##*/}}" == "$skill" ]] && return 0
    fi
    for sd in "$root"/*/SKILL.md; do
      [[ -f "$sd" ]] || continue
      fname=$(skill_frontmatter_name "$sd")
      [[ "$fname" == "$skill" ]] && return 0
    done
  done
  return 1
}

emit_refs() {
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  printf '%s' "$1" | grep -oE '`[^`]+`' 2>/dev/null |
    sed -E 's/^`+//; s/`+$//' |
    sed -nE 's|^(/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*)([[:space:]].*)?$|\1|p'
}

RECONSTRUCT_MAX_CHARS=131072
RECONSTRUCT_MAX_SPANS=40
RECONSTRUCT_MAX_OCCURRENCES=40
RECONSTRUCT_FALLBACK_SCAN_BUDGET=60000

# Append to the caller's $ctx every inline-code span in <region> whose extent
# OVERLAPS [<hunk-start>, <hunk-end>), and count them in the caller's $nspan.
#
# Span boundaries are exactly the ones emit_refs' own `\`[^\`]+\`` finds, so what
# is kept here and what is parsed there cannot disagree: leftmost match, at least
# one character between the backticks (an adjacent pair opens nothing), and never
# across a newline, since grep matches within a line.
#
# Call as: collect_overlapping_spans <region> <hunk-start> <hunk-end>
# shellcheck disable=SC2154  # ctx and nspan are the caller's frame, per the docblock
collect_overlapping_spans() {
  local region="$1" hs="$2" he="$3"
  local i=0 a b rest pre after inner
  while :; do
    rest="${region:i}"
    pre="${rest%%\`*}"
    [[ "$pre" == "$rest" ]] && return 0
    a=$((i + ${#pre}))
    after="${region:a+1}"
    inner="${after%%\`*}"
    [[ "$inner" == "$after" ]] && return 0
    if [[ -z "$inner" || "$inner" == *$'\n'* ]]; then
      i=$((a + 1))
      continue
    fi
    b=$((a + 1 + ${#inner}))
    if ((a < he && b >= hs)); then
      ctx+="\`$inner\`"$'\n'
      ((++nspan >= RECONSTRUCT_MAX_SPANS)) && return 0
    fi
    i=$((b + 1))
  done
}

# Locate every occurrence of <anchor> in the caller's $content, into the caller's
# $offs. Stops one past the occurrence cap: the uniqueness gate only needs to know
# whether there is more than one, and `replace_all` stops contributing context at
# the cap anyway.
#
# Occurrences, not matching lines. Counting lines is not enough: two occurrences
# on one physical line are a single line, and that is a real shape — inserting
# `legacy` into a line that already carries an untouched `` `/alpha:ghost-legacy` ``
# leaves the anchor twice on that line, and reporting the reference would be an
# advisory about text this call never wrote.
#
# ONE pattern operation per iteration. `${rest%%"$anchor"*}` both tests and locates:
# it returns $rest unchanged when there is no match, and a literal `==` on that
# result is a memcmp, not a second search. Asking `[[ $rest == *"$anchor"* ]]` first
# and then stripping searched the same text twice, which doubled the cost of the
# whole-hunk locate — where the anchor is the size of the edit and the search is the
# dominant term.
#
# Call as: anchor_offsets <anchor> -> $offs
# shellcheck disable=SC2154  # content and offs are the caller's frame, per the call contract
anchor_offsets() {
  local anchor="$1" alen=${#1}
  local rest="$content" base=0 pre
  offs=()
  while :; do
    pre="${rest%%"$anchor"*}"
    [[ "$pre" == "$rest" ]] && return 0
    offs+=($((base + ${#pre})))
    ((${#offs[@]} > RECONSTRUCT_MAX_OCCURRENCES)) && return 0
    base=$((base + ${#pre} + alen))
    rest="${content:base}"
  done
}

# Partial-replacement context reconstruction (Edit only). The same shape lives in
# stale-path-verify and cli-flag-verify, which still take the whole located line
# and filter it by word token; this one keeps only the part of the line the hunk
# reaches, so the three are not identical.
#
# An Edit may replace an arbitrary substring: swapping `setup` for `ghost` inside
# an existing `/alpha:setup` leaves `/alpha:ghost` on disk, but the hunk is the
# bare word `ghost` and carries no command for emit_refs to find, so a
# newly-broken reference would be silently missed.
#
# Recover bounded context POSITIONALLY. The edit is already applied by PostToolUse
# time, so every line of new_string is on disk verbatim and its own text locates
# the exact span of the file this call wrote. Diff-scope is then an overlap test
# rather than a word-token heuristic. Two gates:
#
#   1. LOCATE by the hunk's own text, never by its tokens, and only where that text
#      OCCURS exactly once in the file. A unique occurrence IS where the edit
#      landed. Anything repeated cannot say which copy that was, so it is dropped
#      rather than unioned. Exception: under `replace_all` every occurrence is a
#      place this call edited, so all are kept. The hunk is located WHOLE, falling
#      back to line by line only when the whole no longer matches.
#   2. KEEP only the inline-code spans whose extent OVERLAPS the located anchor.
#
# Gate 2 is what a word-token filter could never be: exact. Sharing a physical line
# with the hunk is not evidence the edit wrote a reference, so a span the anchor
# does not reach is dropped no matter how many words it happens to share with the
# hunk. And overlap has no minimum length to clear, so an Edit replacing two
# characters inside a command segment is scoped as precisely as one replacing
# twenty — where the token filter, needing a token long enough to filter on, simply
# produced none and gave up.
#
#   3. Under `replace_all` ONLY, keep an occurrence just when its physical line is
#      one `structuredPatch` reports the call as having WRITTEN. Gate 1's
#      uniqueness rule is what separates an edited occurrence from a coincidental
#      one everywhere else, and `replace_all` is exactly where that rule is
#      suspended — so it is the one branch that needs an external witness.
#
# Gate 3 may only ever REMOVE an occurrence when it can positively identify at
# least one the call wrote. Comparison is whitespace-normalized, and if the
# witness recognizes no occurrence at all it abstains and the unfiltered set
# stands. Both exist for the same reason: an earlier-ordered PostToolUse hook can
# reformat the file between the write and this read — the case the per-line
# fallback above was built for — and a witness compared to rewritten text would
# otherwise turn this gate from a filter into a silent mute, dropping a genuinely
# written reference. Normalization covers the whitespace reflow formatters
# actually do; the abstain covers everything else.
#
# What this does NOT claim, still. The witness is per LINE, so two references on
# one physical line stand or fall together, and an untouched line whose text
# duplicates an edited one verbatim is kept — nothing separates two identical
# lines. A multi-line `new_string` is not filtered at all: its anchor extent spans
# several lines and matches no single patch line. Where `structuredPatch` is absent
# (an older harness, or any payload without `tool_response`) the filter is inert by
# construction. Every one of those degrades to the pre-gate behavior, which is
# over-reporting — the direction this guard already accepts — never under-reporting.
# Reconstruction remains a best effort under an advisory guard, not a proof that
# every reported line was written by this call; it simply no longer reports a line
# the payload itself says was untouched.
#
# Cost is ONE read of the file and, normally, ONE scan of it — no subprocess per
# hunk line and no rescan per hunk line either. The `grep` this replaced spawned two
# processes per line of the hunk; scanning in-memory removed the processes but left
# the per-line rescan, which is anchors TIMES file size and still spent the timeout
# on a thousand-line hunk. Locating the hunk whole is what removes the factor; the
# scanning budget bounds the fallback that cannot.
# The physical line an anchor occurrence sits in: back to the newline before it,
# forward to the newline after. A reference the edit landed inside is only whole
# when read from the line, not from the anchor alone — which is why the line is
# read at all, and why only the part of it the anchor reaches may be kept.
#
# Reads the caller's $content, $alen; sets the caller's $line, $hs, $he. Written
# as a function because Gate 3 needs the line one pass before the span walk does,
# and computing it twice from two copies of this arithmetic is how the two drift.
# Call as: anchor_line <offset> -> $line $hs $he
# shellcheck disable=SC2154  # content/alen/line/hs/he are the caller's frame, per the call contract
anchor_line() {
  local off="$1" head tail
  head="${content:0:off}"
  head="${head##*$'\n'}"
  hs=${#head}
  tail="${content:off+alen}"
  tail="${tail%%$'\n'*}"
  he=$((hs + alen))
  line="${content:off-hs:he+${#tail}}"
}

norm_ws() {
  local s="${1//$'\t'/ }"
  while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
  s="${s#"${s%%[![:space:]]*}"}"
  NORM_WS="${s%"${s##*[![:space:]]}"}"
}

reconstruct_partial_edit() {
  [[ "$TOOL" == "Edit" && -f "$FILE" ]] || return 0
  local +x LC_ALL=C
  local content
  content=$(<"$FILE") || return 0
  ((${#content} <= RECONSTRUCT_MAX_CHARS)) || return 0
  content=${content//$'\r'/}

  local ctx="" nspan=0 anchor alen off hs he line cap kib located_whole=0
  local -a offs=() anchors=() keep=()

  local -A wrote=()
  local filter_wrote=0 wl NORM_WS
  if [[ "$REPLACE_ALL" == "true" && -n "$EDIT_WROTE_LINES" ]]; then
    while IFS= read -r wl; do
      norm_ws "$wl"
      wrote["L$NORM_WS"]=1
    done <<<"$EDIT_WROTE_LINES"
    ((${#wrote[@]})) && filter_wrote=1
  fi

  anchor_offsets "$SCAN_CONTENT"
  if ((${#offs[@]})) && { [[ "$REPLACE_ALL" == "true" ]] || ((${#offs[@]} == 1)); }; then
    anchors=("$SCAN_CONTENT")
    located_whole=1
  else
    mapfile -t anchors < <(printf '%s' "$SCAN_CONTENT" | grep -vE '^[[:space:]]*$' 2>/dev/null)
    ((${#anchors[@]})) || return 0
    kib=$(((${#content} + 1023) / 1024))
    ((kib < 1)) && kib=1
    cap=$((RECONSTRUCT_FALLBACK_SCAN_BUDGET / (kib * kib)))
    ((cap < 1)) && cap=1
    ((${#anchors[@]} > cap)) && anchors=("${anchors[@]:0:cap}")
  fi

  declare -A seen=()
  for anchor in "${anchors[@]}"; do
    alen=${#anchor}
    ((alen)) || continue
    [[ -n "${seen[$anchor]:-}" ]] && continue
    seen["$anchor"]=1
    if ((located_whole)); then located_whole=0; else anchor_offsets "$anchor"; fi
    ((${#offs[@]})) || continue
    [[ "$REPLACE_ALL" == "true" ]] || ((${#offs[@]} == 1)) || continue

    keep=("${offs[@]}")
    if ((filter_wrote)) && [[ "$anchor" != *$'\n'* ]]; then
      keep=()
      for off in "${offs[@]}"; do
        anchor_line "$off"
        norm_ws "$line"
        [[ -n "${wrote[L$NORM_WS]:-}" ]] && keep+=("$off")
      done
      ((${#keep[@]})) || keep=("${offs[@]}")
    fi

    for off in "${keep[@]}"; do
      anchor_line "$off"
      collect_overlapping_spans "$line" "$hs" "$he"
      ((nspan >= RECONSTRUCT_MAX_SPANS)) && break 2
    done
  done
  [[ -n "$ctx" ]] || return 0
  emit_refs "$ctx"
}

declare -A CHECKED=()
UNRESOLVED=()
REFS=()
mapfile -t REFS < <(emit_refs "$SCAN_CONTENT")
if [[ "$TOOL" == "Edit" ]]; then
  mapfile -t -O "${#REFS[@]}" REFS < <(reconstruct_partial_edit)
fi

((${#REFS[@]})) && build_plugin_index

for ref in "${REFS[@]}"; do
  [[ -n "$ref" ]] || continue
  [[ -n "${CHECKED[$ref]:-}" ]] && continue
  CHECKED["$ref"]=1
  plugin="${ref#/}"
  plugin="${plugin%%:*}"
  skill="${ref##*:}"
  pdir="${PLUGIN_DIR[$plugin]:-}"
  [[ -n "$pdir" ]] || continue
  skill_resolves "$pdir" "$skill" "${PLUGIN_SKILL_PATHS[$plugin]:-}" && continue
  UNRESOLVED+=("$ref")
done

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local findings_json="[]" file_rel=""
  hook::repo_relative_path_to file_rel "$FILE" "$REPO_ROOT"
  if ((${#UNRESOLVED[@]} > 0)); then
    findings_json=$(printf '%s\n' "${UNRESOLVED[@]}" | jq -Rn '[inputs]' 2>/dev/null) || findings_json="[]"
  fi
  local data
  data=$(jq -n --arg file "$file_rel" --argjson findings "$findings_json" \
    '{tool:"",file:$file,findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "skill-reference-verify" "PostToolUse" "ok" "$start" "$data" "$REPO_ROOT"
}

if ((${#UNRESOLVED[@]} > 0)); then
  show_file="$FILE"
  ((REPO_ROOT_RESOLVED)) && [[ "$FILE" == "${REPO_ROOT%/}/"?* ]] && show_file="${FILE#"${REPO_ROOT%/}/"}"
  lines=""
  declare -a roots=()
  for r in "${UNRESOLVED[@]}"; do
    plugin="${r#/}"
    plugin="${plugin%%:*}"
    skill_roots "${PLUGIN_DIR[$plugin]}" "${PLUGIN_SKILL_PATHS[$plugin]:-}"
    searched=""
    for root in "${roots[@]}"; do
      searched+="${searched:+, }plugins/${root#"$PLUGINS_DIR/"}/"
    done
    lines+="$r (no such skill under $searched)"$'\n'
  done
  srv_ctx=""
  hook::findings_to srv_ctx \
    "skill-reference-verify: skill reference(s) in $show_file do not resolve; this repo owns the plugin:" \
    "$lines" --max 10
  hook::ctx_append "$srv_ctx"
  hook::ctx_append "A reference kept on purpose (a rename record, another marketplace's skill) is correct as written."
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0
