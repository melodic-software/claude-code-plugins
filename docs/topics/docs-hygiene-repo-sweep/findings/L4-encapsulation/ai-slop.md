# L4 encapsulation. Leaked skills in `plugins/ai-slop`

5 violations, all into `ai-slop:audit`. One of them is in a Tier 1 always-loaded rule file, which
makes it the highest-tier encapsulation violation in the repo.

**Owning skill:** `ai-slop:audit` (`plugins/ai-slop/skills/audit/`).
**Leak kind:** private subdir (5 of 5).

## V-slop-01. `.claude/rules/vendor-docs-are-not-style.md:10`, a T1 rule depends on a private reference

**Private surface reached:** `reference/rewrite-guide.md`.
**Tier:** T1. This file is one of the three always-loaded files in the corpus, and `CLAUDE.md`
imports `AGENTS.md`, so the rule text is paid for in every session.

Verbatim (lines 9-10):

```text
Write this repo's prose to
`plugins/ai-slop/skills/audit/reference/rewrite-guide.md`.
```

The rule directs every agent in the repo to a file inside one skill's private body. It is also the
rule this sweep's own PLAN.md restates as a standing rule for all eight lanes, so the dependency is
not hypothetical: eight agents are currently told to open a private path.

**Public surface element:** none carries the content. The repo's house prose style is repo-wide
shared vocabulary by construction. The rule file names four instruction surfaces it binds
(`SKILL.md`, plugin READMEs, `AGENTS.md`, `CLAUDE.md`, `.claude/rules/**`), none of which belongs to
`ai-slop`. This is **Path A. promote out**.

**Remediation spec:**

1. Promote the rewrite guide's house-style rules to `docs/conventions/house-prose-style/README.md`,
   or fold them into `.claude/rules/vendor-docs-are-not-style.md` itself if they are short enough to
   carry inline at T1 cost.
2. Rewrite `plugins/ai-slop/skills/audit/reference/rewrite-guide.md` to cite the promoted doc rather
   than own the text, so the guide is not dual-maintained.
3. Rewrite this rule's closing sentence.

**Replacement text:**

```text
Write this repo's prose to
[`docs/conventions/house-prose-style/README.md`](../../docs/conventions/house-prose-style/README.md).
```

**Route-only alternative, if the promotion is deferred:** `Run /ai-slop:audit over this repo's own
instruction surfaces; it carries the house style.` That is weaker, because the rule wants the reader
to *write* to a standard, not to run a detector afterwards.

## V-slop-02. `docs/conventions/upstream-drift/README.md:342`

**Private surface reached:** `reference/catalog.md`. **Confidence:** medium. This is a registry row
recording where a conforming upstream-drift record lives, rather than a content dependency. It is
reported because the row is a live index that goes stale silently when the skill refactors.

Verbatim (leading cell of a long table row):

```text
| [ai-slop tell catalog](../../../plugins/ai-slop/skills/audit/reference/catalog.md) §Upstream-drift record | new with 1.5.0 |
```

**Public surface element:** `/ai-slop:audit`, plus the record's own name.

**Replacement text (leading cell only, the rest of the row unchanged):**

```text
| `/ai-slop:audit` tell catalog, §Upstream-drift record | new with 1.5.0 |
```

## V-slop-03, V-slop-04, V-slop-05. `plugins/ai-slop/README.md` reaches into its own skill

A plugin README is an external consumer under the contract: it is not carried when
`plugins/ai-slop/skills/audit/` is ripped and pasted into another repo, and READMEs are named
explicitly in the contract's list of external consumers.

| # | `path:line` | Verbatim | Private surface | Replacement text |
|---|---|---|---|---|
| V-slop-03 | `plugins/ai-slop/README.md:24` | ``The rule inventory in [`skills/audit/reference/catalog.md`](skills/audit/reference/catalog.md) is`` | `reference/catalog.md` | ``The rule inventory `/ai-slop:audit` carries is`` |
| V-slop-04 | `plugins/ai-slop/README.md:34` | ``[`skills/audit/reference/rewrite-guide.md`](skills/audit/reference/rewrite-guide.md), which the`` | `reference/rewrite-guide.md` | ``the house prose style `/ai-slop:audit fix` writes to, which the`` |
| V-slop-05 | `plugins/ai-slop/README.md:42` | ``(see [`skills/audit/context/persist-findings.md`](skills/audit/context/persist-findings.md)).`` | `context/persist-findings.md` | ``(see `/ai-slop:audit`, which persists findings for `/review:fanout fix` to consume).`` |

If V-slop-01's promotion lands, V-slop-04's replacement should point at the promoted
`docs/conventions/house-prose-style/README.md` instead, since the README is describing a standard
rather than a behavior.

## Cross-lane observations

- L3 (SSOT): the house prose style is a three-plus-consumer cluster once the T1 rule, this sweep's
  PLAN.md, and the plugin README are counted, so it clears L3's Rule of Three on its own. V-slop-01
  and any L3 finding on the same content should land one artifact.
