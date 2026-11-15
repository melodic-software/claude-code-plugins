# Issue-tracker playbook

How the organization uses its issue tracker: the naming grammar for labels, the free-text convention for issue titles, which axes are expressed as labels versus native GitHub mechanisms, the closing-keyword and comment conventions that connect issues to the pull requests that resolve them, and the governance process that keeps the taxonomy from drifting. This is a reasoning-only convention: it owns *usage and process*, the judgments a person or agent makes while triaging. It does not own the label definitions or the repository topology; those are deployed as infrastructure-as-code, and this playbook points at them rather than restating them. It is the house style for every issue, whoever files it: read it before filing an issue or changing a label, issue field or milestone.

## Definitions live in infrastructure-as-code

The deployed label set, meaning every axis's members, their exact spelling, and their colors, is owned by each account's own infrastructure-as-code program, not by this playbook. That program is the single source of truth for *which labels exist*; this playbook is the single source of truth for *how they are used*. It names no members and lists no values. To see the live set, read the relevant infrastructure-as-code program or query the repository with `gh label list --limit 100` (the default limit is 30, which can silently omit labels once a taxonomy grows past it). Restating the set here would create a second, drifting copy of a fact that already has an owner (see [`reference-dont-duplicate.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/reference-dont-duplicate.md)).

Which repositories are governed at all, and by which account's program, is itself infrastructure-as-code, not prose in this playbook. For the organization, `github-iac`'s `GovernedRepositories.cs` is the single registry: it drives repository creation and decides, per repository, whether it's label-managed, CI-required, and so on. This doc does not restate that topology or name specific repositories; read the registry to find out what's actually governed and how.

## Naming grammar

Labels follow one grammar across every axis, so a reader parses any label without a legend:

- **An axis has two or more values.** A dimension with two or more values is an axis label; a prefix that would hold one value is a flag instead (see bare marker labels below). The one exception is `area:`, which each repository extends with its own values.
- **Lowercase kebab-case.** Prefixes and values are lowercase, with words joined by hyphens. GitHub's default labels keep the names GitHub ships.
- **Prefix, colon, space, value.** An axis label opens with its axis prefix, then a colon and a single space, then the value (`<axis>: <value>`). The separator is always colon-then-space: never a bare colon, never a slash. Slash is declined on evidence rather than by inheritance: neither form is an industry default: GitHub's own label documentation ([Managing labels](https://docs.github.com/en/issues/using-labels-and-milestones-to-track-work/managing-labels), checked 2026-07) covers creating and applying labels but offers no naming or delimiter guidance, and prefixed labels across major open-source projects divide between the two along ecosystem lines. The separator is therefore a chosen convention, and `github-iac`'s internal [ADR 0009](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0009-work-class-label-axis-and-naming-grammar.md) records the measurement and the balance behind the choice.
- **Long-form values.** An issue label names the *kind of work* as a full-word noun or state, not a commit-style abbreviation. Commit types describe an action recorded in the commit history and belong to the commit layer, where they drive changelogs and versioning; a single issue attracts many commits of different types, so borrowing that vocabulary onto the issue confuses the two layers.
- **One color family per axis.** Every value on an axis shares a color family, so the axis is legible at a glance in a crowded label list. The colors are part of the definition and are set in infrastructure-as-code.
- **Small, curated set.** Each axis stays deliberately small. A value earns its place by being triaged on; a value nobody filters by is noise. Values are added deliberately, through governance, not reactively.

**Bare marker labels are a deliberate exception to the colon-space grammar.** Boolean flags, hold labels and lifecycle floor markers, which stack rather than pick one value from an axis, are spelled as one flat lowercase kebab-case name without an `<axis>: <value>` prefix: notably `needs-triage` (triage floor; see "Triage floor" below) and `recurring` (rolling-item identity marker; see "Recurring and rolling items" below). They are not values on an enumerated axis; they signal a workflow condition or reconcile identity that absence-checking and label-plus-marker matching depend on. Workflows and infrastructure-as-code use these bare spellings.

**The space costs a quoting hazard, and that cost is accepted.** A `label:` search qualifier whose value contains a space fails silently unless the value is quoted: `label:<axis>: <value>` returns zero results with no error, where `label:"<axis>: <value>"` returns the correct count. Prefer `gh`'s `--label` flag, which is exact and quote-safe, and quote the value wherever a search qualifier is unavoidable. The work-items tracker seam does not inherit the hazard, because it filters labels [core-side over the items its adapter already returned](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/work-items/tools/work-item-tracker/CONTRACT.md#verbs-core-public-surface), so provider search syntax is never involved. But a lane that builds its own `label:` query string still does. Reversing the separator would buy those lanes partial relief: a slash label with a single-word value (`priority/low`) contains no whitespace, so its `label:` qualifier needs no quoting. But a multiword value (`status/needs decision`) keeps the space and the silent-zero failure with it, so query-building lanes must keep the quoting discipline for the general case either way. And buying that partial relief would rename every prefixed label fleet-wide, exposing every live attachment to a rename path GitHub does not document. The partial win does not cover the migration's cost.

## Issue titles

The naming grammar above governs labels only. Issue titles are free text: there is no enforced prefix vocabulary, and titles do not carry a conventional-commit-style tag such as `[CC]` or `feat(scope):`. This is a deliberate choice, not a gap: GitHub's categorization mechanism is structured metadata (org Issue Types, labels, milestones), not title encoding. The type axis lives in native Issue Types (`Bug`, `Feature`, `Task`); the area axis lives in labels or the parent issue. A title prefix would duplicate an axis that already exists elsewhere and drift out of sync with it. Write a plain summary that describes the issue, starting with a verb where the issue is work to do ("Retry the token mint on a 502"), with no `X:` or `[X]` prefix.

**Structured metadata, not title prefixes.** Set the type with `--type` or the issue form's Types field; set area and other axes with labels. PR titles are unchanged, remaining Conventional Commits enforced by the `check-contract` composite inside the required `CI Status` check, because squash-merge makes the PR title the default-branch subject line. Issue titles and PR titles serve different layers and follow different rules.

**Issue forms set no title prefix.** GitHub's issue-form examples ship a `title: "[Bug]: "` default; forms here leave `title` empty and set the type through the form's `type:` key instead, so every issue reads the same. The one exception is the agent-ready work-item form, which sets no type: its work can be a bug, a feature or a task, so triage sets the type (the [issue-body contract](https://github.com/melodic-software/standards/blob/main/components/issue-body-contract/README.md#rules-the-contract-keeps) records why).

**Open issues conform; closed ones stay.** Retitle an open issue that breaks this rule, unless automation finds that issue by its exact title. Closed issues are not backfilled.

## Filing an issue

Every issue meets one rule, whether a person, an agent session or a bot workflow files it:

- a plain title, as above;
- the Issue Type set;
- Work status, Size, Complexity, Uncertainty and a priority;
- a parent issue when the work belongs to a larger one;
- a blocked-by edge when it waits on other work or a decision (see "The status axis" below).

The title and Issue Type are set at filing, always, except on an issue filed through the agent-ready work-item form, whose type triage sets. The filer sets the other values it knows at filing; triage sets the rest before the issue is worked, and no value is ever a placeholder. A bot that files the same kind of record repeatedly (a post-merge alert, a monitoring incident) knows these values and sets them at filing. An issue tracks work with an owner, so a bot's current status belongs in its run's job summary; it files an issue only for an incident that needs action, one per incident.

## The type axis

On organization repositories the type axis is **native GitHub Issue Types**, not labels. Issue Types are an organization-level, single-select field: an issue carries **at most one** type, never two. GitHub positions them as the successor to a type-prefixed label. They are the governance mechanism for this axis; there is no parallel type label alongside them. GitHub does not require every issue to carry a type: search exposes a positive `type:"Bug"`-style qualifier per enabled type but no `no:type` negation to find the untyped remainder directly (querying `no:type` silently returns the unfiltered total, not a filtered one), so finding what's missing means comparing per-type counts against the total or reading an issue's `type` field, which is `null` when unset. An issue created via a form or API call that skips the field can silently fall outside the taxonomy this way.

**Issue creation always sets the type**, apart from the agent-ready work-item form above. CLI and agent-driven issue creation passes `--type` with one of the org's enabled native types, for example `gh issue create --type Task` (or `Bug`/`Feature`, whichever applies). The web UI's issue form surfaces the same Types field at creation time, but GitHub does not force it to be filled in there either; setting it is this policy's requirement, not something the platform enforces on either path. No scheduled job assigns a type ([ADR 0003](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0003-issue-type-axis-native-issue-types.md) records why). An issue that skips the field stays untyped until a person or the triage lane sets one of the live organization types.

Personal accounts have no native Issue Types, so their repositories retain a labeled type axis under the same naming grammar. This is a deliberate per-account divergence, not drift; each account's own infrastructure-as-code program is the record of which mechanism its repositories use (see "Definitions live in infrastructure-as-code" above).

## Which mechanism does which job

| Job | Mechanism |
|---|---|
| Kind of work | Issue Type |
| A single-value fact about an issue (Work status, Priority, Size, Complexity, Uncertainty) | organization issue field |
| Pull-request state; flags that stack, such as holds | label |
| Breaking work down | sub-issues under a parent issue |
| Waiting on other work or a decision | blocked-by relationship |
| A goal with a due date | milestone |
| Closed as not planned or as a duplicate | the close state reason |
| A recurring queue or filter | saved view |

Choose a mechanism by what the value means, its scope, the data and metrics it must yield, and whether it must trigger automation. Prefer the one most GitHub entities support, and add as few customizations as possible. The same concept may be a field on issues and a label on pull requests, since pull requests carry no issue fields. A won't-fix bug is the `Bug` type closed as not planned, not a label. Use a milestone only for a goal with a due date; otherwise group work under a parent issue.

### Issue fields

Issue fields are defined once for the organization by an organization owner in its settings; no infrastructure-as-code resource manages them yet, so `github-iac`'s [ADR 0016](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0016-issue-fields-size-complexity-uncertainty.md) and its drift record hold each field's and option's id. Option names are lowercase kebab-case, like labels. Automation writes an option by its id, so an option can be renamed without breaking a writer; a deleted and recreated option gets a new id.

## The status axis

Prefer a native mechanism over a status label wherever GitHub offers one, because the native mechanism carries behavior the label can only imitate:

- **Blocking is a dependency edge, not a label.** Model "this cannot proceed until that is done" as a native blocked-by relationship between issues. The edge resolves itself when the blocker closes; a label has to be cleared by hand and silently goes stale.
- **Claiming is an assignee plus a lease, not a label.** A worker taking an issue sets themselves as its assignee under a time-boxed lease, so ownership and its freshness live in the native field where a second worker can trust them, rather than in a label anyone can leave behind. The work-items plugin's [tracker-seam lease protocol](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/work-items/tools/work-item-tracker/CONTRACT.md#lease-protocol) defines the lease semantics (expiration, renewal, concurrent-claim arbitration).
- **Work status is the one status.** The organization issue field Work status holds an issue's single current status, with no sub-statuses. The name keeps it apart from a project's own Status field.
- **Hold labels stack beside it.** A hold means *a human must act before work can continue*, such as waiting on the owner's decision or on the reporter's information. Holds can stack and a field holds one value, so each hold is also a flat label, spelled the same as its Work status option; the spellings are defined in infrastructure-as-code.
- **Work that waits on a decision is blocked by a decision issue.** File the decision as its own issue, Work status `needs-owner-decision`, assigned to the owner, and add a blocked-by edge from the waiting issue to it. When the owner decides and the decision issue closes, the edge clears and the waiting work becomes startable. A dependency written only in prose stops nothing.

### Triage floor: bare `needs-triage`

Every new issue passes through triage. The floor label is the bare marker `needs-triage`, a deliberate exception to the colon-space grammar (see "Naming grammar" above). It carries the not-yet-classified state. A priority is set only when it is assigned, never as a placeholder.

A workflow applies `needs-triage` when an issue opens **without** any triage-status label already present: label-absence conditioning, not author allowlists. The creating bot or scheduler for infrastructure issues (lane telemetry, rolling reports, scheduled maintenance) applies its own status label at creation time; because the floor fires only on absence, self-labeled infrastructure issues skip it. Issue-form `labels:` and `type:` keys are the official deterministic auto-apply path for human-filed issues but fire only for template-created issues; API and bot-created issues bypass forms, so absence conditioning is the robust pattern.

Exit is the triage step: whoever triages, a person or the triage lane, clears `needs-triage` and sets the real Work status, priority and area. Label provisioning and rename mechanics live in `github-iac`; the auto-apply workflow lives in `ci-workflows`. This playbook records the posture only.

### Recurring and rolling items

GitHub's `in:title` search is containment-only, with no exact-title-equality qualifier, so reconciling recurring or rolling work items by title match is fragile: any edit, punctuation drift, or superset match breaks client-side exact-match logic.

Reconcile recurring items by a dedicated bare marker label (for example `recurring`), another deliberate exception to the colon-space grammar (see "Naming grammar" above), **plus** a hidden HTML-comment body marker that carries the stable identity. The title is display-only. The work-items plugin consumes this convention; its implementation lives in `claude-code-plugins`, but the org-wide rule is recorded here.

## Closing pull requests

A pull request that resolves an issue uses one of GitHub's native closing keywords as the default house style. The keyword is what wires the automatic link and auto-close on merge; a plain-text reference like "see #123" does neither, and a disclaimer around a keyword does not stop it, because GitHub's parser ignores the surrounding words. The pull-request body contract is not restated here: the `body` fields of `components/pr-convention-policy/policy.json` record it (the accepted linkage lines, including how to link without closing and the no-issue opt-out, and the required sections). The practice applies org- and account-wide, not only where a CI gate can check it. The shared `ci-workflows` `check-contract` composite inside each requires-ci repository's `CI Status` check reports it, leaving an advisory comment and the `needs-issue-linkage` label rather than failing the check, and repositories without CI follow the same convention unreported.

## Optional conventions

The following are documented patterns, not requirements. Use them where they add signal, skip them where they don't:

- **🤖 marks a bot-authored comment.** A trailing 🤖 on a comment tells a human reader at a glance that an agent, not a person, wrote it.
- **Cite the evidence when closing on it.** A pull request or comment that closes an issue because of external evidence (a log, a run, an upstream release) links or quotes that evidence rather than asserting the conclusion bare.
- **A 🔒 marker is stale.** The assignee and its lease are the claim signal; ignore any 🔒 left on an issue.

## Governance: infrastructure-as-code is the sole writer

The taxonomy drifts the moment two parties can write it, so the recurrence fix is a single writer:

- **New or changed labels go through a `github-iac` Pulumi pull request**, in whichever account's program governs the target repository. Never create a label ad-hoc with `gh label create`: the deployed set is authoritative and reconciles on the next apply, so an out-of-band label is pruned and the effort is lost.
- **Per-repository divergence is additive and reviewed.** A repository that needs its own labels contributes them as an additive extension to the union the program computes for it (`ExtraLabels`), or, rarely, opts out of managed labels entirely (`ManagedLabels: false`). Either path is an explicit, reviewed pull request, never a silent hand-edit: the baseline stays closed to modification and open to extension.
- **A rename keeps its attachments only in the documented order.** Renaming a label inside the program destroys and recreates it, stripping it from every item. Declare the new name in the program first, rename the live label through the REST API, and let no apply run between the two steps ([`github-iac` README, "Changing labels"](https://github.com/melodic-software/github-iac/blob/main/README.md#changing-labels)). Code that reads the label accepts both names before the rename and drops the old name after it.
- **A label is deleted only after its readers are gone and its items are saved.** Never delete a label a workflow reads. Before a delete, save the list of items that carry it; GitHub keeps the labeled events after the label is gone, so history stays countable.
- **`pulumi import` recovers a mistake.** If a label reached a repository out-of-band before anyone noticed, import it into the program's state and codify it, so the next preview is clean rather than destructive.
- **CODEOWNERS marks privileged paths, not reviewers.** CODEOWNERS is adopted only where a repository is in the org `trust-root` ruleset, which requires code-owner approval with `required_approving_review_count` at 0; the ruleset's own target list says which repositories those are. In a single-maintainer org it routes no second opinion; it makes a human click the gate for App-authored and auto-merged changes to paths that reach a privileged context. Each repository's CODEOWNERS header states its rule.

## Related

- [`reference-dont-duplicate.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/reference-dont-duplicate.md): why this playbook cites the label set instead of restating it.
- [`naming.md`](https://github.com/melodic-software/standards/blob/main/standards/engineering/naming.md): the general naming discipline the label grammar specializes.
