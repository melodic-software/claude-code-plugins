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
host secret location the boundary must not expose, and must name a real host location by
construction — a home env var token (e.g. `$HOME/...`) or a fixed system path (`/root`, `/etc`,
`/run/secrets`), with org-specific mounts routed through configuration (marked examples: a cloud
metadata endpoint, a credentials file under the host home, an injected token env var). Neither is
hardcoded in the binding — each resolves from the detected surface.

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
# probe: host credential path must be absent or denied inside the boundary
<read-command> <host-expanded-path> ; test $? -ne 0 || fail "read <host-expanded-path> — host credentials leaked into the boundary"
```

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
- **VM / microVM** (`L3`; marked example: a microVM or hosted ephemeral executor): boot the
  ephemeral guest with no egress route and no injected host credentials, then run the assertions
  in the guest — `<vm-launcher> <ephemeral-guest> <probe-script>`.

## Transcript capture shape

Capture the run as the `probe_evidence` the level binding records — enough for a reviewer to
confirm both assertions failed inside a boundary the run itself created:

```json
{
  "schema_version": "1",
  "surface": "<execution-surface-id>",
  "level": "<L2|L3>",
  "substrate": "<substrate-instance-id>",
  "substrate_class": "<container|os-sandbox|vm-microvm>",
  "probed_at": "<iso-8601>",
  "assertions": {
    "egress_denied": { "host": "<well-known-external-host>", "exit_code": "<non-zero>", "outer_exit_code": "0", "outcome": "denied" },
    "credentials_absent": { "path": "<host-credential-path>", "host_expanded": "<host-expanded-path>", "exit_code": "<non-zero>", "outcome": "absent-or-denied" }
  },
  "outer_context_networked": true
}
```

When one run probes several `<host-credential-path>` locations, `credentials_absent.path` lists
them comma-separated and `host_expanded` and `exit_code` list one entry per location,
comma-separated in the same order — a single code cannot vouch for every listed location. The
`egress_denied.outer_exit_code` pairs with the probed host the same way and must be `"0"`: the
outer context reached the very target the inner probe failed against.

The captured transcript is referenced from the level binding's `probe_evidence` field; the
security-binding check treats a level binding without it as invalid. A transcript whose
`outer_context_networked` is false does not prove the boundary — a fully-offline outer context
would deny egress on its own — so the recipe keeps the outer context networked and only the inner
boundary sealed.
