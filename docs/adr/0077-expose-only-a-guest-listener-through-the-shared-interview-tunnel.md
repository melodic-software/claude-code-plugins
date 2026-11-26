# Expose only a guest listener through the shared interview tunnel

- Status: accepted
- Date: 2026-10-16
- Related: [ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md) (vendored
  `lib/session-bridge` copies), [ADR 0076](0076-keep-guest-use-of-claude-the-owners-own-use.md)
  (what guests may ask Claude to do). The routes and auth classes are in
  `plugins/planning/shared/README.md`.

## Context

The `/planning:interview` shared session serves one page to several people from the owner's
machine. Guests on other networks reach it through a Cloudflare quick tunnel, which this design
points at one local address, as the docs' command does (`cloudflared tunnel --url <address>`). The
owner's Claude session must also reach the same server: it
reads the round people send (`/api/wait`), writes the next round and results (`/api/ops`) and holds
the watcher lease. Those control routes come from `lib/session-bridge`, whose `LoopbackHandler`
assumes a loopback-only caller holding one per-run token. Four other plugins carry generated copies
of that library.

Whatever the tunnel targets is on the public internet. A guest is anyone with the link.

## Decision

1. **One server process, two listeners, both bound to 127.0.0.1.** The guest listener has its own
   handler and carries only the guest routes (the page, `/api/state`, joins, answers, votes,
   requests, uploads). The control listener is `session_bridge.LoopbackHandler` unchanged, with
   token header `X-Shared-Token`.
2. **The tunnel targets the guest listener only.** The control listener is never tunneled. Only
   `share.sh`, `watch.sh` and `wake.sh` on the owner's machine call it, with the token from 0600
   files in the session's data folder.
3. **The guest listener checks `Host`** against loopback and the current tunnel host, and `Origin`
   when sent, so a rebinding page cannot reach it under another name.
4. **Guest identity is a server-issued secret** sent in a header, never a client-chosen id; the
   owner's actions need the owner token. Neither travels in a URL query or body.

## Alternatives considered

- **Open the session-bridge listener to the tunnel host.** Rejected: `/api/ops` and `/api/wait`
  would sit on the public internet behind one token, so a leaked token, a route added later to
  the library, or a bug in its token check would hand a stranger the owner's write path into the
  session. It would also mean changing `lib/session-bridge` and every carrier of its copies for one
  app's needs.
- **Two server processes, one per listener.** Not adopted: the domain state lives in memory under
  one lock, and two processes would need a second synchronization channel for no security gain
  over two listeners in one process.
- **No tunnel (local network only).** Dropped at design: guests join from other networks, and a
  no-tunnel mode was removed from scope.

## Consequences

- The skill text and the scripts name `share.sh` and the watcher's lines, never a port: the control
  port is an implementation detail on loopback.
- A new guest feature adds a route to the guest handler and its auth class; it never adds a route
  to the control listener without a new decision.
- `lib/session-bridge` stays unchanged, so its copies stay in sync without a version bump.
- Replacing the tunnel provider (a stable link, a hosted transport) replaces `tunnel.py`; the
  two-listener boundary holds for any provider that forwards one address to one port.

Upstream: [Cloudflare quick tunnels: Create a Quick Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/#create-a-quick-tunnel)
shows the command taking one `--url` and says anyone with the resulting URL can reach the local
service. As of 2026-10-16. Recheck when that section changes.
