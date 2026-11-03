# 2.4.2 Pre-create gate

Part of [Phase 2: Create](create.md), which lists every section's file; a bare § number names a section listed there.

Before creating the PR, run two independent checks against the body file `$BODY_FILE`: the closing-keyword check and the required-section check (generic: it reads `pr_body_required_sections`, never a hardcoded section list). Both must pass.

A PR create or edit command issued **outside** this skill meets the plugin's `pr-body-linkage-gate` PreToolUse hook instead, where the repository wires in its own PR-contract check (a workflow that `uses:` the `pr-contract` composite step). The hook blocks only a statically-readable body carrying a negated closing reference, since CI reports a missing closing line or section as advisory; [`../../../hooks/pr-body-linkage-gate.sh`](../../../hooks/pr-body-linkage-gate.sh) has its scope guard and coverage limits. On this skill's path its gate runs first, and the hook still blocks a drafted body carrying a negated closer.

## 2.4.2.1 Verify closing-keyword line

Grep `$BODY_FILE` for a valid closing keyword, a non-closing `Refs:` marker, an opt-out marker, or a link line [§2.4.0](create-linked-issue.md) took from the bound tracker's adapter (whose grammar need not be GitHub's). This catches a §2.4.0 fall-through (issue-existence check failed without the orphan-PR prompt running, user dismissed the prompt, `$CLOSES_LINE` empty) so no PR ships without a linkage signal.

```bash
# Case-insensitive — covers ALL 9 valid keywords (close/closes/closed/fix/
# fixes/fixed/resolve/resolves/resolved) with optional colon, per GitHub's
# linked-issues docs. The 3-keyword shortcut (Closes|Fixes|Resolves)
# misses 6 valid forms GitHub auto-close honors.
KEYWORD_REGEX='^(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):? #[0-9]+'
# Non-closing linkage, mirroring NON_CLOSING_ERE in hooks/pr-linkage-validator.sh:
# `Refs: #N` / `Relates to: #N`, colon required, alone on its line. A bare
# `Refs #N` is not linkage, so it is not accepted here.
NON_CLOSING_REGEX='^ {0,3}(refs|relates[[:blank:]]+to):[[:blank:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[[:blank:]]*$'
OPTOUT_REGEX='^No related issue:'

if grep -qiE "$KEYWORD_REGEX" "$BODY_FILE"; then
  :  # closing keyword present — gate passes
elif grep -qiE "$NON_CLOSING_REGEX" "$BODY_FILE"; then
  :  # non-closing Refs:/Relates to: marker present — gate passes
elif grep -qE "$OPTOUT_REGEX" "$BODY_FILE"; then
  :  # explicit opt-out present — gate passes
elif [[ -n "$CLOSES_LINE" ]] && grep -qxF -f <(printf '%s\n' "$CLOSES_LINE") "$BODY_FILE"; then
  :  # a link line §2.4.0 took from the bound tracker's adapter (`Closes ENG-123`,
     # `Refs: SW2-12`) is present on its own line — gate passes
else
  # No closing keyword, non-closing marker, or opt-out. §2.4.0's orphan-PR prompt
  # should have populated one. If we reach here, either the prompt was
  # skipped or `$CLOSES_LINE` is empty.
  echo "⚠ PR body lacks a native closing keyword (Closes/Fixes/Resolves #N, case-insensitive, optional colon), a non-closing \"Refs: #N\" (or \"Relates to: #N\") on its own line, and a \"No related issue:\" opt-out." >&2
  echo "  Re-run §2.4.0's orphan-PR prompt to choose: Closes #N | Refs: #N | No related issue: <reason>" >&2
  echo "  Aborting PR creation. (Silent proceed would orphan the PR from any tracked issue.)" >&2
  exit 1
fi
```

An explicit `No related issue: <reason>` from §2.4.0 passes silently; the opt-out is legitimate for refactors, drift sweeps, and hotfixes.

## 2.4.2.2 Verify required sections (config-driven)

For every heading in `${REQUIRED_SECTIONS[@]}` (resolved in [§2.4.1](create-push-and-body.md) from `pr_body_required_sections`, or the `briefing` default), confirm a `## <heading>` section exists in `$BODY_FILE` **and** its body is non-empty. `scripts/check-body-sections.sh` judges this with the shared section checker in `hooks/pr-linkage-validator.sh`, which defines what counts as a heading or as content (comments, code, heading levels). It verifies whatever the resolved config lists, never a section name baked into this skill. A resolved `none` (§2.4.1) leaves `${REQUIRED_SECTIONS[@]}` empty, so this check passes with nothing to verify; the §2.4.2.1 closing-keyword check still runs. The gate checks presence and non-empty content only; placeholder-text detection (`TBD`/`TODO`/a restated heading) and per-section minimum-content rules are out of scope here (see [`docs/contracts/pr-body-convention/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/contracts/pr-body-convention/README.md)).

```bash
if ! bash "<skill-dir>/scripts/check-body-sections.sh" "${REQUIRED_SECTIONS[@]}" <"$BODY_FILE"; then
  echo "  Required sections resolved from: ${REQUIRED_SECTIONS_SOURCE}" >&2
  echo "  Add each missing '## <heading>' with real content, then re-run create." >&2
  echo "  Aborting PR creation. (Silent proceed would ship a body that fails the same check downstream.)" >&2
  exit 1
fi
```

The message names the missing heading(s) and the resolved config source (§2.4.1's `${REQUIRED_SECTIONS_SOURCE}`: the winning layer's file path, or the plugin default when no layer sets the key), so the failure itself shows where the convention lives.
