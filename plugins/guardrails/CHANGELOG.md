# Changelog

All notable changes to the `guardrails` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.1]

### Fixed

- **`block-hook-bypass` no longer false-fires when an `echo`/`printf` token and a
  `>` redirect merely co-occur in one Bash command.** The `echo > file` heuristic
  matched any command string containing both tokens, so capturing a subprocess's
  stdout to a scratchpad data file (`bash fetch.sh 526 > pr526.json && echo
  "EXIT: $?"`), a bounded poll loop with a status `echo`, or a `gh issue create
  --body "…"` whose text merely mentions the tokens were all blocked. The check is
  now producer-scoped: it splits the literal-stripped command into simple-command
  segments and flags only a segment whose command word is `echo`/`printf` AND that
  redirects stdout into a real file — so the redirect's producer must be the
  echo/printf, not a co-located but unrelated one. It correctly fires inside loop,
  conditional, and brace-group bodies (`for …; do echo x > f; done`). The
  literal-strip now also carries an open quote across physical lines, so a
  multi-line quoted argument (a `--body "…"` payload spanning newlines) stays
  inert instead of leaking its tokens from the second line on. `printf … > file`
  content-authoring is now caught alongside `echo … > file`.
- **The producer scan now peels command prefixes, so a producer hidden behind a
  valid shell prefix is no longer a trivial bypass.** The head-only producer match
  looked only at a segment's first token, so `FOO=bar echo x > file`,
  `command echo x > file`, `builtin printf x > file`, and `env echo x > file` all
  slipped through even though their stdout is redirected into a real file — the
  prior anywhere-in-command detector caught them. The segment head now peels
  environment assignments and the command-name modifiers `command`/`builtin`/
  `exec`/`env` before the echo/printf check, closing that hole. Peeling is
  block-safe: the producer gate still requires echo/printf, so revealing a
  non-producer command word never causes a block. External command-runner
  utilities that carry their own options (`nohup`/`nice`/`time`/`timeout`/`sudo`/
  `xargs`, non-bare `env`) remain an accepted, documented floor.
- **An fd-duplication redirect before the stdout redirect no longer splits the
  producer off from its `> file`.** Segmenting on every `&` cut `echo x 2>&1 >
  file` and `echo x >&2 > file` at the dup's `&`, orphaning the trailing stdout
  redirect so neither blocked. The `&` in a redirect (`>&`, `<&`, `&>`) is now
  protected from the control-operator split, so the simple command stays one
  segment and its `> file` is scanned as the echo's own; `&&` and a background
  `&` still split as separators.
- **Compound-command headers and pipeline negation before a producer are now
  peeled.** `! echo x > file`, `if echo x > file; then …`, and the `while`/`until`/
  `elif` forms wrote the file yet slipped past the head-only match, since only
  `do`/`then`/`else`/`{` were peeled. The header set now also peels
  `if`/`elif`/`while`/`until`/`!`, completing the before-command keyword class.
- **An unmatched quote inside a `#` comment no longer leaks a quote span onto the
  next line.** `strip_literals` carries an open quote across physical lines, so an
  unclosed `"` in a trailing comment (`true # "`) previously stripped the following
  line's real producer as a quoted span, and `true # "` + newline + `echo x > file`
  returned 0. An unquoted `#` at a word boundary (line start, or after a blank or
  one of `;|&()<>`) is now dropped to end-of-line WITHOUT touching the quote state,
  so the comment cannot leak a span. A mid-word `#` (`echo a#b > file`) and a
  parameter expansion (`${v#x}`) stay literal, so those real writes still block.
- **A leading redirection before the command word no longer hides the producer.**
  Bash permits redirections before the command word, so `> real.txt echo x` writes
  the file, yet the segment-head producer match (anchored at `^(echo|printf)`) never
  saw it and returned 0. A leading redirect is now peeled (operator + its target
  word) to expose the producer, while the redirect itself stays in the segment so
  `_echo_file_out`/`_echo_devnull` still decide whether a real write exists — a
  leading input redirect or `/dev/null` discard stays allowed.
- **The bare `coproc` header before a producer is now peeled.** `coproc echo x >
  file` writes the file but `coproc` was absent from the peeled header set, so it
  returned 0. `coproc` is added to the command-header peel. Only the bare keyword is
  peeled; the named form `coproc NAME { … }` remains a documented floor (NAME is
  indistinguishable from a command word by prefix-peeling, and its redirect is
  group-level — the same brace-group floor).
- **Options of the `command`/`exec` modifiers are now peeled too.** Both were
  peeled but their options were not, so a producer behind a valid option leaked:
  `command -p echo x > file` and `exec -a name echo x > file` wrote the file yet
  returned 0. The producer scan now also peels the modifier options documented by
  bash built-in help (`command [-pVv]`, `exec [-cl] [-a name]`, and a `--`
  end-of-options marker), consuming the value word of the argument-taking
  `exec -a name` so the echo/printf behind it is still seen. Option peeling applies
  only to `command`/`exec` — `env`/`builtin` keep their bare-only floor. As an
  exception, `command -v`/`-V` DESCRIBE their argument instead of running it, so
  `command -v echo > file` (which writes the word "echo", not echo's output) stays
  allowed — the guard blocks only a genuine echo/printf producer.
- **Backslash-escaped separators no longer split a producer from its redirect.**
  The segment split treated an escaped separator as a command boundary, so
  `echo x \; > file` and an escaped-newline continuation (`echo x \` + newline +
  `> file`) — both a single simple command in bash that writes the file — landed
  the producer and its `> file` in different segments and returned 0. Escaped
  separators (`\;`, `\|`, `\&`, `\(`, `\)`, and an escaped newline) are now
  protected from the split so the simple command stays one segment.

## [0.8.0]

### Changed

- All seven hook entry scripts read stdin via the shared `hook::buffer_stdin` helper
  (bounded `read -t`, default 2s) instead of a bare `cat`, so a Windows Win32-pipe
  late-EOF stall can no longer hang a hook — and with it every tool call — indefinitely.
- **Blocking guards now fail closed on a stdin read timeout.** When `hook::buffer_stdin`
  returns 2 (the read timed out before a complete JSON payload arrived), the five
  blocking guards (`block-dangerous-git`, `block-hook-bypass`, `block-no-verify`,
  `secret-pattern-detection`, `hardcoded-path-check`) exit 2 with the BLOCKED reason on
  stderr instead of skipping: a guard that could not evaluate the tool call must not
  wave it through. Empty stdin still skips, matching the previous empty-payload
  behavior. The two advisory hooks (`flag-commit-pr-skill-bypass`,
  `workflow-resilience-check`) skip on any read failure, as before.

## [0.7.1]

### Fixed

- **`flag-commit-pr-skill-bypass` jq-absent skip is now visible** (prerequisite-visibility
  doctrine). The hook previously no-op'd silently when `jq` was missing; it now writes the
  same one-line stderr notice its sibling guardrails hooks emit ("advisory disabled —
  install jq to enable") before exiting 0.

## [0.7.0]

### Added

- **`/guardrails:setup` skill on the uniform contract** (fleet conformance
  wave, dim 8). `check` reads the guard scripts and `hooks.json` as the
  source of truth and probes Bash 5.0+, `jq` (absence = every guard fails
  open — surfaced as the FAIL it is), each guard's effective toggle, the
  `cli-flag-verify` scan surface, and the `block-dangerous-git` allowlist.
  `apply` is guidance-only with no write path; reconfiguration guidance
  states `--config`'s fresh-install-only semantics. All-toggles-disabled
  downgrades prerequisite FAILs to INFO.

## [0.6.2]

### Changed

- Header comment ordering in `machine-path-patterns.sh` corrected to the `shell=bash` →
  description → pragma → code convention: the `SC2034` disable and its rationale comment now
  sit immediately before the pattern definitions they guard, instead of ahead of the module
  description. Comment-only change; pattern bodies are unchanged.

## [0.6.1]

### Changed

- **Per-OS machine-path regex bodies sourced from a shared, standards-managed file.** The five
  `HPP_*` pattern bodies (`HPP_WIN_USER_BODY`, `HPP_MACOS_USER_BODY`, `HPP_LINUX_USER_BODY`,
  `HPP_WIN_REPO_BODY`, `HPP_ESCAPED_WIN_REPO_BODY`) — previously a hand-synced copy of the same
  bodies carried by `ci-workflows`' `machine-specific-paths` action and `medley`'s
  `tools/shared/path-detection` — now live in `machine-path-patterns.sh`, the org's
  standards-managed materialization (`melodic-software/standards#172`). `hardcoded-path-patterns.sh`
  sources it and keeps only its own scan wrapping (OS-context suppression, exclusion pipes).
  Patterns are byte-identical to the prior inline copy; no behavior change.

## [0.6.0]

### Added

- **`block-dangerous-git` guard** (PreToolUse on Bash, blocking): stops irreversible git operations
  before they run — `push --force`/`-f` (never `--force-with-lease`), the equivalent
  leading-`+` refspec and `--mirror` force-push forms (a push dry-run disarms), `reset --hard`,
  `clean` with a force flag (a dry-run flag anywhere disarms the check — git honors it regardless
  of order), worktree-wide `checkout`/`restore` pathspecs (`.`, `:/`, exclude-only sets, and
  long-form magic carrying `top`; path-scoped forms and index-only `restore --staged .` pass), and
  forced `checkout -f`/`--force` and `switch -f`/`--discard-changes` (both throw away local
  modifications). Accepted unique-prefix abbreviations of the blocked long options match too
  (git parse-options accepts them: `reset --h` runs `--hard`). The parse-cap fail-closed path
  never consults the allow-list. `branch -D` is deliberately not blocked: deleted refs are
  reflog-recoverable and sanctioned skill flows issue it inline. Per-repo/per-user allow-list via
  the `block_dangerous_git_allow` userConfig option (comma list of `push-force`, `reset-hard`,
  `clean-force`, `checkout-dot`, `restore-dot`, `checkout-force`); kill switch the
  `block_dangerous_git_enabled` userConfig option set to false. Capability adapted from
  mattpocock/skills `git-guardrails-claude-code`; the implementation is the house argv-grammar
  parser, whose word-exact matching avoids upstream's substring false-blocks (all `git push`
  blocked; `checkout .github/…` matching `checkout .`).

### Changed

- The argv-grammar tokenizer, git-executable resolver, and subcommand walk that `block-no-verify`
  carried privately moved into the shared hook-utils library (`hook::bash_parse_segments`,
  `hook::git_resolve_index`, `hook::git_resolve_subcommand`) so both git guards share one parser.
  `block-no-verify` behavior is unchanged with one alignment: the `core.hooksPath` block now applies
  exactly to `git commit` / `git push` (its documented scope) instead of firing on any git
  subcommand mid-walk.

## [0.5.1]

### Changed

- Shared `hook-utils.sh` resynced with the fleet's new prerequisite-visibility
  helpers (jq-free notice emitters, once-per-session gate, jq gate). No
  behavior change for this plugin's guards: their documented jq fail-open with
  a stderr notice is unchanged.

## [0.5.0]

### Changed

- **Per-hook kill switches and tuning scalars migrated to native `userConfig`** (the
  fleet-wide kill-switch doctrine ruling). Each guard's toggle is now a `userConfig`
  boolean named `<guard>_enabled` (default `true`), read by the hooks through the
  native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror; `cli-flag-verify`'s binary
  set and skip list are now the `cli_flag_verify_bins` / `cli_flag_verify_skip_bins`
  options. Configure interactively with `/plugin configure guardrails` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_<NAME>_ENABLED`, `HOOK_CLI_FLAG_VERIFY_BINS`, and
  `HOOK_CLI_FLAG_VERIFY_SKIP_BINS` environment variables are retired and no
  longer read. A consumer that set any of these in a
  settings `env` block must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (all guards on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.
