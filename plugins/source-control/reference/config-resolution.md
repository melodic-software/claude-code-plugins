# Convention config resolution

How the skills in this plugin resolve the layered `.claude/source-control.md` config surface. The
surface carries two key families: the tracked commit-subject / PR-title convention keys, read by
`/source-control:commit`, `/source-control:pull-request`, and `/source-control:setup`, and the
loop-lane keys, read by `/source-control:babysit-loop`. Every consumer reads this one document; none
bakes its own layering rules, and the three layers and per-key merge below govern both families.

Implements the tracked-rich-config seam in
[`docs/MIGRATION-PLAYBOOK.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/MIGRATION-PLAYBOOK.md).

## The config surface

Markdown, one `## <key>` H2 per key, the value as the section body:

- `subject_pattern` — required; the literal keyword `Conventional Commits`, or an anchored regex
  (`^…`-style). Exactly one value, never a list and never a plain-language description — a convention
  with several accepted shapes is expressed as alternation inside the one regex
  (`^(?:feat|fix): .+|^[A-Z]+-\d+: .+`), which every consumer already evaluates correctly. A list form
  would need a serialization grammar and an any-matches rule that nothing here defines, and a reader
  handing a multi-line value straight to a matcher would reject valid subjects or build an invalid
  regex.
- `type_list` — the type vocabulary; meaningful only when `subject_pattern` is
  Conventional-Commits-shaped, omitted otherwise.
- `pr_title_pattern` — the PR-title shape, or the deferral marker spelled exactly
  `` Same as `subject_pattern`. `` (capital S, backticked key, trailing period). The match is literal:
  any other casing or punctuation is treated as a pattern in its own right.
- `trailer_policy` — the attribution-trailer template, or `none`. Absent means the `/commit` default
  trailer applies.
- `pr_body_attribution` — the attribution line `/pull-request create` appends to the PR body, or
  `none`. Absent means the default `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
  line applies. This is the PR-body analogue of `trailer_policy`, and a separate key on purpose: the
  two govern different surfaces (a commit `Co-Authored-By:` trailer vs a Markdown PR-body line), so a
  consumer setting `trailer_policy: none` keeps the PR-body line unless they also set this to `none`.
- `pr_body_required_sections` — the PR-body section scaffold: a flat Markdown bullet list (`- <H2
  heading>` per line, one heading per bullet) naming every `## <heading>` section
  `/source-control:pull-request create` must both draft and pre-check for before `gh pr create`, or
  the literal keyword `none` — no required sections: the draft emits no section scaffold and the
  pre-create gate requires nothing. Absent everywhere → the bundled portable default, `Summary` and
  `Test plan` only — see
  [`docs/conventions/pr-body-convention/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pr-body-convention/README.md)
  for the default's rationale and the seam's full contract. Like `type_list`, and unlike the single
  scalar `subject_pattern`, this key is a **closed list**: a winning layer's list is taken whole,
  never unioned or ordered against an earlier layer's list (per-key override applies to the entire
  value, per "Merge semantics" below) — the same reasoning `type_list` already documents, applied to
  headings instead of type names. `none` participates in that same per-key override as a **resolved
  value, not an absence** — exactly like its sibling keys `trailer_policy` and `pr_body_attribution`:
  a layer declaring `none` replaces a lower layer's list (a team file requiring `Summary`/`Test plan`
  is overridden to zero sections by a local overlay's `none`), while a key absent from every layer
  still falls through to the portable default.

Absent sections are absent, never empty.

- `convention_source` — optional, **honored in the team-tracked layer only**: a repo-relative
  forward-slash path to a neutral flat-scalar YAML file, the tool-agnostic convention SSOT other
  consumers (commit-msg hooks, CI, other agents) read too. When declared, the neutral file is
  authoritative for the machine keys it carries (`subject_pattern`, `pr_title_pattern`, optionally
  a flat `pr_body_required_sections:` list and `dialect:`); a key it omits falls back to the team
  file's own H2 sections, and plugin-only keys (`trailer_policy`, `pr_body_attribution`) stay in
  the markdown surface. The `Conventional Commits` keyword and the pr-title deferral marker work
  identically in the neutral file. User-global and local-overlay layers are unchanged and still
  merge per key on top. Value grammar, pointer safety rules, and the fail-closed
  broken-pointer contract are owned by the
  [commit-convention seam](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/commit-convention/README.md)
  — drafting honors the same contract (a declared-but-broken pointer is surfaced as a config error,
  never silently re-read from markdown values a migration may have retired).

## Loop-lane keys (`babysit_loop_*`)

The same surface carries the repo-scoped configuration for the `/source-control:babysit-loop` lane —
which stop shape, autonomy tier, and per-dimension overrides a repository's merge lane runs under.
These are repository policy, not personal scalars: whether a repo drains or stands, and how much
merge authority its lane holds, are properties of the target repository, which the plugin's
user-settings-scoped `babysit_*` `userConfig` keys structurally cannot express. The split is
deliberate and both surfaces coexist: `userConfig` keeps the personal and machine scalars the
babysit-prs mechanic documents (watched owners, self logins, engine thresholds); this surface holds
the lane policy a team reviews and tracks. Loop keys carry the `babysit_loop_` prefix so the two key
families sharing one file stay distinguishable.

One `## <key>` H2 per key, exactly like the convention keys above; every value is a scalar, so the
per-key override semantics below apply unchanged.

| Key | Value | Default when absent |
|---|---|---|
| `babysit_loop_stop_mode` | `standing` or `drain` | `standing` |
| `babysit_loop_tier` | a `/source-control:babysit-prs` tier name (`safe`, `worker`, `autopilot`) — the named preset over the autonomy dimensions | `safe` |
| `babysit_loop_discovery_scope` | tier name — overrides dimension 1 (which PRs enter the queue) out of the preset | preset value |
| `babysit_loop_fixing` | tier name — dimension 2 (branch-owned CI/review fix authority) | preset value |
| `babysit_loop_thread_resolution` | tier name — dimension 3 (review-thread resolution) | preset value |
| `babysit_loop_draft_elevation` | tier name — dimension 4 (draft handling / ready-marking) | preset value |
| `babysit_loop_barrier_overrides` | tier name — dimension 5 (blocker handling: escalate vs attempt-with-research) | preset value |
| `babysit_loop_merge` | an autonomy-ladder rung, ordered `human-only` < `c2-mechanical` < `c3-autonomous` < `full-autonomy` — dimension 6 (merge authority) | `c2-mechanical` (the loop-lane convention's shipped baseline) |
| `babysit_loop_escalation` | tier name — dimension 7 (escalation posture); the escalation *surface* is fixed by the loop-lane convention, never by config | preset value |
| `babysit_loop_grace_window_minutes` | positive integer — the concurrency-safety activity grace window | `30` |
| `babysit_loop_cycle_budget` | positive integer — cycles per session before the budget-hit stop | none — no per-session budget |

Dimension semantics — what each tier value grants per dimension — are owned by the babysit-prs
autonomy table (`skills/babysit-prs/SKILL.md`, "Autonomy tiers (per action class)") and are not
restated here. The merge dimension's rung semantics are owned by the loop-lane convention's autonomy
ladder (`docs/conventions/loop-lane/README.md` §1 in the marketplace repository).

**Precedence: invocation arguments win — except the merge dimension.** For every loop key above but
`babysit_loop_merge`, an invocation argument overrides all three layers, exactly as an explicit skill
argument outranks stored config everywhere else in this plugin. `babysit_loop_merge` is the one
policy-floor key on this surface (the consumer-config layering convention's sanctioned policy-floor
class, declared here next to its key): **raises bind from the team-tracked layer only** — every
increase in merge authority is a reviewable, versioned config change, per the loop-lane convention's
"Merge-rung raises are seam-only" rule. The user-global layer, the local overlay, and an invocation
argument may each select a *lower* (safer) rung than the effective team-tracked value, never a higher
one; a raise supplied by any of them is ignored and reported.

## The three layers

Resolve every read from the repo root — `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel`. A cwd-relative read from a nested directory finds
`<subdir>/.claude/source-control.md`, misses the repo-root config, and silently degrades.

Layer, in resolution order — a later layer refines an earlier one:

1. **`~/.claude/source-control.md`** — user-global. The operator's own preference, following them
   across repos and machines. Their home directory, not consumer repository data.
2. **`${REPO_ROOT}/.claude/source-control.md`** — team, tracked. The shared convention; the layer
   `/source-control:setup apply` writes by default.
3. **`${REPO_ROOT}/.claude/source-control.local.md`** — personal overlay, gitignored. A per-machine
   or per-operator deviation from team policy, never committed.

Each layer is optional, and **fall-through is per key, not per file**. A key absent from every layer
is unresolved even when some layer exists — a user-global file contributing only `trailer_policy`
leaves `subject_pattern` exactly as unresolved as no file at all. Each unresolved key falls through
independently to the repo's own `CLAUDE.md`/rules/commit-msg hook, then the bundled Conventional
Commits default. Never gate that fall-through on file presence.

## Merge semantics: per-key override

**A later layer replaces an earlier layer's value key by key, and never drops the base layer
wholesale.** A key absent from a later layer keeps the earlier layer's value.

This is a deliberate deviation from the seam's concatenating default, recorded rather than silent.
Concatenation is right for the first-party `security-guidance` precedent, whose layers are prose
blocks that genuinely accumulate. Every key here is a scalar or a closed list: two `subject_pattern`
regexes cannot concatenate into a third valid regex, and a concatenated `trailer_policy` would emit
two trailers. This is the seam's sanctioned per-key case.

Worked example — user-global sets `trailer_policy: none`, team sets `subject_pattern` to a
ticket-prefix regex and leaves `trailer_policy` unset, local overlay sets nothing: the effective
config is the team `subject_pattern` with the user-global `trailer_policy: none`.

**`type_list` is bound to the effective `subject_pattern`, not merged independently.** It is a
property of a Conventional-Commits-shaped pattern, so after the layers merge, an inherited
`type_list` is dropped whenever the *effective* `subject_pattern` is a custom regex — even when the
layer supplying that pattern said nothing about `type_list`. A user-global `Conventional Commits`
plus its type list, overridden by a team ticket-prefix regex, resolves to the team pattern with **no**
`type_list`; retaining it per key would leave `/commit` pre-checking against a vocabulary the
effective pattern does not use. The reverse also holds: an effective Conventional-Commits pattern with
no `type_list` in any layer resolves to the bundled 11-type list.

`pr_title_pattern` resolving to `Same as \`subject_pattern\`.` expands against the **effective**
`subject_pattern` after all three layers merge, not against the pattern in its own layer.

## Drafting vs enforcement

This document owns **drafting** resolution — how `/source-control:commit` and `/pull-request`
compose a compliant subject/title, reading all three layers with the per-key merge above. A separate
concern owns **enforcement** — how a zero-dependency guardrails hook decides whether an
*already-formed* subject/title is allowed. The two read the same `.claude/source-control.md` file but
differ deliberately: enforcement reads the **team-tracked layer only** (a gitignored `*.local.md`
must never weaken a blocking gate), resolves to **POSIX ERE only**, and treats an unresolved key as
**no enforcement** — never the bundled Conventional Commits default. That contract, the regex-dialect
normalization, and the resolver (`lib/resolve-convention-pattern.sh`) live in the
[commit-convention enforcement seam](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/commit-convention/README.md).

## Consumer `.gitignore`

The overlay convention needs one line in the consuming repo:

```gitignore
.claude/*.local.*
```

No skill in this plugin writes the consumer's root `.gitignore` — `/source-control:setup` recommends
the line and leaves the edit to the consumer.

## Failure modes

- **Team layer gitignored → hard STOP.** Teammates would never receive the shared convention.
  Surface the matching rule and stop; do not degrade silently.
- **Local overlay not ignored, or already tracked → FAIL, with different remediations.** The overlay
  is personal by contract; a committed one leaks a per-operator deviation into team history. A
  missing ignore rule is fixed by the `.gitignore` line; an already-tracked overlay is fixed by
  untracking it, since an ignore rule never applies to a file already in the index.
- **A layer is malformed** (a non-machine-checkable `subject_pattern`, an unparsable section) →
  surface the error, name the layer, and resolve as if that layer were absent. Unknown H2 sections
  are inert.
