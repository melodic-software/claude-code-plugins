# `/harness-ops:observability` privacy filter

Defense-in-depth redaction at output time. Write-time enforcement (in `hook::record_event`) is primary; read-time filter here catches drift if a hook ever logs raw command/prompt content.

## Hard rules

| Field / pattern | Action | Reason |
|---|---|---|
| `subject` containing path | KEEP | Path is intended signal, leak risk is low, debugging value high |
| `subject` containing full command (`>50 chars` AND containing `\|`, `&&`, `&`, `>`, `<`) | REPLACE with first token + `[truncated]` | Hook bug, should never have logged full cmd; defensive trim |
| `cwd` field | KEEP | Already a path |
| Field values matching env-var deny list (see below) | REPLACE with `[redacted-env]` | Catches accidental env-var-as-subject |
| Lines containing 8+ char base64-like token (`[A-Za-z0-9+/]{32,}={0,2}`) | REPLACE token with `[redacted-token]` | Catches accidental secret leak |
| File contents excerpts | REMOVE | Should not appear in any source; if present, hook bug |
| Prompt text snippets, and the event log's content keys (`prompt`, `last_assistant_message`, `message` and the rest of the `session_event_log_content` list in data-sources.md, with their `<key>_truncated` and `content_truncated` markers) | REMOVE | Present in an event-log file only when the operator turned `session_event_log_content` on; a report never repeats them. Anywhere else, a hook bug |

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

Apply just before final stdout / file write, never to the raw JSONL input.

## What is NEVER redacted

- File paths (the whole point of `subject` is path-anchored signal)
- Hook names, event names, exit codes, durations
- Branch names, commit SHAs (these are public via `git log`)
- Cost/token totals (no PII)
- Statusline payload: by spec contains no user content

## Trust boundary

Source files (the hook log root's `sessions/*.jsonl`, `hook-events.jsonl` and its rotated `hook-events.jsonl.1`) sit in a tree that carries its own self-ignoring `.gitignore`. They never leave the repo unless the user explicitly shares the `/harness-ops:observability` report or copies the JSONL elsewhere. A per-session file also carries `file_path` values (repo-relative, or the basename when the file is outside the repo) and, for a `reason`-bearing event, the reason text the hook was given; both pass through the same filter below before any report. Whenever the event log is on, its rows carry `cwd`, `transcript_path` and `scratchpad_dir` (and the other path-valued keys) as the payload's raw absolute values, username and home directory included. The `session_event_log_content` option is off by default; turned on, rows also carry the events' content strings: prompt text, Claude's last message on `Stop` and `SubagentStop`, notification messages, task subjects and descriptions, `PostToolUseFailure` error output, and the other keys data-sources.md lists, limited by the hook's 64 KB read cap: a cut string that follows only scalar members is kept as a prefix with a `<key>_truncated` marker, one that follows a nested value is not recorded, and any row whose payload reached the cap carries `content_truncated: true`. Turn it on only where those files may hold that text. The privacy filter assumes the report MAY be shared (e.g., pasted into chat, attached to issue) and prevents the worst leaks.

Does NOT defend against:

- Adversarial hook authors deliberately writing secrets to `subject` (write-time deny list is the gate there)
- File contents already on disk in unrelated paths (out of scope)
- Memory feedback files in `~/.claude/projects/<slug>/memory/` containing user free-text (read selectively; see below)

## OTEL cold tier content boundary

The hot OTEL store keeps every attribute Claude Code sends, content included when its capture
flags are on. Two switches decide what compaction carries into cold Parquet:

| Switch | Covers | Default | Effect |
|---|---|---|---|
| `CC_OTEL_COLD_KEEP_USER_PROMPTS` | `user_prompt` bodies, the logs `prompt` and spans `user_prompt` columns, the `prompt` and `prompt_text` attributes | scrubbed | `=1` keeps them |
| `CC_OTEL_COLD_KEEP_CONTENT` | every other content-class column: response and model-output text, tool payloads (`content`, `output`, `diff`, `new_context`, `tool_input`, `tool_parameters`), command strings (`full_command`, `bash_command`), error text (`error`), configuration text (`hook_definitions`, `hook_matcher`, `system_prompt_preview`, `user_system_prompt`, `managed_settings_settings`), `user_email`, and absolute paths (`file_path`, `body_ref`, `workspace_host_paths`, `managed_settings_helper_path`) | kept | `=0` NULLs those columns and scrubs their attributes from the raw JSON |

Cold files are unbounded history, so with the default a cold file holds whatever content the
capture flags let through, absolute paths with the username among it. Set
`CC_OTEL_COLD_KEEP_CONTENT=0` where cold files may be shared or kept long. A compaction cannot be
undone: content it scrubbed is gone from cold. Files compacted under a keep switch are cleaned
with `prune-otel-store.sh --scrub-cold` run under the scrubbing switch. The authoritative column
list is the cold content boundary comment in `../otel/cc-otel.sql`.

## Memory feedback handling

When reading `~/.claude/projects/<slug>/memory/feedback_*.md` for the calibration signal (Section 6 of report), only count occurrences, never include feedback text in output. Format:

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

- Write-time enforcement: the consumer's hook emitter owns what lands in `subject`, so keep it path-only (no content, no URLs with tokens)
