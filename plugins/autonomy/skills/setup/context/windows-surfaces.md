# Windows execution surfaces: isolation substrate records

The guardrail slice reads this file at step 1 (detect), step 3 (probe), and step 6 (fail-closed)
for any execution surface whose host is Windows: native Windows, a WSL2 distribution, or a VM or
microVM launched from it. The
[isolation-ladder leaf](../../../reference/guardrails/isolation-ladder.md) owns the
levels; this file restates only the instance facts a binding depends on. Product names are marked
examples, never an instance list, and every candidate still passes the
[isolation probe](../templates/isolation-probe.md) before it binds.

## Native Windows

Claude Code's own sandboxing gives a native Windows surface no boundary. With nothing else, the
surface is `L0`. An org-supplied Windows boundary is judged by its own probe, not by this record.

- **Pointer**: when deciding which platforms Claude Code's sandboxing covers, fetch
  [Get started](https://code.claude.com/docs/en/sandboxing#get-started),
  [OS-level enforcement](https://code.claude.com/docs/en/sandboxing#os-level-enforcement),
  [Choose an approach](https://code.claude.com/docs/en/sandbox-environments#choose-an-approach) and
  [Sandbox runtime](https://code.claude.com/docs/en/sandbox-environments#sandbox-runtime) live.
- **As of**: 2026-11-10
- **Recheck trigger**: any of those sections, or a Claude Code changelog entry, adds native Windows
  as a platform the per-command sandbox or the sandbox runtime supports.

Settings alone never evidence `L1` on native Windows. Setup records neither `sandbox.enabled` nor
`sandbox.failIfUnavailable`, at any value, as a boundary there.

- **Pointer**: when judging what these settings do on an unsupported platform, fetch
  [`sandbox.enabled`](https://code.claude.com/docs/en/settings-reference#sandbox-enabled),
  [`sandbox.failIfUnavailable`](https://code.claude.com/docs/en/settings-reference#sandbox-failifunavailable)
  and the warning under [Get started](https://code.claude.com/docs/en/sandboxing#get-started) live.
- **As of**: 2026-11-10
- **Recheck trigger**: either setting's section, or the Get started warning, says the sandbox runs
  on native Windows.

## WSL2 distribution

A bare WSL2 distribution is neither `L3` nor `L2`, whatever its virtualization: with its default
automount and interop settings it reaches the host file system and executes on the host. Never
ratify one as `vm-microvm`; with nothing else inside it, it is `L0`.

- **Pointer**: when judging what a default WSL2 distribution reaches on the host, fetch Microsoft's
  [Automount settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#automount-settings)
  and [Interop settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#interop-settings)
  live.
- **As of**: 2026-11-10
- **Recheck trigger**: either section's defaults stop mounting the Windows drives or stop launching
  Windows processes from the Linux side.

On WSL2 the built-in sandbox is `L1`, whatever filters are installed, since it does not wrap the
whole process. The `L2` candidates are a whole-process wrap (the sandbox runtime) or a container
with default-deny egress.

- **Pointer**: when judging what the built-in sandbox and the runtime cover on WSL2, fetch
  [OS-level enforcement](https://code.claude.com/docs/en/sandboxing#os-level-enforcement),
  [Scope](https://code.claude.com/docs/en/sandboxing#scope),
  [How isolation relates to permission modes](https://code.claude.com/docs/en/sandbox-environments#how-isolation-relates-to-permission-modes),
  [Sandbox runtime](https://code.claude.com/docs/en/sandbox-environments#sandbox-runtime),
  [What the runtime blocks on its own](https://code.claude.com/docs/en/sandbox-environments#what-the-runtime-blocks-on-its-own)
  and [After unattended runs](https://code.claude.com/docs/en/sandbox-environments#after-unattended-runs)
  live.
- **As of**: 2026-11-10
- **Recheck trigger**: the Scope section puts file tools, MCP servers and hooks inside the built-in
  sandbox, or the runtime sections change how it loads its settings file or when it builds its
  deny list.

The runtime binds only with these limits:

- Launch it with an explicit `--settings <file>`; a clean start alone is no proof the settings
  loaded.
- The workspace repository exists before launch, and anything the session created is reviewed
  after an unattended run.

A Windows binary launched from WSL2 runs on the Windows host, outside every WSL2 boundary, unless
the boundary denies the launch; an installed filter is not evidence that it does.

- **Pointer**: when judging how a WSL2 sandbox treats a Windows binary launch, fetch the WSL2 notes
  under [Set up Linux and WSL2](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2)
  live.
- **As of**: 2026-11-10
- **Recheck trigger**: that section stops routing a Windows binary launch from WSL2 to the Windows
  host, or changes which setting blocks it.

So every WSL2 boundary adds an interop launch check to step 3: a harmless launch by absolute path
(marked example: `/mnt/c/Windows/System32/cmd.exe /c ver`) must succeed in the outer context and
fail inside the boundary. The outer success is the control: without it, a launch that fails
because the binary is off the path or the check never ran inside the boundary would read as
blocked. The inner run first proves the executable is present inside the boundary (a file test
that succeeds, recorded); where the boundary has no Windows drive mount, as in most containers,
copy a harmless Windows executable into the boundary and launch that copy. An inner failure that
reports a missing file is no evidence; only a denied launch of a present executable counts. Which
filter is installed is not the evidence; the paired outcomes are. The level binding ratifies
`host_interop: "wsl2"` for a WSL2 surface, and the transcript records the check as the fourth
assertion, `interop_launch_denied` (shape in [`isolation-probe.md`](../templates/isolation-probe.md)).
The checker enforces it: a WSL2 `L2` or `L3` binding whose transcript lacks the assertion, or
records an inner launch that succeeded, stays unproven and is blocked at step 6. The assertion
binds the inner launch to the outer control: identical arguments, equal SHA-256 digests of both
files, and a PE `MZ` header on the inner file. A binding that
ratifies `host_interop: "none"` while its capture reached a Windows drive mount stays unproven too.
That signal covers the default `/mnt/<letter>/` automount root only; a moved `[automount] root` is
not detected.

WSL2 probes also look through the Windows drive mount (the automount record above). Credential
probes and `--credential-roots` include the Windows profile paths the distribution reaches there
(marked example: an `.ssh` directory under `/mnt/c/Users/<user>/`), since hiding the
distribution's own home proves nothing about the host's. A workspace under a Windows drive mount
is checked for containment from the Windows side, where the host executes it.

## L3 microVM on a Windows host

The sandbox environments page's
[Virtual machine](https://code.claude.com/docs/en/sandbox-environments#virtual-machine) section
names Docker Sandboxes (a marked example) as a microVM, and Docker's security page gives it a
separate kernel per sandbox, so its class is `vm-microvm`. A separate kernel is not ephemerality.
It counts as `L3` only when each run gets a sandbox created for that run and removed at teardown; a
reused sandbox carries a prior run's state and does not bind.

- **Pointer**: when judging what a sandbox keeps between runs, fetch Docker's
  [Start, stop, and remove](https://docs.docker.com/ai/sandboxes/usage/#start-stop-and-remove) and
  [Isolation layers](https://docs.docker.com/ai/sandboxes/security/#isolation-layers) live.
- **As of**: 2026-11-10
- **Recheck trigger**: the security page stops giving each sandbox its own kernel, or the usage
  section changes what a stopped sandbox keeps or how one is removed.

For this marked example, installation and the workspace follow these rules:

- Installing it has a one-time elevated step that turns on a Windows feature (a human step); read
  the requirements and the per-user install command at the pointer.
- The default workspace mode fails the containment probe. A conforming workspace is clone mode
  (`--clone`) or a sandbox created with no workspace path. Each extra workspace is mounted
  read-only (`:ro`) or the containment probe fails again. Create a clone-mode sandbox from the
  main checkout, not from another Git worktree.
- A writable shared agent skills store is a host write outside the workspace that other sandboxes
  read. Require it absent or read-only, and record its mode in the prepared change.

**Pointer**: when installing it or choosing its workspace, fetch Docker's
[Install on Windows](https://docs.docker.com/ai/sandboxes/install/#install-on-windows),
[Choose a workspace](https://docs.docker.com/ai/sandboxes/usage/#choose-a-workspace),
[Clone mode](https://docs.docker.com/ai/sandboxes/usage/#clone-mode),
[Multiple workspaces](https://docs.docker.com/ai/sandboxes/usage/#multiple-workspaces) and
[Trust boundaries](https://docs.docker.com/ai/sandboxes/security/#trust-boundaries) live.
**As of**: 2026-11-10. **Recheck trigger**: the usage page changes which workspace modes mount the
host directory read-write or where clone mode is accepted, or the security page changes how the
skills store can be mounted.

For this marked example, egress, credentials and the permission posture follow these rules:

- List the active egress rules with `sbx policy ls`, remove those the run does not need, and
  choose both well-known probe targets outside every remaining allow rule, wildcards included.
- This record covers only an API key stored with `sbx secret set anthropic`, which stays on the
  host side. The subscription path (`/login` inside the sandbox) is not covered; the credential
  probe decides it.
- Bind the startup command's permission posture explicitly under the ladder's Permission posture
  (at `L2` and above the boundary replaces prompts); setup never records it as discovered.

**Pointer**: when setting egress, credentials or the startup posture, fetch Docker's
[Security considerations](https://docs.docker.com/ai/sandboxes/security/#security-considerations),
[Isolation layers](https://docs.docker.com/ai/sandboxes/security/#isolation-layers),
[Authentication](https://docs.docker.com/ai/sandboxes/agents/claude-code/#authentication) and
[Default startup command](https://docs.docker.com/ai/sandboxes/agents/claude-code/#default-startup-command)
live. **As of**: 2026-11-10. **Recheck trigger**: the security page changes whether egress is
denied by default or where a stored API key lives, or the Claude Code agent page changes the
startup command's permission flags.

A forwarded SSH agent lets a run push or sign with the host's identity, and the credential probe
cannot detect it. A microVM binds only with forwarding disabled for the run, shown by an in-VM
check that no agent answers (recorded beside the probe transcript), or with the signing capability
listed in the prepared change for the human to ratify.

- **Pointer**: when judging SSH agent forwarding, fetch Docker's
  [Credential isolation](https://docs.docker.com/ai/sandboxes/security/isolation/#credential-isolation)
  live.
- **As of**: 2026-11-10
- **Recheck trigger**: that section changes whether the SSH agent is forwarded by default or what a
  process inside the sandbox can ask it to do.

The remaining allowlist is shown in the prepared change for the human and recorded on the level
binding as `base_egress_allowlist`, an informational field. It is never merged into
`component_reachable_hosts`, which lists destinations the probe must show denied, and it is never
proof that other traffic is denied: the checker checks its shape and reads nothing else from it.

A local stdio server and an OCI-packaged stdio server registered on its MCP gateway execute on the
host. They are the ladder's brokered protocol-connected tool surfaces, outside the boundary at
`L3`. Inventory alone does not stop a tool call from leaving the VM, so an autonomous `L3` run is
created with `--static-mcp` naming no local stdio or OCI-packaged server. Each remote server in the
static set is a host-side connection the in-VM egress probe cannot see; list it in the prepared
change for the human to ratify. A run that needs a host-executing server is not `L3` and stays
human-gated.

- **Pointer**: when choosing the gateway's servers and mode, fetch Docker's
  [Register an MCP server](https://docs.docker.com/ai/sandboxes/mcp-gateway/#register-an-mcp-server),
  [Local stdio server](https://docs.docker.com/ai/sandboxes/mcp-gateway/#local-stdio-server),
  [Use static mode](https://docs.docker.com/ai/sandboxes/mcp-gateway/#use-static-mode),
  [Use dynamic mode](https://docs.docker.com/ai/sandboxes/mcp-gateway/#use-dynamic-mode) and
  [Trust boundaries](https://docs.docker.com/ai/sandboxes/security/#trust-boundaries) live.
- **As of**: 2026-11-10
- **Recheck trigger**: the gateway page runs a local stdio or OCI-packaged server inside the
  sandbox, or changes which servers static mode lets the agent attach.

## Fail-closed

A native Windows surface with no validated `L2` or `L3` binding blocks autonomous dispatch at step
6, and no setting lifts it. Setup names the compliant paths: a WSL2 distribution under the sandbox
runtime or a default-deny container, passing the probe and the interop launch check; or an `L3` VM
or microVM on the host, created fresh and removed per run, passing the probe in clone mode or with
no workspace mount, with no host-executing tool server attached and SSH agent forwarding disabled
or its signing capability ratified. Otherwise the surface stays human-gated.
