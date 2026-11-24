# PR-body required-sections convention

Owner doc for the `pr_body_required_sections` key: a configurable scaffold of `## <heading>`
sections a pull-request body must carry. This concern is designed for **more than one plugin**:
`source-control` drafts and pre-checks against it, `guardrails` refuses an off-format body before it
is posted, and a future CI consumer validates an already-created PR body against the same key. Its
ownership lives here at marketplace level, not inside `source-control`, per
[`docs/migration-playbook.md`](../../migration-playbook.md) "concern-named config consumed by >1
plugin". An owner doc lands before the second consumer adopts the key, not after.

## The key, and where it lives

`pr_body_required_sections` is one key on the consumer's tracked
`docs/conventions/source-control.yaml`, resolved across the same three layers as every other key
on that surface, user-global, team-tracked, and a gitignored personal override, per
[`source-control/reference/config-resolution.md`](../../../plugins/source-control/reference/config-resolution.md).
That document owns the **resolution mechanics**: the value grammar, the three-layer read order, and
the per-key (whole-list) override semantics. This doc never restates them. It owns the concern's
*shape* and *rationale*, and points there for *how* a value resolves.

## Consumers

- **`source-control` drafting (today).** `/source-control:pull-request create` resolves the
  effective section list before assembling a PR body, builds one `## <heading>` scaffold per
  required section, and runs a pre-`gh pr create` gate that fails when an assembled body is missing
  a required section or leaves one empty. The `create` action owns both halves, the assembly and
  the pre-create gate.
- **The pr-unblock body refresh (this repository's CI).** Its select job offers for rewriting the
  sections the key lists, else the template headings in the same order, and offers none when the
  owner's default template cannot be read
  ([`docs/conventions/pr-pipeline/README.md`](../../conventions/pr-pipeline/README.md)).
- **`guardrails` enforcement (before posting).** The `block-body-format-violation` hook refuses a
  `gh pr create`, a `gh pr edit` with a body, or a GitHub MCP pull request create or update whose
  body breaks the target repository's declared format, before anything is posted, naming each
  missing or empty section and the line to add. It reads this key from the session checkout when
  that checkout is the target, judges presence and non-empty content as the pre-create gate does,
  and adds the opener rule (`Closes #N`, `Refs: #N` or `No related issue: <reason>` first) only where
  the repository's `linkage_gate_uses_pattern` matches a workflow. Unlike drafting, it never falls
  back to a template or the `briefing` default: a repository that sets neither key is not judged,
  and `none` requires no section. `pr_body_format_gate: false` turns it off
  ([config-resolution](../../../plugins/source-control/reference/config-resolution.md)). The
  plugin's README row lists the command shapes it reads and the ones it passes.
- **`guardrails` enforcement of the issue format.** The same hook reads the sibling key
  `issue_body_required_sections`, which maps each issue kind a repository accepts to the headings
  that kind requires (the shape of the standards `components/issue-body-contract/contract.json`,
  vendored here as [`docs/contracts/issue-body/contract.json`](../issue-body/contract.json)). It
  refuses a `gh issue create` or GitHub MCP issue create whose body completes no declared kind: a
  required `##` or `###` heading missing, empty, or answered `_No response_`. It names the closest
  kind and each heading to add. A repository that sets no mapping, or `none`, is not judged, and
  `issue_body_format_gate: false` turns it off.
- **CI / enforcement (deferred).** A gate validating an *already-opened* PR body against the same
  team-tracked value, the enforcement half of the two-reads pattern the
  [commit-convention seam](../commit-convention/README.md) already establishes for the
  commit-subject / PR-title convention. No such consumer exists yet in this fleet; this doc reserves
  the concern so a CI adopter reads the same key instead of inventing a parallel one.

## When no layer sets the key: the template, then `briefing`

When no layer sets `pr_body_required_sections`, the sections come from the first of these that
names one: the `##` headings of the repository's own pull request template, those of the owner's
default template in its `.github` repository, then the `briefing` preset. `create` reports which
level supplied them; its §2.4.1 owns where each template is read and how a heading is recognized.

Why the template comes first. A repository or organization that ships a pull request template has
already stated its section convention, and a CI contract check usually reads the same headings, so
repeating them in this key only adds a second copy to keep in step. GitHub lists pull request
templates among the default files an owner's `.github` repository supplies to a repository without
its own
([Creating a default community health file](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file)),
so one file sets the convention across an organization. The key stays for a repository whose drafted sections must differ from its template.

## Portable default: the `briefing` preset

With no key and no template, the plugin drafts the `briefing` preset: `Why`,
`What changed`, `Scope`, `Tradeoffs`, `Risk` and `Verification`, in that order, with `Why`,
`What changed`, `Scope` and `Verification` required and the other two written only when they have
content. The section rules live in `/source-control:pull-request`'s `create` reference; this doc
records why the preset is the default. It is a deliberate **lane-1 default**
([`docs/plugin-philosophy.md`](../../plugin-philosophy.md) "Two-lane convention posture"): it
presumes nothing about the consumer, so it cannot conflict in any repo the plugin drops into.

Why this shape. **What the change does and why, plus evidence it was verified**, is the
near-universal core of a reviewable PR description (GitHub's own PR-description guidance, Google's
engineering-practices CL-description doc, GitLab's dogfooded default merge-request template, and a
cross-section of OSS project PR templates, weighed against anti-heavy-template falsification cases).
A two-section body meets that core but has no place for excluded work or for the callers a change
affects. `briefing` adds `Scope` and `Risk` for those, caps each section at a few sentences or
bullets, and drops the two optional sections when they are empty. `Risk` says what the change
reaches and how it is undone; the author states no door or risk tier, since an independent rater
(`/review:merge-risk`) sets that.

A consumer that wants the two-section body declares the keyword `summary-test-plan` (`Summary` and
`Test plan`, both required). The keyword `briefing` states the default explicitly, for a layer that
must override a lower layer's list.

A linked-issue or "Related" section is **not** part of either preset: it presumes the consuming repo
runs an issue tracker and links PRs to it, which is an org-specific choice, not a property every
repo shares. That choice belongs in configuration, not in the plugin's shipped default.

**`## Related` is never dropped by the mechanism.** A consumer whose convention includes it puts a
`## Related` heading in its pull request template, or declares `Related` in its own
`pr_body_required_sections` list (team-tracked, personal override, or user-global), the same as any
other section name. The plugin ships no opinion on it either way.

## `none`: no required sections

The value grammar also accepts the literal keyword `none`, the convention "this repo requires no
PR-body sections", stated as config rather than left unstatable. A resolved `none` means the
drafting consumer emits **no** section scaffold and the pre-create gate requires **nothing**; the
closing-keyword / no-issue-marker mechanism is independent of this key and unaffected.

This exists because "no required sections" is a real team convention, not a hypothetical: consumer
evidence includes a repo whose merged PRs are 199/200 empty bodies, a deliberate no-body-sections
practice that previously had no expression in this key (absence yields the portable default, which
is the opposite of what such a repo wants). `none` parallels the sibling keys `trailer_policy` and
`pr_body_attribution`, whose `none` values already express "suppress the default" as a resolved
value.

**`none` is a value, absence is not.** A layer declaring `none` wins the per-key override exactly
like a list would, replacing a lower layer's list with zero sections, while a key absent from
every layer still falls through to the templates, then the portable default. Layering mechanics live in
[`config-resolution.md`](../../../plugins/source-control/reference/config-resolution.md); this doc
only fixes the value's meaning.

## Resolution semantics

Layering, per-key override, and the value grammar are entirely owned by
[`config-resolution.md`](../../../plugins/source-control/reference/config-resolution.md), and this doc
does not restate them. Two points worth surfacing here because they are easy to get wrong when
reading only the mechanism doc:

- **A later layer's list replaces the earlier layer's list wholesale**, never merges element-wise.
  Declaring `pr_body_required_sections` in a personal override is not additive to the team file's
  list. It is the effective list for that operator, in full.
- **Order is presentation, not matching.** The gate (below) checks presence and non-empty content per
  heading; it does not require the assembled body's sections to appear in the configured list's
  order.

## The pre-create gate

`/source-control:pull-request create`'s §2.4.2 pre-`gh pr create` gate checks, for every section in
the resolved `pr_body_required_sections` list, that a `## <heading>` section exists in the assembled
body **and** its content is non-empty. It judges the body with the shared section checker in the
source-control plugin's `hooks/pr-linkage-validator.sh`, which defines what a heading or content is. On failure it names the exact missing or empty section and the
resolved config source (the winning layer's file path and the `pr_body_required_sections` key),
never a bare "PR body invalid", so the actor who never saw the convention learns where it lives on
first failure, not by asking someone.

This gate is orthogonal to, and does not replace, the existing closing-keyword / no-issue-marker
check on the same body (`Closes #N` or `No related issue:`). That mechanism is unchanged by this
convention and documented at its own site in `create.md` §2.4.0/§2.4.2.

## Deferred: richer per-section schema

**V1 is a flat list of required heading names, nothing more.** The following are known,
deliberately deferred limitations, not oversights:

- **Conditional sections**: a section required only under a condition (e.g. a screenshots section
  required only for UI-affecting changes, or Kubernetes' `NONE`-sentinel release-note block) has no
  expression in a flat list.
- **Placeholder-content rejection**: the gate checks *non-empty*, not *non-placeholder-text*
  (`TBD`, `TODO`, a restated heading). A section satisfied by literally re-emitting the scaffold's
  own stub content is not currently caught beyond the empty case.
- **Minimum-content / structure rules**: no per-section length, format, or sub-structure
  requirement (e.g. "Test plan must contain at least one checklist item").

UI evidence needs no conditional section: when a diff changes rendered output,
`/source-control:pull-request create` drafts before/after media into the section that records
verification (`create.md`, "Visual evidence").
