---
bump: patch
---

### Fixed

- The main-run review (`pr-review-main.yml`) runs on the review lanes' credential chain instead of the API key alone: a lane whose key leg credit-stops, is refused with a 401 or 402, or has no key is reviewed on the reviews role's subscription token, and a lane that leg hands off (a limit stop, a credit stop, a 401 or 402, or no token) on `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`. Each leg is its own job holding one credential, writes the same verdict, and stays green when it hands off, so an exhausted key no longer leaves every lane-source pull request unbound.
- When the main-run review's whole-file diff is over its size cap, a file moved unchanged shows as its rename lines alone, so a pull request of pure moves fits. A move into or out of a lane source, a mode change, a moved symlink or submodule, a move that may run or load (an executable, a skills, agents, commands or hooks path, or a file a tool reads by name), and a move an added line names still show whole, and the reviewer is told a rename-only entry is unseen.
