"""Exporters and the ledger importer for the interview surface. Python 3 stdlib.

Each exporter reads only questions.json and responses.json from a data dir and returns text:
  export_ledger  the interview ledger: a decision-tree checklist, then the open-question register in
                 the row shape scripts/check-open-questions.sh grades, then the deferred questions
  export_brief   the PLAN.md `## Brief` sections and an empty `## Plan`
  export_report  one self-contained HTML file (no external resources; everything escaped); it
                 also inlines each file visual that resolves inside the data dir
import_ledger seeds an empty questions document from a ledger's register rows.
round.py exposes them as export-ledger, export-brief, export-report and import-ledger.

Register ids: surface ids that are already Q1..Qn stay as they are; any other set is renumbered
Q1..Qn in natural id order (letters, then number) and each row's resolution leads with `[<id>]`,
which import_ledger reads back so a re-export numbers the same way.

Every row export_ledger writes has one resolution grammar: named fields in this fixed order, each
present only when it has a value, each value escaped on its own (esc_field), joined with `; `:
  hold:: claude|user E(waitsOn)   the hold, by Claude (waits on) or the user (awaiting user)
  proposal:: E(new)               a plan's proposal and the answer it displaced; always a pair,
  was:: E(old)                    written on every row whose question the plan superseded
  answer:: E(answer)              the decision that counts, on any status: `accepted: <rec>`,
                                  `alt <key>: <text>` (`alt <key>` for a key the question does not
                                  list), `free-text: <text>`, `deferred[: <text>]`, and on a
                                  withdrawn row `archived: <why>` or `superseded by <id>`
  note:: E(note)                  an accept's or an alternative's note; on a deferred or blocked
                                  row whose answer is a bare `deferred`, the row's text as a
                                  ledger seeded it (written even when empty); on an unheld open
                                  or superseded-by-plan row with no proposal, the seeded text
  aside:: E(aside)                the newest decision a user hold set aside, when none counts;
                                  import restores it still set aside
  commitments:: M(c1)[; M(c2)...] every commitment in order, M() being `+` (confirmed) or `-`
                                  (unconfirmed) then E(text)
A superseded-by-plan row keeps that status under a defer, whose answer carries it. A deferred row
seeded from a ledger keeps that ledger's arbiter (ARBITER_USER when its text says USER-RESERVED,
else ARBITER_PLAN); a deferral made on the page is ARBITER_USER.

Import reads these fields by name and refuses, naming the field, an unknown field, a field out of
order or repeated, an unmarked commitment, and a contradictory pair: answer with aside, proposal
without was, hold or aside on a row the status settles, an answer the status contradicts, and a
note no field above gives a meaning.

Every older grammar still imports, read as it always was: a held row
`[plan proposes: E(new); was: E(old); ]waits on:: ...` or `awaiting user:: ...` with `answer:`,
`aside:`, `note:` and `confirmed:` fields; `confirmed:: ...`, `plan proposes:: ...` and
`answer:: ...` rows (an `answer::` row is the older grammar when a later field is a single-colon
`note:` or `arbiter: USER-RESERVED`, or a `; confirmed::` tail ends it); plain resolutions with
a `; confirmed:: ...` tail; and the unescaped `waits on: ...`, `confirmed: ...` and settled
`; confirmed: ...` rows.
"""

import base64
import html
import json
import re
from pathlib import Path

from server import EMPTY_RESPONSES, MAX_VISUAL_FILE, load_json, read_visual_file

# The Brief contract's arbiter tokens (the interview skill's context/loop.md "Brief template").
ARBITER_USER = "**arbiter: USER-RESERVED**"
ARBITER_PLAN = "**arbiter: /planning:plan**"
SEED_NOTE = "Seeded from ledger"
ROW = re.compile(r"^\s*-\s+[Qq]([0-9]+)\s*\|(.*)$")
LEAD = re.compile(r"^\[([^\]\s]+)\]\s*(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")
MID_SENTENCE = re.compile(r"[.!?)\"'`\]]$")
QN = re.compile(r"^Q[1-9][0-9]*$")
# Register statuses that leave a question unresolved; superseded-by-plan is a plan's
# displacement of a user answer, waiting on the user's explicit reply.
UNSETTLED = ("open", "superseded-by-plan")
PROPOSES = re.compile(r"^plan proposes:\s*(.*?);\s*was:\s*(.*)$", re.IGNORECASE)
# An open row held on research or on the user; a research hold carries the answer it keeps,
# and an unanswered one the commitments confirmed on it.
HELD = re.compile(
    r"^(waits on|awaiting user): (.*?)(?:; answer: (.*)|; confirmed: (.*))?$"
)
# E() (module docstring) escapes backslash, `;`, `|`, newline, tab and CR,
# and any other whitespace and a field's trailing spaces (the register strips a row's end) as
# \uXXXX. Only these sequences unescape; any other backslash stays literal.
ESCAPES = {"\\": "\\\\", ";": "\\;", "|": "\\|", "\n": "\\n", "\t": "\\t", "\r": "\\r"}
UNESCAPES = {"n": "\n", "t": "\t", "r": "\r"}
UNESCAPE = re.compile(r"\\(?:([\\;|])|([ntr])|u([0-9a-fA-F]{4}))")
HOLD_MARK = re.compile(r"^(waits on|awaiting user)::(?: |$)(.*)$", re.DOTALL)
HOLD_FIELD = re.compile(r"^(answer|aside|note|confirmed):(?: |$)(.*)$", re.DOTALL)
PROPOSAL_MARK = re.compile(r"^plan proposes::(?: |$)(.*)$", re.DOTALL)
WAS = re.compile(r"^was:(?: |$)(.*)$", re.DOTALL)
CONFIRMED = re.compile(r"^(?:; )?confirmed:(:?)(?: |$)(.*)$", re.DOTALL)
TAIL = re.compile(r"; confirmed::(?=[ ;]|$)")
ANSWER_MARK = re.compile(r"^answer::(?: |$)(.*)$", re.DOTALL)
FIELDS = ("hold", "proposal", "was", "answer", "note", "aside", "commitments")
NAMED = re.compile(rf"^({'|'.join(FIELDS)})::(?: |$)(.*)$", re.DOTALL)
ALT = re.compile(r"^alt (\S+?)(?:: (.*))?$", re.DOTALL)
IMAGE_TYPES = {
    ".png": "png",
    ".jpg": "jpeg",
    ".jpeg": "jpeg",
    ".gif": "gif",
    ".webp": "webp",
    ".svg": "svg+xml",
}


def clean(s):
    """One line with no register separators: pipes become slashes, all whitespace one space."""
    return " ".join(str(s or "").replace("|", "/").split())


def para(s):
    """A plain paragraph that cannot turn into a heading, a list item or a fence."""
    s = clean(s)
    return "\\" + s if s[:1] in "#`~->*+" and s else s


def esc_field(s):
    s = str(s)
    body = s.rstrip(" ")
    out = "".join(
        ESCAPES.get(c) or (f"\\u{ord(c):04x}" if c.isspace() and c != " " else c)
        for c in body
    )
    return out + "\\u0020" * (len(s) - len(body))


def unesc_field(s):
    def one(m):
        if m.group(1):
            return m.group(1)
        if m.group(2):
            return UNESCAPES[m.group(2)]
        return chr(int(m.group(3), 16))

    return UNESCAPE.sub(one, s)


def split_tail(res):
    """(resolution, confirmed commitments) of a settled row; (res, None) when no tail ends it."""
    marks = list(TAIL.finditer(res))
    body = res[marks[-1].end() :] if marks else None
    if body == ";":
        return res[: marks[-1].start()], []
    if body is None or body[:1] not in ("", " "):
        return res, None
    return res[: marks[-1].start()], [unesc_field(c) for c in split_fields(body[1:])]


def split_fields(s):
    """Split on each `; ` no backslash escapes; a final bare `;` also splits, since the row's
    strip took the space before an empty last field."""
    fields, cur, i = [], [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            cur.append(s[i : i + 2])
            i += 2
        elif s[i] == ";" and s[i + 1 : i + 2] in (" ", ""):
            fields.append("".join(cur))
            cur = []
            i += 2
        else:
            cur.append(s[i])
            i += 1
    fields.append("".join(cur))
    return fields


def decision_fields(q, rec):
    """(answer, note): the decision in the resolution vocabulary, and the note an accept or an
    alternative carries. An alternative whose key the question does not list is `alt <key>`."""
    decision, text = rec.get("decision"), rec.get("text") or ""
    if decision == "accept":
        return f"accepted: {q.get('recommendation') or 'the recommendation'}", text
    if decision == "alt":
        key = rec.get("alt") or ""
        alt = next(
            (
                a.get("text", "")
                for a in q.get("alternatives") or []
                if a.get("key") == key
            ),
            None,
        )
        return f"alt {key}" + ("" if alt is None else f": {alt}"), text
    if decision == "own":
        return f"free-text: {text}", ""
    return "deferred" + (f": {text}" if text else ""), ""


def seed_proposal(seed):
    """(new, old) of a superseded-by-plan seeded row: its `proposal` pair, else its resolution
    parsed; None for any other row."""
    if not seed or seed.get("status") != "superseded-by-plan":
        return None
    if seed.get("proposal"):
        return tuple(seed["proposal"])
    m = PROPOSES.match(seed.get("resolution", ""))
    return m.groups() if m else None


def seed_text(seed):
    """The text a seeded open or superseded-by-plan row carries beyond its proposal and its
    commitments, or None."""
    if not seed or seed.get("status") not in UNSETTLED or seed_proposal(seed):
        return None
    res = seed.get("resolution") or ""
    if seed.get("status") == "open" and CONFIRMED.match(res):
        return None
    return res or None


def plain_decision(status, res):
    """The terminal decision import_ledger restores from a plain answered, deferred or blocked
    resolution: (decision, alt, text, recommendation)."""
    if status == "answered":
        return seeded_decision(res)
    return "defer", None, res, None


def parse_answer(status, res, where):
    """(answer, note) of an escaped `answer:: ...` answered or deferred resolution, or None."""
    if status not in ("answered", "deferred") or not ANSWER_MARK.match(res):
        return None
    fields = split_fields(res)
    arbiter = fields[-1] == "arbiter: USER-RESERVED"
    fields = fields[:-1] if arbiter else fields
    note = HOLD_FIELD.match(fields[1]) if len(fields) == 2 else None
    if (
        len(fields) > 2
        or (len(fields) == 2 and not (note and note.group(1) == "note"))
        or arbiter != (status == "deferred")
    ):
        raise SystemExit(f"refused: unreadable answer {res!r} in {where}")
    answer = ANSWER_MARK.match(fields[0]).group(1)
    return unesc_field(answer), unesc_field(note.group(2)) if note else ""


def parse_proposal(res, where):
    """(new, old, confirmed) of an escaped `plan proposes:: ...` resolution, or None for any
    other."""
    mark = PROPOSAL_MARK.match(res)
    if not mark:
        return None
    fields = split_fields(res)
    was = WAS.match(fields[1]) if len(fields) > 1 else None
    listed = HOLD_FIELD.match(fields[2]) if len(fields) > 2 else None
    if not was or (len(fields) > 2 and not (listed and listed.group(1) == "confirmed")):
        raise SystemExit(f"refused: unreadable plan proposal {res!r} in {where}")
    confirmed = [listed.group(2), *fields[3:]] if listed else []
    new = PROPOSAL_MARK.match(fields[0]).group(1)
    return (
        unesc_field(new),
        unesc_field(was.group(1)),
        list(map(unesc_field, confirmed)),
    )


def parse_hold(res, where):
    """The fields of an escaped held resolution as a dict, or None for any other resolution."""
    fields = split_fields(res)
    hold = {}
    if (
        len(fields) > 2
        and fields[0].startswith("plan proposes: ")
        and fields[1].startswith("was: ")
    ):
        hold["proposal"] = (
            unesc_field(fields[0][len("plan proposes: ") :]),
            unesc_field(fields[1][len("was: ") :]),
        )
        fields = fields[2:]
    m = HOLD_MARK.match(fields[0])
    if not m:
        return None
    hold["user"], hold["waitsOn"] = (
        m.group(1) == "awaiting user",
        unesc_field(m.group(2)),
    )
    rest = fields[1:]
    for i, field in enumerate(rest):
        f = HOLD_FIELD.match(field)
        if not f or (f.group(1) in hold and f.group(1) != "confirmed"):
            raise SystemExit(f"refused: unreadable held row field {field!r} in {where}")
        if f.group(1) == "confirmed":
            hold["confirmed"] = [unesc_field(f.group(2))]
            hold["confirmed"] += [unesc_field(x) for x in rest[i + 1 :]]
            break
        hold[f.group(1)] = unesc_field(f.group(2))
    if "answer" in hold and "aside" in hold:
        raise SystemExit(
            f"refused: held row with both an answer and an aside in {where}"
        )
    return hold


def encode(fields, marked):
    """A row's resolution in the named-field grammar (module docstring); a field whose value is
    None is left out."""
    parts = [
        f"{k}::" + (f" {esc_field(fields[k])}" if fields[k] else "")
        for k in FIELDS
        if fields.get(k) is not None
    ]
    if marked:
        items = "; ".join(("+" if ok else "-") + esc_field(c) for ok, c in marked)
        parts.append(f"commitments:: {items}")
    return "; ".join(parts)


def readable(status, fields, marked):
    """A row's resolution as a reader sees it: the fields unescaped on one line. The Brief and the
    report show it; the ledger keeps the escaped row."""
    parts = []
    if fields.get("proposal") is not None:
        parts += [f"plan proposes: {fields['proposal']}", f"was: {fields['was']}"]
    if fields.get("hold"):
        who, _, waits = fields["hold"].partition(" ")
        parts.append(f"{'awaiting user' if who == 'user' else 'waits on'}: {waits}")
    if fields.get("answer"):
        parts.append(("answer: " if fields.get("hold") else "") + fields["answer"])
    if fields.get("aside"):
        parts.append(f"aside: {fields['aside']}")
    decided = fields.get("answer") or fields.get("aside") or ""
    if fields.get("note"):
        # A decision's note is labeled; any other note is the row's own seeded text.
        noted = decided.startswith("accepted: ") or ALT.match(decided)
        parts.append(("note: " if noted else "") + fields["note"])
    if status == "deferred" and fields.get("note") is None:
        # A page deferral; a seeded one's arbiter is in its own text.
        parts.append("arbiter: USER-RESERVED")
    # An unconfirmed commitment reaches the Brief only as a named risk, and only where the
    # decision carries it (register's "carries").
    confirmed = [c for ok, c in marked if ok]
    if confirmed:
        parts.append("confirmed: " + "; ".join(confirmed))
    return clean("; ".join(parts))


def held_terminal(q, answer, note, at):
    """The terminal record a held row's answer restores; an alternative's text and an accept's
    recommendation go back on the question so a re-export writes the same answer."""
    alt = re.match(r"^alt (\S+): (.*)$", answer, re.DOTALL)
    if answer == "deferred" or answer.startswith("deferred: "):
        decision, key, text = "defer", None, answer[len("deferred: ") :]
    elif answer.startswith("free-text: "):
        decision, key, text = "own", None, answer[len("free-text: ") :]
    elif alt:
        decision, key, text = "alt", alt.group(1), note
        if not any(a.get("key") == key for a in q["alternatives"]):
            q["alternatives"].append({"key": key, "text": alt.group(2)})
    elif answer.startswith("accepted: "):
        decision, key, text = "accept", None, note
        q["recommendation"] = answer[len("accepted: ") :]
    else:
        decision, key, text = "own", None, answer
    return {"decision": decision, "alt": key, "text": text, "updatedAt": at}


def natural(qid):
    m = re.match(r"^([A-Za-z]*)([0-9]*)(.*)$", qid)
    return (m.group(1), int(m.group(2) or 0), m.group(3))


def read(d):
    d = Path(d)
    doc = load_json(d / "questions.json", {"questions": []})
    resp = load_json(d / "responses.json", EMPTY_RESPONSES)
    return doc, resp


def hold_label(q):
    return "awaiting user" if q.get("waitingBy") == "user" else "waits on"


def set_aside(q, x):
    """A `wait` with `by: user` sets aside a page decision (it has a seq) up to the question's
    setAsideSeq, a terminal one with a rev up to its setAsideRev, and an older terminal one
    stamped no later than its setAsideAt."""
    if "seq" in x and q.get("setAsideSeq") is not None:
        return x["seq"] <= q["setAsideSeq"]
    if "rev" in x and q.get("setAsideRev") is not None:
        return x["rev"] <= q["setAsideRev"]
    return x["updatedAt"] <= (q.get("setAsideAt") or "")


def newest_decision(q, responses, aside):
    """The newer of the page answer and the terminal answer that a user hold set aside (aside
    True) or did not (aside False), or None."""
    cands = [
        x
        for x in (responses.get(q["id"]), q.get("terminal"))
        if x and x.get("updatedAt") and set_aside(q, x) == aside
    ]
    return max(cands, key=lambda x: x["updatedAt"]) if cands else None


def latest_decision(q, responses):
    """The decision that counts, or None; a set-aside one does not count."""
    return newest_decision(q, responses, aside=False)


def marked_commits(q, events):
    """Every commitment in order as (confirmed, text); a live `confirm` event ticks one by index,
    and so does a `commitsConfirmed` record from the confirm-commitments op."""
    ticked = {c.get("index") for c in q.get("commitsConfirmed") or []}
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
    return [(i in ticked, c) for i, c in enumerate(q.get("commits") or [])]


def commitments(q, events):
    """(confirmed, unconfirmed) commitment texts."""
    marked = marked_commits(q, events)
    return [c for ok, c in marked if ok], [c for ok, c in marked if not ok]


def settle(q, responses, events, seed_rows):
    """(status, fields, note, user_deferred) for one question: its row's named fields, from the
    question's state alone; a seeded row adds only its proposal, its status when blocked or
    deferred and the text of a row nothing decided since."""
    seed = seed_rows.get(q["id"]) or {}
    proposal = seed_proposal(seed)
    fields = dict(zip(("proposal", "was"), proposal)) if proposal else {}
    rec = latest_decision(q, responses)
    decision = (rec or {}).get("decision")
    if q.get("archived"):
        fields["answer"] = f"archived: {q['archived'].get('why', '')}"
        return "withdrawn", fields, "", False
    if q.get("supersededBy"):
        fields["answer"] = f"superseded by {q['supersededBy']}"
        return "withdrawn", fields, "", False
    if q.get("waiting"):
        who = "user" if q.get("waitingBy") == "user" else "claude"
        fields["hold"] = f"{who} {q.get('waitsOn') or 'a lookup'}"
        kind = "answer" if rec else "aside"
        rec = rec or newest_decision(q, responses, aside=True)
        if rec and rec.get("decision"):
            fields[kind], note = decision_fields(q, rec)
            fields["note"] = note or None
        return ("superseded-by-plan" if proposal else "open"), fields, "", False
    status = seed.get("status")
    if decision == "defer" and rec.get("seeded") and status in ("deferred", "blocked"):
        # A deferral as a ledger seeded it: its text rides in note, its arbiter in that text.
        text = rec.get("text") or ""
        fields.update(answer="deferred", note=text)
        return status, fields, "", status == "blocked" or "USER-RESERVED" in text
    if decision:
        text = rec.get("text") or ""
        fields["answer"], note = decision_fields(q, rec)
        fields["note"] = note or None
        if decision == "defer" and status == "superseded-by-plan":
            fields["note"] = seed_text(seed)
            return status, fields, clean(text), False
        status = "deferred" if decision == "defer" else "answered"
        return status, fields, clean(text), decision == "defer"
    fields["note"] = seed_text(seed)
    if status == "superseded-by-plan":
        # A set-aside decision leaves the plan's proposal waiting on the user again.
        return status, fields, "", False
    return "open", fields, "", False


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
        status, fields, note, reserved = settle(q, responses, events, seed_rows)
        marked = marked_commits(q, events)
        lead = "" if contiguous else f"[{clean(q['id'])}] "
        res = lead + encode(fields, marked)
        confirmed, unconfirmed = commitments(q, events)
        decided = latest_decision(q, responses) or {}
        rows.append(
            {
                "n": f"Q{i}",
                "q": q,
                "status": status,
                "resolution": res.rstrip(),
                "display": clean(lead + readable(status, fields, marked)),
                "note": note,
                "reserved": reserved,
                "confirmed": confirmed,
                "unconfirmed": unconfirmed,
                # Accept and own carry the recommendation's commitments; an alternative
                # withdraws them and a defer's open row covers them.
                "carries": decided.get("decision") in ("accept", "own"),
            }
        )
    return rows


def row_line(r):
    q = r["q"]
    line = f"- {r['n']} | {r['status']} | round {q.get('round') or 1} | {clean(q.get('title'))} | {r['resolution']}".rstrip()
    # A raw line break would start a continuation line, and one starting `- Q` forges a row.
    if len(line.splitlines()) != 1:
        raise ValueError(f"register row {r['n']} would span lines: {line!r}")
    return line


def export_ledger(d):
    doc, resp = read(d)
    rows = register(doc, resp)
    title = (doc.get("meta") or {}).get("title")
    out = ["# Interview ledger", ""]
    if title:
        out += [para(title), ""]
    out += ["**Decision tree:**", ""]
    for r in rows:
        mark = " " if r["status"] in UNSETTLED else "x"
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
        for s in ("answered", "deferred", "blocked", "withdrawn", *UNSETTLED)
    }
    answered = [r for r in rows if r["status"] == "answered"]
    confirmed = [(r, c) for r in rows for c in r["confirmed"]]
    risks = [(r, c) for r in answered if r["carries"] for c in r["unconfirmed"]]
    superseded = count["superseded-by-plan"]
    out = ["## Brief", "", "### TLDR", ""]
    out.append(
        f"- {len(rows)} questions: {count['answered']} answered, {count['deferred']} deferred, "
        f"{count['blocked']} blocked, {count['withdrawn']} withdrawn, {count['open']} open"
        + (f", {superseded} superseded-by-plan" if superseded else "")
    )
    out.append(
        f"- {len(confirmed)} commitments confirmed; {len(risks)} unconfirmed, carried as named risks"
    )
    out += ["", "### Goal", "", para(title), "", "### Constraints", ""]
    out += [
        f"- {r['n']} {clean(r['q'].get('short'))}: {r['display']}" for r in answered
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
        f"- {r['n']} {clean(r['q'].get('title'))}: {r['display']}" for r in archived
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


def render_visual(v, d):
    """One visual as HTML; a file visual inside data dir d is inlined like inline content."""
    fmt = v.get("format") or v.get("kind") or ""
    head = f"<h4>{esc(v.get('title') or v.get('id'))} <small>({esc(fmt)})</small></h4>"
    content = v.get("content")
    if "file" in v:
        file = v["file"]
        raw = read_visual_file(d, file)
        itype = IMAGE_TYPES.get(Path(str(file)).suffix.lower())
        if raw is None or len(raw) > MAX_VISUAL_FILE or (fmt == "image" and not itype):
            return head + (
                f"<p>File <code>{esc(file)}</code> in the data dir, not inlined: it is outside "
                f"the data dir, missing, over {MAX_VISUAL_FILE // 2**20} MB, or not an image type.</p>"
            )
        head += f"<p class=muted>File <code>{esc(file)}</code></p>"
        content = (
            f"data:image/{itype};base64,{base64.b64encode(raw).decode('ascii')}"
            if fmt == "image"
            else raw.decode("utf-8", "replace")
        )
    if not isinstance(content, str):
        content = json.dumps(content, indent=2, ensure_ascii=False)
    if fmt in ("svg", "html"):
        if fmt == "html" and SCRIPT_TAG.search(content):
            head += "<p class=muted>This visual needs JavaScript, which the report does not run.</p>"
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
        if r["status"] in (*UNSETTLED, "deferred", "blocked"):
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
SCRIPT_TAG = re.compile(r"<script\b", re.IGNORECASE)


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
            f"<td>{esc(q.get('title'))}</td><td>{esc(r['status'])}</td><td>{esc(r['display'])}</td></tr>"
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
        out += [render_visual(v, d) for v in visuals_for(doc, q)]
        out.append("</section>")
    scoped = {
        v.get("id") for q in doc.get("questions") or [] for v in visuals_for(doc, q)
    }
    others = [v for v in doc.get("visuals") or [] if v.get("id") not in scoped]
    if others:
        out.append("<h2>Visuals</h2>")
        out += [render_visual(v, d) for v in others]
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
        (r, c)
        for r in rows
        if r["status"] == "answered" and r["carries"]
        for c in r["unconfirmed"]
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


def import_hold(qid, title, rnd, hold, seeded, at, rev):
    """The question an escaped held row restores: the hold, the answer or the set-aside decision
    (stamped set aside as of `at` and `rev`, the rev the import writes), the confirmed
    commitments, and for a superseded-by-plan row the seeded proposal. Any other held row gets no
    seeded row, so it settles from this state alone once the hold is cleared."""
    q = {
        "id": qid,
        "short": title if len(title) <= 60 else title[:57] + "...",
        "title": title,
        "round": rnd,
        "stage": "interview",
        "commits": hold.get("confirmed") or [],
        "alternatives": [],
        "waiting": True,
        "waitsOn": hold["waitsOn"],
    }
    if hold["user"]:
        q["waitingBy"] = "user"
    status = "open"
    if "proposal" in hold:
        new, old = hold["proposal"]
        status = "superseded-by-plan"
        q["recommendation"] = new
        q["alternatives"] = [{"key": "was", "text": old}]
        seeded[qid] = {
            "status": status,
            "round": rnd,
            "resolution": f"plan proposes: {new}; was: {old}",
            "proposal": [new, old],
        }
    if "answer" in hold:
        q["terminal"] = held_terminal(q, hold["answer"], hold.get("note", ""), at)
    if "aside" in hold:
        q["terminal"] = held_terminal(q, hold["aside"], hold.get("note", ""), at)
        q.update(setAsideAt=at, setAsideSeq=0, setAsideRev=rev)
    if q["commits"]:
        q["commitsConfirmed"] = [
            {"index": i, "reason": SEED_NOTE, "at": at}
            for i in range(len(q["commits"]))
        ]
    q["history"] = [
        {
            "at": at,
            "by": "claude",
            "kind": "seed",
            "text": f"{SEED_NOTE}: {status}, held.",
        }
    ]
    return q


def refuse(what, where):
    raise SystemExit(f"refused: {what} in {where}")


def parse_named(res, where):
    """(fields, marked commitments) of a named-field resolution, or None for an older grammar's
    (module docstring)."""
    parts = split_fields(res)
    first = NAMED.match(parts[0])
    if not first:
        return None
    older = any(
        p.startswith(("note: ", "confirmed::")) or p == "arbiter: USER-RESERVED"
        for p in parts[1:]
    )
    if first.group(1) == "answer" and older:
        return None
    fields, marked, last = {}, None, -1
    for part in parts:
        m = NAMED.match(part) if marked is None else None
        if marked is None and not m:
            refuse(f"unknown field {part.partition(':')[0]!r}", where)
        if m:
            name, part = m.groups()
            if FIELDS.index(name) <= last:
                refuse(f"field {name!r} repeated or out of order", where)
            last = FIELDS.index(name)
            if name != "commitments":
                fields[name] = unesc_field(part)
                continue
            marked = []
        if part[:1] not in ("+", "-"):
            refuse(f"unmarked commitment {part!r} in field 'commitments'", where)
        marked.append((part[0] == "+", unesc_field(part[1:])))
    return fields, marked or []


def answer_kind(answer, where):
    """What a named-field answer records: defer, withdraw or decide; None for no answer."""
    if answer is None:
        return None
    if answer == "deferred" or answer.startswith("deferred: "):
        return "defer"
    if answer.startswith(("archived: ", "superseded by ")):
        return "withdraw"
    if answer.startswith(("accepted: ", "free-text: ")) or ALT.match(answer):
        return "decide"
    refuse(f"unreadable field 'answer' {answer!r}", where)


def import_named(qid, title, rnd, status, fields, marked, seeded, at, rev, where):
    """The question a named-field row restores (module docstring); a set-aside decision is
    stamped set aside as of `at` and `rev`, the rev the import writes."""

    def clash(a, b):
        refuse(f"contradictory fields {a!r} and {b!r}", where)

    hold, answer, note = fields.get("hold"), fields.get("answer"), fields.get("note")
    decided = answer if answer is not None else fields.get("aside")
    kind = answer_kind(answer, where)
    if answer is not None and "aside" in fields:
        clash("answer", "aside")
    if ("proposal" in fields) != ("was" in fields):
        clash("proposal", "was")
    if hold is not None and status not in UNSETTLED:
        clash("hold", f"status {status}")
    if "aside" in fields and hold is None:
        clash("aside", "hold")
    who, sep, waits = (hold or "").partition(" ")
    if hold is not None and (who not in ("claude", "user") or not sep):
        refuse(f"unreadable field 'hold' {hold!r}", where)
    if "proposal" in fields and status in ("open", "deferred", "blocked"):
        clash("proposal", f"status {status}")
    fits = {
        "open": kind is None or (hold is not None and kind != "withdraw"),
        "superseded-by-plan": kind in (None, "defer")
        or (hold is not None and kind == "decide"),
        "answered": kind == "decide",
        "deferred": kind == "defer",
        "blocked": answer == "deferred",
        "withdrawn": kind == "withdraw",
    }
    if not fits[status]:
        clash("answer", f"status {status}")
    seeded_defer = (
        answer == "deferred"
        and hold is None
        and (status == "blocked" or (status == "deferred" and note is not None))
    )
    residual = (
        hold is None
        and status in UNSETTLED
        and "proposal" not in fields
        and kind in (None, "defer")
    )
    noted = decided is not None and (
        decided.startswith("accepted: ") or bool(ALT.match(decided))
    )
    if note is not None and not (noted or seeded_defer or residual):
        clash("answer" if answer is not None else "hold", "note")
    q = {
        "id": qid,
        "short": title if len(title) <= 60 else title[:57] + "...",
        "title": title,
        "round": rnd,
        "stage": "interview",
        "commits": [c for _, c in marked],
        "alternatives": [],
    }
    ticked = [i for i, (ok, _) in enumerate(marked) if ok]
    if ticked:
        q["commitsConfirmed"] = [
            {"index": i, "reason": SEED_NOTE, "at": at} for i in ticked
        ]
    if hold is not None:
        q.update(waiting=True, waitsOn=waits)
        if who == "user":
            q["waitingBy"] = "user"
    if "proposal" in fields:
        new, old = fields["proposal"], fields["was"]
        q["recommendation"] = new
        q["alternatives"] = [{"key": "was", "text": old}]
        seeded[qid] = {
            "status": "superseded-by-plan",
            "round": rnd,
            "resolution": f"plan proposes: {new}; was: {old}",
            "proposal": [new, old],
        }
    elif status == "superseded-by-plan" or (residual and note is not None):
        seeded[qid] = {"status": status, "round": rnd, "resolution": note or ""}
    if kind == "withdraw" and answer.startswith("archived: "):
        q["archived"] = {"why": answer[len("archived: ") :], "at": at, "seeded": True}
    elif kind == "withdraw":
        q["supersededBy"] = answer[len("superseded by ") :]
    elif seeded_defer:
        q["terminal"] = {
            "decision": "defer",
            "alt": None,
            "text": note or "",
            "updatedAt": at,
            "seeded": True,
        }
        seeded[qid] = {"status": status, "round": rnd, "resolution": note or ""}
    elif decided is not None:
        bare = ALT.match(decided)
        if bare and bare.group(2) is None:
            q["terminal"] = {
                "decision": "alt",
                "alt": bare.group(1),
                "text": note or "",
                "updatedAt": at,
            }
        else:
            q["terminal"] = held_terminal(q, decided, (noted and note) or "", at)
        if "aside" in fields:
            q.update(setAsideAt=at, setAsideSeq=0, setAsideRev=rev)
    by = "claude" if status in UNSETTLED else "user-terminal"
    line = f"{SEED_NOTE}: {status}" + (", held." if hold is not None else ".")
    if hold is None and status == "superseded-by-plan" and seeded[qid]["resolution"]:
        line += " " + seeded[qid]["resolution"]
    q["history"] = [{"at": at, "by": by, "kind": "seed", "text": line}]
    return q


def import_ledger(doc, text, ledger, at):
    """Fill an empty questions document from a ledger: settled rows keep their decision, open rows stay open."""
    rows = parse_register(text)
    if not rows:
        raise SystemExit(f"refused: no open-question register rows in {ledger}")
    seeded, seen = {}, set()
    for n, status, rnd, title, res in rows:
        lead = LEAD.match(res)
        qid, res = (lead.group(1), lead.group(2)) if lead else (f"Q{n}", res)
        if qid in seen:
            raise SystemExit(f"refused: duplicate question id in {ledger}: {qid}")
        seen.add(qid)
        if status not in (*UNSETTLED, "answered", "deferred", "withdrawn", "blocked"):
            raise SystemExit(f"refused: unknown status {status!r} for Q{n} in {ledger}")
        named = parse_named(res, ledger)
        if named:
            rev = doc.get("rev", 0) + 1
            q = import_named(qid, title, rnd, status, *named, seeded, at, rev, ledger)
            doc["questions"].append(q)
            continue
        hold = parse_hold(res, ledger) if status in UNSETTLED else None
        if hold:
            rev = doc.get("rev", 0) + 1
            doc["questions"].append(import_hold(qid, title, rnd, hold, seeded, at, rev))
            continue
        held = HELD.match(res) if status == "open" else None
        commits = held.group(4).split("; ") if held and held.group(4) else None
        if held:  # the hold itself is restored below, so its text leaves the seeded row
            if held.group(3):
                status, res = "answered", held.group(3)
            else:
                res = f"confirmed: {held.group(4)}" if held.group(4) else ""
        elif status not in UNSETTLED:
            res, commits = split_tail(res)
        elif status == "superseded-by-plan" and not (
            PROPOSAL_MARK.match(res) or PROPOSES.match(res)
        ):
            res, commits = split_tail(res)
        answer = parse_answer(status, res, ledger)
        listed = CONFIRMED.match(res) if status == "open" and not held else None
        proposal = (
            parse_proposal(res, ledger) if status == "superseded-by-plan" else None
        )
        # An escaped open or answer row settles from its state alone, as a held row does.
        if not (listed and listed.group(1)) and not answer:
            seeded[qid] = {"status": status, "round": rnd, "resolution": res}
        if proposal:
            new, old, commits = proposal
            seeded[qid].update(
                resolution=f"plan proposes: {new}; was: {old}", proposal=[new, old]
            )
        pair = seed_proposal(seeded.get(qid))
        q = {
            "id": qid,
            "short": title if len(title) <= 60 else title[:57] + "...",
            "title": title,
            "round": rnd,
            "stage": "interview",
            "commits": [],
            "alternatives": [],
        }
        if answer:
            q["terminal"] = held_terminal(q, *answer, at)
            if (q["terminal"]["decision"] == "defer") != (status == "deferred"):
                raise SystemExit(
                    f"refused: {status} row with answer {res!r} in {ledger}"
                )
        elif status in ("answered", "deferred", "blocked"):
            decision, alt, dtext, recommendation = plain_decision(status, res)
            if recommendation:
                q["recommendation"] = recommendation
            q["terminal"] = {
                "decision": decision,
                "alt": alt,
                "text": dtext,
                "updatedAt": at,
                "seeded": True,
            }
        elif status == "withdrawn":
            why = (
                res[len("archived:") :].strip() if res.startswith("archived:") else res
            )
            q["archived"] = {"why": why or "withdrawn", "at": at, "seeded": True}
        elif status == "superseded-by-plan" and pair:
            q["recommendation"] = pair[0]
            q["alternatives"] = [{"key": "was", "text": pair[1]}]
        if listed:
            body = listed.group(2)
            commits = (
                [unesc_field(c) for c in split_fields(body)]
                if listed.group(1)
                else body.split("; ")
            )
        if commits:
            q["commits"] = commits
            q["commitsConfirmed"] = [
                {"index": i, "reason": SEED_NOTE, "at": at} for i in range(len(commits))
            ]
        if held:
            q.update(waiting=True, waitsOn=held.group(2))
            if held.group(1) == "awaiting user":
                q["waitingBy"] = "user"
        by = "claude" if status in UNSETTLED else "user-terminal"
        note = f"{SEED_NOTE}: {status}."
        if status == "superseded-by-plan" and res:
            note += f" {res}"
        q["history"] = [{"at": at, "by": by, "kind": "seed", "text": note}]
        doc["questions"].append(q)
    meta = doc.setdefault("meta", {})
    meta.setdefault("title", f"Seeded from {Path(ledger).name}")
    meta["seededFrom"] = {"ledger": ledger, "at": at, "rows": seeded}
    return doc
