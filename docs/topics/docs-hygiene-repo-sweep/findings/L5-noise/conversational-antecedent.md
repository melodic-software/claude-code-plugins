# L5-noise: `conversational-antecedent`

**2 candidates in. 0 findings out. 2 rejected. Plus a recall check, no additions.**

Both read in full.

## Rejections

### `plugins/playbooks/skills/fable-5/context/communication.md:120`

Verbatim:

```text
- Precedence: live user request > the user's standing instructions > operator convention > project convention files > your defaults. Higher wins — but state the collision in one line as you proceed ("doing X per your request; note the project guide says Y"), because silent precedence hides the conflict from the only person who can resolve it.
```

The cue `per your request` sits inside a quoted model of what the agent should say to a user when
announcing a precedence collision. It is prescribed output, not an address to a requester who has
since vanished. Deleting it would delete the example the rule exists to give.

### `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md:20`

```text
As you asked, the cap sits at 30s rather than the 45s default.
```

Detector eval fixture, authored to trip the shape. The skill's prescribed corpus for a repo-wide
run excludes `**/evals/fixtures/**`.

## Recall check

A corpus-wide grep over all 1218 scanned files for the shape's full cue family:

```text
as (you|we) (asked|requested|discussed)
per your request
as requested
per our (discussion|conversation)
like you said
you (asked|mentioned) (for|that)
```

returns 17 hits. Every one is a shape definition (the sibling
`plugins/code-tidying/skills/audit-comment-residue/SKILL.md:38` and this skill's own row), a
quoted worked example, or ordinary descriptive prose about a request the reader can still see
(`the page you asked for`, `the size you asked for`, `when --execute was requested`). None is an
address to the conversation that produced the page.

No recall gap, and the true population of this shape in the corpus is zero.

## Cross-lane observations

- **L1-derivability, L3-ssot, L6-compress.** Nothing.
