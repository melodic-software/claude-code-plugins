# guardrails

A Claude Code plugin bundling five **safety guards** that catch risky agent
actions the moment they happen — before a write lands or a bash command runs.
Each guard is independently toggleable, so you run exactly the subset you want.

## The guards

| Guard | Event / matcher | Behavior | What it catches |
|-------|-----------------|----------|-----------------|
| **secret-pattern-detection** | PreToolUse · Write \| Edit \| NotebookEdit | **Blocks** (exit 2) | High-confidence secret/credential patterns (AWS/GitHub/GitLab/Slack/Stripe/OpenAI keys, PEM private keys) in new file content. |
| **hardcoded-path-check** | PreToolUse · Write \| Edit \| NotebookEdit | **Blocks** (exit 2) | Hardcoded machine-specific paths — Windows drive-letter homes, macOS/Linux user homes, machine-specific repo checkout roots. |
| **block-no-verify** | PreToolUse · Bash | **Blocks** (exit 2) | Git hook-bypass attempts on `git commit` / `git push`: `--no-verify` / `-n`, `core.hooksPath=` assignment, and `LEFTHOOK=0` / `LEFTHOOK_*=false` env-var prefixes (including inside compound `cd … && …` commands). |
| **block-hook-bypass** | PreToolUse · Bash | **Blocks** (exit 2) | Bash file-write workarounds that circumvent the Write/Edit hook gates — `cat > file`, `echo … > file`, and `python3 -c` with file-write indicators. Executable-token detection ignores quoted prose/commit text that merely mentions the pattern. |
| **cli-flag-verify** | PostToolUse · Write \| Edit | **Advisory** (exit 0) | Hallucinated CLI flags — a `--flag` written as a command that does not exist in the binary's actual `--help` output. Surfaces via `additionalContext`, never blocks. |

The four blocking guards feed their stderr message back to Claude as
actionable fix guidance. The advisory guard surfaces its findings the same way
but always allows the edit.

### Scope notes

- **Hook-manager coverage.** `block-no-verify` recognizes the **lefthook**
  env-var disable prefix (`LEFTHOOK=0` / `LEFTHOOK_*=false`). Other managers'
  disable env vars (husky, pre-commit, …) are **not** matched — but the
  manager-agnostic `--no-verify` / `-n` and `core.hooksPath=` checks catch those
  bypasses regardless of which manager runs the hooks.
- **Argv-grammar-faithful matching (and its residual).** `block-no-verify`
  parses the command the way the shell builds argv — segmenting on unquoted
  operators and tokenizing each segment honoring `'…'`, `"…"`, `$'…'` (ANSI-C),
  and backslash escapes. It detects literal `git commit`/`git push`
  `--no-verify` / `-n` / `core.hooksPath=` across quoting, escaping, wrappers
  (`env -i git …`, `nice git …`, `sudo -u x git …`), and git global options
  (`git -C <dir> commit …`). A `--no-verify` inside a quoted `-m` value stays a
  message, not a flag. It does **not** evaluate shell variable / command
  substitution (`$VAR`, `$(…)`, `$IFS`) — a determined author can construct an
  expansion-based bypass. **This is a friction guard against accidental/casual
  bypass, not a sandbox.** (A command longer than 16 KB is not parsed and is
  blocked fail-closed.)
- **`block-hook-bypass` string-matching floor.** Detection strips quoted literal
  spans before matching the executable token, so quoted prose or a commit
  message merely mentioning `cat >` / `python3 -c open(...)` is not flagged. The
  accepted residual: a write inside a command substitution in double quotes
  (`echo "$(python3 -c 'import pathlib …')"`) is **not** caught — the strip
  treats the quoted span as inert. Same friction-guard, not-a-sandbox posture as
  `block-no-verify`.

## Per-hook kill switches

Each guard is toggled by its own env var (default **on**; set to `false` for a
clean no-op). This per-hook control is the bundle's core contract — disable one
guard without touching the others.

| Guard | Kill switch |
|-------|-------------|
| secret-pattern-detection | `HOOK_SECRET_PATTERN_DETECTION_ENABLED` |
| hardcoded-path-check | `HOOK_HARDCODED_PATH_CHECK_ENABLED` |
| block-no-verify | `HOOK_BLOCK_NO_VERIFY_ENABLED` |
| block-hook-bypass | `HOOK_BLOCK_HOOK_BYPASS_ENABLED` |
| cli-flag-verify | `HOOK_CLI_FLAG_VERIFY_ENABLED` |

Set them in your settings `env` block:

```json
{ "env": { "HOOK_HARDCODED_PATH_CHECK_ENABLED": "false" } }
```

## Consumer seams

The guards scope and tune themselves to **your** repository — they ship no
repo-specific policy of their own:

- **Project scoping.** `secret-pattern-detection` and `hardcoded-path-check`
  only police files under `$CLAUDE_PROJECT_DIR`; a write into a sibling repo is
  that repo's concern. Secret scanning fails **closed** — if the project root
  cannot be resolved, it scans anyway.
- **Gitignore is the allowlist.** `hardcoded-path-check` skips any file
  `git check-ignore` matches against your `$CLAUDE_PROJECT_DIR` — put
  machine-local files (`settings.local.json`, `.venv/`, …) in your
  `.gitignore` and they are exempt automatically.
- **Secret allowlist.** A generic built-in allowlist exempts dependency caches
  (`.venv/`, `node_modules/`), `.env.example` / `.sample` / `.template`
  placeholders, `tests/fixtures` / `tests/testdata` trees, `settings.local.json`,
  `CLAUDE.local.md`, and hook scripts.
- **CLI-flag tuning.** `cli-flag-verify` checks a default binary set
  (`claude gh dotnet docker npm kubectl terraform az aws`); override with
  `HOOK_CLI_FLAG_VERIFY_BINS=bin1,bin2,…` and skip specific binaries with
  `HOOK_CLI_FLAG_VERIFY_SKIP_BINS=bin1,bin2`.

## Telemetry (opt-in)

Every guard emits one structured [hook-telemetry](../../docs/conventions/hook-telemetry/README.md)
envelope per run to whatever `HOOK_TELEMETRY_SINK` names — carrying `status`
(`blocked` on a guard block, `ok` otherwise), `duration_ms`, and a privacy-safe
`data` payload (category **labels** only — never a secret value, matched path,
or full command). Unset `HOOK_TELEMETRY_SINK` → no-op; the guards behave exactly
as before.

## Requirements

- **bash 5.0+** and **jq** — the guards' runtime. Without **jq**, each guard
  fails **open** (disabled) and prints a one-line stderr notice — never a silent
  disable.
- On Windows, **Git Bash** (the hooks run via Git Bash's bash).
- `cli-flag-verify` runs `<bin> --help` for the binaries it scans; findings
  require those binaries on PATH (missing binaries are skipped, never flagged).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install guardrails@melodic-software
```

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
