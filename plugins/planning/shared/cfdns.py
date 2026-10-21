"""Cloudflare checks for the shared session's named tunnel, run by the owner by hand. Python 3 stdlib.

  python cfdns.py plan  --zone-id Z --hostname H --tunnel-id T
  python cfdns.py write --zone-id Z --hostname H --tunnel-id T --confirm H
  python cfdns.py connectors --account-id A --tunnel-id T

`plan` lists the zone's DNS records (read only) and prints the one record the tunnel needs, a proxied
CNAME from H to <T>.cfargotunnel.com, with every record already named H: none means no clash.
`write` lists again and creates that record, only when --confirm repeats H and nothing is named H.
`connectors` lists the machines running the tunnel: Cloudflare sends each guest to the nearest one,
so more than one means guests can reach another machine's session.

The API token is read from --api-token-file, else the CLOUDFLARE_API_TOKEN variable, and goes only
into the Authorization header: never on a command line, in output or in an error. Each command
prints one JSON line on stdout. Exit codes: 0 done; 1 refused (bad arguments, no token, an API
error); 4 a clash: a record already named H, or more than one connector.

Endpoints, bodies and the permissions each accepts, as of 2026-10-21:
https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/list/ (DNS Read or Write),
https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/create/ (DNS Write),
https://developers.cloudflare.com/api/resources/zero_trust/subresources/tunnels/subresources/cloudflared/subresources/connections/methods/get/
(Cloudflare Tunnel Read or Write); the record's shape is step 3 of
https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel-api/.
Recheck when one of those pages changes a path, a field or the permissions it accepts.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import tunnel  # noqa: E402  (beside this file; sys.path is set just above)

API = "https://api.cloudflare.com/client/v4"
ID = re.compile(r"[0-9a-f]{32}")  # zone and account ids
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")  # tunnel ids
PER_PAGE = 100  # judgment: records per list request
MAX_PAGES = 100  # judgment: a zone this tool lists stays well under PER_PAGE * MAX_PAGES records


class Refused(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def api_token(path):
    """The API token from the file at `path`, else from CLOUDFLARE_API_TOKEN; refuses when neither holds one."""
    if path:
        try:
            token = Path(path).read_text(encoding="utf-8").strip()
        except OSError as exc:
            raise Refused(1, f"the API token file {path} cannot be read: {exc.strerror}") from None
    else:
        token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    if not token or any(c.isspace() for c in token):
        raise Refused(1, "no API token: pass --api-token-file, or set CLOUDFLARE_API_TOKEN")
    return token


def request(token, method, path, query=None, body=None):
    """One API call; the parsed `result` and `result_info`. SHARED_CF_API replaces the base URL (tests)."""
    url = (os.environ.get("SHARED_CF_API") or API) + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            doc = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        try:
            doc = json.loads(exc.read())
        except ValueError:
            doc = {}
        raise Refused(1, f"{method} {path}: HTTP {exc.code} {errors(doc)}") from None
    except (OSError, ValueError) as exc:
        raise Refused(1, f"{method} {path}: {exc}") from None
    if not doc.get("success"):
        raise Refused(1, f"{method} {path}: {errors(doc)}")
    return doc.get("result"), doc.get("result_info") or {}


def errors(doc):
    """The API's error messages, as one line."""
    msgs = [f"{e.get('code', '')} {e.get('message', '')}".strip() for e in doc.get("errors") or [] if isinstance(e, dict)]
    return "; ".join(msgs) or "no error message"


def zone_records(token, zone):
    """Every DNS record in the zone, one page at a time."""
    out = []
    for page in range(1, MAX_PAGES + 1):
        result, info = request(token, "GET", f"/zones/{zone}/dns_records", {"page": page, "per_page": PER_PAGE})
        out += result or []
        if page >= int(info.get("total_pages") or 1):
            return out
    raise Refused(1, f"the zone has more than {PER_PAGE * MAX_PAGES} records; this tool lists no more")


def planned(hostname, tunnel_id):
    return {"type": "CNAME", "name": hostname, "content": f"{tunnel_id}.cfargotunnel.com", "proxied": True}


def same(record, want):
    return all(str(record.get(k)).lower() == str(want[k]).lower() for k in ("type", "name", "content")) and record.get("proxied") is True


def plan(token, zone, hostname, tunnel_id):
    """(the answer, its exit code): the planned record, the records already named hostname, whether it is in place."""
    want = planned(hostname, tunnel_id)
    records = zone_records(token, zone)
    named = [{k: r.get(k) for k in ("id", "type", "name", "content", "proxied")} for r in records if str(r.get("name", "")).lower() == hostname]
    done = len(named) == 1 and same(named[0], want)
    out = {"ok": True, "zoneRecords": len(records), "planned": want, "named": named, "inPlace": done, "clash": bool(named) and not done}
    return out, 4 if out["clash"] else 0


def checked(a):
    if not ID.fullmatch(a.zone_id or ""):
        raise Refused(1, "--zone-id must be the zone's 32-character id (the zone's Overview page shows it)")
    problem = tunnel.hostname_problem(a.hostname)
    if problem:
        raise Refused(1, problem)
    if not UUID.fullmatch(a.tunnel_id or ""):
        raise Refused(1, "--tunnel-id must be the tunnel's id, a UUID")


def cmd_plan(a):
    checked(a)
    return plan(api_token(a.api_token_file), a.zone_id, a.hostname, a.tunnel_id)


def cmd_write(a):
    checked(a)
    if a.confirm != a.hostname:
        raise Refused(1, f"--confirm must repeat the hostname ({a.hostname}): the record is written only on that yes")
    token = api_token(a.api_token_file)
    out, code = plan(token, a.zone_id, a.hostname, a.tunnel_id)
    if code or out["inPlace"]:
        return {**out, "written": False}, code
    result, _ = request(token, "POST", f"/zones/{a.zone_id}/dns_records", body=out["planned"])
    return {**out, "written": True, "record": {k: (result or {}).get(k) for k in ("id", "type", "name", "content", "proxied")}}, 0


def cmd_connectors(a):
    if not ID.fullmatch(a.account_id or ""):
        raise Refused(1, "--account-id must be the account's 32-character id")
    if not UUID.fullmatch(a.tunnel_id or ""):
        raise Refused(1, "--tunnel-id must be the tunnel's id, a UUID")
    result, _ = request(api_token(a.api_token_file), "GET", f"/accounts/{a.account_id}/cfd_tunnel/{a.tunnel_id}/connections")
    connectors = [
        {"id": c.get("id"), "version": c.get("version"), "runAt": c.get("run_at"), "originIps": sorted({x.get("origin_ip") for x in c.get("conns") or [] if x.get("origin_ip")})}
        for c in result or []
    ]
    many = len(connectors) > 1
    return {"ok": True, "connectors": connectors, "count": len(connectors), "clash": many}, 4 if many else 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (("plan", cmd_plan), ("write", cmd_write), ("connectors", cmd_connectors)):
        s = sub.add_parser(name)
        s.add_argument("--api-token-file", help="a file holding the API token (else CLOUDFLARE_API_TOKEN)")
        s.add_argument("--tunnel-id", required=True)
        if name == "connectors":
            s.add_argument("--account-id", required=True)
        else:
            s.add_argument("--zone-id", required=True)
            s.add_argument("--hostname", required=True, type=str.lower)
        if name == "write":
            s.add_argument("--confirm", required=True, type=str.lower, help="the hostname again: the owner's yes to the planned record")
        s.set_defaults(fn=fn)
    a = p.parse_args(argv)
    try:
        out, code = a.fn(a)
    except Refused as exc:
        print(str(exc), file=sys.stderr)
        return exc.code
    print(json.dumps(out), flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
