# MCP posture checklist

Criteria P1-P5 for `/mcp-tools:audit-posture`. Each criterion names its severity rule and what it
reads from the inventory. The factual claims behind the criteria are in [Source records](#source-records),
each as a four-part record (claim, basis, as-of date, recheck trigger).

## Contents

- [Severity and scoring](#severity-and-scoring)
- [P1 Floating version](#p1-floating-version)
- [P2 Local stdio where the vendor offers a remote endpoint](#p2-local-stdio-where-the-vendor-offers-a-remote-endpoint)
- [P3 Publisher provenance](#p3-publisher-provenance)
- [P4 OCI image available but unused](#p4-oci-image-available-but-unused)
- [P5 Inventory](#p5-inventory)
- [Source records](#source-records)

## Severity and scoring

- **FAIL**. The config can start different code tomorrow than it started today with no change on
  your side. Fix first.
- **WARN**. A weaker pin or a safer option not taken. Fix in the next pass.
- **info**. Worth knowing; no change expected.
- **PASS**. Criterion met.
- **n/a**. The criterion has no subject for this row (for example, P1 on a remote server).

Rows with `effective = yes` or `approval-unknown` are scored. `approval-unknown` is a project
`.mcp.json` server whose approval lives in a settings file the script does not read, so it may
load; mark its findings "if approved". Rows reading `shadowed-by:<scope>`,
`suppressed-by-managed`, or `disabled` stay in the inventory table and get no findings, because
Claude Code does not launch them from that entry.

P2, P3, and P4 depend on facts outside the config. A result reached without a lookup the operator
asked for carries the label `unverified`.

## P1 Floating version

Reads the `launcher` and `pin` columns. Mechanical: no judgment beyond this table.

| `pin` | Launcher that fetches a package at start (`npx`, `npm-exec`, `pnpm-dlx`, `yarn-dlx`, `bunx`, `uvx`, `uv-tool-run`, `pipx`) | Container launcher (`docker`, `podman`, `nerdctl`) |
|---|---|---|
| `floating-unversioned`, `floating-tag` | FAIL | WARN |
| `floating-range`, `mutable-tag`, `git-ref` | WARN | WARN |
| `unparsed` | WARN | WARN |
| `exact`, `digest`, `git-commit` | PASS | PASS |
| `local-path`, `not-a-package` | n/a | n/a |
| `wrapped` (launcher `local`) | WARN | WARN |

- A package runner resolves the spec each time the server starts, so an unversioned or
  `@latest` spec runs whatever the registry serves that day. This is why it is the only FAIL.
- A container launcher resolves a tag when the image is pulled, not on every start, so a floating
  tag is WARN there. It is still not pinned: only an `@sha256:` digest is.
- `local` launchers (`pin` = `local-path` or `not-a-package`) and `remote` rows (`pin` = `n/a`)
  are `n/a` for P1. Name a `local-path` row in the details so the operator knows the code on disk
  is theirs to track.
- `unparsed` means the script could not isolate a package spec without risking printing an
  argument that may be a secret, so the package column reads `-`. It is WARN because the pin is
  unknown; ask the operator to check that entry by hand.
- `wrapped` appears on a `local` row whose arguments still name a package runner or container
  tool after the script unwrapped the shells it knows (`bash -c`, `cmd /c`, `env`,
  `pwsh -Command`). It is WARN because a floating runner may sit behind the wrapper.

## P2 Local stdio where the vendor offers a remote endpoint

Reads `transport` and `publisher`. Applies to `stdio` rows.

- **WARN** when the vendor publishes a hosted (HTTP) MCP endpoint for the same service and the
  config runs a local stdio package instead.
- **PASS** when no hosted endpoint is known, or the row is already `http` or `sse`.

Prefer the remote endpoint because it runs no code on your host: a stdio server runs
as a local process outside the Claude Code sandbox (see the sandbox record). Do not cite OAuth or
token-audience rules as the rationale. Those govern how a compliant server handles tokens and do
nothing against a hostile package.

Label the result `unverified` unless the operator asked for a vendor lookup in this run.

## P3 Publisher provenance

Reads `package` and `publisher`. Applies to rows with a package spec.

- **WARN** when the package name suggests a vendor (it contains a company or product name) but the
  publisher is not that vendor: an unscoped npm name, or a scope the vendor does not use.
- **info** when the publisher cannot be judged from the name alone.
- **PASS** when the publisher is the vendor's own scope or namespace.

Worked case: `postmark-mcp` on npm was an unscoped package named for Postmark that Postmark did not
publish (see the Postmark record). An unscoped name that matches a vendor is what P3 catches.

Registry namespace ownership is the only provenance signal the official MCP registry itself
provides, and the registry states it does little moderation beyond that (see the registry record).
A registry listing is therefore not evidence that a package is safe.

Label the result `unverified` unless the operator asked for a registry or vendor lookup in this
run.

## P4 OCI image available but unused

Reads `launcher`. Applies to package-runner and `local` rows.

- **info** when the vendor publishes an OCI image for the server and the config runs it through a
  package runner instead.
- **PASS** or **n/a** otherwise.

A container adds namespace isolation around the server process. It is not a sandbox boundary on
the level of a virtual machine, and a digest-pinned image still needs P1 and P3 to hold. Severity
stays at info because the benefit depends on how the container is run (mounts, network, user).

Label the result `unverified` unless the operator asked for a lookup in this run.

## P5 Inventory

The inventory table itself, one row per configured server, with the coverage footer. Not scored.
Its value is the diff between runs: a new server, a changed package, or a pin that loosened.

## Source records

### Sandbox coverage

- **Claim**: The Claude Code sandbox applies to Bash, PowerShell, and Monitor commands and their
  child processes. A stdio MCP server is started by Claude Code itself, not by one of those
  commands, so it runs outside the sandbox. Every stdio row is therefore `sandboxed = no`.
- **Basis**: <https://code.claude.com/docs/en/sandboxing>, which scopes sandboxing to "every Bash,
  PowerShell, or Monitor command and its child processes" and warns that a command editing
  protected config "could ... add a hook or MCP server that Claude Code runs outside the sandbox".
- **As of**: 2026-09-26.
- **Recheck trigger**: a re-fetch of that page no longer matching these quotes, or a Claude Code
  release note naming sandboxing together with MCP servers.

### Anthropic does not audit MCP servers

- **Claim**: Anthropic does not vet the MCP servers a user configures, so the operator owns that
  review.
- **Basis**: <https://code.claude.com/docs/en/security>: Anthropic "does not security-audit or
  manage any MCP server".
- **As of**: 2026-09-26.
- **Recheck trigger**: a re-fetch of that page no longer carrying the quoted sentence.

### Registry moderation

- **Claim**: The official MCP registry verifies namespace ownership and does little moderation
  beyond it; it does not remove a server for having a vulnerability, and it is in preview.
- **Basis**: <https://modelcontextprotocol.io/registry/moderation-policy>: consumers "should assume
  minimal-to-no moderation", and the registry will not remove "Servers with security
  vulnerabilities".
- **As of**: 2026-09-26.
- **Recheck trigger**: a re-fetch of that page no longer matching these quotes, or the registry
  leaving preview.

### Docker sandboxes and local MCP servers

- **Claim**: A virtual-machine sandbox around the agent does not contain a local stdio MCP server
  either; Docker's own sandbox model treats such servers as host integrations.
- **Basis**: <https://docs.docker.com/ai/sandboxes/security>: "local stdio MCP servers run on the
  host, not inside the" sandbox, and the page describes "local MCP servers as trusted host
  integrations".
- **As of**: 2026-09-26.
- **Recheck trigger**: a re-fetch of that page no longer matching these quotes.

### Postmark

- **Claim**: Postmark did not publish the `postmark-mcp` package on npm; it was a third-party
  package under Postmark's name.
- **Basis**: <https://postmarkapp.com/blog/information-regarding-malicious-postmark-mcp-package>.
- **As of**: 2026-09-26.
- **Recheck trigger**: a re-fetch of that post no longer stating that Postmark did not publish the
  package on npm.

### Configuration sources

- **Claim**: MCP servers are configured at user scope (top-level `mcpServers` in `~/.claude.json`),
  local scope (under the project's path in `~/.claude.json`), project scope (`.mcp.json`), and by
  managed configuration (`managed-mcp.json`, and `managedMcpServers` in `managed-settings.json`
  plus `managed-settings.d/*.json` in the same system directory). Local wins over project, which
  wins over user, for the same server name. These are the sources the inventory script reads.
- **Basis**: <https://code.claude.com/docs/en/mcp>, <https://code.claude.com/docs/en/managed-mcp>,
  <https://code.claude.com/docs/en/managed-settings>.
- **As of**: 2026-09-26.
- **Recheck trigger**: a Claude Code release note naming an MCP scope, `managed-mcp.json`, or
  `managedMcpServers`, or a re-fetch of any of the three pages diverging from this record.
