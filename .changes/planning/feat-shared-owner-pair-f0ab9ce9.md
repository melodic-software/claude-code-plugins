---
bump: minor
---

### Added

- The shared interview host can sign in on another device without the owner link: Sign in on another device in the owner's menu shows a one-time code and its QR code, good once for 2 minutes, which a phone scans or types in the join dialog to get its own host sign-in. Signed-in devices lists them, each with Sign out, and a new owner link signs all of them out.

### Security

- The owner link no longer leaves the device that opened it: the owner's Use on another device link is replaced by the one-time code, and making codes or a new owner link works only with the owner link itself. Codes are hashed in memory, throttled per address, and an address with 5 wrong tries is shut out of the live code without ending it for anyone else; device credentials are stored hashed.
