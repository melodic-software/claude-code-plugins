# Changelog

All notable changes to the `x` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-24

### Added

- `skills/read` — returns an X post, note tweet, or X Article as Markdown via a documented three-step
  fallback ladder: `xtomd.com` `POST /api/markdown` for a single post or article, Thread Reader App
  over `WebFetch` for an unrolled reply chain, then an explicit ask for the remaining post URLs.
- Mandatory URL gate ahead of the ladder: anchored match against the post and article forms, outright
  refusal on no match, and rebuild-from-captures (`[A-Za-z0-9_]`, `[0-9]`) that discards the input
  string. Closes an argument-injection surface found in pre-release review, where a URL containing an
  apostrophe broke out of the request body's quoting and contributed a second unconstrained URL plus
  an `-o` arbitrary-write flag to the receiving process — reproduced at `argv` level in both bash and
  PowerShell. Rebuilding also strips query strings, so share-tracking tokens are never transmitted.
- Trust boundary in the skill body: converter output is attacker-authored text, treated as data to
  report and never as instructions, with fetched text barred from introducing any URL, host, or file
  path. Every URL re-enters the gate, including ones supplied at step 3 or surfaced inside fetched
  content. Documented as an advisory, model-honored defense rather than a runtime-enforced one.
- Transport bounds on the step-1 call: `--proto '=https'`, `--max-time`, `--max-filesize`, and no
  `-L`, so no redirect-driven egress. The byte cap is documented as best-effort — before curl 8.4.0
  `--max-filesize` does not stop an unknown-length response, so `--max-time` is the bound that always
  holds.
- The Windows scratch files (request body and curl config) are named for the gate-captured id plus a
  per-invocation nonce, and deleted once the request returns. The nonce matters because of the
  cleanup: without it two sessions reading the same post share a path, and the first to finish
  deletes both files while the second still waits at its permission prompt. Cleanup keeps reading
  many posts from accumulating files or building a local history of submitted X URLs.
- `-q` leads every curl invocation on both paths. curl reads a default `.curlrc` "even when
  `--config` is used" and skips it only when `--disable` "is used as the first parameter on the
  command line", so without it a consumer's ambient config could set `location` and silently
  re-enable redirect following, defeating the egress bounds above.
- `curl` declared as a required-for-correctness prerequisite at step 1, with a visible degrade to
  step 2 on absence — the xtomd endpoint is POST-only, so `WebFetch` cannot substitute.
- Thread Reader App miss detection by final URL (`.../thread/<id>/error`) rather than status code,
  which stays `200` on a miss.
- Evidence-driven escalation: step 2 runs only on positive continuation evidence — an explicit thread
  request, text ending mid-thought, or `1/`-style markers — with length treated as evidence in
  neither direction. Empirically grounded: a genuine 12-post chain returns `isNoteTweet: false` with
  a 346-character root. The flag reports a long-form representation rather than the absence of
  replies, so it suppresses length-only escalation without overriding continuation evidence.
- Status capture (`-w '\n%{http_code}'`) and explicit handling for `400`/`429`/`500`/`502`, timeouts,
  and `200` responses carrying no converted content, so a bot-challenge or stub page is never
  reported as an empty post.
- `skills/read/context/failure-modes.md` — progressive-disclosure spoke holding status-code handling,
  Thread Reader miss detection, and the observed-gotchas list.
- `skills/read/evals/evals.json` — twelve cases covering step-1 resolution, chain escalation,
  note-tweet non-escalation, `502` handling without a retry loop, prompt-injection containment, the
  missing-`curl` path, refusal of a hostile URL string, tracking-parameter stripping, a URL harvested
  from fetched content re-entering the gate, `isNoteTweet` governing escalation, step-1-success plus
  step-2-miss reaching step 3, and a `200` without conversion treated as failure.

### Fixed

- Absent `curl` no longer routes a single post to step 2. Step 2 resolves chains only, so that path
  returned nothing and read as if content had been lost; a single post is now correctly reported as
  unreadable without `curl`.
- Step 3 now triggers whenever the requested content is still incomplete, not only when both services
  fail — covering the common step-1-success-plus-step-2-miss case that previously risked presenting a
  chain root as a complete thread.
- Thread Reader miss detection no longer relies solely on the `/error` suffix; a landing, rate-limit,
  or challenge page returning `200` is also treated as a miss.
- Attribution now uses the gate's rebuilt URL rather than the URL the converter echoed back, which is
  third-party output and attacker-influenced under the skill's own trust model.

### Security

- No Bash or PowerShell tool pre-approval ships. A prefix permission rule cannot express "and no
  further flags" — its trailing wildcard admits every appended argument, which would have suppressed
  the prompt on exactly the injected command above. The step-1 network call therefore prompts,
  showing the operator the exact command. `allowed-tools` retains only
  `WebFetch(domain:threadreaderapp.com)`, which involves no shell. A validating `PreToolUse` hook is
  deferred, with re-introducing a shell grant as its trigger.
- Long-article file redirects are bounded to a `<plugin-data-dir>/x-article-<id>-<nonce>.md` template
  built from the gate-captured id plus a per-invocation nonce — never an agent-chosen path, never one
  derived from fetched content — and the file is deleted once its slice has been read. The nonce
  prevents two sessions reading the same article from sharing a path, where the second `curl` would
  truncate the file between the first request completing and that session's `Read`.
- Gate patterns are presented in fenced code blocks rather than a Markdown table. In table cells the
  alternation had to be written `\|` to survive the renderer, and a model reading the raw source
  could take that as a literal backslash-pipe and refuse every `twitter.com` URL.
- The PowerShell request body drops its backslash escaping. PowerShell single-quoted strings are
  fully literal, so `'{\"url\":...}'` sends literal backslashes and the server rejects the body as
  malformed JSON — silently breaking step 1 on Windows without Git Bash.
- Response validation is scoped to the requested form. The documented step-1 call sends
  `Accept: text/markdown`, whose success response is raw Markdown with no JSON envelope; the earlier
  blanket "`200` with no `markdown` field is a failure" rule therefore classified every successful
  conversion as a failure. The field check now applies only to the JSON form.
- Eval 1 no longer expects attribution from the converter-echoed URL, which contradicted the
  reporting contract's requirement to attribute with the gate's rebuilt URL.
- Escalation no longer treats `isNoteTweet: true` as proof a post has no replies. The flag describes
  a post's long-form representation, and a chain can legitimately begin with a note tweet, so the
  earlier unconditional stop would have returned only the root even when the whole thread was asked
  for. Escalation now requires positive continuation evidence and ignores length in both directions.
- The Windows PowerShell request is issued through a curl config file (`curl.exe -K <path>`) rather
  than inline arguments. PowerShell 7.3 changed native-argument parsing in a way Microsoft documents
  as a breaking change from 5.1, so no inline form is portable: unescaped quotes are stripped under
  `Legacy` while backslash-escaped quotes arrive literally under `Standard`/`Windows`. A config file
  leaves the command line with a single unquoted-content argument, so quoting is parsed by curl and
  the marshalling-mode question does not arise. Both the config and the body file are named for the
  gate-captured id, so concurrent sessions cannot race on a shared path.
- Reference files use a `<plugin-data-dir>` slot rather than `${CLAUDE_PLUGIN_DATA}`, per the
  repository convention that SKILL.md is the only surface where that token expands. PowerShell would
  in any case read `${NAME}` as its own brace-variable syntax and resolve an undefined variable.
