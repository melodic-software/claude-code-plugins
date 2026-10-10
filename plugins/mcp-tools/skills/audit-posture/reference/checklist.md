# MCP posture checklist

Criteria P1-P5 for `/mcp-tools:audit-posture`. Each criterion names its severity rule and what it
reads from the inventory. The decisions behind the criteria are in [Source records](#source-records),
each with a pointer to where the fact lives, an as-of stamp and a recheck trigger.

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
load; mark its findings "if approved". A user row reading `shadowed-by:project-if-approved` is
also scored, marked "if the project entry is not approved". Rows reading `shadowed-by:<scope>`,
`suppressed-by-managed`, `disabled`, `rejected-by-client`, or `skipped-by-client` stay in the
inventory table and get no findings, because Claude Code does not launch them from that entry.
`skipped-by-client` is a `"type": "sdk"` entry in a config file; see the SDK entries record.
`rejected-by-client` is a
`managedMcpServers` entry that fails the entry checks the script applies (`type` of `http`, `sse`,
or `streamable-http`, an `https://` URL, no `command`, `args`, `env`, or `headersHelper`, no
`${VAR}`, a name of letters, numbers, hyphens, and underscores, and no control or invisible
formatting character in any key or value), so the audit treats it as not loaded; see the managed
precedence record.

P2, P3, and P4 depend on facts outside the config. A result reached without a lookup the operator
asked for carries the label `unverified`.

## P1 Floating version

Reads the `launcher` and `pin` columns. Mechanical: no judgment beyond this table.

| `pin` | Launcher that fetches a package at start (`npx`, `npm-exec`, `pnpm-dlx`, `yarn-dlx`, `bunx`, `uvx`, `uv-tool-run`, `pipx`) | Container launcher (`docker`, `podman`, `nerdctl`) |
|---|---|---|
| `floating-unversioned`, `floating-tag` | FAIL | WARN |
| `floating-range`, `mutable-tag`, `git-ref`, `tarball` | WARN | WARN |
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
- `tarball` is an `http(s)://` spec ending in `.tgz` or `.tar.gz` on a host other than the npm
  registry: the URL is fixed, but the bytes behind it can change. A `registry.npmjs.org` tarball
  whose file name ends in `-<version>.tgz` reads `exact`, because the npm registry does not
  republish a version.
- `unparsed` means the script could not isolate a package spec without risking printing an
  argument that may be a secret, so the package column reads `-`. It also covers a `command`
  field holding a whole command line, a URL whose userinfo cannot be separated from the host
  unambiguously, and any wrapper string (`bash -c`, `env -S`, `cmd /c`, `pwsh -Command`) that
  holds quotes, escapes, shell operators, or anything beyond plain words and simple leading
  `NAME=value` assignments: the script reads such strings conservatively rather than emulating
  the shell. It is WARN because the pin is unknown; ask the operator to check that entry by hand.
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

Reads `package` and `publisher`. Applies to rows with a package spec. A publisher of
`index:<host>` means the Python package comes from a custom index rather than PyPI; judge the
index host as well as the package name. A publisher of `-` next to a parsed spec means a custom
index was set but its URL could not be shown safely.

- **WARN** when the package name suggests a vendor (it contains a company or product name) but the
  publisher is not that vendor: an unscoped npm name, or a scope the vendor does not use.
- **info** when the publisher cannot be judged from the name alone.
- **PASS** when the publisher is the vendor's own scope or namespace.

Worked case: `postmark-mcp` on npm was an unscoped package named for Postmark that Postmark did not
publish (see the Postmark record). An unscoped name that matches a vendor is what P3 catches.

P3 takes namespace ownership as the only provenance signal the official MCP registry supplies, and
treats a registry listing as no evidence that a package is safe (see the registry record).

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

The inventory marks every stdio row `sandboxed = no`: this audit treats a stdio MCP server as
started by Claude Code itself, outside the scope of the commands the sandbox covers.

- **Pointer**: for which commands the sandbox covers and the protected paths that keep a command
  from adding an MCP server, see <https://code.claude.com/docs/en/sandboxing> (the page
  introduction) and <https://code.claude.com/docs/en/sandboxing#protected-paths>.
- **As of**: 2026-09-26
- **Recheck trigger**: that page changes which commands the sandbox covers, or a Claude Code
  release note names sandboxing together with MCP servers.

### Anthropic does not audit MCP servers

The audit assigns the review of every configured MCP server to the operator; it never treats a
server as vetted by Anthropic.

- **Pointer**: for Anthropic's position on MCP server review, see
  <https://code.claude.com/docs/en/security#mcp-security>.
- **As of**: 2026-09-26
- **Recheck trigger**: that section changes what Anthropic reviews.

### Registry moderation

P3 takes namespace ownership as the only provenance signal from the official MCP registry and
gives a registry listing no weight as evidence of safety, including for known vulnerabilities.

- **Pointer**: for what the registry moderates, and its preview status, see
  <https://modelcontextprotocol.io/registry/moderation-policy>.
- **As of**: 2026-09-26
- **Recheck trigger**: that page changes what the registry moderates or removes, or the registry
  leaves preview.

### Docker sandboxes and local MCP servers

The audit does not count a virtual-machine sandbox around the agent as containing a local stdio
MCP server.

- **Pointer**: for how Docker's sandbox model places local MCP servers, see
  <https://docs.docker.com/ai/sandboxes/security>.
- **As of**: 2026-09-26
- **Recheck trigger**: that page changes where local stdio MCP servers run.

### Postmark

P3's worked case: the audit treats `postmark-mcp` on npm as a package under Postmark's name that
Postmark did not publish.

- **Pointer**: <https://postmarkapp.com/blog/information-regarding-malicious-postmark-mcp-package>.
- **As of**: 2026-09-26
- **Recheck trigger**: that post changes what it says about who published the package.

### Configuration sources

The inventory script reads user scope (top-level `mcpServers` in `~/.claude.json`), local scope
(under the project's path in `~/.claude.json`), project scope (`.mcp.json`), and managed
configuration (`managed-mcp.json`, and `managedMcpServers` in `managed-settings.json` plus
`managed-settings.d/*.json` in the same system directory), and ranks local over project over user
for the same server name.

- **Pointer**: for the scopes and their precedence, see
  <https://code.claude.com/docs/en/mcp#mcp-installation-scopes> and
  <https://code.claude.com/docs/en/mcp#scope-hierarchy-and-precedence>; for managed configuration,
  <https://code.claude.com/docs/en/managed-mcp> and
  <https://code.claude.com/docs/en/managed-settings#split-a-file-based-policy-across-teams>.
- **As of**: 2026-09-26
- **Recheck trigger**: a Claude Code release note naming an MCP scope, `managed-mcp.json`, or
  `managedMcpServers`, or a re-fetch of any of those pages diverging from this record.

### Managed precedence

The inventory reads a local, project, or user row whose name a `managedMcpServers` entry also
defines as `shadowed-by:managed-settings`; a managed-settings row whose name `managed-mcp.json` also
defines as `shadowed-by:managed`; and, when `managed-mcp.json` is present, every local, project,
and user row as `suppressed-by-managed`. A `managedMcpServers` entry failing the entry checks
listed under [Severity and scoring](#severity-and-scoring) reads `rejected-by-client`. The script
matches `type` case-sensitively, so `"HTTP"` reads `rejected-by-client`; the page does not settle
case handling.

- **Pointer**: for precedence between provided servers, `managed-mcp.json` and the other scopes,
  see <https://code.claude.com/docs/en/managed-mcp#how-provided-servers-load> and
  <https://code.claude.com/docs/en/managed-mcp#exclusive-control-with-managed-mcp-json>; for the
  entry checks, <https://code.claude.com/docs/en/managed-mcp#what-an-entry-can-contain>.
- **As of**: 2026-09-26
- **Recheck trigger**: the managed-mcp page changes precedence or the entry checks, or a Claude
  Code release note names `managedMcpServers` precedence or its entry checks.

### SDK entries

The inventory reads every `"type": "sdk"` entry it finds in a config file, in any scope including
`--config` files, as `skipped-by-client`: Claude Code does not load an in-process server from a
file, so the row is dead config, not a running server. A skipped row shadows no same-name row in a
lower scope; the page does not say whether the lower row then loads, and scoring it is the safer
reading for a posture audit. A `managedMcpServers` sdk entry still reads `rejected-by-client`,
because it fails the entry checks first.

- **Pointer**: when an sdk row appears, fetch
  <https://code.claude.com/docs/en/mcp#option-1-add-a-remote-http-server> (the note on `sdk`
  entries) and <https://code.claude.com/docs/en/changelog> (version 2.1.274) live.
- **Source conflict**: the mcp page
  (<https://code.claude.com/docs/en/mcp#option-1-add-a-remote-http-server>) and changelog 2.1.274
  (<https://code.claude.com/docs/en/changelog>) disagree on which config sources skip an sdk entry.
- **As of**: 2026-10-10
- **Recheck trigger**: the mcp page's `sdk` note changes the sources it names, or a Claude Code
  release note names `"type": "sdk"` entries.
