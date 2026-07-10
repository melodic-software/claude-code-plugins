# eol-normalizer

A Claude Code plugin that normalizes a file's working-tree line endings the
moment you edit it. On every `Write` or `Edit` it resolves the file's
`.gitattributes` `eol=` value via
[`git check-attr`](https://git-scm.com/docs/git-check-attr) and rewrites the
file's line endings to match — symmetric CRLF↔LF, idempotent, best-effort.

It uses **your repository's own `.gitattributes`** — it ships no policy and
imposes no rules of its own.

## Behavior

- **LF arm (every OS).** A file resolving to `eol=lf` is normalized CRLF→LF
  unconditionally. LF is correct on every platform — a CRLF-contaminated `.sh`
  or `requirements.txt` breaks shebangs and parsing everywhere — so this arm is
  never OS-gated.
- **CRLF arm (Windows only).** A file resolving to `eol=crlf` is normalized
  LF→CRLF only on Windows. On Linux/macOS, git's checkout smudge already yields
  CRLF for those paths; the only way such a file lands as LF on disk is a Windows
  write that bypasses smudge, so the arm self-gates to Windows.
- **Unspecified → no-op.** A path with no `eol=` attribute is left untouched.
  There is no hardcoded extension list — resolution is entirely
  `.gitattributes`-driven, so narrow rules (a single `eol=lf` path) correctly
  win over broad ones (`*.txt eol=crlf`).
- **Advisory, never blocking.** The hook always exits `0`. Make a commit hook or
  CI (`git add --renormalize`, an EditorConfig check) your hard gate.

## Requirements

- **git** on `PATH` — the attribute resolution (`git check-attr`) and repo-root
  detection depend on it. Without a git repository the hook is a silent no-op.

Rewriting uses `perl` when present, falling back to `tr`/`awk` otherwise, so no
extra tooling is required.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while normalization
still runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install eol-normalizer@melodic-software
```

## Configuration

This plugin has no `userConfig` — its only "configuration" is the
`.gitattributes` already in your repository, which it reads automatically. To
change which files normalize to which endings, edit your `.gitattributes`.

### Disable without uninstalling

Set the kill switch in your settings `env` block:

```json
{ "env": { "HOOK_EOL_NORMALIZER_ENABLED": "false" } }
```

## License

[MIT](../../LICENSE).
