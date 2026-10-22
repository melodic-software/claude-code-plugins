---
bump: minor
---

### Added

- The pr-merge lane adopts an idle owner pull request (owner decision Q22): one an account in
  `adoption.owner-ids` (none when absent) opened, matched by account id, not a draft,
  whose update and head commit are both at least `adoption.idle-hours` old (read at main, 24
  when absent; 1 to 720), and with no hold label or body hold. The lane's own merge-queue entry
  at the current head keeps adoption though its pin comment refreshed the update time, until
  anyone else comments or reviews after the pin.
  pr-merge.yml lists those accounts' PRs. The decision records it as `eligibility.adoption`;
  every other gate applies unchanged.

### Changed

- The pr-merge verifier gate counts a linked issue a trusted human wrote, and last edited if ever,
  as a trusted spec even when that human opened the pull request, so an adopted owner pull
  request whose closing issue the owner wrote no longer refuses `verify:untrusted-spec`. A spec
  by the lanes App, any other Bot or App, or an untrusted account still refuses.
