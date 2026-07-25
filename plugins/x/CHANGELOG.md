# Changelog

All notable changes to the `x` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-24

### Added

- `skills/read` — returns an X post, note tweet, or X Article as Markdown via a documented three-step
  fallback ladder: `xtomd.com` `POST /api/markdown` for a single post or article, Thread Reader App
  over `WebFetch` for an unrolled reply chain, then an explicit ask for the remaining post URLs.
- Handle-less `/i/web/status/<id>` links — the form embeds, feeds, and legacy clients emit — match a
  separately anchored pattern and rebuild to `https://x.com/i/web/status/<id>`. The shape is kept
  rather than folded into the handle form: no handle was captured, and inventing one would breach
  rebuild-from-captures. The two `/i/` patterns are tried before the handle patterns, since `i` is a
  legal handle character and would otherwise capture `/i/web/status/<id>` as a handle of `i`.
- Mandatory URL gate ahead of the ladder: anchored match against the post and article forms, outright
  refusal on no match, and rebuild-from-captures (`[A-Za-z0-9_]`, `[0-9]`) that discards the input
  string. Closes an argument-injection surface found in pre-release review, where a URL containing an
  apostrophe broke out of the request body's quoting and contributed a second unconstrained URL plus
  an `-o` arbitrary-write flag to the receiving process — reproduced at `argv` level in both bash and
  PowerShell. Rebuilding also discards the host and any query string, so the `x.com`, `twitter.com`,
  `www.`, and legacy `mobile.` forms are all accepted and all collapse to a canonical `x.com` URL,
  and share-tracking tokens are never transmitted. Scheme and host match case-insensitively via a
  `(?i: … )` group that stops at `.com` — RFC 3986 makes both case-insensitive (§3.1, §3.2.2) while
  the path is not — so `HTTPS://X.COM/…` is admitted by the pattern rather than repaired into it. The
  scheme is discarded on rebuild like the host, so an `http://` link matches and still emits
  `https://`; `--proto '=https'` is the runtime backstop, and no plaintext request can be issued.
- Trust boundary in the skill body: converter output is attacker-authored text, treated as data to
  report and never as instructions, with fetched text barred from introducing any URL, host, or file
  path. Every URL re-enters the gate, including ones supplied at step 3 or surfaced inside fetched
  content. Documented as an advisory, model-honored defense rather than a runtime-enforced one.
- Transport bounds on the step-1 call: `--proto '=https'`, `--max-time`, `--max-filesize`, and no
  `-L`, so no redirect-driven egress. The byte cap is documented as best-effort — before curl 8.4.0
  `--max-filesize` does not stop an unknown-length response, so `--max-time` is the bound that always
  holds.
- `-q` leads every curl invocation. curl reads a default `.curlrc` "even when `--config` is used" and
  skips it only when `--disable` "is used as the first parameter on the command line", so without it
  a consumer's ambient config could set `location` and silently re-enable redirect following,
  defeating the egress bounds above.
- `curl` declared as a required-for-correctness prerequisite at step 1, with a visible degrade to
  step 2 on absence — the xtomd endpoint is POST-only, so `WebFetch` cannot substitute.
- Thread Reader App miss detection by final URL (`.../thread/<id>/error`) rather than status code,
  which stays `200` on a miss.
- Evidence-driven escalation: step 2 runs only on positive continuation evidence — an explicit thread
  request, text ending mid-thought, or `1/`-style markers — with length treated as evidence in
  neither direction. Empirically grounded: a genuine 12-post chain returns `isNoteTweet: false` with
  a 346-character root. The flag reports a long-form representation rather than the absence of
  replies, so it suppresses length-only escalation without overriding continuation evidence.
- Success requires **exactly `200`**; the status table names the codes with specific advice, not the
  set that can arrive. A redirect proves the point: without `-L` curl does not follow a `3xx`, so it
  completes with exit `0` and a short `text/plain` body — and plain text is syntactically valid
  Markdown, so only the status code can reject it.
- The spool is read to EOF **or to 256 KB total, whichever comes first**. Bounded slices cap each
  tool result, never their sum, so reading a near-cap response through to EOF still puts every byte
  in the session. The ceiling is a fixed number rather than a per-invocation judgement: faced with a
  5 MB response, "set a budget" admits 5 MB. 256 KB sits well above a long X Article and well below
  the transport cap. Stopping short is allowed; stopping short *silently* is not — a partial read is
  reported as partial, with where it stops.
- curl's **exit status** is checked ahead of the HTTP code and the body. The two disagree when a
  transfer dies after its status line arrives: verified against curl 8.19.0, an over-cap response
  prints `200` on stdout and exits `63`. Any nonzero exit is a failed fetch — the spool is deleted
  unread, because an aborted transfer leaves a syntactically valid Markdown *prefix* that satisfies
  every content check and reads as a complete post.
- Status capture (`-w '\n%{http_code}'`) and explicit handling for `400`/`429`/`500`/`502`, timeouts,
  and `200` responses carrying no converted content, so a bot-challenge or stub page is never
  reported as an empty post.
- `skills/read/context/failure-modes.md` — progressive-disclosure spoke holding status-code handling,
  Thread Reader miss detection, and the observed-gotchas list.
- `skills/read/evals/evals.json` — sixteen cases: step-1 resolution (1), chain escalation (2),
  note-tweet non-escalation (3), `502` handling without a retry loop (4), refusal of a hostile URL
  string (5), tracking-parameter stripping (6), prompt-injection containment (7), a URL harvested
  from fetched content re-entering the gate (8), the missing-`curl` path (9), a note tweet rooting a
  chain still escalating (10), a long post without continuation evidence not escalating (11),
  step-1-success plus step-2-miss reaching step 3 (12), a `200` without conversion treated as
  failure (13), the legacy `mobile.twitter.com` host accepted and canonicalized (14), an uppercased
  scheme and host still matching (15), a long article read to its end before cleanup (16), and a
  plaintext `http://` input upgraded to HTTPS by the rebuild (17), a spool path single-quoted
  against shell expansion (18), a handle-less `/i/web/status/` link accepted (19), and a nonzero curl
  exit treated as failure despite a `200` (20), an unlisted non-`200` rejected before the body (21),
  a near-cap article stopping at the read budget with a partial-result report (22), and `Read`
  receiving the raw path while the shell sites stay escaped (23).

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

- No shell tool pre-approval ships. A prefix permission rule cannot express "and no further flags" —
  its trailing wildcard admits every appended argument, which would have suppressed the prompt on
  exactly the injected command above. The step-1 network call therefore prompts, showing the operator
  the exact command. `allowed-tools` retains only `WebFetch(domain:threadreaderapp.com)`, which
  involves no shell. A validating `PreToolUse` hook is deferred, with re-introducing a shell grant as
  its trigger.
- Step 1 ships one bash invocation and **no PowerShell variant**; Windows requires Git Bash, declared
  as a prerequisite. That prompt is the only runtime-enforced control, so it is only as good as what
  it displays. Every PowerShell-portable form either breaks across `$PSNativeCommandArgumentPassing`
  modes or moves the request into a curl config file, where `curl.exe -q -K <file>` hides the
  destination, the `data` reference, any `output` directive, and redirect behavior inside a file no
  operator approves. A declared platform boundary is the honest cost; an unreadable approval is not.
- Every step-1 response spools to a `<plugin-data-dir>/x-<id>-<nonce>.md` template built from the
  gate-captured id plus a per-invocation nonce — never an agent-chosen path, never one derived from
  fetched content — and the file is deleted on every exit path, not only after a successful read. The
  redirect is unconditional because it cannot be otherwise: an X Article is routinely shared as an
  ordinary `/status/` link, so the URL gives no advance signal of response size and "redirect when it
  is long" is unevaluable when the command is composed. Streaming to stdout instead would put the
  whole body in the tool result before any bound applied. A metadata probe first was rejected — it
  doubles the disclosed egress and its own response has the same unknown size. The spool is read
  through to its end in successive bounded slices before the delete, since a bounded slice is a
  window onto the file rather than the content: deleting after one would discard the tail of exactly
  the long articles this path exists to serve and return truncated Markdown that reads as complete.
  The nonce prevents two sessions reading the same post from sharing a path, where the second `curl`
  would truncate the file between the first request completing and that session's `Read`. The
  substituted path is **single**-quoted at the shell sites — the `-o` target and the delete — because
  double quotes still expand `$name`, still run a backtick or `$(…)` substitution, and still consume
  a backslash, so a home directory carrying any of those characters would retarget the write or
  execute the embedded text. The `Read` tool takes the **raw** path instead: its argument is a
  literal filesystem path that no shell parses, so quotes would become part of the filename and every
  successful fetch would fail to open its own spool.
- Gate patterns are presented in fenced code blocks rather than a Markdown table. In table cells the
  alternation had to be written `\|` to survive the renderer, and a model reading the raw source
  could take that as a literal backslash-pipe and refuse every `twitter.com` URL.
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
- Reference files use a `<plugin-data-dir>` slot rather than `${CLAUDE_PLUGIN_DATA}`, per the
  repository convention that SKILL.md is the only surface where that token expands.
