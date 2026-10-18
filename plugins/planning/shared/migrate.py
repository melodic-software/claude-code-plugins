"""Bring a shared session file up to the current schemaVersion.

`MIGRATIONS[n]` takes a version-n document to version n+1 as a `(doc, ctx) -> doc` function that
never mutates its input; `migrate` runs them in order and stamps each step's version. `ctx.now` is
the migration time and `ctx.note` records a line for server.log (field names, never values).

Version 0 is the prototype's state file (`.work/shared-interview-proto/server.py`), which has no
schemaVersion: a file without one is version 0 only when it has the prototype's top-level keys.
"""

import collections
import copy
import hashlib
import re
import secrets
import time

CURRENT = 3
MIGRATIONS = {}

PROTOTYPE_KEYS = frozenset({"questions", "answers", "ideas", "people", "secrets", "round"})
HOST = "host"
COLORS = tuple(f"c{i}" for i in range(1, 11))
QID = re.compile(r"Q[1-9][0-9]{0,5}")
NUMBERED = re.compile(r"[A-Z]([1-9][0-9]{0,8})")
VIEWS = ("focus", "compare", "tree", "host", "prototype")
REQUEST_KINDS = ("ask", "research", "explore", "design", "prototype")
PREF_KEYS = ("claudeTake", "sort", "filter", "round", "expandedRounds", "theme", "accent", "follow", "mute")
NOTIFY_KINDS = ("mention", "reply", "request", "proposal", "round", "merge", "role", "queue", "ready", "votes")
THEME = {"mode": ("system", "light", "dark"), "accent": ("teal", "indigo", "violet", "amber")}
FLAGS = ("voting", "signoff", "chat", "follow", "digestNames", "uploads")
NOTIFY_CAP = 500
MIN_OWNER_TOKEN = 16  # the prototype's owner token is token_urlsafe(12): 16 characters, 96 bits
MAX_URL = 2000
URL = re.compile(r"https?://\S+", re.IGNORECASE)  # a link, as every v1 write route takes one
IMAGE_ASSET = re.compile(r"[0-9a-f]{16}\.(png|jpg|webp|svg)")  # an image asset's file name
OTHER_OPTION = {"id": "other", "label": "Something else…", "other": True}  # the server adds it to every choice question


class MigrationError(ValueError):
    """The document cannot be brought to the current version."""


class Context:
    def __init__(self, now, notes):
        self.now = now
        self.notes = notes

    def note(self, line):
        if self.notes is not None and line not in self.notes:
            self.notes.append(line)


def version_of(doc):
    if "schemaVersion" not in doc and PROTOTYPE_KEYS <= doc.keys():
        return 0
    version = doc.get("schemaVersion")
    if isinstance(version, bool) or not isinstance(version, int) or version < 1:
        raise MigrationError(f"schemaVersion must be a positive integer, got {version!r}")
    return version


def migrate(doc, notes=None, now=None):
    """`doc` at CURRENT. `notes`, a list, collects lines for server.log."""
    version = version_of(doc)
    if version > CURRENT:
        raise MigrationError(f"state.json has schemaVersion {version}, newer than {CURRENT}, the newest this plugin reads; update the plugin")
    ctx = Context(time.time() if now is None else now, notes)
    while version < CURRENT:
        step = MIGRATIONS.get(version)
        if step is None:
            raise MigrationError(f"no migration from schemaVersion {version} to {version + 1}")
        version += 1
        doc = {**step(doc, ctx), "schemaVersion": version}
    return doc


def prototype_owner_token(doc):
    """The plaintext owner token a prototype state holds, when it is long enough to keep, else None."""
    token = doc.get("ownerToken") if "schemaVersion" not in doc else None
    return token if isinstance(token, str) and len(token) >= MIN_OWNER_TOKEN else None


def prototype_assets(doc):
    """The asset file names a prototype state's questions name (option images, confirm images, image references)."""
    out = set()
    for q in doc.get("questions") or []:
        if not isinstance(q, dict):
            continue
        out.add(q.get("image"))
        out.update(o.get("image") for o in q.get("options") or [] if isinstance(o, dict))
        out.update(r.get("asset") for r in q.get("references") or [] if isinstance(r, dict))
    return sorted(a for a in out if isinstance(a, str) and IMAGE_ASSET.fullmatch(a))


# -- 0 -> 1: the prototype's state ------------------------------------------------------------


def _sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _ts(v, default):
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else default


def _str(v, limit, default=""):
    return v[:limit] if isinstance(v, str) else default


def _dict(v):
    return v if isinstance(v, dict) else {}


def _list(v):
    return v if isinstance(v, list) else []


def _num(ident):
    m = NUMBERED.fullmatch(ident) if isinstance(ident, str) else None
    return int(m.group(1)) if m else 0


def _purpose(fmt_kind, settled):
    if fmt_kind == "confirm":
        return "poll"
    return "gather" if fmt_kind == "text" and not settled else "decide"


class _V0:
    """One prototype document on its way to version 1."""

    def __init__(self, doc, ctx):
        self.src, self.ctx, self.now = doc, ctx, ctx.now
        self.people = {}
        self.names = {}  # case-folded name -> pid
        self.dropped = collections.Counter()  # collection -> records naming no known question or person, or with no id

    def drop(self, collection, n=1):
        self.dropped[collection] += n

    def link(self, v, field):
        """v as a v1 link (http or https), else None with a note naming the field."""
        if isinstance(v, str) and len(v) <= MAX_URL and URL.fullmatch(v.strip()):
            return v.strip()
        self.ctx.note(f"import: {field} is not an http(s) link; dropped")
        return None

    def image(self, v, field):
        """v as an image asset's file name, else None with a note naming the field."""
        if isinstance(v, str) and IMAGE_ASSET.fullmatch(v):
            return v
        self.ctx.note(f"import: {field} is not an image asset name; dropped")
        return None

    def unmapped(self, where, rec, used):
        for k in sorted(set(_dict(rec)) - set(used)):
            self.ctx.note(f"import: {where}.{k} has no counterpart in schemaVersion 1; dropped")

    # people --------------------------------------------------------------------------------

    def _add(self, pid, name, joined):
        base = (name.strip() if isinstance(name, str) else "")[:40] or f"Guest {len(self.people)}"
        out, n = base, 2
        while out.casefold() in self.names:
            suffix = f" {n}"
            out, n = base[: 40 - len(suffix)] + suffix, n + 1
        self.names[out.casefold()] = pid
        self.people[pid] = {
            "pid": pid,
            "name": out,
            "joinedAt": joined,
            "role": "owner" if pid == HOST else "guest",
            "trusted": pid == HOST,
            "color": COLORS[len(self.people) % len(COLORS)],
            "status": {"kind": "active"},
        }

    def person(self, pid, name=None, at=None):
        """pid, added as a guest when a record names someone the prototype no longer listed."""
        if not isinstance(pid, str) or not pid:
            return None
        if pid not in self.people:
            self._add(pid, name, _ts(at, self.now))
        return pid

    def by_name(self, name):
        """The pid of the person the prototype recorded by name only (lock and ready authors), else host."""
        return self.names.get(name.casefold(), HOST) if isinstance(name, str) else HOST

    def load_people(self):
        src = _dict(self.src.get("people"))
        host = _dict(src.get(HOST))
        self._add(HOST, host.get("name") or "Host", _ts(host.get("ts"), self.now))
        for pid, rec in src.items():
            if pid != HOST and isinstance(pid, str):
                self._add(pid, _dict(rec).get("name"), _ts(_dict(rec).get("ts"), self.now))
            self.unmapped("people", rec, ("name", "ts"))

    def finish_people(self):
        leaders, trusted = set(_list(self.src.get("leaders"))), set(_list(self.src.get("trusted")))
        removed = set(_list(self.src.get("removed")))
        for pid, p in self.people.items():
            if pid == HOST:
                continue
            if pid in removed:
                p["status"] = {"kind": "removed", "at": self.now, "by": "host"}
            else:
                p["role"] = "leader" if pid in leaders else "guest"
                p["trusted"] = pid in trusted

    # questions and cards -------------------------------------------------------------------

    @staticmethod
    def _ref(key, q):
        """The card ref a prototype answer key becomes, or None when that card does not exist."""
        if key == "claude":
            return "c:rec" if q.get("recommendation") else None
        if isinstance(key, str) and key.startswith("claude-"):
            k = {"claude-2": "a", "claude-3": "b", "claude-4": "c"}.get(key)
            return f"c:{k}" if k and any(a["key"] == k for a in q["alternatives"]) else None
        fmt = q["format"]
        if fmt["kind"] == "confirm" and key in ("opt-yes", "opt-no"):
            return f"o:{key[4:]}"
        if fmt["kind"] == "choice" and any(o["id"] == key for o in fmt["options"]):
            return f"o:{key}"
        return f"p:{key}" if isinstance(key, str) and key else None

    def _reference(self, r):
        """The v1 reference; None when its kind has no counterpart, False when its link or asset fails."""
        r = _dict(r)
        kind = r.get("kind")
        if kind == "image" and isinstance(r.get("asset"), str):
            if not self.image(r["asset"], "questions.references.asset"):
                return False
            out = {"kind": "image", "asset": r["asset"]}
            if isinstance(r.get("rect"), dict):
                out["rect"] = {k: float(r["rect"].get(k, 0)) for k in ("x", "y", "w", "h")}
            if isinstance(r.get("caption"), str) and r["caption"]:
                out["caption"] = r["caption"][:2000]
            return out
        if kind == "quote" and isinstance(r.get("text"), str) and isinstance(r.get("source"), str):
            url = self.link(r["url"], "questions.references.url") if "url" in r else None
            return {"kind": "quote", "text": r["text"][:2000], "source": r["source"], **({"url": url} if url else {})}
        if kind == "link" and isinstance(r.get("url"), str):
            url = self.link(r["url"], "questions.references.url")
            return {"kind": "link", "url": url, **({"title": r["title"]} if isinstance(r.get("title"), str) else {})} if url else False
        return None

    def question(self, raw, answers, known, ideas):
        raw = _dict(raw)
        qid = raw.get("id")
        if not isinstance(qid, str) or not QID.fullmatch(qid) or qid in known:
            self.ctx.note("import: a question without a usable id was dropped")
            return None
        by = _dict(answers.get(qid))
        fmt_kind = raw.get("format") or "text"
        q = {"id": qid, "text": _str(raw.get("text"), 2000)}
        rec, alts = _dict(by.get("claude")), [_dict(by[k]) for k in ("claude-2", "claude-3", "claude-4") if k in by]
        q["alternatives"] = []
        if fmt_kind == "text" and rec.get("text") and 2 <= len(alts) <= 3:
            q["recommendation"] = _str(rec.get("text"), 2000)
            q["alternatives"] = [{"key": k, "text": _str(a.get("text"), 2000)} for k, a in zip("abc", alts, strict=False)]
            if rec.get("basis"):
                q["basis"] = _str(rec["basis"], 4000)
        q["dependsOn"] = [d for d in dict.fromkeys(_list(raw.get("dependsOn"))) if d in known]
        rnd = raw.get("round", 1)
        q["round"] = rnd if isinstance(rnd, int) and not isinstance(rnd, bool) and rnd >= 1 else 1
        options = [o for o in _list(raw.get("options")) if isinstance(o, dict)]
        if fmt_kind == "choice" and 2 <= len(options) <= 4:
            q["format"] = {"kind": "choice", "options": []}
            for o in options:
                image = self.image(o["image"], "questions.options.image") if "image" in o else None
                q["format"]["options"].append({"id": o.get("id"), "label": _str(o.get("label"), 2000), **({"image": image} if image else {})})
            q["format"]["options"].append(dict(OTHER_OPTION))
        elif fmt_kind == "confirm" and "image" in raw and self.image(raw["image"], "questions.image") and isinstance(raw.get("rect"), dict):
            q["format"] = {"kind": "confirm", "image": raw["image"], "rect": {k: float(raw["rect"].get(k, 0)) for k in ("x", "y", "w", "h")}}
        else:
            if fmt_kind != "text":
                self.ctx.note("import: a choice or confirm question missing its options or image became a text question")
            q["format"] = {"kind": "text"}
        q["answerScope"] = "person"
        refs = [self._reference(r) for r in _list(raw.get("references"))]
        if any(r is None for r in refs):
            self.ctx.note("import: questions.references holds an attachment kind with no counterpart; dropped")
        q["references"] = [r for r in refs if r][:8]
        if isinstance(raw.get("proposal"), str) and raw["proposal"] in ideas:
            q["origin"] = {"kind": "proposal", "proposal": ideas[raw["proposal"]]}
        elif "addedBy" in raw or "from" in raw:
            source = next((iid for iid, idea in self.idea_qids.items() if idea == qid), None)
            q["origin"] = {"kind": "host", "proposal": ideas[source], "by": self.by_name(raw.get("addedBy"))} if source else {"kind": "claude"}
        else:
            q["origin"] = {"kind": "claude"}
        if q["origin"]["kind"] == "host":
            q.pop("recommendation", None)
            q.pop("basis", None)
            q["alternatives"] = []
        voted = any(_list(_dict(a).get("votes")) for a in by.values())
        settled = bool(q.get("recommendation")) or voted or qid in _dict(self.src.get("locks"))
        q["purpose"] = _purpose(q["format"]["kind"], settled)
        if isinstance(raw.get("lockedText"), str):
            q["lockedText"] = raw["lockedText"]
        flag = _dict(raw.get("needsReview"))
        q["needsReview"] = []
        if isinstance(flag.get("because"), str) and QID.fullmatch(flag["because"]):
            why = (
                {"kind": "suggested", "suggestion": flag["suggestion"]}
                if isinstance(flag.get("suggestion"), str)
                else {"kind": "unlocked"}
                if flag.get("unlocked")
                else {"kind": "lock-changed"}
            )
            q["needsReview"] = [{"because": flag["because"], "at": _ts(flag.get("ts"), self.now), "why": why}]
        used = ("id", "text", "round", "dependsOn", "format", "options", "image", "rect", "references", "proposal", "from", "addedBy", "lockedText", "needsReview")
        self.unmapped("questions", raw, used)
        return q

    def cards(self, q, by):
        """The question's cards and votes (pid -> card ref) from the prototype's answers to it."""
        cards = []
        if q.get("recommendation"):
            cards.append({"kind": "claude", "key": "rec", "at": _ts(_dict(by.get("claude")).get("ts"), self.now)})
            for a, key in zip(q["alternatives"], ("claude-2", "claude-3", "claude-4"), strict=False):
                cards.append({"kind": "claude", "key": a["key"], "at": _ts(_dict(by.get(key)).get("ts"), self.now)})
        fmt = q["format"]
        if fmt["kind"] == "choice":
            cards += [{"kind": "option", "option": o["id"]} for o in fmt["options"] if not o.get("other")]
        elif fmt["kind"] == "confirm":
            cards += [{"kind": "option", "option": "yes"}, {"kind": "option", "option": "no"}]
        people = sorted(
            ((cid, _dict(a)) for cid, a in by.items() if not _dict(a).get("claude") and not _dict(a).get("option")),
            key=lambda kv: _ts(kv[1].get("ts"), 0.0),
        )
        for cid, a in people:
            pid = self.person(cid, a.get("name"), a.get("ts"))
            if pid is None:
                self.drop("answers")
                continue
            view = _dict(a.get("ctx")).get("view")
            card = {"kind": "person", "pid": pid, "text": _str(a.get("text"), 2000), "at": _ts(a.get("ts"), self.now)}
            if isinstance(a.get("pick"), str) and a["pick"]:
                card["pick"] = {"opt-yes": "yes", "opt-no": "no"}.get(a["pick"], a["pick"])
            card["cites"] = [c for c in _list(a.get("cites")) if isinstance(c, str)][:5]
            edited = a.get("editedAfter")
            if isinstance(edited, int) and not isinstance(edited, bool) and edited > 0:
                card["editedAfterVotes"] = edited
            card["view"] = view if view in VIEWS else "focus"
            cards.append(card)
            self.unmapped("answers", a, ("name", "text", "ts", "pick", "cites", "editedAfter", "ctx", "votes"))
            for k in sorted(set(_dict(a.get("ctx"))) - {"view"}):
                self.ctx.note(f"import: answers.ctx.{k} has no counterpart in schemaVersion 1; dropped")
        refs = {self._card_ref(c) for c in cards}
        votes = {}
        for key, a in by.items():
            ref = self._ref(key, q)
            if ref not in refs:
                continue
            for voter in _list(_dict(a).get("votes")):
                if isinstance(voter, str) and voter not in votes and f"p:{voter}" != ref:
                    votes[self.person(voter)] = ref
            if _dict(a).get("voteCtx"):
                self.ctx.note("import: answers.voteCtx has no counterpart in schemaVersion 1; dropped")
        return cards, votes

    @staticmethod
    def _card_ref(card):
        if card["kind"] == "person":
            return f"p:{card['pid']}"
        return f"c:{card['key']}" if card["kind"] == "claude" else f"o:{card['option']}"

    # the whole document --------------------------------------------------------------------

    def build(self):
        src, now = self.src, self.now
        self.load_people()
        raw_ideas = [i for i in _list(src.get("ideas")) if isinstance(i, dict) and isinstance(i.get("id"), str)]
        self.drop("ideas", len(_list(src.get("ideas"))) - len(raw_ideas))
        ideas, taken = {}, set()
        for i in raw_ideas:
            n = _num(i["id"])
            while not n or n in taken:
                n = max(taken | {0}) + 1
            taken.add(n)
            ideas[i["id"]] = f"P{n}"
        self.idea_qids = {i["id"]: i.get("qid") for i in raw_ideas}
        answers = _dict(src.get("answers"))

        questions, known = [], set()
        for raw in _list(src.get("questions")):
            q = self.question(raw, answers, known, ideas)
            if q:
                questions.append(q)
                known.add(q["id"])
        self.drop("answers", sum(len(_dict(answers[qid])) for qid in set(answers) - known))
        cards, votes = {}, {}
        for q in questions:
            cards[q["id"]], v = self.cards(q, _dict(answers.get(q["id"])))
            if v:
                votes[q["id"]] = v

        suggestions, suggestion_votes, max_s = {}, {}, 0
        for qid, lst in _dict(src.get("suggestions")).items():
            if qid not in known:
                self.drop("suggestions", len(_list(lst)))
                continue
            out, by = [], {}
            for s in _list(lst):
                s = _dict(s)
                pid = self.person(s.get("cid"), s.get("name"), s.get("ts")) if isinstance(s.get("id"), str) else None
                if pid is None:
                    self.drop("suggestions")
                    continue
                at = _ts(s.get("ts"), now)
                kind = s.get("status")
                status = {"kind": kind, "at": at} if kind in ("used", "dismissed") else {"kind": "closed", "by": "unlock", "at": at} if kind == "closed" else {"kind": "open"}
                rec = {"id": s["id"], "pid": pid, "text": _str(s.get("text"), 2000), "note": _str(s.get("note"), 200), "at": at, "status": status}
                if s.get("fromProposal") in ideas:
                    rec["fromProposal"] = ideas[s["fromProposal"]]
                out.append(rec)
                max_s = max(max_s, _num(s["id"]))
                for voter in _list(s.get("votes")):
                    if isinstance(voter, str) and voter not in by:
                        by[self.person(voter)] = s["id"]
                self.unmapped("suggestions", s, ("id", "cid", "name", "text", "note", "ts", "votes", "status", "closedBy", "fromProposal"))
            suggestions[qid] = out
            if by:
                suggestion_votes[qid] = by

        locks = {}
        for qid, lk in _dict(src.get("locks")).items():
            lk = _dict(lk)
            if qid not in known or not isinstance(lk.get("text"), str):
                self.drop("locks")
                continue
            text = lk["text"][:2000]
            q = next(q for q in questions if q["id"] == qid)
            ref = self._ref(lk.get("answerCid"), q)
            ref = ref if ref in {self._card_ref(c) for c in cards[qid]} else None
            used = next((s for s in suggestions.get(qid, []) if s["status"]["kind"] == "used" and s["text"] == text and f"p:{s['pid']}" == ref), None)
            if q["purpose"] == "poll":  # a poll closes as a whole; no single answer is locked
                source = {"kind": "poll"}
            elif lk.get("edited") or (ref is None and used is None):
                source = {"kind": "edited", "text": text, "from": ref}
            elif used:
                source = {"kind": "suggestion", "suggestion": used["id"], "text": text}
            else:
                source = {"kind": "card", "card": ref, "text": text}
            locks[qid] = {"at": _ts(lk.get("ts"), now), "by": self.by_name(lk.get("by")), "source": source}
            self.unmapped("locks", lk, ("by", "answerCid", "name", "text", "ts", "edited"))

        chat, forwarded = [], {}
        for m in _list(src.get("chat")):
            m = _dict(m)
            pid = self.person(m.get("cid"), m.get("name"), m.get("ts")) if isinstance(m.get("id"), str) else None
            if pid is None:
                self.drop("chat")
                continue
            rec = {"id": m["id"], "pid": pid, "text": _str(m.get("text"), 2000), "at": _ts(m.get("ts"), now)}
            reply = _dict(m.get("replyTo"))
            if isinstance(reply.get("id"), str) and self.person(reply.get("cid"), reply.get("name")):
                rec["replyTo"] = {"id": reply["id"], "pid": reply["cid"], "excerpt": _str(reply.get("text"), 140)}
            if m.get("forwarded") in ideas:
                rec["proposed"] = ideas[m["forwarded"]]
                forwarded[m["forwarded"]] = m["id"]
            chat.append(rec)
            self.unmapped("chat", m, ("id", "cid", "name", "text", "ts", "forwarded", "replyTo"))

        proposals = []
        for i in raw_ideas:
            pid = self.person(i.get("cid"), i.get("name"), i.get("ts"))
            if pid is None:
                self.drop("ideas")
                continue
            qid, reason, kind = i.get("qid"), _str(i.get("reason"), 400), i.get("status")
            if kind in ("question", "placed", "promoted") and qid in known:
                status = {"kind": "question", "question": qid}
            elif kind == "suggested" and qid in known and isinstance(i.get("sid"), str):
                status = {"kind": "suggested", "question": qid, "suggestion": i["sid"]}
            elif kind == "merged" and qid in known:
                status = {"kind": "merged", "question": qid, "reason": reason}
            elif kind == "parked":
                status = {"kind": "parked", "by": HOST}
            elif kind == "later":
                status = {"kind": "later", "reason": reason}
            elif kind == "notplaced":
                status = {"kind": "not-placed", "reason": reason}
            else:
                status = {"kind": "new"}
            via = {"kind": "chat", "message": forwarded[i["id"]], "by": self.by_name(i.get("via"))} if i["id"] in forwarded else {"kind": "direct"}
            proposals.append({"id": ideas[i["id"]], "pid": pid, "text": _str(i.get("text"), 2000), "at": _ts(i.get("ts"), now), "via": via, "status": status})
            self.unmapped("ideas", i, ("id", "cid", "name", "text", "ts", "status", "qid", "sid", "reason", "via", "direct"))

        results, done_by = {}, {}
        for qid, lst in _dict(src.get("research")).items():
            if qid not in known:
                self.drop("research", len(_list(lst)))
                continue
            out = []
            for r in _list(lst):
                r = _dict(r)
                if not isinstance(r.get("id"), str):
                    self.drop("research")
                    continue
                kind = r.get("kind") if r.get("kind") in REQUEST_KINDS else "research"
                links = [(s, self.link(s.get("url"), "research.sources.url")) for s in _list(r.get("sources")) if isinstance(s, dict)]
                sources = [{"title": _str(s.get("title"), 200), "url": url} for s, url in links if url][:30]
                request = r.get("requestId") if isinstance(r.get("requestId"), str) and r.get("requestId") else None
                out.append(
                    {
                        "id": r["id"],
                        "qid": qid,
                        "at": _ts(r.get("ts"), now),
                        "request": request,
                        "kind": kind,
                        "used": [{"name": r["skill"][:80], "type": "skill"}] if isinstance(r.get("skill"), str) and r["skill"] else [],
                        "why": "",
                        "summary": _str(r.get("summary"), 4000),
                        "sources": sources,
                        "report": _str(r.get("report"), 60000),
                        "by": {"kind": "host-claude"},
                        "published": True,
                    }
                )
                if request:
                    done_by[request] = out[-1]
                self.unmapped("research", r, ("id", "requestId", "kind", "skill", "summary", "sources", "report", "ts"))
            results[qid] = out

        requests = []
        for r in _list(src.get("requests")):
            r = _dict(r)
            pid = self.person(r.get("cid"), r.get("name"), r.get("ts")) if isinstance(r.get("id"), str) and r.get("qid") in known else None
            if pid is None:
                self.drop("requests")
                continue
            kind = r.get("status")
            if kind == "running":
                status = {"kind": "running", "since": now}
            elif kind == "declined":
                status = {"kind": "declined", "at": now}
            elif kind == "done":
                res = done_by.get(r["id"])
                status = {"kind": "done", "at": res["at"] if res else now, "result": res["id"] if res else ""}
            elif kind == "failed":
                status = {"kind": "failed", "at": now, "reason": _str(r.get("reason"), 200), "cancelled": False}
            else:
                status = {"kind": "pending"}
            requests.append(
                {
                    "id": r["id"],
                    "pid": pid,
                    "qid": r["qid"],
                    "at": _ts(r.get("ts"), now),
                    "kind": r.get("kind") if r.get("kind") in REQUEST_KINDS else "ask",
                    "text": _str(r.get("text"), 2000),
                    "edited": bool(r.get("edited")),
                    "runner": "host",
                    "status": status,
                }
            )
            self.unmapped("requests", r, ("id", "qid", "kind", "text", "cid", "name", "ts", "status", "edited", "reason"))

        merges = []
        for m in _list(src.get("mergeRequests")):
            m = _dict(m)
            if m.get("from") not in self.people or m.get("to") not in self.people or HOST in (m.get("from"), m.get("to")) or not isinstance(m.get("id"), str):
                self.drop("mergeRequests")
                continue
            at = _ts(m.get("ts"), now)
            kind = m.get("status")
            status = {"kind": "approved", "at": at} if kind == "approved" else {"kind": "declined", "at": at, "why": "host"} if kind == "declined" else {"kind": "pending"}
            merges.append({"id": m["id"], "from": m["from"], "to": m["to"], "at": at, "status": status})
            self.unmapped("mergeRequests", m, ("id", "from", "to", "fromName", "toName", "ts", "status"))

        self.finish_people()

        prefs = {}
        for pid, mine in _dict(src.get("prefs")).items():
            if pid not in self.people:
                self.drop("prefs")
                continue
            out = {}
            for k, v in _dict(mine).items():
                if k in PREF_KEYS and isinstance(v, dict) and "value" in v:
                    out[k] = {"value": v["value"], "at": _ts(v.get("ts"), now)}
                else:
                    self.ctx.note(f"import: prefs.{k} has no counterpart in schemaVersion 1; dropped")
            if out:
                prefs[pid] = out

        notifications, max_n = {}, 0
        for pid, lst in _dict(src.get("notifications")).items():
            if pid not in self.people:
                self.drop("notifications", len(_list(lst)))
                continue
            out = []
            for n in _list(lst)[-NOTIFY_CAP:]:
                n = _dict(n)
                if n.get("kind") not in NOTIFY_KINDS or not isinstance(n.get("id"), str):
                    self.drop("notifications")
                    continue
                rec = {"id": n["id"], "kind": n["kind"], "title": _str(n.get("title"), 400), "at": _ts(n.get("ts"), now), "read": bool(n.get("read"))}
                if n.get("byCid") in self.people:
                    rec["by"] = n["byCid"]
                for k in ("body", "msg"):
                    if isinstance(n.get(k), str):
                        rec[k] = n[k]
                if isinstance(n.get("qid"), str) and QID.fullmatch(n["qid"]):
                    rec["qid"] = n["qid"]
                if isinstance(n.get("key"), str):
                    count = n.get("n", 1)
                    rec["rollup"] = {"key": n["key"], "since": _ts(n.get("since"), rec["at"]), "n": count if isinstance(count, int) and count >= 1 else 1}
                out.append(rec)
                max_n = max(max_n, _num(n["id"]))
                self.unmapped("notifications", n, ("id", "kind", "title", "ts", "read", "by", "byCid", "body", "msg", "qid", "key", "n", "since"))
            notifications[pid] = out

        # A secret the prototype mapped to the host (a join with the owner token, or a guest merged
        # into the host) would give that browser owner powers through the guest listener.
        secrets_out, held, orphans = {}, 0, 0
        for secret, pid in _dict(src.get("secrets")).items():
            if pid == HOST:
                held += 1
            elif isinstance(secret, str) and secret and pid in self.people:
                secrets_out[_sha256(secret)] = pid
            else:
                orphans += 1
        if held:
            self.ctx.note(f"import: {held} session secrets held by the host were dropped; the owner link carries owner identity")
        if orphans:
            self.ctx.note(f"import: {orphans} session secrets name no person; dropped")
        token = src.get("ownerToken") if isinstance(src.get("ownerToken"), str) and src.get("ownerToken") else secrets.token_urlsafe(32)

        settings_in = _dict(src.get("settings"))
        theme = _dict(settings_in.get("theme"))
        settings = {k: settings_in[k] if isinstance(settings_in.get(k), bool) else default for k, default in zip(FLAGS, (True, False, True, True, False, False), strict=True)}
        settings["names"] = "full" if settings_in.get("showNames", True) else "initials"
        settings["claudeTake"] = "answerFirst" if settings_in.get("hideClaude", True) else "always"
        settings["theme"] = {k: theme.get(k) if theme.get(k) in allowed else allowed[0] for k, allowed in THEME.items()}
        self.unmapped("settings", settings_in, (*FLAGS, "showNames", "hideClaude", "theme"))

        rounds = self.rounds(questions, cards)
        ended = _dict(src.get("ended"))
        seq = {
            "P": max([_num(p["id"]) for p in proposals], default=0),
            "S": max(max_s, src.get("suggestSeq", 0) if isinstance(src.get("suggestSeq"), int) else 0),
            "R": max([_num(r["id"]) for r in requests] + [src.get("requestSeq", 0) if isinstance(src.get("requestSeq"), int) else 0]),
            "X": max([_num(r["id"]) for lst in results.values() for r in lst] + [src.get("researchSeq", 0) if isinstance(src.get("researchSeq"), int) else 0]),
            "M": max([_num(m["id"]) for m in chat] + [src.get("chatSeq", 0) if isinstance(src.get("chatSeq"), int) else 0]),
            "G": max([_num(m["id"]) for m in merges] + [src.get("mergeSeq", 0) if isinstance(src.get("mergeSeq"), int) else 0]),
            "U": src.get("uploadSeq", 0) if isinstance(src.get("uploadSeq"), int) else 0,
            "N": max(max_n, src.get("notifySeq", 0) if isinstance(src.get("notifySeq"), int) else 0),
            "A": 0,
        }
        if _list(src.get("uploads")):
            self.ctx.note("import: uploads has no counterpart in schemaVersion 1 yet; dropped")
        known_top = (
            "questions", "round", "answers", "ideas", "locks", "suggestions", "suggestSeq", "chat", "chatSeq", "leaders", "trusted",
            "people", "secrets", "settings", "title", "requests", "requestSeq", "research", "researchSeq", "removed", "ended",
            "guestKey", "ownerToken", "shareUrl", "goal", "mergeRequests", "mergeSeq", "uploads", "uploadSeq", "prefs",
            "notifications", "notifySeq",
        )  # fmt: skip
        self.unmapped("state", src, known_top)
        created = min([p["joinedAt"] for p in self.people.values()], default=now)
        share = (self.link(src["shareUrl"], "shareUrl") or "").rstrip("/") if src.get("shareUrl") else ""
        for collection, n in sorted(self.dropped.items()):
            if n:
                self.ctx.note(f"import: {n} {collection} records named no known question or person, or had no id; dropped")
        return {
            "pluginVersion": "",
            "writtenBy": "",
            "rev": 0,
            "session": {
                "title": _str(src.get("title"), 80) or "Interview",
                "goal": _str(src.get("goal"), 200),
                "createdAt": created,
                "phase": {"kind": "ended", "at": _ts(ended.get("ts"), now)} if ended else {"kind": "live"},
                "share": {"url": share},
                "guestKey": _str(src.get("guestKey"), 200),
                "settings": settings,
                "seq": seq,
            },
            "people": self.people,
            "credentials": {"owner": {"tokenHash": _sha256(token), "rotatedAt": now}, "secrets": secrets_out},
            "rounds": rounds,
            "questions": questions,
            "cards": cards,
            "votes": votes,
            "reactions": {},
            "locks": locks,
            "suggestions": suggestions,
            "suggestionVotes": suggestion_votes,
            "proposals": proposals,
            "chat": chat,
            "requests": requests,
            "results": results,
            "uploads": [],
            "annotations": [],
            "prefs": prefs,
            "notifications": notifications,
            "mergeRequests": merges,
            "aboutYou": {},
            "log": {"seq": 0, "events": [], "handled": []},
        }

    def rounds(self, questions, cards):
        """Rounds 1..current: earlier ones closed, the current one open. A round the prototype had sent
        to Claude, or Claude was working on, opens again: the event that would carry it to Claude
        does not exist here, so the owner sends it once more."""
        cur = _dict(self.src.get("round"))
        n = cur.get("current", 1)
        n = n if isinstance(n, int) and not isinstance(n, bool) and n >= 1 else 1
        opened = {}  # round -> its earliest card time, the closest the prototype records to when it opened
        for q in questions:
            times = [c["at"] for c in cards.get(q["id"], []) if "at" in c]
            if times:
                opened[q["round"]] = min(opened.get(q["round"], self.now), *times)
        out = []
        for k in range(1, n + 1):
            at = opened.get(k, self.now)
            if k < n:
                nxt = opened.get(k + 1, self.now)
                out.append({"n": k, "openedAt": at, "status": {"kind": "closed", "sentAt": nxt, "ackAt": nxt, "closedAt": nxt, "next": k + 1}})
        status = {"kind": "open"}
        ready = _dict(cur.get("ready"))
        if cur.get("status") in ("sent", "working"):
            self.ctx.note("import: the round the prototype had sent to Claude is open again; send it once more")
        elif ready:
            status["ready"] = {"by": self.by_name(ready.get("by")), "at": _ts(ready.get("ts"), self.now)}
        out.append({"n": n, "openedAt": opened.get(n, self.now), "status": status})
        self.unmapped("round", cur, ("current", "status", "ready"))
        return out


def _v0_to_v1(doc, ctx):
    return _V0(doc, ctx).build()


MIGRATIONS[0] = _v0_to_v1


# -- 1 -> 2: a person holds several reactions on one answer ------------------------------------


def _v1_to_v2(doc, ctx):
    """Each person's one reaction on an answer becomes a list of one."""
    reactions = doc.get("reactions")
    if not isinstance(reactions, dict):
        return dict(doc)  # not a session file: the validator names what is wrong
    return {**doc, "reactions": {qid: {ref: {pid: [r] for pid, r in _dict(by).items()} for ref, by in _dict(refs).items()} for qid, refs in reactions.items()}}


MIGRATIONS[1] = _v1_to_v2


# -- 2 -> 3: a mention points at the person ---------------------------------------------------

MENTION = re.compile(r"<@([A-Za-z0-9_-]{1,32})>")  # how state.json stores a mention: the person's pid
BARE = re.compile(r"(?<![^\W_])@([^\W_]\w*)")  # an "@Word" no name matched
LIMITS = {"note": 200, "excerpt": 140}


def tokenize(text, names, limit=None):
    """text with every "@Name" of `names` ((name, pid) pairs) as <@pid>, longest name first, so "@Sam 2" is not
    also "@Sam". A name stands alone: no letter or digit before its @, none (nor _) after it. Tokens stay as they
    are. With `limit`, text the tokens would make longer than limit comes back unchanged."""
    if "@" not in text or not names:
        return text
    by = {}
    for name, pid in names:
        by.setdefault(name.casefold(), pid)
    alt = "|".join(re.escape(n) for n in sorted(by, key=len, reverse=True))
    pattern = re.compile(rf"(?<![^\W_])@({alt})(?!\w)", re.IGNORECASE)
    parts = MENTION.split(text)  # text, pid, text, pid, ...: only the text between tokens is matched
    for i in range(0, len(parts), 2):
        parts[i] = pattern.sub(lambda m: f"<@{by[m.group(1).casefold()]}>" if m.group(1).casefold() in by else m.group(0), parts[i])
    out = "".join(p if i % 2 == 0 else f"<@{p}>" for i, p in enumerate(parts))
    return text if limit is not None and len(out) > limit else out


def mention_texts(doc):
    """(holder, key) of every text a person wrote that can hold a mention, as state.json keeps it."""
    out = []
    people_cards = [c for lst in _dict(doc.get("cards")).values() for c in _list(lst) if _dict(c).get("kind") == "person"]
    for c in [*people_cards, *(t for lst in _dict(doc.get("cleared")).values() for t in _list(lst))]:
        out += [(c, "text"), *((v, "text") for v in _list(c.get("history")) if isinstance(v, dict))]
    out += [(lk["source"], "text") for lk in _dict(doc.get("locks")).values() if "text" in _dict(_dict(lk).get("source"))]
    for s in (s for lst in _dict(doc.get("suggestions")).values() for s in _list(lst)):
        out += [(s, "text"), (s, "note")]
    out += [(q, "text") for q in _list(doc.get("questions")) if _dict(_dict(q).get("origin")).get("kind") == "host"]
    out += [(r, "text") for key in ("proposals", "chat", "annotations", "requests") for r in _list(doc.get(key))]
    out += [(m["replyTo"], "excerpt") for m in _list(doc.get("chat")) if isinstance(_dict(m).get("replyTo"), dict)]
    out += [(n, "body") for lst in _dict(doc.get("notifications")).values() for n in _list(lst) if _dict(n).get("kind") in ("mention", "reply")]
    return [(h, k) for h, k in out if isinstance(h, dict) and isinstance(h.get(k), str)]


def _v2_to_v3(doc, ctx):
    """Each "@Name" becomes <@pid>: first for a name only one person holds now; then, for a chat message with one
    "@Word" left and one mention notification about it whose recipient it does not name already, Word for that
    recipient, everywhere Word names only them. Text that stays ambiguous keeps its "@Name"."""
    doc = copy.deepcopy(doc)
    people = {p: v["name"] for p, v in _dict(doc.get("people")).items() if isinstance(_dict(v).get("name"), str)}
    held = collections.Counter(n.casefold() for n in people.values())
    names = [(n, p) for p, n in people.items() if held[n.casefold()] == 1]
    told = collections.defaultdict(list)  # chat message -> who its mention notifications went to
    for pid, lst in _dict(doc.get("notifications")).items():
        for n in _list(lst):
            if _dict(n).get("kind") == "mention" and isinstance(n.get("msg"), str):
                told[n["msg"]].append(pid)
    seen = collections.defaultdict(set)  # folded Word -> the pids evidence gives it
    for m in _list(doc.get("chat")):
        if not isinstance(_dict(m).get("text"), str):
            continue
        text = tokenize(m["text"], names)
        left = [w for part in MENTION.split(text)[::2] for w in BARE.findall(part)]
        named = set(MENTION.findall(text))
        to = [p for p in told.get(m.get("id"), []) if p not in named]
        if len(left) == 1 and len(to) == 1:
            seen[left[0].casefold()].add(to[0])
    aliases = [(w, next(iter(pids))) for w, pids in seen.items() if len(pids) == 1 and w not in held]
    changed = 0
    for holder, key in mention_texts(doc):
        out = tokenize(holder[key], names + aliases, LIMITS.get(key, 2000))
        changed += out != holder[key]
        holder[key] = out
    if changed:
        ctx.note(f"mentions: {changed} texts point at the people they name; former names learned from notifications: {len(aliases)}")
    return doc


MIGRATIONS[2] = _v2_to_v3
