# Isolation-probe recipes

Live-validation probe shapes the guardrail slice runs INSIDE a candidate isolation boundary
before binding it. `<...>` placeholders resolve from the detected substrate at wire time; no
org, fleet, or vendor value is baked in — substrate/tool names appear only as marked examples.
Every recipe runs the SAME two assertions the [isolation-ladder leaf](../../../reference/guardrails/isolation-ladder.md)
requires of an `L2` boundary — denied egress and absent host credentials — and both MUST fail
for the boundary to bind. A probe that any assertion PASSES (egress succeeded, a credential was
readable) proves the boundary is not `L2`; the binding does not land.

## Assertions (all substrate classes)

Two checks, run inside the boundary, both expected to FAIL:

| Assertion | Runs | Expected result |
|---|---|---|
| Denied egress | a network fetch to `<well-known-external-host>` | connection/DNS refused or timed out — NON-zero exit |
| Absent host credentials | a read of `<host-credential-path>` | file absent, or read denied — NON-zero exit |

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

First prove the target reachable from the OUTER context (a target that fails everywhere — an
unregistered name, a dead host — "fails" inside too and proves nothing), then run the same fetch
INSIDE the boundary and assert non-zero exit:

```sh
# probe (outer context): the target must be reachable — record this exit as outer_exit_code
<fetch-command> <well-known-external-host> ; test $? -eq 0 || fail "cannot reach <well-known-external-host> from the outer context — an unreachable target cannot evidence a boundary"
# probe (inside the boundary): egress must be denied
<fetch-command> <well-known-external-host> ; test $? -ne 0 || fail "egress reached <well-known-external-host> — boundary is not L2"
```

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

## Per-substrate-class wrapping

The two assertions are constant; only the wrapper that launches them inside the boundary changes
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
confirm both assertions failed inside a boundary the run itself created:

```json
{
  "schema_version": "1",
  "surface": "<execution-surface-id>",
  "level": "<L2|L3>",
  "substrate": "<substrate-instance-id>",
  "substrate_class": "<container|os-sandbox|vm-microvm|hosted-ephemeral-executor>",
  "probed_at": "<iso-8601>",
  "assertions": {
    "egress_denied": { "host": "<well-known-external-host>", "exit_code": "<non-zero>", "outer_exit_code": "0", "outcome": "denied" },
    "credentials_absent": { "path": "<host-credential-path>", "host_expanded": "<host-expanded-path>", "exit_code": "<non-zero>", "outer_exit_code": "0", "transport_outcome": "<read-denied|connect-failed>", "outcome": "absent-or-denied" }
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
