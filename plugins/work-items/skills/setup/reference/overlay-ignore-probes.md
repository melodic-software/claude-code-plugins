# Verifying the personal-overlay ignore state

How `apply` step 5 and `check` probe 2 establish that `.work-item-tracker.local.json` is
ignored **and** untracked. Both surfaces assert the same condition, so both run the same
probes; this file is the single description of them.

## Why one probe is not enough

The overlay must be both **ignore-matched** and **absent from the index**, and those are two
independent facts that need opposite remediations. A bare `git check-ignore` cannot separate
them: it consults the index first and reports nothing (exit 1, no output) for a path that is
already tracked, because gitignore rules do not apply to tracked files. So its silence means
either "no rule covers this" or "a rule covers it but the file was committed anyway" — and
reading that silence as the former makes `apply` append an ignore line that changes nothing,
then announce it as the fix while a credential-bearing file stays in team history.

Sibling `source-control` documents the same trap for its own local overlay
(`/source-control:setup`, its `layer=local` overlay).

## The probes

Run both as one Bash tool call:

```bash
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
OVERLAY=".work-item-tracker.local.json"
# Is the path IGNORED? Two flags, each load-bearing:
#   --no-index answers on gitignore's terms alone, so an already-tracked file cannot mask
#              the answer the way it does for a bare check-ignore.
#   NO -v here. With -v, git reports NEGATION patterns too and still exits 0, so the exit
#              code would mean "some pattern matched", not "the path is ignored" — under a
#              `*.json` + `!.work-item-tracker.local.json` pair the overlay is NOT ignored
#              yet `-v` exits 0. Only the bare exit code is a truth value.
# The overlay path does not need to exist; the rule must be in place first.
git -C "$REPO_ROOT" check-ignore --no-index -q -- "$OVERLAY" && IGNORED=1 || IGNORED=0
# An ignore rule does not untrack an already-committed file, so ask the index separately.
TRACKED="$(git -C "$REPO_ROOT" ls-files -- "$OVERLAY")"
# Only for the human-readable report and for source inspection, never as the
# ignored/not-ignored verdict. --no-index still consults info/exclude and
# core.excludesFile; those are operator-local and do not protect a teammate.
[ "$IGNORED" -eq 1 ] && IGNORE_MATCH="$(git -C "$REPO_ROOT" check-ignore --no-index -v -- "$OVERLAY")"
if [ "$IGNORED" -eq 1 ]; then
  IGNORE_SRC="${IGNORE_MATCH%%:*}"
  case "$IGNORE_SRC" in
    .gitignore|*/.gitignore) ;;
    *) IGNORED=0 ;;
  esac
fi
```

## Branching on the pair

| `TRACKED` | `IGNORED` | verdict |
| --- | --- | --- |
| non-empty | either | **STOP / FAIL** — tracked overlay |
| empty | `0` | not covered — `apply` appends the line; `check` FAILs |
| empty | `1` | correct state — report `$IGNORE_MATCH`, change nothing |

- **Tracked** is the serious one and outranks the ignore state: the overlay is in team history
  and may carry per-user auth identity. Remediation is
  `git rm --cached .work-item-tracker.local.json`, plus rotating any credential that was
  committed. Never append the ignore line here — it does not untrack an already-committed
  file, and reporting it as the fix would paper over exactly the failure this check exists to
  catch. When both conditions hold, name the tracked one as the finding.
- **Untracked and not covered** is the ordinary case `apply` fixes: append
  `.work-item-tracker.local.json` to the consumer's `.gitignore` and **announce the edit**
  (the ADR 0015 declared exception; touch nothing else in that file). This is also the correct
  remediation when a negation rule is what left the path exposed, since the last matching rule
  wins. `check` reports the same condition as a FAIL rather than editing.
- **Untracked and covered** needs no action from either surface.
