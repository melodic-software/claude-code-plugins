# L7 findings: `J-toolchain-platform`

Slice audited: 98 `AGENT` rows (31 `T2`). Predicates emitted here: P3.

Verbatim source quotes and proposed replacements are in fenced `text` blocks so wave 3 can match
them against the real files.

## P3 · pointer does not front-load the leading word

All three sit in `playwright`'s on-demand reference tree. All are `T3`, so all are `S3`: the cost is
paid only when something reads the file, and none of the three changes what the agent does.

### J-1 · `plugins/playwright/skills/playwright/reference/storage-and-auth.md:53` (T3, S3)

Verbatim:

```text
See [running-code.md](running-code.md).
```

A bare pointer: no leading term, no statement of what the reader gets. It follows a fenced
`playwright-cli` snippet that evaluates page code.

Replacement:

```text
Running arbitrary page code: see [running-code.md](running-code.md).
```

### J-2 · `plugins/playwright/skills/playwright/reference/commands.md:52` (T3, S3)

Verbatim:

```text
See [snapshots-and-refs.md](snapshots-and-refs.md) for ref system.
```

Replacement:

```text
Ref system: see [snapshots-and-refs.md](snapshots-and-refs.md).
```

### J-3 · `plugins/playwright/skills/playwright/reference/commands.md:129` (T3, S3)

Verbatim:

```text
See [sessions.md](sessions.md) for `-s=<name>` session isolation; [windows-quirks.md](windows-quirks.md) for `--headed` on Windows.
```

Both halves state their payload, so this passes P4. Only the opening routing verb fails P3.

Replacement:

```text
Session isolation with `-s=<name>`: see [sessions.md](sessions.md). `--headed` on Windows: see [windows-quirks.md](windows-quirks.md).
```

## Not filed

`plugins/machine-health/skills/audit/scripts/linux/NOT_IMPLEMENTED.md:21` and its `macos` sibling
both open with a `See ../../references/<os>/NOT_IMPLEMENTED.md for the full porting checklist`
pointer, which is a P3 miss on the same shape. They are not filed here because the audience of both
files is a human porting the scripts, not an agent. See the reclassification proposal in `README.md`.
