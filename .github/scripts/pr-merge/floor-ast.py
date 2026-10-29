#!/usr/bin/env python3
"""Judge a pull request's babysit_risk.py against the base copy, for
lane-armed.mjs, by parsing both and never importing or running either.

Usage: python3 -I floor-ast.py <base-file> <head-file>
Exit 0 and no output: the head binds the floor as the base does. Exit 1
with one line: why the head could rebind it. Any other exit refuses too.

A line test cannot see a rebinding spread over lines, aliased
(`g = globals`) or reached by reflection, so the trees are compared:

- The head may reference no reflective or frame name (REFLECTIVE, FRAMES)
  more often than the base does, counted over every Name, every attribute
  and every imported name, so an alias or a split still counts. Nor may it
  hold more dunder names (`__globals__`, `__dict__` and any other) or more
  imports than the base.
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
# Frame and introspection names: a frame's globals are the module's, so
# `sys._getframe().f_globals[...]` rebinds a table as `globals()` would.
FRAMES = frozenset(
    {
        "f_globals",
        "f_locals",
        "f_back",
        "_getframe",
        "currentframe",
        "gi_frame",
        "cr_frame",
        "ctypes",
        "gc",
        "inspect",
    }
)
# Kinds counted whatever the name: any dunder Name or attribute (a
# function's `__globals__` is the module's namespace), and any import.
DUNDER = "a dunder name"
IMPORT = "an import"
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
    """How often `tree` references each reflective or frame name, any dunder
    name (DUNDER) and any import (IMPORT)."""
    found: Counter[str] = Counter()
    names = REFLECTIVE | FRAMES
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            found[IMPORT] += 1
        name = (
            node.id
            if isinstance(node, ast.Name)
            else node.attr
            if isinstance(node, ast.Attribute)
            else None
        )
        if name is not None:
            if len(name) > 4 and name.startswith("__") and name.endswith("__"):
                found[DUNDER] += 1
            if name in names and not (
                isinstance(node, ast.Attribute) and name in NOT_AS_ATTRIBUTE
            ):
                found[name] += 1
        elif isinstance(node, ast.alias):
            for part in (*node.name.split("."), node.asname):
                if part in names:
                    found[part] += 1
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
            return (
                f"it adds {name}"
                if name in (DUNDER, IMPORT)
                else f"it adds a reference to {name}"
            )
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
