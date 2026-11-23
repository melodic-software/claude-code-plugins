---
bump: minor
---

### Added

- `change-shape.py` has a `DOCSTRING-ONLY` verdict (exit 11) for a Python edit whose only difference is removed module, class or function docstrings. It refuses, by token checks over that one file: a token containing `__doc__` or `__dict__`; an identifier `vars`, `help`, `getdoc`, `getmembers`, `__init_subclass__`, `pydoc` or `doctest`; a docstring holding `>>>`; an owner or enclosing class that is decorated or has bases or a metaclass; an owner named anywhere but its own def/class line or directly before `(`; and a removal that leaves a body empty.
- `/code-tidying:remove-comments` applies a non-public Python docstring deletion under `necessary` and `none` when `change-shape.sh` returns `DOCSTRING-ONLY` and a repository search finds no other file naming its owner except as a direct call. Before, every docstring deletion was a proposal.
- Triage traces a thin claim before judging it: a comment saying `IMPORTANT`, `do not remove`, `too risky` or `fine for now`, or a long justification, is checked against the code it names. Under `necessary` it stays only when the keep list applies and the claim holds on a live path; otherwise it is deleted with a reshape flag.
