#!/usr/bin/env bash
# Description-driven auto-invocation probe harness (#3526).
#
# Measures whether a skill's listing text would win the requests it should
# (and stay quiet on the ones it should not). Default method is a
# deterministic lexical listing-overlap floor that runs without a model.
# Model-graded `claude plugin eval` cases are emitted on demand; a
# replayed model run uses the same report shape so `compare` can show a
# rewrite delta.
#
# Exit 0 = success (WARN lines allowed); 1 = FAIL findings; 2 = usage /
# environment error (no jq, missing file).
#
# Usage:
#   bash measure-invocation.sh validate [--copy-span N] [--verbose] <probes-dir>
#   bash measure-invocation.sh score [--method listing-overlap] <probes-dir>
#   bash measure-invocation.sh compare <baseline.json> <treatment.json>
#   bash measure-invocation.sh emit-plugin-eval [--runs N] <probes-dir> <out-dir>
#   bash measure-invocation.sh --help
#
# validate WARNs when a should-trigger probe shares N or more consecutive
# words (default 4) with the target listing, and once per probe file naming
# every competitor whose id does not start with the file's plugin and a colon
# (--verbose: one WARN per competitor, plus each skill's listing and query
# split; the warning count is the same either way). emit-plugin-eval writes N runs
# per case: --runs, else the plugin_eval_runs setting (skill-quality.yaml, then
# skill-quality.local.yaml, in the convention home), else 3, the CLI's own
# default. compare adds a 95% paired
# normal-approximation interval on each trigger-rate delta, from per-probe
# outcomes matched by id, and an INFO line that says "within noise" when the
# interval contains 0.
#
# Probe files: <probes-dir>/*.json (not baselines/). Each file is one skill:
#   skill, plugin, skill_dir (repo-relative), competitors[], queries[]
#   query: id, split (train|validation), expect_trigger (bool), request
# A competitor's directory is plugins/<plugin>/skills/<skill> from its
# plugin:skill id; an optional competitor_dirs entry overrides it for a rival
# outside the plugins/ tree. skill_dir and competitor directories resolve
# against the repo root (MEASURE_INVOCATION_REPO_ROOT, else the
# git toplevel of this script, else $PWD). The shipped seed probes name this
# marketplace's own skills; `score` exits 2 when none of them resolve.
# Roughly 20 labeled queries per skill, both polarities, both splits.
#
# listing-overlap is a FLOOR, not a model-graded auto-invocation rate. It
# ranks the request against the target description and named competitors by
# quoted-trigger hits plus content-token overlap. The live method is
# emit-plugin-eval + `claude plugin eval`; each emitted case lists the target
# plugin and its competitors' plugins under `plugins:`, and emit exits 2 when
# one of those is not under plugins/. Replay the results through compare.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./skill-frontmatter.sh
source "$SCRIPT_DIR/skill-frontmatter.sh"

usage() {
  awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'Error: jq is required\n' >&2
  exit 2
fi

if [[ $# -lt 1 ]]; then
  printf 'Usage: measure-invocation.sh <validate|score|compare|emit-plugin-eval> ... (run with --help)\n' >&2
  exit 2
fi

fails=0
warns=0
err() {
  printf 'FAIL: %s\n' "$1" >&2
  fails=$((fails + 1))
}
warn() {
  printf 'WARN: %s\n' "$1" >&2
  warns=$((warns + 1))
}
note() { printf 'INFO: %s\n' "$1" >&2; }

repo_root() {
  if [[ -n "${MEASURE_INVOCATION_REPO_ROOT:-}" ]]; then
    printf '%s\n' "$MEASURE_INVOCATION_REPO_ROOT"
    return
  fi
  git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null && return
  printf '%s\n' "$PWD"
}

probe_files() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f -name '*.json' ! -name '.*' | sort
}

load_listing() {
  local md="$1"
  local fm desc wtu
  fm="$(skill_frontmatter::extract <"$md")"
  desc="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$fm")")"
  wtu="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$fm")")"
  printf '%s\n%s\n' "$desc" "$wtu"
}

# Quoted 'trigger phrases' plus remaining content tokens (length >= 3).
listing_tokens() {
  local text="$1"
  printf '%s\n' "$text" | skill_frontmatter::extract_triggers | sed "s/^'//;s/'$//" | tr '[:upper:]' '[:lower:]'
  printf '%s\n' "$text" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' |
    awk 'length($0) >= 3 && $0 !~ /^(the|and|for|with|when|use|this|that|from|into|not|your|our|are|was|were|has|have|had|its|but|nor|any|all|can|may|per|via|than|then|also|just|only|each|both|same|such|over|under|after|before|about)$/'
}

score_request() {
  local request="$1"
  local listing="$2"
  local req_lc listing_lc
  req_lc="$(printf '%s' "$request" | tr '[:upper:]' '[:lower:]')"
  listing_lc="$(printf '%s' "$listing" | tr '[:upper:]' '[:lower:]')"
  local quoted_hits=0
  local phrase
  while IFS= read -r phrase; do
    [[ -z "$phrase" ]] && continue
    if [[ "$req_lc" == *"$phrase"* ]]; then
      quoted_hits=$((quoted_hits + 1))
    fi
  done < <(printf '%s\n' "$listing" | skill_frontmatter::extract_triggers | sed "s/^'//;s/'$//" | tr '[:upper:]' '[:lower:]')
  local overlap=0
  local tok
  while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    if [[ "$req_lc" == *"$tok"* ]]; then
      overlap=$((overlap + 1))
    fi
  done < <(listing_tokens "$listing_lc")
  printf '%s\n' $((quoted_hits * 10 + overlap))
}

resolve_skill_md() {
  local root="$1" rel="$2"
  if [[ -f "$rel" ]]; then
    printf '%s\n' "$rel"
    return
  fi
  if [[ -f "$root/$rel/SKILL.md" ]]; then
    printf '%s\n' "$root/$rel/SKILL.md"
    return
  fi
  if [[ -f "$root/$rel" ]]; then
    printf '%s\n' "$root/$rel"
    return
  fi
  return 1
}

# positive_int <flag> <value>: exits 2 unless value is a positive integer.
positive_int() {
  if [[ ! "${2:-}" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Error: %s needs a positive integer\n' "$1" >&2
    exit 2
  fi
}

# copied_span <request> <listing> <n>: prints the first run of n consecutive
# words the request shares with the listing (lowercase, alphanumeric words).
copied_span() {
  jq -nr --arg r "$1" --arg l "$2" --argjson n "$3" '
    def words: ascii_downcase | [scan("[a-z0-9]+")];
    def grams: . as $w | [range(0; ($w | length) - $n + 1) | $w[.:. + $n] | join(" ")];
    ($l | words | grams) as $lg
    | first(($r | words | grams)[] | select(IN($lg[]))) // empty'
}

cmd_validate() {
  local span=4 verbose=0
  while [[ "${1:-}" == --* ]]; do
    case "$1" in
      --copy-span)
        positive_int --copy-span "${2:-}"
        span="$2"
        shift 2
        ;;
      --verbose)
        verbose=1
        shift
        ;;
      *)
        printf 'Error: unknown validate option %s (--copy-span N, --verbose)\n' "$1" >&2
        exit 2
        ;;
    esac
  done
  local dir="${1:-}"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    printf 'Error: validate needs a probes directory\n' >&2
    exit 2
  fi
  local root
  root="$(repo_root)"
  local f nfiles=0 unresolved=0 cross=0 cross_files=0
  local -a files
  mapfile -t files < <(probe_files "$dir")
  if [[ ${#files[@]} -eq 0 ]]; then
    err "no probe JSON files in $dir"
    return
  fi
  for f in "${files[@]}"; do
    nfiles=$((nfiles + 1))
    if ! jq -e . "$f" >/dev/null 2>&1; then
      err "$f is not valid JSON"
      continue
    fi
    local skill
    skill="$(jq -r '.skill // empty' "$f")"
    if [[ -z "$skill" ]]; then
      err "$f: missing skill"
    fi
    local plugin competitor
    local -a foreign=()
    plugin="$(jq -r '.plugin // empty' "$f")"
    if [[ -n "$plugin" ]]; then
      mapfile -t foreign < <(jq -r --arg p "$plugin:" '.competitors[]? | select((type == "string" and startswith($p)) | not) | tostring' "$f")
    fi
    if ((verbose)); then
      for competitor in ${foreign[@]+"${foreign[@]}"}; do
        warn "$f ($skill): competitor '$competitor' is not from plugin '$plugin'; a rewrite in that plugin moves this probe's listing-overlap score (fine for a live emit-plugin-eval set, which loads it as a rival)"
      done
    elif ((${#foreign[@]} > 0)); then
      # One line per file; warns still counts each competitor.
      printf "WARN: %s (%s): %s competitor(s) not from plugin '%s': %s\n" "$f" "$skill" "${#foreign[@]}" "$plugin" \
        "$(printf "'%s', " "${foreign[@]}" | sed 's/, $//')" >&2
      warns=$((warns + ${#foreign[@]}))
      cross=$((cross + ${#foreign[@]}))
      cross_files=$((cross_files + 1))
    fi
    if ! jq -e '.queries | type == "array" and length > 0' "$f" >/dev/null; then
      err "$f: queries must be a non-empty array"
      continue
    fi
    local n pos neg train val
    n="$(jq '.queries | length' "$f")"
    pos="$(jq '[.queries[] | select(.expect_trigger == true)] | length' "$f")"
    neg="$(jq '[.queries[] | select(.expect_trigger == false)] | length' "$f")"
    train="$(jq '[.queries[] | select(.split == "train")] | length' "$f")"
    val="$(jq '[.queries[] | select(.split == "validation")] | length' "$f")"
    if ((n < 8)); then
      err "$f ($skill): $n queries (need at least 8; roughly 20 is the target)"
    elif ((n < 16 || n > 24)); then
      warn "$f ($skill): $n queries (target is roughly 20)"
    fi
    if ((pos < 1)); then
      err "$f ($skill): no positive (expect_trigger: true) queries"
    fi
    if ((neg < 1)); then
      err "$f ($skill): no negative (expect_trigger: false) queries"
    fi
    if ((train < 1)); then
      err "$f ($skill): no train split"
    fi
    if ((val < 1)); then
      err "$f ($skill): no validation split"
    fi
    local dup
    dup="$(jq -r '.queries | group_by(.id) | map(select(length > 1)[0].id) | .[]?' "$f")"
    if [[ -n "$dup" ]]; then
      err "$f ($skill): duplicate query id(s): $(printf '%s' "$dup" | tr '\n' ' ')"
    fi
    local bad_expect
    bad_expect="$(jq -r '.queries[] | select(.expect_trigger | type != "boolean") | .id' "$f")"
    if [[ -n "$bad_expect" ]]; then
      err "$f ($skill): expect_trigger must be a boolean; bad id(s): $(printf '%s' "$bad_expect" | tr '\n' ' ')"
    fi
    local bad_split
    bad_split="$(jq -r '.queries[] | select(.split != "train" and .split != "validation") | .id' "$f")"
    if [[ -n "$bad_split" ]]; then
      err "$f ($skill): split must be train or validation; bad id(s): $(printf '%s' "$bad_split" | tr '\n' ' ')"
    fi
    local empty_req
    empty_req="$(jq -r '.queries[] | select((.request | type != "string") or (.request | length < 1)) | .id' "$f")"
    if [[ -n "$empty_req" ]]; then
      err "$f ($skill): empty request; id(s): $(printf '%s' "$empty_req" | tr '\n' ' ')"
    fi
    local rel md
    rel="$(jq -r '.skill_dir // empty' "$f")"
    if [[ -n "$rel" ]]; then
      if md="$(resolve_skill_md "$root" "$rel")"; then
        ((verbose)) && note "$skill: listing $md"
        local listing qid request copied
        listing="$(load_listing "$md")"
        while IFS=$'\t' read -r qid request; do
          copied="$(copied_span "$request" "$listing" "$span")"
          if [[ -n "$copied" ]]; then
            warn "$f ($skill): should-trigger probe $qid copies \"$copied\" from the listing; a probe that quotes the description measures the copy, not the trigger, so reword it"
          fi
        done < <(jq -r '.queries[] | select(.expect_trigger == true) | [.id, .request] | @tsv' "$f")
      else
        warn "$f ($skill): skill_dir '$rel' does not resolve under $root"
        unresolved=$((unresolved + 1))
      fi
    else
      warn "$f ($skill): no skill_dir; score cannot load a listing"
    fi
    ((verbose)) && note "$skill: $n queries (pos=$pos neg=$neg train=$train validation=$val)"
  done
  note "validated $nfiles probe file(s)"
  if ((cross > 0)); then
    note "$cross competitor(s) in $cross_files probe file(s) are not from the file's plugin; a rewrite in that plugin moves the probe's listing-overlap score (fine for a live emit-plugin-eval set, which loads it as a rival); --verbose prints one WARN per competitor and each skill's listing and query split"
  fi
  if ((unresolved > 0)); then
    note "$unresolved of $nfiles probe file(s) have a skill_dir that does not resolve under $root; score cannot load those listings (see reference/invocation-probes.md, Outside the marketplace checkout)"
  fi
}

cmd_score() {
  local method="listing-overlap"
  if [[ "${1:-}" == "--method" ]]; then
    if [[ -z "${2:-}" ]]; then
      printf 'Error: --method needs a value (listing-overlap)\n' >&2
      exit 2
    fi
    method="$2"
    shift 2
  fi
  if [[ "$method" != "listing-overlap" ]]; then
    printf 'Error: unknown method %s (listing-overlap is the default floor; emit-plugin-eval for the live path)\n' "$method" >&2
    exit 2
  fi
  local dir="${1:-}"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    printf 'Error: score needs a probes directory\n' >&2
    exit 2
  fi
  local root
  root="$(repo_root)"
  tmp="$(mktemp -d)"
  trap 'rm -rf -- "$tmp"' EXIT
  local f
  local -a files
  mapfile -t files < <(probe_files "$dir")
  if [[ ${#files[@]} -eq 0 ]]; then
    printf 'Error: no probe JSON files in %s\n' "$dir" >&2
    exit 2
  fi
  local pf pf_rel resolvable=0
  for pf in "${files[@]}"; do
    pf_rel="$(jq -r '.skill_dir // empty' "$pf" 2>/dev/null)"
    if [[ -n "$pf_rel" ]] && resolve_skill_md "$root" "$pf_rel" >/dev/null; then
      resolvable=$((resolvable + 1))
    fi
  done
  if ((resolvable == 0)); then
    printf 'Error: none of the %s probe file(s) in %s has a skill_dir that resolves under %s. The shipped seed probes name skills of the melodic-software marketplace checkout (plugins/<plugin>/skills/..., such as plugins/skill-quality/...) that are not present here. Pass your own probes directory (same JSON shape, skill_dir relative to your repo root or absolute), or set MEASURE_INVOCATION_REPO_ROOT to the repo root the probes name.\n' "${#files[@]}" "$dir" "$root" >&2
    exit 2
  fi
  local skill_idx=0
  local -A comp_listing
  for f in "${files[@]}"; do
    local skill plugin rel
    skill="$(jq -r '.skill' "$f")"
    plugin="$(jq -r '.plugin // empty' "$f")"
    rel="$(jq -r '.skill_dir // empty' "$f")"
    local md
    if ! md="$(resolve_skill_md "$root" "$rel")"; then
      err "$skill: cannot resolve skill_dir '$rel'"
      continue
    fi
    local listing
    listing="$(load_listing "$md")"
    for k in "${!comp_listing[@]}"; do
      unset "comp_listing[$k]"
    done
    local comp
    while IFS= read -r comp; do
      [[ -z "$comp" ]] && continue
      local comp_dir derived=""
      comp_dir="$(jq -r --arg c "$comp" '.competitor_dirs[$c] // empty' "$f")"
      if [[ -z "$comp_dir" && "$comp" == *:* ]]; then
        comp_dir="plugins/${comp%%:*}/skills/${comp#*:}"
        derived=1
      fi
      if [[ -z "$comp_dir" ]]; then
        err "$skill: competitor '$comp' is not a plugin:skill id and has no competitor_dirs entry; a partial rival set would inflate the rates"
        continue
      fi
      local cmd
      if cmd="$(resolve_skill_md "$root" "$comp_dir")"; then
        comp_listing["$comp"]="$(load_listing "$cmd")"
      elif [[ -n "$derived" ]]; then
        err "$skill: competitor '$comp' has no competitor_dirs entry and '$comp_dir' does not resolve; a partial rival set would inflate the rates"
      else
        err "$skill: competitor_dirs '$comp' -> '$comp_dir' does not resolve"
      fi
    done < <(jq -r '.competitors[]?' "$f")

    local cases_json='[]'
    local nq
    nq="$(jq '.queries | length' "$f")"
    local i
    for ((i = 0; i < nq; i++)); do
      local id split expect request
      id="$(jq -r ".queries[$i].id" "$f")"
      split="$(jq -r ".queries[$i].split" "$f")"
      expect="$(jq -r ".queries[$i].expect_trigger" "$f")"
      request="$(jq -r ".queries[$i].request" "$f")"
      local tscore
      tscore="$(score_request "$request" "$listing")"
      local winner="$skill"
      local best="$tscore"
      local predicted=true
      if ((tscore == 0)); then
        predicted=false
        winner="none"
        best=0
      fi
      local cname
      for cname in $(printf '%s\n' "${!comp_listing[@]}" | sort); do
        local cscore
        cscore="$(score_request "$request" "${comp_listing[$cname]}")"
        if ((cscore > best)); then
          best="$cscore"
          winner="$cname"
          predicted=false
        elif ((cscore == best)) && [[ "$winner" == "$skill" ]] && ((cscore > 0)); then
          # Tie with a competitor: target did not uniquely win.
          predicted=false
          winner="$skill+$cname"
        fi
      done
      local correct=false
      if [[ "$expect" == "true" && "$predicted" == "true" ]]; then
        correct=true
      elif [[ "$expect" == "false" && "$predicted" == "false" ]]; then
        correct=true
      fi
      cases_json="$(jq -c --arg id "$id" --arg split "$split" --argjson expect "$expect" \
        --argjson predicted "$predicted" --argjson correct "$correct" \
        --argjson tscore "$tscore" --arg winner "$winner" --arg request "$request" \
        '. + [{id:$id, split:$split, expect_trigger:$expect, predicted:$predicted, correct:$correct, target_score:$tscore, winner:$winner, request:$request}]' <<<"$cases_json")"
    done

    local split_json
    split_json="$(jq -c '
      def band($s; $pos):
        (.[] | select(.split == $s and .expect_trigger == $pos));
      def rate(hits; n): if n == 0 then null else (hits / n) end;
      {
        train: {
          n: [.[] | select(.split == "train")] | length,
          n_positive: [band("train"; true)] | length,
          n_negative: [band("train"; false)] | length,
          trigger_hits: [band("train"; true) | select(.predicted == true)] | length,
          false_triggers: [band("train"; false) | select(.predicted == true)] | length
        },
        validation: {
          n: [.[] | select(.split == "validation")] | length,
          n_positive: [band("validation"; true)] | length,
          n_negative: [band("validation"; false)] | length,
          trigger_hits: [band("validation"; true) | select(.predicted == true)] | length,
          false_triggers: [band("validation"; false) | select(.predicted == true)] | length
        }
      }
      | .train.trigger_rate = (if .train.n_positive == 0 then null else (.train.trigger_hits / .train.n_positive) end)
      | .train.false_trigger_rate = (if .train.n_negative == 0 then null else (.train.false_triggers / .train.n_negative) end)
      | .validation.trigger_rate = (if .validation.n_positive == 0 then null else (.validation.trigger_hits / .validation.n_positive) end)
      | .validation.false_trigger_rate = (if .validation.n_negative == 0 then null else (.validation.false_triggers / .validation.n_negative) end)
    ' <<<"$cases_json")"

    jq -n --arg skill "$skill" --arg plugin "$plugin" --arg method "$method" \
      --arg listing_file "${md#"$root"/}" --argjson splits "$split_json" --argjson cases "$cases_json" \
      '{skill:$skill, plugin:$plugin, method:$method, listing_file:$listing_file, splits:$splits, cases:$cases}' \
      >"$tmp/skill-$skill_idx.json"
    skill_idx=$((skill_idx + 1))

    local tr vr ft_t ft_v
    tr="$(jq -r '.train.trigger_rate' <<<"$split_json")"
    vr="$(jq -r '.validation.trigger_rate' <<<"$split_json")"
    ft_t="$(jq -r '.train.false_trigger_rate' <<<"$split_json")"
    ft_v="$(jq -r '.validation.false_trigger_rate' <<<"$split_json")"
    note "$skill listing-overlap  train trigger_rate=$tr false_trigger_rate=$ft_t  validation trigger_rate=$vr false_trigger_rate=$ft_v"
  done

  local generated
  generated="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ $skill_idx -eq 0 ]]; then
    printf 'Error: no skills scored\n' >&2
    exit 1
  fi
  jq -s --arg generated "$generated" --arg method "$method" \
    '{method:$method, generated_at:$generated, skills:.}' "$tmp"/skill-*.json
}

cmd_compare() {
  local base="${1:-}" treat="${2:-}"
  if [[ -z "$base" || -z "$treat" || ! -f "$base" || ! -f "$treat" ]]; then
    printf 'Error: compare needs two report JSON files\n' >&2
    exit 2
  fi
  if ! jq -e -n --slurpfile b "$base" --slurpfile t "$treat" \
    '([$b[0].skills[].skill] | sort) == ([$t[0].skills[].skill] | sort) and ($b[0].skills | length) > 0' >/dev/null; then
    printf 'Error: compare needs two reports over the same non-empty skill set\n' >&2
    return 2
  fi
  local report
  report="$(jq -n --slurpfile b "$base" --slurpfile t "$treat" '
    def delta($t; $b): if $t == null or $b == null then null else $t - $b end;
    def r3: . * 1000 | round / 1000;
    # 95% paired normal-approximation interval on the trigger-rate delta: both
    # reports score the same positive probes, so the per-probe deltas
    # (treatment hit - baseline hit, hit = predicted) are the sample. Null when
    # fewer than 2 probes pair or the positive probe ids differ between reports.
    def interval($bs; $ts; $s):
      def pos($r): [$r.cases[]? | select(.split == $s and .expect_trigger == true)];
      def hit: if .predicted == true then 1 else 0 end;
      pos($bs) as $bc | pos($ts) as $tc
      | ($bc | map(.id) | sort) as $bi
      | if $bi != ($tc | map(.id) | sort) or ($bi | length) < 2 or ($bi | unique | length) != ($bi | length)
        then null
        else ($bc | map({key: .id, value: hit}) | from_entries) as $bh
          | [$tc[] | hit - $bh[.id]] as $d
          | ($d | length) as $n
          | ($d | add / $n) as $m
          | ((($d | map(. - $m | . * .) | add) / ($n - 1)) | sqrt * 1.96 / ($n | sqrt)) as $h
          | [([$m - $h, -1] | max | r3), ([$m + $h, 1] | min | r3)] end;
    def noise($i): if $i == null then null else ($i[0] <= 0 and $i[1] >= 0) end;
    ($b[0].skills) as $bs | ($t[0].skills) as $ts |
    {
      method_baseline: $b[0].method,
      method_treatment: $t[0].method,
      skills: [
        $ts[] as $t |
        ($bs[] | select(.skill == $t.skill)) as $bb |
        def split($s):
          $bb.splits[$s] as $x | $t.splits[$s] as $y
          | interval($bb; $t; $s) as $i
          | {
              trigger_rate_baseline: $x.trigger_rate,
              trigger_rate_treatment: $y.trigger_rate,
              trigger_rate_delta: delta($y.trigger_rate; $x.trigger_rate),
              trigger_rate_delta_interval: $i,
              trigger_rate_within_noise: noise($i),
              false_trigger_rate_baseline: $x.false_trigger_rate,
              false_trigger_rate_treatment: $y.false_trigger_rate,
              false_trigger_rate_delta: delta($y.false_trigger_rate; $x.false_trigger_rate)
            };
        { skill: $t.skill, train: split("train"), validation: split("validation") }
      ]
    }
  ')" || return 2
  jq -r '.skills[] | .skill as $s | ("train", "validation") as $sp | .[$sp]
    | select(.trigger_rate_delta_interval != null)
    | "\($s) \($sp) trigger_rate delta \(.trigger_rate_delta * 1000 | round / 1000) 95% interval [\(.trigger_rate_delta_interval | join(", "))]"
      + (if .trigger_rate_within_noise then ": within noise" else "" end)' <<<"$report" |
    while IFS= read -r line; do note "$line"; done
  printf '%s\n' "$report"
}

# rival_plugins <probe-file>: distinct plugins of the plugin:skill competitors,
# sorted, without the file's own plugin.
rival_plugins() {
  jq -r '(.plugin // "") as $own
    | [.competitors[]? | select(type == "string" and contains(":")) | split(":")[0] | select(. != $own)]
    | unique[]' "$1"
}

# rel_path <from> <to>: relative path between two absolute, symlink-free paths.
rel_path() {
  local from="$1" to="$2" up=""
  while [[ -n "$from" && "$to" != "$from" && "$to" != "$from/"* ]]; do
    from="${from%/*}"
    up="../$up"
  done
  local rest="${to#"$from"}"
  rest="${up}${rest#/}"
  rest="${rest%/}"
  printf '%s\n' "${rest:-.}"
}

# plugin_eval_runs_setting <root>: prints the plugin_eval_runs key from the
# skill-quality settings layers check-skill.sh reads (<home>/skill-quality.yaml,
# then .local.yaml; <home> per lib/resolve-convention-home.sh, docs/conventions
# when no home is bound) into RUNS and its layer into RUNS_LAYER; 3 and
# "default" when no layer sets it. A layer with a value that is not a whole
# number from 1 to 999999, or that does not parse, is named in a WARN and dropped.
plugin_eval_runs_setting() {
  local root="$1" home rel value status lib="$SCRIPT_DIR/../lib"
  RUNS=3
  RUNS_LAYER=default
  local -a layers=()
  home="$(bash "$lib/resolve-convention-home.sh" --root "$root" 2>/dev/null)"
  case $? in
  0) layers=("$home/skill-quality.yaml" "$home/skill-quality.local.yaml") ;;
  1) layers=("docs/conventions/skill-quality.yaml" "docs/conventions/skill-quality.local.yaml") ;;
  3) warn "the convention-home pointer region does not resolve (see lib/resolve-convention-home.sh --explain): plugin_eval_runs uses its default" ;;
  *) ;;
  esac
  for rel in ${layers[@]+"${layers[@]}"}; do
    [[ -f "$root/$rel" ]] || continue
    value="$(bash "$lib/parse-concern-value.sh" --strict "$root/$rel" plugin_eval_runs 2>/dev/null)"
    status=$?
    value="${value//$'\r'/}"
    ((status == 0)) && [[ -z "$value" ]] && continue
    if ((status == 0)) && [[ "$value" =~ ^[1-9][0-9]{0,5}$ ]]; then
      RUNS="$value"
      RUNS_LAYER="$rel"
      continue
    fi
    if ((status == 0)); then
      warn "$rel: plugin_eval_runs is '$value', not a whole number from 1 to 999999; that layer is dropped and plugin_eval_runs resolves to 3 unless a later layer sets it"
    else
      warn "$rel does not parse; that layer is dropped and plugin_eval_runs resolves to 3 unless a later layer sets it"
    fi
    RUNS=3
    RUNS_LAYER=default
  done
}

cmd_emit() {
  local runs layer
  if [[ "${1:-}" == "--runs" ]]; then
    positive_int --runs "${2:-}"
    runs="$2"
    layer=--runs
    shift 2
  else
    plugin_eval_runs_setting "$(repo_root)"
    runs="$RUNS"
    layer="$RUNS_LAYER"
  fi
  local dir="${1:-}" out="${2:-}"
  if [[ -z "$dir" || ! -d "$dir" || -z "$out" ]]; then
    printf 'Error: emit-plugin-eval needs <probes-dir> <out-dir>\n' >&2
    exit 2
  fi
  if [[ -d "$out" && -n "$(ls -A "$out")" ]]; then
    printf 'Error: emit-plugin-eval needs an empty or new <out-dir>; stale cases would still run\n' >&2
    exit 2
  fi
  note "runs per case: $runs ($layer)"
  local f root missing=0
  local -a files
  mapfile -t files < <(probe_files "$dir")
  root="$(repo_root)"
  for f in "${files[@]}"; do
    local p
    local -a need
    mapfile -t need < <(rival_plugins "$f")
    ((${#need[@]})) && need+=("$(jq -r '.plugin // empty' "$f")")
    for p in "${need[@]}"; do
      if [[ ! -d "$root/plugins/$p" ]]; then
        printf 'Error: emit-plugin-eval: %s needs plugin %s at %s, which does not exist; a case cannot load it\n' "$f" "$p" "$root/plugins/$p" >&2
        missing=1
      fi
    done
  done
  ((missing)) && exit 2
  local made=0
  [[ -d "$out" ]] || made=1
  mkdir -p "$out" || return 2
  local out_abs root_abs
  out_abs="$(cd "$out" && pwd -P)" || return 2
  root_abs="$(cd "$root" && pwd -P)" || return 2
  for f in "${files[@]}"; do
    if [[ -n "$(rival_plugins "$f")" && "$out_abs" != "$root_abs"/* ]]; then
      printf 'Error: emit-plugin-eval: %s lists cross-plugin rivals, so <out-dir> must sit inside %s; the CLI loads a case'"'"'s plugins only from inside the run target\n' "$f" "$root_abs" >&2
      ((made)) && rmdir "$out" 2>/dev/null
      exit 2
    fi
  done
  for f in "${files[@]}"; do
    local skill plugin leaf plugins_line=""
    skill="$(jq -r '.skill' "$f")"
    plugin="$(jq -r '.plugin // empty' "$f")"
    leaf="${skill#*:}"
    local -a rivals
    mapfile -t rivals < <(rival_plugins "$f")
    if ((${#rivals[@]})); then
      # Every case sits one level below out_abs; paths are relative to the case directory.
      local -a paths
      paths=("$(rel_path "$out_abs/_" "$(cd "$root/plugins/$plugin" && pwd -P)")") || return 2
      for p in "${rivals[@]}"; do
        paths+=("$(rel_path "$out_abs/_" "$(cd "$root/plugins/$p" && pwd -P)")")
      done
      plugins_line="$(jq -rn '"plugins: [" + ($ARGS.positional | map(tojson) | join(", ")) + "]"' --args "${paths[@]}")
"
    fi
    local nq i
    nq="$(jq '.queries | length' "$f")"
    for ((i = 0; i < nq; i++)); do
      local id split expect request
      id="$(jq -r ".queries[$i].id" "$f")"
      split="$(jq -r ".queries[$i].split" "$f")"
      expect="$(jq -r ".queries[$i].expect_trigger" "$f")"
      request="$(jq -r ".queries[$i].request" "$f")"
      local case_dir="$out/${plugin}-${leaf}-${id}"
      mkdir -p "$case_dir/graders" || return 2
      printf '%s\n' "---
description: invocation probe ${skill} ${id} (${split}, expect_trigger=${expect})
tags: [invocation-probe, ${split}]
${plugins_line}runs: ${runs}
max_turns: 8
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: Skill ${skill} $(if [[ "$expect" == "true" ]]; then echo fires; else echo does not fire; fi)
---

${request}
" >"$case_dir/prompt.md" || return 2
      # portability-ok: \s is read by the eval grader's own regex engine, never
      # shell grep/sed; kept out of the emitted YAML so the grader files stay clean.
      local match_re="\"skill\"\\s*:\\s*\"(?:${plugin}:)?${leaf}\""
      if [[ "$expect" == "true" ]]; then
        printf '%s\n' "---
type: tool_used
tool: Skill
input_match: '${match_re}'
min: 1
---
" >"$case_dir/graders/skill-fired.md" || return 2
      else
        printf '%s\n' "---
type: tool_used
tool: Skill
input_match: '${match_re}'
min: 0
max: 0
arm: both
---
" >"$case_dir/graders/skill-quiet.md" || return 2
      fi
    done
    note "emitted $nq plugin-eval cases for $skill under $out"
  done
  cat >"$out/README.md" <<'EOF' || return 2
Plugin-eval cases generated by `measure-invocation.sh emit-plugin-eval`.

Run one plugin's cases at a time:

```
claude plugin eval plugins/<plugin> --eval-dir <this-dir-filtered-to-that-plugin> --trust-plugin \
  --ablation none --keep-temp --disallow-tools Read Glob Grep Agent
```

The run workspace is empty, so without `--disallow-tools` the agent searches
outside it, or hands the task to a subagent that outlives the run's timeout;
the denied calls and timed-out runs make the run INVALID.

A with-only `tool_used: Skill` grader is a plugin-fired indicator, not a score.
Copy the per-case predicted fire/quiet bits into a report JSON matching
`measure-invocation.sh score` output, then `compare` against a baseline.
A probe with competitors in other plugins gets a `plugins:` line in each
case, listing the target plugin and those plugins relative to the case
directory, so the run loads the rivals too; keep the cases where they were
emitted. The CLI loads a case's plugins only from inside the run target, so
run those cases against the directory that holds plugins/, with
`--eval-dir` set to this directory relative to it (for example
`probe-evals/<plugin>`, which git ignores; the CLI refuses an --eval-dir segment that starts
with a dot, so not .work/; delete it after the run).
EOF
}

ACTION="$1"
shift
case "$ACTION" in
  validate)
    cmd_validate "$@"
    if ((fails > 0)); then
      printf 'measure-invocation validate: FAIL (%s error(s), %s warning(s))\n' "$fails" "$warns" >&2
      exit 1
    fi
    printf 'measure-invocation validate: PASS (%s warning(s))\n' "$warns" >&2
    exit 0
    ;;
  score)
    cmd_score "$@"
    if ((fails > 0)); then
      exit 1
    fi
    exit 0
    ;;
  compare)
    cmd_compare "$@"
    exit $?
    ;;
  emit-plugin-eval)
    cmd_emit "$@"
    exit $?
    ;;
  *)
    printf 'Error: unknown action %s (validate|score|compare|emit-plugin-eval)\n' "$ACTION" >&2
    exit 2
    ;;
esac
