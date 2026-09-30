"""Dynamic overlap discovery: score every native surface against every component.

Seeded pairs only find what someone already thought of. Discovery scores each
(native surface, repo component) pair from name and description tokens, so a
surface a new Claude Code release adds is compared against the whole fleet
without anyone hand-seeding it. It proposes candidates; it never decides one.

Scoring, standard library only:

  score = NAME_WEIGHT * name_score + (1 - NAME_WEIGHT) * text_score,
          times SINGLE_TOKEN_FACTOR when a described surface shares one token

  name_score  IDF-weighted share of the native name's tokens (or one alias's,
              whichever covers best) found in the component's skill or agent
              name; a token found only in its plugin name earns
              PLUGIN_NAME_CREDIT of its weight.
  text_score  geometric mean of the TF-IDF cosine between the two weighted
              bags and the share of the native bag the component covers
              (native name x3, aliases x2, description and argument hint x1;
              component name x3, plugin name x1, description x1). Coverage
              keeps a long component description from diluting a one-line
              native one; cosine keeps a long description from matching
              everything.

Tokens are lower-cased, stoplisted, lightly stemmed, split off an `auto`/`sub`
prefix, and a few abbreviations are expanded (`pr` -> pull request), so
`verify` meets `verification` and `subagent` meets `agent`.
"""

from __future__ import annotations

import math
import re
from collections import Counter
from dataclasses import dataclass, field
from typing import Any, Iterable

DEFAULT_THRESHOLD = 0.30
DEFAULT_TOP_K = 3
NAME_WEIGHT = 0.5
PLUGIN_NAME_CREDIT = 0.5
SINGLE_TOKEN_FACTOR = 0.7

STOPWORDS = frozenset(
    """
    a about after all also an and any are as at be been before but by can
    could do does doing each either every for from get gets give given go
    has have how i if in into is it its it's just let like make makes may me
    more most my need no none not now of off on one only or other our out
    over own per please same see set should show so some such than that the
    their them then there these they this those through to too under up us
    use used uses using very via want was we what when where whether which
    while who why will with without would yet you your
    claude code skill skills plugin plugins built builtin bundled native
    command commands invoke invoked invocation user users model setup
    """.split()
)
ABBREVIATIONS: dict[str, tuple[str, ...]] = {
    "pr": ("pull", "request"),
    "prs": ("pull", "request"),
    "repo": ("repository",),
    "repos": ("repository",),
}
MORPH_PREFIXES = ("auto", "sub")
SUFFIXES = (
    "ications",
    "ication",
    "ations",
    "ation",
    "ings",
    "ing",
    "ies",
    "ied",
    "ers",
    "er",
    "es",
    "ed",
    "s",
    "y",
    "e",
)
TOKEN_RE = re.compile(r"[a-z0-9]+")


def stem(word: str) -> str:
    """Strip one common suffix, keeping a stem of at least three letters.

    A bare trailing `e` needs a five-letter stem and `es` a sibilant before it,
    so `states` meets `state` and never `stats`.
    """
    for suffix in SUFFIXES:
        if suffix == "es" and not word[:-2].endswith(("s", "x", "z", "ch", "sh")):
            continue
        floor = 5 if suffix == "e" else 3
        if word.endswith(suffix) and len(word) - len(suffix) >= floor:
            return word[: -len(suffix)]
    return word


def tokenize(text: str) -> list[str]:
    tokens: list[str] = []
    for raw in TOKEN_RE.findall((text or "").lower()):
        if len(raw) < 2 or raw.isdigit() or raw in STOPWORDS:
            continue
        words = [raw, *ABBREVIATIONS.get(raw, ())]
        for prefix in MORPH_PREFIXES:
            if raw.startswith(prefix) and len(raw) - len(prefix) >= 4:
                words.append(raw[len(prefix) :])
        tokens.extend(stem(w) for w in words if w not in STOPWORDS)
    return tokens


def _bag(*parts: tuple[str, float]) -> Counter:
    bag: Counter = Counter()
    for text, weight in parts:
        for token in tokenize(text):
            bag[token] += weight
    return bag


@dataclass
class Surface:
    """One native surface: its identity, its text, and its name token sets."""

    name: str
    klass: str
    lane: str
    registrations: list[dict[str, Any]]
    bag: Counter = field(default_factory=Counter)
    name_sets: list[set[str]] = field(default_factory=list)
    described: bool = False

    @classmethod
    def build(
        cls, name: str, klass: str, lane: str, registrations: list[dict[str, Any]]
    ) -> "Surface":
        aliases = sorted(
            {
                a
                for r in registrations
                for a in (r.get("aliases") or [])
                if isinstance(a, str)
            }
        )
        text = " ".join(
            str(r.get(key) or "")
            for r in registrations
            for key in ("description", "argument_hint")
        )
        bag = _bag((name, 3.0), (" ".join(aliases), 2.0), (text, 1.0))
        name_sets = [s for s in (set(tokenize(n)) for n in [name, *aliases]) if s]
        return cls(
            name, klass, lane, registrations, bag, name_sets, bool(tokenize(text))
        )


@dataclass
class Component:
    plugin: str
    name: str
    kind: str
    bag: Counter
    name_tokens: set[str]
    plugin_tokens: set[str]
    description: str = ""

    @classmethod
    def build(cls, plugin: str, name: str, kind: str, description: str) -> "Component":
        bag = _bag((name, 3.0), (plugin, 1.0), (description, 1.0))
        return cls(
            plugin,
            name,
            kind,
            bag,
            set(tokenize(name)),
            set(tokenize(plugin)),
            description,
        )


def idf_table(bags: Iterable[Counter]) -> dict[str, float]:
    bags = list(bags)
    df: Counter = Counter()
    for bag in bags:
        df.update(bag.keys())
    total = len(bags)
    return {t: math.log((1 + total) / (1 + n)) + 1.0 for t, n in df.items()}


def _vector(bag: Counter, idf: dict[str, float]) -> dict[str, float]:
    return {t: (1 + math.log(w)) * idf.get(t, 1.0) for t, w in bag.items() if w > 0}


def _norm(vec: dict[str, float]) -> float:
    return math.sqrt(sum(v * v for v in vec.values())) or 1.0


def score_pair(
    surface: Surface,
    component: Component,
    idf: dict[str, float],
    vectors: dict[int, tuple[dict[str, float], float]],
) -> tuple[float, list[str]]:
    """(score, matched tokens ordered by contribution) for one pair."""
    sv, sn = vectors[id(surface)]
    cv, cn = vectors[id(component)]
    shared = set(sv) & set(cv)
    cosine = sum(sv[t] * cv[t] for t in shared) / (sn * cn)
    coverage = sum(sv[t] ** 2 for t in shared) / (sn * sn)
    text_score = math.sqrt(cosine * coverage)
    name_score = 0.0
    for names in surface.name_sets:
        total = sum(idf.get(t, 1.0) for t in names)
        hit = sum(
            idf.get(t, 1.0)
            * (1.0 if t in component.name_tokens else PLUGIN_NAME_CREDIT)
            for t in names & (component.name_tokens | component.plugin_tokens)
        )
        name_score = max(name_score, hit / total if total else 0.0)
    score = NAME_WEIGHT * name_score + (1 - NAME_WEIGHT) * text_score
    if len(shared) == 1 and surface.described:
        score *= SINGLE_TOKEN_FACTOR
    matched = sorted(shared, key=lambda t: (-sv[t] * cv[t], t))
    return round(score, 4), matched


Scored = tuple[Surface, Component, float, list[str]]


def score_all(surfaces: list[Surface], components: list[Component]) -> list[Scored]:
    """Every pair sharing at least one token, best first per native surface."""
    idf = idf_table([s.bag for s in surfaces] + [c.bag for c in components])
    vectors: dict[int, tuple[dict[str, float], float]] = {}
    for item in [*surfaces, *components]:
        vec = _vector(item.bag, idf)
        vectors[id(item)] = (vec, _norm(vec))
    found: list[Scored] = []
    for surface in surfaces:
        scored = []
        for component in components:
            score, matched = score_pair(surface, component, idf, vectors)
            if matched:
                scored.append((surface, component, score, matched))
        scored.sort(key=lambda item: (-item[2], item[1].plugin, item[1].name))
        found.extend(scored)
    return found


def select(scored: list[Scored], *, threshold: float, top_k: int) -> list[Scored]:
    """The pairs at or over the threshold, at most top_k per native surface."""
    kept: list[Scored] = []
    per_surface: Counter = Counter()
    for item in scored:
        if item[2] >= threshold and per_surface[id(item[0])] < top_k:
            per_surface[id(item[0])] += 1
            kept.append(item)
    return kept


def discover(
    surfaces: list[Surface],
    components: list[Component],
    *,
    threshold: float = DEFAULT_THRESHOLD,
    top_k: int = DEFAULT_TOP_K,
) -> list[Scored]:
    """Every pair at or over the threshold, at most top_k per native surface."""
    return select(score_all(surfaces, components), threshold=threshold, top_k=top_k)


def invocability(registrations: list[dict[str, Any]]) -> dict[str, Any]:
    """Who can invoke a surface, from the fields its registrations carry.

    `model_invocable` wins; an older extraction's `disable_model_invocation`
    stands in for it; anything else is unknown (None). Registrations that
    disagree (a name collision) are unknown too: the name alone cannot say
    which registration a caller would reach.
    """

    def agreed(values: list[Any]) -> Any:
        return values[0] if values and all(v == values[0] for v in values) else None

    models: list[Any] = []
    users: list[Any] = []
    hints: list[Any] = []
    for entry in registrations:
        if isinstance(entry.get("model_invocable"), bool):
            models.append(entry["model_invocable"])
        elif isinstance(entry.get("disable_model_invocation"), bool):
            models.append(not entry["disable_model_invocation"])
        else:
            models.append(None)
        users.append(
            entry.get("user_invocable")
            if isinstance(entry.get("user_invocable"), bool)
            else None
        )
        hint = entry.get("argument_hint")
        hints.append(hint if isinstance(hint, str) and hint else None)
    model, user = agreed(models), agreed(users)
    invocable_by = {
        (True, True): "model+user",
        (False, True): "user-only",
        (True, False): "model-only",
    }.get((model, user), "unknown")
    return {
        "model_invocable": model,
        "user_invocable": user,
        "argument_hint": agreed(hints),
        "invocable_by": invocable_by,
    }


def recommended_integration(klass: str, invocable_by: str) -> str | None:
    """A recommendation label for the human, never a verdict or a store value.

    A user-only surface can only be suggested (ours tells the model to suggest
    the user type it); a model-invocable one can be routed to or wrapped,
    except a class the store never lets take `wrap`.
    """
    if invocable_by == "user-only":
        return "suggest"
    if invocable_by in ("model+user", "model-only"):
        return "route" if klass in ROUTE_ONLY_CLASSES else "route-or-wrap"
    return None


# Classes whose store rows take `route` or `suggest`, never `wrap`: a Native
# step invokes through the Skill tool, and neither is a skill.
ROUTE_ONLY_CLASSES = frozenset({"builtin-command", "bundled-workflow"})
