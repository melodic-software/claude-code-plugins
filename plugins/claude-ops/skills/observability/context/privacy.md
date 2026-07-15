# `/observability` privacy filter

Defense-in-depth redaction at output time. Write-time enforcement (in `hook::record_event`) is primary; read-time filter here catches drift if a hook ever logs raw command/prompt content.

## Hard rules

| Field / pattern | Action | Reason |
|---|---|---|
| `subject` containing path | KEEP | Path is intended signal — leak risk is low; debugging value high |
| `subject` containing full command (`>50 chars` AND containing `\|`, `&&`, `&`, `>`, `<`) | REPLACE with first token + `[truncated]` | Hook bug — should never have logged full cmd; defensive trim |
| `cwd` field | KEEP | Already a path |
| Field values matching env-var deny list (see below) | REPLACE with `[redacted-env]` | Catches accidental env-var-as-subject |
| Lines containing 8+ char base64-like token (`[A-Za-z0-9+/]{32,}={0,2}`) | REPLACE token with `[redacted-token]` | Catches accidental secret leak |
| File contents excerpts | REMOVE | Should not appear in any source; if present, hook bug |
| Prompt text snippets | REMOVE | Should not appear in any source; if present, hook bug |

## Env-var deny list (literal field-value match)

Strings matching any of these names trigger redaction of the **value**:

```text
AWS_SECRET_ACCESS_KEY  AWS_SESSION_TOKEN
GITHUB_TOKEN  GH_TOKEN  GITHUB_PAT
ANTHROPIC_API_KEY  OPENAI_API_KEY  PERPLEXITY_API_KEY
MIRO_API_TOKEN  AZURE_*_KEY  AZURE_*_SECRET
DATABASE_URL  CONNECTION_STRING
*_PASSWORD  *_SECRET  *_TOKEN  *_KEY
```

Case-insensitive substring match on the **field name** if reading structured data. For free-text fields, match the **value** against shape heuristics (length + character class).

## Redaction implementation

```bash
redact() {
  # stdin → stdout, applies all rules
  sed -E '
    # Token-shaped strings
    s/[A-Za-z0-9+/_-]{32,}={0,2}/[redacted-token]/g
    # Env-var assignments in subject fields
    s/(AWS_[A-Z_]*|GITHUB_[A-Z_]*|.*_TOKEN|.*_KEY|.*_SECRET|.*_PASSWORD)=[^[:space:]"]*/\1=[redacted]/gi
  '
}
```

Apply just before final stdout / file write — never to the raw JSONL input.

## What is NEVER redacted

- File paths (the whole point of `subject` is path-anchored signal)
- Hook names, event names, exit codes, durations
- Branch names, commit SHAs (these are public via `git log`)
- Cost/token totals (no PII)
- Statusline payload — by spec contains no user content

## Trust boundary

Source files (`hook-events.jsonl`) are gitignored. They never leave the repo unless the user explicitly shares the `/observability` report or copies the JSONL elsewhere. The privacy filter assumes the report MAY be shared (e.g., pasted into chat, attached to issue) and prevents the worst leaks.

Does NOT defend against:

- Adversarial hook authors deliberately writing secrets to `subject` (write-time deny list is the gate there)
- File contents already on disk in unrelated paths (out of scope)
- Memory feedback files in `~/.claude/projects/<slug>/memory/` containing user free-text (read selectively; see below)

## Memory feedback handling

When reading `~/.claude/projects/<slug>/memory/feedback_*.md` for the calibration signal (Section 6 of report), only count occurrences — never include feedback text in output. Format:

```
"<N> dismissals matching 'side observation' / 'noticed' / 'mentioned'"
```

Never:

```
"User dismissed: '<actual feedback content>'"
```

## Recheck triggers

- New env-var pattern lands in `settings.local.json` or workflows → add to deny list
- Hook author proposes logging richer subject → require write-time redaction in their hook before merge
- ccusage MCP starts returning prompt previews (it doesn't today) → add filter

## Cross-references

- Write-time enforcement: the consumer's hook emitter owns what lands in `subject` — keep it path-only (no content, no URLs with tokens)
