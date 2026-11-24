---
bump: patch
---

### Fixed

- `change-shape.py` no longer holds every function docstring in a file that reads a bare `__doc__` name, such as `argparse.ArgumentParser(description=__doc__)`: that name refuses removal of the module docstring only, and `f.__doc__` refuses removal of f's. `__doc__` on any other expression (`obj.__doc__` for a name owning no removed docstring, `x.f.__doc__`, `f().__doc__`, a string), `__dict__`, and the reader identifiers still return CODE-CHANGED for the whole file.
