# eol-normalizer

A Claude Code plugin that normalizes a file's working-tree line endings the
moment you edit it. On every `Write` or `Edit` it resolves the file's
`.gitattributes` `eol=` value via
[`git check-attr`](https://git-scm.com/docs/git-check-attr) and rewrites the
file's line endings to match — symmetric CRLF↔LF, idempotent, best-effort.

It uses **your repository's own `.gitattributes`** — it ships no policy and
imposes no rules of its own.

## Behavior

- **LF arm (every OS).** A file resolving to `eol=lf` is normalized CRLF→LF.
- **CRLF arm (every OS).** A file resolving to `eol=crlf` is normalized
  LF→CRLF. The hook compensates for tool writes that bypass git's checkout
  smudge, and such writes happen on any platform — an LF write to an
  `eol=crlf` path violates the repo's policy on Linux/macOS just as much as on
  Windows.
- **Binary guard.** `eol` alone is not proof of text: under a broad
  `* text=auto eol=lf` rule, the `eol` attribute resolves to `lf` for binaries
  too. The hook mirrors gitattributes semantics — explicit `text` is trusted,
  `-text` skips, and `text=auto` content-sniffs (NUL scan of the first 8000
  bytes, git's own detection window) — so binary files are never rewritten.
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

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
