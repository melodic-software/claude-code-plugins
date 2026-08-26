# L4 encapsulation. Leaked skills in `plugins/context-budget`

1 violation, from the plugin README into `context-budget:audit`.

**Owning skill:** `context-budget:audit` (`plugins/context-budget/skills/audit/`).
**Private surface reached:** `reference/levers.json`.
**Leak kind:** private subdir.
**Citing file:** `plugins/context-budget/README.md:53`, an external consumer under the contract.

## V-cb-01

Verbatim:

```text
  `skills/audit/reference/levers.json` carries its honesty category (does it remove weight, work
```

**A note on why the data-file carve-out does not apply.** The contract exempts plain data files at
skill *root* (`<skill>/<name>.json`), on the reasoning that the file is the canonical single source
the skill reads at runtime and a vendored copy would race the skill's writer. This file is at
`skills/audit/reference/levers.json`, one level down inside a private subdirectory, so the carve-out
does not reach it. The detector's own pattern comments say the same thing: it matches any path into a
subdirectory under a skill and explicitly does not match plain-JSON data files at skill root.

**Public surface element:** `/context-budget:audit`.

**Replacement text:**

```text
  `/context-budget:audit` carries each lever's honesty category (does it remove weight, work
```

## Two clean remedies, pick one at apply time

- **Path B. route**, the replacement above. Correct if the README is describing what the audit
  reports, which the sentence suggests.
- **Move the file to skill root**, that is `plugins/context-budget/skills/audit/levers.json`, which
  brings it inside the data-file carve-out and makes the README's path cite legal as written. This is
  the right call only if the levers table is genuinely a canonical data source other tooling reads at
  runtime. Check whether any script in the plugin reads the path before choosing it; if nothing
  outside the skill reads it, route instead.

Do not leave it as-is on the grounds that it is "only JSON". The contract puts location of
non-root data files on the private side without exception.

## Cross-lane observations

- L8 (write-for-humans): `plugins/context-budget/README.md` is a HUMAN-audience file. The replacement
  keeps the sentence intact.
