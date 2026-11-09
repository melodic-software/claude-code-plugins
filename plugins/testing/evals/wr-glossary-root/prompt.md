This is the catalogue code for our tool library: `Library` in `tool_library.py`, with its tests in
`tests/test_tool_library.py`. Run the tests with `python3 -m unittest discover -s tests -t .`. Use
the `testing:write` skill if you have it.

Members want to check tools out and bring them back. Add that to `Library`, tests first, with the
tests in `tests/test_tool_library.py`:

1. Checking out an available tool for a member records who has it and a due date 14 days after the
   day it went out.
2. A tool that is already out cannot go out again: raise `ValueError`.
3. Bringing a tool back makes it available again.
4. An unknown card number cannot take a tool out: raise `KeyError`.

The work is done when each point has a test and the whole suite passes.
