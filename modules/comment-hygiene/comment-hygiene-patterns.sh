# shellcheck shell=bash
# Comment-hygiene detection policy — org-wide default ruleset.
#
# Library, NOT executable. Pure functions: no env reads, no file I/O, no exit
# calls. The comment-hygiene composite action sources this file and handles file
# enumeration, path scoping, and exit-code mapping. POSIX ERE only (grep -E) for
# cross-platform parity.
#
# Policy: comments in production code must not carry deferred-work markers
# (TODO / FIXME / HACK / XXX) or issue-tracker references (issue|fixes|closes
# #N, PR #N). Track outstanding work in the issue tracker, not in code comments,
# so it stays visible and does not rot silently in the source.
#
# This file is the CONFIG artifact: to tune the policy for a repo, vendor and
# edit it. The execution action is sourced separately and stays put.

# chp::scan_text <content>
#
# Scan the comment lines of <content> (those starting with // or #, after
# optional indentation) for banned markers and tracker references.
#
# Output (stdout): "lineno:kind:detail" per violation, lineno relative to
# <content>. Exit: 0 = clean, 1 = one or more violations.
chp::scan_text() {
  local content="$1"
  local entry lineno line violations=0
  local nocase_was=0

  # Markers match case-insensitively (Todo:, fixme, …). Save/restore the shell
  # option so sourcing this function never leaks nocasematch to the caller.
  if shopt -q nocasematch; then
    nocase_was=1
  else
    shopt -s nocasematch
  fi

  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    lineno="${entry%%:*}"
    line="${entry#*:}"

    # Warning markers — FIXME/HACK/XXX share one rule; TODO is separate so the
    # report names the exact marker.
    if [[ "$line" =~ (^|[^[:alnum:]_])(FIXME|HACK|XXX)([^[:alnum:]_]|$) ]]; then
      printf '%s:warning-marker:%s\n' "$lineno" "${BASH_REMATCH[2]}"
      violations=$((violations + 1))
      continue
    fi
    if [[ "$line" =~ (^|[^[:alnum:]_])TODO([^[:alnum:]_]|$) ]]; then
      printf '%s:warning-marker:TODO\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi

    # Issue-tracker references in comments.
    if [[ "$line" =~ (^|[^[:alnum:]_])(issue|fixes|closes)[[:space:]]*#?[0-9]+ ]]; then
      printf '%s:tracker-ref:issue-reference\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi
    if [[ "$line" =~ (^|[^[:alnum:]_])PR[[:space:]]*#[0-9]+ ]]; then
      printf '%s:tracker-ref:pr-reference\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi
  done < <(awk '/^[[:space:]]*(\/\/|#)/ { print NR ":" $0 }' <<<"$content")

  if [[ $nocase_was -eq 0 ]]; then
    shopt -u nocasematch
  fi
  if [[ $violations -gt 0 ]]; then
    return 1
  fi
  return 0
}
