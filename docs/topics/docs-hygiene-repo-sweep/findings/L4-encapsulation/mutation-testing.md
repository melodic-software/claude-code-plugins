# L4 encapsulation. Leaked skills in `plugins/mutation-testing`

5 violations, all skill-to-skill inside the plugin. Three skills form a cycle of private reaches:
`setup` reaches into `audit`, and `audit` reaches into `principles`.

**Leak kind:** private subdir (5 of 5).

## V-mut-01, V-mut-02. `setup` reaches into `audit`'s private `context/`

**Owning skill:** `mutation-testing:audit`. **Private surface:** `context/suppression.md`.
**Citing file:** `plugins/mutation-testing/skills/setup/SKILL.md`, a T2 surface.

| # | `path:line` | Verbatim |
|---|---|---|
| V-mut-01 | `plugins/mutation-testing/skills/setup/SKILL.md:41` | ``[`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/suppression.md`](../audit/context/suppression.md).`` |
| V-mut-02 | `plugins/mutation-testing/skills/setup/SKILL.md:74` | ``[`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/suppression.md`](../audit/context/suppression.md), not a subset of it:`` |

V-mut-02's phrasing ("not a subset of it") shows this is a content dependency: `setup` is asserting
that the suppression vocabulary it writes must match `audit`'s exactly. That is shared vocabulary
between two skills, so the durable fix is **Path A within the plugin**: promote the suppression
contract to `plugins/mutation-testing/reference/suppression-contract.md`, outside both skills, and
have `audit` and `setup` both cite it.

**Replacement text, V-mut-01 (post-promotion):**

```text
[`${CLAUDE_PLUGIN_ROOT}/reference/suppression-contract.md`](../../reference/suppression-contract.md).```

**Replacement text, V-mut-02 (post-promotion):**

```text
   [`${CLAUDE_PLUGIN_ROOT}/reference/suppression-contract.md`](../../reference/suppression-contract.md), not a subset of it:```

**Route-only alternative, V-mut-01:** ``the suppression contract `/mutation-testing:audit` enforces.``

## V-mut-03, V-mut-04. `audit`'s SKILL.md reaches into `principles`

**Owning skill:** `mutation-testing:principles`. **Private surfaces:**
`reference/scaling-and-suppression.md`, `reference/metrics.md`.

| # | `path:line` | Verbatim | Replacement text |
|---|---|---|---|
| V-mut-03 | `plugins/mutation-testing/skills/audit/SKILL.md:224` | ``[`scaling-and-suppression.md`](../principles/reference/scaling-and-suppression.md) "The node-kind`` | ```/mutation-testing:principles` ("The node-kind`` |
| V-mut-04 | `plugins/mutation-testing/skills/audit/SKILL.md:240` | ``skill's [`${CLAUDE_PLUGIN_ROOT}/skills/principles/reference/metrics.md`](../principles/reference/metrics.md), and this skill does not restate it:`` | ``skill (`/mutation-testing:principles`), and this skill does not restate it:`` |

V-mut-04 is the good case for routing: the citing line already says the content is not restated
here, which is precisely what a slash invocation expresses.

## V-mut-05. `audit`'s context file reaches into `principles`

**Owning skill:** `mutation-testing:principles`. **Private surface:**
`reference/scaling-and-suppression.md`. **Citing file:**
`plugins/mutation-testing/skills/audit/context/suppression.md:20`.

Verbatim (the cite inside a long table cell):

```text
The `<node-kind>` vocabulary is enumerated in full in the `principles` skill's [`scaling-and-suppression.md`](../../principles/reference/scaling-and-suppression.md) ("The node-kind vocabulary") — that table is the whole list, and a survivor fitting none of it **is not arid** and must not be suppressed.```

This is the strongest content dependency in the plugin: a validation rule ("validation is membership
in that table") binds one skill's correctness to a table inside another skill's private reference.
A rename there silently turns a hard validation rule into a dangling pointer.

**Preferred remedy, Path A within the plugin:** the node-kind vocabulary is the shared term set for
`audit`, `principles`, and (via V-mut-01/02) `setup`. Promote the table to
`plugins/mutation-testing/reference/node-kind-vocabulary.md`.

**Replacement text (post-promotion):**

```text
The `<node-kind>` vocabulary is enumerated in full in [`${CLAUDE_PLUGIN_ROOT}/reference/node-kind-vocabulary.md`](../../../reference/node-kind-vocabulary.md), that table is the whole list, and a survivor fitting none of it **is not arid** and must not be suppressed.```

**Route-only alternative:**

```text
The `<node-kind>` vocabulary is enumerated in full by `/mutation-testing:principles` ("The node-kind vocabulary"), that table is the whole list, and a survivor fitting none of it **is not arid** and must not be suppressed.```

Both replacements drop an em dash present in the original, which brings the line into line with the
house prose style. Flag to reconciliation so the L5/L6 in-file lane does not count it twice.

## Cross-lane observations

- L3 (SSOT): suppression vocabulary appears in `audit/context/suppression.md`,
  `principles/reference/scaling-and-suppression.md`, and `setup/SKILL.md`. Three instances clears
  L3's Rule of Three, and the SSOT artifact L3 would mint is the same
  `plugins/mutation-testing/reference/` file this lane needs. One artifact, not two.
