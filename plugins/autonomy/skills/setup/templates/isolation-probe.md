# Isolation-probe recipes

Live-validation probe shapes the guardrail slice runs INSIDE a candidate isolation boundary
before binding it. `<...>` placeholders resolve from the detected substrate at wire time; no
org, fleet, or vendor value is baked in — substrate/tool names appear only as marked examples.
Every recipe runs the SAME three assertions the [isolation-ladder leaf](../../../reference/guardrails/isolation-ladder.md)
requires of an `L2` boundary — denied egress, absent host credentials, and contained workspace
host-writes — and all three MUST fail for the boundary to bind. A probe that any assertion PASSES
(data flowed from the origin, a credential was readable, an inner write reached the host) proves the
boundary is not `L2`; the binding does not land.

## Assertions (all substrate classes)

Three checks, run inside the boundary, all expected to FAIL:

| Assertion | Runs | Expected result |
|---|---|---|
| Denied egress | a TLS fetch of two `<well-known-external-host>` targets under different operators, plus every destination the level binding ratifies as component-reachable | no origin peer answered — NON-zero exit, and no in-boundary peer identity matching the outer context's |
| Absent host credentials | a read of `<host-credential-path>` | file absent, or read denied — NON-zero exit |
| Contained workspace host-writes | randomized canary writes into the workspace mount, re-checked on the host after teardown | every canary still absent on the host, and the VCS control-plane digest unchanged |

**Why the egress assertion tests peer identity, not reachability.** Two boundary behaviors defeat an
exit-code test, and both were observed live rather than theorized. A raw TCP `connect()` SUCCEEDS
where an interception layer accepts the SYN and then drops the session — so "connection refused" is
the wrong thing to require. And a policy block page is still a valid HTTP response, so a fetch client
can exit `0` against a fully sealed boundary. Certificate VALIDITY does not settle it either: an
organization that trusts a TLS-inspection CA inside the boundary makes an interceptor verify cleanly.
Peer IDENTITY does settle it — an interceptor cannot present the origin's own key, so an in-boundary
fingerprint that MATCHES the outer context's means the origin itself answered, which is reached
egress.

**Why the workspace assertion is proven from the outer side.** Substrates disagree about whether the
inner write should succeed: a read-only mount rejects it, a clone-mode mount accepts it and discards
it. Both are contained. Asserting on the inner exit code would grade the second one wrongly, so the
assertion constrains only what the HOST can see afterward, and the inner exit code is recorded as
evidence rather than tested.

`<well-known-external-host>` is a durable public endpoint chosen at wire time (a marked example:
a public DNS resolver's address, or a well-known example domain). `<host-credential-path>` is a
host secret location the boundary must not expose. A filesystem credential path is validated
DENY-BY-DEFAULT against the checker's `--credential-roots`: its recorded `host_expanded` value
must resolve under one of the operator-configured trusted credential roots, so probe an actual
host credential location under a root the org configures (marked examples: a home-anchored secret
file such as `$HOME/.netrc` or `$HOME/.ssh/id_rsa`, a fixed system secret path such as host SSH
keys under `/etc/ssh` or the injected `/run/secrets` credentials file). With no roots configured
the checker cannot know the org's real credential locations, so every filesystem credential entry
is untrusted and the level fails closed. A cloud metadata endpoint credential route and a
well-known credential env token (e.g. `$GITHUB_TOKEN`) are bounded closed sets that need no root.
Neither target is hardcoded in the binding — each resolves from the detected surface, and the
trusted-root values bind per the deployment's secret-binding classification.

## Egress-denial probe shape

Four properties have to hold together, because each one alone is satisfiable by a boundary that is
not `L2`.

**The client must be shown to run.** A boundary with no working fetch tool denies nothing, yet a
missing tool is indistinguishable from a sealed network by exit code alone — so the emptiest possible
boundary would otherwise score best. Prove the client runs before believing anything it reports.

**At least two targets, under different operators.** One denied destination is fully consistent with
a policy that allows others; a component installed on top of a global deny-all can add its own allow
rule.

**Each target must be reachable from the OUTER context first.** A target that fails everywhere — an
unregistered name, a dead host — "fails" inside too and proves nothing. This is why the targets are
well-known hosts rather than unguessable ones: unguessability and outer-reachability cannot both hold
over DNS, and outer-reachability is what makes the inner failure mean something.

**Every destination the level binding ratifies as component-reachable must be among the targets.**
Two targets under different operators sample only what the BASE policy denies. Where the surface
carries an additive policy layer, the destinations its installed components request are the exact
places the boundary may already have been widened, so a probe drawn from anywhere else certifies a
boundary open at the one place it never looked. Which destinations those are is an outer-world fact
no capture can establish, so the set is HUMAN-RATIFIED on the level binding's
`component_reachable_hosts` — the agent-unwritable surface `substrate_class` already sits on — and
the probe covers it in FULL, since covering one ratified destination says nothing about the rest.
An empty ratified list is the explicit claim that this surface installs nothing carrying policy
rules of its own; an ABSENT one leaves the level unproven, fail-closed. Ratify only destinations
the outer context can itself reach: a component-reachable destination on a private or internal
network fails the outer-reachability property above and is outside what this probe settles. Probe
in the configuration the run will ACTUALLY use, those components installed.

What this settles and what it does not. A transcript can prove that the probe covered every
destination the human ratified, and the egress assertion then proves each one was denied. It cannot
prove the ratified set is COMPLETE — a component requesting a destination nobody ratified is
invisible to every capture — and it cannot prove the probe ran with those components installed at
all. The first is where the human takes responsibility by ratifying on the agent-unwritable surface;
nothing takes responsibility for the second, and a component-reachable destination on a private or
internal network is outside the probe's reach entirely, since a non-external target cannot evidence
external egress denial. These are RECORDED, not implied.

```sh
# readiness (inside the boundary): the client itself must work — record as client_ready
<fetch-command> <in-boundary-endpoint> ; test $? -eq 0 || fail "the probe client does not run inside the boundary — an absent client would satisfy every egress assertion trivially"
# probe (outer context), per target: must be reachable — record exit as outer_exit_code and the
# peer certificate fingerprint as outer_peer_fingerprint
<fetch-command> <well-known-external-host> ; test $? -eq 0 || fail "cannot reach <well-known-external-host> from the outer context — an unreachable target cannot evidence a boundary"
<peer-fingerprint-command> <well-known-external-host>
# probe (inside the boundary), per target. Run the client in fail-on-HTTP-error mode so a policy
# block page is not counted as a successful transfer — but do NOT stop on a zero exit, because a
# block page carrying a SUCCESSFUL status also exits 0 and that boundary is sealed. The exit is
# evidence; the peer identity is the verdict.
<fetch-command> --fail-on-http-error <well-known-external-host> ; record exit as exit_code
<peer-fingerprint-command> <well-known-external-host>   # record as inner_peer_fingerprint, or "none"
# the verdict, evaluated for every target regardless of exit code
test "<inner_peer_fingerprint>" != "<outer_peer_fingerprint>" || fail "the origin's own peer identity answered inside the boundary — this is reached egress, not interception"
```

A zero exit is therefore accepted ONLY where that target's `transport_outcome` is `peer-substituted`
and its two fingerprints differ. Everywhere else a non-zero exit is still required, so the exception
cannot be claimed to excuse a target that simply succeeded.

**Two capture requirements, both learned from a boundary that defeated the naive form.**

`<peer-fingerprint-command>` MUST be proxy-aware — it has to obtain the certificate through whatever
path the boundary routes traffic over. A direct-TLS tool cannot traverse an HTTP `CONNECT` proxy and
reports NO peer at all, identically for a sealed boundary and a wide-open one, so an unaware capture
silently records "no peer" and proves nothing. Use the fetch client's own certificate output, since
it is the component that already speaks the boundary's egress path.

Certificate VALIDITY must not be substituted for the comparison. On a measured boundary the
interception layer presented a certificate carrying the CORRECT hostname, signed by a CA the boundary
trusted: hostname matching passed and verification returned success, so a verification-based test
graded a fully sealed boundary as reached egress. Only the peer's IDENTITY — its fingerprint, differing
from the outer context's — distinguished the two.

Record HOW each target was denied as `transport_outcome`, one entry per target:
`dns-unresolved` · `connect-failed` · `tls-failed` · `peer-substituted`. There is deliberately no
token for a completed handshake with the origin's own identity, because that is egress and cannot be
recorded as a pass. `outer_peer_fingerprint` and `inner_peer_fingerprint` are required for a
`peer-substituted` target (the comparison IS the proof) and are the literal `none` elsewhere.

Record the address families exercised as `address_families` (`ipv4` · `ipv6`). A boundary sealed on
one family and open on the other passes an unrecorded probe, so the families are recorded rather than
inferred, and an unexercised family is never counted as denied.

`<fetch-command>` is the substrate's available client (marked example: an HTTP client CLI with a
short connect timeout so a denied boundary fails fast rather than hanging).

## Credential-absence probe shape

Expand any home env var token in `<host-credential-path>` OUTSIDE the boundary first — inside,
`$HOME` is the boundary's OWN home, not the host's — and pass the concrete result in as a
literal argument, recording it as `host_expanded` (a fixed system path, metadata endpoint, or
whole-entry token needs no expansion and is recorded verbatim). Then run INSIDE the boundary;
assert the credential is absent or unreadable:

```sh
# expand on the host side; the boundary receives only the literal expanded path
<host-expanded-path>=<outer-shell expansion of <host-credential-path>>
# probe (outer context): the target must exist on the host — record this exit as outer_exit_code
<outer-existence-check> <host-expanded-path> ; test $? -eq 0 || fail "no such credential target on the host — an absent target cannot evidence a boundary"
# probe: host credential path must be absent or denied inside the boundary
<read-command> <host-expanded-path> ; test $? -ne 0 || fail "read <host-expanded-path> — host credentials leaked into the boundary"
```

`<outer-existence-check>` is the deliberate credential-side parallel of the egress probe's outer
reachability step: without it, a fixed path like `/root/.ssh` names the boundary's OWN (empty)
root and its failing inner read proves nothing. Per entry kind it is a readability test on the
expanded path (readability only, never content), an is-set-and-non-empty test for a whole-entry
env token, or a service-reachability check for a metadata endpoint.

For a metadata endpoint the assertion is connection-level: the probe must fail to CONNECT
(refused, timeout, no route — use a short connect timeout), not merely receive an HTTP error,
which a fully reachable service returns for an incomplete request (a missing required header, a
wrong api-version). Record HOW each probe failed as `transport_outcome`: `connect-failed` for a
metadata endpoint, `read-denied` for a file or env-token read.

## Workspace host-write containment probe shape

The ladder's levels describe the PROCESS boundary. The workspace mount is a deliberate hole through
it, and nothing else in this recipe measures it — a substrate can fail both other assertions cleanly
while the agent still writes files the HOST later executes. `.git/config` is the documented instance:
it is a command key ring, and `core.fsmonitor` executes host code on a read-only-looking `git status`.

Snapshot the host first, write randomized canaries from inside, tear the boundary down, then re-check
the host:

```sh
# outer, pre: every canary must be ABSENT on the host first — record each exit as host_pre_absent
<outer-absence-check> <workspace-host-path>/<canary> ; test $? -eq 0 || fail "canary already present on the host — its later absence would prove nothing"
<digest-command> <workspace-host-path>/.git/config    # record as git_config_digest_pre, or the literal "absent"
# inner: write each canary, and append to the VCS control plane — record inner_exit_code, do NOT assert on it
<write-command> <workspace-mount>/<canary>
<append-command> <workspace-mount>/.git/config
# TEAR THE BOUNDARY DOWN, then re-check the host
<outer-absence-check> <workspace-host-path>/<canary> ; test $? -eq 0 || fail "an inner write reached the host workspace — the mount carries host-executing writes"
<digest-command> <workspace-host-path>/.git/config    # record as git_config_digest_post; must EQUAL pre
```

`<canary>` names are RANDOMIZED per run and span at least three shapes — an ordinary file, a dotfile,
and a `.git/`-relative path. Randomization defeats a substrate that special-cases a known probe path;
the shape set covers hidden-file handling and the control plane that a single literal path would miss.
Canonicalize both sides before comparing, so a case-folding or path-normalizing host filesystem
cannot hide a landed write behind a differently-spelled name.

The re-check runs AFTER teardown (`checked_after_teardown`), never immediately: a caching or
asynchronously-flushed mount can propagate the write after an in-flight check has already looked.

Where the host workspace path is not observable from the outer context — a hosted ephemeral executor
whose storage the operator cannot inspect — record `outcome: "not-applicable"`. That leaves the level
UNPROVEN. It is deliberately not a pass: a boundary nobody could observe is not a boundary anybody
verified.

**Scope, stated because the assertion's name has to earn it.** This proves host-WRITE containment
only. It does not measure READ exposure, and a clone-mode workspace leaves reads fully open — so
exfiltration of workspace contents is unaffected by a passing result.

## Per-substrate-class wrapping

The three assertions are constant; only the wrapper that launches them inside the boundary changes
per substrate class. Each wrapper passes NO host environment and NO host secrets into the
boundary, and each keeps the OUTER context normally networked so a passing assertion means the
inner boundary — not a broken outer environment — denied egress.

- **Container** (`L2`; marked example: an OCI runtime): launch the assertions in a container run
  with egress default-denied (network mode `none` or an internal-only network) and no host env or
  secret mounts — `<container-runtime> run --network none <image> <probe-script>`.
- **OS-sandbox wrap** (`L2`; marked example: a whole-process OS sandbox profile): launch the
  assertions under the sandbox profile that denies egress and blocks host credential paths —
  `<sandbox-wrapper> <profile> <probe-script>`.
- **VM / microVM** (`L3`; marked example: a microVM): boot the ephemeral guest with no egress
  route and no injected host credentials, then run the assertions in the guest —
  `<vm-launcher> <ephemeral-guest> <probe-script>`.
- **Hosted ephemeral executor** (`L3`; marked example: a hosted ephemeral executor surface per
  the isolation-ladder leaf): the platform boots a fresh kernel-separated guest per run; launch
  the run with no egress route and no injected host credentials, then run the assertions in it —
  `<hosted-run-launcher> <probe-script>`.

## Transcript capture shape

Capture the run as the `probe_evidence` the level binding records — enough for a reviewer to
confirm all three assertions failed inside a boundary the run itself created:

```json
{
  "schema_version": "1",
  "surface": "<execution-surface-id>",
  "level": "<L2|L3>",
  "substrate": "<substrate-instance-id>",
  "substrate_class": "<container|os-sandbox|vm-microvm|hosted-ephemeral-executor>",
  "probed_at": "<iso-8601>",
  "assertions": {
    "egress_denied": { "host": "<well-known-external-host>,<second-target-different-operator>", "exit_code": "<non-zero>,<non-zero>", "outer_exit_code": "0,0", "transport_outcome": "<dns-unresolved|connect-failed|tls-failed|peer-substituted>,<...>", "outer_peer_fingerprint": "<fingerprint|none>,<...>", "inner_peer_fingerprint": "<fingerprint|none>,<...>", "client_ready": "0", "address_families": "<ipv4|ipv6>,<...>", "outcome": "denied" },
    "credentials_absent": { "path": "<host-credential-path>", "host_expanded": "<host-expanded-path>", "exit_code": "<non-zero>", "outer_exit_code": "0", "transport_outcome": "<read-denied|connect-failed>", "outcome": "absent-or-denied" },
    "workspace_host_write_contained": { "workspace_host_path": "<workspace-host-path>", "canaries": "<randomized-file>,<randomized-dotfile>,.git/<randomized>", "inner_exit_code": "<any>,<any>,<any>", "host_pre_absent": "0,0,0", "host_post_absent": "0,0,0", "git_config_digest_pre": "<digest|absent>", "git_config_digest_post": "<digest|absent>", "checked_after_teardown": true, "outcome": "contained" }
  },
  "outer_context_networked": true
}
```

When one run probes several `<host-credential-path>` locations, `credentials_absent.path` lists
them comma-separated and `host_expanded`, `exit_code`, `outer_exit_code`, and
`transport_outcome` list one entry per location, comma-separated in the same order — a single
code cannot vouch for every listed location. Several egress targets work the same way:
`egress_denied.host` lists them comma-separated, `exit_code` pairs one non-zero code per target,
and `outer_exit_code` pairs the same way and must be all-`"0"` — the outer context reached the
very target the inner probe failed against.
`credentials_absent.outer_exit_code` is its credential-side mirror, also all-`"0"`: the outer
context proved the very target the inner read failed against exists on the host.

The captured transcript is referenced from the level binding's `probe_evidence` field; the
security-binding check treats a level binding without it as invalid. The level binding also
records its own `substrate_class` — the HUMAN-RATIFIED class assertion the eligibility decision
keys off, living on the agent-unwritable surface — and the transcript's recorded
`substrate_class` must EQUAL it: the transcript's value is capture evidence, so a mismatch means
the capture proves a different substrate than the one ratified. A transcript whose
`outer_context_networked` is false does not prove the boundary — a fully-offline outer context
would deny egress on its own — so the recipe keeps the outer context networked and only the inner
boundary sealed.
