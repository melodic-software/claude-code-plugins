---
bump: patch
---

### Changed

- The work-items skills, references, README, CONTRACT, schema description and adapter seed READMEs name the tracker binding as the `tracker` key of `<home>/work-items.yaml` (default `docs/conventions/work-items.yaml`) and the role-label remap as `tracker.config.role_labels` (#11880). Only `/work-items:setup` and the seam reader still name the legacy repo-root JSON binding, which the seam reads with a notice until setup migrates it.
- The "no binding found" message from the dispatcher, the jira, gitea and linear seeds and the onboard-adapter `common.sh` template points at `tracker:` in `<home>/work-items.yaml`, or the legacy repo-root JSON binding the seam still reads. A seed already copied into a repository keeps its old message until setup copies it again.
- The conformance runner re-homes its binding as `binding.json` and finds the overlay path through the new `wit_overlay_path` helper in `lib/binding.sh`.
- The eval scaffolds write the binding under `tracker:` in `docs/conventions/work-items.yaml`, and their graders and samples check that file. The GitHub adapter tests' `test-scope` lines name `docs/conventions/work-items.yaml`.
