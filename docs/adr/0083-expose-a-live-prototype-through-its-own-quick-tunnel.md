# Expose a live prototype through its own quick tunnel

- Status: accepted
- Date: 2026-10-22
- Related: [ADR 0077](0077-expose-only-a-guest-listener-through-the-shared-interview-tunnel.md)
  (the session tunnel reaches the guest listener only; the control listener is never tunneled).
  The live tier's routes and records are in `plugins/planning/shared/README.md`.

## Context

A shared interview can ask guests to click through a running prototype. That prototype is a
server on the owner's machine, and its scripts are written by a model. The interview page keeps its
identities in its origin's browser storage: the owner token in `sessionStorage`, a signed-in
owner device in `localStorage`, a guest's secret sent from the same origin. OWASP warns that "A
single Cross Site Scripting can be used to steal all the data in these objects" and that "every
object is shared within an origin". So a prototype's script must never run in the interview's
origin.

ADR 0077 gives the session one public address: one quick tunnel to the guest listener. Serving a
prototype under a path on that address would put its scripts in the interview's origin, and would
add a forwarding route to the guest listener's boundary.

## Decision

1. **Each live prototype gets its own quick tunnel and so its own public origin.** It does not
   share the session tunnel. `trycloudflare.com` is on the Public Suffix List, so each quick-tunnel
   host is a site of its own. Its storage and cookies are apart from the interview's and from every
   other prototype's. `tunnel.py` stays the only file that runs cloudflared. Each live prototype
   has its own record at `.shared-live/<id>.json` (0600). The session tunnel's record and its
   functions are unchanged. A live link's origin must be a quick tunnel's: https, one label under
   `trycloudflare.com`, no port and no IP literal (`session.LIVE_URL`). The tunnel's address can
   change on a restart; the new one replaces the old without a new Approve, since approval covers
   the prototype, not the hostname.
2. **The default is a static build served by the plugin.** `add-live` takes a folder under the data
   folder's `staging/`. It refuses a folder that holds a link, a junction, a hard link (its other
   name could be a file outside the folder), a hidden name or a special file, or that passes the
   size cap. On the owner's Approve, the server copies that folder
   into `live/<id>/` with the same rules. `liveserve.py` then serves only the copy, so the served
   root never sits beside the session's secrets. It is one stdlib process bound to 127.0.0.1 and
   answers GET and HEAD only, 405 otherwise. It lists no folder and serves no dotfile. A path that
   resolves, links included, outside the copy answers 404. Every answer carries
   `Content-Security-Policy: default-src 'self'; connect-src 'self'; form-action 'self';
   frame-ancestors 'none'; base-uri 'none'`, `Referrer-Policy: no-referrer` and
   `Cross-Origin-Opener-Policy: same-origin`.
3. **A port target is refused when it is the session's own guest or control port, or when it
   answers the session-bridge ping as a control listener does.** This keeps another session's
   control listener from being tunneled, which extends ADR 0077 Decision 2 to every session on the
   machine. The check runs on every start and restart, since a port can change hands. The watch also
   ends the entry once nothing listens on the port, so a later server there never inherits the
   public address without a new Approve. A server the
   owner runs needs the owner's attestation on Approve: sample data only, writes stubbed, no
   credentials in its environment. The plugin tunnels that server but never starts or stops it.
4. **Lifecycle.** A live prototype runs only while its entry runs. The server restarts an exited
   tunnel or static server once a second, with backoff, and ends the entry after five failures in
   a row. These end it and both its processes:
   - the owner's Stop;
   - turning the live tier off;
   - ending the session;
   - `share.sh stop`;
   - `share.sh live-stop <id>`.

   `ensure-running` and server shutdown sweep the records. A record whose processes are gone, or
   that belongs to an ended session, ends.

## Alternatives considered

- **A path on the session tunnel.** Rejected: it puts the prototype's scripts in the origin that
  holds the owner token. It also adds a forwarding route to the guest listener, and root-relative
  URLs break under a path prefix.
- **A named-tunnel hostname per prototype.** Rejected: it needs a Cloudflare API credential at run
  time, and its configuration call replaces the owner's whole tunnel configuration. It also gives
  the prototype the same site as the interview host.
- **One gateway tunnel for all of a session's prototypes.** Rejected: the prototypes would share
  one origin with each other, and the path-prefix breakage remains.
- **Tunnel any local dev server by default.** Rejected as the default: a tunnel to a dev server
  publishes its whole file-serving surface. GHSA-4r4m-qw57-chr8 is a Vite `server.fs.deny` bypass
  whose stated precondition is "apps explicitly exposing the Vite dev server to the network". A
  quick tunnel to 127.0.0.1 gives the same reach (judgment). A port target stays as the owner's
  attested opt-in.

## Consequences

- Each running live prototype is one more public address on the owner's machine, and "Anyone with
  the URL can access your local service". The URL reaches guests only after the owner's Approve
  (`/api/state` filtering) and leaves every view once the entry ends.
- CSP limits what a prototype's page fetches, submits and frames, not where it navigates itself, so
  a model-written page could still send what a guest types to another site. Sample data only, by
  construction for the static default and by attestation for a port, is the control for that.
- A server swapped on the port within one watch pass (one second) is not caught; the attestation
  covers that window.
- Quick tunnels carry Cloudflare's limits: "Each Quick Tunnel supports up to 200 in-flight
  requests", "Quick Tunnels do not support Server-Sent Events (SSE)", and they "have no uptime
  guarantee". A prototype whose dev tooling relies on SSE breaks behind one.
- The quick-tunnel page does not say whether several quick tunnels may run on one machine at once.
  That, and whether the installed cloudflared accepts `--http-host-header` for a dev server that
  checks `Host`, are left to a manual check on the owner's machine; this build does not pass the
  flag.
- On Windows a stop kills a pid only. The static server is one Python process, so that is enough.
  The plugin never manages an owner's dev server, whose process tree a pid kill would not end.

Upstream, each read 2026-10-22; recheck when the page changes the quoted text:

- [Public Suffix List](https://publicsuffix.org/list/public_suffix_list.dat): `trycloudflare.com`
  at line 12762.
- [Cloudflare Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/):
  the command, "Anyone with the URL can access your local service", and the limits quoted above.
- [OWASP HTML5 Security Cheat Sheet, Local Storage](https://cheatsheetseries.owasp.org/cheatsheets/HTML5_Security_Cheat_Sheet.html#local-storage).
- [GHSA-4r4m-qw57-chr8](https://osv.dev/vulnerability/GHSA-4r4m-qw57-chr8), published 2025-03-31.
