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
  `-L`, so no redirect-driven egress.
- `curl` declared as a required-for-correctness prerequisite at step 1, with a visible degrade to
  step 2 on absence — the xtomd endpoint is POST-only, so `WebFetch` cannot substitute.
- Thread Reader App miss detection by final URL (`.../thread/<id>/error`) rather than status code,
  which stays `200` on a miss.
- Metadata-driven escalation: `isNoteTweet` from `/api/fetch` decides whether step 2 runs, replacing
  prose heuristics that produced both false negatives and false positives. Empirically grounded — a
  genuine 12-post chain returns `isNoteTweet: false` with a 346-character root, while a long single
  post returns `isNoteTweet: true` and is already complete.
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
- Long-article file redirects are bounded to `${CLAUDE_PLUGIN_DATA}` — never an agent-chosen absolute
  path, never a path derived from fetched content.
