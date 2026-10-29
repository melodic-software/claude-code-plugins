#!/usr/bin/env python3
"""Judge a pull request's babysit_risk.py against the base copy, for
lane-armed.mjs, by parsing both and never importing or running either.

Usage: python3 -I floor-ast.py <base-file> <head-file>
Exit 0 and no output: the head binds the floor as the base does. Exit 1
with one line: why the head could rebind it. Any other exit refuses too.

A line test cannot see a rebinding spread over lines, aliased
(`g = globals`) or reached by reflection, so the trees are compared:

- The head may reference no reflective name (REFLECTIVE) more often than
  the base does, counted over every Name, every attribute and every
  imported name, so an alias or a split still counts.
- Each floor table (TABLES) is bound exactly once in the head, at module
  level, by a plain or annotated assignment to that one name, with a value
  `ast.literal_eval` accepts. Each set derived from them (DERIVED) is bound
  the same way, to the same expression as in the base. Any other binding of
  either (augmented, deleted, a loop, with, except or match target, an
  import alias, global or nonlocal, a walrus, an argument, a def or class)
  refuses.
"""

from __future__ import annotations

import ast
import sys
from collections import Counter

REFLECTIVE = frozenset(
    {
        "globals",
        "locals",
        "vars",
        "setattr",
        "delattr",
        "getattr",
        "exec",
        "eval",
        "compile",
        "__import__",
        "importlib",
        "__builtins__",
        "builtins",
        "__dict__",
        "__setattr__",
        "__delattr__",
        "modules",
        "__class__",
        "__getattribute__",
    }
)
# `re.compile` is a pattern, not the builtin; the builtin is a Name, and
# `builtins.compile` counts through `builtins`.
NOT_AS_ATTRIBUTE = frozenset({"compile"})
TABLES = ("FLOOR_CLASSES", "LANE_ARM_GATE", "LANE_ARMED", "PERSON_HELD", "COST_PATHS")
DERIVED = (
    "PERSON_CLASSES",
    "LANE_ARMED_FLOOR",
    "HIGH_FLOOR",
    "REVIEW_FLOOR",
    "AUTHOR_REVIEW_CLASSES",
    "_NO_AUTHOR_LIFT",
    "AUTHOR_REVIEW_FLOOR",
    "FLOOR",
)
NAMES = frozenset((*TABLES, *DERIVED))


def reflective(tree: ast.AST) -> Counter[str]:
    found: Counter[str] = Counter()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and node.id in REFLECTIVE:
            found[node.id] += 1
        elif (
            isinstance(node, ast.Attribute)
            and node.attr in REFLECTIVE - NOT_AS_ATTRIBUTE
        ):
            found[node.attr] += 1
        elif isinstance(node, ast.alias):
            for name in (*node.name.split("."), node.asname):
                if name in REFLECTIVE:
                    found[name] += 1
    return found


def bound(node: ast.AST) -> list[str]:
    """Every floor name `node` binds, however."""
    names: list[str] = []

    def targets(target: ast.AST) -> None:
        for each in ast.walk(target):
            if isinstance(each, ast.Name):
                names.append(each.id)

    if isinstance(node, ast.Assign):
        for target in node.targets:
            targets(target)
    elif isinstance(node, (ast.AugAssign, ast.AnnAssign, ast.NamedExpr)):
        targets(node.target)
    elif isinstance(node, ast.Delete):
        for target in node.targets:
            targets(target)
    elif isinstance(node, (ast.For, ast.AsyncFor, ast.comprehension)):
        targets(node.target)
    elif isinstance(node, ast.withitem) and node.optional_vars is not None:
        targets(node.optional_vars)
    elif isinstance(node, ast.alias):
        names.append(node.asname or node.name.split(".")[0])
    elif isinstance(node, (ast.Global, ast.Nonlocal)):
        names.extend(node.names)
    elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        names.append(node.name)
    elif isinstance(node, ast.arg):
        names.append(node.arg)
    elif isinstance(node, ast.ExceptHandler) and node.name:
        names.append(node.name)
    elif isinstance(node, (ast.MatchAs, ast.MatchStar)) and node.name:
        names.append(node.name)
    elif isinstance(node, ast.MatchMapping) and node.rest:
        names.append(node.rest)
    return [name for name in names if name in NAMES]


def bindings(tree: ast.Module) -> dict[str, list[ast.AST]]:
    found: dict[str, list[ast.AST]] = {name: [] for name in NAMES}
    for node in ast.walk(tree):
        for name in bound(node):
            found[name].append(node)
    return found


def value(tree: ast.Module, name: str) -> tuple[ast.expr | None, str | None]:
    """The value of `name`'s one module-level plain binding, or why not."""
    nodes = bindings(tree)[name]
    if len(nodes) != 1:
        return None, f"{name} is bound {len(nodes)} times"
    node = nodes[0]
    plain = (
        isinstance(node, ast.Assign)
        and len(node.targets) == 1
        and isinstance(node.targets[0], ast.Name)
    ) or (
        isinstance(node, ast.AnnAssign)
        and isinstance(node.target, ast.Name)
        and node.value is not None
    )
    if not plain or node not in tree.body:
        return None, f"{name} is not bound by one module-level assignment"
    return node.value, None


def judge(base_text: str, head_text: str) -> str | None:
    try:
        base, head = ast.parse(base_text), ast.parse(head_text)
    except (SyntaxError, ValueError) as error:
        return f"a copy does not parse: {error.__class__.__name__}"
    before, after = reflective(base), reflective(head)
    for name in sorted(after):
        if after[name] > before[name]:
            return f"it adds a reference to {name}"
    for name in NAMES:
        old, why = value(base, name)
        if why:
            return f"the base copy: {why}"
        new, why = value(head, name)
        if why:
            return why
        if name in TABLES:
            try:
                ast.literal_eval(new)
            except ValueError:
                return f"{name} is not a literal"
        elif ast.dump(new) != ast.dump(old):
            return f"it changes how {name} is derived"
    return None


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: floor-ast.py <base-file> <head-file>")
        return 2
    with (
        open(argv[0], encoding="utf-8") as base,
        open(argv[1], encoding="utf-8") as head,
    ):
        why = judge(base.read(), head.read())
    if why:
        print(why)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
