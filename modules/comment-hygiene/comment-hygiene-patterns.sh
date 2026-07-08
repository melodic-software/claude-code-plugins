# shellcheck shell=bash
# Comment-hygiene detection policy — org-wide default ruleset.
#
# Library, NOT executable. Pure functions: no env reads, no file I/O, no exit
# calls. The comment-hygiene composite action sources this file and handles file
# enumeration, path scoping, and exit-code mapping. POSIX ERE only (grep -E) for
# cross-platform parity.
#
# Policy: comments in production code must not carry deferred-work markers
# (TODO / FIXME / HACK / XXX) or issue-tracker references: cc-issue, GitHub
# closing keywords with a number (fix(es|ed)/close[sd]/resolve[sd] #N), issue /
# issues / tracked #N, owner/repo#N, GH-N, and PR #N. Track outstanding work in
# the issue tracker, not in code comments, so it stays visible and does not rot
# silently in the source.
#
# This file is the CONFIG artifact: to tune the policy for a repo, vendor and
# edit it. The execution action is sourced separately and stays put.

# chp::scan_text <content>
#
# Scan the comment lines of <content> (those starting with //, #, /*, *, or
# <!--, after optional indentation) for banned markers and tracker references.
#
# Output (stdout): "lineno:kind:detail" per violation, lineno relative to
# <content>. Exit: 0 = clean, 1 = one or more violations.
chp::scan_text() {
  local content="$1"
  local entry lineno line violations=0
  local nocase_was=0

  # Every pattern below matches case-insensitively (Todo:, fixme, Closes #1,
  # gh-5, …). Save/restore the shell option so sourcing this function never
  # leaks nocasematch to the caller.
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

    # Internal continuous-collaboration issue marker.
    if [[ "$line" =~ cc-issue ]]; then
      printf '%s:tracker-ref:cc-issue\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi

    # GitHub closing keywords only close an issue when paired with a #number, so
    # require the # — that keeps prose like "fix 3 bugs" or "close the handle"
    # clean while catching "fixes #12" / "resolves #42" / "closed #7".
    if [[ "$line" =~ (^|[^[:alnum:]_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+ ]]; then
      printf '%s:tracker-ref:closing-keyword\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi

    # issue / issues / tracked references (the # is optional here).
    if [[ "$line" =~ (^|[^[:alnum:]_])(issues?|tracked)[[:space:]]*:?[[:space:]]*#?[0-9]+ ]]; then
      printf '%s:tracker-ref:issue-reference\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi

    # owner/repo#N — same- or cross-repo issue reference (e.g. org/app#123). The
    # owner segment excludes '.' — the only character needed to keep a bare domain
    # host (e.g. foo.com/bar#3 or example.com/page#2) from being misread as
    # owner/repo, since a dotted host cannot be an owner. '_' stays in the owner
    # class because GitHub Enterprise Managed User logins carry an '_SHORTCODE'
    # suffix (e.g. mona-cat_octo), so dropping it would miss real owner refs in
    # EMU repos. The repo segment also keeps '.' and '_' because repository names
    # allow them; the leading boundary still excludes '.'/'-' so a host embedded
    # mid-token is not a match start either.
    if [[ "$line" =~ (^|[^[:alnum:]_/.-])[A-Za-z0-9_-]+/[A-Za-z0-9._-]+#[0-9]+ ]]; then
      printf '%s:tracker-ref:repo-issue\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi

    # GH-N shorthand.
    if [[ "$line" =~ (^|[^[:alnum:]_])GH-[0-9]+ ]]; then
      printf '%s:tracker-ref:gh-reference\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi

    if [[ "$line" =~ (^|[^[:alnum:]_])PR[[:space:]]*#[0-9]+ ]]; then
      printf '%s:tracker-ref:pr-reference\n' "$lineno"
      violations=$((violations + 1))
      continue
    fi
    # Jira-style keys (PROJ-123) are intentionally NOT matched: the bare
    # LETTERS-NUMBER shape collides with technical tokens (UTF-8, SHA-256,
    # ISO-8601, RFC-2119, CVE-2025-…, P-256) and POSIX ERE cannot exclude them.
    # Deferred until a Jira-using consumer supplies an explicit project-key list.
  done < <(awk '/^[[:space:]]*(\/\/|#|\/\*|\*|<!--)/ { print NR ":" $0 }' <<<"$content")

  if [[ $nocase_was -eq 0 ]]; then
    shopt -u nocasematch
  fi
  if [[ $violations -gt 0 ]]; then
    return 1
  fi
  return 0
}
