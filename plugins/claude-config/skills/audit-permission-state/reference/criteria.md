# Effective-Permission Merge Criteria

Version: 1.0.0
Last updated: 2026-08-11

This file defines what `permission-merge.sh` may claim and on which documented mechanic each claim
rests. It exists because an *effective* permission set is a precedence claim, and a precedence claim
with no cited mechanic is folklore. The reader's own record contract lives in `SKILL.md`; the
per-check grant vocabulary lives in the sibling `audit-permission-grants` — neither is restated here.

Sources, both fetched 2026-08-11: <https://code.claude.com/docs/en/settings> §How scopes interact and
<https://code.claude.com/docs/en/permissions> §Manage permissions and §Settings precedence.

---

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
- **A surface that could not be read bounds the result.** `skipped`, `unreadable` and `invalid-json`
  each raise a caveat naming the surface. `absent` and `not-applicable` raise none — the reader looked
  and there was nothing, which is a complete answer.

## The auto-mode entry diff

> "On entering auto mode, broad allow rules that grant arbitrary code execution are dropped: Blanket
> `Bash(*)` or `PowerShell(*)`; Wildcarded interpreters like `Bash(python*)`; Package-manager run
> commands; `Agent` allow rules… Narrow rules like `Bash(npm test)` carry over. Dropped rules are
> restored when you leave auto mode."

Four documented classes, and every dropped rule is reported as exactly one of them: `blanket`,
`interpreter-wildcard`, `package-manager-run`, `agent`. The patterns are not defined here — they live
in `lib/permission-patterns.sh`, shared with `audit-permission-grants` check P1, so a class change
lands once.

- **Only allow rules are in scope.** Deny and ask are evaluated before the classifier in every mode.
- **`autoMode.classifyAllShell` (v2.1.193+) inverts the carry-over answer.** When true it "suspend[s]
  every Bash and PowerShell allow rule while auto mode is active", so a narrow `Bash(npm test)` does
  **not** carry over. A diff that cannot see this key can be exactly wrong, which is why the reader
  inventories it as a `conf` record.
- **The key is resolved only from scopes the classifier reads** — user settings, managed settings, and
  inline `--settings`/SDK JSON. "The classifier doesn't read `autoMode` from project settings in
  `.claude/settings.json` or `.claude/settings.local.json`." A project- or local-scope occurrence is
  reported as having no effect, never obeyed.
- **The oracle is corroboration, not the read path.** `--oracle` spawns a real session to capture the
  harness's own `Ignoring dangerous permission … (bypasses classifier)` narration. Those are
  undocumented `[DEBUG]` strings with no stability contract, so a capture that yields nothing is
  **unavailable** and the prediction stands — an empty capture is never an empty drop set. Its
  measured cost is stated at the flag rather than discovered afterwards.

## Managed policy, and what it does not buy

> "no other level, including command line arguments, can override a managed permission rule."

A managed rule cannot be removed by a lower scope. It does **not** follow that managed rules win every
contest: a deny at any scope still beats an allow at managed, because deny is evaluated first
everywhere. Conformance of managed intent against what is deployed is a separate question and belongs
to the managed-policy report, not to this merge.
