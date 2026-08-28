# Effective-Permission Merge Criteria

## Contents

- [Scopes](#scopes)
- [The one thing that is not a contest](#the-one-thing-that-is-not-a-contest)
- [The one thing that is](#the-one-thing-that-is)
- [`precedence_basis` vocabulary](#precedence_basis-vocabulary)
- [Whole-tool rules](#whole-tool-rules)
- [Bounds every run states](#bounds-every-run-states)
- [The auto-mode entry diff](#the-auto-mode-entry-diff)
- [The permission-plane lint](#the-permission-plane-lint)
- [The `autoMode` block lane](#the-automode-block-lane)
- [Open upstream discrepancy — carry this caveat on any `ask` finding](#open-upstream-discrepancy--carry-this-caveat-on-any-ask-finding)
- [Managed policy, and what it does not buy](#managed-policy-and-what-it-does-not-buy)

Version: 1.1.0
Last updated: 2026-08-28

This file defines what `permission-merge.sh` may claim and on which documented mechanic each claim
rests. It exists because an *effective* permission set is a precedence claim, and a precedence claim
with no cited mechanic is folklore. The reader's own record contract lives in `SKILL.md`; the
per-check grant vocabulary lives in the sibling `audit-permission-grants` — neither is restated here.

Sources, both fetched 2026-08-11: <https://code.claude.com/docs/en/settings> §How scopes interact and
<https://code.claude.com/docs/en/permissions> §Manage permissions and §Settings precedence.

---

## Scopes

| Scope | Why it is its own member |
| --- | --- |
| `managed` | Highest precedence. Four surfaces per OS, not one file — see below |
| `user` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`. Where Claude Code's own "Always allow" path writes, so it accumulates the most rules |
| `project` | `.claude/settings.json` at the repository root |
| `local` | `.claude/settings.local.json`, resolved **through worktrees to the main checkout** — anchoring on the worktree root looks where the file is not. Three documented exceptions keep it in the start directory: outside a git repository, when the repository root is the home directory, and in Agent SDK sessions |
| `startdir-local` | A pre-v2.1.211 copy left in the session's start directory. Not a fallback: when both exist the repository root wins on a shared key, **but permission rules from both stay in effect**, so both are live |

The managed scope is four surfaces. Two are the **portable core**, read on every OS: the per-OS
`managed-settings.json` and its `managed-settings.d/` drop-in directory. Their merge order is
documented rather than guessed, so the reader implements it instead of reporting an inventory:

> "Following the systemd convention, `managed-settings.json` is merged first as the base, then all
> `*.json` files in the drop-in directory are sorted alphabetically and merged on top. Later files
> override earlier ones for scalar values, arrays are concatenated and de-duplicated, and objects are
> deep-merged. Hidden files starting with `.` are ignored."

Two are **declared optional platform integrations**: the Windows policy registry keys and the macOS managed-preferences
domain. Each is read where it is native and readable; where its tool is missing the surface reports
`skipped` with a notice and every other result is unaffected.

`HKCU` is not a peer of `HKLM`. It is documented as lowest policy priority, used only when no
admin-level source exists, so the first key that **exists** ends the search and the rest are not
consulted — an existing key that yields nothing readable is reported unread, never as permission to
fall through.

## The one thing that is not a contest

> "Permission rules behave differently because they merge across scopes rather than override."

Every scope's rules are in effect at once. A rule text present in the **same list** at several scopes
therefore has no winner and no loser — the entries are all live and identical in outcome. Naming one
of them "the" origin would assert an override the documentation explicitly denies, so provenance for
that case is the whole contributor set.

`scopes=` lists contributors in the order the reader emitted them. That order is presentation only,
never a ranking.

## The one thing that is

> "Rules are evaluated in order: deny, then ask, then allow. The first match in that order determines
> the outcome, and rule specificity doesn't change the order."

> "If a tool is denied at any level, no other level can allow it… The same holds across settings
> scopes: if user settings allow a permission and project settings deny it, the deny rule blocks it.
> The reverse is also true: a user-level deny blocks a project-level allow, because deny rules from
> any scope are evaluated before allow rules."

The winner is decided by **kind**, and the mechanic is scope-independent in both directions. An
implementation that ranked scopes here would get the second sentence exactly backwards: `user` is the
lowest scope and its deny still wins.

## `precedence_basis` vocabulary

Every `effective` record carries exactly one token. A record without one is a defect.

| Token | Emitted when | Mechanic it cites |
| --- | --- | --- |
| `uncontested` | the rule text appears once, in one kind, at one scope | none needed — nothing contests it |
| `merged-across-scopes` | one kind, two or more scopes | rules merge across scopes rather than override |
| `evaluation-order` | two or more kinds for the same text | deny, then ask, then allow; first match wins, from any scope |
| `evaluation-order+merged-across-scopes` | both of the above | both, in that order |

An `inert` record is an entry that is not in force. It deliberately carries no basis — a basis on it
would read as a claim about what is in force — and instead names what displaced it:

| Field | Meaning |
| --- | --- |
| `outranked_by=<kind>` | the same rule text exists in a kind that is evaluated earlier |
| `removed_by=deny@<tool>` | a whole-tool deny took the tool out of the model context, so this rule has nothing to act on |
| `outranked_by=ask@<tool>` | a whole-tool ask prompts for every call of that tool, so this scoped allow never applies |

## Whole-tool rules

> "A bare tool name like `Bash` removes the tool from Claude's context entirely, so Claude never sees
> it… A scoped rule like `Bash(rm *)` leaves the tool available and blocks matching calls when Claude
> attempts them."

The tool token is the text before the first `(`; a rule that **is** its own token names the whole
tool. That test needs no pattern matcher, so it is computed rather than caveated.

- **A whole-tool deny makes every other rule for that tool inert**, whatever its kind. An inert deny
  is moot, not weakened — the tool is gone, so a second deny has nothing left to block. Reporting a
  scoped allow as effective underneath one would claim access to a tool that is not in context.
- **`EndConversation` is the documented exception**: "a deny rule can't remove it while any other tool
  remains, and an ask rule never prompts for it." It is exempt from removal here.
- **A whole-tool ask outranks every scoped allow for that tool**, because it matches every call and
  ask is evaluated before allow.

Both cases print a `NOTE:` naming the tool, so the removal is announced rather than inferred from a
run of `inert` records.

## Bounds every run states

Neither is a limitation to apologise for; both change what a finding means.

- **The command-line scope has no file.** `--settings`, `--allowedTools` and `--disallowedTools` rank
  above local, project and user settings, and no file reader can see them. The merge is the effective
  set the settings **files** define.
- **Rules are compared by exact text, and the error direction is known.** "A broad deny rule like
  `Bash(aws *)` blocks every matching call, including calls that also match a narrower allow rule like
  `Bash(aws s3 ls)`." This merge does not evaluate pattern subsumption, so a narrow allow that a
  broader deny blocks is still reported effective. It over-reports allow; it never over-reports
  blocking.
- **A rule containing a literal newline or carriage return is reported, never split or stripped.**
  The records are line-oriented, so such a rule cannot be represented in one. A newline read line by
  line produced two records; a carriage return was silently deleted by the CRLF line-ending strip,
  turning `Bash(a\rb *)` into `Bash(ab *)`. Every one of those is a rule string present in no
  settings file, flowing downstream as if it were a real grant. Both are reachable through an
  ordinary settings file, and both are now named as unrepresentable with no rule record emitted. The
  line-ending strip stays — `jq` emits CRLF on Windows — so the in-string case is caught *before* it
  reaches the strip rather than by weakening it.
- **A surface that could not be read bounds the result.** `skipped`, `unreadable` and `invalid-json`
  each raise a caveat naming the surface. `absent` and `not-applicable` raise none — the reader looked
  and there was nothing, which is a complete answer.

## The auto-mode entry diff

> "On entering auto mode, broad allow rules that grant arbitrary code execution are dropped: Blanket
> `Bash(*)` or `PowerShell(*)`; Wildcarded interpreters like `Bash(python*)`; Package-manager run
> commands; `Agent` allow rules; `Monitor` allow rules, because Claude Code runs Monitor commands
> through the shell. Narrow rules like `Bash(npm test)` carry over. Dropped rules are restored when
> you leave auto mode."
>
> Source: [permission-modes](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode),
> "How the classifier evaluates actions", re-fetched 2026-08-26. The `Monitor` category was added
> upstream in v2.1.236; before that version Monitor allow rules stayed in effect in auto mode.

Five documented classes, and every dropped rule is reported as exactly one of them: `blanket`,
`interpreter-wildcard`, `package-manager-run`, `agent`, `monitor`. The shell-shape patterns are not
defined here: they live in `lib/permission-patterns.sh`, shared with `audit-permission-grants` check
P1, so a class change lands once. `agent` and `monitor` are whole-tool classes with no shell pattern
to share, so the diff driver tests them on the tool token instead.

- **`monitor` is carried by this skill only.** `audit-permission-grants` check P1 flags `Agent`
  allow rules through its own `scan_agent` and has no `Monitor` equivalent, so a fragile `Monitor`
  grant is reported by the entry diff and not by that check. A clean P1 run is not evidence that a
  `Monitor` allow rule survives auto mode.
- **The `monitor` verdict is version-dependent and the diff says so.** Before v2.1.236 a `Monitor`
  allow rule stayed in effect, so reporting it dropped on an older version is inverted in the
  direction that matters: it tells an operator a live grant is already suspended. The script cannot
  read the running version, so whenever it classifies a `Monitor` rule it emits a `DIFF-NOTE`
  naming the v2.1.236 bound rather than asserting the verdict unqualified. Confirm the running
  version before acting on a `monitor` verdict.

- **Only allow rules are in scope.** Deny and ask are evaluated before the classifier in every mode.
- **`autoMode.classifyAllShell` (v2.1.193+) inverts the carry-over answer.** When true it "suspend[s]
  every Bash and PowerShell allow rule while auto mode is active", so a narrow `Bash(npm test)` does
  **not** carry over. A diff that cannot see this key can be exactly wrong, which is why the reader
  inventories it as a `conf` record.
- **The key is resolved only from scopes the classifier reads** — user settings, managed settings, and
  inline `--settings`/SDK JSON. "The classifier doesn't read `autoMode` from project settings in
  `.claude/settings.json` or `.claude/settings.local.json`." A project- or local-scope occurrence is
  reported as having no effect, never obeyed.
- **A bare tool name is the broadest shell grant, not a surviving one.** `Bash` with no parentheses
  is strictly broader than `Bash(*)`, so it drops as `blanket` — the same treatment `Agent`'s bare
  form already had. Reporting it as kept would tell an operator their widest grant survives.
- **Three scopes set `autoMode`; this reader can open two.** Inline `--settings` and Agent SDK JSON
  have no file, and `classifyAllShell` set there **inverts every shell verdict**. Every run states
  that bound, because the merge's command-line caveat covers rules and not this key.
- **`classifyAllShell: false` is the documented default**, not a type error. Only a value that is
  neither boolean is reported as malformed.
- **The oracle is corroboration, not the read path.** `--oracle` spawns a real session to capture the
  harness's own `Ignoring dangerous permission … (bypasses classifier)` narration. Those are
  undocumented `[DEBUG]` strings with no stability contract, so a capture that yields nothing is
  **unavailable** and the prediction stands — an empty capture is never an empty drop set. Its
  measured cost is stated at the flag rather than discovered afterwards.

  **What the oracle costs, measured** — Claude Code 2.1.225, Windows 11, by checksumming the settings
  files and taking a file-mtime census of the config directory either side of one
  `claude --debug-file <scratch> -p` run:

  | Question | Measured answer |
  | --- | --- |
  | Are settings files modified? | **No.** `settings.json` and `settings.local.json` byte-identical afterwards |
  | Is anything under the config root rewritten? | **Yes — `~/.claude.json`.** The harness's own state file; carries no `permissions` key, but it does change |
  | What new files appear? | A `projects/` entry for the working directory, a `session-env/` entry, per-session `security/` and `subagents/` state, a `backups/` entry |
  | Does a plain `-p` session emit drop lines? | **Yes — 216 of them, with no mode flag passed.** On a machine whose `defaultMode` may already have been `auto`, so this does **not** establish that drops require auto mode |

  A probe with `CLAUDE_CONFIG_DIR` pointed at a scratch directory **cannot authenticate** —
  credentials live in the real config root — so a probe of this shape necessarily touches it. That is
  why the flag enumerates what it leaves behind rather than implying an isolation it cannot have.

  The narration `Ignoring dangerous permission <rule> from <path> (bypasses classifier)` delimits
  **neither field**, and both sides may legitimately contain the separator: a rule
  (`Bash(python3 import from x *)`) and a directory (`notes from work`). No fixed choice of first-
  or last-separator is right for both, so the split is resolved by which candidate leaves a
  well-formed tool token on the left. A line that resolves to zero candidates or several is
  **announced as unresolvable**, never silently split — a wrong rule name in a divergence verdict is
  worse than an admitted gap.

## The permission-plane lint

Nine checks over one question: the operator wrote something believing it takes effect, and it does
not. Several also emit a startup warning upstream; the added value here is reading every scope at
once, before a session, and naming the file the dead entry is in.

**The three `C2` gates never merge into one finding.** They cover different scope sets and carry
different version histories, so a merged count would let an operator fix one and believe they had
fixed all three.

| Check | Mechanic it follows from |
| --- | --- |
| `C2-autoMode` | "The classifier doesn't read `autoMode` from project settings in `.claude/settings.json` or `.claude/settings.local.json`." Before v2.1.207 it also read local settings, so a local-scope finding says so rather than implying it never worked |
| `C2-defaultMode` | "Claude Code v2.1.142 and later ignore `auto` from those files so a repository cannot grant itself auto mode." Only the value `auto` is dead — other modes are read in project scope |
| `C2-planMode` | `useAutoModeDuringPlan` is "**Not read from shared project settings**". That names `.claude/settings.json` specifically, so a local-settings occurrence is **not** claimed dead — doing so would assert a restriction no page states |
| `C5-disableType` | "set `permissions.disableBypassPermissionsMode` or `permissions.disableAutoMode` to `\"disable\"` in any settings file" — the **string**. Checked at both documented key paths, in every scope; it is not managed-only |
| `C6-winPath` | "On Windows, paths are normalized to POSIX form before matching. `C:\Users\alice` becomes `/c/Users/alice`". Tested on the **shape** — a drive-letter or UNC prefix — never on the backslash character. This check has been wrong in both directions: first testing the doubled JSON-source spelling that `jq -r` decodes away, which made it dead in the real pipeline; then a bare backslash, which was worse than dead, because backslashes are ordinary in shell rules (a regex, an escape, `\n`) so every one became a severity-`error` finding and the single true finding drowned. A UNC path gets its own message: the drive-letter remedy is wrong advice for it |
| `C6-contentField` | "You can't match a tool's primary content field this way: `command` for Bash and PowerShell, `file_path` for Read, Edit, and Write, `path` for Grep and Glob, `notebook_path` for NotebookEdit, and `url` for WebFetch… Claude Code ignores it and emits a startup warning" |
| `C6-allowParam` | "**Deny and ask rules** can match a top-level input parameter on any tool with `Tool(param:value)`… An allow rule for one parameter value wouldn't establish that the call is safe overall, so allow rules continue to use each tool's own specifier syntax." An operator writing one believes they narrowed a grant and has not. Fires only on parameters the page names for tools whose own syntax is a path or a command — `WebFetch(domain:host)` is the documented WebFetch form and `Bash(npm:*)` is a command prefix, so neither is distinguishable from a parameter by shape and neither fires |
| `C6-uncoveredPath` | "Claude Code checks file permissions against `Edit(path)` and `Read(path)` rules only. If you write a path rule for `Write`, `NotebookEdit`, `Glob`, or the legacy `MultiEdit` tool instead, Claude Code accepts the rule but never consults it, and warns at startup" (v2.1.210+; a `Glob` rule passed in `--allowedTools` is the stated exception) |
| `C6-colonStar` | "The `:*` form is only recognized at the end of a pattern. In a pattern like `Bash(git:* push)`, the colon is treated as a literal character". The mechanic is about **command-prefix** patterns, so a documented parameter form is exempt: "WebFetch rules use a `domain:` prefix… supports `*` wildcards", and firing on `WebFetch(domain:*.example.com)` called a documented, working rule broken. **Known gap:** in a deny or ask rule a mid-pattern `:*` with NO space after it — `Bash(git:*push)` — is not reported. It is structurally identical to the parameter form `Agent(model:*-haiku)`, so once the space is gone nothing in the rule text distinguishes them; the space was the only signal. The documented example is the space form, and the pages show no no-space mid-pattern rule anywhere. The exemption is by **grammar** — in a deny or ask rule an `identifier:value` body is the parameter form — not by a list of parameter names: the page says parameter matching works "on any tool" for "any scalar parameter", so an allowlist could only ever chase it, and one did, flagging `Agent(model:*-haiku)` |

**`C5-disableType` is the highest-consequence check here.** A boolean is valid JSON, is accepted, and
does nothing — so the operator believes auto mode is locked out and it is not.

**False positives these checks are written to avoid**, each a legitimate documented shape:

- A **bare tool-name rule** (`deny: ["Write"]`) matches at the tool level everywhere; `C6-uncoveredPath`
  fires only on a *path* rule.
- `:*` **at the end** (`Bash(npm:*)`) is the working form; only mid-pattern use is dead.
- A parameter rule on a **non**-content field (`WebFetch(domain:example.com)`) is the working form.
- A POSIX-form absolute path (`//c/**/.env`) is the documented Windows spelling and must not trip
  `C6-winPath`.

**Advisory by contract: exit 0 whenever the lint ran.** Exit 2 means it could not run at all — never
"nothing found". A findings count of zero is printed as a summary line, so a clean plane is stated
rather than inferred from silence.

## The `autoMode` block lane

A different surface from the permission plane: four natural-language sections (`environment`,
`allow`, `soft_deny`, `hard_deny`) that an LLM classifier reads. Only mechanical checks live here —
prose judgment belongs to `claude auto-mode critique`, which is surfaced rather than reimplemented.

| Check | What it means |
| --- | --- |
| `C4-defaults` | a customized section omits `"$defaults"`, which **replaces** the built-in list rather than adding to it. The finding names how many built-in entries are gone, because "you dropped 65 soft_deny rules" is actionable where "missing $defaults" is not |
| `C2b-contradiction` | the same label subject appears in `allow` and in a deny section |
| `C3-shadowed` | an entry whose subject is already in `hard_deny`, which cannot be overridden, so the entry can never change an outcome |

Comparison is by **label subject**, never by body text. The bodies are prose written for an LLM, and
no mechanical comparison of prose is defensible; a shared label across two sections is a mechanical
signal, and the finding says which two sections to reconcile rather than which one is right.

A section still carrying every built-in entry was **never customized** — the CLI expands `"$defaults"`
in its own output, so an expanded section and an omitted one differ only in what is missing. Firing on
the expanded case would report a discard that did not happen.

### The measured defensive contract

Every item below was measured on 2.1.225, not assumed. Each is a way this lane could have reported a
confident wrong answer.

| Defect | What the reader does |
| --- | --- |
| `claude auto-mode config` emits **raw control characters inside JSON string values** — `jq` and strict `json.loads` both reject it, exit status still 0 | parses non-strictly. The offending byte is a raw line feed inside a string, so no line-oriented POSIX filter can distinguish it from the pretty-printer's structural newlines — which is why this lane needs a real parser and why pure POSIX was tested and rejected |
| `defaults --label <x>` **omits** a non-matching key entirely rather than returning an empty list | tolerates a missing key as "no entries", never as an error |
| Entry labels carry a bracketed annotation **before** the colon — `Git Destructive [named+specifics …]: …` | splits at the first `[` when one precedes the colon, so the label is not truncated mid-annotation |
| **Exit status is never trustworthy** — `critique` returned 0 on a run producing no output at all | judges every capture by whether it yielded usable content. A run that produced nothing is `status=unavailable` with an explicit "NOT a clean bill", never success |
| A **section** can be present but not a list — `{"allow": "not-an-array"}` | reported `status=partial` with a note naming the section, never `read`. Returning an empty list for it gave a clean bill on a section no check could examine |
| A payload can **parse and still be the wrong shape** — a JSON array or string is valid JSON and has no sections | shape is checked before use. An earlier revision exploded on the first field access, exiting 0 with a traceback and **no summary line**, so a caller grepping `status=` saw nothing and a success exit. Now `status=unexpected-shape`, exactly one summary line, always |

`--critique` prints a cost notice before spawning, for the same reason the entry diff's oracle does:
an unpriced session spawn is the surprise an opt-in flag exists to prevent.

### Optional by declaration

`python3` is **required for an optional feature** — this lane only. Absent, the lane prints a visible
skip notice and exits 0, and every other stage of the skill is unaffected. Node is an equally capable
host and is deliberately not adopted: a second optional runtime doubles the declaration surface for
one feature.

`claude auto-mode reset` is never run. It strips the `autoMode` section from user settings.

## Open upstream discrepancy — carry this caveat on any `ask` finding

Any finding that rests on an `ask` rule prompting under auto mode carries this, named:

> The permissions page states that content-scoped `ask` rules "always force a permission prompt, even
> in auto mode… The classifier cannot auto-approve a matching action."

Two upstream issues (**#83766** and **#42797**) report the opposite — `permissions.ask` patterns
auto-approved under `defaultMode: "auto"`. Both cannot be true. This plugin follows the documented
behavior, because that is the only source with a stated contract, but a reader acting on an `ask`
finding should know the reported behavior contradicts it.

**What this changes in practice:** an `ask` rule is reported here as outranking an `allow`, and as
surviving auto mode. If the issues are right, an `ask` rule is weaker in auto mode than this report
implies — so treat `ask` as a prompt you *expect*, not a guarantee you *rely on*, and use
`permissions.deny` where the outcome must hold. This is not a defect in the reader: it reports the
documented mechanic, and the discrepancy is upstream.

**Retires when** the permissions page and the issue reports agree — either the issues close as
not-reproducible against a current version, or the page is corrected. Only a fresh read of both
settles it; a version bump alone does not.

## Managed policy, and what it does not buy

> "no other level, including command line arguments, can override a managed permission rule."

A managed rule cannot be removed by a lower scope. It does **not** follow that managed rules win every
contest: a deny at any scope still beats an allow at managed, because deny is evaluated first
everywhere.

### The conformance report

Two claims are both true and their interaction is what an administrator does not expect: managed
settings are the highest **scope**, and evaluation order (deny, then ask, then allow) applies **from
any scope**. So a lower-scope deny changes the outcome of a managed allow without overriding it.

| Verdict | What it rests on |
| --- | --- |
| `enforced deny` | "If a tool is denied at any level, no other level can allow it." The strongest thing an administrator can write |
| `enforced allow` / `enforced ask` | the managed rule is highest and nothing beneath it outranks its kind |
| `loosenable rule` | a lower scope carries an earlier-evaluated kind for the same rule text |
| `loosenable autoMode` | "A developer can extend `environment`, `allow`, `soft_deny`, and `hard_deny` with personal entries but can't remove entries that managed settings provide… a developer-added `allow` entry can override an organization `soft_deny` entry: the combination is additive, not a hard policy boundary." Permissions, hooks, MCP, sandbox-filesystem and sandbox-network each have an exclusivity lock; auto mode has none |
| `enforced` / `loosenable lockout` | `disableAutoMode` is a real lock only when it carries the documented string `"disable"` |

The remedy the `autoMode` finding names is the page's own: "For actions that must never run regardless
of user intent or classifier configuration, use `permissions.deny` in managed settings, which… can't
be overridden."

**The report prescribes nothing.** It says what the consumer's policy does and does not achieve, and
every rule string it prints came from a file it read — a property the suite asserts positively rather
than by checking that some recommendation marker is absent. It ships no security floor of its own,
which keeps it neutral by construction rather than by restraint.

**Completeness bounds every claim.** Server-managed settings have no local path, so `managed` means
the local surfaces; a `skipped` or `unreadable` surface gets its own note stating that it is not
evidence no policy is deployed there. An administrator reading silence as "no policy" is the failure
this report exists to prevent.
