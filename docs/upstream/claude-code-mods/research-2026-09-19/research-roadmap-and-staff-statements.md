<!-- markdownlint-disable MD049 -->

# Roadmap and staff statements

Self-contained. Pin: 2026-09-19. Every quote below was fetched and re-fetched by
a fresh-context verifier on 2026-09-19 from `xtomd.com/api/fetch` (X) and
`gh api` (GitHub). Nothing is reconstructed from memory. Basis labels:
`OBSERVED` / `SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` / `INFERRED`.

Lane: `x-threads/`, with corrections in its `VERIFICATION.md`.

## Who counts as staff

| Handle / login | Basis | Verdict |
|---|---|---|
| `@ClaudeDevs` | X bio *"Official updates for developers building with @ClaudeAI"* | Official account |
| `bcherny` (Boris Cherny) | X bio *"Claude Code @anthropicai"* | Staff |
| `trq212` (Thariq) | X bio *"Claude Code @anthropicai"* | Staff |
| `poteat` (Alice T'Poteat) | Authors every `mods/*` commit; **self-merged PR #93215 into `anthropics/claude-code` main within 4 minutes**; writes in first-person org voice; bcherny routes the community to their issue | **Staff by inference, disclosed** |

**`poteat` is not confirmable by metadata.** `gh api users/poteat` →
`company: null`, `bio: "SWE in SF"`, `twitter_username: null`;
`author_association` reads `CONTRIBUTOR`, not `MEMBER`;
`gh api orgs/anthropics/members/poteat` → 404. That 404 means "not a *public*
member", so the badge is **neutral on employment, not evidence against it** — an
outsider cannot distinguish "not a member" from "private member".
`x-threads/VERIFICATION.md` row 9; `community-falsification/VERIFICATION.md`
row 2f. The architecture PDF attached to #91870 carries the byline *"Alice
Poteat · August 2026 · Anthropic"*. **No X statements by this person exist in
this corpus**; everything attributed to them is from GitHub.

## The dated timeline

| Date (UTC) | Who | Statement |
|---|---|---|
| 2026-09-03T18:00:23Z | poteat | Issue #91870 opened: *"Mods - make Claude 10x more extensible"* |
| 2026-09-03T18:01:25Z | @ClaudeDevs | *"We're exploring a new way to let you extend and customize Claude Code: Function Hooks. … **It hasn't shipped yet**, we'd love feedback on this on our GitHub issue."* |
| 2026-09-03T19:11:27Z | bcherny | *"Your input needed: would you use this? This is an early look at how we're thinking about making Claude Code way more extensible."* |
| 2026-09-09 (self-declared heading in an edited issue body) | poteat | The Community Update — see below |
| 2026-09-09T22:30:08Z | poteat | First `mods/` commit; PR #93215 opened 22:31:07Z, self-merged 22:34:33Z |
| 2026-09-14T17:30:10Z | bcherny | *"**Claude Mods are landing now.** Someone already built a Tetris-in-Claude mod 🤯"* |
| 2026-09-18T18:04:08Z | trq212 | *"We're adding support for AGENTS.md to Claude Code. Starting today in version 2.1.277…"* |
| 2026-09-18T18:04:08Z | trq212 | *"AGENTS.md support is built off of Claude Code mods, **our upcoming way** to customize the Claude Code harness. This is a built-in mod, but **you'll be able to build custom versions of project instructions yourself as you'd like too.**"* |
| 2026-09-18T18:50:44Z | poteat | *"Separately to all this, we were able to get out AGENTS.md support as a built-in mod!"* |
| 2026-09-19T00:53:54Z | poteat | *"mods cannot dictate their own registration order, full-stop."* |

`STAFF` · HIGH throughout.

**Two dating caveats.** The "Sep 9, 2026" Community Update is a heading the
author typed into an edited issue body; GitHub exposes no body-edit time, so the
date is self-declared and unverifiable from metadata. And bcherny's Sep 14 link
*"See issue for the latest community update"* resolves to comment 5666255143 by
`sezaakgun`, `author_association: NONE` — **a community member's Tetris demo,
not an Anthropic update**. The phrase is accurate; a reader skimming it as
"Anthropic's latest update" would be wrong. `x-threads/VERIFICATION.md` rows 2, 6.

## The Community Update — the roadmap, verbatim

> **AI;DR**: We're shipping in N weeks.

> We're now committed to shipping function hooks, on the scale of weeks in lieu
> of days or months. As well, from a product perspective, we are going to be
> calling this functionality "Claude Mods". The engineering term of art 'function
> hook' will still exist as the documented implementation primitive Mods are
> built on. A mod is just a plugin that uses function hooks, nothing is changing
> there.

> We're still rapidly iterating on the interface, design, etc. but much of the
> semantics are now set in place, and we don't anticipate as many breaking
> changes as our first week. … **Our intent is to take further extant features as
> they exist in CC today and migrate them to mod form.**

> Finally, I'm sharing here a cheat sheet reference that enumerates some
> affordances on v267/v268 (today / tomorrow). As well, I may now publicly
> acknowledge that any folks who want to test and give feedback may use
> `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude`.

`STAFF` · HIGH. **"N weeks" is a commitment without a date. No GA date exists.**

## "Landing now" vs "upcoming"

bcherny's *"Claude Mods are landing now"* (Sep 14) and trq212's *"our upcoming
way to customize the Claude Code harness"* (Sep 18) look contradictory.

**The reconciliation is this corpus's own inference, not a staff statement:**
built-in mods ship to everyone (AGENTS.md landed in 2.1.277), while user-authored
mods stay behind the gate. No staff source reconciles the two.
`INFERRED` · HIGH-supported · `x-threads/VERIFICATION.md` row 5.

Note also that the 2.1.277 CHANGELOG entry **never says "mod"**. The built-in-mod
linkage comes from trq212's post, comment 5734700291, and commit `a92ea1cd
mods/agents-md: the AGENTS.md project-instructions mod`. `OBSERVED` · HIGH.

## Capability statements

All `STAFF` · HIGH, all in #91870, quoted with comment id and UTC time.

**`$` and its purpose — 5530356661, 2026-09-03T18:34:27Z**
> to clarify: `$.fs`, `$.http`, and `$.process` will very likely exist. Our
> prerogative is not to restrict what plugins can do; that's your org admin's
> job. The point is that there's no _ambient_ support, everything goes through
> `$` so that admins can audit, allowlist, deny, log, etc. any event.

**The onion model — 5530555431, 2026-09-03T18:50:55Z**
> the plugin registered first 'owns' all subsequent hooks on a given event
> instance. There is no capability for a plugin 'further down the chain' to
> inhibit a plugin above it; it's an "onion model".

**MCP coverage — 5531058610, 2026-09-03T19:33:04Z**
> the current plan is for `tool.call` to hook into both MCP tool calls as well as
> non-MCP tool calls.

**Subagent coverage — 5560100559, 2026-09-06T15:04:35Z**
> [does a `tool.call` hook see tool calls made inside a subagent?] Yes, it does
> today in our internal prototype.

**Runtime — 5532000239, 2026-09-03T20:54:00Z**
> yep, keeping it all in-process on Bun is extraordinarily fast. we're looking at
> a p99 of 50μs per hook tbh.

**Plugin integration — 5539280904, 2026-09-04T10:41:20Z**
> To the extent possible, we are intending function hooks to cleanly integrate
> with plugins as they exist today, as a new type of hook. Therefore
> dependencies, versions, etc. will all go unchanged.

Same comment: *"The engine does refuse if the author does things like
`$[<arbitrary expr>]`, both during plugin registration at startup and during the
manual validation tool."* · *"We're not changing anything on that level with the
function hooks work. You need enterprise endpoint management to prevent certain
scenarios"* · *"we want really good OTEL support day one."*

**Non-TypeScript escape hatches — 5561046073, 2026-09-06T17:52:01Z**
> `$.process.run` is our intended escape hatch. If you're willing to pay the
> spawn cost, you can do it that way. As well, there's a `$.http.fetch` so you
> could spin up a daemon in Python and have your function hook cheaply call out
> over the local network

**Classic-hook compatibility and tiers — 5574036379, 2026-09-07T17:39:14Z**
> Our internal prototype now introduces a `classic.PreToolUse` event (and the
> others, 1:1), which 'wraps' the core shell hooks you already have configured,
> and has the same in/out data interface.

> The `next.to` (also new to the design) allows you to skip tiers. There are five
> tiers: `[prepend] [user] [append] [builtin] [core]`.

**`/plugin-types` — 5541093682, 2026-09-04T13:25:58Z, then 5609917069,
2026-09-09T23:01:55Z**
> I disavow knowledge of any such flag. If such a flag existed, I would put the
> typings under a `/plugin-types` command.

> If anyone decides to enable the experimental flag, `/plugin-types` will make
> available a full listing of the available `$` affordances.

**Isolation — 5546290346, 2026-09-04T20:49:39Z**
> It's a boundary! The current design is a Bun Worker surrounding the entire
> plugin realm, with each plugin then having a `node:vm` wrapper - that's not
> part of the contract though, the contract is merely that you don't get access
> to ambients.

**What `validate` checks — 5560061162, 2026-09-06T14:57:49Z**
> `validate` only syntactically checks your plugin.

**Load order — 5738020815, 2026-09-19T00:53:54Z**
> The order is always in the following order: `[org-prepend] [user] [org-append]
> [built-in]` … mods cannot dictate their own registration order, full-stop.

## Stated plans, with their status

| Item | Staff wording | Status |
|---|---|---|
| Migrating further built-in features to mod form | *"Our intent is to take further extant features as they exist in CC today and migrate them to mod form."* | **Stated intent** |
| User-authored project-instruction mods | *"you'll be able to build custom versions of project instructions yourself as you'd like too"* | **Stated intent** |
| `agentId` on events, for subagent transcripts | *"Indeed, we'll fix this."* | Committed, unshipped |
| `next.budget` correctness on `session.end` | *"I'll ensure `next.budget` is relaying the correct time in this case."* | Committed, unshipped |
| `on(...).catch(...)` for fail-closed | proposed 2026-09-08, restated 2026-09-16 | **Now shipped** — present in the `.d.ts` and works (`OBSERVED`) |
| `tool.check` | referred to as future (*"Once we have `tool.check`"*) | **Now shipped** — in the 92-event catalog (`SOURCE`) |
| `$.ui.ask` originating a question | *"there ought be a e.g. `$.ui.ask`"* | **Now shipped as a method, with no event** (`SOURCE`) |
| Raised node limits / WebAssembly | *"I think we'll up the node limits. re WebAssembly et al, it is in my plans"* | Aspiration |
| Mod ordering managers | *"every mod system in the world … end up **converging** to the same solution: a community-managed repository of order-compatibility information - i.e. a Mod Manager"* | **Speculation by staff, not a roadmap item** |

`STAFF` · HIGH. (One quote-integrity note: an earlier draft rendered
"converging" as "converge" inside quotation marks; corrected.
`x-threads/VERIFICATION.md` row Q.)

## Explicit non-goals and refusals

- **No numeric priority system.** *"every 'numeric priority' system in the world
  has failed on this, which is why I don't introduce any number levels at all."*
  `STAFF` · HIGH
- **No declarative error policy.** A declarative `{ onError: "deny" }` was
  rejected: *"You can always just wrap your hook in a try-catch and prove by
  construction that your hook does-some-behavior-on-throw."* `STAFF` · HIGH
- **No restriction of plugin capability by Anthropic.** *"It's not within our
  prerogative to limit the functionality of what plugins can do; you (or your
  admin) are giving consent by installing the plugin in the first place."*
  `STAFF` · HIGH
- **Not everything is hookable.** *"our internal 'permission request component'
  is simply not something you can hook into, because the surface does not declare
  it as being hookable."* `STAFF` · HIGH
- **Raw transcript files are not a stable interface.** *"in the optimal case you
  don't need to read the raw transcript file - those can be very large and
  technically do not form a stable interface."* `STAFF` · HIGH

## What is inference, not statement

Flagged so no later agent promotes it:

1. **"Landing now" and "upcoming" are reconciled by the built-in / user-authored
   split.** This corpus's inference. `INFERRED`
2. **Desktop support.** Demoed in an internal prototype 2026-09-03; every claim
   beyond that is inference. `INFERRED` — see `research-surfaces.md`.
3. **The install path** (`claude plugin marketplace add` / `claude plugin
   install`). Community-sourced; **no staff statement names either command**.
   Staff corroborate only the hedged intent that packaging is unchanged.
   `COMMUNITY`
4. **Naming the GrowthBook-off providers Bedrock / Vertex / Foundry.** The binary
   says only "a third-party provider". `INFERRED`
5. **`node:vm` is not a containment boundary.** This corpus's inference from
   Node's documentation; staff asserted a boundary and never conceded
   non-containment. `INFERRED`
6. **`poteat`'s employment.** Strong circumstantial evidence (commit and merge
   access, org voice, PDF byline), not a confirmed fact. `INFERRED`
7. **The five-tier vs four-tier lists.** The 2026-09-07 list names five
   (`[prepend] [user] [append] [builtin] [core]`); the 2026-09-19 list names four
   (`[org-prepend] [user] [org-append] [built-in]`). The `.d.ts` settles it at
   five (`SOURCE`). That the Sep 19 list omits `core` because `core` is the
   engine rather than a plugin tier is `INFERRED`.

## Community attention, for calibration

Near zero. Hacker News: the *"Claude Mods, Functional Hooks in Claude Code and
Desktop"* story is **3 points, 0 comments** (2026-09-15); *"The Guard I Installed
Was Enabled, Running, and Doing Nothing"* is 1 point, 0 comments (2026-09-17).
`anthropics/claude-code` has Discussions disabled. Reddit was network-blocked and
is unchecked. `COMMUNITY` · HIGH ·
`community-falsification/VERIFICATION.md` row 11.

Against that, the **adopter** record is real: seven third-party repos shipping
genuine hooks modules with tests (`kunchenguid/firstmate` 6,658★,
`Storybloq/storybloq` 751★, `kunchenguid/compact-adviser` 126★,
`darkroomengineering/cc-settings` 45★, `TransmuteLabs/Catalyst`,
`Miracle0x0/CCometixLine`, `getexcited/stepwarden`), all pushed within two days
of the check, plus `davila7/claude-code-templates`' mods component library with
an `npx` installer. `COMMUNITY` · HIGH.

A widely circulated community prompt template tells Claude to *"Read the Claude
Mods documentation below"* and then links the GitHub design thread. **There is no
documentation to read.** `COMMUNITY` · HIGH.
