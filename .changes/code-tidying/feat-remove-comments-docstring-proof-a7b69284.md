---
bump: minor
---

### Added

- `change-shape.py` has a `DOCSTRING-ONLY` verdict (exit 11) for a Python edit whose only difference is removed docstrings of the module or of functions defined outside any class (top level or nested in a function); a class or method docstring removal reads CODE-CHANGED. It also refuses, by token checks over that one file: a token containing `__doc__` or `__dict__`; an identifier `vars`, `help`, `getdoc`, `getmembers`, `__init_subclass__`, `pydoc` or `doctest`; a docstring holding `>>>`; a decorated function; a function named anywhere but its own def line or directly before `(`; and a removal that leaves a body empty.
- `/code-tidying:remove-comments` applies a non-public module or class-free function docstring deletion under `necessary` and `none` when `change-shape.sh` returns `DOCSTRING-ONLY` and a repository search finds no other file naming the function except as a direct call. Class and method docstring deletions stay proposals, as every docstring deletion was before.
- Triage traces a thin claim before judging it: a comment saying `IMPORTANT`, `do not remove`, `too risky` or `fine for now`, or a long justification, is checked against the code it names. Under `necessary` it stays only when the keep list applies and the claim holds on a live path; otherwise it is deleted with a reshape flag.
