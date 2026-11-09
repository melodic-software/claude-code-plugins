#!/usr/bin/env bash
# Writes the Larkspur tool library: a Python catalogue with passing unittest tests, and a project
# glossary at the place $1 names: root (GLOSSARY.md), docs (docs/glossary.md) or none.
# The code and tests name neither the glossary's canonical terms for lending nor their rejected
# synonyms, so any such name in the finished tests came from the run.
set -euo pipefail
place="${1:?usage: tool-library.sh root|docs|none}"

mkdir -p tests
cat >README.md <<'MD'
# Larkspur Tool Library

The catalogue and front desk of a neighborhood tool library.
MD

cat >tool_library.py <<'PY'
from dataclasses import dataclass, field


@dataclass
class Tool:
    tool_id: str
    name: str


@dataclass
class Member:
    card_number: str
    name: str


@dataclass
class Library:
    tools: dict = field(default_factory=dict)
    members: dict = field(default_factory=dict)

    def add_tool(self, tool):
        self.tools[tool.tool_id] = tool

    def enroll(self, member):
        self.members[member.card_number] = member

    def tool(self, tool_id):
        return self.tools[tool_id]
PY

touch tests/__init__.py
cat >tests/test_tool_library.py <<'PY'
import unittest

from tool_library import Library, Member, Tool


class CatalogueTest(unittest.TestCase):
    def test_added_tool_is_found_by_id(self):
        library = Library()
        library.add_tool(Tool("T-7", "Orbital sander"))
        self.assertEqual(library.tool("T-7").name, "Orbital sander")

    def test_enrolled_member_is_kept_by_card_number(self):
        library = Library()
        library.enroll(Member("C-102", "Ada"))
        self.assertEqual(library.members["C-102"].name, "Ada")


if __name__ == "__main__":
    unittest.main()
PY

glossary() {
  cat <<'MD'
# Larkspur Tool Library glossary

Words the front desk uses.

**Member**

A person holding a current library card.

Avoid: customer, user

**Loan**

One tool in a member's hands for a fixed period, from the moment the desk hands it over until it
comes back to the desk. A loan records the tool, the member and the due date.

Avoid: checkout, rental, booking

**Due date**

The last day a loan may run before it is overdue.

Avoid: deadline, return-by date
MD
}

case "$place" in
root) glossary >GLOSSARY.md ;;
docs)
  mkdir -p docs
  glossary >docs/glossary.md
  ;;
none) ;;
*)
  echo "tool-library.sh: unknown place '$place' (root|docs|none)" >&2
  exit 2
  ;;
esac
