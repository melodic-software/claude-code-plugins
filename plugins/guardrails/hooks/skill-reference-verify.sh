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
# a repo with a `plugins/` directory containing at least one `.claude-plugin/`
# manifest — i.e. a marketplace repo. Outside one there is no local authority to
# resolve a reference against, so the guard stays silent rather than guessing.
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

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "SKILL_REFERENCE_VERIFY"

hook::ctx_reset

INPUT=$(hook::buffer_stdin) || exit 0

hook::require_jq "PostToolUse" "guardrails-skill-reference-verify" "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
# A CHANGELOG is an append-only historical record: an entry saying a skill was
# renamed MUST keep naming the old command, so every rename permanently adds an
# unresolvable reference to one. Measured on this repo: 56 of 63 findings (89%)
# were CHANGELOG rename entries, all correct as written, and excluding them moves
# the guard from 3.4% of files firing at 6% precision to 0.5% firing at 57%.
#
# Deliberately narrow. `docs/topics/*/PLAN.md` completion records are arguably the
# same shape, but two of the four real findings on this corpus live there — a
# broader "historical by contract" rule would cost half the signal.
*/CHANGELOG.md | CHANGELOG.md) exit 0 ;;
*.md) ;;
*) exit 0 ;;
esac

# Diff-scope: verify only the content THIS tool call wrote, never re-read the
# whole file from disk.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null | tr -d '\r')
# Edit's `replace_all` (documented at
# https://code.claude.com/docs/en/tools-reference — Edit requires `old_string` to
# occur exactly once, and `replace_all: true` is how Claude edits every occurrence
# instead). Reconstruction needs it: with `replace_all` the same `new_string`
# lands in several places on purpose, so several matches are the edit's own
# footprint rather than an ambiguity. Absent or false on every ordinary Edit.
REPLACE_ALL=false
case "$TOOL" in
Edit)
  SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | tr -d '\r')
  REPLACE_ALL=$(printf '%s' "$INPUT" | jq -r '(.tool_input.replace_all // false) | tostring' 2>/dev/null | tr -d '\r')
  ;;
Write) SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null | tr -d '\r') ;;
*) exit 0 ;;
esac
[[ -n "$SCAN_CONTENT" ]] || exit 0

REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"
PLUGINS_DIR="$REPO_ROOT/plugins"

# PLUGINS-ROOT GATE. Outside a marketplace repo there is no local authority.
[[ -d "$PLUGINS_DIR" ]] || exit 0
shopt -s nullglob
manifests=("$PLUGINS_DIR"/*/.claude-plugin/plugin.json)
shopt -u nullglob
((${#manifests[@]} > 0)) || exit 0

# A plugin's command namespace is its manifest `name`, which need not equal its
# directory name. Build the name → directory map from the manifests themselves so
# a renamed directory or a name override resolves correctly.
#
# The manifest also decides WHERE that plugin's skills live. Its `skills` key
# holds a path or an array of paths, each relative to the plugin root, and those
# ADD to the conventional `skills/` directory rather than replacing it — verified
# against the Plugins reference (<https://code.claude.com/docs/en/plugins-reference>,
# "Path behavior rules", fetched 2026-08-06). Collect them per plugin so a skill
# loaded from a declared location resolves like any other.
#
# One documented exception is NOT modelled: for a marketplace entry whose `source`
# resolves to the marketplace root, declared subdirectories REPLACE the default
# `skills/` scan. Modelling it would mean reading marketplace.json to learn how
# each entry resolves, and the cost of not modelling it is bounded — the default
# stays in the search set, so at worst a reference resolves that Claude Code would
# not offer and this advisory stays quiet. Staying quiet is the failure this guard
# is allowed to have; a false alarm is not.
declare -A PLUGIN_DIR=() PLUGIN_SKILL_PATHS=()
for m in "${manifests[@]}"; do
  pdir="${m%/.claude-plugin/plugin.json}"
  pname=$(jq -r '.name // empty' "$m" 2>/dev/null | tr -d '\r')
  [[ -n "$pname" ]] || pname="${pdir##*/}"
  PLUGIN_DIR["$pname"]="$pdir"
  PLUGIN_SKILL_PATHS["$pname"]=$(
    jq -r '.skills // empty | if type == "array" then .[] else . end' "$m" 2>/dev/null | tr -d '\r'
  )
done

# Extract a plugin skill's frontmatter `name`, or nothing when it declares none.
# Tolerates quoting and a trailing YAML comment (`name: renamed # public
# command`); comments are stripped first so the value pattern stays anchored to
# end-of-line.
skill_frontmatter_name() {
  sed -n '1,40p' "$1" 2>/dev/null |
    sed -E 's/[[:space:]]+#.*$//' |
    sed -nE 's/^name:[[:space:]]*"?'"'"'?([A-Za-z0-9_-]+)"?'"'"'?[[:space:]]*$/\1/p' |
    head -1
}

# The directories a plugin's skills are loaded from: the conventional `skills/`,
# plus every path its manifest declares, plus the plugin root when the manifest
# declares nothing and the root itself is the skill.
#
# All three shapes come from the Plugins reference
# (<https://code.claude.com/docs/en/plugins-reference>, fetched 2026-08-06):
# declared paths are relative to the plugin root and start with `./` (the `skills`
# key also accepts `.`, and both `.` and `./` denote the root); they ADD to the
# default `skills/` scan; and a plugin with a root SKILL.md, no `skills/`
# subdirectory and no `skills` key auto-loads as a single-skill plugin. That last
# condition is honoured as written rather than widened — a root SKILL.md sitting
# beside a populated `skills/` is not loaded, and accepting it would suppress the
# advisory for a command Claude Code does not actually offer.
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

# A plugin skill's command segment comes from its frontmatter `name` when set,
# and from the directory name ONLY when it does not.
#
# The directory name is not an alias. A `skills/legacy-dir/SKILL.md` declaring
# `name: renamed` answers to `/plugin:renamed` and NOT to `/plugin:legacy-dir` —
# treating the directory as a second valid spelling would suppress the advisory
# for exactly the stale pre-rename references this guard exists to catch.
#
# A directory alone is also not a skill: it must carry a SKILL.md, or a leftover
# empty `skills/<name>/` would suppress the advisory for a command that never
# existed.
#
# A root may BE a skill directory rather than a directory of them — a declared
# path can point straight at a directory holding SKILL.md — so each root is tried
# both ways.
skill_resolves() {
  local pdir="$1" skill="$2" declared="$3" root sd sdir fname
  local -a roots=()
  skill_roots "$pdir" "$declared"
  for root in "${roots[@]}"; do
    if [[ -f "$root/$skill/SKILL.md" ]]; then
      fname=$(skill_frontmatter_name "$root/$skill/SKILL.md")
      # No declared name → the directory name IS the command segment.
      [[ -z "$fname" || "$fname" == "$skill" ]] && return 0
    fi
    if [[ -f "$root/SKILL.md" ]]; then
      fname=$(skill_frontmatter_name "$root/SKILL.md")
      sdir="${root%/}"
      if [[ -n "$fname" ]]; then
        [[ "$fname" == "$skill" ]] && return 0
      else
        [[ "${sdir##*/}" == "$skill" ]] && return 0
      fi
    fi
    for sd in "$root"/*/SKILL.md; do
      [[ -f "$sd" ]] || continue
      fname=$(skill_frontmatter_name "$sd")
      [[ -n "$fname" && "$fname" == "$skill" ]] && return 0
    done
  done
  return 1
}

# Candidate references: `/<plugin>:<skill>` inside inline-code spans only. Prose
# is not scanned — an unbackticked `/a:b` is as likely to be a URL fragment, a
# Windows drive path, or a time range as a command.
#
# The reference need not be the whole span: an invocation commonly carries
# arguments (`/plugin:skill --apply`, `/plugin:skill <target>`). Take the leading
# command token from each span rather than requiring the span to match exactly,
# or argument-bearing invocations — the common form in this repo — go unchecked.
emit_refs() {
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  printf '%s' "$SCAN_CONTENT" | grep -oE '`[^`]+`' 2>/dev/null |
    sed -E 's/^`+//; s/`+$//' |
    sed -nE 's|^(/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*)([[:space:]].*)?$|\1|p'
}

# Reconstruction is bounded on three axes, because this hook has a 30s timeout
# (hooks.json) and a guard that loses its advisory to a timeout has stopped
# guarding. A file too large to hold in a shell variable is not reconstructed at
# all; a hunk stops contributing once it has yielded this many code spans, which is
# far above any real edit given that only spans the anchor reaches are kept; and an
# anchor stops being counted one occurrence past the cap, which is all the
# uniqueness gate needs to know.
RECONSTRUCT_MAX_CHARS=4194304
RECONSTRUCT_MAX_SPANS=40
RECONSTRUCT_MAX_OCCURRENCES=40

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
    # No backtick left in the region — nothing further can open a span.
    [[ "$pre" == "$rest" ]] && return 0
    a=$((i + ${#pre}))
    after="${region:a+1}"
    inner="${after%%\`*}"
    # No closing backtick anywhere after this one: no span can open here or later.
    [[ "$inner" == "$after" ]] && return 0
    # An empty inner (an adjacent pair) or one spanning a newline is not a match
    # for grep either; it retries from the next character, so this walk does too.
    if [[ -z "$inner" || "$inner" == *$'\n'* ]]; then
      i=$((a + 1))
      continue
    fi
    b=$((a + 1 + ${#inner}))
    # The span occupies [a, b] inclusive of both backticks; the hunk [hs, he).
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
# Call as: anchor_offsets <anchor> -> $offs
# shellcheck disable=SC2154  # content and offs are the caller's frame, per the call contract
anchor_offsets() {
  local anchor="$1" alen=${#1}
  local rest="$content" base=0 pre
  offs=()
  while [[ "$rest" == *"$anchor"* ]]; do
    pre="${rest%%"$anchor"*}"
    offs+=($((base + ${#pre})))
    ((${#offs[@]} > RECONSTRUCT_MAX_OCCURRENCES)) && return 0
    base=$((base + ${#pre} + alen))
    rest="${content:base}"
  done
}

# Partial-replacement context reconstruction (Edit only). The same shape lives in
# stale-path-verify and cli-flag-verify, which still take the whole located line
# and filter it by word token (stale-path-verify was fixed for the line-anchoring
# half of this defect class by a2d98f8a); this one keeps only the part of the line
# the hunk reaches, so the three are not identical.
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
#   1. LOCATE by the hunk's own lines, never by its tokens, and only where a line
#      OCCURS exactly once in the file. A unique occurrence IS where the edit
#      landed. Anything repeated cannot say which copy that was, so it is dropped
#      rather than unioned. Exception: under `replace_all` every occurrence is a
#      place this call edited, so all are kept.
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
# What this does NOT claim: the `replace_all` branch keeps every occurrence,
# including one that pre-existed the edit and merely happens to read the same —
# nothing in the payload separates those. Reconstruction is a best effort under an
# advisory guard, not a proof that every reported line was written by this call.
#
# Cost is ONE read of the file, then in-memory scans — no subprocess per hunk line.
# The per-anchor `grep` this replaced spawned two processes per line of the hunk,
# which a large multiline Edit turned into the hook's timeout.
reconstruct_partial_edit() {
  [[ "$TOOL" == "Edit" && -f "$FILE" ]] || return 0
  local content
  content=$(<"$FILE") || return 0
  # new_string arrived with CR stripped, so a CRLF file must be searched the same
  # way or no anchor would ever locate. Offsets are read back off this normalized
  # text only, never off the bytes on disk.
  content=${content//$'\r'/}
  ((${#content} <= RECONSTRUCT_MAX_CHARS)) || return 0

  local -a anchors=()
  mapfile -t anchors < <(printf '%s' "$SCAN_CONTENT" | grep -vE '^[[:space:]]*$' 2>/dev/null)
  ((${#anchors[@]})) || return 0

  # A repeated anchor line resolves identically every time, so scan each once.
  declare -A seen=()
  local ctx="" nspan=0 anchor alen off hs he head tail
  local -a offs=()
  for anchor in "${anchors[@]}"; do
    alen=${#anchor}
    ((alen)) || continue
    [[ -n "${seen[$anchor]:-}" ]] && continue
    seen["$anchor"]=1
    anchor_offsets "$anchor"
    ((${#offs[@]})) || continue
    # A non-unique anchor cannot say WHICH occurrence the edit landed on, so it is
    # dropped rather than unioned. Cost: a missed advisory when an edit lands in
    # text that repeats verbatim elsewhere in the file. For a detect-then-judge
    # guard that is the right side of the trade — it is degraded far worse by being
    # wrong when it speaks than by staying quiet.
    [[ "$REPLACE_ALL" == "true" ]] || ((${#offs[@]} == 1)) || continue
    for off in "${offs[@]}"; do
      # The physical line the anchor sits in: back to the newline before it,
      # forward to the newline after. A reference the edit landed inside is only
      # whole when read from the line, not from the anchor alone — which is why
      # the line is read at all, and why only the part of it the anchor reaches
      # may be kept.
      head="${content:0:off}"
      head="${head##*$'\n'}"
      hs=${#head}
      tail="${content:off+alen}"
      tail="${tail%%$'\n'*}"
      he=$((hs + alen))
      collect_overlapping_spans "${content:off-hs:he+${#tail}}" "$hs" "$he"
      ((nspan >= RECONSTRUCT_MAX_SPANS)) && break 2
    done
  done
  [[ -n "$ctx" ]] || return 0

  local saved="$SCAN_CONTENT"
  SCAN_CONTENT="$ctx"
  emit_refs
  SCAN_CONTENT="$saved"
}

declare -A CHECKED=()
UNRESOLVED=()
REFS=()
mapfile -t REFS < <(emit_refs)
# Reconstruction runs on EVERY Edit, not only when the hunk yielded nothing. One
# hunk can both carry a complete reference and change a substring inside another
# (`setup and placeholder` -> `ghost` plus a literal `/alpha:setup`), so gating on
# an empty REFS would miss the partial half. Duplicates are harmless — CHECKED
# dedupes below.
if [[ "$TOOL" == "Edit" ]]; then
  mapfile -t -O "${#REFS[@]}" REFS < <(reconstruct_partial_edit)
fi

for ref in "${REFS[@]}"; do
  [[ -n "$ref" ]] || continue
  [[ -n "${CHECKED[$ref]:-}" ]] && continue
  CHECKED["$ref"]=1
  plugin="${ref#/}"
  plugin="${plugin%%:*}"
  skill="${ref##*:}"
  # PLUGIN-SCOPE GATE: only adjudicate a plugin this repo owns.
  pdir="${PLUGIN_DIR[$plugin]:-}"
  [[ -n "$pdir" ]] || continue
  skill_resolves "$pdir" "$skill" "${PLUGIN_SKILL_PATHS[$plugin]:-}" && continue
  UNRESOLVED+=("$ref")
done

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
  # Redaction: a path that could not be made repo-relative degrades to its
  # basename — never an absolute path, which would embed the developer's
  # username.
  case "$file_rel" in
  /* | [A-Za-z]:*)
    file_rel="${file_rel##*/}"
    file_rel="${file_rel##*\\}"
    ;;
  *) ;;
  esac
  if ((${#UNRESOLVED[@]} > 0)); then
    local r raw_list=""
    for r in "${UNRESOLVED[@]}"; do raw_list+="$r"$'\n'; done
    findings_json=$(printf '%s' "$raw_list" | jq -R . | jq -s . 2>/dev/null) || findings_json="[]"
  fi
  local data
  data=$(jq -n --arg file "$file_rel" --argjson findings "$findings_json" \
    '{tool:"",file:$file,findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "skill-reference-verify" "PostToolUse" "ok" "$start" "$data" "$REPO_ROOT"
}

if ((${#UNRESOLVED[@]} > 0)); then
  hook::ctx_append "skill-reference-verify: ${#UNRESOLVED[@]} skill reference(s) do not resolve in $FILE"
  hook::ctx_append "This repo owns each plugin named below, so it can say the skill is not there:"
  for r in "${UNRESOLVED[@]}"; do
    plugin="${r#/}"
    plugin="${plugin%%:*}"
    hook::ctx_append "  UNRESOLVED_SKILL: $r (no such skill under plugins/${PLUGIN_DIR[$plugin]##*/}/skills/)"
  done
  hook::ctx_append ""
  hook::ctx_append "Detect-then-judge: this is a prompt for your verdict, not a determination."
  hook::ctx_append "Confirm against the tree. A reference retained deliberately — documenting"
  hook::ctx_append "a rename, or a capability another marketplace ships — is correct as written."
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0
