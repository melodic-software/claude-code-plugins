# Roadmap and staff statements

Self-contained. Pin: 2026-09-19. Every statement below was fetched and re-fetched
by a fresh-context verifier on 2026-09-19 from `xtomd.com/api/fetch` (X) and
`gh api` (GitHub), and is described here in our words; read each at its comment
id or post for the wording. Nothing is reconstructed from memory. Basis labels:
`OBSERVED` / `SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` / `INFERRED`.

Lane: `x-threads/`, with corrections in its `VERIFICATION.md`.

## Who counts as staff

| Handle / login | Basis | Verdict |
|---|---|---|
| `@ClaudeDevs` | X bio presents it as Anthropic's official channel for developers | Official account |
| `bcherny` (Boris Cherny) | X bio *"Claude Code @anthropicai"* | Staff |
| `trq212` (Thariq) | X bio *"Claude Code @anthropicai"* | Staff |
| `poteat` (Alice T'Poteat) | Authors every `mods/*` commit; **self-merged PR #93215 into `anthropics/claude-code` main within 4 minutes**; writes in first-person org voice; bcherny routes the community to their issue | **Staff by inference, disclosed** |

**`poteat` is not confirmable by metadata.** `gh api users/poteat` →
`company: null`, `bio: "SWE in SF"`, `twitter_username: null`;
`author_association` reads `CONTRIBUTOR`, not `MEMBER`;
`gh api orgs/anthropics/members/poteat` → 404. That 404 means "not a *public*
member", so the badge is **neutral on employment, not evidence against it**: an
outsider cannot distinguish "not a member" from "private member".
`x-threads/VERIFICATION.md` row 9; `community-falsification/VERIFICATION.md`
row 2f. The architecture PDF attached to #91870 carries the byline *"Alice
Poteat · August 2026 · Anthropic"*. **No X statements by this person exist in
this corpus**; everything attributed to them is from GitHub.

## The dated timeline

| Date (UTC) | Who | Statement |
|---|---|---|
| 2026-09-03T18:00:23Z | poteat | Issue #91870 opened: *"Mods - make Claude 10x more extensible"* |
| 2026-09-03T18:01:25Z | @ClaudeDevs | Announces Function Hooks as an extension mechanism under exploration, **not yet shipped**, and asks for feedback on the GitHub issue |
| 2026-09-03T19:11:27Z | bcherny | Asks whether people would use it, presenting it as an early view of plans to make Claude Code much more extensible |
| 2026-09-09 (self-declared heading in an edited issue body) | poteat | The Community Update, see below |
| 2026-09-09T22:30:08Z | poteat | First `mods/` commit; PR #93215 opened 22:31:07Z, self-merged 22:34:33Z |
| 2026-09-14T17:30:10Z | bcherny | Says mods are **"landing now"** and points to a community Tetris mod |
| 2026-09-18T18:04:08Z | trq212 | Announces AGENTS.md support in Claude Code from version 2.1.277 |
| 2026-09-18T18:04:08Z | trq212 | Says AGENTS.md support ships as a mod compiled into Claude Code, calls mods **"our upcoming way"** for customizing the harness, and **says users will later write their own project-instruction mods** |
| 2026-09-18T18:50:44Z | poteat | Notes that AGENTS.md support went out as one of the bundled mods |
| 2026-09-19T00:53:54Z | poteat | Rules out, with no exception, any way for a mod to choose its own place in the registration order |

`STAFF` · HIGH throughout.

**Two dating caveats.** The "Sep 9, 2026" Community Update is a heading the
author typed into an edited issue body; GitHub exposes no body-edit time, so the
date is self-declared and unverifiable from metadata. And bcherny's Sep 14 link,
which he labels the latest community update, resolves to comment 5666255143 by
`sezaakgun`, `author_association: NONE`: **a community member's Tetris demo,
not an Anthropic update**. The phrase is accurate; a reader skimming it as
"Anthropic's latest update" would be wrong. `x-threads/VERIFICATION.md` rows 2, 6.

## The Community Update: the roadmap

What the update says, in our words:

- Its one-line summary promises shipping in an unstated number of weeks.
- Function hooks are now a firm commitment, on a timescale of weeks rather than
  days or months. The product name becomes "Claude Mods"; "function hook" stays
  the engineering name for the documented primitive underneath. A mod is still a
  plugin, one that happens to rely on function hooks.
- The interface and design are still changing fast, but most semantics are
  settled, with fewer breaking changes expected than in the first week. **The
  stated intent is to move more of today's Claude Code features into mod form.**
- An attached cheat sheet lists some affordances in v267 and v268, and anyone
  who wants to test and send feedback is now openly invited to run
  `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude`.

`STAFF` · HIGH. **"N weeks" is a commitment without a date. No GA date exists.**

## "Landing now" vs "upcoming"

bcherny's "landing now" (Sep 14) and trq212's "our upcoming way" for customizing
the harness (Sep 18) look contradictory.

**The reconciliation is this corpus's own inference, not a staff statement:**
built-in mods ship to everyone (AGENTS.md landed in 2.1.277), while user-authored
mods stay behind the gate. No staff source reconciles the two.
`INFERRED` · HIGH-supported · `x-threads/VERIFICATION.md` row 5.

Note also that the 2.1.277 CHANGELOG entry **never says "mod"**. The built-in-mod
linkage comes from trq212's post, comment 5734700291, and commit `a92ea1cd`,
which adds the `mods/agents-md` mod. `OBSERVED` · HIGH.

## Capability statements

All `STAFF` · HIGH, all in #91870, described in our words with comment id and UTC
time.

**`$` and its purpose: 5530356661, 2026-09-03T18:34:27Z.** `$.fs`, `$.http` and
`$.process` are likely to exist. Limiting plugins is left to an organization's
admin, not to Anthropic; nothing is ambient, and every action passes through `$`
so an admin can audit, allow, block or log any event.

**The onion model: 5530555431, 2026-09-03T18:50:55Z.** For one event instance
the earliest-registered plugin wraps every later hook, and no plugin lower in
the chain can stop one above it.

**MCP coverage: 5531058610, 2026-09-03T19:33:04Z.** The plan is for `tool.call`
to fire for tools from MCP servers and for all others.

**Subagent coverage: 5560100559, 2026-09-06T15:04:35Z.** Asked whether a
`tool.call` hook also fires for a subagent's tool use: yes, in the internal
prototype at that time.

**Runtime: 5532000239, 2026-09-03T20:54:00Z.** Hooks run in-process on Bun, with
a p99 of about 50μs per hook.

**Plugin integration: 5539280904, 2026-09-04T10:41:20Z.** Function hooks are
meant to fit existing plugins as one more hook type, so dependencies and
versioning stay as they are. The same comment says the engine refuses a module
that indexes `$` with a computed expression (`$[<arbitrary expr>]`), at startup
registration and in the manual validation tool; that preventing some scenarios
takes enterprise endpoint management, which this work does not change; and that
strong OTEL support is wanted from launch.

**Non-TypeScript escape hatches: 5561046073, 2026-09-06T17:52:01Z.**
`$.process.run` is the intended escape hatch for whoever accepts the spawn cost;
`$.http.fetch` also lets a hook call a local daemon, for example one in Python.

**Classic-hook compatibility and tiers: 5574036379, 2026-09-07T17:39:14Z.** The
internal prototype adds `classic.PreToolUse` and one such event per classic hook,
each wrapping the shell hooks already configured with the same input and output.
`next.to`, also new, skips tiers, of which there are five:
`[prepend] [user] [append] [builtin] [core]`.

**`/plugin-types`: 5541093682, 2026-09-04T13:25:58Z, then 5609917069,
2026-09-09T23:01:55Z.** First a joking denial that any such flag exists, adding
that a `/plugin-types` command would be where its typings went; later, that with
the experimental flag on, `/plugin-types` lists every `$` affordance.

**Isolation: 5546290346, 2026-09-04T20:49:39Z.** Staff called it a boundary: a
Bun Worker around the whole plugin realm and a `node:vm` wrapper per plugin. The
wrappers are not the contract; the contract is only that plugins get no ambient
access.

**What `validate` checks: 5560061162, 2026-09-06T14:57:49Z.** Syntax only.

**Load order: 5738020815, 2026-09-19T00:53:54Z.** The order is fixed:
`[org-prepend] [user] [org-append] [built-in]`, and no mod gets to pick its own
place in it.

## Stated plans, with their status

| Item | What staff said | Status |
|---|---|---|
| Migrating further built-in features to mod form | Intends to move more existing Claude Code features into mods | **Stated intent** |
| User-authored project-instruction mods | Users will be able to write their own project-instruction mods | **Stated intent** |
| `agentId` on events, for subagent transcripts | Agreed and promised a fix | Committed, unshipped |
| `next.budget` correctness on `session.end` | Promised `next.budget` will report the right time there | Committed, unshipped |
| `on(...).catch(...)` for fail-closed | proposed 2026-09-08, restated 2026-09-16 | **Now shipped**: present in the `.d.ts` and works (`OBSERVED`) |
| `tool.check` | Mentioned as future work | **Now shipped**: in the 92-event catalog (`SOURCE`) |
| `$.ui.ask` originating a question | Suggested a method such as `$.ui.ask` should exist | **Now shipped as a method, with no event** (`SOURCE`) |
| Raised node limits / WebAssembly | Expects to raise the node limits; WebAssembly and similar are planned | Aspiration |
| Mod ordering managers | Predicts that mod systems tend to converge on a community-run registry of which mods can be ordered together, a "Mod Manager" | **Speculation by staff, not a roadmap item** |

`STAFF` · HIGH. (An earlier draft altered a word inside a quotation of the Mod
Manager comment; the snapshot first corrected the quote, and now records the
comment in our words. `x-threads/VERIFICATION.md` row Q.)

## Explicit non-goals and refusals

- **No numeric priority system.** Staff hold that numeric priorities have failed
  in every system that tried them, so the design has no number levels at all.
  `STAFF` · HIGH
- **No declarative error policy.** A declarative `{ onError: "deny" }` was
  rejected: an author can wrap the hook in try/catch and so guarantee what it
  does when it throws. `STAFF` · HIGH
- **No restriction of plugin capability by Anthropic.** Limiting what plugins
  can do is not Anthropic's call; installing a plugin is the consent, given by
  the user or their admin.
  `STAFF` · HIGH
- **Not everything is hookable.** The internal permission-request component
  cannot be hooked, since its surface never marks it as hookable.
  `STAFF` · HIGH
- **Raw transcript files are not a stable interface.** Ideally a plugin never
  reads them: they can grow very big, and their format is not a stable interface.
  `STAFF` · HIGH

## What is inference, not statement

Flagged so no later agent promotes it:

1. **"Landing now" and "upcoming" are reconciled by the built-in / user-authored
   split.** This corpus's inference. `INFERRED`
2. **Desktop support.** Demoed in an internal prototype 2026-09-03; every claim
   beyond that is inference. `INFERRED`; see `research-surfaces.md`.
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

A widely circulated community prompt template tells Claude to read the mods
documentation it claims to include, and then links the GitHub design thread.
**There is no documentation to read.** `COMMUNITY` · HIGH.
