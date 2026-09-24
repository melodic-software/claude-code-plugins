"""Exporters and the ledger importer for the interview surface. Python 3 stdlib.

Each exporter reads only questions.json and responses.json from a data dir and returns text:
  export_ledger  the interview ledger: a decision-tree checklist, then the open-question register in
                 the row shape scripts/check-open-questions.sh grades, then the deferred questions
  export_brief   the PLAN.md `## Brief` sections and an empty `## Plan`
  export_report  one self-contained HTML file (no external resources; everything escaped)
import_ledger seeds an empty questions document from a ledger's register rows.
round.py exposes them as export-ledger, export-brief, export-report and import-ledger.

Register ids: surface ids that are already Q1..Qn stay as they are; any other set is renumbered
Q1..Qn in natural id order (letters, then number) and each row's resolution leads with `[<id>]`,
which import_ledger reads back so a re-export numbers the same way.
"""

import html
import json
import re
from pathlib import Path

from server import EMPTY_RESPONSES, load_json

# The Brief contract's arbiter tokens (the interview skill's context/loop.md "Brief template").
ARBITER_USER = "**arbiter: USER-RESERVED**"
ARBITER_PLAN = "**arbiter: /planning:plan**"
SEED_NOTE = "Seeded from ledger"
ROW = re.compile(r"^\s*-\s+[Qq]([0-9]+)\s*\|(.*)$")
LEAD = re.compile(r"^\[([^\]\s]+)\]\s*(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")
MID_SENTENCE = re.compile(r"[.!?)\"'`\]]$")
QN = re.compile(r"^Q[1-9][0-9]*$")


def clean(s):
    """One line with no register separators: pipes become slashes, all whitespace one space."""
    return " ".join(str(s or "").replace("|", "/").split())


def para(s):
    """A plain paragraph that cannot turn into a heading, a list item or a fence."""
    s = clean(s)
    return "\\" + s if s[:1] in "#`~->*+" and s else s


def natural(qid):
    m = re.match(r"^([A-Za-z]*)([0-9]*)(.*)$", qid)
    return (m.group(1), int(m.group(2) or 0), m.group(3))


def read(d):
    d = Path(d)
    doc = load_json(d / "questions.json", {"questions": []})
    resp = load_json(d / "responses.json", EMPTY_RESPONSES)
    return doc, resp


def latest_decision(q, responses):
    """The newer of the page answer and the terminal answer, or None."""
    cands = [
        x
        for x in (responses.get(q["id"]), q.get("terminal"))
        if x and x.get("updatedAt")
    ]
    return max(cands, key=lambda x: x["updatedAt"]) if cands else None


def commitments(q, events):
    """(confirmed, unconfirmed) commitment texts; a live `confirm` event ticks one by index."""
    commits = q.get("commits") or []
    ticked = set()
    for e in events:
        if (
            e.get("id") == q["id"]
            and e.get("kind") == "confirm"
            and not e.get("withdrawn")
        ):
            try:
                ticked.add(int(e.get("alt")))
            except (TypeError, ValueError):
                continue
    confirmed = [c for i, c in enumerate(commits) if i in ticked]
    return confirmed, [c for i, c in enumerate(commits) if i not in ticked]


def settle(q, responses, events, seed_rows):
    """(status, resolution, note, user_deferred) for one question."""
    seed = seed_rows.get(q["id"])
    page = responses.get(q["id"])
    if seed and not page:
        term, arch = q.get("terminal") or {}, q.get("archived") or {}
        untouched = seed["status"] == "open" and not term and not arch
        if untouched or term.get("seeded") or arch.get("seeded"):
            res = seed.get("resolution", "")
            reserved = seed["status"] == "blocked" or "USER-RESERVED" in res
            return seed["status"], res, "", reserved
    confirmed, _ = commitments(q, events)
    tail = f"; confirmed: {'; '.join(confirmed)}" if confirmed else ""
    if q.get("archived"):
        return (
            "withdrawn",
            f"archived: {q['archived'].get('why', '')}" + tail,
            "",
            False,
        )
    if q.get("supersededBy"):
        return "withdrawn", f"superseded by {q['supersededBy']}" + tail, "", False
    rec = latest_decision(q, responses)
    decision = rec.get("decision") if rec else None
    text = clean((rec or {}).get("text"))
    note = f"; note: {text}" if text else ""
    if decision == "accept":
        return (
            "answered",
            f"accepted: {q.get('recommendation') or 'the recommendation'}{note}{tail}",
            text,
            False,
        )
    if decision == "alt":
        key = rec.get("alt") or ""
        alt = next(
            (
                a.get("text", "")
                for a in q.get("alternatives") or []
                if a.get("key") == key
            ),
            "",
        )
        return "answered", f"alt {key}: {alt}{note}{tail}", text, False
    if decision == "own":
        return "answered", f"free-text: {text}{tail}", text, False
    if decision == "defer":
        res = "deferred" + (f": {text}" if text else "") + "; arbiter: USER-RESERVED"
        return "deferred", res + tail, text, True
    waiting = (
        f"waiting on: {q.get('waitsOn') or 'a lookup'}" if q.get("waiting") else ""
    )
    return "open", waiting + tail, "", False


def register(doc, resp):
    """One dict per question, in register order, with its Q<N> and settled status."""
    qs = list(doc.get("questions") or [])
    ids = [q["id"] for q in qs]
    contiguous = all(QN.match(i) for i in ids) and sorted(
        int(i[1:]) for i in ids
    ) == list(range(1, len(ids) + 1))
    qs.sort(key=lambda q: natural(q["id"]))
    events = resp.get("events") or []
    responses = resp.get("responses") or {}
    seed_rows = ((doc.get("meta") or {}).get("seededFrom") or {}).get("rows") or {}
    rows = []
    for i, q in enumerate(qs, start=1):
        status, res, note, reserved = settle(q, responses, events, seed_rows)
        if not contiguous:
            res = f"[{q['id']}]" + (f" {res}" if res else "")
        confirmed, unconfirmed = commitments(q, events)
        rows.append(
            {
                "n": f"Q{i}",
                "q": q,
                "status": status,
                "resolution": clean(res),
                "note": note,
                "reserved": reserved,
                "confirmed": confirmed,
                "unconfirmed": unconfirmed,
            }
        )
    return rows


def row_line(r):
    q = r["q"]
    return f"- {r['n']} | {r['status']} | round {q.get('round') or 1} | {clean(q.get('title'))} | {r['resolution']}".rstrip()


def export_ledger(d):
    doc, resp = read(d)
    rows = register(doc, resp)
    title = (doc.get("meta") or {}).get("title")
    out = ["# Interview ledger", ""]
    if title:
        out += [para(title), ""]
    out += ["**Decision tree:**", ""]
    for r in rows:
        mark = " " if r["status"] == "open" else "x"
        out.append(f"- [{mark}] {r['n']} {clean(r['q'].get('short'))}: {r['status']}")
    out += ["", "## Open-question register", ""]
    out += [row_line(r) for r in rows]
    out += ["", "### Deferred questions", ""]
    retired = [r for r in rows if r["status"] in ("deferred", "blocked")]
    out += [f"- {r['n']}: {clean(r['q'].get('title'))}" for r in retired] or ["- none"]
    return "\n".join(out) + "\n"


def export_brief(d):
    doc, resp = read(d)
    rows = register(doc, resp)
    title = (doc.get("meta") or {}).get("title") or "Interview decisions"
    count = {
        s: sum(1 for r in rows if r["status"] == s)
        for s in ("answered", "deferred", "blocked", "withdrawn", "open")
    }
    answered = [r for r in rows if r["status"] == "answered"]
    confirmed = [(r, c) for r in rows for c in r["confirmed"]]
    risks = [(r, c) for r in answered for c in r["unconfirmed"]]
    out = ["## Brief", "", "### TLDR", ""]
    out.append(
        f"- {len(rows)} questions: {count['answered']} answered, {count['deferred']} deferred, "
        f"{count['blocked']} blocked, {count['withdrawn']} withdrawn, {count['open']} open"
    )
    out.append(
        f"- {len(confirmed)} commitments confirmed; {len(risks)} unconfirmed, carried as named risks"
    )
    out += ["", "### Goal", "", para(title), "", "### Constraints", ""]
    out += [
        f"- {r['n']} {clean(r['q'].get('short'))}: {r['resolution']}" for r in answered
    ] or ["- none recorded"]
    out += [
        "",
        "### Acceptance criteria",
        "",
        "- none recorded in the interview surface",
        "",
    ]
    out += ["### Captured assumptions", ""]
    lines = [
        f"- {clean(c)}: confirmed on {r['n']}; revisit if {r['n']} changes"
        for r, c in confirmed
    ]
    lines += [f"- risk: {clean(c)} (unconfirmed); from {r['n']}" for r, c in risks]
    out += lines or ["- none"]
    out += ["", "### Out-of-scope", ""]
    archived = [r for r in rows if r["status"] == "withdrawn"]
    out += [
        f"- {r['n']} {clean(r['q'].get('title'))}: {r['resolution']}" for r in archived
    ] or ["- none"]
    out += ["", "### Deferred questions", ""]
    retired = [r for r in rows if r["status"] in ("deferred", "blocked")]
    for r in retired:
        until = r["note"] or "the user revisits it"
        arbiter = ARBITER_USER if r["reserved"] else ARBITER_PLAN
        out.append(
            f"- {r['n']}: {clean(r['q'].get('title'))}, defer until {until}; {arbiter}"
        )
    if not retired:
        out.append("- none")
    out += ["", "## Plan", ""]
    return "\n".join(out)


def esc(s):
    return html.escape(str(s if s is not None else ""), quote=True)


def render_visual(v):
    fmt = v.get("format") or v.get("kind") or ""
    head = f"<h4>{esc(v.get('title') or v.get('id'))} <small>({esc(fmt)})</small></h4>"
    if "file" in v:
        return head + (
            f"<p>File <code>{esc(v['file'])}</code> in the data dir; the report embeds only "
            "what questions.json carries.</p>"
        )
    content = v.get("content")
    if not isinstance(content, str):
        content = json.dumps(content, indent=2, ensure_ascii=False)
    if fmt in ("svg", "html"):
        return (
            head
            + f'<iframe sandbox="" title="{esc(v.get("title") or v.get("id"))}" srcdoc="{esc(content)}"></iframe>'
        )
    if fmt == "image" and content.startswith("data:image/"):
        return (
            head
            + f'<img alt="{esc(v.get("title") or v.get("id"))}" src="{esc(content)}">'
        )
    body = head + f"<pre>{esc(content)}</pre>"
    if fmt == "mermaid":
        body += "<p class=muted>Mermaid rendering is not available; the source is shown.</p>"
    return body


def visuals_for(doc, q):
    by_id = {v.get("id"): v for v in doc.get("visuals") or []}
    out = []
    for v in q.get("visuals") or []:
        v = by_id.get(v) if isinstance(v, str) else v
        if v:
            out.append(v)
    out += [
        v for v in doc.get("visuals") or [] if v.get("scope") == f"question:{q['id']}"
    ]
    return out


def thread(q, resp):
    lines = [dict(h) for h in q.get("history") or []]
    lines += [dict(h) for h in (resp.get("history") or {}).get(q["id"], [])]
    lines.sort(key=lambda h: h.get("at") or "")
    items = []
    for h in lines:
        what = " ".join(x for x in (h.get("kind") or "", h.get("alt") or "") if x)
        cls = ' class="withdrawn"' if h.get("withdrawn") else ""
        items.append(
            f"<li{cls}><b>{esc(h.get('by'))}</b> <time>{esc(h.get('at'))}</time> "
            f"{esc(what)} {esc(h.get('text'))}</li>"
        )
    return "<ol class=thread>" + "".join(items) + "</ol>" if items else ""


def loose_ends(rows, doc, resp):
    ends = []
    for r in rows:
        if r["status"] in ("open", "deferred", "blocked"):
            ends.append(
                f"{r['n']} ({r['q']['id']}) is {r['status']}: {clean(r['q'].get('title'))}"
            )
    replied = {
        h.get("replyTo")
        for q in doc.get("questions") or []
        for h in q.get("history") or []
    }
    replied |= {h.get("replyTo") for h in doc.get("notes") or []}
    for e in resp.get("events") or []:
        text = (e.get("text") or "").strip()
        if e.get("withdrawn"):
            continue
        if (
            text
            and not MID_SENTENCE.search(text)
            and e.get("kind") in ("own", "note", "ask", "accept", "alt", "defer")
        ):
            ends.append(
                f"#{e['seq']} {e.get('id') or 'note'} ends mid-sentence: {clean(text)}"
            )
        if e.get("kind") in ("ask", "rephrase", "note") and e["seq"] not in replied:
            ends.append(
                f"#{e['seq']} {e.get('id') or 'note'} {e['kind']} has no reply from Claude"
            )
    return ends


STYLE = """
body{font:15px/1.5 system-ui,sans-serif;margin:24px;color:#1d2433;background:#fff}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccd;padding:4px 8px;text-align:left;vertical-align:top}
section{border-top:1px solid #ccd;margin-top:16px}iframe{width:100%;height:320px;border:1px solid #ccd}
pre{white-space:pre-wrap;background:#f4f5f8;padding:8px}.muted{color:#667}.withdrawn{text-decoration:line-through}
"""
# No network source: the srcdoc iframes inherit this policy, so a visual cannot load remote content.
REPORT_CSP = "default-src 'none'; img-src data:; style-src 'unsafe-inline'"


def export_report(d):
    doc, resp = read(d)
    rows = register(doc, resp)
    title = (doc.get("meta") or {}).get("title") or "Interview report"
    out = [
        "<!doctype html>",
        '<html lang="en"><head><meta charset="utf-8">',
        f'<meta http-equiv="Content-Security-Policy" content="{REPORT_CSP}">',
        f"<title>{esc(title)}</title><style>{STYLE}</style></head><body>",
        f"<h1>{esc(title)}</h1>",
        "<h2>Decisions</h2>",
        "<table><thead><tr><th>Register</th><th>Id</th><th>Question</th><th>Status</th>"
        "<th>Resolution</th></tr></thead><tbody>",
    ]
    for r in rows:
        q = r["q"]
        out.append(
            f'<tr><td>{esc(r["n"])}</td><td><a href="#q-{esc(q["id"])}">{esc(q["id"])}</a></td>'
            f"<td>{esc(q.get('title'))}</td><td>{esc(r['status'])}</td><td>{esc(r['resolution'])}</td></tr>"
        )
    out.append("</tbody></table>")
    out.append("<h2>Questions</h2>")
    for r in rows:
        q = r["q"]
        out.append(
            f'<section id="q-{esc(q["id"])}"><h3>{esc(q["id"])} {esc(q.get("short"))}</h3>'
        )
        out.append(f"<p>{esc(q.get('title'))}</p>")
        if q.get("recommendation"):
            out.append(f"<p><b>Recommendation:</b> {esc(q['recommendation'])}</p>")
        if q.get("basis"):
            out.append(f"<p class=muted>{esc(q['basis'])}</p>")
        commits = [(c, "confirmed") for c in r["confirmed"]] + [
            (c, "unconfirmed") for c in r["unconfirmed"]
        ]
        if commits:
            out.append(
                "<ul>"
                + "".join(f"<li>{esc(c)} ({s})</li>" for c, s in commits)
                + "</ul>"
            )
        out.append(thread(q, resp))
        out += [render_visual(v) for v in visuals_for(doc, q)]
        out.append("</section>")
    scoped = {
        v.get("id") for q in doc.get("questions") or [] for v in visuals_for(doc, q)
    }
    others = [v for v in doc.get("visuals") or [] if v.get("id") not in scoped]
    if others:
        out.append("<h2>Visuals</h2>")
        out += [render_visual(v) for v in others]
    notes = [e for e in resp.get("events") or [] if e.get("kind") == "note"]
    if notes or doc.get("notes"):
        out.append("<h2>Notes</h2><ol>")
        out += [
            f"<li>#{e['seq']} <time>{esc(e.get('at'))}</time> {esc(e.get('text'))}</li>"
            for e in notes
        ]
        out += [
            f"<li><b>claude</b> <time>{esc(n.get('at'))}</time> {esc(n.get('text'))}</li>"
            for n in doc.get("notes") or []
        ]
        out.append("</ol>")
    out.append("<h2>Loose ends</h2><ul>")
    out += [f"<li>{esc(x)}</li>" for x in loose_ends(rows, doc, resp)] or [
        "<li>none</li>"
    ]
    out.append("</ul><h2>Named risks</h2><ul>")
    risks = [
        (r, c) for r in rows if r["status"] == "answered" for c in r["unconfirmed"]
    ]
    out += [f"<li>{esc(r['n'])}: {esc(c)} (unconfirmed)</li>" for r, c in risks] or [
        "<li>none</li>"
    ]
    out.append("</ul></body></html>")
    return "\n".join(out) + "\n"


def parse_register(text):
    """Register rows as (n, status, round, title, resolution), skipping fenced blocks."""
    rows, inside, fenced = [], False, False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        if re.match(r"^#+\s", line):
            if inside:
                break
            inside = "open-question register" in line.lower()
            continue
        m = ROW.match(line) if inside else None
        if not m:
            continue
        parts = [p.strip() for p in m.group(2).split("|", 3)]
        parts += [""] * (4 - len(parts))
        status, rnd, title, res = parts
        digits = re.sub(r"[^0-9]", "", rnd)
        rows.append((int(m.group(1)), status.lower(), int(digits or 1), title, res))
    return rows


def seeded_decision(res):
    """The terminal decision an `answered` resolution records: (decision, alt, text, recommendation)."""
    if res.startswith("free-text:"):
        return "own", None, res[len("free-text:") :].strip(), None
    m = re.match(r"^alt (\S+): (.*)$", res)
    if m:
        return "alt", m.group(1), m.group(2), None
    if res.startswith("accepted:"):
        return "accept", None, "", res[len("accepted:") :].strip()
    return "own", None, res, None


def import_ledger(doc, text, ledger, at):
    """Fill an empty questions document from a ledger: settled rows keep their decision, open rows stay open."""
    rows = parse_register(text)
    if not rows:
        raise SystemExit(f"refused: no open-question register rows in {ledger}")
    seeded = {}
    for n, status, rnd, title, res in rows:
        lead = LEAD.match(res)
        qid, res = (lead.group(1), lead.group(2)) if lead else (f"Q{n}", res)
        if qid in seeded:
            raise SystemExit(f"refused: duplicate question id in {ledger}: {qid}")
        if status not in ("open", "answered", "deferred", "withdrawn", "blocked"):
            raise SystemExit(f"refused: unknown status {status!r} for Q{n} in {ledger}")
        seeded[qid] = {"status": status, "round": rnd, "resolution": res}
        q = {
            "id": qid,
            "short": title if len(title) <= 60 else title[:57] + "...",
            "title": title,
            "round": rnd,
            "stage": "interview",
            "commits": [],
            "alternatives": [],
        }
        if status == "answered":
            decision, alt, dtext, recommendation = seeded_decision(res)
            if recommendation:
                q["recommendation"] = recommendation
            q["terminal"] = {
                "decision": decision,
                "alt": alt,
                "text": dtext,
                "updatedAt": at,
                "seeded": True,
            }
        elif status in ("deferred", "blocked"):
            q["terminal"] = {
                "decision": "defer",
                "alt": None,
                "text": res,
                "updatedAt": at,
                "seeded": True,
            }
        elif status == "withdrawn":
            why = (
                res[len("archived:") :].strip() if res.startswith("archived:") else res
            )
            q["archived"] = {"why": why or "withdrawn", "at": at, "seeded": True}
        by = "claude" if status == "open" else "user-terminal"
        q["history"] = [
            {"at": at, "by": by, "kind": "seed", "text": f"{SEED_NOTE}: {status}."}
        ]
        doc["questions"].append(q)
    meta = doc.setdefault("meta", {})
    meta.setdefault("title", f"Seeded from {Path(ledger).name}")
    meta["seededFrom"] = {"ledger": ledger, "at": at, "rows": seeded}
    return doc
