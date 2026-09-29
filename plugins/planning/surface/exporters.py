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

A held row's resolution escapes each field on its own (esc_field) and joins the fields with `; `:
  [plan proposes: E(new); was: E(old); ]<label>:: E(waitsOn)[; answer: E(answer)|; aside: E(aside)]
  [; note: E(note)][; confirmed: E(c1)[; E(c2)...]]
The label is `waits on` (a Claude hold) or `awaiting user` (a user hold); its double colon marks
the row as escaped, so an older row (`waits on: ...`) is read as before and never unescaped. The
proposal leads only on a superseded-by-plan row, which keeps that status; import keeps it as the
seeded row's `proposal` pair, so a re-export never parses it again. The answer is the decision
that counts, in the resolution vocabulary (`accepted: <recommendation>`, `alt <key>: <text>`,
`free-text: <text>`, `deferred[: <text>]`); when none counts, aside is the newest decision a user
hold set aside, which import restores still set aside; note is the note of an accept or an
alternative in answer or aside; confirmed lists the confirmed commitments, one field each.

Unheld rows use the same escaping, marked the same way by a double colon:
  confirmed:: E(c1)[; E(c2)...]        an open row with confirmed commitments
  plan proposes:: E(new); was: E(old)[; confirmed: E(c1)[; E(c2)...]]
                                       a superseded-by-plan row with confirmed commitments, or
                                       whose proposal the plain
                                       `plan proposes: <new>; was: <old>` would not read back
  answer:: E(answer)[; note: E(note)][; arbiter: USER-RESERVED]
                                       an answered or deferred row (the arbiter on a deferred
                                       row only) whose plain resolution would not read back the
                                       same decision, text and answer; answer and note are a
                                       held row's
  <resolution>; confirmed:: C(c1)[; C(c2)...]
                                       an answered, deferred, withdrawn or blocked row, or a
                                       superseded-by-plan row whose resolution is not a
                                       proposal, with confirmed commitments; the resolution
                                       before it is plain or the escaped answer
C() is E() with the `c` of each `confirmed::` written \\u0063 and the `w` of each `was:` (any
case) written \\u0077 or \\u0057, so the tail holds no other `confirmed::`, the last
`; confirmed::` of the row (followed by a space, a `;` or the row's end) starts it, and the tail
never makes a row read as a plain proposal. A plain resolution holding that mark and no
confirmed commitment gets the empty tail `; confirmed::;`; a superseded-by-plan row that reads
as a plain proposal has no tail.
An older `confirmed: ...` or `; confirmed: ...` row still imports, split on `; ` unescaped, and an
older settled row's `; confirmed: ...` stays part of its resolution.
"""

import base64
import html
import json
import re
from pathlib import Path

from server import (
    EMPTY_RESPONSES,
    IMAGE_TYPES,
    MAX_VISUAL_FILE,
    load_json,
    read_visual_file,
)

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
# The escaped held row (module docstring): E() escapes backslash, `;`, `|`, newline, tab and CR,
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
WAS_MARK = re.compile(r"w(?=as:)", re.IGNORECASE)


def clean(s):
    """One line with no register separators: pipes become slashes, all whitespace one space."""
    return " ".join(str(s or "").replace("|", "/").split())


def para(s):
    """A plain paragraph that cannot turn into a heading, a list item or a fence."""
    s = clean(s)
    return "\\" + s if s[:1] in "#`~->*+" and s else s


class Escaped(str):
    """A held row's resolution, already escaped field by field; clean() would corrupt it."""


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


def with_tail(res, confirmed):
    """A settled row's resolution, cleaned, then its escaped `; confirmed:: ...` tail when it has
    confirmed commitments or the resolution already holds the tail's mark."""
    res = res if isinstance(res, Escaped) else clean(res)
    if not confirmed and not TAIL.search(res):
        return res
    listed = "; ".join(
        WAS_MARK.sub(
            lambda m: f"\\u{ord(m.group()):04x}",
            esc_field(c).replace("confirmed::", "\\u0063onfirmed::"),
        )
        for c in confirmed
    )
    return Escaped(f"{res}; confirmed::" + (f" {listed}" if confirmed else ";"))


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
    """(answer, note) for a held row: the decision in the resolution vocabulary, and the note an
    accept or an alternative carries."""
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
            "",
        )
        return f"alt {key}: {alt}", text
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


def seed_resolution(seed, confirmed):
    """A seeded row's resolution; a superseded-by-plan proposal with confirmed commitments, or
    one the plain form would not read back, takes the escaped `plan proposes:: ...` form."""
    res = seed.get("resolution", "")
    proposal = seed_proposal(seed)
    m = PROPOSES.match(res)
    plain = clean(res) == res and m and m.groups() == tuple(proposal or ())
    if not proposal:
        superseded = seed.get("status") == "superseded-by-plan"
        return with_tail(res, confirmed) if superseded else res
    if plain and not confirmed:
        return res
    new, old = proposal
    fields = [f"plan proposes:: {esc_field(new)}", f"was: {esc_field(old)}"]
    if confirmed:
        fields.append("confirmed: " + "; ".join(esc_field(c) for c in confirmed))
    return Escaped("; ".join(fields))


def plain_decision(status, res):
    """The terminal decision import_ledger restores from a plain answered, deferred or blocked
    resolution: (decision, alt, text, recommendation)."""
    if status == "answered":
        return seeded_decision(res)
    return "defer", None, res, None


def reads_back(status, res, q, rec):
    """Whether importing the plain res restores rec's decision, text and answer."""
    decision, alt, text, recommendation = plain_decision(status, res)
    back = {"decision": decision, "alt": alt, "text": text}
    mine = {"recommendation": recommendation, "alternatives": []}

    def key(q, r):
        alt = r.get("alt") if r.get("decision") == "alt" else None
        return r.get("decision"), alt, r.get("text") or "", decision_fields(q, r)

    return key(mine, back) == key(q, rec)


def answer_row(q, rec, confirmed):
    """(status, resolution) of an unheld answered or deferred question: the plain vocabulary
    when it reads back, else the escaped `answer:: ...` form."""
    status = "deferred" if rec["decision"] == "defer" else "answered"
    answer, note = decision_fields(q, rec)
    arbiter = ["arbiter: USER-RESERVED"] if status == "deferred" else []
    noted = [f"note: {clean(note)}"] if clean(note) else []
    res = "; ".join([clean(answer), *noted, *arbiter])
    if not reads_back(status, res, q, rec):
        noted = [f"note: {esc_field(note)}"] if note else []
        res = Escaped("; ".join([f"answer:: {esc_field(answer)}", *noted, *arbiter]))
    return status, with_tail(res, confirmed)


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


def hold_row(q, responses, events, seed):
    """(status, resolution) of a held question, in the escaped grammar of the module docstring."""
    proposal = seed_proposal(seed)
    fields = []
    if proposal:
        new, old = proposal
        fields += [f"plan proposes: {esc_field(new)}", f"was: {esc_field(old)}"]
    fields.append(f"{hold_label(q)}:: {esc_field(q.get('waitsOn') or 'a lookup')}")
    rec = latest_decision(q, responses)
    kind = "answer" if rec else "aside"
    rec = rec or newest_decision(q, responses, aside=True)
    if rec and rec.get("decision"):
        answer, note = decision_fields(q, rec)
        fields.append(f"{kind}: {esc_field(answer)}")
        if note:
            fields.append(f"note: {esc_field(note)}")
    confirmed, _ = commitments(q, events)
    if confirmed:
        fields.append("confirmed: " + "; ".join(esc_field(c) for c in confirmed))
    return ("superseded-by-plan" if proposal else "open"), Escaped("; ".join(fields))


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


def readable(status, res):
    """An escaped row's resolution as a reader sees it: the plain vocabulary on one line, its
    marks dropped and its fields unescaped, read in import_ledger's order. The Brief and the
    report show it; the ledger keeps the escaped row."""
    where = "the register"
    hold = parse_hold(res, where) if status in UNSETTLED else None
    parts, confirmed = [], None
    if hold:
        if "proposal" in hold:
            new, old = hold["proposal"]
            parts += [f"plan proposes: {new}", f"was: {old}"]
        label = "awaiting user" if hold["user"] else "waits on"
        parts.append(f"{label}: {hold['waitsOn']}")
        parts += [f"{k}: {hold[k]}" for k in ("answer", "aside", "note") if k in hold]
        confirmed = hold.get("confirmed")
    else:
        if status not in UNSETTLED or (
            status == "superseded-by-plan"
            and not (PROPOSAL_MARK.match(res) or PROPOSES.match(res))
        ):
            res, confirmed = split_tail(res)
        answer = parse_answer(status, res, where)
        proposal = (
            parse_proposal(res, where) if status == "superseded-by-plan" else None
        )
        listed = CONFIRMED.match(res) if status == "open" else None
        if answer:
            parts = [answer[0], *([f"note: {answer[1]}"] if answer[1] else [])]
            parts += ["arbiter: USER-RESERVED"] if status == "deferred" else []
        elif proposal:
            parts = [f"plan proposes: {proposal[0]}", f"was: {proposal[1]}"]
            confirmed = proposal[2]
        elif listed and listed.group(1):
            confirmed = [unesc_field(c) for c in split_fields(listed.group(2))]
        else:
            parts = [res]
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


def commitments(q, events):
    """(confirmed, unconfirmed) commitment texts; a live `confirm` event ticks one by index, and
    so does a `commitsConfirmed` record from the confirm-commitments op."""
    commits = q.get("commits") or []
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
    confirmed = [c for i, c in enumerate(commits) if i in ticked]
    return confirmed, [c for i, c in enumerate(commits) if i not in ticked]


def settle(q, responses, events, seed_rows):
    """(status, resolution, note, user_deferred) for one question."""
    seed = seed_rows.get(q["id"])
    page = responses.get(q["id"])
    # A hold, or a user hold's set-aside stamp, outranks a seeded row; a superseded-by-plan
    # one keeps the plan's proposal as its resolution once the hold is cleared.
    held = q.get("waiting") or any(k.startswith("setAside") for k in q)
    live = q.get("waiting") or (
        held and seed and seed["status"] != "superseded-by-plan"
    )
    confirmed, _ = commitments(q, events)
    if seed and not page and not live:
        term, arch = q.get("terminal") or {}, q.get("archived") or {}
        untouched = seed["status"] in UNSETTLED and not term and not arch
        if untouched or term.get("seeded") or arch.get("seeded"):
            res = seed_resolution(seed, confirmed)
            reserved = seed["status"] == "blocked" or "USER-RESERVED" in res
            if seed["status"] not in UNSETTLED:
                res = with_tail(res, confirmed)
            return seed["status"], res, "", reserved
    if q.get("archived"):
        why = q["archived"].get("why", "")
        return "withdrawn", with_tail(f"archived: {why}", confirmed), "", False
    if q.get("supersededBy"):
        res = with_tail(f"superseded by {q['supersededBy']}", confirmed)
        return "withdrawn", res, "", False
    if q.get("waiting"):
        status, res = hold_row(q, responses, events, seed)
        return status, res, "", False
    rec = latest_decision(q, responses)
    decision = rec.get("decision") if rec else None
    text = clean((rec or {}).get("text"))
    note = f"; note: {text}" if text else ""
    superseded = seed and seed["status"] == "superseded-by-plan"
    proposal = seed_proposal(seed)
    if decision == "accept" and proposal:
        new, old = proposal
        res = f"reconfirmed at plan approval: {new}; was: {old}{note}"
        return "answered", with_tail(res, confirmed), text, False
    if decision == "defer" and superseded:
        # The resolution stays the seed's own, so a re-import reads the same proposal back.
        return "superseded-by-plan", seed_resolution(seed, confirmed), text, False
    if decision in ("accept", "alt", "own", "defer"):
        return (*answer_row(q, rec, confirmed), text, decision == "defer")
    if superseded:
        # A set-aside decision leaves the plan's proposal waiting on the user again.
        return "superseded-by-plan", seed_resolution(seed, confirmed), "", False
    if confirmed:
        listed = "; ".join(esc_field(c) for c in confirmed)
        return "open", Escaped(f"confirmed:: {listed}"), "", False
    return "open", "", "", False


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
        lead = "" if contiguous else f"[{q['id']}] "
        shown = (
            clean(lead + readable(status, res)) if isinstance(res, Escaped) else None
        )
        if isinstance(res, Escaped):
            res = f"[{clean(q['id'])}] {res}" if not contiguous else str(res)
        else:
            res = clean(
                f"[{q['id']}]" + (f" {res}" if res else "") if not contiguous else res
            )
        confirmed, unconfirmed = commitments(q, events)
        decided = latest_decision(q, responses) or {}
        rows.append(
            {
                "n": f"Q{i}",
                "q": q,
                "status": status,
                "resolution": res,
                "display": res if shown is None else shown,
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
    restated = (doc.get("restatement") or {}).get("sections", {}).get("acceptance")
    criteria = [
        "- " + para(re.sub(r"^(?:[-*+]\s+)?(?:\[[ xX]\]\s*)?", "", line.strip()))
        for line in str(restated or "").splitlines()
        if line.strip()
    ]
    out += [
        "",
        "### Acceptance criteria",
        "",
        *(criteria or ["- none recorded in the interview surface"]),
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
    return [v for v in out if not v.get("archived")]


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
    others = [
        v
        for v in doc.get("visuals") or []
        if v.get("id") not in scoped and not v.get("archived")
    ]
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
