# Container substrate for local lanes: `L2` study

The guardrail slice reads this file at step 1 (detect) when the candidate `L2`
substrate on a local surface is a container. The
[isolation-ladder leaf](../../../reference/guardrails/isolation-ladder.md) owns the levels and the
[isolation probe](../templates/isolation-probe.md) owns the checks; this file records how a
container meets or misses each `L2` clause and what any container picked must pass first. Product
names are marked examples, never an instance list. Rows of the
[sandcastle upstream record](../../../../../docs/upstream/mattpocock-sandcastle.md) feed the
acceptance list below.

**Outcome.** The container class can reach `L2` for a local lane. The reference dev container
(marked example: the one in the `anthropics/claude-code` repository) does not as shipped: it fails
four clauses, listed below. No instance is picked here. Choosing one, and whether the containment
probe may accept protected git overlays in place of a copied workspace, are owner decisions; until
then a local lane runs unattended only on a path the owner exemption in the
[ladder's Local lanes section](../../../reference/guardrails/isolation-ladder.md#local-lanes) covers.
**As of:** 2026-11-20. **Recheck when:** a source this file cites changes a fact a row rests
on, or an instance is picked.

## The reference dev container against `L2`

*Claim:* its firewall sets `INPUT`, `OUTPUT` and `FORWARD` to `DROP`, then allows seven named
domains, GitHub's `web`, `api` and `git` address ranges from `api.github.com/meta`, outbound UDP
port 53 and TCP port 22 to any destination, and both directions to the default route's `/24`. Its
self-check requires `example.com` to fail and `api.github.com` to answer. Running it needs the
`NET_ADMIN` and `NET_RAW` capabilities. *Basis:* the
[dev container page](https://code.claude.com/docs/en/devcontainer#restrict-network-egress) and the
reference [`init-firewall.sh`](https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh)
and [`devcontainer.json`](https://github.com/anthropics/claude-code/blob/main/.devcontainer/devcontainer.json).
*Recheck trigger:* a change to that script's rules or self-check.

*Claim:* the workspace is a read-write bind mount of the host folder, Claude Code's credentials
live in `~/.claude` inside the container, and with permissions skipped the container does not stop
a malicious project exfiltrating anything reachable inside it, those credentials included. The
image installs the latest Claude Code unless a build argument pins it, and the `node` user may run
only the firewall script through `sudo`. *Basis:* the dev container page's opening warning and
[Run without permission prompts](https://code.claude.com/docs/en/devcontainer#run-without-permission-prompts),
the reference `devcontainer.json` (`workspaceMount`) and
[`Dockerfile`](https://github.com/anthropics/claude-code/blob/main/.devcontainer/Dockerfile).
*Recheck trigger:* a change to that page's warning or the reference files' mounts or `sudoers` line.

Measured against the `L2` clauses:

| `L2` clause | Reference container | Gap |
|---|---|---|
| Default-deny egress | Default `DROP`, allowlist | TCP 22 and UDP 53 to any host, and the host `/24`, are egress past the deny. The probe's fetch to two well-known hosts is denied while they stay open. |
| Credential protection | No host secret mounted by default | The lane's own tokens sit inside the boundary, readable by the run. The probe's credential check reads host paths, the metadata route and well-known env token names; a token under another name or in `~/.claude` is outside it. |
| Contained workspace host-writes | Read-write bind of the host folder | Every canary reaches the host, `.git/config` included. Fails the probe. |
| Nothing the run installs may widen policy | `sudo` limited to the firewall script | `.devcontainer/` sits in the checkout the lane writes, so a lane can change the next launch's image, capabilities and firewall. |

## What any container picked must pass

Each row is an acceptance test for the candidate, run in addition to the probe.

1. **Egress closed past the allowlist.** No rule admits a port or destination outside the named
   hosts: DNS only to the container's own resolver, no open port 22, no host subnet. Record each
   range the allowlist keeps, GitHub's included, as `base_egress_allowlist`, and choose both probe
   targets outside it. Docker's [`none` network driver](https://docs.docker.com/engine/network/drivers/none/)
   (a marked example) creates only a loopback device, so a container on it has no network route.
2. **Workspace off the host.** The run edits a copy inside the container (a clone into a volume
   created for the run) and its result leaves by push or patch, so the probe's canaries stay off
   the host. A read-write bind of the checkout fails the probe whatever else is protected.
3. **Git control files read-only where a bind remains.** The sandcastle `protectGitMounts.ts` row:
   the repository's `config`, `hooks` and `info`, a linked worktree's `.git` pointer and its
   `commondir` are mounted read-only wherever they are visible, and each directory between them
   and the writable mount is bound onto itself so renaming a parent cannot move them aside. Test
   the overlays and the parent binds on our own mounts. This protects the files git executes on the host, not the rest of
   the workspace, so it does not pass the probe's ordinary-file canary; accepting it in place of
   row 2 changes the probe and is the owner's call.
4. **Container definition from a store the lane cannot edit.** Build the image and its run flags
   from the default branch or a governance home, never the lane's working tree. The loop-lane
   convention records "config re-read each run from a store the lane cannot edit" as not met for
   local lanes; the container definition is one more such config.
5. **Lane credentials short-lived and scoped.** Pass repository-scoped tokens with a short expiry
   as environment, never a mounted host credential file, as the dev container page advises. A
   token under an env name the probe's credential check reads fails that assertion, and the probe
   has no allowance for a lane's own scoped token: whether it gets one is open for the owner.
6. **Pinned Claude Code.** Pin the version at build and turn auto-update off, so the probe result
   describes the binary that runs. The dev container page's
   [Enforce organization policy](https://code.claude.com/docs/en/devcontainer#enforce-organization-policy)
   gives both steps.
7. **Exec status read from inside.** The sandcastle engine-exit-status row: when the launcher runs
   the lane through the engine's exec, a missing status line or code counts as a failure, never a
   pass.
8. **Resource caps, recorded not gated.** The sandcastle memory-and-process row: a memory limit
   with `--memory-swap` equal to it gives the container no swap
   ([resource constraints](https://docs.docker.com/engine/containers/resource_constraints/#--memory-swap-details)),
   and `--pids-limit` caps processes
   ([`docker container run`](https://docs.docker.com/reference/cli/docker/container/run/)). `L2`
   names no resource limit, so these go in the prepared change, not the gate.

On a WSL2 host the container also runs the interop launch check in
[`windows-surfaces.md`](windows-surfaces.md).

## Rows that stay as recorded

The sandcastle native-provider row (a process sandbox, not a container) and the cloud-provider
row keep their `reject` and their own recheck triggers. Picking an `L2` substrate is the recheck
trigger the engine-exit-status, resource-cap and `protectGitMounts.ts` rows name.

## Sources read

- [Development containers](https://code.claude.com/docs/en/devcontainer): the reference
  container's firewall, capabilities, workspace bind, credential warning and policy delivery.
- [Choose a sandbox environment](https://code.claude.com/docs/en/sandbox-environments#dev-containers):
  a dev container with a default-deny firewall supports unattended runs; a custom container's
  checklist is writable mounts, reachable credentials and egress policy.
- The reference `init-firewall.sh`, `devcontainer.json` and `Dockerfile` in `anthropics/claude-code`
  at `main`.
- Sandcastle at the pinned commit:
  [`src/protectGitMounts.ts`](https://github.com/mattpocock/sandcastle/blob/0ed674e5195b200d34bc4128eec33409f2952dcf/src/protectGitMounts.ts)
  (the read-only control files and parent binds) and
  [`src/sandboxes/docker.ts`](https://github.com/mattpocock/sandcastle/blob/0ed674e5195b200d34bc4128eec33409f2952dcf/src/sandboxes/docker.ts)
  (the default bridge network when none is set, the memory and process options).
- Docker's [`none` driver](https://docs.docker.com/engine/network/drivers/none/),
  [resource constraints](https://docs.docker.com/engine/containers/resource_constraints/) and
  [`docker container run`](https://docs.docker.com/reference/cli/docker/container/run/) pages.
