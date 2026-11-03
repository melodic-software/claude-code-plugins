# 3.0.05 Push-channel primary path (local CLI sessions, optional)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there.

**Preferred over [§3.0.1](monitor-auto-watch.md) Monitor watch, when your environment provides it.** Some environments ship a GitHub-events push channel: an MCP server paired with a webhook forwarder (e.g. the `cli/gh-webhook` gh extension) that delivers `check_run` / `workflow_run` / `pull_request*` / `issue_comment` events into the active session, with zero idle polling and ~0 request cost between events.

**Activation gate. Verify, never assume:**

1. Confirm the channel's MCP server is registered in this session (its status tool responds).
2. Verify its delivery pipeline is healthy per the channel's own docs (broker/forwarder process alive, subscriber connected to the LIVE broker. A stale subscriber whose connection looks "open" against a dead or replaced broker looks healthy without a cross-check; when the channel exposes a broker address, cross-check it against the live process before trusting it).
3. Arm the channel's PR filter for `<N>` so events scope to the monitored PR.

**If all checks pass → channel mode active:**

- Skip §3.0.1 Monitor-watch arming entirely
- Process channel event arrivals per [§3.1](monitor-ci-loop.md) (each event triggers a single iteration; zero polling between events)
- Continue to honor [§3.0.5](monitor-self-termination.md) loop-aware self-termination. Channel mode does not change merge gating

**If the environment has no such channel, or any check fails and can't be remediated → fall through to §3.0.1 Monitor watch** with a one-line note: `Push notifications unavailable — using Monitor tool (60s poll).`
