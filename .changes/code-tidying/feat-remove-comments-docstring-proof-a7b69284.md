---
bump: minor
---

### Added

- `change-shape.py` has a `DOCSTRING-ONLY` verdict (exit 11) for a Python edit whose only difference is removed module, class or function docstrings. It refuses a file that can read a docstring at run time (`__doc__`, `getdoc`, `pydoc`, `doctest`), a docstring holding `>>>` examples, a decorated owner or a class with bases, and a removal that leaves a body empty.
- `/code-tidying:remove-comments` applies a non-public Python docstring deletion under `necessary` and `none` when `change-shape.sh` returns `DOCSTRING-ONLY` and a repository search finds no `__doc__` or `getdoc` reader of its owner in another file. Before, every docstring deletion was a proposal.
- Triage traces a thin claim before judging it: a comment saying `IMPORTANT`, `do not remove`, `too risky` or `fine for now`, or a long justification, is checked against the code it names. Under `necessary` it stays only when the keep list applies and the claim holds on a live path; otherwise it is deleted with a reshape flag.
