# x

A Claude Code plugin that makes a pasted X (formerly Twitter) link readable.

X serves its content behind an authenticated client, so a plain HTTP fetch of an `x.com` URL returns
a shell rather than the post. This plugin routes the URL through public third-party converters that
already hold the extraction logic and returns Markdown — no X account, no API key, no browser
extension.

The plugin namespace is the platform, not the technique, so later capabilities (search, archival, an
MCP surface) join it as sibling skills rather than forcing a rename.

## Skills

| Skill | What it does |
|---|---|
| `/x:read <url>` | Returns an X post, note tweet, or X Article as Markdown, walking a documented fallback ladder. |

## URL gate

Every invocation validates the URL before anything else runs, including URLs offered later in the
conversation and URLs that surface inside fetched content. The gate anchors the input against the
post and article patterns, **refuses outright** on no match, and on a match discards the input
string and rebuilds the URL from captured groups restricted to `[A-Za-z0-9_]` and `[0-9]`.

This is rebuild-from-captures, not escaping. The URL otherwise lands inside a shell command line,
where an apostrophe terminates the quoting and contributes new arguments — demonstrated against a
real `argv` dump, yielding a second unconstrained URL and an arbitrary-write flag. Character classes
that cannot express a quote make the emitted command safe by construction; hand-escaping is the
failure mode, not the fix.

Rebuilding also drops the query string, so `?s=`/`?t=` share-tracking tokens never reach a third
party.

The gate is model-honored instruction, not a runtime-enforced control — stated plainly because it is
the primary defense. The plugin therefore ships **no** shell pre-approval: the network call surfaces
a permission prompt showing the exact command, destination and transport bounds included. That
inspectability is why the invocation stays a single bash command line rather than a config file, and
why there is no PowerShell path. A validating `PreToolUse` hook is the stronger control and is
deferred, with re-introducing a shell grant as its trigger.

## The ladder

1. **xtomd.com** (`POST /api/markdown`) — X Articles, plain tweets, note tweets, quote tweets. This
   resolves the large majority of pasted links.
2. **Thread Reader App** (`WebFetch`) — only when step 1's result is a fragment of a multi-post reply
   chain. xtomd returns exactly one post; its response schema has no field for sibling or child
   posts, and `replies` is an integer count rather than an array. Verified end to end: a genuine
   12-post chain came back from xtomd as a 346-character root, and Thread Reader App recovered all
   twelve.
3. **Ask** — reached whenever the requested content is still incomplete, including the common case of
   step 1 succeeding with a chain root and step 2 missing. The skill names what each step did, then
   asks for the remaining post URLs. It never presents a truncated chain as complete and never
   reconstructs a post from memory.

Escalation requires positive evidence of continuation — an explicit thread request, text ending
mid-thought, or `1/`-style markers — and length is evidence in neither direction. The `isNoteTweet`
flag from `/api/fetch` describes a post's long-form representation, **not** the absence of replies: a
chain can begin with a note tweet, so `true` suppresses length-only escalation but never overrides
positive continuation evidence.

Status-code handling, Thread Reader miss detection, and the observed-gotchas list live in
[`skills/read/context/failure-modes.md`](skills/read/context/failure-modes.md).

## Prerequisite

`curl` on `PATH` **and a POSIX shell**, both required for step 1. The xtomd endpoint is POST-only
(verified: a GET to `/api/markdown` returns a self-describing stub whose body reads
`"method":"POST"`), so `WebFetch` cannot reach it.

**On Windows that means Git Bash.** The plugin ships no PowerShell variant, deliberately: every
PowerShell-portable form of this request hides the destination and transport bounds from the approval
prompt, and that prompt is the only runtime-enforced control here. A narrower, declared platform
boundary is the honest trade against a Windows path whose approval cannot be trusted.

Absence of either prerequisite is always reported — never a silent skip — and step 2 is **not** a
general substitute: it resolves chains only. Without them a single post is unreadable, and the skill
says so rather than returning an empty chain lookup that reads as if content were lost.

## Configuration

None. No `userConfig`, no consumer-project config file, no external credential — so per the
marketplace's setup criteria the plugin ships no `setup` skill. Per-project control is whole-plugin
via scope-level `enabledPlugins`.

## Trust boundary

Both providers return **attacker-authored text**: anyone can post anything on X. The skill treats
every returned byte as data to report, never as instructions to follow, and never lets fetched text
select a subsequent tool call, path, or URL.

## What leaves the machine

Only the gate's rebuilt, query-stripped URL, sent to `xtomd.com` and `threadreaderapp.com`. No
credentials, no repository content, no conversation text. This holds because of the gate — without
it the request body is attacker-steerable.

Neither vendor identifies its operating entity or publishes a retention policy, so assume every
submitted URL is logged indefinitely. A consumer who does not accept that egress disables the
plugin. The recorded trust decision, including the retracted claims from the first review draft,
lives in the marketplace's
[plugin-acceptance security review](../../docs/MIGRATION-PLAYBOOK.md).

## Known limits

- **Private, protected, or deleted posts** are unreachable by any converter. xtomd reports `502`;
  the skill surfaces that rather than retrying.
- **Thread Reader App coverage is not guaranteed** — a thread page exists only if someone requested
  that unroll. A miss redirects to `.../thread/<id>/error` while still returning HTTP `200`, so the
  skill detects it by final URL rather than status code.
- **A mid-chain reply URL** carries its own id, not the root's, so the step-2 path will miss. The
  skill reports this instead of guessing at the root.
- **Both providers are third-party.** Neither is operated by Melodic Software, and either can change
  or disappear without notice.

## License

MIT
