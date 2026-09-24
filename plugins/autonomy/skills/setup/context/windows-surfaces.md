# Windows execution surfaces: isolation substrate records

The guardrail slice reads this file at step 1 (detect), step 3 (probe), and step 6 (fail-closed)
for any execution surface whose host is Windows: native Windows, a WSL2 distribution, or a VM or
microVM launched from it. The
[isolation-ladder leaf](${CLAUDE_PLUGIN_ROOT}/reference/guardrails/isolation-ladder.md) owns the
levels; this file restates only the instance facts a binding depends on. Product names are marked
examples, never an instance list, and every candidate still passes the
[isolation probe](../templates/isolation-probe.md) before it binds.

## Native Windows

*Claim:* Claude Code's own sandboxing gives a native Windows surface no boundary. The per-command
sandbox runs on macOS, Linux, and WSL2 only, and the sandbox environments page gives the
whole-process runtime's setup for Linux, WSL2, and macOS only, while its row for a native Windows
host points to a container, a VM, or the Bash sandbox inside WSL2. With nothing else, the surface
is `L0`. An org-supplied Windows boundary is judged by its own probe, not by this record.
*Basis:* [Get started](https://code.claude.com/docs/en/sandboxing#get-started) and
[Platform and tool compatibility](https://code.claude.com/docs/en/sandboxing#platform-and-tool-compatibility);
[Choose an approach](https://code.claude.com/docs/en/sandbox-environments#choose-an-approach) and
[Sandbox runtime](https://code.claude.com/docs/en/sandbox-environments#sandbox-runtime); all read
as raw markdown. The [changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
through 2.1.281 adds no native Windows sandbox support. *Verified:* 2026-09-23. *Recheck trigger:*
a Claude Code changelog entry touching sandbox platform support, or a read-time fetch of those
sections that no longer matches this record.

*Claim:* settings alone never evidence `L1` on native Windows. `sandbox.enabled` and
`sandbox.failIfUnavailable` both default to `false`. With `sandbox.enabled: true` on an
unsupported platform and `failIfUnavailable` at its default, commands run unsandboxed, which is the
ladder's silent degrade whether or not a warning shows; with `failIfUnavailable: true`, Claude Code
exits at startup instead. Setup records neither case as a boundary. *Basis:*
[`sandbox.enabled`](https://code.claude.com/docs/en/settings-reference#sandbox-enabled) and
[`sandbox.failIfUnavailable`](https://code.claude.com/docs/en/settings-reference#sandbox-failifunavailable),
the sandboxing page's [Get started](https://code.claude.com/docs/en/sandboxing#get-started)
warning, read as raw markdown, and the changelog entry that added `sandbox.failIfUnavailable`.
*Verified:* 2026-09-23. *Recheck trigger:* a Claude Code changelog entry touching sandbox platform
support or `sandbox.failIfUnavailable`, or a read-time fetch of those sections that no longer
matches this record.

## WSL2 distribution

*Claim:* a bare WSL2 distribution is neither `L3` nor `L2`, whatever its virtualization. By
default WSL mounts the fixed Windows drives under `/mnt` (`C:\` at `/mnt/c/`), launches Windows
processes from the Linux side, and appends Windows path elements to `$PATH`, so the distribution
reads and writes the host file system and executes on the host. Never ratify one as `vm-microvm`;
with nothing else inside it, it is `L0`. *Basis:* Microsoft's
[wsl.conf reference](https://learn.microsoft.com/en-us/windows/wsl/wsl-config) (Automount settings
and Interop settings defaults) and
[Working across file systems](https://learn.microsoft.com/en-us/windows/wsl/filesystems), read as
their source markdown. *Verified:* 2026-09-24. *Recheck trigger:* a read-time fetch of those pages
whose `[automount]` or `[interop]` defaults no longer match this record.

*Claim:* on WSL2 the built-in sandbox uses bubblewrap as on Linux and isolates Bash subprocesses
only; file tools, MCP servers, and hooks stay on the host, and the page calls it not sufficient for
fully unattended runs. It is `L1`, whatever filters are installed. The `L2` candidates are a
whole-process wrap (the sandbox runtime, a beta research preview, which on WSL2 puts file tools,
MCP servers, and hooks inside the boundary) or a container with default-deny egress. The runtime
binds only with these limits:

- Launch it with an explicit `--settings <file>`: with that flag it refuses to start when the file
  fails to load, while a missing default `~/.srt-settings.json` starts anyway with network blocked,
  so a clean start is no proof the settings loaded.
- It builds its deny list once at launch, so a repository the session creates later (`git init`,
  `git clone`) gets no deny on its `.git/hooks` or `.git/config`. The workspace repository exists
  before launch, and anything the session created is reviewed after an unattended run.

*Basis:* [OS-level enforcement](https://code.claude.com/docs/en/sandboxing#os-level-enforcement)
and [Scope](https://code.claude.com/docs/en/sandboxing#scope);
[How isolation relates to permission modes](https://code.claude.com/docs/en/sandbox-environments#how-isolation-relates-to-permission-modes),
[Sandbox runtime](https://code.claude.com/docs/en/sandbox-environments#sandbox-runtime),
[What the runtime blocks on its own](https://code.claude.com/docs/en/sandbox-environments#what-the-runtime-blocks-on-its-own),
and [After unattended runs](https://code.claude.com/docs/en/sandbox-environments#after-unattended-runs);
all read as raw markdown. *Verified:* 2026-09-23. *Recheck trigger:* a Claude Code changelog entry
touching sandbox platform support or the sandbox runtime, or a read-time fetch of those sections
that no longer matches this record.

*Claim:* WSL hands a launch of a Windows binary, such as `cmd.exe`, `powershell.exe`, or anything
under `/mnt/c/`, to the Windows host over a Unix socket, and the sandbox's optional seccomp filter
is what blocks that socket. With the filter missing, or with `allowAllUnixSockets` set, the socket
stays open. A launch that gets through runs on the Windows host, outside every WSL2 boundary. *Basis:* the WSL2 notes under
[Set up Linux and WSL2](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2), read as
raw markdown. *Verified:* 2026-09-23. *Recheck trigger:* a Claude Code changelog entry touching WSL
interop, Unix socket blocking, or the seccomp filter, or a read-time fetch of that section that no
longer matches this record.

So every WSL2 boundary adds an interop launch check to step 3: a harmless launch by absolute path
(marked example: `/mnt/c/Windows/System32/cmd.exe /c ver`) must succeed in the outer context and
fail inside the boundary. The outer success is the control: without it, a launch that fails
because the binary is off the path or the check never ran inside the boundary would read as
blocked. Which filter is installed is not the evidence; the paired outcomes are. Record both
commands, exit codes, and outputs beside the probe transcript as review evidence in the prepared
change, not inside `assertions`. The checker does not parse them, so the reviewing human confirms
them, and a WSL2 `L2` binding with no such record, or with an inner launch that succeeded, is
unbound and blocked at step 6.

WSL2 probes also look through the Windows drive mount (the automount record above). Credential
probes and `--credential-roots` include the Windows profile paths the distribution reaches there
(marked example: an `.ssh` directory under `/mnt/c/Users/<user>/`), since hiding the
distribution's own home proves nothing about the host's. A workspace under a Windows drive mount
is checked for containment from the Windows side, where the host executes it.

## L3 microVM on a Windows host

The sandbox environments page's
[Virtual machine](https://code.claude.com/docs/en/sandbox-environments#virtual-machine) section
names Docker Sandboxes (a marked example) as a microVM that needs no Docker Desktop. Docker's pages
give it a separate kernel per sandbox (security page, Isolation layers, cited in the records
below), so its class is `vm-microvm` at `L3`.

*Claim:* each installation and workspace fact below holds for this marked example.

- It needs Windows 11 on a 64-bit Intel or AMD processor with the Windows Hypervisor Platform
  feature, which is turned on once from an elevated PowerShell prompt (a human step). The `sbx` CLI
  then installs for the current user with `winget install -h Docker.sbx`, without administrator
  rights and without Docker Desktop or Docker Engine.
- `sbx run` defaults to direct mode: the current directory is mounted read-write and changes appear
  on the host at once, which fails the containment probe. A conforming workspace is clone mode
  (`--clone`: the repository is mounted read-only and the agent edits a private clone) or a
  sandbox created with no workspace path, which has no host mount. Extra workspaces are always
  mounted directly, so each extra workspace is mounted read-only (`:ro`) or the containment probe
  fails again. Clone mode is rejected
  inside a Git worktree other than the main one; create it from the main checkout.
- The shared agent skills store is read-only by default, but `--skills` or `skills.defaultMode`
  can mount it `readwrite`, a host write outside the workspace that other sandboxes read. Require
  it absent or read-only, and record its mode in the prepared change.

*Basis:* Docker's [install page](https://docs.docker.com/ai/sandboxes/install/),
[usage page](https://docs.docker.com/ai/sandboxes/usage/#git-workspace-modes) (Choose a workspace,
Clone mode, Multiple workspaces), and
[security page](https://docs.docker.com/ai/sandboxes/security/#trust-boundaries) (Trust
boundaries, Isolation layers), read as markdown. *Verified:* 2026-09-23. *Recheck trigger:* a
read-time fetch of those pages that no longer matches this record.

*Claim:* each egress, credential, and permission fact below holds for this marked example.

- Egress is deny by default, but the default allowed domains include broad wildcards such as
  `*.googleapis.com`. List the active rules with `sbx policy ls`, remove those the run does not
  need, and choose both well-known probe targets outside every remaining allow rule, wildcards
  included.
- The host-side proxy injects API keys into request headers, so a key stored with
  `sbx secret set anthropic` never enters the VM: unreadable inside, usable through the proxy. The
  subscription path signs in with `/login` inside the sandbox, which this claim does not cover; the
  credential probe decides it.
- The default startup command is `claude --dangerously-skip-permissions`, and arguments after `--`
  that begin with a flag keep it. Bind that posture explicitly under the ladder's Permission
  posture (at `L2` and above the boundary replaces prompts); setup never records it as discovered.

*Basis:* Docker's [security page](https://docs.docker.com/ai/sandboxes/security/#security-considerations)
(Security considerations, Isolation layers) and
[Claude Code agent page](https://docs.docker.com/ai/sandboxes/agents/claude-code/#default-startup-command)
(Authentication, Default startup command), read as markdown. *Verified:* 2026-09-23. *Recheck
trigger:* a read-time fetch of those pages that no longer matches this record.

The remaining allowlist is shown in the prepared change for the human. It is not
`component_reachable_hosts`: that field lists destinations the probe must show denied, and the
security binding has no field for a base allowlist.

*Claim:* tool servers registered on its MCP gateway run on the host: a local stdio command runs as
a host process, and an OCI-packaged stdio server runs on the host with host Docker isolation, not
sandbox isolation. Either can reach host files, host network, and credentials made available to
it. They are the ladder's brokered protocol-connected tool surfaces, outside the boundary at `L3`.
Setup lists the gateway's registrations and records each local stdio server in the prepared change
as a host-executing surface; a surface with none says so.
*Basis:* Docker's [MCP gateway page](https://docs.docker.com/ai/sandboxes/mcp-gateway/#local-stdio-server)
(Register an MCP server, Local stdio server) and its security page's
[Trust boundaries](https://docs.docker.com/ai/sandboxes/security/#trust-boundaries), read as
markdown. *Verified:* 2026-09-23. *Recheck trigger:* a read-time fetch of those pages that no
longer matches this record.

## Fail-closed

A native Windows surface with no validated `L2` or `L3` binding blocks autonomous dispatch at step
6, and no setting lifts it. Setup names the compliant paths: a WSL2 distribution under the sandbox
runtime or a default-deny container, passing the probe and the interop launch check; or an `L3` VM
or microVM on the host, passing the probe in clone mode or with no workspace mount. Otherwise the
surface stays human-gated.
