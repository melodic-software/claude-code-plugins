#!/usr/bin/env bash
# Exit 0 clean, 1 findings, 2 the canary could not run (never a quiet pass).
set -uo pipefail

_SILENT_REVERT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/changed-files.sh"
cd "$(dirname "${BASH_SOURCE[0]}")/.." || {
  echo "check-silent-revert: cannot reach the repository root" >&2
  exit 2
}
# shellcheck source=lib/changed-files.sh
. "$_SILENT_REVERT_LIB" || {
  echo "check-silent-revert: cannot load scripts/lib/changed-files.sh" >&2
  exit 2
}
# shellcheck source=lib/changelog-fragments.sh
. "${_SILENT_REVERT_LIB%/*}/changelog-fragments.sh" || {
  echo "check-silent-revert: cannot load scripts/lib/changelog-fragments.sh" >&2
  exit 2
}

THRESHOLD="${SILENT_REVERT_THRESHOLD:-200}"
WINDOW="${SILENT_REVERT_WINDOW:-40}"
SAMPLES="${SILENT_REVERT_SAMPLES:-5}"
SAMPLE_MIN_LEN=25
MOVED_LINE_MIN_LEN=25

INCIDENTS_FILE="${SILENT_REVERT_INCIDENTS:-scripts/silent-revert-incidents.txt}"
ACK_FILE="${SILENT_REVERT_ACK:-scripts/silent-revert-acknowledged.txt}"

SEP=$'\037'

die() {
  echo "check-silent-revert: $*" >&2
  exit 2
}

usage() {
  cat >&2 <<'EOF'
usage:
  scripts/check-silent-revert.sh <range>                  e.g. abc123..def456
  scripts/check-silent-revert.sh --commit <sha>
  scripts/check-silent-revert.sh --verify-known-incidents
  scripts/check-silent-revert.sh --verify-restoration [<rev>]
EOF
  exit 2
}

command -v git >/dev/null 2>&1 || die "git is required"

declares_removal() {
  local sha="$1" msg subject
  msg="$(git log -1 --no-show-signature --format=%B "$sha")" || return 1
  subject="${msg%%$'\n'*}"

  if [[ "$subject" == 'Revert "'* ]]; then
    printf 'the subject begins with a Revert quote, as git revert writes it\n'
    return 0
  fi
  if grep -Eq '^revert(\([^()]+\))?!?:[[:space:]]*[^[:space:]]' <<<"$subject"; then
    printf 'the subject carries the Conventional-Commits revert type\n'
    return 0
  fi
  if grep -Eq '^This reverts commit [0-9a-f]{7,40}' <<<"$msg"; then
    printf 'the body carries a "This reverts commit <sha>" line\n'
    return 0
  fi
  if grep -Eq '^Intentional-removal:[[:space:]]*[^[:space:]]' <<<"$msg"; then
    printf 'the body carries an Intentional-removal trailer\n'
    return 0
  fi
  return 1
}

ack_reason() {
  local sha="$1"
  [[ -f "$ACK_FILE" ]] || return 1
  local recorded reason
  while read -r recorded reason || [[ -n "$recorded" ]]; do
    if [[ "$recorded" = "$sha" ]]; then
      printf '%s\n' "${reason:-<no reason recorded>}"
      return 0
    fi
  done <"$ACK_FILE"
  return 1
}

append_deleted_ranges() {
  local -n _adr_ranges_out="$1"
  local _adr_range
  while read -r _adr_range; do
    _adr_ranges_out+=(-L "$_adr_range")
  done < <(awk '/^@@ /{
         split($2, a, ",")
         start = substr(a[1], 2) + 0
         count = (length(a) > 1) ? a[2] + 0 : 1
         if (start > 0 && count > 0) print start "," (start + count - 1)
       }' "$2")
}

print_added_lines() {
  awk '/^diff --git /{ in_hunk = 0; next }
       /^@@ /{ in_hunk = 1; next }
       in_hunk && /^\+/ { print substr($0, 2) }' "$1"
}

attribute_file() {
  local parent="$1" commit="$2" file="$3"
  local -a ranges=()

  local diff_out
  diff_out="$(mktemp)" || die "mktemp failed"
  run_attributing_git "$diff_out" \
    "git diff failed attributing $file in $commit" \
    diff --no-ext-diff --no-textconv --unified=0 --no-color \
    --diff-algorithm=myers -M "$parent" "$commit" -- "$file"

  append_deleted_ranges ranges "$diff_out"
  local added_out
  added_out="$(mktemp)" || die "mktemp failed"
  print_added_lines "$diff_out" >"$added_out"

  if [[ "${#ranges[@]}" -eq 0 ]]; then
    local binary_rc=0
    grep -q '^Binary files ' "$diff_out" || binary_rc=$?
    case "$binary_rc" in
    0)
      local binary_attr
      binary_attr="$(git check-attr --source "$parent" binary -- "$file")" ||
        die "git check-attr failed attributing $file at $parent"
      case "$binary_attr" in
      *': binary: set') ;;
      *)
        local old_blob new_blob blob_out
        old_blob="$(git rev-parse --verify "${parent}:${file}" 2>/dev/null)" ||
          die "could not resolve ${parent}:${file} after a Binary files header"
        if ! new_blob="$(git rev-parse --verify "${commit}:${file}" 2>/dev/null)"; then
          new_blob="$(git hash-object -w --stdin </dev/null)" ||
            die "could not hash empty blob attributing $file in $commit"
        fi
        if [[ "$old_blob" != "$new_blob" ]]; then
          blob_out="$(mktemp)" || die "mktemp failed"
          run_attributing_git "$blob_out" \
            "git diff failed attributing blobs of $file in $commit" \
            diff --no-ext-diff --no-textconv --unified=0 --no-color \
            --diff-algorithm=myers "$old_blob" "$new_blob"
          append_deleted_ranges ranges "$blob_out"
          print_added_lines "$blob_out" >>"$added_out"
          rm -f "$blob_out"
        fi
        ;;
      esac
      ;;
    1) ;;
    *) die "grep failed looking for a binary-files header attributing $file in $commit (exit $binary_rc)" ;;
    esac
  fi
  rm -f "$diff_out"

  [[ "${#ranges[@]}" -gt 0 ]] || {
    rm -f "$added_out"
    return 0
  }

  local blame_out
  blame_out="$(mktemp)" || die "mktemp failed"
  run_attributing_git "$blame_out" \
    "git blame failed attributing $file at $parent" \
    blame --no-ignore-revs-file --no-textconv --line-porcelain \
    "${ranges[@]}" "$parent" -- "$file"
  awk -v added_file="$added_out" '
    function sha_normalized(s,   out, run, after_last_sha) {
      had_sha = 0
      out = ""
      while (match(s, /[0-9a-fA-F]+/)) {
        run = substr(s, RSTART, RLENGTH)
        out = out substr(s, 1, RSTART - 1)
        if (RLENGTH == 40) { run = "<sha>"; had_sha = 1; after_last_sha = length(out) + 5 }
        out = out run
        s = substr(s, RSTART + RLENGTH)
      }
      out = out s
      # A re-pin also rewrites the version comment after the SHA
      # (`@<sha> # v0.82.1`), so fold that tail too, and ONLY a bare version
      # tag: free comment text (`# keep: needed for X`) must come back
      # verbatim to cancel a removal. No ERE interval, so it stays mawk-safe.
      if (had_sha && substr(out, after_last_sha + 1) ~ /^[ \t]+#[ \t]*v?[0-9]+(\.[0-9]+)*[ \t]*$/)
        out = substr(out, 1, after_last_sha) " #<ref>"
      return out
    }
    BEGIN {
      while ((getline line < added_file) > 0) {
        key = sha_normalized(line)
        if (had_sha) re_added[key]++
      }
    }
    /^[0-9a-f]+ [0-9]+ [0-9]+/ { if (length($1) == 40) { sha = $1; ln = $3; next } }
    /^\t/ {
      if (sha == "") next
      text = substr($0, 2)
      key = sha_normalized(text)
      if (had_sha && re_added[key] > 0) { re_added[key]--; next }
      printf "%s\t%d\t%s\n", sha, ln, text
    }
  ' "$blame_out"
  rm -f "$blame_out" "$added_out"
}

run_attributing_git() {
  local out_file="$1" what="$2" err_file err rc=0
  shift 2
  err_file="$(mktemp)" || die "mktemp failed"
  git "$@" >"$out_file" 2>"$err_file" || rc=$?
  ((rc == 0)) || err="$(<"$err_file")"
  rm -f "$err_file"
  ((rc == 0)) || die "$what (exit $rc): ${err:-no stderr}"
}

discount_moved_lines() {
  local parent="$1" sha="$2" attributed="$3" added kept headers blob fresh file
  local -a files
  [[ -s "$attributed" ]] || return 0
  added="$(mktemp)" || die "mktemp failed"
  kept="$(mktemp)" || die "mktemp failed"
  headers="$(mktemp)" || die "mktemp failed"
  blob="$(mktemp)" || die "mktemp failed"
  fresh="$(mktemp)" || die "mktemp failed"
  run_attributing_git "$added" \
    "git diff failed listing the lines $sha added" \
    -c core.quotePath=false -c diff.suppressBlankEmpty=false diff --no-ext-diff --no-textconv \
    --no-relative --unified=100000000 --no-color --no-prefix --diff-algorithm=myers -M -l0 \
    "$parent" "$sha" -- .
  run_attributing_git "$blob" "git log failed listing the paths the window before $sha touched" \
    -c core.quotePath=false log --first-parent --diff-merges=first-parent --no-show-signature \
    --no-renames --format= --name-only -n "$WINDOW" "$parent"
  run_attributing_git "$fresh" "git diff failed listing the paths $sha added" \
    -c core.quotePath=false diff --no-relative --name-only --diff-filter=A -M -l0 "$parent" "$sha"
  awk 'NR == FNR { touched[$0] = 1; next }
    { base = tolower($0); sub(/.*\//, "", base) }
    !($0 in touched) && ("/" $0 "/") !~ /\/\.changes\// &&
      base !~ /^(changelog|history|changes|news|release-notes)/' \
    "$blob" "$fresh" >"$kept" || die "awk failed listing the new paths $sha added"
  mv -f "$kept" "$fresh" || die "could not record the new paths $sha added"
  awk -F '\t' '!seen[$2]++ { print $2 }' "$attributed" >"$blob" ||
    die "awk failed listing the files $sha deleted lines from"
  mapfile -t files <"$blob"
  for file in "${files[@]}"; do
    run_attributing_git "$blob" "git cat-file failed reading $file at $parent" \
      cat-file blob "$parent:$file"
    LC_ALL=C awk -v f="$file" '
      BEGIN { md = f ~ /\.md$/ }
      /^[[:space:]]*$/ { start = 0; next }
      {
        if (!start) start = FNR
        run_of[FNR] = start
        run_end[start] = FNR
        lines[++n] = FNR
        match($0, /^[ \t]*/)
        ind = RLENGTH
        while (depth > 0 && indent[depth] >= ind) depth--
        h = depth > 0 ? line[depth] : 0
        if (h) has_child[h] = 1
        lvl = 0
        if (md) {
          if (/^</) lt = 1
          lt_at[FNR] = lt
          match($0, /^ ? ? ?/)
          rest = substr($0, RLENGTH + 1)
          mark = ""
          if (match(rest, /^(`+|~+)/)) mark = substr(rest, 1, RLENGTH)
          if (fence) {
            h = fence
            if (mark == fence_mark && rest ~ /^(```|~~~)[ \t\r]*$/) fence = 0
            else if (length(mark) >= 3) poison = 1
          } else if (length(mark) >= 3) {
            fence = FNR
            fence_mark = mark
            if (length(mark) > 3) poison = 1
          } else if (/^#+([ \t\r]|$)/) { match($0, /^#+/); lvl = RLENGTH > 6 ? 0 : RLENGTH }
          if (h == 0)
            for (k = (lvl ? lvl - 1 : 6); k > 0; k--) if (at[k] > h) h = at[k]
          if (lvl) at[lvl] = FNR
        }
        heading[FNR] = lvl > 0
        up[FNR] = h
        atx[FNR] = lvl > 0 || (h && atx[h])
        bad[FNR] = md && (poison || !atx[FNR])
        indent[++depth] = ind
        line[depth] = FNR
      }
      END {
        for (k = 1; k <= n; k++)
          for (a = lines[k]; a; a = up[a]) last[a] = lines[k]
        for (k = 1; k <= n; k++) {
          ln = lines[k]
          if (ln > reach) unit = ln
          unit_of[ln] = unit
          hi = run_end[run_of[ln]]
          if (last[ln] > hi) hi = last[ln]
          if (hi > reach) reach = hi
        }
        for (k = 1; k <= n; k++) {
          ln = lines[k]
          unit = unit_of[ln]
          printf "%s\t%d\t%d\t%d\t%d\n", f, ln, unit, bad[ln],
            (md ? heading[unit] && !lt_at[unit] : has_child[unit] + 0)
        }
      }
    ' "$blob" >>"$headers" || die "awk failed reading the blocks of $file at $parent"
  done
  LC_ALL=C awk -v min="$MOVED_LINE_MIN_LEN" -v triple="'''" -v heredoc_re="<<-?[[:space:]]*[\"']?[A-Za-z_][A-Za-z0-9_]*" '
    function long_enough(line) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      return length(line) >= min
    }
    function blank(line) { return line ~ /^[[:space:]]*$/ }
    function indent_of(line) { match(line, /^[ \t]*/); return RLENGTH }
    function count(s, x,   n, k) {
      while ((k = index(s, x)) > 0) { n++; s = substr(s, k + length(x)) }
      return n + 0
    }
    function last_at(s, x,   at, k, off) {
      while ((k = index(substr(s, off + 1), x)) > 0) { at = off + k; off = at }
      return at + 0
    }
    function still_open(was, s, opener, closer,   o, c) {
      o = last_at(s, opener)
      c = last_at(s, closer)
      return o > c ? 1 : c > o ? 0 : was
    }
    function scan(p,   i, t, l, low, word, dq, sq, comment, block, pre, fence, heredoc) {
      scanned[p] = 1
      low = 1e9
      heredoc = ""
      for (i = 1; i <= last_ln[p]; i++) {
        t = new_text[p, i]
        l = tolower(t)
        if (heredoc != "") {
          word = t
          gsub(/^[ \t]+|[ \t\r]+$/, "", word)
          if (word == heredoc) heredoc = ""
        } else if (fence) {
          if (t ~ /^[ \t]*(```|~~~)/) fence = 0
        } else {
          if (t ~ /^[ \t]*(```|~~~)/) fence = 1
          dq = (dq + count(t, "\"\"\"")) % 2
          sq = (sq + count(t, triple)) % 2
          comment = still_open(comment, l, "<!--", "-->")
          block = still_open(block, t, "/*", "*/")
          pre = still_open(pre, l, "<pre", "</pre")
          if (match(t, heredoc_re)) {
            heredoc = substr(t, RSTART, RLENGTH)
            sub(/^<<-?[ \t]*/, "", heredoc)
            gsub(/[^A-Za-z0-9_]/, "", heredoc)
          } else if (index(t, "<<")) heredoc = "\001"
        }
        if (t ~ /[:{][ \t\r]*$/ && indent_of(t) < low) low = indent_of(t)
        wrapped_by[p, i] = dq || sq || comment || block || pre || fence || heredoc != ""
        lowest_opener[p, i] = low
      }
    }
    function placed(p, pos, f, u,   k, i, ind) {
      ind = indent_of(deleted[f, member[f, u, 1]])
      if (!(p in scanned)) scan(p)
      if (pos > 1 && (wrapped_by[p, pos - 1] || (p !~ /\.md$/ && lowest_opener[p, pos - 1] < ind))) return 0
      i = pos
      for (k = 1; k <= size[f, u]; k++) {
        while (i <= last_ln[p] && blank(new_text[p, i])) i++
        if (i > last_ln[p] || !((p, i) in added) || ((p, i) in taken) ||
          new_text[p, i] != deleted[f, member[f, u, k]]) return 0
        slot[k] = i++
      }
      while (i <= last_ln[p] && blank(new_text[p, i])) i++
      if (p !~ /\.md$/ && i <= last_ln[p] && indent_of(new_text[p, i]) > ind) return 0
      for (k = 1; k <= size[f, u]; k++) taken[p, slot[k]] = 1
      return 1
    }
    function unit_moved(f, u,   k, first, q, p, j) {
      if ((f, u) in moved) return moved[f, u]
      if (size[f, u] < 3 || !((f, u) in headed)) return moved[f, u] = 0
      for (k = 1; k <= size[f, u]; k++)
        if (!((f, member[f, u, k]) in deleted)) return moved[f, u] = 0
      first = deleted[f, member[f, u, 1]]
      for (q = 1; q <= path_count[first]; q++) {
        p = paths[first, q]
        if (p == f || !(p in fresh)) continue
        for (j = 1; j <= at_count[p, first]; j++)
          if (placed(p, at[p, first, j], f, u)) return moved[f, u] = 1
      }
      return moved[f, u] = 0
    }
    FILENAME == ARGV[1] {
      if (/^diff --git /) { in_header = 1; path = ""; old = ""; next }
      if (in_header) {
        if (/^--- /) {
          old = substr($0, 5)
          sub(/\t$/, "", old)
          if (old == "/dev/null" || substr(old, 1, 1) == "\"") old = ""
        } else if (/^\+\+\+ /) {
          path = substr($0, 5)
          sub(/\t$/, "", path)
          if (path == "/dev/null" || substr(path, 1, 1) == "\"") path = ""
        } else if (/^@@ /) {
          in_header = 0
        }
        if (!/^@@ /) next
      }
      if (/^@@ /) {
        split($2, a, ",")
        old_ln = substr(a[1], 2) + 0
        split($3, a, ",")
        new_ln = substr(a[1], 2) + 0
        next
      }
      mark = substr($0, 1, 1)
      text = substr($0, 2)
      if (mark == "-") {
        if (old != "") deleted[old, old_ln] = text
        old_ln++
        next
      }
      if (mark != " " && mark != "+") next
      if (mark == " ") old_ln++
      if (path != "") {
        new_text[path, new_ln] = text
        last_ln[path] = new_ln
        if (mark == "+") {
          added[path, new_ln] = 1
          if (!((text, path) in seen)) { seen[text, path] = 1; paths[text, ++path_count[text]] = path }
          at[path, text, ++at_count[path, text]] = new_ln
        }
      }
      new_ln++
      next
    }
    FILENAME == ARGV[2] {
      split($0, h, "\t")
      u = h[3] + 0
      unit_of[h[1], h[2] + 0] = u
      member[h[1], u, ++size[h[1], u]] = h[2] + 0
      if (h[4] + 0) bad[h[1], h[2] + 0] = 1
      if (h[5] + 0) headed[h[1], u] = 1
      next
    }
    FILENAME == ARGV[3] { fresh[$0] = 1; next }
    {
      split($0, r, "\t")
      file = r[2]
      ln = r[3] + 0
      text = substr($0, length(r[1]) + length(r[2]) + length(r[3]) + 4)
      if (long_enough(text) && !((file, ln) in bad) && ((file, ln) in unit_of) &&
        unit_moved(file, unit_of[file, ln])) next
      printf "%s\t%s\t%s\n", r[1], file, text
    }
  ' "$added" "$headers" "$fresh" "$attributed" >"$kept" || die "awk failed discounting moved lines in $sha"
  mv -f "$kept" "$attributed" || die "could not replace the attribution of $sha"
  rm -f "$added" "$headers" "$blob" "$fresh"
}

scan_commit() {
  local commit="$1"
  local sha subject parent
  sha="$(git rev-parse --verify "${commit}^{commit}" 2>/dev/null)" ||
    die "not a commit: $commit"
  subject="$(git log -1 --no-show-signature --format=%s "$sha")"

  parent="$(git rev-parse --verify "${sha}^1" 2>/dev/null)" || {
    printf 'skip %s (root commit, no parent to compare against)\n' "${sha:0:9}"
    return 0
  }

  local why
  if why="$(declares_removal "$sha")"; then
    printf 'declared %s %s\n' "${sha:0:9}" "$subject"
    printf '         removal is declared: %s\n' "$why"
    return 0
  fi

  local ack_note
  if ack_note="$(ack_reason "$sha")"; then
    printf 'acknowledged %s %s\n' "${sha:0:9}" "$subject"
    printf '             reviewed and cleared: %s\n' "$ack_note"
    return 0
  fi

  local window_file
  window_file="$(mktemp)" || die "mktemp failed"
  git rev-list --first-parent -n "$WINDOW" "$parent" >"$window_file" 2>/dev/null

  if [[ ! -s "$window_file" ]]; then
    rm -f "$window_file"
    printf 'skip %s (no history behind the parent to compare against)\n' "${sha:0:9}"
    return 0
  fi

  local attributed file_attr enum_list
  attributed="$(mktemp)" || die "mktemp failed"
  file_attr="$(mktemp)" || die "mktemp failed"
  enum_list="$(mktemp)" || die "mktemp failed"
  local -a scope=(-- .)
  local p
  run_attributing_git "$enum_list" \
    "git diff --name-only failed enumerating CHANGELOG changes in $sha" \
    diff --name-only --no-renames "$parent" "$sha" -- ':(glob)plugins/*/CHANGELOG.md' \
    ':(glob)docs/contracts/*/CHANGELOG.md' ':(glob)docs/conventions/*/CHANGELOG.md'
  while IFS= read -r p; do
    [[ "$p" == plugins/* ]] || continue
    p="${p#plugins/}"
    scope+=(":(exclude,literal).changes/${p%/CHANGELOG.md}/")
  done <"$enum_list"
  local file
  if [[ -s "$enum_list" ]]; then
    local frag_body
    frag_body="$(mktemp)" || die "mktemp failed"
    run_attributing_git "$enum_list" \
      "git diff --name-only failed enumerating deleted fragments in $sha" \
      diff --name-only -z --no-renames --diff-filter=D "$parent" "$sha" -- ':(glob).changes/*/*.md'
    while IFS= read -r -d '' file; do
      [[ "$file" =~ ^\.changes/[A-Za-z0-9._-]+/[^/]+\.md$ ]] || continue
      run_attributing_git "$frag_body" "git cat-file failed reading $file at $parent" \
        cat-file blob "$parent:$file"
      [[ "$(changelog_fragments::bump_of "$frag_body")" == none ]] || continue
      scope+=(":(exclude,literal)$file")
    done <"$enum_list"
    rm -f "$frag_body"
  fi
  run_attributing_git "$enum_list" \
    "git diff --name-only failed enumerating $sha" \
    diff --name-only -z -M -l0 --diff-filter=MD "$parent" "$sha" "${scope[@]}"
  while IFS= read -r -d '' file; do
    attribute_file "$parent" "$sha" "$file" >"$file_attr"
    awk -v f="$file" '{ i = index($0, "\t"); printf "%s\t%s\t%s\n", substr($0, 1, i - 1), f, substr($0, i + 1) }' \
      "$file_attr" >>"$attributed"
  done <"$enum_list"
  rm -f "$file_attr" "$enum_list"
  discount_moved_lines "$parent" "$sha" "$attributed"

  local in_window
  in_window="$(mktemp)" || die "mktemp failed"
  if [[ -s "$attributed" ]]; then
    awk -F '\t' 'NR == FNR { w[$1] = 1; next } ($1 in w)' \
      "$window_file" "$attributed" >"$in_window"
  fi

  if [[ -n "${ATTRIBUTION_SINK:-}" ]]; then
    awk -F '\t' '{c[$1]++} END {for (k in c) print k, c[k]}' \
      "$in_window" >>"$ATTRIBUTION_SINK"
  fi

  local findings=0 culprit count
  while read -r count culprit; do
    [[ -n "$culprit" ]] || continue
    [[ "$count" -ge "$THRESHOLD" ]] || continue
    findings=$((findings + 1))
    report_finding "$sha" "$subject" "$parent" "$culprit" "$count" "$in_window"
  done < <(awk -F '\t' '{c[$1]++} END {for (k in c) print c[k], k}' "$in_window" |
    sort -rn)

  rm -f "$window_file" "$attributed" "$in_window"

  if [[ "$findings" -eq 0 ]]; then
    printf 'ok %s %s\n' "${sha:0:9}" "$subject"
    return 0
  fi
  return 1
}

report_finding() {
  local sha="$1" subject="$2" parent="$3" culprit="$4" count="$5" data="$6"
  local distance
  distance="$(git rev-list --first-parent --count "${culprit}..${parent}" 2>/dev/null)"

  if [[ -n "${FINDINGS_SINK:-}" ]]; then
    printf '%s %s\n' "$culprit" "$count" >>"$FINDINGS_SINK"
  fi
  if [[ -n "${DELETED_SINK:-}" ]]; then
    awk -F '\t' -v c="$culprit" '$1 == c' "$data" >>"$DELETED_SINK"
  fi

  printf '\n'
  printf 'SILENT REVERT SUSPECTED\n'
  printf '\n'
  printf '  removed by   %s  %s\n' "${sha:0:9}" "$subject"
  printf '               %s\n' "$(git log -1 --no-show-signature --format=%ci "$sha")"
  printf '  content from %s  %s\n' "${culprit:0:9}" \
    "$(git log -1 --no-show-signature --format=%s "$culprit")"
  printf '               %s  (%s commit(s) earlier on main)\n' \
    "$(git log -1 --no-show-signature --format=%ci "$culprit")" "$((distance + 1))"
  printf '  lines lost   %s  (threshold %s, window %s commits)\n' \
    "$count" "$THRESHOLD" "$WINDOW"
  printf '\n'
  printf '  by file:\n'
  awk -F '\t' -v c="$culprit" '$1 == c {n[$2]++} END {for (f in n) printf "%8d  %s\n", n[f], f}' \
    "$data" | sort -rn
  printf '\n'
  printf '  sample of the removed content:\n'
  awk -F '\t' -v c="$culprit" -v min="$SAMPLE_MIN_LEN" -v max="$SAMPLES" '
    $1 == c {
      line = $3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) >= min) {
        printf "      | %s\n", substr(line, 1, 100)
        if (++shown >= max) exit
      }
    }' "$data"
  printf '\n'
  printf '  What to do:\n'
  printf '    Compare the merged tree against what %s landed:\n' "${culprit:0:9}"
  printf '      git diff %s %s -- <file>\n' "${culprit:0:9}" "${sha:0:9}"
  printf '    If the content should still be on main, re-land it.\n'
  printf '    If the removal was intended, record the review in %s:\n' "$ACK_FILE"
  printf '      %s  <why it was intended>\n' "$sha"
  printf '    Next time, saying it in the PR body up front avoids the fire\n'
  printf '    entirely -- GitHub carries the body into the squash message:\n'
  printf '      Intentional-removal: <why>\n'
  printf '\n'
}

parse_attribution_field() {
  local field="$1" entry
  field="${field#\[}"
  field="${field%\]}"
  [[ -n "$field" ]] || die "empty attribution field in $INCIDENTS_FILE"
  case "$field" in
  *, | ,* | *,,*)
    die "malformed attribution field in $INCIDENTS_FILE (empty entry from a leading, trailing, or doubled comma)"
    ;;
  *) ;;
  esac
  local IFS=','
  for entry in $field; do
    [[ "$entry" == *=* ]] ||
      die "malformed attribution entry '$entry' in $INCIDENTS_FILE (want <40-char-sha>=<lines>)"
    local culprit="${entry%%=*}" lines="${entry#*=}"
    [[ "$culprit" =~ ^[0-9a-f]{40}$ ]] ||
      die "attribution culprit '$culprit' in $INCIDENTS_FILE is not a full 40-character sha"
    [[ "$lines" =~ ^[0-9]+$ ]] ||
      die "attribution line count '$lines' for $culprit in $INCIDENTS_FILE is not a number"
    printf '%s %s\n' "$culprit" "$lines"
  done
}

largest_attributions() {
  local src="$1"
  awk '
    {
      n = $2 + 0
      if (n > max) {
        max = n
        delete keep
        keep[$1] = n
      } else if (n == max && max > 0) {
        keep[$1] = n
      }
    }
    END {
      for (s in keep) print s, keep[s]
    }
  ' "$src"
}

report_mismatch() {
  printf 'FAIL %s\n' "$1"
  printf '     recorded %s:\n' "$2"
  sed 's/^/       /' "$3"
  printf '     what the detector reported:\n'
  sed 's/^/       /' "$4"
  printf '     %s is not a reproduction.\n' "$5"
  printf '     Do not edit the row to match; find out why the attribution moved.\n'
}

verify_known_incidents() {
  [[ -f "$INCIDENTS_FILE" ]] || die "incident file not found: $INCIDENTS_FILE"

  local rc=0 expect sha rest note attribution
  local expected_file observed_file all_attr_file verified=0
  expected_file="$(mktemp)" || die "mktemp failed"
  observed_file="$(mktemp)" || die "mktemp failed"
  all_attr_file="$(mktemp)" || die "mktemp failed"

  while read -r expect sha rest || [[ -n "$expect" ]]; do
    [[ -z "$expect" || "$expect" == '#'* || "$expect" == marker ]] && continue
    verified=$((verified + 1))
    if ! changed_files::verify_base "$sha"; then
      die "incident commit $sha is unreachable -- the canary self-check needs full history (fetch-depth: 0)"
    fi

    attribution=""
    note="$rest"
    if [[ "$rest" == \[* ]]; then
      [[ "$rest" == \[*\]* ]] ||
        die "unterminated attribution field for $sha in $INCIDENTS_FILE (no closing ']'): $rest"
      attribution="${rest%%\]*}]"
      note="${rest#*\]}"
      note="${note# }"
    fi

    : >"$expected_file"
    if [[ -n "$attribution" ]]; then
      case "$expect" in
      fires | clean) ;;
      *)
        die "row for $sha in $INCIDENTS_FILE records an attribution on a '$expect' row; only 'fires' and 'clean' rows may carry one"
        ;;
      esac
      parse_attribution_field "$attribution" >"$expected_file"
      sort -o "$expected_file" "$expected_file"
    fi

    local out status
    : >"$observed_file"
    : >"$all_attr_file"
    out="$(FINDINGS_SINK="$observed_file" ATTRIBUTION_SINK="$all_attr_file" \
      scan_commit "$sha" 2>&1)"
    status=$?
    if [[ "$status" -eq 2 ]]; then
      printf '%s\n' "$out"
      rm -f "$expected_file" "$observed_file" "$all_attr_file"
      die "scan of $sha could not run"
    fi
    sort -o "$observed_file" "$observed_file"

    case "$expect" in
    fires)
      if [[ "$status" -ne 1 ]]; then
        printf 'FAIL %s should fire and did not  (%s)\n' "${sha:0:9}" "$note"
        printf '%s\n' "$out"
        rc=1
      elif [[ -n "$attribution" ]] && ! cmp -s "$expected_file" "$observed_file"; then
        report_mismatch "${sha:0:9} fires, but NOT as recorded  ($note)" "attribution" \
          "$expected_file" "$observed_file" "A row that fires for the wrong reason"
        rc=1
      elif [[ -n "$attribution" ]]; then
        printf 'ok   %s fires as recorded, %s attribution(s) reproduced exactly  (%s)\n' \
          "${sha:0:9}" "$(wc -l <"$expected_file" | tr -d '[:space:]')" "$note"
      else
        printf 'ok   %s fires as recorded  (%s)\n' "${sha:0:9}" "$note"
      fi
      ;;
    clean)
      if [[ "$status" -ne 0 ]]; then
        printf 'FAIL %s should stay clean and fired  (%s)\n' "${sha:0:9}" "$note"
        printf '%s\n' "$out"
        rc=1
      elif [[ -n "$attribution" ]]; then
        largest_attributions "$all_attr_file" >"$observed_file"
        sort -o "$observed_file" "$observed_file"
        if ! cmp -s "$expected_file" "$observed_file"; then
          report_mismatch "${sha:0:9} stays clean, but NOT as recorded  ($note)" \
            "largest sub-threshold attribution" "$expected_file" "$observed_file" \
            "A clean row whose figure has moved"
          rc=1
        else
          printf 'ok   %s stays clean as recorded, largest sub-threshold attribution reproduced exactly  (%s)\n' \
            "${sha:0:9}" "$note"
        fi
      else
        printf 'ok   %s stays clean as recorded  (%s)\n' "${sha:0:9}" "$note"
      fi
      ;;
    *) die "unknown expectation '$expect' in $INCIDENTS_FILE" ;;
    esac
  done <"$INCIDENTS_FILE"

  rm -f "$expected_file" "$observed_file" "$all_attr_file"

  ((verified > 0)) ||
    die "$INCIDENTS_FILE verified zero rows -- an incident file that pins nothing is a broken input, not a pass"

  if [[ "$rc" -ne 0 ]]; then
    echo
    echo "The canary no longer reproduces the incidents it was built for."
    echo "Do not relax the recorded expectations to make this pass."
    return 1
  fi
  echo
  echo "Canary reproduces every recorded incident at the shipped settings."
  return 0
}

parse_incidents_file() {
  local fires_out="$1" markers_out="$2"
  : >"$fires_out"
  : >"$markers_out"

  local line kind sha path rest reason marker
  while IFS= read -r line || [[ -n "$line" ]]; do
    read -r kind sha path rest <<<"$line"

    case "$kind" in
    '' | '#'*) continue ;;
    fires | clean)
      [[ "$sha" =~ ^[0-9a-f]{40}$ ]] ||
        die "incident sha '$sha' in $INCIDENTS_FILE is not a full 40-character sha"
      if [[ "$kind" = "fires" ]]; then
        printf '%s\n' "$sha" >>"$fires_out"
      fi
      ;;
    marker)
      case "$line" in
      *"$SEP"*) die "marker row for $sha in $INCIDENTS_FILE contains a control character" ;;
      *) ;;
      esac
      [[ "$sha" =~ ^[0-9a-f]{40}$ ]] ||
        die "marker row sha '$sha' in $INCIDENTS_FILE is not a full 40-character sha"
      [[ -n "$path" ]] ||
        die "marker row for $sha in $INCIDENTS_FILE records no path"
      case "$path" in
      \[*) die "marker row for $sha in $INCIDENTS_FILE has a disposition where its path should be" ;;
      /* | [A-Za-z]:[/\\]* | \\*)
        die "marker path '$path' for $sha in $INCIDENTS_FILE is absolute -- use a path relative to the repository root"
        ;;
      .. | ../* | */../* | */..)
        die "marker path '$path' for $sha in $INCIDENTS_FILE escapes the repository with '..'"
        ;;
      :*)
        die "marker path '$path' for $sha in $INCIDENTS_FILE uses pathspec magic -- a marker binds to one literal file path"
        ;;
      *[*?[]*)
        die "marker path '$path' for $sha in $INCIDENTS_FILE contains a glob character -- a marker binds to one literal file path"
        ;;
      *) ;;
      esac

      reason=""
      marker="$rest"
      if [[ "$rest" == \[* ]]; then
        [[ "$rest" == \[*\]* ]] ||
          die "unterminated disposition on the marker row for $sha in $INCIDENTS_FILE (no closing ']'): $rest"
        local disposition="${rest%%\]*}"
        disposition="${disposition#\[}"
        grep -Eq '^not-restored:[[:space:]]*[^[:space:]]' <<<"$disposition" ||
          die "disposition '[$disposition]' on the marker row for $sha in $INCIDENTS_FILE must be [not-restored: <non-empty reason>]"
        reason="${disposition#not-restored:}"
        reason="${reason#"${reason%%[![:space:]]*}"}"
        marker="${rest#*\]}"
        marker="${marker#"${marker%%[![:space:]]*}"}"
      fi
      [[ -n "$marker" ]] ||
        die "marker row for $sha in $INCIDENTS_FILE records no marker text"

      printf '%s%s%s%s%s%s%s\n' \
        "$sha" "$SEP" "$path" "$SEP" "$reason" "$SEP" "$marker" >>"$markers_out"
      ;;
    *) die "unknown row kind '$kind' in $INCIDENTS_FILE" ;;
    esac
  done <"$INCIDENTS_FILE"
}

marker_present() {
  local rev="$1" path="$2" marker="$3" status kind mode content
  if [[ -n "$rev" ]]; then
    kind="$(git cat-file -t "${rev}:${path}" 2>/dev/null)" || return 1
    [[ "$kind" = "blob" ]] ||
      die "marker path '$path' resolves to a $kind at $rev, not a file -- bind a marker to exactly one file"
    mode="$(git ls-tree "$rev" -- "$path" 2>/dev/null)"
    mode="${mode%% *}"
    case "$mode" in
    100644 | 100755) ;;
    120000)
      die "marker path '$path' is a symlink at $rev -- bind a marker to the file that holds the content"
      ;;
    *)
      die "marker path '$path' is not a regular file at $rev (mode '${mode:-unreadable}') -- bind a marker to exactly one file"
      ;;
    esac
    content="$(git cat-file blob "${rev}:${path}" 2>/dev/null)" ||
      die "could not read '$path' at $rev"
  else
    git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || return 1
    if [[ -L "$path" ]]; then
      die "marker path '$path' is a symlink -- bind a marker to the file that holds the content"
    fi
    [[ -f "$path" ]] ||
      die "marker path '$path' is not a regular file -- bind a marker to exactly one file"
    content="$(<"$path")" || die "could not read '$path'"
  fi
  grep -qF -e "$marker" <<<"$content"
  status=$?
  case "$status" in
  0) return 0 ;;
  1) return 1 ;;
  *) die "grep failed (status $status) resolving a marker in $path at ${rev:-the working tree}" ;;
  esac
}

verify_restoration() {
  local rev="${1:-}"
  [[ -f "$INCIDENTS_FILE" ]] || die "incident file not found: $INCIDENTS_FILE"

  local where="the working tree"
  if [[ -n "$rev" ]]; then
    changed_files::verify_base "$rev" ||
      die "cannot resolve rev '$rev' -- the restoration assertion needs full history (fetch-depth: 0)"
    where="$rev"
  fi

  local fires markers
  fires="$(mktemp)" || die "mktemp failed"
  markers="$(mktemp)" || die "mktemp failed"
  # shared with anything.
  # shellcheck disable=SC2064  # expand the paths now, while they are in scope.
  trap "rm -f '$fires' '$markers'" EXIT
  parse_incidents_file "$fires" "$markers"

  [[ -s "$fires" ]] ||
    die "$INCIDENTS_FILE records no 'fires' row -- the restoration assertion would pass while covering nothing"

  local sha marker_shas
  marker_shas="$(cut -d"$SEP" -f1 "$markers")"
  while read -r sha; do
    [[ -n "$sha" ]] || continue
    changed_files::verify_base "$sha" ||
      die "incident commit $sha is unreachable -- the restoration assertion needs full history (fetch-depth: 0)"
    grep -qxF "$sha" <<<"$marker_shas" ||
      die "the 'fires' row for ${sha:0:9} in $INCIDENTS_FILE carries no marker. Record at least one: marker $sha <path> <a line of the content it removed>"
  done <"$fires"

  local mpath mreason mtext
  while IFS="$SEP" read -r sha mpath mreason mtext; do
    [[ -n "$sha" ]] || continue
    grep -qxF "$sha" "$fires" ||
      die "marker row for $sha in $INCIDENTS_FILE names no recorded 'fires' incident"
  done <"$markers"

  local rc=0 checked=0 absent=0 excused=0
  printf 'Restoration of recorded incident content, resolved at %s:\n\n' "$where"
  while IFS="$SEP" read -r sha mpath mreason mtext; do
    [[ -n "$sha" ]] || continue
    checked=$((checked + 1))
    if marker_present "$rev" "$mpath" "$mtext"; then
      printf 'ok    %s  %s\n' "${sha:0:9}" "$mpath"
      printf '        present: %s\n' "$mtext"
    elif [[ -n "$mreason" ]]; then
      excused=$((excused + 1))
      printf 'noted %s  %s\n' "${sha:0:9}" "$mpath"
      printf '        deliberately not restored: %s\n' "$mreason"
      printf '        marker: %s\n' "$mtext"
    else
      absent=$((absent + 1))
      rc=1
      printf 'FAIL  %s  %s\n' "${sha:0:9}" "$mpath"
      printf '        NOT RESTORED: %s\n' "$mtext"
    fi
  done <"$markers"

  if [[ "$rc" -ne 0 ]]; then
    printf '\n'
    printf '%s of %s recorded marker(s) are absent from %s.\n' "$absent" "$checked" "$where"
    echo "Those incidents still FIRE as recorded, which is only half the proof:"
    echo "the removal was detected and never fully undone. Re-land the content."
    echo "If it is deliberately staying out, say so on its marker row -- with a"
    echo "reason, the same shape an Intentional-removal: trailer needs:"
    echo "  marker <incident-sha> <path> [not-restored: <why>] <marker text>"
    echo "Do not delete the marker row. That is the mute button this corpus"
    echo "exists in order not to have."
    return 1
  fi

  printf '\n'
  printf 'Every recorded incident has its content at %s (%s marker(s), %s dispositioned).\n' \
    "$where" "$checked" "$excused"
  return 0
}

main() {
  [[ $# -ge 1 ]] || usage

  case "$1" in
  --verify-known-incidents)
    verify_known_incidents
    exit $?
    ;;
  --verify-restoration)
    [[ $# -le 2 ]] || usage
    verify_restoration "${2:-}"
    exit $?
    ;;
  --commit)
    [[ $# -eq 2 ]] || usage
    scan_commit "$2"
    exit $?
    ;;
  -*) usage ;;
  *) ;;
  esac

  local range="$1"
  case "$range" in
  *..*) ;;
  *) die "expected a commit range like A..B, got '$range'" ;;
  esac

  local commits
  commits="$(git rev-list --first-parent --reverse "$range" 2>/dev/null)" ||
    die "cannot resolve range '$range' -- is the full history fetched (fetch-depth: 0)?"

  if [[ -z "$commits" ]]; then
    echo "check-silent-revert: no commits in range '$range'; nothing to scan."
    exit 0
  fi

  local rc=0 c
  for c in $commits; do
    scan_commit "$c" || rc=1
  done

  if [[ "$rc" -ne 0 ]]; then
    echo
    echo "One or more merges removed a large block of content that had just"
    echo "landed on main, without declaring the removal. See each finding above."
    echo "This check never blocks a merge -- the merge has already happened."
  fi
  exit "$rc"
}

main "$@"
