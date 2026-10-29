---
bump: patch
---

### Fixed

- The main-run review (`pr-review-main.yml`) runs on the review lanes' credential chain instead of the API key alone: a lane whose key leg credit-stops, is refused with a 401 or 402, or has no key is reviewed on the reviews role's subscription token, and a lane that leg hands off (a limit stop, a credit stop, a 401 or 402, or no token) on `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`. Each leg is its own job holding one credential, writes the same verdict, and stays green when it hands off, so an exhausted key no longer leaves every lane-source pull request unbound.
- The main-run review's diff shows a file moved unchanged as its rename lines alone, so a pull request of pure moves stays under the review's size cap. An edited rename, a move into or out of a lane source and a move that changes the file mode still show whole.
