---
bump: patch
---

### Fixed

- The pr-merge lane's verdict gate (`babysit_verify_evidence.py`) now lets a pass supersede a FAIL at the same head after a trusted person fixed the pull request's body. Before, a pass that recorded the same linked issues as the FAIL never superseded it, so the gate refused the head as `verify:fail` even after pr-verify judged the fixed body and passed. Now such a pass supersedes the FAIL when the pass run was created after every FAIL there and, from the last FAIL's creation to the pass run's completion, at least one body edit falls and every body edit and issue link change was by a person on the trusted-actor list. The superseded FAIL no longer refuses `verify:fail` and still counts toward `merge.max-verify-fails`. A Bot's edit, a link change alone, or a read that fails keeps the refusal. This is the same rule resolve-pr.mjs uses.
