"""A stdlib subset of JSON Schema 2020-12 for the surface's shipped schemas in schema/.

Keywords: type, enum, required, properties, additionalProperties (false or a schema), items,
minItems, maxItems, oneOf, anyOf, allOf, and $ref to `#/$defs/<name>` or to another shipped schema by $id.
Anything else in a schema is ignored. `first_error` returns the first failure as
`<path>: <message>` (path in `$.a[0].b` form), or None when the instance is valid.
"""

import json
from pathlib import Path

SCHEMA_DIR = Path(__file__).resolve().parent / "schema"
TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}
_REGISTRY = {}


def registry():
    """Every shipped schema, keyed by its $id; loaded once."""
    if not _REGISTRY:
        for path in sorted(SCHEMA_DIR.glob("*.schema.json")):
            s = json.loads(path.read_text(encoding="utf-8"))
            _REGISTRY[s["$id"]] = s
    return _REGISTRY


def load(name):
    """The shipped schema `schema/<name>.schema.json`."""
    for s in registry().values():
        if s["$id"].rsplit("/", 1)[-1] == name:
            return s
    raise KeyError(name)


def _resolve(ref, root):
    base, _, frag = ref.partition("#")
    doc = registry()[base] if base else root
    node = doc
    for part in [p for p in frag.split("/") if p]:
        node = node[part]
    return node, doc


def first_error(inst, schema, path="$", root=None):
    root = root if root is not None else schema
    if "$ref" in schema:
        target, doc = _resolve(schema["$ref"], root)
        err = first_error(inst, target, path, doc)
        if err:
            return err
    types = schema.get("type")
    if types is not None:
        names = [types] if isinstance(types, str) else types
        if not any(TYPES[t](inst) for t in names):
            return f"{path}: expected {' or '.join(names)}, got {type(inst).__name__}"
    if "enum" in schema and inst not in schema["enum"]:
        return f"{path}: {inst!r} is not one of {schema['enum']}"
    if isinstance(inst, dict):
        for key in schema.get("required", []):
            if key not in inst:
                return f"{path}: missing required {key!r}"
        props = schema.get("properties", {})
        extra = schema.get("additionalProperties", True)
        for key, val in inst.items():
            sub = f"{path}.{key}"
            if key in props:
                err = first_error(val, props[key], sub, root)
            elif extra is False:
                err = f"{path}: unexpected property {key!r}"
            elif isinstance(extra, dict):
                err = first_error(val, extra, sub, root)
            else:
                err = None
            if err:
                return err
    if isinstance(inst, list):
        if len(inst) < schema.get("minItems", 0):
            return f"{path}: needs at least {schema['minItems']} items, has {len(inst)}"
        if len(inst) > schema.get("maxItems", len(inst)):
            return f"{path}: allows at most {schema['maxItems']} items, has {len(inst)}"
        if "items" in schema:
            for i, val in enumerate(inst):
                err = first_error(val, schema["items"], f"{path}[{i}]", root)
                if err:
                    return err
    for sub in schema.get("allOf", []):
        err = first_error(inst, sub, path, root)
        if err:
            return err
    if "anyOf" in schema:
        errs = [first_error(inst, sub, path, root) for sub in schema["anyOf"]]
        if all(errs):
            return f"{path}: matches none of anyOf ({'; '.join(errs)})"
    if "oneOf" in schema:
        errs = [first_error(inst, sub, path, root) for sub in schema["oneOf"]]
        hits = errs.count(None)
        if hits != 1:
            why = (
                "; ".join(e for e in errs if e)
                if hits == 0
                else f"{hits} branches match"
            )
            return f"{path}: must match exactly one of oneOf ({why})"
    return None
