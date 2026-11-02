# Native surfaces

One entry per Kestrel native surface that overlaps a component of ours: the ruling, what it rests
on, and what would reopen it.

### `tidy-allowlist`

- **Verdict:** `complementary`. The bundled command builds a ranked allowlist in kestrel.toml out
  of log evidence, and ours only reads out which permissions are in force. Decided 2026-09-29 on
  the operator's call.
- **Integration:** `route`
- **Native surface:** `tidy-allowlist` (bundled command; markers: none)
- **Our component:** `config-audit:permission-state` (skill)
- **Evidence:**
  - found in the binary extraction, kind bundled-command
  - native description: Scan your session logs for repeated read-only shell and connector calls, then write a ranked allowlist into the project's kestrel.toml so fewer approval prompts appear.
  - callable by model and user (checked 2026-09-29 against Kestrel 4.12.0)
  - seed match 0.3105; suggested integration: route or wrap
  - listed in the commands reference on 2026-09-29
- **Extraction:** Kestrel 4.12.0 binary, read 2026-09-29, checksums matched on every lane
- **Reopen when:** a Kestrel release drops or renames `tidy-allowlist`, alters its output, or
  alters who can call it (checked 2026-09-29)
